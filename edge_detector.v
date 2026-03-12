module edge_detector #(
    parameter RISE = 1'b1,
    parameter FALL = 1'b1
) (
    input  wire clk,
    input  wire in,
    output reg  out
);

  reg last_q;

  initial begin
    last_q = 1'b0;
  end

  always @* begin
    out = 1'b0;

    if (RISE) begin
      if (in == 1'b1 && last_q == 1'b0) out = 1'b1;
    end

    if (FALL) begin
      if (in == 1'b0 && last_q == 1'b1) out = 1'b1;
    end
  end

  always @(posedge clk) begin
    last_q <= in;
  end

endmodule
