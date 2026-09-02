`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_inst_alu.v
// 18 条指令逐条测试：ADD SUB AND OR XOR SLT ADDI ANDI ORI SLLI AUIPC LW SW
// 自检式：运行结束后自动比对寄存器/内存并输出 PASS/FAIL
//////////////////////////////////////////////////////////////////////////////////

module tb_inst_alu;

    reg clk;
    reg rst;

    PipelineCPU #(
        .HEX_FILE("../../../../Lab2.file/inst_alu.hex")
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
        $display("18-instruction test start");
        $display("========================================");
        #20;
        rst = 0;
        #1000;   // 足够执行完整个程序

        fail = 0;
        $display("");
        $display("==== Register check ====");
        check(uut.rf_inst.regs[5],  10, "x5 (ADDI)", fail);
        check(uut.rf_inst.regs[6],  3,  "x6 (ADDI)", fail);
        check(uut.rf_inst.regs[7],  13, "x7 (ADD)",  fail);
        check(uut.rf_inst.regs[8],  7,  "x8 (SUB)",  fail);
        check(uut.rf_inst.regs[9],  2,  "x9 (AND)",  fail);
        check(uut.rf_inst.regs[11], 11, "x11 (OR)",  fail);
        check(uut.rf_inst.regs[12], 9,  "x12 (XOR)", fail);
        check(uut.rf_inst.regs[13], 1,  "x13 (SLT)", fail);
        check(uut.rf_inst.regs[14], 0,  "x14 (SLT)", fail);
        check(uut.rf_inst.regs[15], 15, "x15 (ADDI)", fail);
        check(uut.rf_inst.regs[16], 2,  "x16 (ANDI)", fail);
        check(uut.rf_inst.regs[17], 14, "x17 (ORI)",  fail);
        check(uut.rf_inst.regs[18], 40, "x18 (SLLI)", fail);
        check(uut.rf_inst.regs[19], 32'h0040003c, "x19 (AUIPC)", fail);
        check(uut.rf_inst.regs[20], 9,  "x20 (LW)",   fail);

        $display("");
        $display("==== Memory check ====");
        check(uut.dm_inst.mem[0],  13,             "mem[0]",  fail);
        check(uut.dm_inst.mem[1],  7,              "mem[1]",  fail);
        check(uut.dm_inst.mem[2],  2,              "mem[2]",  fail);
        check(uut.dm_inst.mem[3],  11,             "mem[3]",  fail);
        check(uut.dm_inst.mem[4],  9,              "mem[4]",  fail);
        check(uut.dm_inst.mem[5],  1,              "mem[5]",  fail);
        check(uut.dm_inst.mem[6],  0,              "mem[6]",  fail);
        check(uut.dm_inst.mem[7],  15,             "mem[7]",  fail);
        check(uut.dm_inst.mem[8],  2,              "mem[8]",  fail);
        check(uut.dm_inst.mem[9],  14,             "mem[9]",  fail);
        check(uut.dm_inst.mem[10], 40,             "mem[10]", fail);
        check(uut.dm_inst.mem[11], 32'h0040003c,   "mem[11]", fail);

        if (fail == 0)
            $display("RESULT: PASS - all 18 instructions correct");
        else
            $display("RESULT: FAIL - %0d check(s) failed", fail);
        $finish;
    end

endmodule
