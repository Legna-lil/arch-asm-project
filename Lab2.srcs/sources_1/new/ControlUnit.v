`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/29
// Design Name: 
// Module Name: ControlUnit
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

`include "macro.vh"

module ControlUnit (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output       reg_we,
    output       mem_we,
    output       mem_to_reg,
    output [3:0] alu_ctrl,
    output       alu_src_sel,
    output       alu_src1_sel,
    output [2:0] imm_type,
    output       is_jal,
    output       is_branch,
    output       is_arith      // 算术指令(ADD/SUB/ADDI)，用于溢出检测门控
);
    // decode
    wire is_add   = (opcode == `OP_R_TYPE) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    wire is_sub   = (opcode == `OP_R_TYPE) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
    wire is_and   = (opcode == `OP_R_TYPE) && (funct3 == 3'b111) && (funct7 == 7'b0000000);
    wire is_or    = (opcode == `OP_R_TYPE) && (funct3 == 3'b110) && (funct7 == 7'b0000000);
    wire is_xor   = (opcode == `OP_R_TYPE) && (funct3 == 3'b100) && (funct7 == 7'b0000000);
    wire is_slt   = (opcode == `OP_R_TYPE) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
    wire is_addi  = (opcode == `OP_I_TYPE) && (funct3 == 3'b000);
    wire is_andi  = (opcode == `OP_I_TYPE) && (funct3 == 3'b111);
    wire is_ori   = (opcode == `OP_I_TYPE) && (funct3 == 3'b110);
    wire is_slli  = (opcode == `OP_I_TYPE) && (funct3 == 3'b001);
    wire is_lw    = (opcode == `OP_LOAD)   && (funct3 == 3'b010);
    wire is_sw    = (opcode == `OP_STORE)  && (funct3 == 3'b010);
    wire is_beq   = (opcode == `OP_BRANCH) && (funct3 == 3'b000);
    wire is_bne   = (opcode == `OP_BRANCH) && (funct3 == 3'b001);
    wire is_blt   = (opcode == `OP_BRANCH) && (funct3 == 3'b100);
    wire is_bge   = (opcode == `OP_BRANCH) && (funct3 == 3'b101);
    assign is_jal = (opcode == `OP_JAL);
    wire is_auipc = (opcode == `OP_AUIPC);

    // control signals
    assign reg_we       = is_add | is_sub | is_and | is_or | is_xor | is_slt |
                          is_addi | is_andi | is_ori | is_slli |
                          is_lw | is_auipc | is_jal;
    assign mem_we       = is_sw;
    assign mem_to_reg   = is_lw;
    assign alu_src_sel  = is_addi | is_andi | is_ori | is_slli | is_lw | is_sw | is_auipc;
    assign alu_src1_sel = is_auipc;
    // 分支判定移至 EX 级：ID 级只输出分支类型标志
    assign is_branch = is_beq || is_bne || is_blt || is_bge;
    // 溢出检测门控：仅对有符号 ADD/SUB/ADDI 产生 overflow，避免地址计算(AUIPC/LW/SW)误报
    assign is_arith     = is_add | is_sub | is_addi;
    assign imm_type     = (is_sw) ? 3'b001 :
                          (is_beq || is_bne || is_blt || is_bge) ? 3'b010 :
                          (is_auipc) ? 3'b011 :
                          (is_jal) ? 3'b100 : 3'b000;

    // ALU control
    assign alu_ctrl = (is_add | is_addi | is_lw | is_sw | is_auipc) ? 4'b0000 :
                      (is_sub | is_beq | is_bne) ? 4'b0001 :
                      (is_ori | is_or) ? 4'b0010 :
                      (is_and | is_andi) ? 4'b0011 :
                      is_xor  ? 4'b0100 :
                      (is_slt | is_blt | is_bge) ? 4'b0101 :
                      is_slli ? 4'b0110 :
                      4'b1111;

endmodule
