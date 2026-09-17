`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// FlagReg.v - 状态标志寄存器（SF/ZF/CF/OF/PF + 粘滞溢出位 + 溢出计数）
//
// 迁移自 Lab1 的 alu.v "标志位寄存"做法：Lab1 的 ALU 在 done 那一拍把
//   S/SF/CF/ZF/OF/PF 一起锁存进寄存器，供后续读取；这里把这套"标志位处理
//   方法"搬进流水线 CPU：每条**算术类指令**在 EX 级退役的那一拍刷新标志。
//
// 与 Lab1 的差别（为流水线/上板演示做的增强，见文档 §8.5）：
//   ① 增加 OF_STICKY（粘滞溢出位）：一旦溢出就保持为 1，直到 clrflags，
//      这样程序/MMIO 在之后任意时刻都能查到"曾经溢出过"；
//   ② 增加 of_count：溢出累计次数（Lab1 只有单次标志）；
//   ③ 只有算术类指令（ADD/SUB/ADDI/MUL/DIV/REM）会刷新标志 ——
//      逻辑/移位/访存/地址计算指令不刷新，避免 lw/sw/auipc 把 OF 冲掉。
//
// flags 位定义（CPU_FLAGS 寄存器 0x1000_0300）：
//   [0] SF        结果符号位
//   [1] ZF        结果为零
//   [2] CF        ADD 进位 / SUB 借位
//   [3] OF        最近一次算术运算的溢出
//   [4] OF_STICKY 粘滞溢出（曾溢出过，clrflags 才清）
//   [5] PF        结果偶校验 ~^result
//   [6] SEEN      复位后是否执行过算术类指令
//   [7] 保留 0
//////////////////////////////////////////////////////////////////////////////////
module FlagReg (
    input  wire        clk,
    input  wire        rst,       // 高有效
    input  wire        en,        // 本拍有一条算术类指令在 EX 级退役
    input  wire        clr,       // clrflags 指令：清全部标志（优先于 en）
    input  wire        sf,
    input  wire        zf,
    input  wire        cf,
    input  wire        ovf,
    input  wire        pf,
    output reg  [7:0]  flags,
    output reg  [31:0] of_count
);

    always @(posedge clk) begin
        if (rst) begin
            flags    <= 8'd0;
            of_count <= 32'd0;
        end
        else if (clr) begin
            flags    <= 8'd0;
            of_count <= 32'd0;
        end
        else if (en) begin
            flags[0]  <= sf;
            flags[1]  <= zf;
            flags[2]  <= cf;
            flags[3]  <= ovf;
            flags[4]  <= flags[4] | ovf;          // 粘滞：一旦置 1 就不再自动清 0
            flags[5]  <= pf;
            flags[6]  <= 1'b1;                    // 已经执行过算术指令
            of_count  <= of_count + {31'd0, ovf}; // 溢出累计次数
        end
    end

endmodule
