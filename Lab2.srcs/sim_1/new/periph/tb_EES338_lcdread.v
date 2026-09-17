`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_lcdread.v - LCD 读回自检（lcd_read.hex）验证
//
//  本 tb 扮演 LCD 屏：写周期不管，读周期（CS#=0 且 RD#=0）把数据总线驱动成
//  0xA5（刻意与程序写进去的 0x5A 不同，用来证明读到的数据确实来自总线），
//  然后检查程序把读回的字节打印成 "1=10100101"。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_lcdread;

    localparam HEX_F = "../../../../Lab2.file/lcd_read.hex";
    localparam DAT_F = "../../../../Lab2.file/lcd_read_mem.hex";
    localparam integer BAUD_UP = 20;

    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;

    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;

    wire [7:0] lcd_d;
    wire       lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n;

    // ---- tb 扮演 LCD：读周期把总线驱动成 0xA5 ----
    localparam [7:0] BUS_PAT = 8'hA5;
    wire rd_drive = (!lcd_cs_n && !lcd_rd_n);
    assign lcd_d = rd_drive ? BUS_PAT : 8'hZZ;

    integer rd_low_cnt = 0;

    EES338_Core #(
        .HEX_FILE      (HEX_F),
        .DATA_FILE     (DAT_F),
        .BAUD_DIV      (BAUD_UP),
        .LCD_RST_CYCLES(200),
        .TIMER_DELAY   (64)
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .bt_rxd   (bt_rxd),
        .bt_txd   (bt_txd),
        .lcd_d    (lcd_d),
        .lcd_wr_n (lcd_wr_n),
        .lcd_rd_n (lcd_rd_n),
        .lcd_cs_n (lcd_cs_n),
        .lcd_rs   (lcd_rs),
        .lcd_rst_n(lcd_rst_n),
        .seg_grp0 (),
        .dn0      (),
        .seg_grp1 (),
        .dn1      ()
    );

    // 统计读选通低电平的拍数（应有多次读周期）
    always @(posedge clk)
        if (!rst && !lcd_rd_n) rd_low_cnt = rd_low_cnt + 1;

    // ---------------- 串口内容 ----------------
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

    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        rst = 0;

        // 等到出现 "1=xxxxxxxx"（一整套读回 + 打印）
        for (watch = 0; watch < 4000000; watch = watch + 1) begin
            if (ucnt >= 40) watch = 4000000;
            else #20;
        end
        repeat (4000) @(posedge clk);

        $display("---- 串口共 %0d 字节，读选通累计低 %0d 拍 ----", ucnt, rd_low_cnt);
        chk_str("LCD READBACK", 12, "横幅 LCD READBACK");
        // 读回值应来自总线（tb 驱动 0xA5 = 10100101），与程序写进去的 0x5A 不同
        chk_str("1=10100101", 10, "读回字节 1 = 总线上的 0xA5");
        if (rd_low_cnt == 0) begin
            $display("FAIL: 从未出现读选通（RD# 一直为高）");
            err = err + 1;
        end
        else $display("PASS: 出现读选通，RD# 累计低 %0d 拍", rd_low_cnt);

        $display("==================================================");
        if (err == 0) $display("==== tb_EES338_lcdread: ALL PASS ====");
        else          $display("==== tb_EES338_lcdread: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #60000000;
        $display("FAIL: tb_EES338_lcdread 超时（uart=%0d）", ucnt);
        $finish;
    end

endmodule
