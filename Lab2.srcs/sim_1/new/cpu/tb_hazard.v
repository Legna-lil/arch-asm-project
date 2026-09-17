`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_hazard.v
// 冒险处理专项测试：
//   1. ALU 数据前递 (Forwarding)：addi x6,x5 / addi x7,x6
//   2. Load-use Stall：lw x11 后紧接 addi x12,x11
//   3. 控制冒险 Flush：blt 回跳 与 jal 后紧跟的指令被清空
//   4. JAL 链接写回：x1 = PC+4
//////////////////////////////////////////////////////////////////////////////////

module tb_hazard;

    reg clk;
    reg rst;

    PipelineCPU #(
        .HEX_FILE("../../../../Lab2.file/hazard_test.hex")
    ) uut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    integer i;

    initial begin
        clk = 0;
        rst = 1;
        $display("========================================");
        $display("Hazard test start");
        $display("========================================");

        #20;
        rst = 0;

        // 让 CPU 执行完整程序
        #1000;

        $display("");
        $display("==== Final register values ====");
        for (i = 0; i < 32; i = i + 1) begin
            if (i % 8 == 0) $display("");
            $display("x%0d = %0d (0x%h)", i, uut.rf_inst.regs[i], uut.rf_inst.regs[i]);
        end

        $display("");
        $display("==== Memory values ====");
        for (i = 0; i < 4; i = i + 1) begin
            $display("mem[%0d] = %0d (0x%h)", i, uut.dm_inst.mem[i], uut.dm_inst.mem[i]);
        end

        $display("");
        // 期望结果
        $display("Expected: x5=10  x6=15  x7=35  x10=0x10010000");
        $display("          x11=10 x12=11 x13=10 x14=0 (flushed) x15=0x00400034");
        $display("          mem[0]=10 mem[1]=11 mem[2]=0x00400034 mem[3]=10");
        if (uut.rf_inst.regs[5]  == 10 &&
            uut.rf_inst.regs[6]  == 15 &&
            uut.rf_inst.regs[7]  == 35 &&
            uut.rf_inst.regs[10] == 32'h10010000 &&
            uut.rf_inst.regs[11] == 10 &&
            uut.rf_inst.regs[12] == 11 &&
            uut.rf_inst.regs[13] == 10 &&
            uut.rf_inst.regs[14] == 0 &&
            uut.rf_inst.regs[15] == 32'h00400034 &&
            uut.dm_inst.mem[0]   == 10 &&
            uut.dm_inst.mem[1]   == 11 &&
            uut.dm_inst.mem[2]   == 32'h00400034 &&
            uut.dm_inst.mem[3]   == 10)
            $display("RESULT: PASS - all hazard tests correct");
        else
            $display("RESULT: FAIL - hazard test error");

        $display("========================================");
        $finish;
    end

endmodule
