`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.03.2026 20:11:20
// Design Name: 
// Module Name: wrapper
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


module wrapper(
    input  logic CLK100MHZ,
    input  logic CPU_RESETN,
    output logic [15:0] LED,
    input  logic[1:0] SW
);

    `ifdef TASK1
    counter_task1 u_cnt_1 (
        .clk_i(CLK100MHZ),
        .rstn_i(CPU_RESETN),
        .counter_o(LED)
    );
    `endif
    
    `ifdef TASK2
    counter_task2 u_cnt_2 (
        .clk_i(CLK100MHZ),
        .rstn_i(CPU_RESETN),
        .counter_o(LED),
        .en_i(SW[0])
    );
    `endif

    `ifdef TASK3
    counter_task3 u_cnt_3 (
        .clk_i(CLK100MHZ),
        .rstn_i(CPU_RESETN),
        .counter1_o(LED[7:0]),
        .counter2_o(LED[15:0])
    );
    `endif

    `define TASK4
    `ifdef TASK4
    logic [7:0] counter1_max;
    logic [7:0] counter2_max;
    vio_0 vio_0_inst (
        .clk(CLK100MHZ),
        .probe_in0(LED[7:0]),
        .probe_in1(LED[15:8]),
        .probe_out0(counter1_max),
        .probe_out1(counter2_max)
    );

    counter_task4 u_cnt_4 (
        .clk_i(CLK100MHZ),
        .rstn_i(CPU_RESETN),
        .counter1_max_i(counter1_max),
        .counter2_max_i(counter2_max),
        .counter1_o(LED[7:0]),
        .counter2_o(LED[15:8])
    );
    `endif

endmodule
