`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 17:17:38
// Design Name: 
// Module Name: tb_ImmGen
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


// tb_ImmGen.v
module tb_ImmGen;
    reg [31:0] instr;
    reg [2:0] imm_type;
    wire [31:0] imm;
    
    ImmediateGenerator uut (.instr(instr), .imm_type(imm_type), .imm(imm));
    
    initial begin
        // I-type: addi x1, x0, 0x80
        // 编码: imm[11:0]=0x080, rs1=0, funct3=000, rd=1, opcode=0010011
        instr = 32'h08000093; imm_type = 3'b000; #10 $display("I imm = %h", imm); // 应显示0x00000080
        
        // S-type: sw x1, 0x80(x0)
        instr = 32'h08102023; imm_type = 3'b001; #10 $display("S imm = %h", imm); // 应显示0x00000080
        
        // B-type: beq x0, x0, 偏移8（即目标地址 = PC+8）
        instr = 32'h00000463; imm_type = 3'b010; #10 $display("B imm = %h", imm); // 应显示0x00000008
        $finish;
    end
endmodule
