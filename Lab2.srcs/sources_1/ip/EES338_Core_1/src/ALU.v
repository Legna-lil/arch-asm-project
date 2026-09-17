`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:57:54
// Design Name: 
// Module Name: ALU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 算术逻辑单元（组合逻辑）
//              ADD/SUB/AND/OR/XOR/SLT/SLL + 有符号加减溢出检测
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ALU.v
// 标志位生成方法迁移自 Lab1 的 alu.v（见文件头说明）：
//   OF：ADD/SUB 符号判定、MUL 用 64 位积是否能被低 32 位符号扩展表示判定
//   CF：ADD 取进位、SUB 取借位；逻辑/移位运算 CF=OF=0
//   SF/ZF/PF：结果符号位 / 全零 / 偶校验 ~^result
//
// alu_ctrl 编码：
//   0000 ADD   0001 SUB   0010 OR   0011 AND
//   0100 XOR   0101 SLT   0110 SLL
//   0111 MUL(低32)  1000 MULH  1001 MULHU  1010 MULHSU
//   1011 DIV   1100 DIVU  1101 REM  1110 REMU（结果由 DivUnit 给出）
//   1111 无效（空操作）
module ALU (
    input  [31:0] src1,
    input  [31:0] src2,
    input  [3:0]  alu_ctrl,      // 运算控制信号
    output reg [31:0] result,
    output wire zero,            // 结果为零标志
    output wire sign,            // SF：结果符号位
    output reg  carry,           // CF：ADD 进位 / SUB 借位，其它运算 0
    output wire parity,          // PF：结果偶校验 ~^result（与 Lab1 一致）
    output reg  overflow         // 有符号溢出标志（ADD/SUB/MUL 有意义，仅对算术指令门控）
);
    // ---- 33 位加减：多出的 1 位就是进位/借位 ----
    wire [32:0] add_res = {1'b0, src1} + {1'b0, src2};
    wire [32:0] sub_res = {1'b0, src1} - {1'b0, src2};

    // ---- 64 位乘法（三种符号组合，综合出 DSP48）----
    wire signed [63:0] mul_ss = $signed(src1) * $signed(src2);          // MUL / MULH
    wire        [63:0] mul_uu = src1 * src2;                            // MULHU
    wire signed [63:0] mul_su = $signed(src1) * $signed({1'b0, src2});  // MULHSU

    always @(*) begin
        result   = 32'b0;
        carry    = 1'b0;
        overflow = 1'b0;
        case (alu_ctrl)
            4'b0000: begin  // ADD
                result = add_res[31:0];
                carry  = add_res[32];                                  // 无符号进位
                // 两个操作数符号相同，结果符号不同 => 溢出
                overflow = (src1[31] == src2[31]) && (result[31] != src1[31]);
            end
            4'b0001: begin  // SUB
                result = sub_res[31:0];
                carry  = sub_res[32];                                  // 借位：src1 < src2 时 = 1
                // 两个操作数符号不同，结果符号与第一个操作数不同 => 溢出
                overflow = (src1[31] != src2[31]) && (result[31] != src1[31]);
            end
            4'b0010: result = src1 | src2;   // OR
            4'b0011: result = src1 & src2;   // AND
            4'b0100: result = src1 ^ src2;   // XOR
            4'b0101: result = ($signed(src1) < $signed(src2)) ? 32'b1 : 32'b0; // SLT
            4'b0110: result = src1 << src2[4:0]; // SLL
            4'b0111: begin  // MUL：取 64 位积的低 32 位
                result = mul_ss[31:0];
                // Lab1 判据：64 位积不能被低 32 位的符号扩展表示 => 溢出
                overflow = (mul_ss[63:32] != {32{mul_ss[31]}});
            end
            4'b1000: result = mul_ss[63:32]; // MULH  ：有符号×有符号 取高 32 位
            4'b1001: result = mul_uu[63:32]; // MULHU ：无符号×无符号 取高 32 位
            4'b1010: result = mul_su[63:32]; // MULHSU：有符号×无符号 取高 32 位
            // 1011~1110：DIV/DIVU/REM/REMU，结果与溢出标志由 DivUnit 给出（见 PipelineCPU.v）
            default: result = 32'b0;         // 1111 及保留：空操作
        endcase
    end

    assign zero   = (result == 32'b0);
    assign sign   = result[31];
    assign parity = ~^result;            // 32 位偶校验（Lab1 同）

endmodule

