`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// LCD128128.v - EES-338 板载 LCD（JLX128128G-81202 / ST7571 驱动 IC）并口控制器
//
//  板载 LCD 走 8080 并口：D[7:0] 数据、WR# 写选通、RD# 读选通、CS# 片选、
//  RS 寄存器选择（0=命令，1=数据）、RST# 硬复位。
//  本模块只实现"写"方向（显示用），LCD_RD# 默认恒为高。
//
//  握手方式与 UART_TX 的 tx_busy 完全一致（便于讲解、便于 CPU 程序复用同一套轮询）：
//    * busy=1 表示控制器占用总线（上电复位脉宽 / 正在执行一次写时序）；
//    * CPU 先 lw LCD_STATUS 轮询 busy==0，再 sw LCD_CMD / LCD_DAT 给出 1 拍 wr_req；
//    * 控制器自动产生 [建立 -> WR# 拉低 -> WR# 拉高 -> 保持] 四段时序。
//
//  参数（50MHz 逻辑时钟下的周期数，20ns/拍）：
//    WR_CYCLES    写脉冲宽度(WR# 低电平)     10 拍 = 200ns
//    SETUP_CYCLES 数据/RS 建立时间            4 拍 =  80ns
//    HOLD_CYCLES  数据保持时间                4 拍 =  80ns
//    RST_CYCLES   上电复位低电平宽度      200000 拍 =   4ms
//
//  ★ 两个"上板调试开关"（由 LCD_CTRL 的 bit1/bit2 运行时给出，方便排查板级差异）：
//    inv_rst   = 1 : 把 LCD_RST 输出取反（若实测复位是高有效）
//    swap_wrrd = 1 : 把 LCD_WR# 与 LCD_RD# 两个输出互换（若实测这两个脚标反了）
//  默认都是 0（即手册标法）。上电后控制器自动拉低 LCD_RST 并保持 RST_CYCLES 拍，
//  期间 busy=1，所以 CPU 程序只要先轮询 busy 就能保证复位脉宽。
//////////////////////////////////////////////////////////////////////////////////
module LCD128128 #(
    parameter integer WR_CYCLES    = 10,
    parameter integer SETUP_CYCLES = 4,
    parameter integer HOLD_CYCLES  = 4,
    parameter integer RST_CYCLES   = 200000,
    parameter integer RD_CYCLES    = 30        // 读周期 RD# 低电平拍数（600ns @50MHz）
)(
    input  wire       clk,        // 逻辑时钟（50MHz）
    input  wire       rst,        // 复位（高有效）
    input  wire       wr_req,     // 单拍写请求（busy=0 时有效）
    input  wire       rs,         // 0=命令 1=数据（与 wr_req 同拍）
    input  wire [7:0] wdata,      // 写数据（与 wr_req 同拍）
    input  wire       rst_req,    // 单拍软复位请求
    input  wire       rd_req,     // 单拍读请求（读显示 RAM：RS=1 + RD# 低）
    input  wire       inv_rst,    // 1 = LCD_RST 输出取反（调试用）
    input  wire       swap_wrrd,  // 1 = LCD_WR#/LCD_RD# 输出互换（调试用）
    output wire       busy,       // 1=控制器忙（CPU 轮询此位）
    output wire [7:0] rd_data,    // 最近一次读回的字节
    inout  wire [7:0] lcd_d,      // LCD_D0..D7（写时驱动、读时高阻）
    output wire       lcd_wr_n,   // LCD_WR#（低有效写选通）
    output wire       lcd_rd_n,   // LCD_RD#（低有效读选通）
    output wire       lcd_cs_n,   // LCD_CS#（低有效片选）
    output wire       lcd_rs,     // LCD_RS
    output wire       lcd_rst_n   // LCD_RST（默认低有效）
);

    // 四段写时序 + 上电复位 + 软复位 状态
    localparam [2:0] S_POR    = 3'd0,   // 上电/复位等待
                     S_IDLE   = 3'd1,   // 空闲（busy=0）
                     S_SETUP  = 3'd2,   // 数据/RS 建立
                     S_WRLOW  = 3'd3,   // WR# 低电平脉冲
                     S_HOLD   = 3'd4,   // 数据保持
                     S_RSTLOW = 3'd5,   // 软复位脉宽
                     S_RDLOW  = 3'd6;   // 读选通（RD# 低，采样数据总线）

    reg [2:0]  state;
    reg [15:0] cnt;        // 段内计数
    reg [31:0] rst_cnt;    // 复位脉宽计数（4ms 需要 >17 位）

    // 内部输出寄存器（对外再做极性/互换处理）
    reg [7:0] d_r;
    reg       wr_n_r, rd_n_r, cs_n_r, rs_r, rst_n_r;
    reg       busy_r;
    reg       d_oe;        // 1 = 驱动数据总线（写）；0 = 高阻（读）
    reg [7:0] rd_data_r;

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_POR;
            cnt     <= 16'd0;
            rst_cnt <= 32'd0;
            busy_r  <= 1'b1;
            d_r     <= 8'h00;
            wr_n_r  <= 1'b1;
            rd_n_r  <= 1'b1;
            cs_n_r  <= 1'b1;
            rs_r    <= 1'b0;
            rst_n_r <= 1'b0;
            d_oe    <= 1'b1;
            rd_data_r <= 8'h00;
        end
        else begin
            rd_n_r <= 1'b1;            // 只写方向：RD# 一直无效（高）
            case (state)
                // -------- 上电复位：LCD_RST 低电平保持 RST_CYCLES 拍 --------
                S_POR: begin
                    rst_n_r <= 1'b0;
                    cs_n_r  <= 1'b1;
                    wr_n_r  <= 1'b1;
                    busy_r  <= 1'b1;
                    if (rst_cnt >= RST_CYCLES) begin
                        rst_cnt <= 32'd0;
                        rst_n_r <= 1'b1;
                        busy_r  <= 1'b0;
                        cnt     <= 16'd0;
                        state   <= S_IDLE;
                    end
                    else begin
                        rst_cnt <= rst_cnt + 32'd1;
                    end
                end

                // -------- 空闲：等待 CPU 的写请求 / 软复位请求 --------
                S_IDLE: begin
                    busy_r  <= 1'b0;
                    cs_n_r  <= 1'b1;
                    wr_n_r  <= 1'b1;
                    if (rst_req) begin
                        rst_cnt <= 32'd0;
                        rst_n_r <= 1'b0;
                        busy_r  <= 1'b1;
                        state   <= S_RSTLOW;
                    end
                    else if (wr_req) begin
                        d_r    <= wdata;      // 先建立数据与 RS，再给 WR#
                        rs_r   <= rs;
                        cs_n_r <= 1'b0;
                        wr_n_r <= 1'b1;
                        busy_r <= 1'b1;
                        cnt    <= 16'd0;
                        state  <= S_SETUP;
                    end
                    else if (rd_req) begin
                        // 读显示 RAM：CS#=0、RS=1（数据）、RD#=0、总线放开
                        rs_r   <= 1'b1;
                        cs_n_r <= 1'b0;
                        d_oe   <= 1'b0;
                        busy_r <= 1'b1;
                        cnt    <= 16'd0;
                        state  <= S_RDLOW;
                    end
                end

                // -------- 建立时间：D/RS/CS# 稳定 SETUP_CYCLES 拍 --------
                S_SETUP: begin
                    if (cnt >= SETUP_CYCLES - 1) begin
                        cnt    <= 16'd0;
                        wr_n_r <= 1'b0;        // WR# 拉低：写入
                        state  <= S_WRLOW;
                    end
                    else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                // -------- 写脉冲：WR# 低电平 WR_CYCLES 拍 --------
                S_WRLOW: begin
                    if (cnt >= WR_CYCLES - 1) begin
                        cnt    <= 16'd0;
                        wr_n_r <= 1'b1;        // WR# 拉高：锁存
                        state  <= S_HOLD;
                    end
                    else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                // -------- 保持时间：D 保持 HOLD_CYCLES 拍后释放 --------
                S_HOLD: begin
                    if (cnt >= HOLD_CYCLES - 1) begin
                        cnt    <= 16'd0;
                        cs_n_r <= 1'b1;
                        busy_r <= 1'b0;        // 本次写完成，CPU 可以再写
                        state  <= S_IDLE;
                    end
                    else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                // -------- 读选通：RD# 低 RD_CYCLES 拍，末尾采样数据总线 --------
                S_RDLOW: begin
                    if (cnt >= RD_CYCLES) begin
                        rd_data_r <= lcd_d;        // 采样：本拍 RD# 仍为低（数据有效）
                        cs_n_r    <= 1'b1;
                        d_oe      <= 1'b1;         // 读完恢复驱动（写方向）
                        busy_r    <= 1'b0;
                        state     <= S_IDLE;       // rd_n_r 走默认值 1（拉高）
                    end
                    else begin
                        cnt    <= cnt + 16'd1;
                        rd_n_r <= 1'b0;            // 保持读选通低
                    end
                end

                // -------- 软复位：LCD_RST 低电平保持 RST_CYCLES 拍 --------
                S_RSTLOW: begin
                    rst_n_r <= 1'b0;
                    cs_n_r  <= 1'b1;
                    wr_n_r  <= 1'b1;
                    busy_r  <= 1'b1;
                    if (rst_cnt >= RST_CYCLES) begin
                        rst_cnt <= 32'd0;
                        rst_n_r <= 1'b1;
                        busy_r  <= 1'b0;
                        cnt     <= 16'd0;
                        state   <= S_IDLE;
                    end
                    else begin
                        rst_cnt <= rst_cnt + 32'd1;
                    end
                end

                default: state <= S_POR;
            endcase
        end
    end

    // ---------------- 对外输出（极性/互换由调试开关决定） ----------------
    // 数据总线双向：写周期驱动、读周期高阻（由 LCD 侧驱动）
    assign lcd_d     = d_oe ? d_r : 8'hZZ;
    assign rd_data   = rd_data_r;
    assign lcd_cs_n  = cs_n_r;
    assign lcd_rs    = rs_r;
    assign busy      = busy_r;
    assign lcd_wr_n  = swap_wrrd ? rd_n_r : wr_n_r;
    assign lcd_rd_n  = swap_wrrd ? wr_n_r : rd_n_r;
    assign lcd_rst_n = inv_rst   ? ~rst_n_r : rst_n_r;

endmodule

