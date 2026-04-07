`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: McCain Boonma
// Engineer: McCain Boonma
// 
// Create Date: 04/06/2026 08:07:37 PM
// Design Name: RISC-V FPGA Implementation
// Module Name: RISC-V_top
// Project Name: RISC-V FPGA Implementation
// Target Devices: Mimas A7 Mini FPGA Development Board
// Tool Versions: Vivado 2025.2
// Description: FPGA Implemnentation of a RISC-V processor. This module serves as the top-level design, integrating the processor core with input and output peripherals such as switches and LEDs.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module RISC-V_top(
    input clk,
    input rst,
    input [2:0] sw,     //Inputs from the switches to control the LEDs
    output [7:0] LED,   // Output to the LEDs
    output [2:0] RGB    // Output to the RGB LEDs
    );


logic [7:0] LED_reg = 8'b0000_0001; // Register to hold the current state of the LEDs
logic [2:0] RGB_reg = 3'b001; // Register to hold the current state of the RGB LEDs


assign LED = LED_reg;
assign RGB = RGB_reg;


endmodule