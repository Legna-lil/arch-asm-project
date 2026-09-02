`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_CPU_singlecycle.v
// 单周期 CPU 冒泡排序（对照基准）：
//   - 与流水线版本使用同一段机器码 inst_code_clean.hex 和相同初始数据 mem_clean.hex
//   - 单周期每周期执行一条指令，周期数 = 动态指令数，CPI = 1.000
//   - 自检排序结果
//////////////////////////////////////////////////////////////////////////////////

module tb_CPU_singlecycle;

    reg clk, rst;
    integer cycle_count;
    reg done;

    SingleCycleCPU uut (
        .clk(clk), .rst(rst)
    );

    always #5 clk = ~clk;

    // 单周期：每周期执行 1 条指令。程序占 0x00400000 ~ 0x00400050
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
            done        <= 1'b0;
        end
        else if (!done) begin
            if (uut.curr_pc <= 32'h00400050)
                cycle_count <= cycle_count + 1;
            if (uut.curr_pc == 32'h00400050)
                done <= 1'b1;
        end
    end

    initial begin
        clk = 0;
        rst = 1;
        $display("========================================");
        $display("Single-cycle CPU bubble-sort test");
        $display("========================================");
        #20;
        rst = 0;
        #3000;

        $display("");
        $display("==== Final result check ====");
        $display("mem[0..5] = %0d %0d %0d %0d %0d %0d",
                 uut.dm_inst.mem[0], uut.dm_inst.mem[1], uut.dm_inst.mem[2],
                 uut.dm_inst.mem[3], uut.dm_inst.mem[4], uut.dm_inst.mem[5]);
        if (uut.dm_inst.mem[0] == 1 && uut.dm_inst.mem[1] == 3 &&
            uut.dm_inst.mem[2] == 5 && uut.dm_inst.mem[3] == 7 &&
            uut.dm_inst.mem[4] == 9 && uut.dm_inst.mem[5] == 5)
            $display("RESULT: PASS - array sorted correctly");
        else
            $display("RESULT: FAIL - array NOT sorted correctly");

        $display("");
        $display("==== Single-cycle performance ====");
        $display("cycles = %0d (动态指令数)", cycle_count);
        $display("CPI    = 1.000");
        $finish;
    end

endmodule
