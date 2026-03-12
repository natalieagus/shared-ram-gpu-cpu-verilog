module simple_dual_port_ram #(
    parameter WIDTH   = 8,  // size of each entry
    parameter ENTRIES = 8   // number of entries
) (
    // write interface
    input                       wclk,         // write clock
    input [$clog2(ENTRIES)-1:0] waddr,        // write address
    input [          WIDTH-1:0] write_data,   // write data
    input                       write_enable, // write enable (1 = write)

    // read interface
    input                            rclk,      // read clock
    input      [$clog2(ENTRIES)-1:0] raddr,     // read address
    output reg [          WIDTH-1:0] read_data  // read data
);

  reg [WIDTH-1:0] mem[ENTRIES-1:0];  // memory array

  // write clock domain
  always @(posedge wclk) begin
    if (write_enable)  // if write enable
      mem[waddr] <= write_data;  // write memory
  end

  // read clock domain
  always @(posedge rclk) begin
    read_data <= mem[raddr];  // read memory
  end

endmodule
