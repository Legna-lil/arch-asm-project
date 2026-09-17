`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// DivUnit.v - 多周期除法/取余单元（加减交替法 = 非恢复余数法）
//
// 算法迁移自 Lab1 的 mult_alu.v 除法通路（OP=0 分支），只是把"卷积在一起"的
// 乘法/除法状态机拆成独立的除法单元，并按流水线需要加上 busy/done 握手。
//
// 算法（Lab1 原文）：
//   A_rem_tmp = {A_rem[BITS-1:0], C_reg[BITS-1]}      // 部分余数左移，把被除数最高位移入
//   if (A_rem >= 0) A_rem_tmp = A_rem_tmp - B_reg     // 余数非负 -> 减除数
//   else            A_rem_tmp = A_rem_tmp + B_reg     // 余数 为负 -> 加除数
//   C_reg     = {C_reg[BITS-2:0], (A_rem_tmp >= 0)}   // 新余数非负 -> 商位 1
//   迭代 BITS 次；最后若余数为负，再加一次除数补正（rem_corr）
//
// 有符号处理：先取 |被除数|、|除数| 按无符号算，再按符号补回（Lab1 做法）。
// 除零 / INT_MIN ÷ -1 两种特殊情况按 RISC-V 语义给结果，并把 div_of 置 1
//（Lab1 同样把这两种情况当作溢出，只是商/余数取值不同：Lab1 恒为 0，
//  这里按 RISC-V：除零 商=-1、余=被除数；INT_MIN/-1 商=INT_MIN、余=0）。
//
// 时序：start 有效后 EX 占用 BITS+2 拍（1 拍装载 + BITS 拍迭代 + 1 拍收尾），
//       done 在收尾那一拍为高，同时 quot/rem/div_of 有效。
//////////////////////////////////////////////////////////////////////////////////
module DivUnit #(
    parameter BITS = 32
)(
    input  wire            clk,
    input  wire            rst,
    input  wire            start,       // 单拍启动脉冲（IDLE 时才接受）
    input  wire            is_signed,   // 1=DIV/REM（有符号），0=DIVU/REMU
    input  wire [BITS-1:0] dividend,    // 被除数
    input  wire [BITS-1:0] divisor,     // 除数
    output wire            busy,        // 正在计算（不含收尾拍）
    output wire            done,        // 收尾拍：结果有效
    output wire            div_of,      // 溢出：除零 或 INT_MIN/(-1)（仅 done 拍有效）
    output wire [BITS-1:0] quot,        // 商
    output wire [BITS-1:0] rem          // 余数
);

    localparam [1:0] IDLE = 2'd0, CALC = 2'd1, FIN = 2'd2;

    reg [1:0]           state;
    reg [5:0]           cnt;
    reg signed [BITS:0] arem;       // 部分余数（多 1 位符号位，Lab1 的 A_rem）
    reg [BITS-1:0]      cquo;       // 被除数绝对值 -> 逐步变成商（Lab1 的 C_reg）
    reg [BITS-1:0]      bdiv;       // |除数|（Lab1 的 B_reg）
    reg [BITS-1:0]      dvd_r, dvs_r; // 启动时的操作数（特殊情况用）
    reg                 sgn_a, sgn_b;

    // ---- 迭代组合逻辑：2*部分余数 + 移入被除数最高位，然后 ±除数 ----
    wire signed [BITS:0] bdiv_s   = {1'b0, bdiv};
    wire signed [BITS:0] step_in  = {arem[BITS-1:0], cquo[BITS-1]};
    wire signed [BITS:0] step_nxt = (arem >= 0) ? (step_in - bdiv_s)
                                                : (step_in + bdiv_s);

    // ---- 收尾组合逻辑：负余数补正 + 符号补回 ----
    wire signed [BITS:0] rem_corr = (arem < 0) ? (arem + bdiv_s) : arem;
    wire [BITS-1:0] q_mag = cquo;
    wire [BITS-1:0] r_mag = rem_corr[BITS-1:0];
    wire [BITS-1:0] q_fix = (sgn_a ^ sgn_b) ? (~q_mag + 1'b1) : q_mag;
    wire [BITS-1:0] r_fix = (sgn_a)          ? (~r_mag + 1'b1) : r_mag;

    // ---- 特殊情况 ----
    wire div0   = (dvs_r == {BITS{1'b0}});
    wire ovfmin = is_signed && (dvd_r == {1'b1, {BITS-1{1'b0}}}) && (dvs_r == {BITS{1'b1}});

    assign busy   = (state != IDLE);
    assign done   = (state == FIN);
    assign div_of = done && (div0 | ovfmin);

    assign quot = !done        ? {BITS{1'b0}} :
                  div0         ? {BITS{1'b1}}              :  // 除零：商 = -1
                  ovfmin       ? {1'b1, {BITS-1{1'b0}}}    :  // INT_MIN/-1：商 = INT_MIN
                                 q_fix;
    assign rem  = !done        ? {BITS{1'b0}} :
                  div0         ? dvd_r                     :  // 除零：余 = 被除数
                  ovfmin       ? {BITS{1'b0}}              :  // INT_MIN/-1：余 = 0
                                 r_fix;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            cnt   <= 6'd0;
            arem  <= {BITS+1{1'b0}};
            cquo  <= {BITS{1'b0}};
            bdiv  <= {BITS{1'b0}};
            dvd_r <= {BITS{1'b0}};
            dvs_r <= {BITS{1'b0}};
            sgn_a <= 1'b0;
            sgn_b <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        sgn_a <= is_signed & dividend[BITS-1];
                        sgn_b <= is_signed & divisor[BITS-1];
                        dvd_r <= dividend;
                        dvs_r <= divisor;
                        // 取绝对值后按无符号做除法（有符号标志为 0 时保持原值）
                        cquo  <= (is_signed && dividend[BITS-1]) ? (~dividend + 1'b1) : dividend;
                        bdiv  <= (is_signed && divisor[BITS-1])  ? (~divisor  + 1'b1) : divisor;
                        arem  <= {BITS+1{1'b0}};
                        cnt   <= 6'd0;
                        state <= CALC;
                    end
                end
                CALC: begin
                    arem <= step_nxt;
                    cquo <= {cquo[BITS-2:0], (step_nxt >= 0)};
                    cnt  <= cnt + 6'd1;
                    if (cnt == BITS - 1) state <= FIN;
                end
                default: state <= IDLE;   // FIN：结果由组合逻辑给出，这里只回到空闲
            endcase
        end
    end

endmodule
