`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_btseg.v - 蓝牙→数码管演示（bt_seg.hex）验证
//
//  本 tb 扮演 BLE 模组：
//    ① 按 9600bps 往 bt_rxd 发两个字节 'A'、'B'（模拟手机发字符）；
//    ② 用 UART_RX 收 bt_txd，应当**只**收到被回发的这两个字节
//       （证明这个演示**没有发 AT 命令**——AT 交互会让模组拒绝手机连接，见文档 §4.8）；
//    ③ 检查数码管 MMIO 写：最新字节在最右两位且带小数点
//       （'B'=0x42 → dig6=4|DP=0x14、dig7=2|DP=0x12；'A'=0x41 被左移到 dig4/dig5=4/1）；
//    ④ 检查 USB-UART 打印出 "BT SEG DEMO" / "RX=A" / "RX=B"。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_btseg;

    localparam HEX_F = "../../../../Lab2.file/bt_seg.hex";
    localparam DAT_F = "../../../../Lab2.file/bt_seg_mem.hex";

    localparam integer BAUD_DIV_BT = 5208;      // 50MHz / 9600（真实模组波特率）
    localparam integer BIT_NS      = 104167;    // 9600bps 一个 bit ≈ 104.17us
    localparam integer BAUD_UP     = 20;        // USB-UART（仿真加速）

    reg clk = 0;
    always #10 clk = ~clk;

    reg  rst      = 1'b1;
    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;
    wire bt_pw_on, bt_master_slave, bt_sw_hw, bt_sw, bt_rst_n;
    wire [7:0] seg_grp0, seg_grp1;
    wire [3:0] dn0, dn1;

    integer err = 0;

    EES338_Core #(
        .HEX_FILE   (HEX_F),
        .DATA_FILE  (DAT_F),
        .BAUD_DIV   (BAUD_UP),
        .BAUD_DIV_BT(BAUD_DIV_BT),
        .TIMER_DELAY(64),
        .BT_RST_CYCLES(200)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),
        .bt_rxd    (bt_rxd),
        .bt_txd    (bt_txd),
        .bt_pw_on        (bt_pw_on),
        .bt_master_slave (bt_master_slave),
        .bt_sw_hw        (bt_sw_hw),
        .bt_sw           (bt_sw),
        .bt_rst_n        (bt_rst_n),
        .lcd_d     (),
        .lcd_wr_n  (),
        .lcd_rd_n  (),
        .lcd_cs_n  (),
        .lcd_rs    (),
        .lcd_rst_n (),
        .seg_grp0  (seg_grp0),
        .dn0       (dn0),
        .seg_grp1  (seg_grp1),
        .dn1       (dn1)
    );

    // ---------------- 模组侧：收 FPGA 发来的字节（应只有回显） ----------------
    wire [7:0] mod_rx;
    wire       mod_rx_v;
    reg  [7:0] mod_got [0:7];
    integer    mod_cnt = 0;

    UART_RX #(.BAUD_DIV(BAUD_DIV_BT)) u_mod_rx (
        .clk(clk), .rst(rst), .uart_rxd(bt_txd),
        .rx_data(mod_rx), .rx_valid(mod_rx_v)
    );
    always @(posedge clk)
        if (mod_rx_v && mod_cnt < 8) begin
            mod_got[mod_cnt] = mod_rx;
            mod_cnt = mod_cnt + 1;
        end

    // ---------------- 数码管寄存器监视 ----------------
    reg [4:0] dig [0:7];
    always @(posedge clk)
        if (!rst && dut.memio_write &&
            (dut.memio_addr >= 32'h1000_0200) && (dut.memio_addr <= 32'h1000_021C))
            dig[dut.memio_addr[4:2]] <= dut.memio_wdata[4:0];

    // ---------------- USB-UART 内容 ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] uart [0:1023];
    integer    ucnt = 0, j, hit;

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

    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    // 按 9600bps 往 bt_rxd 发一个字节（LSB 先发）
    integer jj, watch;
    task send_bt_byte(input [7:0] d);
        begin
            @(posedge clk);
            bt_rxd = 1'b0; #BIT_NS;
            for (jj = 0; jj < 8; jj = jj + 1) begin
                bt_rxd = d[jj];
                #BIT_NS;
            end
            bt_rxd = 1'b1; #BIT_NS;
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst = 1'b0;
        #200000;                                     // 等 CPU 起来（上电复位 + 清屏）

        send_bt_byte(8'h41);                         // 'A'
        for (watch = 0; watch < 100000; watch = watch + 1) begin
            if (mod_cnt >= 1) watch = 100000;        // 等回显发完（9600bps 一个字节 ~1.04ms）
            else #100;
        end
        send_bt_byte(8'h42);                         // 'B'
        for (watch = 0; watch < 100000; watch = watch + 1) begin
            if (mod_cnt >= 2) watch = 100000;
            else #100;
        end

        $display("---- 模组侧收到 %0d 字节，串口收到 %0d 字节 ----", mod_cnt, ucnt);

        // ① 回显：模组侧应收到 'A'、'B'（顺序一致），且**没有别的字节**（说明未发 AT）
        chk("回显字节 1 = 'A'", mod_cnt >= 1 && mod_got[0] === 8'h41);
        chk("回显字节 2 = 'B'", mod_cnt >= 2 && mod_got[1] === 8'h42);
        chk("BT 线上只有回显、没有 AT 命令", mod_cnt == 2);

        // ② 数码管：'B' 的两位在最右且带小数点，'A' 被左移到 dig4/dig5
        chk("dig6 = 0x14 ('B' 高半字节 4 + 小数点)", dig[6] === 5'h14);
        chk("dig7 = 0x12 ('B' 低半字节 2 + 小数点)", dig[7] === 5'h12);
        chk("dig4 = 0x04 ('A' 高半字节 4)",          dig[4] === 5'h04);
        chk("dig5 = 0x01 ('A' 低半字节 1)",          dig[5] === 5'h01);

        // ③ 串口日志
        chk_str("BT SEG DEMO", 11, "横幅 BT SEG DEMO");
        chk_str("RX=A", 4, "串口打印 RX=A");
        chk_str("RX=B", 4, "串口打印 RX=B");

        // ④ 控制脚
        chk("bt_pw_on = 1", bt_pw_on === 1'b1);

        $display("==================================================");
        if (err == 0) $display("==== tb_EES338_btseg: ALL PASS ====");
        else          $display("==== tb_EES338_btseg: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #60000000;
        $display("FAIL: tb_EES338_btseg 超时（mod=%0d, uart=%0d）", mod_cnt, ucnt);
        $finish;
    end

endmodule
