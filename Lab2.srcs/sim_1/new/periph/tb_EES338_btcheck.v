`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_btcheck.v - 蓝牙自检程序 + 硬件环回（模拟上板短接 N2↔L3）
//
//  把 DUT 的 bt_txd 直接接回 bt_rxd（= 上板用跳线短接 N2↔L3 的环回自检）：
//   程序每 ~0.4s（仿真里是 TIMER_DELAY 拍）发一个 'K'，环回后自己收到，
//   再通过 USB-UART 打印 "RX=K" → 证明 FPGA 侧蓝牙收发通道与引脚方向都正确。
//  检查项：① 串口先打印 "BT SELF-TEST"；② 串口反复出现 "RX=K"
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_btcheck;

    localparam HEX_F = "../../../../Lab2.file/bt_check.hex";
    localparam DAT_F = "../../../../Lab2.file/bt_check_mem.hex";
    localparam integer BAUD_UP = 20;       // USB-UART（仿真用高速）
    localparam integer BAUD_BT = 5208;     // 蓝牙 9600 @50MHz

    reg clk = 0;
    always #10 clk = ~clk;

    reg  rst = 1'b1;
    reg  uart_rxd = 1'b1;
    wire uart_txd;
    wire bt_txd;
    wire bt_rxd;
    wire [7:0] lcd_d;
    wire lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n;
    wire [7:0] seg_grp0, seg_grp1;
    wire [3:0] dn0, dn1;

    // ★ 环回：bt_txd -> bt_rxd（对应上板"短接 N2 与 L3"）
    assign bt_rxd = bt_txd;

    EES338_Core #(
        .HEX_FILE    (HEX_F),
        .DATA_FILE   (DAT_F),
        .BAUD_DIV    (BAUD_UP),
        .TIMER_DELAY (64)
    ) dut (
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
        .seg_grp0 (seg_grp0),
        .dn0      (dn0),
        .seg_grp1 (seg_grp1),
        .dn1      (dn1)
    );

    // USB-UART 接收模型（收集打印内容）
    wire [7:0] rx_data;
    wire       rx_valid;
    reg [7:0]  got [0:511];
    integer    got_cnt = 0;

    UART_RX #(.BAUD_DIV(BAUD_UP)) u_lb (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_txd),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    always @(posedge clk) begin
        if (rx_valid && got_cnt < 512) begin
            got[got_cnt] = rx_data;
            got_cnt      = got_cnt + 1;
        end
    end

    integer err = 0;
    integer i, k, n_rxk, n_hit, watch;

    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst = 1'b0;

        // 等串口收到足够内容（"BT SELF-TEST\r\n" + 至少 2 条 "RX=K\r\n"）
        for (watch = 0; watch < 400000; watch = watch + 1) begin
            if (got_cnt >= 60) watch = 400000;
            else #20;
        end
        repeat (2000) @(posedge clk);

        $display("---- USB-UART 收到 %0d 字节 ----", got_cnt);

        // ① 开头的自检提示
        n_hit = 0;
        for (i = 0; i + 12 <= got_cnt; i = i + 1) begin
            if (got[i] === "B" && got[i+1] === "T" && got[i+2] === " " &&
                got[i+3] === "S" && got[i+4] === "E" && got[i+5] === "L" &&
                got[i+6] === "F" && got[i+7] === "-")
                n_hit = n_hit + 1;
        end
        chk("UART prints BT SELF-TEST banner", n_hit >= 1);

        // ② 环回：反复出现 "RX=K"
        n_rxk = 0;
        for (i = 0; i + 4 <= got_cnt; i = i + 1) begin
            if (got[i] === "R" && got[i+1] === "X" && got[i+2] === "=" && got[i+3] === "K")
                n_rxk = n_rxk + 1;
        end
        $display("---- 环回收到 'K' 共 %0d 次 ----", n_rxk);
        chk("BT loopback returns K repeatedly", n_rxk >= 2);

        if (err == 0) $display("==== tb_EES338_btcheck: ALL PASS ====");
        else          $display("==== tb_EES338_btcheck: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #40000000;
        $display("FAIL: tb_EES338_btcheck timeout (uart=%0d)", got_cnt);
        $finish;
    end

endmodule
