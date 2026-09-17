`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// UART_RX.v - 通用异步收发 - 接收器（8 数据位 / 无校验 / 1 停止位，LSB 先收）
//
//  - BAUD_DIV = 系统时钟每 bit 的周期数（同 UART_TX）
//  - 检测到起始位下降沿后，先到起始位中点确认，再在每个数据位中点采样
//  - 一帧接收完成后 rx_valid 输出单拍脉冲，rx_data 输出该字节
//  - 全同步可综合逻辑；uart_rxd 建议由外部两级触发器同步后接入
//////////////////////////////////////////////////////////////////////////////////
module UART_RX #(
    parameter integer BAUD_DIV = 868
)(
    input  wire       clk,       // 系统时钟
    input  wire       rst,       // 复位（高有效）
    input  wire       uart_rxd,  // 串行输入（已同步）
    output reg  [7:0] rx_data,   // 接收到的字节
    output reg        rx_valid   // 接收完成单拍脉冲
);

    localparam integer FULL = BAUD_DIV;
    localparam integer HALF = BAUD_DIV / 2;

    localparam [1:0] S_IDLE = 2'd0,
                     S_START= 2'd1,   // 等待到起始位中点
                     S_DATA = 2'd2,   // 采样 8 个数据位
                     S_STOP = 2'd3;   // 等待停止位结束

    reg [1:0]  state;
    reg [15:0] cnt;          // 当前相位计数
    reg [3:0]  bit_idx;      // 正在采样的数据位 0~7
    reg [7:0]  shreg;        // 数据位逐位装入

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            cnt      <= 16'd0;
            bit_idx  <= 4'd0;
            shreg    <= 8'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end
        else begin
            rx_valid <= 1'b0;           // 默认无完成脉冲
            case (state)
                S_IDLE: begin
                    cnt <= 16'd0;
                    if (uart_rxd == 1'b0)   // 检测起始位下降沿
                        state <= S_START;
                end

                S_START: begin
                    if (cnt == HALF - 1) begin       // 起始位中点
                        if (uart_rxd == 1'b0) begin  // 确认为有效起始位
                            state   <= S_DATA;
                            cnt     <= 16'd0;
                            bit_idx <= 4'd0;
                        end
                        else begin                   // 噪声毛刺，重新等待
                            state <= S_IDLE;
                        end
                    end
                    else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (cnt == FULL - 1) begin       // 数据位中点采样
                        shreg[bit_idx] <= uart_rxd;
                        cnt            <= 16'd0;
                        if (bit_idx == 4'd7) begin
                            state <= S_STOP;         // 8 位采完
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
                    if (cnt == FULL - 1) begin       // 停止位结束，输出结果
                        state    <= S_IDLE;
                        cnt      <= 16'd0;
                        rx_data  <= shreg;
                        rx_valid <= 1'b1;
                    end
                    else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
