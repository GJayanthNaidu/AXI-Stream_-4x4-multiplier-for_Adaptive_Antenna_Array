package complex_pkg;

  localparam int DATA_WIDTH     = 16;              // Q1.15 sample/weight width
  localparam int FRACTION_WIDTH = 15;              // fractional bits of DATA_WIDTH
  localparam int PROD_WIDTH     = DATA_WIDTH + 2;  // 18, see width analysis above
  localparam int STAGE1_WIDTH   = PROD_WIDTH + 1;  // 19, one growth bit
  localparam int ACC_WIDTH      = STAGE1_WIDTH + 1;// 20, one growth bit

  localparam int NUM_ELEM = 4;
  
  localparam int TDATA_WIDTH        = NUM_ELEM * 2 * DATA_WIDTH; // 128
  localparam int S_AXIS_TDATA_WIDTH = TDATA_WIDTH;
  localparam int M_AXIS_TDATA_WIDTH = TDATA_WIDTH;

  typedef struct packed {
    logic signed [DATA_WIDTH-1:0] real_part;
    logic signed [DATA_WIDTH-1:0] imag_part;
  } complex_t;

  typedef struct packed {
    logic signed [PROD_WIDTH-1:0] real_part;
    logic signed [PROD_WIDTH-1:0] imag_part;
  } complex_prod_t;

  typedef struct packed {
    logic signed [STAGE1_WIDTH-1:0] real_part;
    logic signed [STAGE1_WIDTH-1:0] imag_part;
  } complex_stage1_t;

  typedef struct packed {
    logic signed [ACC_WIDTH-1:0] real_part;
    logic signed [ACC_WIDTH-1:0] imag_part;
  } complex_acc_t;

endpackage : complex_pkg
