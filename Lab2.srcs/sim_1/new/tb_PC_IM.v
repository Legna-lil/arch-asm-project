`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:03:08
// Design Name: 
// Module Name: tb_PC_IM
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


// tb_PC_IM.v
module tb_PC_IM;
    reg clk, rst;
    wire [31:0] pc, instr;
    
    // 时钟生成
    always #5 clk = ~clk;
    
    // 实例化PC
    PC u_pc (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .npc(pc + 32'd4),   // 简单顺序执行，每次+4
        .pc(pc)
    );
    
    // 实例化指令存储器
    InstructionMemory u_im (
        .addr(pc),
        .instr(instr)
    );
    
    initial begin
        clk = 0;
        rst = 1;
        #10 rst = 0;   // 释放复位
        #200 $finish;
    end
    
    // 监视输出
    initial begin
        $monitor("time=%0t, pc=%h, instr=%h", $time, pc, instr);
    end
endmodule
