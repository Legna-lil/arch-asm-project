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
    input        alu_zero,
    output       reg_we,
    output       mem_we,
    output       mem_to_reg,
    output [3:0] alu_ctrl,
    output       alu_src_sel,
    output       alu_src1_sel,
    output       branch_taken,
    output [2:0] imm_type,
    output       is_jal
);
    // decode
    wire is_add   = (opcode == `OP_R_TYPE) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    wire is_sub   = (opcode == `OP_R_TYPE) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
    wire is_addi  = (opcode == `OP_I_TYPE) && (funct3 == 3'b000);
    wire is_ori   = (opcode == `OP_I_TYPE) && (funct3 == 3'b110);
    wire is_slli  = (opcode == `OP_I_TYPE) && (funct3 == 3'b001);
    wire is_lw    = (opcode == `OP_LOAD)   && (funct3 == 3'b010);
    wire is_sw    = (opcode == `OP_STORE)  && (funct3 == 3'b010);
    wire is_beq   = (opcode == `OP_BRANCH) && (funct3 == 3'b000);
    wire is_blt   = (opcode == `OP_BRANCH) && (funct3 == 3'b100);
    wire is_bge   = (opcode == `OP_BRANCH) && (funct3 == 3'b101);
    wire is_slt   = (opcode == `OP_R_TYPE) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
    assign is_jal = (opcode == `OP_JAL);
    wire is_auipc = (opcode == `OP_AUIPC);

    // control signals
    assign reg_we       = is_add | is_sub | is_addi | is_ori | is_lw | is_slt | is_slli | is_auipc | is_jal;
    assign mem_we       = is_sw;
    assign mem_to_reg   = is_lw;
    assign alu_src_sel  = is_addi | is_ori | is_lw | is_sw | is_auipc | is_slli;
    assign alu_src1_sel = is_auipc;
    assign branch_taken = (is_beq && alu_zero) || (is_blt && !alu_zero) || (is_bge && alu_zero) || is_jal;
    assign imm_type     = (is_sw) ? 3'b001 :
                          (is_beq || is_blt || is_bge) ? 3'b010 :
                          (is_auipc) ? 3'b011 :
                          (is_jal) ? 3'b100 : 3'b000;

    // ALU control
    assign alu_ctrl = (is_add | is_addi | is_lw | is_sw | is_auipc) ? 4'b0000 :
                      (is_sub | is_beq) ? 4'b0001 :
                      is_ori  ? 4'b0010 :
                      (is_slt | is_blt | is_bge) ? 4'b0101 :
                      is_slli ? 4'b0110 :
                      4'b1111;

endmodule
