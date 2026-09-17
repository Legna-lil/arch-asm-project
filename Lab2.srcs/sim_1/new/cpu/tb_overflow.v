`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_overflow.v
// 溢出检测专项测试：
//   - 统计 overflow_ex（EX/MEM 级寄存器化信号）脉冲次数，期望 3 次
//     （addi x6 溢出、add x8 溢出、sub x9 溢出）
//   - addi x7 / sub x11 不溢出
//   - AUIPC/SW 地址计算不得误报溢出
//   - 检查各寄存器/内存结果
//////////////////////////////////////////////////////////////////////////////////

module tb_overflow;

    reg clk;
    reg rst;

    PipelineCPU #(
        .HEX_FILE("../../../../Lab2.file/inst_overflow.hex")
    ) uut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    integer overflow_count;
    integer fail;

    task check(input integer got, input integer exp, input [99:0] name, inout integer fail);
        if (got !== exp) begin
            $display("FAIL: %s = %0d (0x%h), expected %0d (0x%h)", name, got, got, exp, exp);
            fail = fail + 1;
        end
    endtask

    // 每个时钟沿统计溢出脉冲（rst 期间清零）
    always @(posedge clk) begin
        if (rst)
            overflow_count <= 0;
        else if (uut.overflow_ex)
            overflow_count <= overflow_count + 1;
    end

    initial begin
        clk = 0;
        rst = 1;
        overflow_count = 0;
        $display("========================================");
        $display("Overflow detection test start");
        $display("========================================");
        #20;
        rst = 0;
        #1000;

        fail = 0;
        $display("");
        $display("==== Register check ====");
        check(uut.rf_inst.regs[6],  32'h7ffffff8, "x6  (addi overflow)",   fail);
        check(uut.rf_inst.regs[7],  32'h80000009, "x7  (no overflow)",     fail);
        check(uut.rf_inst.regs[8],  32'h00000010, "x8  (add overflow)",    fail);
        check(uut.rf_inst.regs[9],  32'h80000001, "x9  (sub overflow)",    fail);
        check(uut.rf_inst.regs[11], 0,            "x11 (no overflow)",     fail);

        $display("");
        $display("==== Memory check ====");
        check(uut.dm_inst.mem[0], 32'h7ffffff8, "mem[0]", fail);
        check(uut.dm_inst.mem[1], 32'h80000009, "mem[1]", fail);
        check(uut.dm_inst.mem[2], 32'h00000010, "mem[2]", fail);
        check(uut.dm_inst.mem[3], 32'h80000001, "mem[3]", fail);
        check(uut.dm_inst.mem[4], 0,            "mem[4]", fail);

        $display("");
        $display("==== Overflow pulse count ====");
        $display("overflow_ex pulses = %0d (expect 3)", overflow_count);
        if (overflow_count != 3) begin
            $display("FAIL: overflow count = %0d, expected 3", overflow_count);
            fail = fail + 1;
        end

        if (fail == 0)
            $display("RESULT: PASS - overflow detection correct");
        else
            $display("RESULT: FAIL - %0d check(s) failed", fail);
        $finish;
    end

endmodule
