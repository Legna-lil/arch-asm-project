`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_bt.v - SoC 级蓝牙(BLE-CC41-A)回显自检
//
//  顶层例化 EES338_Core（不含 MMCM），跑 "gen_uart_demo.py bt" 生成的程序：
//    CPU 轮询 0x1000_0014(BT_STATUS) -> 读 0x1000_0010(BT_DATA) -> 原样回发
//  测试平台按 9600bps（BT 模块默认波特率）向 bt_rxd 发 4 个字节，
//  用设计里的 UART_RX(BAUD_DIV=5208) 收 bt_txd，逐字节比对回显。
//
//  注：本板蓝牙模块与 USB-UART 是两条独立链路，本测试只动蓝牙那两个脚。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_bt;

    localparam HEX_F = "../../../../Lab2.file/bt_echo.hex";
    localparam DAT_F = "../../../../Lab2.file/bt_echo_mem.hex";

    localparam integer BAUD_DIV_BT = 5208;      // 50MHz / 9600
    localparam integer BIT_NS      = 104167;    // 9600bps 一个 bit ≈ 104.17us

    reg clk = 0;
    always #10 clk = ~clk;                      // 50MHz

    reg  rst      = 1'b1;
    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;
    wire [7:0] lcd_d;
    wire lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n;

    EES338_Core #(
        .HEX_FILE   (HEX_F),
        .DATA_FILE  (DAT_F),
        .BAUD_DIV_BT(BAUD_DIV_BT)
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

    // ---------------- 接收模型：复用设计里的 UART_RX ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg [7:0]  got [0:7];
    integer    got_cnt = 0;
    integer    err = 0;

    UART_RX #(.BAUD_DIV(BAUD_DIV_BT)) u_lb (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (bt_txd),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    always @(posedge clk) begin
        if (rx_valid && got_cnt < 8) begin
            got[got_cnt] = rx_data;
            got_cnt = got_cnt + 1;
        end
    end

    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    // 按 9600bps 时序往 bt_rxd 送一个字节（LSB 先发）
    integer jj;
    task send_bt_byte(input [7:0] d);
        begin
            @(posedge clk);
            bt_rxd = 1'b0; #BIT_NS;                     // 起始位
            for (jj = 0; jj < 8; jj = jj + 1) begin
                bt_rxd = d[jj];
                #BIT_NS;
            end
            bt_rxd = 1'b1; #BIT_NS;                     // 停止位
        end
    endtask

    // ---------------- 主流程 ----------------
    integer watch, idx;
    reg [7:0] sent [0:3];
    initial begin
        sent[0] = "B";  sent[1] = "l";  sent[2] = "u";  sent[3] = "e";
        repeat (10) @(posedge clk);
        rst = 1'b0;                                     // 放复位
        #2000000;                                       // 等 CPU 进入轮询循环

        for (idx = 0; idx < 4; idx = idx + 1) begin
            send_bt_byte(sent[idx]);
            for (watch = 0; watch < 4000; watch = watch + 1) begin
                if (got_cnt >= idx + 1) watch = 4000;
                else #1000;                             // 最多等 4ms
            end
            if (got_cnt >= idx + 1)
                chk("bt echo byte", got[idx] === sent[idx]);
            else begin
                $display("FAIL: bt echo[%0d] not received", idx);
                err = err + 1;
            end
        end

        if (err == 0) $display("==== tb_EES338_bt: ALL PASS (4 bytes echoed) ====");
        else          $display("==== tb_EES338_bt: %0d FAIL ====", err);
        $finish;
    end

    // 看门狗
    initial begin
        #60000000;
        $display("FAIL: tb_EES338_bt timeout (got %0d bytes)", got_cnt);
        $finish;
    end

endmodule
