`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.03.2026 18:49:21
// Design Name: 
// Module Name: counter_task3
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


module counter_task3 (
  input  logic clk_i,
  input  logic rstn_i,

  output logic [7:0] counter1_o,
  output logic [7:0] counter2_o
);

  (* MARK_DEBUG = "TRUE" *) logic [7:0] counter1_ff;
  (* MARK_DEBUG = "TRUE" *) logic [7:0] counter2_ff;

  always_ff @( posedge clk_i or negedge rstn_i  ) begin
    if (~rstn_i)
      counter1_ff <= '0;
    else
      counter1_ff <= counter1_ff + 1;
  end

  always_ff @( posedge clk_i or negedge rstn_i  ) begin
    if (~rstn_i)
      counter2_ff <= '0;
    else if (counter1_ff >= 8'hFF)
      counter2_ff <= counter2_ff + 1;
  end

endmodule

