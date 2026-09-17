`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// SegDisplay.v - EES-338 板载 8 位数码管（段选/位选均高有效）扫描控制器
//
//  板载数码管结构（EES-338 手册 §6.4）：8 位分成两组，每组 4 位
//    组0：段选 A0..G0/DP0（8 根），位选 DN0_K1..K4（4 根）
//    组1：段选 A1..G1/DP1（8 根），位选 DN1_K1..K4（4 根）
//  同一组的 4 位共用段选线，靠位选线分时点亮（动态扫描）。本模块用 4 个相位
//  同时扫描两组，因此 8 位数字刷新一次 = 4 个相位。
//
//  CPU 侧只写"每一位显示什么"，刷新完全由硬件完成（不占用 CPU 时间）：
//    寄存器格式 = {mark, value[3:0]}   value = 0..15，其中 0xF = 空白（全灭）
//    mark = 1 → 该位小数点(DP)点亮，用于"高亮"正在比较/交换的两位
//  逻辑位编号 dig[0..7] 表示"从左到右"的第 0..7 位；上电默认全空白；
//  SEG_CTRL.bit0 = 1 使能显示。
//
//  ★ 模块物理排布/位选顺序由两个参数描述（只改参数，不改逻辑）：
//    GROUP_SWAP = 1 : 由 seg_grp0/dn0 驱动的模块在**右边**（组1 在左）
//                     → 组0 段选输出"右半边（逻辑位 4..7）"，组1 输出左半边
//    REVERSE_K  = 1 : 模块内 K1..K4 与"从左到右"**相反**（K1 是最右一位）
//                     → 输出模块内第 pos 位时选 dn bit (3-pos)
//    本板实测：GROUP_SWAP=1 且 REVERSE_K=1 时 dig0..dig7 才从左到右排列
//    （默认值即按实测设定；换板子/发现左右反了，把两个参数一起翻过来即可）
//////////////////////////////////////////////////////////////////////////////////
module SegDisplay #(
    parameter integer SCAN_DIV   = 16384,
    parameter integer GROUP_SWAP = 1,
    parameter integer REVERSE_K  = 1
)(
    input  wire       clk,
    input  wire       rst,        // 高有效
    // ---- CPU MMIO 写端口 ----
    input  wire       en,         // 全局显示使能（SEG_CTRL.bit0）
    input  wire       wr,         // 单拍写脉冲
    input  wire [2:0] wr_idx,     // 写第几位（逻辑序号 0..7，0 为最左）
    input  wire [4:0] wr_data,    // {mark(bit4), value[3:0]}
    // ---- 数码管引脚（组0）----
    output reg  [7:0] seg_grp0,   // {DP, G, F, E, D, C, B, A}
    output reg  [3:0] dn0,        // DN0_K1..K4（高有效，一位独热）
    // ---- 数码管引脚（组1）----
    output reg  [7:0] seg_grp1,
    output reg  [3:0] dn1
);

    // 8 位显示寄存器：{mark, value[3:0]}，dig[0] 在最左
    reg [4:0] dig [0:7];

    // 扫描相位计数器
    reg [1:0]  phase;
    reg [15:0] scan_cnt;
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            scan_cnt <= 16'd0;
            phase    <= 2'd0;
            for (i = 0; i < 8; i = i + 1)
                dig[i] <= 5'h0F;              // 上电全部空白
        end
        else begin
            if (wr) dig[wr_idx] <= wr_data;
            if (scan_cnt >= SCAN_DIV - 1) begin
                scan_cnt <= 16'd0;
                phase    <= phase + 2'd1;
            end
            else begin
                scan_cnt <= scan_cnt + 16'd1;
            end
        end
    end

    // ---------------- 相位 -> 逻辑位 / 位选 bit ----------------
    wire [1:0] pos  = phase;                              // 模块内位置：0 = 该模块最左
    wire [1:0] sbit = REVERSE_K ? (2'd3 - pos) : pos;     // 该位置对应的位选 bit

    wire [4:0] dig_L = dig[{1'b0, pos}];                  // 左半边 = 逻辑位 0..3
    wire [4:0] dig_R = dig[{1'b1, pos}];                  // 右半边 = 逻辑位 4..7

    // ---------------- 七段译码（1 = 点亮，共阴 + 位选高有效） ----------------
    function [6:0] seg7;              // 返回 {g,f,e,d,c,b,a}
        input [3:0] v;
        case (v)
            4'h0:    seg7 = 7'b0111111;
            4'h1:    seg7 = 7'b0000110;
            4'h2:    seg7 = 7'b1011011;
            4'h3:    seg7 = 7'b1001111;
            4'h4:    seg7 = 7'b1100110;
            4'h5:    seg7 = 7'b1101101;
            4'h6:    seg7 = 7'b1111101;
            4'h7:    seg7 = 7'b0000111;
            4'h8:    seg7 = 7'b1111111;
            4'h9:    seg7 = 7'b1101111;
            4'hA:    seg7 = 7'b1110111;
            4'hB:    seg7 = 7'b1111100;
            4'hC:    seg7 = 7'b0111001;
            4'hD:    seg7 = 7'b1011110;
            4'hE:    seg7 = 7'b1111001;
            default: seg7 = 7'b0000000;   // 4'hF = 空白
        endcase
    endfunction

    // 左/右半边段选（含小数点高亮）+ 位选（en=0 时整屏熄灭）
    wire [7:0] seg_L = en ? {dig_L[4], seg7(dig_L[3:0])} : 8'h00;
    wire [7:0] seg_R = en ? {dig_R[4], seg7(dig_R[3:0])} : 8'h00;
    wire [3:0] dn_s  = en ? (4'b0001 << sbit) : 4'b0000;

    // 段选/位选输出（寄存一拍，利于时序）
    always @(posedge clk) begin
        if (rst) begin
            seg_grp0 <= 8'h00;
            seg_grp1 <= 8'h00;
            dn0      <= 4'h0;
            dn1      <= 4'h0;
        end
        else begin
            // GROUP_SWAP=1：组0 那块模块在右边 → 组0 段选输出右半边
            seg_grp0 <= GROUP_SWAP ? seg_R : seg_L;
            seg_grp1 <= GROUP_SWAP ? seg_L : seg_R;
            dn0      <= dn_s;
            dn1      <= dn_s;
        end
    end

endmodule

