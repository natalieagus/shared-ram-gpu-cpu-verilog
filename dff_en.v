`timescale 1ns/1ps
module dff_en(
    input  D,
    input  clk,
    input  rst,
    input  en,
    output reg Q
);

reg next_Q;

// combinational
always @* begin
    next_Q = Q;          // default: hold
    if (en) next_Q = D;  // if enabled: take D
end

// sequential
always @(posedge clk or posedge rst) begin
    if (rst) Q <= 1'b0;
    else     Q <= next_Q;
end

// alternative

// always @(posedge clk or posedge rst) begin
//     if (rst)
//         Q <= 1'b0;
//     else if (en)
//         Q <= D;
//     // else: hold
// end


endmodule
