`timescale 1ns / 1ps

// Clock setup:
//   clk50: posedge at 10,30,50,...  negedge at 20,40,60,...
//   clk25: posedge at 20,60,100,... negedge at 40,80,120,...
//
// clk50 negedge is always aligned with clk25 posedge AND negedge.
// This means every clk25 half-period contains exactly one clk50 posedge
// in its interior, giving 10 ns of setup time from any stimulus driven
// right at a clk25 edge.
//
// IMPORTANT: the clk50 initial block MUST appear before the clk25 initial
// block in the file.  At a shared timestamp (e.g. t=60) both toggles land
// in the active region; because clk50 is scheduled first it fires first in
// delta 0, so the GPU-cache register (clk = clk50_n, en = ~clk25) samples
// with clk25 still 0 (en=1) before clk25 rises in delta 1.
//
// Task calling convention:
//   cpu_* tasks are called right after @(posedge clk25)  -> CPU slot
//   gpu_*  task is called right after @(negedge clk25)   -> GPU slot
//   Stimulus is stable well before the next clk50 posedge in each slot.
//
// Cache latency analysis:
//   GPU addr driven at negedge clk25 (T).
//   RAM latches raddr at next clk50 posedge (T+10ns).
//   gpu_cache register captures at next clk50 negedge = next clk25 posedge (T+20ns).
//   Total GPU cache latency = 1 clk25 half-period = 20ns true wall time.
//
//   CPU raw driven at posedge clk25 (T).
//   RAM latches raddr at next clk50 posedge (T+10ns).
//   cpu_rdata_raw is a wire directly from ram_rdata, valid T+10ns+delta.
//   Readable cleanly at negedge clk25 (T+20ns).
//
// GPU cache read timing note:
//   gpu_rdata_cached is driven by a non-blocking assignment (NBA) inside
//   the cache register.  The NBA commits AFTER the active region of the
//   posedge clk25 timestep.  Therefore every GPU $display adds #1 after
//   @(posedge clk25) to step past the NBA region before sampling the wire.
//   This makes all GPU latency readings appear as 21 ns instead of 20 ns;
//   the true hardware latency is 20 ns -- the extra 1 ns is a simulation
//   read-after-NBA artefact only.

module tb_shared_ram;

  reg            clk50;
  reg            clk25;
  reg            rst;

  reg     [ 2:0] cpu_addr;
  reg     [31:0] cpu_wdata;
  reg            cpu_we;
  reg     [ 2:0] gpu_addr;

  wire    [31:0] cpu_rdata_raw;
  wire    [31:0] gpu_rdata_cached;
  wire    [31:0] ram_read_data_dbg;
  wire    [ 2:0] ram_raddr_dbg;
  wire           ram_write_enable_dbg;

  // track when each read request was issued for latency reporting
  integer        gpu_req_time;
  integer        cpu_req_time;

  shared_ram_gpu_cpu dut (
      .same_phase          (1'b0),
      .clk50               (clk50),
      .clk25               (clk25),
      .rst                 (rst),
      .cpu_addr            (cpu_addr),
      .cpu_wdata           (cpu_wdata),
      .cpu_we              (cpu_we),
      .gpu_addr            (gpu_addr),
      .cpu_rdata_raw       (cpu_rdata_raw),
      .gpu_rdata_cached    (gpu_rdata_cached),
      .ram_read_data_dbg   (ram_read_data_dbg),
      .ram_raddr_dbg       (ram_raddr_dbg),
      .ram_write_enable_dbg(ram_write_enable_dbg)
  );

  // clk50 MUST be first -- see delta-cycle note above
  initial begin
    clk50 = 1'b0;
    forever #10 clk50 = ~clk50;
  end

  initial begin
    clk25 = 1'b0;
    #20;
    forever #20 clk25 = ~clk25;
  end

  initial begin
    $dumpfile("tb_shared_ram.vcd");
    $dumpvars(0, tb_shared_ram);
  end

  // Log every clk50 posedge: this is when the RAM actually does its work
  always @(posedge clk50) begin
    $display(
        "T=%0t [RAM+] clk25=%b | cpu_addr=%0d we=%b wdata=%h | gpu_addr=%0d | raddr=%0d rdata=%h | cpu_raw=%h gpu_cache=%h",
        $time, clk25, cpu_addr, cpu_we, cpu_wdata, gpu_addr, ram_raddr_dbg, ram_read_data_dbg,
        cpu_rdata_raw, gpu_rdata_cached);
  end

  // ----------------------------------------------------------------
  // Tasks
  // ----------------------------------------------------------------

  task cpu_write;
    input [2:0] addr;
    input [31:0] data;
    begin
      cpu_addr  = addr;
      cpu_wdata = data;
      cpu_we    = 1'b1;
      $display("T=%0t [CPU]  WRITE  addr=%0d  data=%h", $time, addr, data);
    end
  endtask

  task cpu_read;
    input [2:0] addr;
    begin
      cpu_addr     = addr;
      cpu_we       = 1'b0;
      cpu_req_time = $time;
      $display("T=%0t [CPU]  READ   addr=%0d  (req_time recorded)", $time, addr);
    end
  endtask

  task cpu_idle;
    begin
      cpu_we = 1'b0;
    end
  endtask

  task gpu_read;
    input [2:0] addr;
    begin
      gpu_addr     = addr;
      gpu_req_time = $time;
      $display("T=%0t [GPU]  READ   addr=%0d  (req_time recorded)", $time, addr);
    end
  endtask

  // ----------------------------------------------------------------
  // Main test sequence
  // ----------------------------------------------------------------
  initial begin
    rst          = 1'b1;
    cpu_addr     = 3'd0;
    cpu_wdata    = 32'h0;
    cpu_we       = 1'b0;
    gpu_addr     = 3'd0;
    gpu_req_time = 0;
    cpu_req_time = 0;

    #5;
    rst = 1'b0;

    // ==============================================================
    // PHASE 1: CPU preloads addrs 1-4
    // ==============================================================
    $display("\n===== PHASE 1: CPU writes addrs 1-4  |  GPU parks on addr 0 (uninit -> X) =====");

    @(posedge clk25);
    gpu_addr = 3'd0;
    cpu_idle();

    @(posedge clk25);
    cpu_write(3'd1, 32'hAAAA1111);
    @(negedge clk25);
    cpu_idle();

    @(posedge clk25);
    cpu_write(3'd2, 32'hBBBB2222);
    @(negedge clk25);
    cpu_idle();

    @(posedge clk25);
    cpu_write(3'd3, 32'hCCCC3333);
    @(negedge clk25);
    cpu_idle();

    @(posedge clk25);
    cpu_write(3'd4, 32'hDDDD4444);
    @(negedge clk25);
    cpu_idle();

    // ==============================================================
    // PHASE 2: GPU reads addrs 1-4
    // ==============================================================
    $display("\n===== PHASE 2: GPU reads addrs 1-4 that CPU wrote  |  CPU idle =====");

    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    gpu_read(3'd1);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 = %h  (expect AAAA1111) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    @(negedge clk25);
    gpu_read(3'd2);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr2 = %h  (expect BBBB2222) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    @(negedge clk25);
    gpu_read(3'd3);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr3 = %h  (expect CCCC3333) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    @(negedge clk25);
    gpu_read(3'd4);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr4 = %h  (expect DDDD4444) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    // ==============================================================
    // PHASE 3: CPU write and GPU read SAME addr same clk25 period
    // ==============================================================
    $display("\n===== PHASE 3: CPU write and GPU read SAME addr in same clk25 period =====");

    @(posedge clk25);
    cpu_write(3'd3, 32'hDEADBEEF);
    @(negedge clk25);
    cpu_idle();
    gpu_read(3'd3);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr3 = %h  (expect DEADBEEF) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    @(posedge clk25);
    cpu_write(3'd5, 32'hFEED5555);
    @(negedge clk25);
    cpu_idle();
    gpu_read(3'd5);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr5 = %h  (expect FEED5555) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    @(posedge clk25);
    cpu_write(3'd6, 32'h66660000);
    @(negedge clk25);
    cpu_idle();
    gpu_read(3'd5);
    @(posedge clk25); #1;
    $display(
        "T=%0t [CHECK] gpu_cache addr5 = %h  (expect FEED5555, diff-addr write no corrupt) latency=%0t ns",
        $time, gpu_rdata_cached, $time - gpu_req_time);

    // ==============================================================
    // PHASE 4: CPU writes addr 7, GPU reads different addr
    // ==============================================================
    $display("\n===== PHASE 4: CPU writes addr 7 | GPU reads addr 2 (different addrs) =====");

    @(posedge clk25);
    cpu_write(3'd7, 32'h77777777);
    @(negedge clk25);
    cpu_idle();
    gpu_read(3'd2);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr2 = %h  (expect BBBB2222) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    gpu_read(3'd7);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr7 = %h  (expect 77777777) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // ==============================================================
    // PHASE 5: CPU reads raw then GPU reads same addrs
    // ==============================================================
    $display("\n===== PHASE 5: CPU reads raw then GPU reads same addrs =====");

    @(posedge clk25);
    cpu_read(3'd1);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr1 = %h  (expect AAAA1111) latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd1);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 = %h  (expect AAAA1111) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    @(posedge clk25);
    cpu_read(3'd3);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr3 = %h  (expect DEADBEEF) latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd3);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr3 = %h  (expect DEADBEEF) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    @(posedge clk25);
    cpu_read(3'd6);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr6 = %h  (expect 66660000) latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd6);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr6 = %h  (expect 66660000) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    @(posedge clk25);
    cpu_read(3'd7);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr7 = %h  (expect 77777777) latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd7);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr7 = %h  (expect 77777777) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);
    cpu_idle();

    // ==============================================================
    // PHASE 6: Rapid interleaved GPU/CPU reads cycling all written
    //          addresses.  CPU and GPU always read DIFFERENT addrs
    //          each slot so the mux stays busy.
    //          Measures cache latency on every single GPU request.
    //          Expected GPU latency: 21 ns displayed (20 ns true,
    //          +1 ns post-NBA read offset -- see file header note).
    //          Expected CPU latency: always 20 ns (readable at negedge,
    //          which is 20 ns after posedge clk25 where addr was driven).
    // ==============================================================
    $display("\n===== PHASE 6: Rapid interleaved reads across all written addrs =====");
    $display(
        "       GPU latency = time from negedge clk25 (addr driven) to posedge clk25+1ns (cache valid)");
    $display(
        "       CPU latency = time from posedge clk25 (addr driven) to negedge clk25 (raw valid)");
    $display("       CPU should show 20 ns, GPU should show 21 ns (20 ns true + 1 ns NBA offset).");

    // slot A: CPU reads addr 1, GPU reads addr 4
    @(posedge clk25);
    cpu_read(3'd1);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr1 = %h  (expect AAAA1111) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd4);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr4 = %h  (expect DDDD4444) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // slot B: CPU reads addr 2, GPU reads addr 7
    @(posedge clk25);
    cpu_read(3'd2);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr2 = %h  (expect BBBB2222) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd7);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr7 = %h  (expect 77777777) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // slot C: CPU reads addr 5, GPU reads addr 3
    @(posedge clk25);
    cpu_read(3'd5);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr5 = %h  (expect FEED5555) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd3);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr3 = %h  (expect DEADBEEF) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // slot D: CPU reads addr 6, GPU reads addr 1
    @(posedge clk25);
    cpu_read(3'd6);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr6 = %h  (expect 66660000) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd1);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 = %h  (expect AAAA1111) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // slot E: CPU reads addr 7, GPU reads addr 6
    @(posedge clk25);
    cpu_read(3'd7);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr7 = %h  (expect 77777777) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd6);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr6 = %h  (expect 66660000) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // slot F: CPU reads addr 3, GPU reads addr 5
    @(posedge clk25);
    cpu_read(3'd3);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr3 = %h  (expect DEADBEEF) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd5);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr5 = %h  (expect FEED5555) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // slot G: CPU reads addr 4, GPU reads addr 2
    @(posedge clk25);
    cpu_read(3'd4);
    @(negedge clk25);
    $display("T=%0t [CHECK] cpu_raw  addr4 = %h  (expect DDDD4444) cpu_latency=%0t ns", $time,
             cpu_rdata_raw, $time - cpu_req_time);
    gpu_read(3'd2);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr2 = %h  (expect BBBB2222) gpu_latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // ==============================================================
    // PHASE 7: GPU reads the SAME address multiple consecutive slots
    //          to confirm cache holds stably between updates.
    // ==============================================================
    $display(
        "\n===== PHASE 7: GPU holds same addr across 4 consecutive slots (cache stability) =====");

    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    gpu_read(3'd1);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 slot 1 = %h  (expect AAAA1111) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // keep gpu_addr=1 for 3 more slots, confirm value holds
    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 slot 2 = %h  (expect AAAA1111, held)", $time,
             gpu_rdata_cached);

    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 slot 3 = %h  (expect AAAA1111, held)", $time,
             gpu_rdata_cached);

    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 slot 4 = %h  (expect AAAA1111, held)", $time,
             gpu_rdata_cached);

    // ==============================================================
    // PHASE 8: CPU writes a new value while GPU is repeatedly reading
    //          the same addr.  Confirms GPU cache updates exactly 1
    //          clk25 period after the CPU write completes.
    // ==============================================================
    $display(
        "\n===== PHASE 8: CPU overwrites addr 1 mid-stream, GPU should see new value next slot =====");

    // GPU parked on addr 1, CPU writes new value
    @(posedge clk25);
    cpu_write(3'd1, 32'hABCD1111);  // overwrite
    @(negedge clk25);
    cpu_idle();
    gpu_read(3'd1);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 = %h  (expect ABCD1111) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    // one more slot: GPU re-reads addr 1 to confirm cache holds new value
    @(posedge clk25);
    cpu_idle();
    @(negedge clk25);
    gpu_read(3'd1);
    @(posedge clk25); #1;
    $display("T=%0t [CHECK] gpu_cache addr1 = %h  (expect ABCD1111, stable) latency=%0t ns", $time,
             gpu_rdata_cached, $time - gpu_req_time);

    $display("\n===== END =====");
    #40;
    $finish;
  end

endmodule
