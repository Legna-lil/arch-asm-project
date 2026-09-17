`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_divunit.v - 加减交替法（非恢复余数）除法单元测试
//
// 用例覆盖 Lab1 gen_tests.py 的除/取余清单 + RISC-V 特殊情况：
//   正/负、能整除/不能整除、除零、INT_MIN ÷ -1、无符号大数
//////////////////////////////////////////////////////////////////////////////////
module tb_divunit;

    reg         clk = 0;
    reg         rst = 1;
    reg         start = 0;
    reg         is_signed;
    reg  [31:0] dividend, divisor;
    wire        busy, done, div_of;
    wire [31:0] quot, rem;
    integer     err, wait_cnt, max_wait;

    always #5 clk = ~clk;

    DivUnit dut (
        .clk(clk), .rst(rst), .start(start), .is_signed(is_signed),
        .dividend(dividend), .divisor(divisor),
        .busy(busy), .done(done), .div_of(div_of), .quot(quot), .rem(rem)
    );

    task div_chk(input signed [31:0] a, input signed [31:0] b, input sgn,
                 input [31:0] e_q, input [31:0] e_r, input e_of, input [255:0] name);
        reg [31:0] q_got, r_got;
        reg        of_got;
        begin
            dividend = a; divisor = b; is_signed = sgn;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            wait_cnt = 0;
            // done 只在收尾那一拍为高，观察到它时要"立刻"采样输出（不能加 #1）
            while (!done && wait_cnt < 200) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            q_got = quot; r_got = rem; of_got = div_of;
            if (!done) begin
                $display("FAIL: %0s 超时（未收到 done）", name);
                err = err + 1;
            end
            else if (q_got !== e_q || r_got !== e_r || of_got !== e_of) begin
                $display("FAIL: %0s  %0d / %0d (signed=%b)", name, a, b, sgn);
                $display("      quot=%h(%0d) exp=%h(%0d) | rem=%h(%0d) exp=%h(%0d) | of=%b exp=%b",
                         q_got, $signed(q_got), e_q, $signed(e_q),
                         r_got, $signed(r_got), e_r, $signed(e_r), of_got, e_of);
                err = err + 1;
            end
            else
                $display("PASS: %0s  %0d / %0d = %0d ... 余 %0d  of=%b  (用了 %0d 拍)",
                         name, a, b, $signed(q_got), $signed(r_got), of_got, wait_cnt);
        end
    endtask

    initial begin
        err = 0;
        rst = 1;
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("================ DivUnit（加减交替法）================ ");
        div_chk(32'd100,  32'd3,          1'b1, 32'd33,  32'd1,          1'b0, "100/3=33 余1");
        div_chk(-32'd100, 32'd3,          1'b1, -32'd33, -32'd1,         1'b0, "-100/3=-33 余-1");
        div_chk(-32'd20,  32'd4,          1'b1, -32'd5,  32'd0,          1'b0, "-20/4=-5 余0");
        div_chk(-32'd6,  -32'd9,          1'b1, 32'd0,   -32'd6,         1'b0, "-6/-9=0 余-6");
        div_chk(32'd5,    32'd10,         1'b1, 32'd0,   32'd5,          1'b0, "5/10=0 余5");
        div_chk(32'd33,   32'd3,          1'b1, 32'd11,  32'd0,          1'b0, "33/3=11");
        div_chk(32'h80000000, 32'hFFFFFFFF, 1'b1, 32'h80000000, 32'd0,   1'b1, "INT_MIN/-1 溢出");
        div_chk(32'h80000000, 32'd0,      1'b1, 32'hFFFFFFFF, 32'h80000000, 1'b1, "除零(有符号)");
        div_chk(32'h80000000, 32'd4,      1'b1, 32'hE0000000, 32'd0,     1'b0, "INT_MIN/4");
        div_chk(32'hFFFFFFFF, 32'd2,      1'b0, 32'h7FFFFFFF, 32'd1,     1'b0, "无符号 FFFFFFFF/2");
        div_chk(32'h80000000, 32'hFFFFFFFF, 1'b0, 32'd0,    32'h80000000, 1'b0, "无符号 2^31/(2^32-1)");
        div_chk(-32'd7,  -32'd2,          1'b1, 32'd3,   -32'd1,         1'b0, "-7/-2=3 余-1");
        div_chk(32'h12345678, 32'd16,     1'b0, 32'h01234567, 32'd8,     1'b0, "无符号 0x12345678/16");
        div_chk(32'd0,    32'd7,          1'b1, 32'd0,   32'd0,          1'b0, "0/7=0");

        $display("========================================================");
        if (err == 0) $display("==== tb_divunit: ALL PASS ====");
        else          $display("==== tb_divunit: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: tb_divunit 超时");
        $finish;
    end

endmodule
