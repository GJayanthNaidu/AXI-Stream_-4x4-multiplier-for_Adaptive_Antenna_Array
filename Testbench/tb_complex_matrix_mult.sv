`timescale 1ns/1ps
module tb_complex_matrix_mult;
  import complex_pkg::*;
  // ===========================================================================
  // PARAMETERS
  // ===========================================================================
  localparam int CLK_PERIOD       = 10;
  // DUT measured latency = 4 clock cycles
  localparam int EXPECTED_LATENCY = 4;
  localparam real TOL_ABS          = 1.0e-3;
  localparam real TOL_PHASE_DEG    = 1.0;
  localparam real AMP_PHASE_THRESH = 0.02;
  localparam real PI = 3.14159265358979323846;
  localparam int TDATA_W = complex_pkg::TDATA_WIDTH;

  // ===========================================================================
  // COMPLEX VECTOR
  // ===========================================================================
  typedef struct {
        real re[4];
        real im[4];
                  }cvec_t;
  // ===========================================================================
  // DUT SIGNALS
  // ===========================================================================
  logic clk;
  logic rst_n;
  logic               s_axis_tvalid;
  logic               s_axis_tready;
  logic [TDATA_W-1:0] s_axis_tdata;
  logic               m_axis_tvalid;
  logic               m_axis_tready;
  logic [TDATA_W-1:0] m_axis_tdata;
  logic               cfg_wr_en;
  logic [3:0]         cfg_wr_addr;
  complex_t            cfg_wr_data;
  logic               cfg_wr_ready;
  // ===========================================================================
  // REFERENCE WEIGHTS
  // ===========================================================================
  real w_real[4][4];
  real w_imag[4][4];
  // ===========================================================================
  // TEST COUNTERS
  // ===========================================================================
  int errors    = 0;
  int tests_run = 0;
  // ===========================================================================
  // TREADY MODE
  //
  // 0 = always ready
  // 1 = randomized
  // 2 = manual
  // ===========================================================================
  int tready_mode = 0;
  // ===========================================================================
  // DUT
  // ===========================================================================
  axi4_stream_wrapper u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .s_axis_tdata  (s_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tdata  (m_axis_tdata),
    .cfg_wr_en     (cfg_wr_en),
    .cfg_wr_addr   (cfg_wr_addr),
    .cfg_wr_data   (cfg_wr_data),
    .cfg_wr_ready  (cfg_wr_ready)
  );

  // ===========================================================================
  // CLOCK
  // ===========================================================================

  initial begin
    clk = 1'b0;
  end

  always #(CLK_PERIOD/2) clk = ~clk;
  // ===========================================================================
  // OUTPUT READY DRIVER
  // ===========================================================================
  initial begin
    m_axis_tready = 1'b1;
    forever begin
      @(negedge clk);
      case (tready_mode)
        0: begin
          m_axis_tready = 1'b1;
        end
        1: begin
          m_axis_tready =($urandom_range(0,99) < 70);
        end
        2: begin
          // Manual control
        end
        default: begin
          m_axis_tready = 1'b1;
        end
      endcase
    end
  end
  // ===========================================================================
  // ABSOLUTE VALUE
  // ===========================================================================
  function automatic real fabs_r(input real value);
    begin
      if (value < 0.0)
        fabs_r = -value;
      else
        fabs_r = value;
    end
  endfunction

  // ===========================================================================
  // REAL -> FIXED POINT
  // ===========================================================================
  function automatic logic signed [DATA_WIDTH-1:0] to_fixed(input real value);
    real val;
    real scaled;
    real maxv;
    real minv;
    integer temp;
    begin
      val = value;
      maxv = (2.0**(DATA_WIDTH-1) - 1.0) /(2.0**FRACTION_WIDTH);
      minv =-(2.0**(DATA_WIDTH-1)) /(2.0**FRACTION_WIDTH);
      // Saturation
      if (val > maxv)
        val = maxv;
      if (val < minv)
        val = minv;
      scaled = val * (2.0**FRACTION_WIDTH);
      // Rounding
      if (scaled >= 0.0)
        temp = $rtoi(scaled + 0.5);
      else
        temp = $rtoi(scaled - 0.5);
      to_fixed = temp[DATA_WIDTH-1:0];
    end
  endfunction

  // ===========================================================================
  // FIXED POINT -> REAL
  // ===========================================================================
  function automatic real
    to_float(input logic signed [DATA_WIDTH-1:0] value);
    begin
      to_float = real'(value) /(2.0**FRACTION_WIDTH);
    end
  endfunction
  // ===========================================================================
  // RESET
  // ===========================================================================
  task automatic apply_reset();
    begin
      rst_n = 1'b0;
      s_axis_tvalid = 1'b0;
      s_axis_tdata  = '0;
      cfg_wr_en   = 1'b0;
      cfg_wr_addr = '0;
      cfg_wr_data = '{default:'0};
      repeat (3)@(negedge clk);
      rst_n = 1'b1;
      @(negedge clk);
    end
  endtask


  // ===========================================================================
  // WRITE ONE WEIGHT
  // ===========================================================================

  task automatic cfg_set_weight(input int row,input int col,input real re,input real im );
    logic signed [DATA_WIDTH-1:0] re_fixed;
    logic signed [DATA_WIDTH-1:0] im_fixed;
    begin
      re_fixed = to_fixed(re);
      im_fixed = to_fixed(im);
      @(negedge clk);
      while (!cfg_wr_ready)@(negedge clk);
      cfg_wr_addr = {row[1:0], col[1:0]};
      cfg_wr_data.real_part = re_fixed;
      cfg_wr_data.imag_part = im_fixed;
      cfg_wr_en = 1'b1;
      @(negedge clk);
      cfg_wr_en = 1'b0;
      // Store quantized values in reference model
      w_real[row][col] = to_float(re_fixed);
      w_imag[row][col] = to_float(im_fixed);
    end
  endtask
  // ===========================================================================
  // IDENTITY MATRIX
  // ===========================================================================
  task automatic configure_identity();
    int r;
    int c;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          cfg_set_weight(r,c,(r == c) ? 1.0 : 0.0,0.0);
        end
      end
    end
  endtask

  // ===========================================================================
  // SCALE MATRIX
  // ===========================================================================
  task automatic configure_scale(input real gain);
    int r;
    int c;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          cfg_set_weight(r,c,(r == c) ? gain : 0.0,0.0);
        end
      end
    end
  endtask
  // ===========================================================================
  // PHASE ROTATION MATRIX
  // ===========================================================================
  task automatic configure_phase_rotate(input real re,input real im);
    int r;
    int c;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          cfg_set_weight(r,c,(r == c) ? re : 0.0,(r == c) ? im : 0.0);
        end
      end
    end
  endtask
  // ===========================================================================
  // BEAMSTEERING MATRIX
  // ===========================================================================
  task automatic configure_beamsteering(input real phi,input real mag);
    int r;
    int c;
    real angle;
    real re;
    real im;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          angle = c * phi;
          re = mag * $cos(angle);
          im = mag * $sin(angle);
          cfg_set_weight(r,c,re,im);
        end
      end
    end
  endtask
  // ===========================================================================
  // CUSTOM MATRIX
  // ===========================================================================

  task automatic configure_custom(input real re_mat[4][4],input real im_mat[4][4]);
    int r;
    int c;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          cfg_set_weight(r,c,re_mat[r][c],im_mat[r][c]);
        end
      end
    end
  endtask
  // ===========================================================================
  // DRIVE ONE INPUT VECTOR
  // ===========================================================================
  task automatic drive_input(input real x_re[4],input real x_im[4],output realtime fire_time);
    logic [TDATA_W-1:0] tdata_local;
    int i;
    begin
      tdata_local = '0;
      for (i = 0; i < 4; i = i + 1) begin
        tdata_local[i*32 +: 16] = to_fixed(x_re[i]);
        tdata_local[i*32+16 +: 16] = to_fixed(x_im[i]);
      end
      @(negedge clk);
      s_axis_tdata  = tdata_local;
      s_axis_tvalid = 1'b1;
      // Wait for input handshake
      do begin @(posedge clk);
      end
      while (!s_axis_tready);
      fire_time = $time;
      @(negedge clk);
      s_axis_tvalid = 1'b0;
    end
  endtask
  // ===========================================================================
  // DRIVE BURST
  // ===========================================================================
  task automatic drive_burst(input cvec_t xvecs[$],output realtime fire_t[$]);
    int NUM;
    int k;
    int i;
    logic [TDATA_W-1:0] tdata_local;
    begin
      NUM = xvecs.size();
      fire_t.delete();
      if (NUM == 0)
        return;
      // First vector
      @(negedge clk);
      tdata_local = '0;
      for (i = 0; i < 4; i = i + 1) begin
        tdata_local[i*32 +: 16] = to_fixed(xvecs[0].re[i]);
        tdata_local[i*32+16 +: 16] = to_fixed(xvecs[0].im[i]);
      end
      s_axis_tdata  = tdata_local;
      s_axis_tvalid = 1'b1;
      k = 0;
      while (k < NUM) begin
        @(posedge clk);
        if (s_axis_tready) begin
          fire_t.push_back($time);
          k = k + 1;
          if (k < NUM) begin
            @(negedge clk);
            tdata_local = '0;
            for (i = 0; i < 4; i = i + 1) begin
              tdata_local[i*32 +: 16] = to_fixed(xvecs[k].re[i]);
              tdata_local[i*32+16 +: 16] = to_fixed(xvecs[k].im[i]);
            end
            s_axis_tdata = tdata_local;
          end
        end
      end
      @(negedge clk);
      s_axis_tvalid = 1'b0;
    end
  endtask

  // ===========================================================================
  // CAPTURE OUTPUT
  // ===========================================================================
  task automatic capture_output(output real y_re[4],output real y_im[4],output realtime xfer_time);
    logic [TDATA_W-1:0] tdata_local;
    int i;
    begin
      do begin
        @(posedge clk);
      end
      while (!(m_axis_tvalid && m_axis_tready));
      xfer_time = $time;
      tdata_local = m_axis_tdata;
      for (i = 0; i < 4; i = i + 1) begin
        y_re[i] = to_float( tdata_local[i*32 +: 16]);
        y_im[i] =to_float(tdata_local[i*32+16 +: 16]);
      end
    end
  endtask
  // ===========================================================================
  // REFERENCE MODEL
  // ===========================================================================

  function automatic void compute_reference(input real x_re[4],input real x_im[4],output real y_re[4],output real y_im[4]);
    int r;
    int c;
    real sr;
    real si;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        sr = 0.0;
        si = 0.0;
        for (c = 0; c < 4; c = c + 1) begin
          sr = sr + x_re[c] * w_real[r][c] - x_im[c] * w_imag[r][c];
          si = si + x_re[c] * w_imag[r][c] + x_im[c] * w_real[r][c];
        end
        y_re[r] = sr;
        y_im[r] = si;
      end
    end
  endfunction
  // ===========================================================================
  // CHECK OUTPUT
  // ===========================================================================
  task automatic check_outputs(
    input string test_name,
    input real y_re_ref[4],
    input real y_im_ref[4],
    input real y_re_rtl[4],
    input real y_im_rtl[4],
    input bit check_phase
  );
    int i;
    real err_re;
    real err_im;
    real amp_ref;
    real amp_rtl;
    real err_amp;
    real ph_ref;
    real ph_rtl;
    real dphi;
    real err_phase_deg;
    bit fail;
    begin
      for (i = 0; i < 4; i = i + 1) begin
        fail = 1'b0;
        err_re = y_re_rtl[i] - y_re_ref[i];
        err_im = y_im_rtl[i] - y_im_ref[i];
        amp_ref = $sqrt(y_re_ref[i] * y_re_ref[i]+y_im_ref[i] * y_im_ref[i]);
        amp_rtl = $sqrt(y_re_rtl[i] * y_re_rtl[i]+y_im_rtl[i] * y_im_rtl[i]);
        err_amp =amp_rtl - amp_ref;
        err_phase_deg = 0.0;
        if (fabs_r(err_re) > TOL_ABS)
          fail = 1'b1;
        if (fabs_r(err_im) > TOL_ABS)
          fail = 1'b1;
        if (fabs_r(err_amp) > TOL_ABS)
          fail = 1'b1;
        if (check_phase &&
            amp_ref > AMP_PHASE_THRESH) begin
          ph_ref = $atan2(y_im_ref[i],y_re_ref[i]);
          ph_rtl =$atan2(y_im_rtl[i],y_re_rtl[i]);
          dphi = ph_rtl - ph_ref;
          while (dphi > PI)
            dphi = dphi - 2.0 * PI;
          while (dphi < -PI)
            dphi = dphi + 2.0 * PI;
          err_phase_deg = dphi * 180.0 / PI;
          if (fabs_r(err_phase_deg) > TOL_PHASE_DEG)
            fail = 1'b1;
        end
        tests_run = tests_run + 1;
        if (fail)
          errors = errors + 1;
        if (fail) begin
          $display("[%s] y%0d : FAIL",test_name,i);
        end
        else begin
          $display("[%s] y%0d : PASS",test_name,i);
        end
        $display("REF = (%f, %f)",y_re_ref[i],y_im_ref[i]);
        $display("RTL = (%f, %f)",y_re_rtl[i],y_im_rtl[i]);
        $display("ERR = (Re:%e Im:%e Amp:%e Phase:%f deg)",err_re,err_im,err_amp,err_phase_deg);
      end
    end
  endtask
  // ===========================================================================
  // RUN ONE VECTOR
  // ===========================================================================
  task automatic run_vector(
    input string test_name,
    input real x_re[4],
    input real x_im[4],
    input bit check_latency
  );
    realtime t_fire;
    realtime t_xfer;
    real y_re_rtl[4];
    real y_im_rtl[4];
    real y_re_ref[4];
    real y_im_ref[4];
    int latency_cycles;
    begin
      drive_input(x_re,x_im,t_fire);
      capture_output(y_re_rtl,y_im_rtl,t_xfer);
      compute_reference(x_re,x_im,y_re_ref,y_im_ref);
      check_outputs(test_name,y_re_ref,y_im_ref,y_re_rtl,y_im_rtl,1'b1);
      if (check_latency) begin
        latency_cycles = (t_xfer - t_fire) /CLK_PERIOD;
        tests_run = tests_run + 1;
        if (latency_cycles != EXPECTED_LATENCY) begin
          errors = errors + 1;
          $display("[%s] LATENCY FAIL: measured=%0d expected=%0d",test_name,latency_cycles,EXPECTED_LATENCY);
        end
        else begin
          $display("[%s] LATENCY PASS: %0d cycles",test_name,latency_cycles);
        end
      end
    end
  endtask
  // ===========================================================================
  // RUN BURST
  // ===========================================================================
  task automatic run_burst(
    input string test_name,
    input cvec_t xvecs[$],
    input bit check_spacing
  );
    int NUM;
    int i;
    realtime fire_t[$];
    realtime xfer_t[$];
    cvec_t yref_q[$];
    cvec_t yref;
    bit overlap_seen;
    begin
      NUM = xvecs.size();
      fire_t.delete();
      xfer_t.delete();
      yref_q.delete();
      overlap_seen = 1'b0;
      if (NUM == 0) begin
        $display("[%s] WARNING: empty burst",test_name);
        return;
      end
      // Precalculate reference
      foreach (xvecs[k]) begin
        compute_reference(xvecs[k].re,xvecs[k].im,yref.re,yref.im);
        yref_q.push_back(yref);
      end
      // =======================================================================
      // DRIVER + CHECKER
      // =======================================================================
      fork
        begin : burst_driver
          drive_burst(xvecs,fire_t);
        end
        begin : burst_checker
          real yr_rtl[4];
          real yi_rtl[4];
          realtime t;
          for (int k = 0; k < NUM; k = k + 1) begin
            capture_output(yr_rtl,yi_rtl,t);
            xfer_t.push_back(t);
            check_outputs($sformatf("%s-vec%0d",test_name,k),yref_q[k].re,yref_q[k].im,yr_rtl,yi_rtl,1'b1);
          end
        end
      join
      // =======================================================================
      // THROUGHPUT CHECK
      // =======================================================================
      for (i = 1; i < NUM; i = i + 1) begin
        tests_run = tests_run + 1;
        if (check_spacing) begin
          if ((xfer_t[i] - xfer_t[i-1]) != CLK_PERIOD) begin
            errors = errors + 1;
            $display("[%s] THROUGHPUT FAIL: vec%0d -> vec%0d spacing=%0t",test_name,i-1,i,xfer_t[i] - xfer_t[i-1]);
          end
          else begin
            $display("[%s] THROUGHPUT PASS: vec%0d -> vec%0d = 1 cycle",test_name,i-1,i);
          end
        end
        else begin
          if (fire_t[i] < xfer_t[i-1])
            overlap_seen = 1'b1;
        end
      end
      // =======================================================================
      // OVERLAP CHECK
      // =======================================================================
      if (!check_spacing) begin
        tests_run = tests_run + 1;
        if (!overlap_seen) begin
          errors = errors + 1;
          $display("[%s] OVERLAP FAIL: burst did not overlap",test_name);
        end
        else begin
          $display("[%s] OVERLAP PASS: multiple vectors in flight",test_name);
        end
      end
    end
  endtask
  // ===========================================================================
  // MAIN TEST
  // ===========================================================================
  initial begin
    real xr[4];
    real xi[4];
    realtime t_fire;
    realtime t_xfer;
    real y_re_rtl[4];
    real y_im_rtl[4];
    real y_re_ref[4];
    real y_im_ref[4];
    int i;
    int j;
    // =========================================================================
    // INITIALIZE REFERENCE MATRIX
    // =========================================================================
    for (i = 0; i < 4; i = i + 1) begin
      for (j = 0; j < 4; j = j + 1) begin
        w_real[i][j] = 0.0;
        w_imag[i][j] = 0.0;
      end
    end
    // =========================================================================
    // RESET
    // =========================================================================
    apply_reset();
   // =========================================================================
    // TEST 1: IDENTITY
    // =========================================================================
    $display("\n===== TEST 1: Identity matrix (Y = X), latency check =====");
   configure_identity();
    xr = '{0.50, -0.30, 0.20, 0.00};
    xi = '{0.25,  0.10, -0.20, 0.40};
    run_vector("T1-identity",xr,xi,1'b1);
    // =========================================================================
    // TEST 2: SCALE
    // =========================================================================
    $display("\n===== TEST 2: Pure amplitude scaling (0.5x) =====");
    configure_scale(0.5);
    run_vector("T2-scale0p5",xr,xi,1'b0);
    // =========================================================================
    // TEST 3: PHASE ROTATION
    // =========================================================================
    $display("\n===== TEST 3: Pure phase rotation (~+90 degrees) =====");
    configure_phase_rotate(0.0,32767.0 / 32768.0);
    run_vector("T3-rotate90",xr,xi,1'b0);
    // =========================================================================
    // TEST 4: BEAMSTEERING
    // =========================================================================
    $display("\n===== TEST 4: Progressive-phase static beamsteering matrix =====");
    configure_beamsteering(PI / 6.0,0.20);
    run_vector("T4-beamsteer",xr,xi,1'b0);
    // =========================================================================
    // TEST 5: BACK-TO-BACK
    // =========================================================================
    $display("\n===== TEST 5: Back-to-back throughput =====");
    configure_identity();
    tready_mode = 0;
    begin : test5_block
      cvec_t burst5[$];
      cvec_t v;
      for (i = 0; i < 5; i = i + 1) begin
        v.re = '{0.1 * i,-0.05 * i,0.2 - 0.02 * i,0.01 * i};
        v.im = '{0.05 * i,0.1 * i,-0.1 + 0.01 * i,0.3 - 0.02 * i};
        burst5.push_back(v);
      end
      run_burst("T5-burst",burst5,1'b1);
    end
    // =========================================================================
    // TEST 6: RANDOM BACKPRESSURE
    // =========================================================================
    $display("\n===== TEST 6: Back-to-back under randomized backpressure =====");
    tready_mode = 1;
    begin : test6_block
      cvec_t burst6[$];
      cvec_t v;
      for (i = 0; i < 5; i = i + 1) begin
        v.re = '{0.3 - 0.05 * i,0.15,-0.1 + 0.02 * i,0.05 * i};
        v.im = '{-0.2 + 0.03 * i,0.1 * i,0.05,-0.15 + 0.01 * i};
        burst6.push_back(v);
      end
      run_burst("T6-burst-bp",burst6,1'b0);
    end
    tready_mode = 0;
    // =========================================================================
    // TEST 7: INPUT FLOW CONTROL
    // =========================================================================
    $display("\n===== TEST 7: Input-side flow control =====");
    tready_mode = 2;
    m_axis_tready = 1'b0;
    xr = '{0.4,0.1,-0.2,0.05};
    xi = '{0.1,-0.3,0.05,0.2};
    drive_input(xr,xi,t_fire);
    wait (m_axis_tvalid == 1'b1);
    @(negedge clk);
    tests_run = tests_run + 1;
    if (s_axis_tready !== 1'b0) begin
      errors = errors + 1;
      $display("[T7-flow-control] FAIL: s_axis_tready did not deassert");
    end
    else begin
      $display("[T7-flow-control] PASS: s_axis_tready deasserted");
    end
    m_axis_tready = 1'b1;
    capture_output(y_re_rtl,y_im_rtl,t_xfer);
    compute_reference(xr,xi,y_re_ref,y_im_ref);
    check_outputs("T7-flow-control-data",y_re_ref,y_im_ref,y_re_rtl,y_im_rtl,1'b1);
    tready_mode = 0;
    // =========================================================================
    // TEST 8: RESET MID-FLIGHT
    // =========================================================================
    //
    // FIX NOTE:
    // Previously this block called apply_reset(), which internally does:
    //   rst_n = 0; repeat(3) @(negedge clk); rst_n = 1; @(negedge clk);
    // i.e. by the time apply_reset() RETURNS, rst_n has already been HIGH
    // for a full extra clock cycle. The old code then immediately sampled
    // s_axis_tready and expected it to still read 0 - but for an idle,
    // well-behaved DUT it is perfectly correct for tready to already be
    // back up by then, since reset was released a cycle earlier. That
    // mismatch (not a real DUT bug) is what caused the single reported
    // failure: "[T8-reset] FAIL: s_axis_tready asserted after reset".
    //
    // Fix: assert reset manually here (instead of calling apply_reset()),
    // and sample s_axis_tready WHILE rst_n is still low, which is the
    // actual intent of this check. Reset is then released afterward, and
    // the rest of the original test sequence (stale-output check, normal
    // operation resume) is preserved unchanged.
    // =========================================================================
    $display("\n===== TEST 8: Reset during in-flight transaction =====");
    xr = '{0.2,0.2,0.2,0.2};
    xi = '{0.1,0.1,0.1,0.1};
    // Start transaction
    drive_input(xr,xi,t_fire);
    // Assert reset while transaction is in the pipeline
    @(negedge clk);
    rst_n = 1'b0;
    s_axis_tvalid = 1'b0;
    s_axis_tdata  = '0;
    cfg_wr_en   = 1'b0;
    cfg_wr_addr = '0;
    cfg_wr_data = '{default:'0};
    // Give reset one cycle to take effect, then check tready
    // WHILE reset is still asserted (rst_n == 0)
    @(negedge clk);
    // Check no valid output
    tests_run = tests_run + 1;
    if (m_axis_tvalid !== 1'b0) begin
      errors = errors + 1;
      $display("[T8-reset] FAIL: m_axis_tvalid asserted after reset");
    end
    else begin
      $display("[T8-reset] PASS: m_axis_tvalid deasserted after reset");
    end
    // Check input ready is deasserted DURING reset (rst_n still 0 here)
    tests_run = tests_run + 1;
    if (s_axis_tready !== 1'b0) begin
      errors = errors + 1;
      $display("[T8-reset] FAIL: s_axis_tready asserted after reset");
    end
    else begin
      $display("[T8-reset] PASS: s_axis_tready deasserted after reset");
    end
    // Hold reset for the remaining cycles, then release it
    repeat (2)
      @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    // Make sure stale result does not appear
    repeat (EXPECTED_LATENCY + 2) begin
      @(posedge clk);
      if (m_axis_tvalid !== 1'b0) begin
        errors = errors + 1;
        $display("[T8-reset] FAIL: stale m_axis_tvalid detected");
      end
    end
    $display("[T8-reset] PASS: no stale output after reset");
    // Check normal operation after reset
    configure_identity();
    run_vector("T8-post-reset-identity",xr,xi,1'b1);
    // =========================================================================
    // FINAL REPORT
    // =========================================================================
    $display("\n===================================================");
    if (errors == 0) begin
      $display("OVERALL RESULT: PASS");
      $display("TOTAL CHECKS = %0d",tests_run);
    end
    else begin
      $display("OVERALL RESULT: FAIL");
      $display("TOTAL CHECKS = %0d",tests_run);
      $display("TOTAL FAILURES = %0d",errors);
    end
    $display("===================================================\n");
    $finish;
  end
  // ===========================================================================
  // WATCHDOG
  // ===========================================================================
  initial begin
    #(CLK_PERIOD * 20000);
    $display("ERROR: TESTBENCH WATCHDOG TIMEOUT");
    $finish;
  end
endmodule
