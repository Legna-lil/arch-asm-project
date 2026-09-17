`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// SimpleTimer.v - 一次性的"硬件延时"外设
//
//  为什么需要它：数码管演示程序需要在每次比较/交换后停顿一会儿让人看清，
//  如果用软件空循环做延时，延时长度就**写死在程序里**，仿真时要跑几秒钟的
//  仿真时间（几亿个周期）根本跑不动。把它做成硬件参数之后：
//    * 上板：DELAY_CYCLES = 20_000_000 → 50MHz 下 0.4s
//    * 仿真：DELAY_CYCLES = 64        → 同一份程序，仿真瞬间跑完
//  也就是说"仿真验证的程序"和"烧进板子的程序"是同一份机器码，只是外部延时参数不同。
//
//  用法（MMIO）：
//    w TIMER_CTRL.bit0 = 1  → 重装计数并开始
//    r TIMER_VALUE          → 剩余拍数，读到 0 表示延时结束
//////////////////////////////////////////////////////////////////////////////////
module SimpleTimer #(
    parameter integer DELAY_CYCLES = 20000000
)(
    input  wire        clk,
    input  wire        rst,        // 高有效
    input  wire        start,      // 单拍脉冲：重装并开始计时
    output reg  [31:0] value,      // 剩余拍数（0 = 已到时间）
    output wire        busy
);

    always @(posedge clk) begin
        if (rst) begin
            value <= 32'd0;
        end
        else if (start) begin
            value <= DELAY_CYCLES;
        end
        else if (value != 32'd0) begin
            value <= value - 32'd1;
        end
    end

    assign busy = (value != 32'd0);

endmodule
