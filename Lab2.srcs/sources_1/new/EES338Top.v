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
module EES338Top #(
    parameter HEX_FILE     = "../../../../Lab2.file/uart_hello.hex",
    parameter DATA_FILE    = "../../../../Lab2.file/uart_hello_mem.hex",
    parameter integer BAUD_DIV = 434
)(
    input  wire sys_clk,     // T5 100MHz
    input  wire rst_btn,     // P15 复位按键（低有效）
    input  wire uart_rxd,    // T4
    output wire uart_txd,    // N5
    output wire led0         // K2 心跳灯
);

    localparam [31:0] UART_DATA   = 32'h1000_0000;
    localparam [31:0] UART_STATUS = 32'h1000_0004;

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

    // ==================== CPU 实例 ====================
    wire        cpu_memio_read, cpu_memio_write;
    wire [31:0] cpu_memio_addr, cpu_memio_wdata;
    wire [31:0] cpu_memio_rdata;

    PipelineCPU #(
        .HEX_FILE (HEX_FILE),
        .DATA_FILE(DATA_FILE)
    ) cpu_inst (
        .clk          (cpu_clk),
        .rst          (cpu_rst),
        .memio_rdata  (cpu_memio_rdata),
        .memio_read   (cpu_memio_read),
        .memio_write  (cpu_memio_write),
        .memio_addr   (cpu_memio_addr),
        .memio_wdata  (cpu_memio_wdata)
    );

    // ==================== RX 输入同步（跨时钟域 2 级触发器） ====================
    reg rxd_s1 = 1'b1, rxd_s2 = 1'b1;
    always @(posedge cpu_clk) begin
        rxd_s1 <= uart_rxd;
        rxd_s2 <= rxd_s1;
    end
    wire uart_rxd_sync = rxd_s2;

    // ==================== UART 收发器 ====================
    wire        tx_busy, rx_valid;
    wire [7:0]  rx_data;

    // --- TX 数据寄存器：SW 0x10000000 -> 启动一次发送 ---
    reg [7:0] tx_data_reg;
    reg       tx_start_p;          // 单拍启动脉冲
    wire wr_data = cpu_memio_write && (cpu_memio_addr == UART_DATA);

    UART_TX #(.BAUD_DIV(BAUD_DIV)) u_uart_tx (
        .clk      (cpu_clk),
        .rst      (cpu_rst),
        .tx_start (tx_start_p),
        .tx_data  (tx_data_reg),
        .tx_busy  (tx_busy),
        .uart_txd (uart_txd)
    );

    UART_RX #(.BAUD_DIV(BAUD_DIV)) u_uart_rx (
        .clk      (cpu_clk),
        .rst      (cpu_rst),
        .uart_rxd (uart_rxd_sync),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    // ==================== MMIO 寄存器 ====================
    always @(posedge cpu_clk) begin
        if (cpu_rst) begin
            tx_data_reg <= 8'd0;
            tx_start_p  <= 1'b0;
        end
        else begin
            tx_start_p <= 1'b0;                    // 默认拉低
            if (wr_data) begin
                tx_data_reg <= cpu_memio_wdata[7:0];
                tx_start_p  <= 1'b1;
            end
        end
    end

    // --- RX 可读标志：LW 0x10000000 读走后清除；收到新字节置位 ---
    reg rx_rdy;
    wire rd_data = cpu_memio_read && (cpu_memio_addr == UART_DATA);

    always @(posedge cpu_clk) begin
        if (cpu_rst) begin
            rx_rdy <= 1'b0;
        end
        else begin
            if (rd_data)          rx_rdy <= rx_valid;   // 同拍若来新字节则保留 1
            else if (rx_valid)    rx_rdy <= 1'b1;
        end
    end

    // --- 读数据组合多路选择 ---
    assign cpu_memio_rdata =
        (cpu_memio_addr == UART_DATA)   ? {24'd0, rx_data}   :
        (cpu_memio_addr == UART_STATUS) ? {30'd0, rx_rdy, tx_busy} :
                                          32'd0;

    // ==================== LED 心跳（可选，K2） ====================
    reg [24:0] led_cnt = 25'd0;
    always @(posedge cpu_clk) begin
        if (cpu_rst) led_cnt <= 25'd0;
        else         led_cnt <= led_cnt + 1'b1;
    end
    assign led0 = led_cnt[24];      // 50MHz/2^25 ≈ 0.7 Hz 闪烁，肉眼可见

endmodule
