`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// PeriphMMIO.v - 存储器映射外设集合（USB-UART / 蓝牙 / LCD）
//
//  CPU 侧零改动：PipelineCPU 的 MEM 级外设窗口判定是 addr[31:16]==16'h1000，
//  覆盖 0x1000_0000 ~ 0x1000_FFFF，所以新增外设只是"往这个窗口里加地址"，
//  不需要新增指令、也不需要改流水线。
//
//  地址映射（CPU 只用普通 lw/sw 访问）：
//    0x1000_0000  UART_DATA    w: 低 8 位送入 CP2102 发送器   r: 最近收到的字节(读后清 ready)
//    0x1000_0004  UART_STATUS  r: bit0=TX_BUSY  bit1=RX_READY
//    0x1000_0010  BT_DATA      w: 低 8 位送入蓝牙模块发送器    r: 最近收到的字节(读后清 ready)
//    0x1000_0014  BT_STATUS    r: bit0=TX_BUSY  bit1=RX_READY
//    0x1000_0100  LCD_CMD      w: 低 8 位作为命令(RS=0)送 LCD（busy=0 时才有效）
//    0x1000_0104  LCD_DAT      w: 低 8 位作为数据(RS=1)送 LCD（busy=0 时才有效）
//    0x1000_0108  LCD_STATUS   r: bit0=LCD_BUSY
//    0x1000_010C  LCD_CTRL     w: bit0=1 产生一次 LCD 硬复位脉冲
//    0x1000_0200+4i  SEG_DIG_i  w: 第 i 位数码管 {mark, value[3:0]}
//    0x1000_0240  SEG_CTRL     w: bit0=显示使能
//    0x1000_0244  TIMER_CTRL   w: bit0=1 启动硬件延时
//    0x1000_0248  TIMER_VALUE  r: 剩余拍数（0 = 延时结束）
//    0x1000_0300  CPU_FLAGS    r: 状态标志寄存器（来自 CPU，见 FlagReg.v）
//    0x1000_0304  OF_COUNT     r: 算术溢出累计次数（clrflags 指令清零）
//
//  说明：标志寄存器本体在 PipelineCPU 内部（FlagReg），这里只把它"暴露成
//  一个可读的 MMIO 寄存器"，程序用普通 lw 就能查"有没有溢出过"；
//  清除则用自定义指令 clrflags（不需要新增 CPU 输入端口）。
//
//  两条串口链路（UART / 蓝牙）共用同一个 UartChannel 模块，只差 BAUD_DIV。
//////////////////////////////////////////////////////////////////////////////////
module PeriphMMIO #(
    parameter integer BAUD_DIV       = 434,     // 50MHz/115200
    parameter integer BAUD_DIV_BT    = 5208,    // 50MHz/9600（BLE-CC41-A 缺省波特率）
    parameter integer LCD_WR_CYCLES  = 10,
    parameter integer LCD_RST_CYCLES = 200000,
    parameter integer SEG_SCAN_DIV   = 16384,   // 数码管扫描相位长度（50MHz → 328us/相位）
    parameter integer SEG_GROUP_SWAP = 1,       // 数码管：组0 模块在右边（本板实测）
    parameter integer SEG_REVERSE_K  = 1,       // 数码管：模块内 K1..K4 与左→右相反（本板实测）
    parameter integer TIMER_DELAY    = 20000000, // 硬件延时长度（50MHz → 0.4s）
    parameter integer BT_RST_CYCLES  = 1000000   // 蓝牙上电复位脉宽（50MHz → 20ms）
)(
    input  wire        clk,
    input  wire        rst,          // 高有效
    // ---- CPU MEM 级 MMIO 从机 ----
    input  wire        memio_read,
    input  wire        memio_write,
    input  wire [31:0] memio_addr,
    input  wire [31:0] memio_wdata,
    output wire [31:0] memio_rdata,
    // ---- CPU 状态标志寄存器（Lab1 溢出标志位迁移；只读镜像）----
    input  wire [7:0]  cpu_flags,    // 读 0x1000_0300
    input  wire [31:0] cpu_of_count, // 读 0x1000_0304
    // ---- USB-UART(CP2102) ----
    input  wire        uart_rxd,
    output wire        uart_txd,
    // ---- 蓝牙(BLE-CC41-A) ----
    input  wire        bt_rxd,
    output wire        bt_txd,
    // ---- 蓝牙模块控制脚（官方 lab08 的接法：FPGA 必须驱动这 5 根，否则模组不上电/一直复位）----
    output wire        bt_pw_on,      // D18 电源开关（1=上电）
    output wire        bt_master_slave, // C16 模式选择（1=从模式，手机可连）
    output wire        bt_sw_hw,      // H15（官方：置低）
    output wire        bt_sw,         // E18（官方：置高）
    output wire        bt_rst_n,      // M2  复位（低有效，官方：拉低再拉高）
    // ---- LCD(JLX128128G-81202 / ST7571) ----
    output wire [7:0]  lcd_d,
    output wire        lcd_wr_n,
    output wire        lcd_rd_n,
    output wire        lcd_cs_n,
    output wire        lcd_rs,
    output wire        lcd_rst_n,
    // ---- 8 位数码管（两组各 4 位，动态扫描）----
    output wire [7:0]  seg_grp0,     // {DP,G,F,E,D,C,B,A}
    output wire [3:0]  dn0,          // DN0_K1..K4（高有效）
    output wire [7:0]  seg_grp1,
    output wire [3:0]  dn1
);

    localparam [31:0] A_UART_DATA   = 32'h1000_0000;
    localparam [31:0] A_UART_STATUS = 32'h1000_0004;
    localparam [31:0] A_BT_DATA     = 32'h1000_0010;
    localparam [31:0] A_BT_STATUS   = 32'h1000_0014;
    localparam [31:0] A_BT_CTRL     = 32'h1000_0018;   // w: 蓝牙模块控制脚（见下方注释）
    localparam [31:0] A_LCD_CMD     = 32'h1000_0100;
    localparam [31:0] A_LCD_DAT     = 32'h1000_0104;
    localparam [31:0] A_LCD_STATUS  = 32'h1000_0108;
    localparam [31:0] A_LCD_CTRL    = 32'h1000_010C;
    localparam [31:0] A_LCD_RCTRL   = 32'h1000_0110;   // w: bit0=1 启动一次读显示 RAM
    localparam [31:0] A_LCD_RDATA   = 32'h1000_0114;   // r: 最近一次读回的字节
    // 数码管：0x1000_0200 + 4*i （i=0..7）分别对应第 i 位
    localparam [31:0] A_SEG_BASE    = 32'h1000_0200;
    localparam [31:0] A_SEG_END     = 32'h1000_021C;
    localparam [31:0] A_SEG_CTRL    = 32'h1000_0240;
    localparam [31:0] A_TIMER_CTRL  = 32'h1000_0244;
    localparam [31:0] A_TIMER_VALUE = 32'h1000_0248;
    // 状态标志寄存器（CPU 内部 FlagReg 的只读镜像）
    localparam [31:0] A_CPU_FLAGS   = 32'h1000_0300;
    localparam [31:0] A_OF_COUNT    = 32'h1000_0304;

    // ==================== 地址译码（均为当拍选通） ====================
    wire wr_uart_data = memio_write && (memio_addr == A_UART_DATA);
    wire rd_uart_data = memio_read  && (memio_addr == A_UART_DATA);
    wire wr_bt_data   = memio_write && (memio_addr == A_BT_DATA);
    wire rd_bt_data   = memio_read  && (memio_addr == A_BT_DATA);
    wire wr_bt_ctrl   = memio_write && (memio_addr == A_BT_CTRL);
    wire wr_lcd_cmd   = memio_write && (memio_addr == A_LCD_CMD);
    wire wr_lcd_dat   = memio_write && (memio_addr == A_LCD_DAT);
    wire wr_lcd_ctrl  = memio_write && (memio_addr == A_LCD_CTRL);
    wire wr_lcd_rctrl = memio_write && (memio_addr == A_LCD_RCTRL);

    // 数码管：窗口 0x1000_0200~0x1000_021C，每 4 字节一位（索引 = addr[4:2]）
    wire       wr_seg      = memio_write && (memio_addr >= A_SEG_BASE) && (memio_addr <= A_SEG_END);
    wire [2:0] seg_wr_idx  = memio_addr[4:2];
    wire       wr_seg_ctrl = memio_write && (memio_addr == A_SEG_CTRL);
    wire       wr_timer    = memio_write && (memio_addr == A_TIMER_CTRL);

    // ==================== 串口通道 1：USB-UART(CP2102) ====================
    wire [7:0] uart_rdata;
    wire       uart_tx_busy, uart_rx_rdy;

    UartChannel #(.BAUD_DIV(BAUD_DIV)) u_uart (
        .clk     (clk),
        .rst     (rst),
        .wr      (wr_uart_data),
        .rd      (rd_uart_data),
        .wdata   (memio_wdata),
        .rdata   (uart_rdata),
        .tx_busy (uart_tx_busy),
        .rx_rdy  (uart_rx_rdy),
        .rxd     (uart_rxd),
        .txd     (uart_txd)
    );

    // ==================== 串口通道 2：蓝牙(BLE-CC41-A) ====================
    wire [7:0] bt_rdata;
    wire       bt_tx_busy, bt_rx_rdy;

    UartChannel #(.BAUD_DIV(BAUD_DIV_BT)) u_bt (
        .clk     (clk),
        .rst     (rst),
        .wr      (wr_bt_data),
        .rd      (rd_bt_data),
        .wdata   (memio_wdata),
        .rdata   (bt_rdata),
        .tx_busy (bt_tx_busy),
        .rx_rdy  (bt_rx_rdy),
        .rxd     (bt_rxd),
        .txd     (bt_txd)
    );

    // ==================== 蓝牙模块控制脚（官方 lab08 的接法） ====================
    // 本板蓝牙模组的**电源/复位/模式**由 FPGA 的 5 根脚驱动（用户手册 §11 没写，
    // 只有官方 lab08 的工程里才有）：
    //   bt_pw_on(D18) / bt_master_slave(C16) / bt_sw_hw(H15) / bt_sw(E18) / bt_rst_n(M2)
    // 官方可用状态（lab08 步骤 5：SW1 低、SW0/SW2/SW3/SW4 高，再用 SW2 复位一次）：
    //   pw_on=1、master_slave=1（从模式）、sw_hw=0、sw=1、rst_n 拉低再拉高
    // 这里默认给这个状态，并且上电先输出 20ms 低电平复位脉冲；也可用
    //   0x1000_0018 BT_CTRL  覆盖（bit0 pw_on, bit1 master_slave, bit2 sw_hw, bit3 sw, bit4 rst_n）
    //   —— 复位后默认 5'b11011，正好就是官方可用状态。
    reg [4:0]  bt_ctrl_r;
    reg [31:0] bt_rst_cnt;

    always @(posedge clk) begin
        if (rst) begin
            bt_ctrl_r  <= 5'b11011;
            bt_rst_cnt <= 32'd0;
        end
        else begin
            if (bt_rst_cnt != BT_RST_CYCLES) bt_rst_cnt <= bt_rst_cnt + 32'd1;
            if (wr_bt_ctrl) bt_ctrl_r <= memio_wdata[4:0];
        end
    end

    wire bt_boot_rst = (bt_rst_cnt < BT_RST_CYCLES);

    assign bt_pw_on        = bt_ctrl_r[0];
    assign bt_master_slave = bt_ctrl_r[1];
    assign bt_sw_hw        = bt_ctrl_r[2];
    assign bt_sw           = bt_ctrl_r[3];
    assign bt_rst_n        = bt_ctrl_r[4] & ~bt_boot_rst;   // 上电先低 20ms（复位）再释放

    // ==================== LCD 并口控制器（JLX128128G-81202 / ST7571） ====================
    reg       lcd_wr_req, lcd_rs_r, lcd_rst_req, lcd_rd_req;
    reg [7:0] lcd_wdata_r;
    reg       lcd_inv_rst, lcd_swap_wrrd;      // ★ 调试开关（LCD_CTRL.bit1/bit2）
    wire      lcd_busy;
    wire [7:0] lcd_rd_data;

    always @(posedge clk) begin
        if (rst) begin
            lcd_wr_req    <= 1'b0;
            lcd_rs_r      <= 1'b0;
            lcd_wdata_r   <= 8'd0;
            lcd_rst_req   <= 1'b0;
            lcd_rd_req    <= 1'b0;
            lcd_inv_rst   <= 1'b0;
            lcd_swap_wrrd <= 1'b0;
        end
        else begin
            lcd_wr_req  <= wr_lcd_cmd | wr_lcd_dat;   // 单拍写请求
            lcd_rs_r    <= wr_lcd_dat;                // 1=数据(RS=1)，0=命令(RS=0)
            lcd_wdata_r <= memio_wdata[7:0];
            lcd_rst_req <= wr_lcd_ctrl & memio_wdata[0];
            lcd_rd_req  <= wr_lcd_rctrl & memio_wdata[0];   // 单拍读请求（读显示 RAM）
            if (wr_lcd_ctrl) begin
                lcd_inv_rst   <= memio_wdata[1];       // 1 = LCD_RST 高有效
                lcd_swap_wrrd <= memio_wdata[2];       // 1 = WR#/RD# 互换
            end
        end
    end

    LCD128128 #(
        .WR_CYCLES (LCD_WR_CYCLES),
        .RST_CYCLES(LCD_RST_CYCLES)
    ) u_lcd (
        .clk        (clk),
        .rst        (rst),
        .wr_req     (lcd_wr_req),
        .rs         (lcd_rs_r),
        .wdata      (lcd_wdata_r),
        .rst_req    (lcd_rst_req),
        .rd_req     (lcd_rd_req),
        .inv_rst    (lcd_inv_rst),
        .swap_wrrd  (lcd_swap_wrrd),
        .busy       (lcd_busy),
        .rd_data    (lcd_rd_data),
        .lcd_d      (lcd_d),
        .lcd_wr_n   (lcd_wr_n),
        .lcd_rd_n   (lcd_rd_n),
        .lcd_cs_n   (lcd_cs_n),
        .lcd_rs     (lcd_rs),
        .lcd_rst_n  (lcd_rst_n)
    );

    // CPU 看到的"忙"必须包含"CPU 已经写下来、控制器还没开始执行"的那一拍：
    // 若只上报控制器内部的 busy，则"sw 紧跟 lw 轮询"的写法（poll 的 MEM 级只比
    // sw 的 MEM 级晚 1 拍）会读到 busy=0，于是下一拍又发一个写请求，而控制器此时
    // 还在上一笔的建立时间里(S_SETUP)，请求会被丢掉 —— 仿真中实测出现过该问题。
    // 加上 lcd_wr_req / lcd_rst_req 之后，写请求受理到完成之间 busy 始终为 1。
    wire lcd_busy_cpu = lcd_busy | lcd_wr_req | lcd_rst_req | lcd_rd_req;

    // ==================== 8 位数码管（硬件动态扫描刷新） ====================
    reg        seg_en;              // SEG_CTRL.bit0，上电默认使能显示
    reg        seg_wr_p;            // 写脉冲：寄存一拍，与数据同拍交给 SegDisplay
    reg [2:0]  seg_idx_r;
    reg [4:0]  seg_data_r;

    always @(posedge clk) begin
        if (rst) begin
            seg_en     <= 1'b1;
            seg_wr_p   <= 1'b0;
            seg_idx_r  <= 3'd0;
            seg_data_r <= 5'h0F;
        end
        else begin
            seg_wr_p   <= wr_seg;
            seg_idx_r  <= seg_wr_idx;
            seg_data_r <= memio_wdata[4:0];
            if (wr_seg_ctrl) seg_en <= memio_wdata[0];
        end
    end

    SegDisplay #(
        .SCAN_DIV  (SEG_SCAN_DIV),
        .GROUP_SWAP(SEG_GROUP_SWAP),
        .REVERSE_K (SEG_REVERSE_K)
    ) u_seg (
        .clk      (clk),
        .rst      (rst),
        .en       (seg_en),
        .wr       (seg_wr_p),
        .wr_idx   (seg_idx_r),
        .wr_data  (seg_data_r),
        .seg_grp0 (seg_grp0),
        .dn0      (dn0),
        .seg_grp1 (seg_grp1),
        .dn1      (dn1)
    );

    // ==================== 硬件延时定时器（数码管演示程序用） ====================
    reg         timer_start_p;
    wire [31:0] timer_value;

    always @(posedge clk) begin
        if (rst) timer_start_p <= 1'b0;
        else     timer_start_p <= wr_timer & memio_wdata[0];
    end

    SimpleTimer #(
        .DELAY_CYCLES(TIMER_DELAY)
    ) u_timer (
        .clk   (clk),
        .rst   (rst),
        .start (timer_start_p),
        .value (timer_value),
        .busy  ()
    );

    // 与 LCD 的 busy 同理：CPU 写完 TIMER_CTRL 的**下一拍**就会来读状态，
    // 而定时器要到再下一拍才真正装上 DELAY_CYCLES。如果上一轮已经数到 0，
    // 那一拍就会读到"0 = 延时结束"，轮询立刻退出、延时被跳过（仿真中实测到过）。
    // 把"已受理但还没开始"的这一拍也报成未结束，任何"先启动再轮询"的程序都不会漏等。
    wire [31:0] timer_value_cpu = timer_start_p ? TIMER_DELAY : timer_value;

    // ==================== 读数据多路选择 ====================
    // UART 两行的语义与原 EES338Top.v 完全一致（回归测试 tb_EES338_* 不变）
    assign memio_rdata =
        (memio_addr == A_UART_DATA)   ? {24'd0, uart_rdata}                     :
        (memio_addr == A_UART_STATUS) ? {30'd0, uart_rx_rdy, uart_tx_busy}      :
        (memio_addr == A_BT_DATA)     ? {24'd0, bt_rdata}                       :
        (memio_addr == A_BT_STATUS)   ? {30'd0, bt_rx_rdy, bt_tx_busy}          :
        (memio_addr == A_LCD_STATUS)  ? {31'd0, lcd_busy_cpu}                   :
        (memio_addr == A_LCD_RDATA)   ? {24'd0, lcd_rd_data}                    :
        (memio_addr == A_CPU_FLAGS)   ? {24'd0, cpu_flags}                      :
        (memio_addr == A_OF_COUNT)    ? cpu_of_count                            :
        (memio_addr == A_TIMER_VALUE) ? timer_value_cpu                         :
                                         32'd0;

endmodule
