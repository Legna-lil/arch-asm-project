`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ClockGen.v - 用 MMCME2_BASE 把板上 100MHz 转成 50MHz 逻辑时钟
//  (Artix-7, Vivado 会自动为 MMCM 生成 derived clock，无需额外约束)
//  之所以用 50MHz：CPU 关键路径在 100MHz 下有约 -2.3ns 违例，
//  降到 50MHz(20ns) 后时序即可收敛，保证上板稳定运行。
//////////////////////////////////////////////////////////////////////////////////
module ClockGen (
    input  wire clk_in,    // 100MHz（来自 SYS_CLK T5）
    output wire clk_out,   // 50MHz
    output wire locked
);
    wire clkfb;
    wire clk0;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.0),      // VCO = 100MHz x 10 = 1000MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.0),      // 输入 100MHz
        .CLKOUT0_DIVIDE_F   (20.0),      // 1000MHz / 20 = 50MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (1),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (1),
        .CLKOUT2_DUTY_CYCLE (0.5),
        .CLKOUT2_PHASE      (0.0),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT3_DUTY_CYCLE (0.5),
        .CLKOUT3_PHASE      (0.0),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT4_DUTY_CYCLE (0.5),
        .CLKOUT4_PHASE      (0.0),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT5_DUTY_CYCLE (0.5),
        .CLKOUT5_PHASE      (0.0),
        .CLKOUT6_DIVIDE     (1),
        .CLKOUT6_DUTY_CYCLE (0.5),
        .CLKOUT6_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        .CLKIN1         (clk_in),
        .CLKFBIN        (clkfb),
        .CLKFBOUT       (clkfb),
        .CLKFBOUTB      (),
        .CLKOUT0        (clk0),
        .CLKOUT0B       (),
        .CLKOUT1        (),
        .CLKOUT1B       (),
        .CLKOUT2        (),
        .CLKOUT2B       (),
        .CLKOUT3        (),
        .CLKOUT3B       (),
        .CLKOUT4        (),
        .CLKOUT5        (),
        .CLKOUT6        (),
        .LOCKED         (locked),
        .PWRDWN         (1'b0),
        .RST            (1'b0)
    );

    BUFG bufg_50m (.I(clk0), .O(clk_out));

endmodule
