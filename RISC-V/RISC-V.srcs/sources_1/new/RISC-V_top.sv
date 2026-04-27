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


module RISC_V_top #(
    parameter int CLK_FREQ_HZ = 100_000_000

)(
    input clk,
    input rst,
    input [2:0] sw, //Inputs from the switches to control the LEDs
    output [7:0] LED,  // Output to the LEDs
    output [2:0] RGB,  // Output to the RGB LEDs
    output [7:0] CONN0 // Output to the PMOD OLED display
    );
    
assign RGB[2:0] = 3'b000; // Initialize RGB LEDs to off
assign CONN0[2] = 1'b0; // Initialize PMOD OLED control signal to low


PMOD_SERIAL  #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ))
    pmod_OLED(
    .clk(clk),
    .rst(rst),
    .rst_n(CONN0[5]), // Not used in this implementation
    .cs_n(CONN0[0]),  // Not used in this implementation
    .sclk(CONN0[3]),   // Not used in this implementation
    .mosi(CONN0[1]),   // Not used in this implementation
    .DCEN(CONN0[4]),   // Not used in this implementation
    .VCCEN(CONN0[6]),  // Not used in this implementation
    .PMODEN(CONN0[7])  // Not used in this implementation
);

assign LED = CONN0;

endmodule