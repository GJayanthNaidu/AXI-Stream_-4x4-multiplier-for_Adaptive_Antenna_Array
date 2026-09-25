module complex_add #(
  parameter int IN_WIDTH  = 16,
  parameter int OUT_WIDTH = IN_WIDTH + 1
)
(
  input  logic signed [IN_WIDTH-1:0]  a_real, a_imag,
  input  logic signed [IN_WIDTH-1:0]  b_real, b_imag,
  output logic signed [OUT_WIDTH-1:0] sum_real, sum_imag
);

  initial begin
    assert (OUT_WIDTH >= IN_WIDTH + 1)
      else $error("complex_add: OUT_WIDTH must be >= IN_WIDTH+1 to guarantee no overflow (IN_WIDTH=%0d, OUT_WIDTH=%0d)",
                  IN_WIDTH, OUT_WIDTH);
  end

  localparam int EXT = OUT_WIDTH - IN_WIDTH;

  always_comb begin
    sum_real = {{EXT{a_real[IN_WIDTH-1]}}, a_real} + {{EXT{b_real[IN_WIDTH-1]}}, b_real};
    sum_imag = {{EXT{a_imag[IN_WIDTH-1]}}, a_imag} + {{EXT{b_imag[IN_WIDTH-1]}}, b_imag};
  end

endmodule : complex_add
