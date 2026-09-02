`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:02:21
// Design Name: 
// Module Name: InstructionMemory
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: RISC-V 指令存储器（IF 级取指）
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// InstructionMemory.v
module InstructionMemory #(
    parameter HEX_FILE = "../../../../Lab2.file/inst_code_clean.hex"
) (
    input  [31:0] addr,  // PC 地址
    output [31:0] instr   // 输出的 32 位指令
);
    // 1024 个 32 位存储单元，按字节寻址，指令按字对齐
    reg [31:0] mem [0:1023];

    // 初始化：默认全部填 NOP（addi x0, x0, 0），防止程序跑飞后取到 X 值
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h00000013;
        // 再从外部文件加载实际程序（去掉注释的干净 hex 文件）
        $readmemh(HEX_FILE, mem);
    end

    // 地址偏移处理：PC 起始地址为 0x00400000
    // 将 (addr - 0x00400000) >> 2 作为字索引
    wire [31:0] relative_addr = addr - 32'h00400000;
    assign instr = mem[relative_addr[31:2]];

endmodule

