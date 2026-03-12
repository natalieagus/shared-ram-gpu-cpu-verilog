module register #(
    parameter W = 1,
    parameter RESET_VALUE = 0
) (
    input  wire         clk,
    input  wire         rst,  // async active-high reset
    input  wire         en,   // synchronous enable
    input  wire [W-1:0] d,
    output reg  [W-1:0] q
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      q <= RESET_VALUE;
    end else if (en) begin
      q <= d;
    end else begin
      q <= q;  // hold
    end
  end
endmodule
