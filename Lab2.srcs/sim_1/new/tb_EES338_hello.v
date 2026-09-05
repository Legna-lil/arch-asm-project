`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_hello.v - 板级 SoC 系统测试（Hello 打印）
//  EES338Top 装入 uart_hello 程序，CPU 轮询 TX 并发送字符串。
//  测试平台在 uart_txd 上按 115200 时序采样，还原出字节流并与期望串比对。
//  时钟 10ns = 100MHz，BAUD_DIV=868（与板上一致）。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_hello;

    reg clk = 0;
    reg rst_btn = 1'b1;      // P15 复位键，测试中不按（依赖板上电自动复位）
    reg uart_rxd = 1'b1;     // 本测试只用 TX，RX 保持空闲高
    wire uart_txd;
    wire led0;

    localparam integer BIT = 8680;      // ns：115200 bps 的一个 bit 在 100MHz 下为 8680ns

    reg [7:0] exp_chars [0:16];         // "Hello, EES-338!\r\n"
    reg [7:0] got_chars [0:63];         // 每 burst 两条(34B) + 余量
    integer   got_cnt = 0;
    integer   err_cnt;
    integer   rx_i;      // 预留
    integer   chk_j;     // 校验专用

    EES338Top #(
        .HEX_FILE ("E:/VivadoProject/Lab2/Lab2.file/uart_hello.hex"),
        .DATA_FILE("E:/VivadoProject/Lab2/Lab2.file/uart_hello_mem.hex")
    ) dut (
        .sys_clk (clk),
        .rst_btn (rst_btn),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .led0    (led0)
    );

    always #5 clk = ~clk;

    // ---------------- UART 接收模型：硬件 RX 模块还原 TX 线上字节 ----------------
    // 用与发送端同一时钟/波特率的 UART_RX 收下字节，逐拍存入 got_chars。
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
                $display("FAIL: captured more than 64 chars (overrun)");
                $finish;
            end
        end
    end

    // ---------------- 主测试 ----------------
    initial begin
        // 期望串：Hello, EES-338! CR LF
        exp_chars[ 0] = "H"; exp_chars[ 1] = "e"; exp_chars[ 2] = "l";
        exp_chars[ 3] = "l"; exp_chars[ 4] = "o"; exp_chars[ 5] = ",";
        exp_chars[ 6] = " "; exp_chars[ 7] = "E"; exp_chars[ 8] = "E";
        exp_chars[ 9] = "S"; exp_chars[10] = "-"; exp_chars[11] = "3";
        exp_chars[12] = "3"; exp_chars[13] = "8"; exp_chars[14] = "!";
        exp_chars[15] = 8'h0D; exp_chars[16] = 8'h0A;   // \r \n
        err_cnt = 0;

        #10;                                // 清 tb 内部初值
        // 等待 CPU 启动并打印完成（上电自动复位 ~2.6us + 17 字符 * ~87us）
        #6000000;                            // 6ms

        $display("================================================");
        $display("tb_EES338_hello: got %0d chars", got_cnt);

        if (got_cnt < 34) begin
            $display("FAIL: expected 2 full hello copies (34B), got %0d", got_cnt);
            err_cnt = err_cnt + 1;
        end
        else begin
            // 校验第一条与第二条（两条紧连，用于对抗“空闲后丢开头”）
            for (chk_j = 0; chk_j < 17; chk_j = chk_j + 1) begin
                if (got_chars[chk_j] != exp_chars[chk_j]) begin
                    $display("FAIL: line1 char[%0d] expected 0x%02X got 0x%02X",
                             chk_j, exp_chars[chk_j], got_chars[chk_j]);
                    err_cnt = err_cnt + 1;
                end
                if (got_chars[17+chk_j] != exp_chars[chk_j]) begin
                    $display("FAIL: line2 char[%0d] expected 0x%02X got 0x%02X",
                             chk_j, exp_chars[chk_j], got_chars[17+chk_j]);
                    err_cnt = err_cnt + 1;
                end
            end
        end

        // 打印实际收到的字符串（可读）
        $write("received: \"");
        for (chk_j = 0; chk_j < got_cnt; chk_j = chk_j + 1) begin
            if (got_chars[chk_j] >= 8'h20 && got_chars[chk_j] <= 8'h7E)
                $write("%c", got_chars[chk_j]);
            else
                $write("<%02x>", got_chars[chk_j]);
        end
        $display("\"");

        if (err_cnt == 0)
            $display("==== tb_EES338_hello: ALL PASS ====");
        else
            $display("==== tb_EES338_hello: %0d FAIL ====", err_cnt);
        $finish;
    end

endmodule
