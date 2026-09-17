`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_btcfg.v - 蓝牙模式脚扫描（bt_cfg.hex）验证
//
//  程序把 BT_CTRL(0x1000_0018) 的 3 个模式位组合成 8 种，每种"先复位再按组合释放"，
//  本 tb 检查：
//    ① 对 BT_CTRL 的写序列 = 每种组合两条（复位值 0x01|k<<1、释放值 0x11|k<<1）
//    ② 串口打印 "BT CFG SWEEP" + "T<k> m.. h.. s.." 共 8 行
//    ③ 蓝牙电源位 bt_pw_on 始终为 1
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_btcfg;

    localparam HEX_F = "../../../../Lab2.file/bt_cfg.hex";
    localparam DAT_F = "../../../../Lab2.file/bt_cfg_mem.hex";
    localparam integer BAUD_UP = 20;

    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;

    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;
    wire bt_pw_on, bt_master_slave, bt_sw_hw, bt_sw, bt_rst_n;

    EES338_Core #(
        .HEX_FILE      (HEX_F),
        .DATA_FILE     (DAT_F),
        .BAUD_DIV      (BAUD_UP),
        .LCD_RST_CYCLES(20),
        .TIMER_DELAY   (64),
        .BT_RST_CYCLES (200)
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .bt_rxd   (bt_rxd),
        .bt_txd   (bt_txd),
        .bt_pw_on        (bt_pw_on),
        .bt_master_slave (bt_master_slave),
        .bt_sw_hw        (bt_sw_hw),
        .bt_sw           (bt_sw),
        .bt_rst_n        (bt_rst_n),
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

    // ---------------- 记录 BT_CTRL 写序列 ----------------
    reg [4:0] ctrl_seen [0:31];
    integer   n_ctrl = 0;

    always @(posedge clk) begin
        if (!rst && uut.memio_write && (uut.memio_addr == 32'h1000_0018)) begin
            if (n_ctrl < 32) ctrl_seen[n_ctrl] = uut.memio_wdata[4:0];
            n_ctrl = n_ctrl + 1;
        end
    end

    // ---------------- USB-UART 内容 ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] uart [0:1023];
    integer    ucnt = 0, err = 0, watch, j, hit;

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
        integer i2; reg ok;
        begin
            ok = 1'b1;
            for (i2 = 0; i2 < slen; i2 = i2 + 1)
                if (uart[start+i2] !== s[8*(slen-1-i2)+:8]) ok = 1'b0;
            match_at = ok;
        end
    endfunction

    task chk_str(input [255:0] s, input integer slen, input [255:0] name);
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

    integer k, exp_rst, exp_rel;
    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        rst = 0;

        // 等 8 种组合都跑完（至少 16 次 BT_CTRL 写）并把最后一行打印完
        for (watch = 0; watch < 2000000; watch = watch + 1) begin
            if (n_ctrl >= 16 && ucnt >= 120) watch = 2000000;
            else #20;
        end
        repeat (2000) @(posedge clk);

        $display("---- BT_CTRL 写了 %0d 次，串口收到 %0d 字节 ----", n_ctrl, ucnt);

        if (n_ctrl < 16) begin
            $display("FAIL: BT_CTRL 写次数不足（%0d < 16）", n_ctrl);
            err = err + 1;
        end
        // ① 检查写序列：每组 = 复位值 0x01|k<<1、释放值 0x11|k<<1
        for (k = 0; k < 8; k = k + 1) begin
            exp_rst = 5'h01 | (k << 1);
            exp_rel = 5'h11 | (k << 1);
            if (ctrl_seen[2*k] !== exp_rst || ctrl_seen[2*k+1] !== exp_rel) begin
                $display("FAIL: 第 %0d 组 BT_CTRL 值 = %h / %h，期望 %h / %h",
                         k, ctrl_seen[2*k], ctrl_seen[2*k+1], exp_rst, exp_rel);
                err = err + 1;
            end
        end
        if (err == 0) $display("PASS: 8 组 BT_CTRL 写序列正确（每组先复位后释放）");

        // ② 串口文本
        chk_str("BT CFG SWEEP", 12, "横幅 BT CFG SWEEP");
        chk_str("T0 m0 h0 s0", 11, "组合 0 标记");
        chk_str("T7 m1 h1 s1", 11, "组合 7 标记");

        // ③ 电源位
        if (bt_pw_on !== 1'b1) begin
            $display("FAIL: bt_pw_on 应为 1"); err = err + 1;
        end else $display("PASS: bt_pw_on = 1");

        $display("==================================================");
        if (err == 0) $display("==== tb_EES338_btcfg: ALL PASS ====");
        else          $display("==== tb_EES338_btcfg: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: tb_EES338_btcfg 超时（n_ctrl=%0d, uart=%0d）", n_ctrl, ucnt);
        $finish;
    end

endmodule
