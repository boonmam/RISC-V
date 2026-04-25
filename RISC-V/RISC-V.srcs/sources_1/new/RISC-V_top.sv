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


module RISC_V_top(
    input clk,
    input rst,
    input [2:0] sw, //Inputs from the switches to control the LEDs
    output [7:0] LED,  // Output to the LEDs
    output [2:0] RGB  // Output to the RGB LEDs
  );

reg [7:0] LEDOut = 8'b00000000;
reg [2:0] RGBLED = 3'b001;

//Divide Down the Clock so LEDs are visible
reg [24:0] count_reg = 0;
reg clk1 = 0;
reg clk2 = 0;

always @(posedge clk) begin
  if (rst == 1'b1) begin
    count_reg <= 0;
    clk1 <= 0;
  end else begin
  if (count_reg == 3000000) begin
    count_reg <= 0;
    clk1 <= ~clk1;
  end else begin
    count_reg <= count_reg + 1'b1;
  end
  end
end
    
always @(posedge clk1, posedge rst)begin
  if(rst == 1'b1)begin
    LEDOut <= 8'b00000000;
    RGBLED <= 3'b000; //White Light - Red Blue Green
  end else begin
  
    if (clk2 == 1) begin
        RGBLED <= RGBLED + 1'b1;
        LEDOut <= LEDOut + 1'b1;
        clk2 = ~clk2;
    end
        else begin
        clk2 = ~clk2;
        end
    
    
      if(sw[0] == 1'b1)begin
        LEDOut <= LEDOut + 1'b1;
        RGBLED <= 3'b101; //Green
      end
      else if(sw[1] == 1'b1)begin
        LEDOut <= LEDOut - 1'b1;
        RGBLED <= 3'b110; //Red
        end
      else if(sw[2] == 1'b1)begin
        LEDOut <= LEDOut << 1'b1;
        RGBLED <= 3'b011; //Blue
      end
  end
end

assign LED = LEDOut;
assign RGB = RGBLED;

endmodule