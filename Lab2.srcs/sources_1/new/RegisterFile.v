`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:37:40
// Design Name: 
// Module Name: RegisterFile
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


// RegisterFile.v
module RegisterFile (
    input        clk,
    input        reg_we,        // 写使能
    input  [4:0] raddr1,        // 读端口1地址
    input  [4:0] raddr2,        // 读端口2地址
    input  [4:0] waddr,         // 写地址
    input  [31:0] wdata,        // 写数据
    output [31:0] rdata1,       // 读数据1
    output [31:0] rdata2        // 读数据2
);
    reg [31:0] regs [0:31];
    integer i;
    
    // 初始化所有寄存器为0，为了测试ADD，给x1, x2赋初值
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
        // regs[1] = 32'd5;   // x1 = 5
        // regs[2] = 32'd10;  // x2 = 10
    end
    
    // 写操作（同步，x0不可写）
    always @(posedge clk) begin
        if (reg_we && (waddr != 0))
            regs[waddr] <= wdata;
    end
    
    // 读操作（组合逻辑，x0读0）
    assign rdata1 = (raddr1 == 0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 0) ? 32'b0 : regs[raddr2];
    
endmodule
