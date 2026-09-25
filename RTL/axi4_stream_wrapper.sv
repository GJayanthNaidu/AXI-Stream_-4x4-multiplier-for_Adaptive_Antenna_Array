module axi4_stream_wrapper
  import complex_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic                          s_axis_tvalid,
  output logic                          s_axis_tready,
  input  logic [S_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,

  output logic                          m_axis_tvalid,
  input  logic                          m_axis_tready,
  output logic [M_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,

  input  logic                          cfg_wr_en,
  input  logic [3:0]                    cfg_wr_addr,
  input  complex_t                      cfg_wr_data,
  output logic                          cfg_wr_ready
);

  localparam int SAMPLE_WIDTH = 2*DATA_WIDTH; // one complex sample slot

  complex_t antenna_in     [NUM_ELEM];
  complex_t beamformed_out [NUM_ELEM];
  complex_t weight_matrix  [NUM_ELEM][NUM_ELEM];
  logic     pipeline_busy;

  generate
    genvar i;
    for (i = 0; i < NUM_ELEM; i++) begin : g_pack
      assign antenna_in[i].real_part = s_axis_tdata[i*SAMPLE_WIDTH             +: DATA_WIDTH];
      assign antenna_in[i].imag_part = s_axis_tdata[i*SAMPLE_WIDTH+DATA_WIDTH  +: DATA_WIDTH];

      assign m_axis_tdata[i*SAMPLE_WIDTH             +: DATA_WIDTH] = beamformed_out[i].real_part;
      assign m_axis_tdata[i*SAMPLE_WIDTH+DATA_WIDTH  +: DATA_WIDTH] = beamformed_out[i].imag_part;
    end
  endgenerate

  weight_storage #(
    .NUM_ROWS(NUM_ELEM),
    .NUM_COLS(NUM_ELEM)
  ) u_weights 
  (
    .clk           (clk),
    .rst_n         (rst_n),
    .cfg_wr_en     (cfg_wr_en),
    .cfg_wr_addr   (cfg_wr_addr),
    .cfg_wr_data   (cfg_wr_data),
    .cfg_wr_ready  (cfg_wr_ready),
    .pipeline_busy (pipeline_busy),
    .weight_matrix (weight_matrix)
  );

  complex_matrix_mult_4x4 u_core (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axis_tvalid  (s_axis_tvalid),
    .s_axis_tready  (s_axis_tready),
    .antenna_in     (antenna_in),
    .m_axis_tvalid  (m_axis_tvalid),
    .m_axis_tready  (m_axis_tready),
    .beamformed_out (beamformed_out),
    .weight_matrix  (weight_matrix),
    .pipeline_busy  (pipeline_busy)
  );

endmodule : axi4_stream_wrapper
