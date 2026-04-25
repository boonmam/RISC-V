`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/19/2026 05:57:44 PM
// Design Name: 
// Module Name: 16bit_adder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module 16bit_adder(

    input a [15:0],
    input b [15:0],
    output sum [15:0]
    output carry_out
    output overflow
    );

a + b = sum;

overflow = (a[15] == b[15]) && (sum[15] != a[15]);

endmodule
