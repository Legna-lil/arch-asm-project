`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_helloecho.v - 板级 SoC 自检（TX + RX 全测）
//  程序：上电打印 "Hello, EES-338!"(17 字节) 后进入回显模式。
//  测试平台：先用硬件 UART_RX 收下打印的 17 字节并比对；
//  随后按 115200 时序向 rxd 发送 4 字节，逐一校验回显。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_helloecho;

    reg clk = 0;
    reg rst_btn = 1'b1;
    reg uart_rxd = 1'b1;
    wire uart_txd;
    wire led0;

    localparam integer BIT = 8680;      // ns（115200 一个 bit）

    reg [7:0] exp_chars [0:16];         // "Hello, EES-338!\r\n"
    reg [7:0] sent [0:3];
    reg [7:0] got_chars [0:63];
    integer   got_cnt = 0;
    integer   err_cnt;
    integer   chk_j, idx, watch;
    integer   jj;                       // send_byte 局部循环

    EES338Top #(
        .HEX_FILE ("../../../../Lab2.file/uart_helloecho.hex"),
        .DATA_FILE("../../../../Lab2.file/uart_hello_mem.hex")
    ) dut (
        .sys_clk (clk),
        .rst_btn (rst_btn),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .led0    (led0)
    );

    always #5 clk = ~clk;

    // ---------------- RX 收包模型（硬件 UART_RX） ----------------
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
            got_chars[got_cnt] = lb_data;
            got_cnt = got_cnt + 1;
            if (got_cnt > 63) begin
                $display("FAIL: overrun >64 chars");
                $finish;
            end
        end
    end

    // ---------------- 按 115200 时序发送一字节到 rxd ----------------
    task automatic send_byte;
        input [7:0] d;
        begin
            uart_rxd = 1'b1;
            #(BIT*2);
            uart_rxd = 1'b0; #BIT;   // start
            for (jj = 0; jj < 8; jj = jj + 1) begin
                uart_rxd = d[jj];
                #BIT;
            end
            uart_rxd = 1'b1; #BIT;   // stop
            uart_rxd = 1'b1;
        end
    endtask

    // ---------------- 看门狗 ----------------
    initial begin
        #40000000;
        $display("FAIL: helloecho test timeout, got %0d chars", got_cnt);
        $finish;
    end

    // ---------------- 主流程 ----------------
    initial begin
        exp_chars[ 0] = "H"; exp_chars[ 1] = "e"; exp_chars[ 2] = "l";
        exp_chars[ 3] = "l"; exp_chars[ 4] = "o"; exp_chars[ 5] = ",";
        exp_chars[ 6] = " "; exp_chars[ 7] = "E"; exp_chars[ 8] = "E";
        exp_chars[ 9] = "S"; exp_chars[10] = "-"; exp_chars[11] = "3";
        exp_chars[12] = "3"; exp_chars[13] = "8"; exp_chars[14] = "!";
        exp_chars[15] = 8'h0D; exp_chars[16] = 8'h0A;
        sent[0] = "A"; sent[1] = "b"; sent[2] = "3"; sent[3] = "!";
        err_cnt = 0;

        // 1) 等待 Hello 打印完成（17B）
        for (watch = 0; watch < 5000; watch = watch + 1) begin
            if (got_cnt >= 17) watch = 5000;
            else #1000;
        end

        $display("---- Hello TX check: got %0d chars ----", got_cnt);
        if (got_cnt < 17) begin
            $display("FAIL: no hello output (TX path problem)");
            err_cnt = err_cnt + 1;
        end
        else begin
            for (chk_j = 0; chk_j < 17; chk_j = chk_j + 1) begin
                if (got_chars[chk_j] != exp_chars[chk_j]) begin
                    $display("FAIL: hello[%0d] expected 0x%02X got 0x%02X",
                             chk_j, exp_chars[chk_j], got_chars[chk_j]);
                    err_cnt = err_cnt + 1;
                end
            end
            $write("hello received: \"");
            for (chk_j = 0; chk_j < 17; chk_j = chk_j + 1) begin
                if (got_chars[chk_j] >= 8'h20 && got_chars[chk_j] <= 8'h7E)
                    $write("%c", got_chars[chk_j]);
                else
                    $write("<%02x>", got_chars[chk_j]);
            end
            $display("\"");
        end

        #200000;   // 等 CPU 结束打印进入轮询模式

        // 2) 回显测试（回显字节从索引 17 开始）：逐字节发送并等回显
        for (idx = 0; idx < 4; idx = idx + 1) begin
            send_byte(sent[idx]);
            for (watch = 0; watch < 3000; watch = watch + 1) begin
                if (got_cnt >= 18 + idx) watch = 3000;
                else #1000;
            end
            if (got_cnt >= 18 + idx) begin
                if (got_chars[17+idx] == sent[idx])
                    $display("PASS: echo[%0d] = 0x%02X (%c)", idx,
                             got_chars[17+idx], got_chars[17+idx]);
                else begin
                    $display("FAIL: echo[%0d] expected 0x%02X got 0x%02X",
                             idx, sent[idx], got_chars[17+idx]);
                    err_cnt = err_cnt + 1;
                end
            end
            else begin
                $display("FAIL: echo[%0d] not received", idx);
                err_cnt = err_cnt + 1;
            end
        end

        if (err_cnt == 0)
            $display("==== tb_EES338_helloecho: ALL PASS ====");
        else
            $display("==== tb_EES338_helloecho: %0d FAIL ====", err_cnt);
        $finish;
    end

endmodule
