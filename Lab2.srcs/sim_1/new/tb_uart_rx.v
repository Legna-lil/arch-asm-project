`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_uart_rx.v - UART_RX 单元测试
//  用时间模型逐 bit 驱动 rxd（起始位/8数据位LSB先发/停止位），
//  用一个 always 记录 rx_valid 事件，主流程校验 rx_data。
//////////////////////////////////////////////////////////////////////////////////
module tb_uart_rx;

    reg        clk = 0;
    reg        rst = 1;
    reg        uart_rxd;
    wire [7:0] rx_data;
    wire       rx_valid;

    localparam integer FULL = 20;              // 每 bit 20 个 10ns = 200ns
    localparam integer BIT  = 200;             // ns

    integer err_cnt;

    // rx_valid 事件记录（在主流程驱动字节期间异步到来）
    reg [7:0] ev_data;
    integer   ev_cnt = 0;
    always @(posedge clk) begin
        if (rx_valid) begin
            ev_data <= rx_data;
            ev_cnt  <= ev_cnt + 1;
        end
    end

    UART_RX #(.BAUD_DIV(FULL)) dut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    always #5 clk = ~clk;

    // 以标准 UART 时序驱动一字节（LSB first）
    task automatic drive_byte;
        input [7:0] d;
        integer k;
        begin
            @(negedge clk);          // 避开时钟上升沿，稳定驱动
            uart_rxd = 1'b1; #BIT;   // 空闲
            uart_rxd = 1'b0; #BIT;   // 起始位
            for (k = 0; k < 8; k = k + 1) begin
                uart_rxd = d[k];
                #BIT;
            end
            uart_rxd = 1'b1; #BIT;   // 停止位
            #(BIT*2);                // 帧间隔
        end
    endtask

    initial begin
        err_cnt  = 0;
        uart_rxd = 1'b1;

        #20 rst = 0;
        #50;

        // 依次送入多种数据，验证中点采样与 LSB 先收
        drive_byte(8'hA5);
        wait (ev_cnt >= 1);
        @(negedge clk);
        if (ev_data == 8'hA5) $display("PASS: rx 0xA5");
        else begin
            $display("FAIL: expect 0xA5, got 0x%02X", ev_data);
            err_cnt = err_cnt + 1;
        end

        drive_byte(8'h00);
        wait (ev_cnt >= 2);
        @(negedge clk);
        if (ev_data == 8'h00) $display("PASS: rx 0x00");
        else begin
            $display("FAIL: expect 0x00, got 0x%02X", ev_data);
            err_cnt = err_cnt + 1;
        end

        drive_byte(8'hFF);
        wait (ev_cnt >= 3);
        @(negedge clk);
        if (ev_data == 8'hFF) $display("PASS: rx 0xFF");
        else begin
            $display("FAIL: expect 0xFF, got 0x%02X", ev_data);
            err_cnt = err_cnt + 1;
        end

        drive_byte(8'h5A);
        wait (ev_cnt >= 4);
        @(negedge clk);
        if (ev_data == 8'h5A) $display("PASS: rx 0x5A");
        else begin
            $display("FAIL: expect 0x5A, got 0x%02X", ev_data);
            err_cnt = err_cnt + 1;
        end

        if (err_cnt == 0)
            $display("==== tb_uart_rx: ALL PASS ====");
        else
            $display("==== tb_uart_rx: %0d FAIL ====", err_cnt);
        $finish;
    end

endmodule
