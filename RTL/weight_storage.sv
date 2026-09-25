module weight_storage
  import complex_pkg::*;
#(
  parameter int NUM_ROWS = 4,
  parameter int NUM_COLS = 4
)
(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       cfg_wr_en,
  input  logic [3:0] cfg_wr_addr,   
  input  complex_t   cfg_wr_data,
  output logic       cfg_wr_ready, 
  input  logic       pipeline_busy,
  output complex_t   weight_matrix [NUM_ROWS][NUM_COLS]
);

  assign cfg_wr_ready = !pipeline_busy;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < NUM_ROWS; r++) begin
        for (int c = 0; c < NUM_COLS; c++) begin
          weight_matrix[r][c] <= (r == c) ? '{real_part: 16'sd32767, imag_part: 16'sd0} : '{real_part: 16'sd0,     imag_part: 16'sd0};
        end
      end
    end else if (cfg_wr_en && cfg_wr_ready) begin
      weight_matrix[cfg_wr_addr[3:2]][cfg_wr_addr[1:0]] <= cfg_wr_data;
    end
  end

endmodule : weight_storage
