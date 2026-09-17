`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_lcd.v - SoC 级 LCD 演示自检（CPU + MMIO + LCD 全链路）
//
//  顶层直接例化 EES338_Core（不含 MMCM），跑 "gen_uart_demo.py lcd" 生成的程序：
//    ① 用 8080 总线模型（WR# 上升沿锁存）重建 128×128 帧缓存
//    ② 与 Python 生成的期望帧缓存 lcd_fb_expected.hex 逐字节比对
//    ③ 校验命令/数据条数（说明初始化 + 清屏 + 图案三段流程都完整执行）
//    ④ 顺便用 UART_RX 收下 CPU 打印的 "LCD OK\r\n"（回归验证 UART 通路未受影响）
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_lcd;

    localparam HEX_F = "../../../../Lab2.file/lcd_demo.hex";
    localparam DAT_F = "../../../../Lab2.file/lcd_demo_mem.hex";
    localparam FB_F  = "../../../../Lab2.file/lcd_fb_expected.hex";
    localparam integer BAUD_LB = 434;      // 50MHz/115200

    reg clk = 0;
    always #10 clk = ~clk;                 // 50MHz，20ns/拍

    reg  rst_btn = 1'b1;                   // 这里直接给 core 的异步复位（低有效含义由 tb 自行处理）
    reg  rst     = 1'b1;
    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;
    wire [7:0] lcd_d;
    wire lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n;

    EES338_Core #(
        .HEX_FILE      (HEX_F),
        .DATA_FILE     (DAT_F),
        .LCD_RST_CYCLES(200),               // 缩短 LCD 上电复位脉宽（真实 4ms），加快仿真
        .TIMER_DELAY   (64)                 // 初始化序列里的 4 个"等电源稳定"用短延时
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),
        .bt_rxd    (bt_rxd),
        .bt_txd    (bt_txd),
        .lcd_d     (lcd_d),
        .lcd_wr_n  (lcd_wr_n),
        .lcd_rd_n  (lcd_rd_n),
        .lcd_cs_n  (lcd_cs_n),
        .lcd_rs    (lcd_rs),
        .lcd_rst_n (lcd_rst_n)
    );

    // ================= LCD 面板模型 =================
    reg [7:0] fb     [0:1023];             // 重建的帧缓存：8 页 × 128 列
    reg [7:0] exp_fb [0:1023];             // Python 生成的期望帧缓存
    integer   page = 0, col = 0;
    integer   n_cmd = 0, n_dat = 0;
    integer   err = 0;
    integer   fb_err = 0;
    integer   i;

    initial $readmemh(FB_F, exp_fb);

    // WR# 上升沿就是 LCD 内部锁存数据的时刻
    always @(posedge lcd_wr_n) begin
        if (rst === 1'b1) ;                      // 复位期间的总线边沿不计
        else if (lcd_cs_n !== 1'b0) begin
            $display("FAIL: write while LCD_CS# inactive (0x%02X rs=%b)", lcd_d, lcd_rs);
            err = err + 1;
        end
        else if (lcd_rs) begin
            n_dat = n_dat + 1;
            fb[page * 128 + col] = lcd_d;
            col = col + 1;
            if (col > 127) col = 127;
        end
        else begin
            n_cmd = n_cmd + 1;
            if (lcd_d[7:4] == 4'hB)          // 页地址 0xB0..0xB7
                page = lcd_d[2:0];
            else if (lcd_d[7:4] == 4'h1)     // 列地址高 4 位
                col = (lcd_d[3:0] << 4) | (col & 8'h0F);
            else if (lcd_d[7:4] == 4'h0)     // 列地址低 4 位
                col = (col & 8'hF0) | lcd_d[3:0];
        end
    end

    // ================= UART 接收模型（复用设计里的 UART_RX） =================
    wire [7:0] rx_data;
    wire       rx_valid;
    reg [7:0]  got [0:15];
    integer    got_cnt = 0;

    UART_RX #(.BAUD_DIV(BAUD_LB)) u_lb (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_txd),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    always @(posedge clk) begin
        if (rx_valid && got_cnt < 16) begin
            got[got_cnt] = rx_data;
            got_cnt = got_cnt + 1;
        end
    end

    // ================= 检查任务 =================
    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    // ================= 主流程 =================
    integer watch;
    initial begin
        for (i = 0; i < 1024; i = i + 1) fb[i] = 8'h00;
        repeat (10) @(posedge clk);
        rst = 1'b0;                        // 放开复位，CPU 开始跑

        // 等 CPU 打印完 "LCD OK\r\n"（说明 LCD 流程已经走完）
        for (watch = 0; watch < 400000; watch = watch + 1) begin
            if (got_cnt >= 8) watch = 400000;
            else #20;
        end
        repeat (200) @(posedge clk);        #1;   // 等总线/帧缓存稳定

        $display("---- LCD bus: %0d commands, %0d data bytes ----", n_cmd, n_dat);
        // 命令数 = 初始化 15 条（表里 19 项，其中 4 项是"等电源稳定"标记，不产生总线动作）
        //          + 清屏 8 页 × 3 = 24 + 图案 12 = 51
        chk("UART receipt complete (8 bytes)", got_cnt == 8);
        chk("UART msg[0]='L'", got[0] === 8'h4C);
        chk("UART msg[1]='C'", got[1] === 8'h43);
        chk("UART msg[2]='D'", got[2] === 8'h44);
        chk("UART msg[3]=' '", got[3] === 8'h20);
        chk("UART msg[4]='O'", got[4] === 8'h4F);
        chk("UART msg[5]='K'", got[5] === 8'h4B);
        chk("UART msg[6]=CR",  got[6] === 8'h0D);
        chk("UART msg[7]=LF",  got[7] === 8'h0A);

        chk("LCD command count = 51",     n_cmd == 51);
        chk("LCD data count = 1232",      n_dat == 1232);

        // 帧缓存逐字节比对（LCD 总线上真正收到的数据 vs Python 渲染的期望图案）
        fb_err = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            if (fb[i] !== exp_fb[i]) begin
                if (fb_err < 6)
                    $display("  fb mismatch: page %0d col %0d expected 0x%02X got 0x%02X",
                             i / 128, i % 128, exp_fb[i], fb[i]);
                fb_err = fb_err + 1;
            end
        end
        if (fb_err != 0) $display("  total framebuffer mismatch cells: %0d", fb_err);
        chk("framebuffer == expected image", fb_err == 0);
        err = err + fb_err;

        if (err == 0) $display("==== tb_EES338_lcd: ALL PASS ====");
        else          $display("==== tb_EES338_lcd: %0d FAIL ====", err);
        $finish;
    end

    // 看门狗
    initial begin
        #80000000;
        $display("FAIL: tb_EES338_lcd timeout (uart bytes %0d)", got_cnt);
        $finish;
    end

endmodule
