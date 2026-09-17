`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EES338Top.v - EES-338 (Artix-7 XC7A35T-1CSG324C) 板上 SoC 顶层
//
// 五级流水线 CPU + 存储器映射 UART（TX/RX 全功能）演示。
//
// 板级引脚（对照 EES-338 User Manual v1.0）：
//   SYS_CLK : T5    板上 100 MHz 时钟（进 MMCM，内部转 50MHz 逻辑时钟）
//   UART_TX : N5    FPGA -> CP2102 -> PC（本模块输出）
//   UART_RX : T4    PC   -> CP2102 -> FPGA（本模块输入）
//   RST_BTN : P15   复位按键（低有效，可选；若不用请绑 1'b1）
//   LED0    : K2    心跳灯（可选）
//
// 存储器映射（CPU 仅用 lw/sw 访问，无需新增指令）：
//   0x0040_0000 ~         指令 ROM（复位后 PC=0x00400000）
//   0x1001_0000 ~ 0x10010FFF  数据 RAM（DataMemory 内部）
//   0x1000_0000            UART_DATA  : sw=把低8位送入发送器
//                                       lw=读回最近 RX 字节（并清除可读标志）
//   0x1000_0004            UART_STATUS: bit0=TX_BUSY  bit1=RX_READY
//
// 参数：
//   HEX_FILE / DATA_FILE 指定仿真加载的程序与数据 hex 文件
//   BAUD_DIV             每 bit 时钟数 = 50MHz/波特率（115200 => 434）
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
// EES338Top.v - EES-338 (Artix-7 XC7A35T-1CSG324C) 板上 SoC 顶层
//
// 五级流水线 CPU + 存储器映射外设（USB-UART / 蓝牙 BLE / LCD）演示。
//
// 本文件现在只做"板级胶水"：MMCM 分频 + 上电/按键复位 + EES338_Core + LED 心跳。
// 真正的 CPU 与外设都在 EES338_Core.v 里（该文件可被 Vivado 封装成 IP 核）。
//
// 板级引脚（对照 EES-338 User Manual v1.0）：
//   SYS_CLK : T5    板上 100 MHz 时钟（进 MMCM，内部转 50MHz 逻辑时钟）
//   UART_TX : N5    手册标 UART_RX=T4 / UART_TX=N5，实测方向相反（见 EES338.xdc）
//   UART_RX : T4
//   BT_TX   : L3    蓝牙 BLE-CC41-A 模块 TX -> FPGA 输入（§11）
//   BT_RX   : N2    蓝牙模块 RX <- FPGA 输出
//   LCD     : §13  JLX128128G-81202 / ST7571 8080 并口（D0-D7/WR#/RD#/CS#/RS/RST#）
//   RST_BTN : P15   复位按键（低有效，可选）
//   LED0    : K2    心跳灯（可选）
//
// 存储器映射（CPU 仅用 lw/sw 访问，无需新增指令）见 PeriphMMIO.v
//
// 参数：
//   HEX_FILE / DATA_FILE 指定仿真加载的程序与数据 hex 文件
//   BAUD_DIV             每 bit 时钟数 = 50MHz/波特率（115200 => 434）
//   BAUD_DIV_BT          蓝牙每 bit 时钟数（9600 => 5208）
//////////////////////////////////////////////////////////////////////////////////
module EES338Top #(
    parameter HEX_FILE     = "../../../../Lab2.file/uart_hello.hex",
    parameter DATA_FILE    = "../../../../Lab2.file/uart_hello_mem.hex",
    parameter integer BAUD_DIV    = 434,       // 115200 @50MHz
    parameter integer BAUD_DIV_BT = 5208,      // 9600  @50MHz（BLE 缺省）
    parameter integer SEG_SCAN_DIV = 16384,    // 数码管扫描相位长度（≈760Hz 刷新）
    parameter integer SEG_GROUP_SWAP = 1,      // 数码管：组0 模块在右边（本板实测）
    parameter integer SEG_REVERSE_K  = 1,      // 数码管：模块内 K1..K4 与左→右相反（本板实测）
    parameter integer TIMER_DELAY  = 20000000, // 硬件延时长度（0.4s @50MHz）
    parameter integer BT_RST_CYCLES = 1000000  // 蓝牙上电复位脉宽（20ms @50MHz）
)(
    input  wire sys_clk,     // T5 100MHz
    input  wire rst_btn,     // P15 复位按键（低有效）
    input  wire uart_rxd,    // T4 实测输入（手册标 N5）
    output wire uart_txd,    // N5 实测输出（手册标 T4）
    input  wire bt_rxd,      // L3 蓝牙模块 TX -> FPGA
    output wire bt_txd,      // N2 FPGA -> 蓝牙模块 RX
    // ---- 蓝牙模块控制脚（手册 §11 未列出；见官方 lab08 蓝牙工程）----
    output wire bt_pw_on,        // D18 模块电源（1=上电）
    output wire bt_master_slave, // C16 模式选择（1=从模式，手机可连接）
    output wire bt_sw_hw,        // H15
    output wire bt_sw,           // E18
    output wire bt_rst_n,        // M2  模块复位（低有效）
    // ---- LCD 8080 并口（数据线双向）----
    inout  wire [7:0] lcd_d,      // LCD_D0..D7（写时 FPGA 驱动，读时 LCD 驱动）
    output wire       lcd_wr_n,   // LCD_WR#
    output wire       lcd_rd_n,   // LCD_RD#（恒 1）
    output wire       lcd_cs_n,   // LCD_CS#
    output wire       lcd_rs,     // LCD_RS
    output wire       lcd_rst_n,  // LCD_RST#
    // ---- 8 位数码管（两组各 4 位，动态扫描）----
    output wire [7:0] seg_grp0,   // 组0 段选 {DP,G,F,E,D,C,B,A}
    output wire [3:0] dn0,        // 组0 位选 DN0_K1..K4
    output wire [7:0] seg_grp1,   // 组1 段选
    output wire [3:0] dn1,        // 组1 位选 DN1_K1..K4
    output wire led0         // K2 心跳灯
);

    // ==================== 时钟：100MHz -> 50MHz ====================
    wire cpu_clk;
    wire mmcm_locked;
    ClockGen u_clkgen (
        .clk_in (sys_clk),
        .clk_out(cpu_clk),
        .locked (mmcm_locked)
    );

    // ==================== 上电/按键复位 ====================
    // 上电后 GSR 释放，寄存器从 0 开始计数，自动复位约 255 拍，
    // 保证下载 bitstream 后不按键 CPU 也能从 0x00400000 正确启动。
    reg [9:0] rst_cnt = 10'd0;     // 仿真初值 0（综合后为寄存器 INIT 值）
    wire pow_rst = (rst_cnt < 10'd255);
    always @(posedge cpu_clk) begin
        if (rst_cnt != 10'h3FF)
            rst_cnt <= rst_cnt + 1'b1;
    end
    wire cpu_rst = pow_rst | (~rst_btn) | (~mmcm_locked);  // MMCM 未锁定也复位

    // ==================== SoC 内核（CPU + MMIO 外设） ====================
    // 顶层不再直接例化 UART/LCD，全部收进 EES338_Core（便于封装成 IP 核）。
    // 串口输入先做两级同步，再进内核（内核内部不再做跨时钟域处理）。
    reg rxd_s1 = 1'b1, rxd_s2 = 1'b1;
    reg btx_s1 = 1'b1, btx_s2 = 1'b1;
    always @(posedge cpu_clk) begin
        rxd_s1  <= uart_rxd;
        rxd_s2  <= rxd_s1;
        btx_s1  <= bt_rxd;
        btx_s2  <= btx_s1;
    end

    EES338_Core #(
        .HEX_FILE    (HEX_FILE),
        .DATA_FILE   (DATA_FILE),
        .BAUD_DIV    (BAUD_DIV),
        .BAUD_DIV_BT (BAUD_DIV_BT),
        .SEG_SCAN_DIV(SEG_SCAN_DIV),
        .SEG_GROUP_SWAP(SEG_GROUP_SWAP),
        .SEG_REVERSE_K(SEG_REVERSE_K),
        .TIMER_DELAY (TIMER_DELAY),
        .BT_RST_CYCLES(BT_RST_CYCLES)
    ) u_core (
        .clk          (cpu_clk),
        .rst          (cpu_rst),
        .uart_rxd     (rxd_s2),
        .uart_txd     (uart_txd),
        .bt_rxd       (btx_s2),
        .bt_txd       (bt_txd),
        .bt_pw_on        (bt_pw_on),
        .bt_master_slave (bt_master_slave),
        .bt_sw_hw        (bt_sw_hw),
        .bt_sw           (bt_sw),
        .bt_rst_n        (bt_rst_n),
        .lcd_d        (lcd_d),
        .lcd_wr_n     (lcd_wr_n),
        .lcd_rd_n     (lcd_rd_n),
        .lcd_cs_n     (lcd_cs_n),
        .lcd_rs       (lcd_rs),
        .lcd_rst_n    (lcd_rst_n),
        .seg_grp0     (seg_grp0),
        .dn0          (dn0),
        .seg_grp1     (seg_grp1),
        .dn1          (dn1)
    );

    // ==================== LED 心跳（可选，K2） ====================
    reg [24:0] led_cnt = 25'd0;
    always @(posedge cpu_clk) begin
        if (cpu_rst) led_cnt <= 25'd0;
        else         led_cnt <= led_cnt + 1'b1;
    end
    assign led0 = led_cnt[24];      // 50MHz/2^25 ≈ 0.7 Hz 闪烁，肉眼可见

endmodule
