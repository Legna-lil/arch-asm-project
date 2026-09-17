`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_flags.v - 溢出标志位演示程序（flags_demo.hex）上板行为验证
//
//  监视 CPU 对数码管寄存器 0x1000_0200+4i 的写，每当写满 8 位就记一帧，
//  共 5 帧（对应演示程序的 5 个场景），逐位比对标志寄存器显示是否正确：
//    从左到右：SF ZF CF OF STK(带小数点) PF SEEN CNT(溢出计数奇偶)
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_flags;

    localparam HEX_F = "../../../../Lab2.file/flags_demo.hex";
    localparam DAT_F = "../../../../Lab2.file/flags_demo_mem.hex";

    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;

    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;

    EES338_Core #(
        .HEX_FILE      (HEX_F),
        .DATA_FILE     (DAT_F),
        .LCD_RST_CYCLES(20),          // 仿真里缩短 LCD 上电复位
        .TIMER_DELAY   (64)           // 仿真里延时缩短为 64 拍（上板是 0.4s）
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .bt_rxd   (bt_rxd),
        .bt_txd   (bt_txd),
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

    reg  [4:0] snap [0:7];
    reg  [4:0] trace [0:63];
    integer    n_scn = 0, err = 0, i, k, watch;
    integer    idx;

    always @(posedge clk) begin
        if (!rst && uut.memio_write && (uut.memio_addr[31:16] == 16'h1000) &&
            (uut.memio_addr >= 32'h1000_0200) && (uut.memio_addr <= 32'h1000_021C)) begin
            idx = uut.memio_addr[4:2];
            snap[idx] = uut.memio_wdata[4:0];
            if (idx == 3'd7 && n_scn < 64/8) begin
                for (k = 0; k < 8; k = k + 1)
                    trace[n_scn*8 + k] = snap[k];
                n_scn = n_scn + 1;
            end
        end
    end

    // 期望的 5 帧（每帧 8 个数字值，0xF=空白；dig4 的 bit4=小数点=粘滞溢出位）
    task exp_frame(input integer f, input [4:0] d0, input [4:0] d1, input [4:0] d2, input [4:0] d3,
                                  input [4:0] d4, input [4:0] d5, input [4:0] d6, input [4:0] d7,
                                  input [255:0] name);
        begin
            if (n_scn <= f) begin
                $display("FAIL: 场景 %0d 还没出现（只抓到 %0d 帧）：%0s", f, n_scn, name);
                err = err + 1;
            end
            else if (trace[f*8+0] !== d0 || trace[f*8+1] !== d1 || trace[f*8+2] !== d2 ||
                     trace[f*8+3] !== d3 || trace[f*8+4] !== d4 || trace[f*8+5] !== d5 ||
                     trace[f*8+6] !== d6 || trace[f*8+7] !== d7) begin
                $display("FAIL: 场景 %0d (%0s)", f, name);
                $display("      got = %h %h %h %h %h %h %h %h",
                         trace[f*8+0], trace[f*8+1], trace[f*8+2], trace[f*8+3],
                         trace[f*8+4], trace[f*8+5], trace[f*8+6], trace[f*8+7]);
                $display("      exp = %h %h %h %h %h %h %h %h",
                         d0, d1, d2, d3, d4, d5, d6, d7);
                err = err + 1;
            end
            else
                $display("PASS: 场景 %0d (%0s)  SF=%h ZF=%h CF=%h OF=%h STK=%h PF=%h SE=%h CNT=%h",
                         f, name, d0, d1, d2, d3, d4, d5, d6, d7);
        end
    endtask

    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        rst = 0;

        // 等 5 帧（一遍演示）抓齐
        for (watch = 0; watch < 200000; watch = watch + 1) begin
            if (n_scn >= 5) watch = 200000;
            else #20;
        end
        repeat (500) @(posedge clk);

        $display("============ 溢出标志位演示（数码管帧）============ ");
        // ① 0x80000000 + (-1)：SF0 ZF0 CF1 OF1 STK1 PF0 SEEN1 CNT odd
        exp_frame(0, 5'h00, 5'h00, 5'h01, 5'h01, 5'h11, 5'h00, 5'h01, 5'h01, "ADD 溢出+进位");
        // ② +0：不溢出，粘滞位保持
        exp_frame(1, 5'h00, 5'h00, 5'h00, 5'h00, 5'h11, 5'h00, 5'h01, 5'h01, "ADD 不溢出");
        // ③ 0 - 5：SF=1、借位 CF=1
        exp_frame(2, 5'h01, 5'h00, 5'h01, 5'h00, 5'h11, 5'h00, 5'h01, 5'h01, "SUB 借位");
        // ④ INT_MIN × INT_MIN：ZF=1、OF=1、PF=1，溢出次数 2（偶数）
        exp_frame(3, 5'h00, 5'h01, 5'h00, 5'h01, 5'h11, 5'h01, 5'h01, 5'h00, "MUL 溢出");
        // ⑤ clrflags：全灭
        exp_frame(4, 5'h00, 5'h00, 5'h00, 5'h00, 5'h00, 5'h00, 5'h00, 5'h00, "clrflags 清标志");

        $display("（共抓到 %0d 帧）", n_scn);
        $display("==================================================");
        if (err == 0) $display("==== tb_EES338_flags: ALL PASS ====");
        else          $display("==== tb_EES338_flags: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #4000000;
        $display("FAIL: tb_EES338_flags 超时（n_scn=%0d）", n_scn);
        $finish;
    end

endmodule
