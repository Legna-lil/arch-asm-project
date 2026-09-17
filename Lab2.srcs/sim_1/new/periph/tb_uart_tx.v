`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_uart_tx.v - UART_TX 单元测试
//  验证：空闲高电平 / 起始位低 / 8 数据位 LSB 先发 / 停止位高 / busy 时序
//  时钟 10ns，BAUD_DIV=20（每 bit 200ns），在每位中心采样比对。
//////////////////////////////////////////////////////////////////////////////////
module tb_uart_tx;

    reg        clk = 0;
    reg        rst = 1;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire       uart_txd;

    localparam integer FULL = 20;              // 每 bit 20 个 10ns 周期 = 200ns
    localparam integer BIT  = 200;             // ns
    localparam integer HALF = 100;             // ns

    integer err_cnt;
    integer i;
    reg [7:0] got0, got1, got2, got3;

    UART_TX #(.BAUD_DIV(FULL)) dut (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .uart_txd (uart_txd)
    );

    always #5 clk = ~clk;

    // 发送一字节并回到空闲，返回 8 位采样结果（LSB first）
    task automatic send_and_sample;
        input  [7:0] d;
        output [7:0] got;
        integer k;
        begin
            // 等前一次发送完成
            wait (!tx_busy);
            @(posedge clk);
            tx_data  = d;        // 装载待发送字节
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;

            // 等待起始位下降沿，逐位中心采样
            wait (uart_txd == 1'b0);
            #HALF;                       // 起始位中心
            if (uart_txd !== 1'b0) begin
                $display("FAIL: start bit not low at center");
                err_cnt = err_cnt + 1;
            end
            got = 8'd0;
            for (k = 0; k < 8; k = k + 1) begin
                #BIT;                    // 数据位中心：HALF+k*BIT
                got[k] = uart_txd;
            end
            #BIT;                        // 停止位中心
            if (uart_txd !== 1'b1) begin
                $display("FAIL: stop bit not high at center");
                err_cnt = err_cnt + 1;
            end
            #BIT;                        // 帧结束回空闲
            if (uart_txd !== 1'b1 || tx_busy !== 1'b0) begin
                $display("FAIL: not back to idle after frame");
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    initial begin
        err_cnt = 0;
        tx_start = 0;
        tx_data  = 8'd0;

        #20 rst = 0;
        #30;

        // 空闲高
        if (uart_txd !== 1'b1) begin
            $display("FAIL: idle should be high");
            err_cnt = err_cnt + 1;
        end

        // 测试 0xB4 = 1011_0100，LSB 先发 -> 0,0,1,0,1,1,0,1
        send_and_sample(8'hB4, got0);
        if (got0 == 8'hB4)
            $display("PASS: 0xB4  -> 0x%02X", got0);
        else begin
            $display("FAIL: 0xB4  -> 0x%02X", got0);
            err_cnt = err_cnt + 1;
        end

        // 测试 0x3C = 0011_1100 -> 0,0,1,1,1,1,0,0
        send_and_sample(8'h3C, got1);
        if (got1 == 8'h3C)
            $display("PASS: 0x3C  -> 0x%02X", got1);
        else begin
            $display("FAIL: 0x3C  -> 0x%02X", got1);
            err_cnt = err_cnt + 1;
        end

        // 测试 0x00 与 0xFF
        send_and_sample(8'h00, got2);
        if (got2 == 8'h00)
            $display("PASS: 0x00  -> 0x%02X", got2);
        else begin
            $display("FAIL: 0x00  -> 0x%02X", got2);
            err_cnt = err_cnt + 1;
        end

        send_and_sample(8'hFF, got3);
        if (got3 == 8'hFF)
            $display("PASS: 0xFF  -> 0x%02X", got3);
        else begin
            $display("FAIL: 0xFF  -> 0x%02X", got3);
            err_cnt = err_cnt + 1;
        end

        if (err_cnt == 0)
            $display("==== tb_uart_tx: ALL PASS ====");
        else
            $display("==== tb_uart_tx: %0d FAIL ====", err_cnt);
        $finish;
    end

endmodule
