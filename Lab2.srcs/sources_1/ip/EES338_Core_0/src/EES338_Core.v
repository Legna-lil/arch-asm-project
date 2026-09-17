`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EES338_Core.v - EES-338 SoC 内核（可封装为 IP 核的部分）
//
//  组成：五级流水线 RV32I CPU + 存储器映射外设集合 PeriphMMIO（UART / 蓝牙 / LCD）
//  输入一个已经稳定的逻辑时钟（板级顶层用 MMCM 从 100MHz 分出 50MHz 再送进来），
//  不含任何 Xilinx 原语，因此：
//    * 仿真可以直接例化本模块（不需要编译 unisims 库）；
//    * 可以直接被 Vivado 封装成 IP 核，在 Block Design 里由 clk_wiz 供时钟。
//
//  与 EES338Top.v 的分工：
//    EES338Top = ClockGen(MMCM) + 上电/按键复位 + EES338_Core + LED 心跳
//    EES338_Core = PipelineCPU + PeriphMMIO
//  CPU 代码（PipelineCPU.v 及其子模块）未做任何修改。
//////////////////////////////////////////////////////////////////////////////////
module EES338_Core #(
    parameter HEX_FILE    = "../../../../Lab2.file/uart_hello.hex",  // 仿真：指令 ROM 内容
    parameter DATA_FILE   = "../../../../Lab2.file/uart_hello_mem.hex", // 仿真：数据 RAM 内容
    parameter integer BAUD_DIV       = 434,      // UART 115200 @50MHz
    parameter integer BAUD_DIV_BT    = 5208,     // 蓝牙 9600  @50MHz
    parameter integer LCD_WR_CYCLES  = 10,
    parameter integer LCD_RST_CYCLES = 200000,
    parameter integer SEG_SCAN_DIV   = 16384,    // 数码管扫描相位长度
    parameter integer SEG_GROUP_SWAP = 1,        // 数码管：组0 模块在右边（本板实测）
    parameter integer SEG_REVERSE_K  = 1,        // 数码管：模块内 K1..K4 与左→右相反（本板实测）
    parameter integer TIMER_DELAY    = 20000000  // 硬件延时长度（0.4s @50MHz）
)(
    input  wire       clk,        // 逻辑时钟（50MHz）
    input  wire       rst,        // 复位（高有效）
    // ---- USB-UART(CP2102)：uart_txd 出，uart_rxd 入 ----
    input  wire       uart_rxd,
    output wire       uart_txd,
    // ---- 蓝牙(BLE-CC41-A)：bt_txd 出，bt_rxd 入 ----
    input  wire       bt_rxd,
    output wire       bt_txd,
    // ---- LCD(JLX128128G-81202 / ST7571) 8080 并口 ----
    output wire [7:0] lcd_d,
    output wire       lcd_wr_n,
    output wire       lcd_rd_n,
    output wire       lcd_cs_n,
    output wire       lcd_rs,
    output wire       lcd_rst_n,
    // ---- 8 位数码管（两组各 4 位，动态扫描）----
    output wire [7:0] seg_grp0,   // {DP,G,F,E,D,C,B,A}
    output wire [3:0] dn0,        // DN0_K1..K4
    output wire [7:0] seg_grp1,
    output wire [3:0] dn1
);

    // ==================== CPU 与外设之间的 MMIO 总线 ====================
    wire        memio_read, memio_write;
    wire [31:0] memio_addr, memio_wdata, memio_rdata;

    // ==================== 五级流水线 CPU（未修改） ====================
    // 新增：把 CPU 内部的状态标志寄存器（FlagReg）引给 PeriphMMIO，
    //       程序用 lw 访问 0x1000_0300/0x1000_0304 即可读取溢出状态。
    wire [7:0]  cpu_flags;
    wire [31:0] cpu_of_count;

    PipelineCPU #(
        .HEX_FILE (HEX_FILE),
        .DATA_FILE(DATA_FILE)
    ) cpu_inst (
        .clk          (clk),
        .rst          (rst),
        .memio_rdata  (memio_rdata),
        .memio_read   (memio_read),
        .memio_write  (memio_write),
        .memio_addr   (memio_addr),
        .memio_wdata  (memio_wdata),
        .flags_o      (cpu_flags),
        .of_count_o   (cpu_of_count)
    );

    // ==================== 存储器映射外设（UART / 蓝牙 / LCD） ====================
    PeriphMMIO #(
        .BAUD_DIV       (BAUD_DIV),
        .BAUD_DIV_BT    (BAUD_DIV_BT),
        .LCD_WR_CYCLES  (LCD_WR_CYCLES),
        .LCD_RST_CYCLES (LCD_RST_CYCLES),
        .SEG_SCAN_DIV   (SEG_SCAN_DIV),
        .SEG_GROUP_SWAP (SEG_GROUP_SWAP),
        .SEG_REVERSE_K  (SEG_REVERSE_K),
        .TIMER_DELAY    (TIMER_DELAY)
    ) periph_inst (
        .clk          (clk),
        .rst          (rst),
        .memio_read   (memio_read),
        .memio_write  (memio_write),
        .memio_addr   (memio_addr),
        .memio_wdata  (memio_wdata),
        .memio_rdata  (memio_rdata),
        .cpu_flags    (cpu_flags),
        .cpu_of_count (cpu_of_count),
        .uart_rxd     (uart_rxd),
        .uart_txd     (uart_txd),
        .bt_rxd       (bt_rxd),
        .bt_txd       (bt_txd),
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

endmodule
