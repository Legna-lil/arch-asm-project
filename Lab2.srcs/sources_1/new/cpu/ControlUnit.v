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
    output       is_arith,      // 算术指令(ADD/SUB/ADDI)，用于溢出检测门控
    // ---- 以下为"Lab1 溢出标志位迁移"新增：M 扩展 + 标志寄存器指令 ----
    output       is_mul,        // M 扩展乘法（单周期）：MUL/MULH/MULHU/MULHSU
    output       is_div,        // M 扩展除法/取余（多周期）：DIV/DIVU/REM/REMU
    output       is_div_signed, // 1=DIV/REM（有符号），0=DIVU/REMU（无符号）
    output       is_div_rem,    // 1=REM/REMU（取余），0=DIV/DIVU（取商）
    output       is_rdflags,    // 自定义(rdflags)：把标志寄存器读到 rd
    output       is_clrflags,   // 自定义(clrflags)：清标志寄存器
    output       upd_flags      // 会刷新标志寄存器的指令（算术类，见下）
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

    // ---- M 扩展（RV32M 标准编码：opcode=0110011, funct7=0000001）----
    wire is_m_ext = (opcode == `OP_R_TYPE) && (funct7 == 7'b0000001);
    wire d_mul    = is_m_ext && (funct3 == 3'b000);   // MUL   低 32 位
    wire d_mulh   = is_m_ext && (funct3 == 3'b001);   // MULH  有符号×有符号 高 32 位
    wire d_mulhsu = is_m_ext && (funct3 == 3'b010);   // MULHSU 有符号×无符号 高 32 位
    wire d_mulhu  = is_m_ext && (funct3 == 3'b011);   // MULHU 无符号×无符号 高 32 位
    wire d_div    = is_m_ext && (funct3 == 3'b100);   // DIV
    wire d_divu   = is_m_ext && (funct3 == 3'b101);   // DIVU
    wire d_rem    = is_m_ext && (funct3 == 3'b110);   // REM
    wire d_remu   = is_m_ext && (funct3 == 3'b111);   // REMU

    assign is_mul        = d_mul | d_mulh | d_mulhsu | d_mulhu;
    assign is_div        = d_div | d_divu | d_rem | d_remu;
    assign is_div_signed = d_div | d_rem;
    assign is_div_rem    = d_rem | d_remu;

    // ---- 自定义标志指令（custom-0）----
    wire d_rdflags  = (opcode == `OP_CUSTOM0) && (funct3 == 3'b001);
    wire d_clrflags = (opcode == `OP_CUSTOM0) && (funct3 == 3'b000);
    assign is_rdflags  = d_rdflags;
    assign is_clrflags = d_clrflags;

    // control signals
    assign reg_we       = is_add | is_sub | is_and | is_or | is_xor | is_slt |
                          is_addi | is_andi | is_ori | is_slli |
                          is_lw | is_auipc | is_jal |
                          is_mul | is_div | is_rdflags;      // 乘法/除法/读标志都写 rd
    assign mem_we       = is_sw;
    assign mem_to_reg   = is_lw;
    assign alu_src_sel  = is_addi | is_andi | is_ori | is_slli | is_lw | is_sw | is_auipc;
    assign alu_src1_sel = is_auipc;
    // 分支判定移至 EX 级：ID 级只输出分支类型标志
    assign is_branch = is_beq || is_bne || is_blt || is_bge;
    // 溢出检测门控：仅对有符号 ADD/SUB/ADDI 产生 overflow，避免地址计算(AUIPC/LW/SW)误报
    assign is_arith    = is_add | is_sub | is_addi;
    // 标志寄存器刷新门控：只有"算术类"指令刷新 SF/ZF/CF/OF/PF 与溢出计数。
    // 逻辑/移位/访存/地址计算指令一律不刷新，避免 lw/sw/auipc/andi 把 OF 冲掉
    //（Lab1 的 ALU 是每条指令都刷新 SF/ZF/PF，这里为流水线场景做了收敛，见文档 §8.5）
    assign upd_flags   = is_arith | is_mul | is_div;
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
                      d_mul   ? 4'b0111 :   // MUL
                      d_mulh  ? 4'b1000 :   // MULH
                      d_mulhu ? 4'b1001 :   // MULHU
                      d_mulhsu? 4'b1010 :   // MULHSU
                      d_div   ? 4'b1011 :   // DIV   （结果由 DivUnit 给出）
                      d_divu  ? 4'b1100 :   // DIVU
                      d_rem   ? 4'b1101 :   // REM
                      d_remu  ? 4'b1110 :   // REMU
                      4'b1111;

endmodule
