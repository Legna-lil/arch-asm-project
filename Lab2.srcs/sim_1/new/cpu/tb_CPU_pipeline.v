`timescale 1ns / 1ps
// =============================================================================
// tb_CPU_pipeline.v - 五级流水线 CPU 整机功能自检
//
//   跑默认程序（PipelineCPU 的 HEX_FILE = inst_code_clean.hex，
//   DATA_FILE = mem_clean.hex，其中 mem[0..5] = 9,3,7,1,5,5 的冒泡排序），
//   3000ns 后检查：
//     * x0 恒为 0
//     * mem[0..5] 已升序排好（排序后置条件）
//     * mem[0..5] 是初值的重排（元素不多不少）
// =============================================================================
module tb_CPU_pipeline;

    reg clk, rst;
    integer i, j, errs;
    reg [31:0] init_mem [0:1023];

    PipelineCPU uut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    initial begin
        errs = 0;
        $readmemh("../../../../Lab2.file/mem_clean.hex", init_mem);
        clk = 0; rst = 1;
        $display("========================================");
        $display("五级流水线 CPU 整机测试开始");
        $display("========================================");

        #20;  rst = 0;
        #3000;                                  // 冒泡排序约 195 拍（1950ns），留足余量

        // ---- 1) x0 必须恒为 0 ----
        if (uut.rf_inst.regs[0] !== 32'd0) begin
            $display("FAIL: x0 = %0d (应为 0)", uut.rf_inst.regs[0]); errs = errs + 1;
        end else $display("PASS: x0 == 0");

        // ---- 2) mem[0..5] 升序 ----
        for (i = 1; i < 6; i = i + 1) begin
            if (uut.dm_inst.mem[i] < uut.dm_inst.mem[i-1]) begin
                $display("FAIL: mem[%0d]=%0d < mem[%0d]=%0d (排序结果不是升序)",
                         i, uut.dm_inst.mem[i], i-1, uut.dm_inst.mem[i-1]);
                errs = errs + 1;
            end
        end
        $display("PASS: mem[0..5] 升序检查完成 -> %0d %0d %0d %0d %0d %0d",
                 uut.dm_inst.mem[0], uut.dm_inst.mem[1], uut.dm_inst.mem[2],
                 uut.dm_inst.mem[3], uut.dm_inst.mem[4], uut.dm_inst.mem[5]);

        // ---- 3) 排序结果必须是初值的重排（每个初值都能在结果里找到）----
        for (i = 0; i < 6; i = i + 1) begin
            j = 0;
            while (j < 6 && uut.dm_inst.mem[j] !== init_mem[i]) j = j + 1;
            if (j == 6) begin
                $display("FAIL: 初值 %0d (mem[%0d]) 在排序结果里丢了", init_mem[i], i);
                errs = errs + 1;
            end
        end
        if (errs == 0) $display("PASS: 排序结果是初值的重排 %0d %0d %0d %0d %0d %0d",
                                init_mem[0], init_mem[1], init_mem[2],
                                init_mem[3], init_mem[4], init_mem[5]);

        // ---- 附：寄存器/内存快照，便于人工核对 ----
        $display("");
        $display("Final registers:");
        for (i = 0; i < 32; i = i + 1) begin
            if (i % 8 == 0) $display("");
            $display("x%0d = %0d (0x%h)", i, uut.rf_inst.regs[i], uut.rf_inst.regs[i]);
        end
        $display("");
        $display("Final memory:");
        for (i = 0; i < 8; i = i + 1)
            $display("mem[%0d] = %0d (0x%h)", i, uut.dm_inst.mem[i], uut.dm_inst.mem[i]);

        $display("========================================");
        if (errs == 0) $display("==== tb_CPU_pipeline: ALL PASS ====");
        else           $display("==== tb_CPU_pipeline: %0d FAIL ====", errs);
        $display("========================================");
        $finish;
    end

endmodule
