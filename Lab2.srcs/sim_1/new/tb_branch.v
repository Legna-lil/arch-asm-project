`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_branch.v
// 控制冒险专项测试：
//   BEQ/BNE/BLT/BGE 各测跳转成立/不成立两种情况
//   JAL 链接写回 + 跳转后错误路径指令被 flush（x28 必须保持 0）
//////////////////////////////////////////////////////////////////////////////////

module tb_branch;

    reg clk;
    reg rst;

    PipelineCPU #(
        .HEX_FILE("../../../../Lab2.file/inst_branch.hex")
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
        $display("Branch/Jump test start");
        $display("========================================");
        #20;
        rst = 0;
        #1000;

        fail = 0;
        $display("");
        $display("==== Register check ====");
        check(uut.rf_inst.regs[5],  7,              "x5",   fail);
        check(uut.rf_inst.regs[8],  9,              "x8 (branch count)", fail);
        check(uut.rf_inst.regs[9],  32'h00400068,   "x9 (JAL link)",     fail);
        check(uut.rf_inst.regs[28], 0,              "x28 (flushed paths must NOT write)", fail);

        $display("");
        $display("==== Memory check ====");
        check(uut.dm_inst.mem[0], 9,                "mem[0]", fail);
        check(uut.dm_inst.mem[1], 32'h00400068,     "mem[1] (link)", fail);
        check(uut.dm_inst.mem[2], 0,                "mem[2] (no garbage write)", fail);

        if (fail == 0)
            $display("RESULT: PASS - all branch/jump cases correct");
        else
            $display("RESULT: FAIL - %0d check(s) failed", fail);
        $finish;
    end

endmodule
