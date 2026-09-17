`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// UART_TX.v - 通用异步收发 - 发送器（8 数据位 / 无校验 / 1 停止位，LSB 先发）
//
//  - BAUD_DIV = 系统时钟每 bit 的周期数 = CLK_FREQ / BAUD_RATE
//    例如 100 MHz / 115200 bps ≈ 868
//  - 空闲时 uart_txd 保持高电平
//  - tx_start=1 且模块空闲(busy=0)时开始发送低 8 位数据
//  - tx_busy 在整帧（起始位+8数据位+停止位，共 10 个 bit 周期）内为 1
//  - 全同步可综合逻辑
//////////////////////////////////////////////////////////////////////////////////
module UART_TX #(
    parameter integer BAUD_DIV = 868
)(
    input  wire       clk,       // 系统时钟
    input  wire       rst,       // 复位（高有效）
    input  wire       tx_start,  // 发送请求（busy=0 时有效，电平/脉冲均可）
    input  wire [7:0] tx_data,   // 待发送数据
    output reg        tx_busy,   // 忙标志：1=正在发送
    output reg        uart_txd   // 串行输出
);

    localparam integer FULL = BAUD_DIV;

    localparam [1:0] S_IDLE = 2'd0,
                     S_START= 2'd1,   // 起始位（低电平 1 个 bit）
                     S_BITS = 2'd2,   // 8 个数据位
                     S_STOP = 2'd3;   // 停止位（高电平 1 个 bit）

    reg [1:0]  state;
    reg [15:0] cnt;          // 当前 bit 相位内的时钟计数 0~(FULL-1)
    reg [3:0]  bit_idx;      // 已发出数据位数 0~7
    reg [7:0]  shreg;        // 发送数据锁存/移位

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            cnt      <= 16'd0;
            bit_idx  <= 4'd0;
            shreg    <= 8'd0;
            tx_busy  <= 1'b0;
            uart_txd <= 1'b1;
        end
        else begin
            case (state)
                S_IDLE: begin
                    // 空闲：总线保持高；有新数据且不忙则进入起始位
                    uart_txd <= 1'b1;
                    tx_busy  <= 1'b0;
                    cnt      <= 16'd0;
                    if (tx_start) begin
                        state    <= S_START;
                        shreg    <= tx_data;
                        tx_busy  <= 1'b1;
                        uart_txd <= 1'b0;       // 起始位：拉低
                    end
                end

                S_START: begin
                    // 起始位持续 FULL 个时钟
                    if (cnt == FULL - 1) begin
                        state <= S_BITS;
                        cnt   <= 16'd0;
                        bit_idx <= 4'd0;
                    end
                    else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_BITS: begin
                    // 输出当前数据位（LSB 先发）
                    uart_txd <= shreg[0];
                    if (cnt == FULL - 1) begin
                        cnt     <= 16'd0;
                        shreg   <= {1'b0, shreg[7:1]};   // 准备下一位
                        if (bit_idx == 4'd7) begin
                            state <= S_STOP;             // 8 位已发完
                        end
                        else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                    else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    // 停止位：高电平 1 个 bit，结束整帧
                    uart_txd <= 1'b1;
                    if (cnt == FULL - 1) begin
                        state <= S_IDLE;
                        cnt   <= 16'd0;
                        tx_busy <= 1'b0;
                    end
                    else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    uart_txd <= 1'b1;
                end
            endcase
        end
    end

endmodule
