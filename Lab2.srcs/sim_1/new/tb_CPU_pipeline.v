`timescale 1ns / 1ps

module tb_CPU_pipeline_test;

    reg clk;
    reg rst;

    PipelineCPU uut (
        .clk(clk),
        .rst(rst)
    );

    integer i;

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;

        $display("========================================");
        $display("Pipeline CPU functional test start");
        $display("========================================");

        #20;
        rst = 0;

        // 让 CPU 运行足够长时间，执行指令流
        // 冒泡排序程序约需 195 个周期（约 1950ns），留出余量
        #3000;

        $display("========================================");
        $display("Final register values:");
        for (i = 0; i < 32; i = i + 1) begin
            if (i % 8 == 0) $display("");
            $display("x%0d = %0d (0x%h)", i, uut.rf_inst.regs[i], uut.rf_inst.regs[i]);
        end

        $display("");
        $display("Memory values:");
        for (i = 0; i < 8; i = i + 1) begin
            $display("mem[%0d] = %0d (0x%h)", i, uut.dm_inst.mem[i], uut.dm_inst.mem[i]);
        end

        $display("========================================");
        $display("Pipeline CPU functional test end");
        $display("========================================");
        $finish;
    end

endmodule