`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_btat.v - 蓝牙 AT 探针（bt_at.hex）验证
//
//  本 tb 扮演 BLE 模组：用 UART_RX 收 FPGA 发到 bt_txd 的字节，每收到一个字节
//  就回 "OK\r\n"（模拟 HM-10/CC41-A 对 AT 命令的应答），再用 UART_TX 送进 bt_rxd。
//  程序应把回显打到 USB-UART：期望看到 "A: OK" / "B: OK" / "C: OK"。
//
//  仿真参数：BT 波特率分频改为 20（真实 9600→5208）加快仿真；
//            硬件延时窗口 4000 拍（真实 0.4s）以便装下 4 字节回显。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_btat;

    localparam HEX_F  = "../../../../Lab2.file/bt_at.hex";
    localparam DAT_F  = "../../../../Lab2.file/bt_at_mem.hex";
    localparam integer BAUD_UP = 20;     // USB-UART（仿真加速）
    localparam integer BAUD_BT = 20;     // 蓝牙（仿真加速）

    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;

    reg  uart_rxd = 1'b1;
    wire bt_rxd;                    // 由本 tb 的"模组"UART_TX 驱动（不能用 reg）
    wire uart_txd, bt_txd;
    wire bt_pw_on, bt_master_slave, bt_sw_hw, bt_sw, bt_rst_n;
    integer bt_rst_fall = 0, bt_rst_rise = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (bt_rst_n === 1'b0) bt_rst_fall = bt_rst_fall + 1;
            else                   bt_rst_rise = bt_rst_rise + 1;
        end
    end

    EES338_Core #(
        .HEX_FILE      (HEX_F),
        .DATA_FILE     (DAT_F),
        .BAUD_DIV      (BAUD_UP),
        .BAUD_DIV_BT   (BAUD_BT),
        .LCD_RST_CYCLES(20),
        .TIMER_DELAY   (4000),
        .BT_RST_CYCLES (200)           // 仿真里缩短蓝牙复位脉宽
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

    // ---------------- 扮演 BLE 模组 ----------------
    wire [7:0] m_rx;
    wire       m_rx_v;
    UART_RX #(.BAUD_DIV(BAUD_BT)) u_mod_rx (
        .clk(clk), .rst(rst), .uart_rxd(bt_txd),
        .rx_data(m_rx), .rx_valid(m_rx_v)
    );

    reg  [7:0] q [0:31];
    reg  [5:0] q_wr = 0, q_rd = 0;
    reg        tx_start = 0;
    reg  [7:0] tx_byte  = 8'h00;
    wire       m_tx_busy;
    integer    mod_rx_cnt = 0;
    integer    quiet = 0;
    reg        pend  = 0;
    localparam integer QUIET_N = 2000;    // 收完命令后静默这么久才回复（模拟模组处理时间）

    UART_TX #(.BAUD_DIV(BAUD_BT)) u_mod_tx (
        .clk(clk), .rst(rst), .tx_start(tx_start),
        .tx_data(tx_byte), .tx_busy(m_tx_busy), .uart_txd(bt_rxd)
    );

    always @(posedge clk) begin
        if (rst) begin
            q_wr <= 0; q_rd <= 0; tx_start <= 0; mod_rx_cnt = 0;
            quiet = 0; pend = 0;
        end
        else begin
            // 收到一个字节 → 记下"有命令待回复"，并重置静默计时
            if (m_rx_v) begin
                $display("[MOD] RX %h (%0d)", m_rx, mod_rx_cnt);
                mod_rx_cnt = mod_rx_cnt + 1;
                quiet = 0;
                pend  = 1;
            end
            else if (pend && quiet < QUIET_N)
                quiet = quiet + 1;

            // 命令发完、静默到期 → 回 "OK\r\n"（模拟 HM-10/CC41-A 的 AT 应答）
            if (pend && quiet >= QUIET_N) begin
                $display("[MOD] reply OK+CRLF");
                q[q_wr]     <= "O";
                q[q_wr + 1] <= "K";
                q[q_wr + 2] <= 8'h0D;
                q[q_wr + 3] <= 8'h0A;
                q_wr <= q_wr + 4;
                pend = 0;
            end

            // 发送器空闲且有排队字节 → 取出一个字节并触发一次发送
            if (!m_tx_busy && (q_rd != q_wr) && !tx_start) begin
                tx_byte  <= q[q_rd];
                tx_start <= 1'b1;
                q_rd     <= q_rd + 1;
            end
            else tx_start <= 1'b0;
        end
    end

    // ---------------- USB-UART 侧内容 ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] uart [0:2047];
    integer    ucnt = 0, err = 0, watch, j, hit;

    // ---- 调试探针 ----
    integer bt_edge = 0, bt_rdy_cnt = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (bt_rxd !== 1'b1) bt_edge = bt_edge + 1;                 // 线上低电平拍数
            if (uut.periph_inst.bt_rx_rdy) bt_rdy_cnt = bt_rdy_cnt + 1; // RX_READY 拍数
        end
    end

    UART_RX #(.BAUD_DIV(BAUD_UP)) u_lb (
        .clk(clk), .rst(rst), .uart_rxd(uart_txd),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );
    always @(posedge clk)
        if (rx_valid && ucnt < 2048) begin
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

        // 等模组答完 A/B 两轮（每轮 4 字节回显）
        for (watch = 0; watch < 200000; watch = watch + 1) begin
            if (ucnt >= 44 && mod_rx_cnt >= 6) watch = 200000;
            else #20;
        end
        repeat (3000) @(posedge clk);

        $display("---- 模组收到 %0d 字节，USB-UART 打印 %0d 字节，bt_rxd 低 %0d 拍，RX_READY %0d 拍 ----",
                 mod_rx_cnt, ucnt, bt_edge, bt_rdy_cnt);
        $write("USB 收到的字节: ");
        for (j = 0; j < ucnt && j < 48; j = j + 1) $write("%h ", uart[j]);
        $write("\n");
        chk_str("BT AT PROBE", 11, "横幅 BT AT PROBE");
        chk_str("A: OK", 5, "AT 回复 OK");
        chk_str("B: OK", 5, "AT\\r\\n 回复 OK");

        // ---- 蓝牙模块控制脚（官方 lab08：必须由 FPGA 驱动）----
        $display("---- BT 控制脚：pw_on=%b m_s=%b sw_hw=%b sw=%b rst_n=%b (低%0d拍/高%0d拍)",
                 bt_pw_on, bt_master_slave, bt_sw_hw, bt_sw, bt_rst_n, bt_rst_fall, bt_rst_rise);
        if (bt_pw_on !== 1'b1) begin
            $display("FAIL: bt_pw_on 应为 1（模块上电）"); err = err + 1;
        end else $display("PASS: bt_pw_on = 1（模块上电）");
        if (bt_master_slave !== 1'b1) begin
            $display("FAIL: bt_master_slave 应为 1（从模式，手机可连）"); err = err + 1;
        end else $display("PASS: bt_master_slave = 1（从模式）");
        if (bt_rst_rise == 0 || bt_rst_fall == 0) begin
            $display("FAIL: bt_rst_n 没有出现低到高的复位序列"); err = err + 1;
        end else $display("PASS: bt_rst_n 出现复位序列（先低 %0d 拍，后高）", bt_rst_fall);

        $display("==================================================");
        if (err == 0) $display("==== tb_EES338_btat: ALL PASS ====");
        else          $display("==== tb_EES338_btat: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: tb_EES338_btat 超时（模组收到 %0d，串口 %0d）", mod_rx_cnt, ucnt);
        $finish;
    end

endmodule
