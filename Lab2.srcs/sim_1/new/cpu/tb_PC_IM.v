`timescale 1ns / 1ps
// =============================================================================
// tb_PC_IM.v - PC + 指令存储器取指通路自检
//   * 复位后 PC = 0x00400000（RISC-V 程序起始地址）
//   * 顺序取指时 PC 每周期 +4
//   * 取出的指令与 hex 文件内容逐条一致
// =============================================================================
module tb_PC_IM;
    reg  clk, rst;
    wire [31:0] pc, instr;
    reg  [31:0] exp_mem [0:1023];
    integer errs, k;

    always #5 clk = ~clk;

    // 顺序执行：npc = pc + 4
    PC u_pc (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .npc(pc + 32'd4),
        .pc(pc)
    );

    InstructionMemory u_im (
        .addr(pc),
        .instr(instr)
    );

    initial begin
        errs = 0;
        $readmemh("../../../../Lab2.file/inst_code_clean.hex", exp_mem);  // 期望值 = RTL 用的同一份 hex
        clk = 0; rst = 1;

        @(posedge clk); #1;
        if (pc !== 32'h00400000) begin
            $display("FAIL: 复位后 pc = %h (期望 00400000)", pc); errs = errs + 1;
        end else $display("PASS: 复位后 pc = 00400000");
        if (instr !== exp_mem[0]) begin
            $display("FAIL: 指令[0] = %h (hex[0] = %h)", instr, exp_mem[0]); errs = errs + 1;
        end else $display("PASS: 指令[0] = %h", instr);

        rst = 0;
        for (k = 1; k <= 8; k = k + 1) begin
            @(posedge clk); #1;
            if (pc !== (32'h00400000 + 4*k)) begin
                $display("FAIL: 第 %0d 拍 pc = %h (期望 %h)", k, pc, 32'h00400000 + 4*k);
                errs = errs + 1;
            end else $display("PASS: 第 %0d 拍 pc = %h", k, pc);
            if (instr !== exp_mem[k]) begin
                $display("FAIL: 指令[%0d] = %h (hex[%0d] = %h)", k, instr, k, exp_mem[k]);
                errs = errs + 1;
            end else $display("PASS: 指令[%0d] = %h", k, instr);
        end

        if (errs == 0) $display("==== tb_PC_IM: ALL PASS ====");
        else           $display("==== tb_PC_IM: %0d FAIL ====", errs);
        $finish;
    end
endmodule
