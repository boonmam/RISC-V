`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/18/2026 01:32:19 PM
// Design Name: 
// Module Name: RISC-V_testbench
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


module RISC_V_testbench;

    reg clk;
    reg rst;

    reg [7:0] LED;
    reg [2:0] RGB;

    RISC_V_top uut (
        .clk(clk),
        .rst(rst),
        .sw(3'b000),
        .LED(LED),
        .RGB(RGB)
    );

    always #5 clk = ~clk; // Generate a clock signal with a period of 10ns (100MHz)

    initial begin
        // Initialize Inputs
        clk = 0;
        rst = 1; // Start with reset active

        // Wait for a few clock cycles
        #50;

        rst = 0; // Deactivate reset

        // Wait for some time to observe the behavior of the LEDs
        #500;

        $finish; // End the simulation
    end
    
    
endmodule