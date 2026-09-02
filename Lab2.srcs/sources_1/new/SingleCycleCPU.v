`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 17:49:48
// Design Name: 
// Module Name: SingleCycleCPU
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


module SingleCycleCPU(
    input clk,
    input rst
    );
    
    // Wires for components
    wire [31:0] curr_pc;
    wire [31:0] next_pc;
    wire [31:0] instruction;
    
    wire [4:0]  rs1 = instruction[19:15];
    wire [4:0]  rs2 = instruction[24:20];
    wire [4:0]  rd  = instruction[11:7];
    wire [6:0]  opcode = instruction[6:0];
    wire [2:0]  funct3 = instruction[14:12];
    wire [6:0]  funct7 = instruction[31:25];
    
    wire [31:0] rdata1, rdata2;
    wire [31:0] alu_result;
    wire [31:0] mem_rdata;
    wire alu_zero;
    
    // Control Signals
    wire reg_we;
    wire mem_we;
    wire mem_to_reg;
    wire [3:0] alu_ctrl;
    wire is_branch;
    wire is_jal;
    wire [31:0] imm_out;
    wire [2:0]  imm_type;
    
    // --- PC ---
    wire [31:0] pc_plus_4 = curr_pc + 4;
    wire [31:0] pc_branch = curr_pc + imm_out;
    // 分支判定：JAL 无条件跳转；BEQ/BNE/BLT/BGE 由 ALU 结果决定
    // beq(f3=000): zero ; bne(f3=001): !zero ; blt(f3=100): !zero ; bge(f3=101): zero
    wire branch_taken = is_jal ||
                        (is_branch && ((funct3 == 3'b000 && alu_zero) ||
                                       (funct3 == 3'b001 && !alu_zero) ||
                                       (funct3 == 3'b100 && !alu_zero) ||
                                       (funct3 == 3'b101 && alu_zero)));
    assign next_pc = branch_taken ? pc_branch : pc_plus_4;
    
    PC pc_inst (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .npc(next_pc),
        .pc(curr_pc)
    );
    
    // --- Instruction Memory ---
    InstructionMemory im_inst (
        .addr(curr_pc),
        .instr(instruction)
    );
    
    // --- Register File ---
    wire [31:0] rf_wdata = is_jal ? pc_plus_4 : (mem_to_reg ? mem_rdata : alu_result);
    RegisterFile rf_inst (
        .clk(clk),
        .reg_we(reg_we),
        .raddr1(rs1),
        .raddr2(rs2),
        .waddr(rd),
        .wdata(rf_wdata), 
        .rdata1(rdata1),
        .rdata2(rdata2)
    );
    
    // --- ALU ---
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire alu_src_sel; // 0: rdata2, 1: immediate
    wire alu_src1_sel; // 0: rdata1, 1: pc
    
    assign alu_src1 = alu_src1_sel ? curr_pc : rdata1;
    assign alu_src2 = alu_src_sel ? imm_out : rdata2;
    
    ALU alu_inst (
        .src1(alu_src1),
        .src2(alu_src2),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(alu_zero)
    );
    
    // --- Data Memory ---
    DataMemory dm_inst (
        .clk(clk),
        .mem_we(mem_we),
        .addr(alu_result), // ALU 计算出的地址
        .wdata(rdata2),    // 存入的数据
        .rdata(mem_rdata)
    );
    
    // --- Immediate Generator ---
    ImmediateGenerator imm_gen_inst (
        .instr(instruction),
        .imm_type(imm_type),
        .imm(imm_out)
    );
    
    // --- Control Unit ---
    ControlUnit ctrl_inst (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .reg_we(reg_we),
        .mem_we(mem_we),
        .mem_to_reg(mem_to_reg),
        .alu_ctrl(alu_ctrl),
        .alu_src_sel(alu_src_sel),
        .alu_src1_sel(alu_src1_sel),
        .imm_type(imm_type),
        .is_jal(is_jal),
        .is_branch(is_branch)
    );

endmodule




