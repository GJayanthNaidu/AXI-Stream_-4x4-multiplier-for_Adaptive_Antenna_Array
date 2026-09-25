module complex_mult
  import complex_pkg::*;
(
  input  complex_t      a,
  input  complex_t      b,
  output complex_prod_t p
);

  localparam int RAW_W  = 2*DATA_WIDTH;   // raw partial product: Q2.30, 32 bits
  localparam int COMB_W = RAW_W + 1;      // combined (1 guard bit): Q3.30, 33 bits
  localparam int SHIFT  = FRACTION_WIDTH; // fractional bits discarded going to Q_.15

  function automatic logic signed [COMB_W-1:0] sext_raw(input logic signed [RAW_W-1:0] v);
    sext_raw = {v[RAW_W-1], v};
  endfunction

  logic signed [RAW_W-1:0]  ar_br, ai_bi, ar_bi, ai_br; // each: Q2.30, 32 bits
  logic signed [COMB_W-1:0] real_comb, imag_comb;       // each: Q3.30, 33 bits
  logic signed [COMB_W-1:0] real_trunc, imag_trunc;     // each: Q3.15, 33 bits (18 significant)
  logic                     real_round_up, imag_round_up;
  logic signed [COMB_W-1:0] real_rounded, imag_rounded; // each: Q3.15, 33 bits (18 significant)

  always_comb begin
    ar_br = a.real_part * b.real_part;
    ai_bi = a.imag_part * b.imag_part;
    ar_bi = a.real_part * b.imag_part;
    ai_br = a.imag_part * b.real_part;


    real_comb = sext_raw(ar_br) - sext_raw(ai_bi);
    imag_comb = sext_raw(ar_bi) + sext_raw(ai_br);

    real_trunc = real_comb >>> SHIFT;
    imag_trunc = imag_comb >>> SHIFT;

    real_round_up = real_comb[SHIFT-1] &&
                    (|real_comb[SHIFT-2:0] || real_trunc[0]);
    imag_round_up = imag_comb[SHIFT-1] &&
                    (|imag_comb[SHIFT-2:0] || imag_trunc[0]);

    real_rounded = real_trunc + real_round_up;
    imag_rounded = imag_trunc + imag_round_up;


    p.real_part = $signed(real_rounded[PROD_WIDTH-1:0]);
    p.imag_part = $signed(imag_rounded[PROD_WIDTH-1:0]);
  end

endmodule : complex_mult
