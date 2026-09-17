`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// UartChannel.v - 一路"存储器映射 UART 通道"（CPU 侧寄存器 + UART_TX/UART_RX）
//
//  本模块把原先 EES338Top.v 里的 UART 寄存器逻辑原封不动搬进来，做成可复用的
//  "通道"，这样 UART(CP2102) 与 蓝牙(BLE-CC41-A) 两条链路可以各例化一份，
//  只差一个 BAUD_DIV 参数，CPU 侧看到的是完全相同的两个寄存器：
//
//    DATA   寄存器: sw  -> 低 8 位送发送器；lw -> 读最近收到的字节并清 ready
//    STATUS 寄存器: bit0 = TX_BUSY, bit1 = RX_READY
//
//  wr / rd 由上层地址译码给出（本通道 DATA 地址被读写的那一拍为 1）。
//////////////////////////////////////////////////////////////////////////////////
module UartChannel #(
    parameter integer BAUD_DIV = 434      // 每 bit 时钟数 = 50MHz/波特率
)(
    input  wire        clk,
    input  wire        rst,        // 高有效（复位整个通道）
    // ---- CPU 侧 MMIO ----
    input  wire        wr,         // 本拍 CPU 在写 DATA 寄存器
    input  wire        rd,         // 本拍 CPU 在读 DATA 寄存器
    input  wire [31:0] wdata,      // CPU 写数据（只用低 8 位）
    output wire [7:0]  rdata,      // 读回值：最近收到的字节
    output wire        tx_busy,
    output wire        rx_rdy,
    // ---- 串口引脚 ----
    input  wire        rxd,        // 串行输入（已两级同步）
    output wire        txd         // 串行输出
);

    // ---------- TX 数据寄存器：写 DATA 寄存器 -> 启动一次发送 ----------
    reg [7:0] tx_data_reg;
    reg       tx_start_p;          // 单拍启动脉冲

    always @(posedge clk) begin
        if (rst) begin
            tx_data_reg <= 8'd0;
            tx_start_p  <= 1'b0;
        end
        else begin
            tx_start_p <= 1'b0;                    // 默认拉低
            if (wr) begin
                tx_data_reg <= wdata[7:0];
                tx_start_p  <= 1'b1;
            end
        end
    end

    UART_TX #(.BAUD_DIV(BAUD_DIV)) u_tx (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start_p),
        .tx_data  (tx_data_reg),
        .tx_busy  (tx_busy),
        .uart_txd (txd)
    );

    // ---------- RX：收字节置 ready，CPU 读走清 ready ----------
    wire [7:0] rx_data;
    wire       rx_valid;

    UART_RX #(.BAUD_DIV(BAUD_DIV)) u_rx (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (rxd),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    reg rx_rdy_r;
    always @(posedge clk) begin
        if (rst) begin
            rx_rdy_r <= 1'b0;
        end
        else begin
            if (rd)               rx_rdy_r <= rx_valid;  // 同拍若来新字节则保留 1
            else if (rx_valid)    rx_rdy_r <= 1'b1;
        end
    end

    assign rdata  = rx_data;
    assign rx_rdy = rx_rdy_r;

endmodule
