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
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// InstructionMemory.v
module InstructionMemory (
    input  [31:0] addr,  // 来自PC的地址
    output [31:0] instr   // 输出的32位指令
);
    // 1024个32位存储单元，地址按字节寻址，但指令按字对齐
    reg [31:0] mem [0:1023];
    
    // 初始化：从外部文件加载指令
    initial begin
        // 尝试加上相对源文件目录的路径或绝对路径
        // 在 Vivado 仿真中，直接写文件名通常在 behav/xsim 下找
        // $readmemh("inst_code.hex", mem);
        
        // 如果上面报错，你可以取消下面的注释并填入你的绝对路径用于调试
        $readmemh("../../../../Lab2.file/inst_code_clean.hex", mem);
    end
    
    // 地址偏移处理：PC起始地址为 0x00400000
    // addr的最低两位应该为0，我们将 (addr - 0x00400000) >> 2 作为索引
    wire [31:0] relative_addr = addr - 32'h00400000;
    assign instr = mem[relative_addr[31:2]];
    
endmodule
