`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 18:24:19
// Design Name: 
// Module Name: DataMemory
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


module DataMemory #(
    parameter DATA_FILE = "../../../../Lab2.file/mem_clean.hex"
) (
    input        clk,
    input        mem_we,       // 写使能
    input  [31:0] addr,         // 内存地址
    input  [31:0] wdata,        // 写入数据
    output [31:0] rdata         // 读取数据
);
    // 定义内存大小（例如 1024 个 32 位字）
    reg [31:0] mem [0:1023];
    localparam DATA_BASE = 32'h10010000;
    wire [31:0] relative_addr = addr - DATA_BASE;
    wire [31:0] word_index = relative_addr[31:2];
    wire addr_in_range = (addr >= DATA_BASE) && (word_index < 32'd1024);
    
    // 初始化内存
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'b0;

`ifdef SYNTHESIS
        // 综合阶段：数据内容由脚本生成的字面量赋值提供（gen_uart_demo.py 生成）
`include "dmem_boot_init.vh"
`else
        // 仿真阶段：Load data memory from file (hex words, one per line)
        $readmemh(DATA_FILE, mem);
`endif
    end
    
    // 写操作（同步上升沿）
    always @(posedge clk) begin
        if (mem_we && addr_in_range) begin
            // 字节寻址转字索引
            mem[word_index] <= wdata;
        end
    end
    
    // 读操作（组合逻辑）
    assign rdata = addr_in_range ? mem[word_index] : 32'b0;
    
endmodule
