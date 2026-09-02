`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_forward.v
// 前递专项测试：
//   1. ALU->ALU EX/MEM 前递（addi 紧接 addi）
//   2. ALU->ALU MEM/WB 前递（中间隔一条指令）
//   3. add->sw 写数据前递（EX/MEM 与 MEM/WB 两条路径）
//   4. lw-use 停顿 + 前递
//   5. 分支比较操作数走前递；lw->branch 停顿后前递
//////////////////////////////////////////////////////////////////////////////////

module tb_forward;

    reg clk;
    reg rst;

    PipelineCPU #(
        .HEX_FILE("../../../../Lab2.file/inst_forward.hex")
    ) uut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    integer fail;

    task check(input integer got, input integer exp, input [99:0] name, inout integer fail);
        if (got !== exp) begin
            $display("FAIL: %s = %0d (0x%h), expected %0d (0x%h)", name, got, got, exp, exp);
            fail = fail + 1;
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        $display("========================================");
        $display("Forwarding test start");
        $display("========================================");
        #20;
        rst = 0;
        #1000;

        fail = 0;
        $display("");
        $display("==== Register check ====");
        check(uut.rf_inst.regs[6],  101,  "x6  (EX/MEM forward)",  fail);
        check(uut.rf_inst.regs[7],  102,  "x7  (EX/MEM forward)",  fail);
        check(uut.rf_inst.regs[9],  105,  "x9  (MEM/WB forward)",  fail);
        check(uut.rf_inst.regs[11], 40,   "x11 (LW)",              fail);
        check(uut.rf_inst.regs[12], 45,   "x12 (lw-use)",          fail);
        check(uut.rf_inst.regs[13], 40,   "x13 (ADD)",             fail);
        check(uut.rf_inst.regs[15], 2,    "x15 (branch flushed)",  fail);
        check(uut.rf_inst.regs[16], 2,    "x16 (ADDI)",            fail);
        check(uut.rf_inst.regs[17], 45,   "x17 (LW)",              fail);

        $display("");
        $display("==== Memory check ====");
        check(uut.dm_inst.mem[0], 40, "mem[0] (add->sw EX/MEM)", fail);
        check(uut.dm_inst.mem[1], 40, "mem[1] (add->sw MEM/WB)", fail);
        check(uut.dm_inst.mem[2], 45, "mem[2] (lw-use store)",   fail);
        check(uut.dm_inst.mem[3], 2,  "mem[3] (branch result)",  fail);
        check(uut.dm_inst.mem[4], 2,  "mem[4] (branch result)",  fail);

        if (fail == 0)
            $display("RESULT: PASS - forwarding/stall all correct");
        else
            $display("RESULT: FAIL - %0d check(s) failed", fail);
        $finish;
    end

endmodule
