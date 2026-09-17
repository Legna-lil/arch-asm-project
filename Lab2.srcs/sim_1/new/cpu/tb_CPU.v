`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 17:55:13
// Design Name: 
// Module Name: tb_CPU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_CPU;
    reg clk, rst;

    // 性能计数器：cycle / stall / flush / retired（程序结束即停止统计�?
    integer cycle_count;
    integer stall_count;
    integer flush_count;
    integer retired_count;
    integer taken_branch_count;
    reg done;

    PipelineCPU uut (
        .clk(clk), .rst(rst)
    );

    always #5 clk = ~clk;

    // 每个时钟沿统计：周期数�?�停顿数、分支冲刷数、�??休指令数(MEM/WB.valid)
    // 结束条件：程序最后一条指令（0x00400050 addi x5,x0,0）在 WB �?�?
    //           （mem_wb_pc4 == 0x00400054）后冻结计数�?
    always @(posedge clk) begin
        if (rst) begin
            cycle_count       <= 0;
            stall_count       <= 0;
            flush_count       <= 0;
            retired_count     <= 0;
            taken_branch_count<= 0;
            done              <= 1'b0;
        end
        else if (!done) begin
            cycle_count <= cycle_count + 1;
            if (uut.stall)           stall_count        <= stall_count + 1;
            if (uut.flush)           flush_count        <= flush_count + 1;
            if (uut.wb_valid)        retired_count      <= retired_count + 1;
            if (uut.branch_taken_ex) taken_branch_count <= taken_branch_count + 1;
            if (uut.wb_valid && uut.mem_wb_pc4 == 32'h00400054)
                done <= 1'b1;
        end
    end

    initial begin
        $display("==== Five-stage pipeline CPU simulation start ====");
        clk = 0;
        rst = 1;
        #10 rst = 0;
        // 运行足够的周期让程序（含分支循环）执行完�?
        #5000 $display("==== Simulation end ====");
        
        $display("");
        $display("==== Final result check ====");
        $display("mem[0]=%d  mem[1]=%d  mem[2]=%d  mem[3]=%d  mem[4]=%d  mem[5]=%d",
                 uut.dm_inst.mem[0], uut.dm_inst.mem[1], uut.dm_inst.mem[2],
                 uut.dm_inst.mem[3], uut.dm_inst.mem[4], uut.dm_inst.mem[5]);
        $display("x5=%d  x8=0x%h  x9=%d  x18=%d", 
                 uut.rf_inst.regs[5], uut.rf_inst.regs[8], 
                 uut.rf_inst.regs[9], uut.rf_inst.regs[18]);
        // 期望：冒泡排序后 mem[0..4] = 1,3,5,7,9（升序）；mem[5]=n=5 保持不变
        if (uut.dm_inst.mem[0] == 1 && uut.dm_inst.mem[1] == 3 &&
            uut.dm_inst.mem[2] == 5 && uut.dm_inst.mem[3] == 7 &&
            uut.dm_inst.mem[4] == 9 && uut.dm_inst.mem[5] == 5)
            $display("RESULT: PASS - array sorted correctly");
        else
            $display("RESULT: FAIL - array NOT sorted correctly");
            
        $display("");
        $display("==== Performance (five-integer bubble sort) ====");
        $display("Clock period  = 10 ns");
        $display("cycles        = %0d", cycle_count);
        $display("Execution time= %0d ns = %0.3f us",
                 cycle_count * 10, cycle_count * 10.0 / 1000.0);
        $display("retired       = %0d  (��ָ̬����)", retired_count);
        $display("stalls        = %0d  (load-use ͣ������)", stall_count);
        $display("flushes       = %0d  (��֧/��ת��ˢ����)", flush_count);
        $display("taken branches= %0d", taken_branch_count);
        if (retired_count > 0)
            $display("CPI           = %0.3f", cycle_count * 1.0 / retired_count);
        $finish;
        $finish;
    end
endmodule
