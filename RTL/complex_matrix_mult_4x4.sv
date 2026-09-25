module complex_matrix_mult_4x4
  import complex_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic       s_axis_tvalid,
  output logic       s_axis_tready,
  input  complex_t   antenna_in [NUM_ELEM],

  output logic       m_axis_tvalid,
  input  logic       m_axis_tready,
  output complex_t   beamformed_out [NUM_ELEM],

  input  complex_t   weight_matrix [NUM_ELEM][NUM_ELEM],

  output logic pipeline_busy
);

  localparam int PIPE_LATENCY = 3; // cycles, see header comment (corrected from 4)

  logic advance;
  assign advance      = !(m_axis_tvalid && !m_axis_tready);
  assign s_axis_tready = rst_n && advance;

  logic input_fire;
  assign input_fire = s_axis_tvalid && s_axis_tready;

  complex_t x_reg [NUM_ELEM];
  logic     valid0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid0 <= 1'b0;
      x_reg  <= '{default: '0};
    end 
    else if (advance) begin
      valid0 <= input_fire;
        if (input_fire) 
          x_reg <= antenna_in;
    end
  end

  complex_prod_t products     [NUM_ELEM][NUM_ELEM]; // combinational
  complex_prod_t products_reg [NUM_ELEM][NUM_ELEM]; // pipeline register
  logic          valid1;

  genvar r, c;
  generate
    for (r = 0; r < NUM_ELEM; r++) begin : g_row
      for (c = 0; c < NUM_ELEM; c++) begin : g_col
        complex_mult u_mult (.a(x_reg[c]),.b(weight_matrix[r][c]),.p(products[r][c]));
      end
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid1       <= 1'b0;
      products_reg <= '{default: '0};
    end else if (advance) begin
      valid1        <= valid0;
      products_reg  <= products;
    end
  end

  complex_stage1_t partial_a_arr [NUM_ELEM]; // combinational
  complex_stage1_t partial_b_arr [NUM_ELEM]; // combinational
  complex_stage1_t partial_a_reg [NUM_ELEM]; // pipeline register
  complex_stage1_t partial_b_reg [NUM_ELEM]; // pipeline register
  logic             valid2;

  generate
    for (r = 0; r < NUM_ELEM; r++) begin : g_stageA
      complex_add #(.IN_WIDTH(PROD_WIDTH), .OUT_WIDTH(STAGE1_WIDTH)) u_add_a (
        .a_real(products_reg[r][0].real_part), .a_imag(products_reg[r][0].imag_part),
        .b_real(products_reg[r][1].real_part), .b_imag(products_reg[r][1].imag_part),
        .sum_real(partial_a_arr[r].real_part), .sum_imag(partial_a_arr[r].imag_part)
      );
      complex_add #(.IN_WIDTH(PROD_WIDTH), .OUT_WIDTH(STAGE1_WIDTH)) u_add_b (
        .a_real(products_reg[r][2].real_part), .a_imag(products_reg[r][2].imag_part),
        .b_real(products_reg[r][3].real_part), .b_imag(products_reg[r][3].imag_part),
        .sum_real(partial_b_arr[r].real_part), .sum_imag(partial_b_arr[r].imag_part)
      );
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid2        <= 1'b0;
      partial_a_reg <= '{default: '0};
      partial_b_reg <= '{default: '0};
    end else if (advance) begin
      valid2        <= valid1;
      partial_a_reg <= partial_a_arr;
      partial_b_reg <= partial_b_arr;
    end
  end

  complex_acc_t acc_arr [NUM_ELEM]; // combinational, full-precision sum

  function automatic logic signed [DATA_WIDTH-1:0] saturate
      (input logic signed [ACC_WIDTH-1:0] val);
    localparam logic signed [DATA_WIDTH-1:0] MAX_POS = {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam logic signed [DATA_WIDTH-1:0] MAX_NEG = {1'b1, {(DATA_WIDTH-1){1'b0}}};
    logic signed [ACC_WIDTH-1:0] max_ext, min_ext;
    begin
      max_ext = {{(ACC_WIDTH-DATA_WIDTH){MAX_POS[DATA_WIDTH-1]}}, MAX_POS};
      min_ext = {{(ACC_WIDTH-DATA_WIDTH){MAX_NEG[DATA_WIDTH-1]}}, MAX_NEG};
      if (val > max_ext)
        saturate = MAX_POS;
      else if (val < min_ext)
        saturate = MAX_NEG;
      else
        saturate = val[DATA_WIDTH-1:0];
    end
  endfunction

  generate
    for (r = 0; r < NUM_ELEM; r++) begin : g_stageB
      complex_add #(.IN_WIDTH(STAGE1_WIDTH), .OUT_WIDTH(ACC_WIDTH)) u_add_final (
        .a_real(partial_a_reg[r].real_part), .a_imag(partial_a_reg[r].imag_part),
        .b_real(partial_b_reg[r].real_part), .b_imag(partial_b_reg[r].imag_part),
        .sum_real(acc_arr[r].real_part), .sum_imag(acc_arr[r].imag_part)
      );
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tvalid  <= 1'b0;
      beamformed_out <= '{default: '0};
    end else if (advance) begin
      m_axis_tvalid <= valid2;
      for (int i = 0; i < NUM_ELEM; i++) begin
        beamformed_out[i].real_part <= saturate(acc_arr[i].real_part);
        beamformed_out[i].imag_part <= saturate(acc_arr[i].imag_part);
      end
    end
  end

  assign pipeline_busy = valid0 || valid1 || valid2 || m_axis_tvalid;

  property p_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (m_axis_tvalid && !m_axis_tready) |=> ($stable(beamformed_out) && m_axis_tvalid);
  endproperty
  
  a_stable_when_stalled: assert property (p_stable_when_stalled)
    else $error("[ASSERT] m_axis output changed or TVALID dropped while stalled");

  a_reset_clears_valid: assert property ( @(posedge clk) !rst_n |-> !m_axis_tvalid)
   else $error("[ASSERT] m_axis_tvalid asserted during reset");

  a_reset_clears_tready: assert property ( @(posedge clk) !rst_n |-> !s_axis_tready)
     else $error("[ASSERT] s_axis_tready asserted during reset");
 
endmodule : complex_matrix_mult_4x4
