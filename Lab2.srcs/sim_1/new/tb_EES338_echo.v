`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_echo.v - 板级 SoC 系统测试（RX 回显）
//  EES338Top 装入 uart_echo 程序：PC 每发一字节，CPU 轮询 RX 后原样回发。
//  测试平台按 115200 时序向 uart_rxd 发送字节；
//  回显用另一个硬件 UART_RX 模块从 uart_txd 接收并比对。
//  时钟 10ns = 100MHz，BAUD_DIV=868（与板上一致）。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_echo;

    reg clk = 0;
    reg rst_btn = 1'b1;
    reg uart_rxd = 1'b1;
    wire uart_txd;
    wire led0;

    localparam integer BIT = 8680;      // ns

    reg [7:0] sent [0:3];
    reg [7:0] echo_chars [0:31];
    integer   echo_cnt = 0;
    integer   err_cnt;
    integer   idx, watch;
    integer   k;                        // send_byte 循环用

    EES338Top #(
        .HEX_FILE ("E:/VivadoProject/Lab2/Lab2.file/uart_echo.hex"),
        .DATA_FILE("E:/VivadoProject/Lab2/Lab2.file/uart_echo_mem.hex")
    ) dut (
        .sys_clk (clk),
        .rst_btn (rst_btn),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .led0    (led0)
    );

    always #5 clk = ~clk;

    // ---------------- 回显接收：硬件 UART_RX ----------------
    wire [7:0] lb_data;
    wire       lb_valid;
    UART_RX #(.BAUD_DIV(868)) lb (
        .clk      (clk),
        .rst      (dut.cpu_rst),
        .uart_rxd (uart_txd),
        .rx_data  (lb_data),
        .rx_valid (lb_valid)
    );

    always @(posedge clk) begin
        if (lb_valid) begin
            echo_chars[echo_cnt] = lb_data;
            echo_cnt = echo_cnt + 1;
        end
    end

    // ---------------- 按 115200 时序向 rxd 发送一字节 ----------------
    task automatic send_byte;
        input [7:0] d;
        integer j;
        begin
            uart_rxd = 1'b1;
            #(BIT*2);                // 发送前保持空闲
            uart_rxd = 1'b0; #BIT;   // 起始位
            for (j = 0; j < 8; j = j + 1) begin
                uart_rxd = d[j];
                #BIT;
            end
            uart_rxd = 1'b1; #BIT;   // 停止位
            uart_rxd = 1'b1;
        end
    endtask

    // ---------------- 看门狗 ----------------
    initial begin
        #40000000;      // 40ms
        $display("FAIL: echo test timeout");
        $finish;
    end

    // ---------------- 主测试 ----------------
    initial begin
        sent[0] = "A";   // 0x41
        sent[1] = "b";   // 0x62
        sent[2] = "3";   // 0x33
        sent[3] = "!";   // 0x21
        err_cnt = 0;

        #100000;         // 等待上电复位+程序进入轮询 (100us)

        for (idx = 0; idx < 4; idx = idx + 1) begin
            // 等前一个回显完成（除第一个外）
            if (idx > 0) begin
                for (watch = 0; watch < 1000; watch = watch + 1) begin
                    if (echo_cnt >= idx) watch = 1000;
                    else #1000;
                end
            end
            send_byte(sent[idx]);
            // 等待本字节回显
            for (watch = 0; watch < 2000; watch = watch + 1) begin
                if (echo_cnt >= idx + 1) watch = 2000;
                else #1000;
            end
        end

        #100000;   // 收尾

        $display("================================================");
        $display("tb_EES338_echo: got %0d echo chars", echo_cnt);

        if (echo_cnt < 4) begin
            $display("FAIL: expected 4 echo chars, got %0d", echo_cnt);
            err_cnt = err_cnt + 1;
        end
        for (idx = 0; idx < 4; idx = idx + 1) begin
            if (echo_cnt > idx && echo_chars[idx] != sent[idx]) begin
                $display("FAIL: echo[%0d] expected 0x%02X got 0x%02X",
                         idx, sent[idx], echo_chars[idx]);
                err_cnt = err_cnt + 1;
            end
            else if (echo_cnt > idx) begin
                $display("PASS: echo[%0d] = 0x%02X (%c)", idx,
                         echo_chars[idx], echo_chars[idx]);
            end
        end

        if (err_cnt == 0 && echo_cnt >= 4)
            $display("==== tb_EES338_echo: ALL PASS ====");
        else
            $display("==== tb_EES338_echo: %0d FAIL ====", err_cnt);
        $finish;
    end

endmodule
