`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_muldiv.v - CPU 级 M 扩展（乘/除/取余）专项测试
//
// 程序 inst_muldiv.hex 把 24 个结果写回 DMEM（基址 0x1001_0000），这里逐字比对：
//   * MUL / MULH / MULHU / MULHSU
//   * DIV / DIVU / REM / REMU（含除零、INT_MIN÷-1 等特殊情况）
//   * 多周期除法带来的流水线停顿 + 后续指令的前递（紧跟依赖、背靠背除法）
//   * 溢出计数 of_count_o（迁移后的粘滞溢出计数）：期望 6 次
//////////////////////////////////////////////////////////////////////////////////
module tb_muldiv;

    localparam HEX_F = "../../../../Lab2.file/inst_muldiv.hex";
    localparam DAT_F = "../../../../Lab2.file/mem_clean.hex";

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    PipelineCPU #(
        .HEX_FILE (HEX_F),
        .DATA_FILE(DAT_F)
    ) uut (
        .clk(clk),
        .rst(rst)
    );

    reg [31:0] exp [0:23];
    integer    err, i, cycle_cnt;

    always @(posedge clk) if (!rst) cycle_cnt = cycle_cnt + 1;

    task chk(input [31:0] got, input [31:0] e, input [255:0] name);
        begin
            if (got !== e) begin
                $display("FAIL: mem[%0s] = %h (%0d), expect %h (%0d)",
                         name, got, $signed(got), e, $signed(e));
                err = err + 1;
            end
        end
    endtask

    initial begin
        // ---- 期望结果 ----
        exp[0]  = 32'h00000084;   //  12*11 = 132
        exp[1]  = 32'hFFFFFFC8;   //  -7*8  = -56
        exp[2]  = 32'h80000000;   //  INT_MIN*(-1) 低 32（OF=1）
        exp[3]  = 32'h40000000;   //  MULH
        exp[4]  = 32'h40000000;   //  MULHU
        exp[5]  = 32'hC0000000;   //  MULHSU
        exp[6]  = 32'h00000000;   //  MULH (-1)*(-2^31)
        exp[7]  = 32'h00000021;   //  100/3 = 33
        exp[8]  = 32'h00000001;   //  100%3 = 1
        exp[9]  = 32'hFFFFFFFB;   //  -20/4 = -5
        exp[10] = 32'h00000000;   //  -20%4 = 0
        exp[11] = 32'hFFFFFFDF;   //  -100/3 = -33
        exp[12] = 32'hFFFFFFFF;   //  -100%3 = -1
        exp[13] = 32'hFFFFFFFF;   //  除零 商 = -1（OF=1）
        exp[14] = 32'h80000000;   //  除零 余 = 被除数
        exp[15] = 32'h80000000;   //  INT_MIN/-1 商 = INT_MIN（OF=1）
        exp[16] = 32'h00000000;   //  INT_MIN/-1 余 = 0
        exp[17] = 32'h00000000;   //  DIVU
        exp[18] = 32'h80000000;   //  REMU
        exp[19] = 32'hE0000004;   //  紧跟依赖（前递）：0xE0000000 + 4
        exp[20] = 32'hFFFFFFFC;   //  0 - 4
        exp[21] = 32'h0000000B;   //  背靠背除法：33/3 = 11
        exp[22] = 32'hE0000000;   //  INT_MIN/4 的除法原值
        exp[23] = 32'h00000000;   //  （未写）

        err = 0;
        cycle_cnt = 0;
        rst = 1;
        #22;
        rst = 0;
        #30000;                 // 9 次除法 × 33 拍 + 63 条指令，留足时间
        // 注意：检查要在复位之前做（复位会清零标志寄存器）

        $display("================ M 扩展（乘/除/取余）================ ");
        for (i = 0; i < 24; i = i + 1) begin
            if (uut.dm_inst.mem[i] !== exp[i]) begin
                $display("FAIL: mem[%0d] = %h (%0d), expect %h (%0d)",
                         i, uut.dm_inst.mem[i], $signed(uut.dm_inst.mem[i]), exp[i], $signed(exp[i]));
                err = err + 1;
            end
            else
                $display("PASS: mem[%0d] = %h (%0d)", i, uut.dm_inst.mem[i], $signed(uut.dm_inst.mem[i]));
        end

        // 溢出计数（粘滞计数，来自迁移后的 FlagReg）
        if (uut.of_count_o !== 32'd6) begin
            $display("FAIL: of_count = %0d, expect 6", uut.of_count_o);
            err = err + 1;
        end
        else
            $display("PASS: of_count = %0d（6 次溢出：mul/div0/rem0/INT_MIN-1/REM/INT_MIN*4）", uut.of_count_o);

        // 粘滞溢出位（flags bit4）与"最近一次"溢出位（bit3）
        if (uut.flags_o[4] !== 1'b1) begin
            $display("FAIL: OF_STICKY = %b, expect 1（末条算术指令是 addi x0,x0,0，不溢出但粘滞位应为 1）",
                     uut.flags_o[4]);
            err = err + 1;
        end
        else
            $display("PASS: OF_STICKY = 1（粘滞位保持）");

        $display("（本程序执行了约 %0d 个周期，含 9 次除法停顿）", cycle_cnt);
        $display("======================================================");
        if (err == 0) $display("==== tb_muldiv: ALL PASS ====");
        else          $display("==== tb_muldiv: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: tb_muldiv 超时");
        $finish;
    end

endmodule
