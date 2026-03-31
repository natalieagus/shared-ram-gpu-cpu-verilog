module shared_ram_gpu_cpu (
    input         clk50,
    input         clk25,
    input         rst,
    input         same_phase,
    input  [ 2:0] cpu_addr,
    input  [31:0] cpu_wdata,
    input         cpu_we,
    input  [ 2:0] gpu_addr,
    output [31:0] cpu_rdata_raw,
    output [31:0] gpu_rdata_cached,
    output [31:0] ram_read_data_dbg,
    output [ 2:0] ram_raddr_dbg,
    output        ram_write_enable_dbg
);
  wire [ 2:0] ram_raddr;
  wire [31:0] ram_rdata;
  wire        ram_we;

  // Time-sliced shared read port:
  // clk25 = 1  -> CPU owns read port
  // clk25 = 0  -> GPU owns read port
  assign ram_raddr = (clk25 == 1'b1) ? cpu_addr : gpu_addr;

  assign ram_we = cpu_we;

  simple_dual_port_ram #(
      .WIDTH  (32),
      .ENTRIES(8)
  ) ram_u (
      .wclk(clk50),
      .waddr(cpu_addr),
      .write_data(cpu_wdata),
      .write_enable(ram_we),
      .rclk(clk50),
      .raddr(ram_raddr),
      .read_data(ram_rdata)
  );

  // GPU-side cache register
  register #(
      .W(32),
      .RESET_VALUE(0)
  ) gpu_cache_u (
      .clk(clk25),
      .rst(rst),
      .en (1'b1),
      .d  (ram_rdata),
      .q  (gpu_rdata_cached)
  );

  assign cpu_rdata_raw        = ram_rdata;
  assign ram_read_data_dbg    = ram_rdata;
  assign ram_raddr_dbg        = ram_raddr;
  assign ram_write_enable_dbg = ram_we;
endmodule
