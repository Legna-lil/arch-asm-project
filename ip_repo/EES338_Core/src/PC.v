`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 15:50:48
// Design Name: 
// Module Name: PC
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


module PC (
    input        clk,   // 时钟
    input        rst,   // 复位（高电平有效）
    input        en,    // 使能（一般置1）
    input  [31:0] npc,  // 下一跳地址
    output reg [31:0] pc // 当前指令地址
);
    always @(posedge clk) begin
        if (rst)
            pc <= 32'h00400000;  // RISC-V程序起始地址
        else if (en)
            pc <= npc;
        // 否则保持pc不变
    end
endmodule
