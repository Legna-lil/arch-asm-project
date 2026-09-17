`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_compare.v
// 单周期 vs 五级流水线 CPU 冒泡排序对比实验：
//   - 两个 CPU 使用同一段机器码 inst_code_clean.hex、相同初始数据 mem_clean.hex
//   - 分别统计周期数 / 动态指令数 / 停顿 / 冲刷 / CPI
//   - 自检两个 CPU 排序结果完全一致
// 结论：流水线 CPI(≈1.46) 略高于单周期(1.0)，但流水线时钟周期显著缩短，
//       CPU 时间 = cycles x clock_period 仍大幅下降（clock_period 取自综合时序报告）
//////////////////////////////////////////////////////////////////////////////////

module tb_compare;

    reg clk, rst;

    // ---- 单周期 CPU ----
    SingleCycleCPU sc (
        .clk(clk), .rst(rst)
    );
    integer sc_cycles;
    reg     sc_done;

    // ---- 流水线 CPU ----
    PipelineCPU pipe (
        .clk(clk), .rst(rst)
    );
    integer pipe_cycles, pipe_retired, pipe_stalls, pipe_flushes;
    reg     pipe_done;

    always #5 clk = ~clk;

    // 单周期计数器：每周期执行一条指令，程序占 0x00400000 ~ 0x00400050
    always @(posedge clk) begin
        if (rst) begin
            sc_cycles <= 0;
            sc_done   <= 1'b0;
        end
        else if (!sc_done) begin
            if (sc.curr_pc <= 32'h00400050)
                sc_cycles <= sc_cycles + 1;
            if (sc.curr_pc == 32'h00400050)
                sc_done <= 1'b1;
        end
    end

    // 流水线计数器：最后一条指令 0x00400050 在 WB 退休（mem_wb_pc4==0x00400054）后停止
    always @(posedge clk) begin
        if (rst) begin
            pipe_cycles  <= 0;
            pipe_retired <= 0;
            pipe_stalls  <= 0;
            pipe_flushes <= 0;
            pipe_done    <= 1'b0;
        end
        else if (!pipe_done) begin
            pipe_cycles <= pipe_cycles + 1;
            if (pipe.stall)         pipe_stalls  <= pipe_stalls + 1;
            if (pipe.flush)         pipe_flushes <= pipe_flushes + 1;
            if (pipe.wb_valid)      pipe_retired <= pipe_retired + 1;
            if (pipe.wb_valid && pipe.mem_wb_pc4 == 32'h00400054)
                pipe_done <= 1'b1;
        end
    end

    initial begin
        clk = 0;
        rst = 1;
        $display("================================================");
        $display("Single-cycle vs Pipeline bubble-sort comparison");
        $display("================================================");
        #20;
        rst = 0;
        #3000;

        // 结果检查（两个 CPU 必须一致）
        $display("");
        $display("==== Result check (must be identical) ====");
        $display("Single  : mem[0..5] = %0d %0d %0d %0d %0d %0d",
                 sc.dm_inst.mem[0], sc.dm_inst.mem[1], sc.dm_inst.mem[2],
                 sc.dm_inst.mem[3], sc.dm_inst.mem[4], sc.dm_inst.mem[5]);
        $display("Pipeline: mem[0..5] = %0d %0d %0d %0d %0d %0d",
                 pipe.dm_inst.mem[0], pipe.dm_inst.mem[1], pipe.dm_inst.mem[2],
                 pipe.dm_inst.mem[3], pipe.dm_inst.mem[4], pipe.dm_inst.mem[5]);

        if (sc.dm_inst.mem[0]==1   && sc.dm_inst.mem[1]==3 &&
            sc.dm_inst.mem[2]==5   && sc.dm_inst.mem[3]==7 &&
            sc.dm_inst.mem[4]==9   && sc.dm_inst.mem[5]==5 &&
            pipe.dm_inst.mem[0]==1 && pipe.dm_inst.mem[1]==3 &&
            pipe.dm_inst.mem[2]==5 && pipe.dm_inst.mem[3]==7 &&
            pipe.dm_inst.mem[4]==9 && pipe.dm_inst.mem[5]==5)
            $display("RESULT: PASS - both CPUs sort correctly and identically");
        else
            $display("RESULT: FAIL - result mismatch");

        // 对比表
        $display("");
        $display("==== Performance comparison ====");
        $display("                  Single-cycle      Pipeline");
        $display("cycles            %0d               %0d", sc_cycles, pipe_cycles);
        $display("dynamic instrs    %0d               %0d", sc_cycles, pipe_retired);
        $display("stalls            -                  %0d", pipe_stalls);
        $display("flushes           -                  %0d", pipe_flushes);
        $display("CPI               1.000             %0.3f", pipe_cycles * 1.0 / pipe_retired);

        $display("");
        $display("CPU time = cycles x clock_period (时钟周期取综合/实现时序报告)");
        $display("Speedup  = (单周期 cycles x T_single) / (流水线 cycles x T_pipe)");
        $finish;
    end

endmodule
