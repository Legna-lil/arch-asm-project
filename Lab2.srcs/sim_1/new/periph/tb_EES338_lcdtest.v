`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_lcdtest.v - LCD 自检 v3（lcd_test.hex）的上板行为验证
//
//  v3 每种配置（k = rstp*4 + swap*2 + variant）依次：
//    ① 写 LCD_CTRL（调试开关+硬复位）→ 初始化表（15 条命令，DELAY 条目不上总线）
//    ② 0xA5（全屏点亮）→ 0xAF（开显示保险）→ 0xA4（恢复正常）
//    ③ 半屏图案：8 页 × (0xB0|页, 0x10, 0x00 命令 + 64 字节 0xFF + 64 字节 0x00)
//    ④ 对比度扫描：8 组 (0x81, EV = 0,8,16,...,56)
//  命令数 = 15 + 3 + 24 + 16 = 58；数据字节 = 8×128 = 1024
//
//  本 tb 直接在 MMIO 总线上按"写 LCD_CTRL"切分配置，逐配置核对命令序列、
//  数据图案与串口输出。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_lcdtest;

    localparam HEX_F = "../../../../Lab2.file/lcd_test.hex";
    localparam DAT_F = "../../../../Lab2.file/lcd_test_mem.hex";
    localparam integer BAUD_UP = 20;       // 仿真用"高速串口"（真实 115200 → 434）
    localparam integer N_CFG   = 8;

    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;

    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;

    EES338_Core #(
        .HEX_FILE      (HEX_F),
        .DATA_FILE     (DAT_F),
        .BAUD_DIV      (BAUD_UP),
        .LCD_RST_CYCLES(200),          // 仿真里缩短上电复位脉宽
        .TIMER_DELAY   (64)            // 仿真里延时缩短为 64 拍
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .bt_rxd   (bt_rxd),
        .bt_txd   (bt_txd),
        .lcd_d    (),
        .lcd_wr_n (),
        .lcd_rd_n (),
        .lcd_cs_n (),
        .lcd_rs   (),
        .lcd_rst_n(),
        .seg_grp0 (),
        .dn0      (),
        .seg_grp1 (),
        .dn1      ()
    );

    // ---------------- 采集 LCD 总线上的命令/数据 ----------------
    reg [7:0]  cmd [0:63];
    reg [7:0]  dat [0:1023];
    integer    cmd_cnt = 0, dat_cnt = 0, n_cfg = 0, err = 0, i, k, watch;

    always @(posedge clk) begin
        if (!rst && uut.memio_write && (uut.memio_addr[31:16] == 16'h1000)) begin
            if (uut.memio_addr == 32'h1000_0100) begin
                if (cmd_cnt < 64) cmd[cmd_cnt] = uut.memio_wdata[7:0];
                cmd_cnt = cmd_cnt + 1;
            end
            else if (uut.memio_addr == 32'h1000_0104) begin
                if (dat_cnt < 1024) dat[dat_cnt] = uut.memio_wdata[7:0];
                dat_cnt = dat_cnt + 1;
            end
            else if (uut.memio_addr == 32'h1000_010C) begin
                // LCD_CTRL 写 = 新配置开始：先把刚结束的那一配置核对完
                if (n_cfg > 0) check_cfg(n_cfg - 1);
                n_cfg   = n_cfg + 1;
                cmd_cnt = 0;
                dat_cnt = 0;
            end
        end
    end

    task check_cfg(input integer cfg);
        integer p, c, base, eb;
        begin
            eb = cfg & 1;                       // 初始化变体
            if (cmd_cnt != 58 || dat_cnt != 1024) begin
                $display("FAIL: 配置 %0d 命令数=%0d(期望58) 数据数=%0d(期望1024)",
                         cfg, cmd_cnt, dat_cnt);
                err = err + 1;
            end
            // ---- 初始化 15 条 ----
            if (cmd[0] !== 8'hE2 || cmd[1] !== 8'hAE ||
                cmd[2] !== (eb ? 8'hA3 : 8'hA2) ||
                cmd[3] !== 8'hA0 || cmd[4] !== 8'hC8 || cmd[5] !== 8'hA6 ||
                cmd[6] !== 8'hA4 || cmd[7] !== 8'h40 ||
                cmd[8] !== (eb ? 8'h25 : 8'h24) ||
                cmd[9] !== 8'h81 || cmd[10] !== (eb ? 8'h30 : 8'h28) ||
                cmd[11] !== 8'h2C || cmd[12] !== 8'h2E || cmd[13] !== 8'h2F ||
                cmd[14] !== 8'hAF) begin
                $display("FAIL: 配置 %0d 初始化命令序列不对", cfg);
                $display("      got = %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                         cmd[0],cmd[1],cmd[2],cmd[3],cmd[4],cmd[5],cmd[6],cmd[7],
                         cmd[8],cmd[9],cmd[10],cmd[11],cmd[12],cmd[13],cmd[14]);
                err = err + 1;
            end
            // ---- 0xA5 / 0xAF / 0xA4 ----
            if (cmd[15] !== 8'hA5 || cmd[16] !== 8'hAF || cmd[17] !== 8'hA4) begin
                $display("FAIL: 配置 %0d 全屏点亮命令不对: %h %h %h",
                         cfg, cmd[15], cmd[16], cmd[17]);
                err = err + 1;
            end
            // ---- 8 页 × (0xB0|页, 0x10, 0x00) ----
            for (p = 0; p < 8; p = p + 1) begin
                base = 18 + 3 * p;
                if (cmd[base] !== (8'hB0 | p) || cmd[base+1] !== 8'h10 ||
                    cmd[base+2] !== 8'h00) begin
                    $display("FAIL: 配置 %0d 第 %0d 页命令不对: %h %h %h",
                             cfg, p, cmd[base], cmd[base+1], cmd[base+2]);
                    err = err + 1;
                end
            end
            // ---- 8 组对比度 (0x81, i*8) ----
            for (i = 0; i < 8; i = i + 1) begin
                base = 42 + 2 * i;
                if (cmd[base] !== 8'h81 || cmd[base+1] !== (i * 8)) begin
                    $display("FAIL: 配置 %0d 第 %0d 档对比度不对: %h %h",
                             cfg, i, cmd[base], cmd[base+1]);
                    err = err + 1;
                end
            end
            // ---- 数据：每页前 64 字节 0xFF、后 64 字节 0x00 ----
            for (p = 0; p < 8; p = p + 1) begin
                for (c = 0; c < 128; c = c + 1) begin
                    if (dat[p*128 + c] !== (c < 64 ? 8'hFF : 8'h00)) begin
                        $display("FAIL: 配置 %0d 页 %0d 第 %0d 字节 = %h（期望 %h）",
                                 cfg, p, c, dat[p*128+c], (c < 64) ? 8'hFF : 8'h00);
                        err = err + 1;
                    end
                end
            end
        end
    endtask

    // ---------------- 串口内容（核对进度字符串）----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] uart [0:1023];
    integer    ucnt = 0;

    UART_RX #(.BAUD_DIV(BAUD_UP)) u_lb (
        .clk(clk), .rst(rst), .uart_rxd(uart_txd),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );
    always @(posedge clk)
        if (rx_valid && ucnt < 1024) begin
            uart[ucnt] = rx_data;
            ucnt = ucnt + 1;
        end

    function match_at(input integer start, input [255:0] s, input integer slen);
        integer j; reg ok;
        begin
            ok = 1'b1;
            for (j = 0; j < slen; j = j + 1)
                if (uart[start+j] !== s[8*(slen-1-j)+:8]) ok = 1'b0;
            match_at = ok;
        end
    endfunction

    task chk_str(input [255:0] s, input integer slen, input [255:0] name);
        integer j, hit;
        begin
            hit = 0;
            for (j = 0; j + slen <= ucnt; j = j + 1)
                if (match_at(j, s, slen)) hit = hit + 1;
            if (hit == 0) begin
                $display("FAIL: 串口未出现 %0s", name);
                err = err + 1;
            end
            else $display("PASS: 串口出现 %0s（%0d 次）", name, hit);
        end
    endtask

    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        rst = 0;

        // 等 9 次配置切换（8 种跑完 + 回到第 0 种）
        for (watch = 0; watch < 4000000; watch = watch + 1) begin
            if (n_cfg >= N_CFG + 1) watch = 4000000;
            else #20;
        end
        repeat (3000) @(posedge clk);

        $display("---- 共切分到 %0d 段配置，串口收到 %0d 字节 ----", n_cfg, ucnt);
        if (n_cfg < N_CFG + 1) begin
            $display("FAIL: 配置数不足（%0d < %0d）", n_cfg, N_CFG + 1);
            err = err + 1;
        end

        chk_str("LCD TEST3", 9, "横幅 LCD TEST3");
        chk_str("C0", 2, "配置号 C0");
        chk_str("EV01234567", 10, "对比度扫描进度 EV01234567");

        $display("==================================================");
        if (err == 0) $display("==== tb_EES338_lcdtest: ALL PASS ====");
        else          $display("==== tb_EES338_lcdtest: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #60000000;      // 60ms 上限
        $display("FAIL: tb_EES338_lcdtest 超时（n_cfg=%0d, uart=%0d）", n_cfg, ucnt);
        $finish;
    end

endmodule

