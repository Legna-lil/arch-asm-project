`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_flags.v - 状态标志寄存器专项（rdflags / clrflags / MMIO 读取）
//
// 在 SoC 级（EES338_Core = PipelineCPU + PeriphMMIO）运行 inst_flags.hex：
//   ① clrflags 清零、rdflags 读出 0x00
//   ② ADD 溢出（负+负=正）→ OF=1、CF=1、粘滞位=1 → 0x5C
//      同时用 MMIO(0x1000_0300) 读一遍，验证两条读通路一致
//   ③ 不溢出的 ADD 不改变粘滞位 → 0x70；OF_COUNT 保持 1
//   ④ SUB 借位 → SF=1、CF=1 → 0x55
//   ⑤ MUL 溢出（INT_MIN²）→ ZF=1、OF=1、PF=1 → 0x7A
//   ⑥ 逻辑指令（AND）不刷新标志、也不增加溢出计数
//   ⑦ 连续两次 ADD 只有溢出的那次计数 → OF_COUNT 仍为 1
//////////////////////////////////////////////////////////////////////////////////
module tb_flags;

    localparam HEX_F = "../../../../Lab2.file/inst_flags.hex";
    localparam DAT_F = "../../../../Lab2.file/mem_clean.hex";

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;

    EES338_Core #(
        .HEX_FILE    (HEX_F),
        .DATA_FILE   (DAT_F),
        .LCD_RST_CYCLES(20)          // 仿真里缩短 LCD 上电复位时间
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .bt_rxd   (bt_rxd),
        .bt_txd   (bt_txd),
        .lcd_d    (),
        .lcd_wr_n (),
        .lcd_rd_n (),
        .lcd_cs_n (),
        .lcd_rs   (),
        .lcd_rst_n(),
        .seg_grp0 (),
        .dn0      (),
        .seg_grp1 (),
        .dn1      ()
    );

    reg [31:0] exp [0:12];
    integer    err, i;

    task chk(input [31:0] got, input [31:0] e, input [255:0] name);
        begin
            if (got !== e) begin
                $display("FAIL: mem[%0s] = %h, expect %h   (%0s)", name, got, e, name);
                err = err + 1;
            end
            else
                $display("PASS: mem[%0s] = %h", name, got);
        end
    endtask

    initial begin
        // ---- 期望值（标志字：bit0 SF, bit1 ZF, bit2 CF, bit3 OF, bit4 粘滞, bit5 PF, bit6 SEEN）----
        exp[0]  = 32'h00000000;   // clrflags 之后
        exp[1]  = 32'h0000005C;   // 0x80000000 + (-1): OF=1, CF=1, 粘滞=1, SEEN=1
        exp[2]  = 32'h0000005C;   // 同一拍用 MMIO 读回 CPU_FLAGS，应与 rdflags 一致
        exp[3]  = 32'h00000001;   // MMIO OF_COUNT = 1
        exp[4]  = 32'h00000070;   // 5+5=10 不溢出：OF=0，粘滞保持，PF=1
        exp[5]  = 32'h00000055;   // 0-5=-5：SF=1、借位 CF=1
        exp[6]  = 32'h00000000;   // clrflags 之后
        exp[7]  = 32'h0000007A;   // MUL INT_MIN^2 低32=0：ZF=1、OF=1、PF=1
        exp[8]  = 32'h00000001;   // MMIO OF_COUNT = 1
        exp[9]  = 32'h00000000;   // AND 不刷新标志
        exp[10] = 32'h00000074;   // 0x80000000+(-1) 溢出；再 0x7FFFFFFE：PF=1
        exp[11] = 32'h00000001;   // OF_COUNT 仍为 1（只有上面那次溢出）

        err = 0;
        rst = 1;
        #22;
        rst = 0;
        #20000;

        $display("================ 状态标志寄存器（CPU_FLAGS / OF_COUNT）================ ");
        for (i = 0; i < 12; i = i + 1) begin
            if (uut.cpu_inst.dm_inst.mem[i] !== exp[i]) begin
                $display("FAIL: mem[%0d] = %h, expect %h", i, uut.cpu_inst.dm_inst.mem[i], exp[i]);
                err = err + 1;
            end
            else
                $display("PASS: mem[%0d] = %h", i, uut.cpu_inst.dm_inst.mem[i]);
        end

        // 末态：最后一条算术指令是 addi x0,x0,0（结果 0，不溢出）→ 粘滞位仍为 1
        if (uut.cpu_inst.flags_reg !== 8'h72) begin
            $display("FAIL: 末态 flags = %h, expect 0x72（ZF|PF|粘滞|SEEN）", uut.cpu_inst.flags_reg);
            err = err + 1;
        end
        else
            $display("PASS: 末态 flags = %h（粘滞位保持，OF 已被 NOP 的 addi 覆盖）",
                     uut.cpu_inst.flags_reg);

        if (uut.cpu_inst.of_count_reg !== 32'd1) begin
            $display("FAIL: 末态 of_count = %0d, expect 1", uut.cpu_inst.of_count_reg);
            err = err + 1;
        end
        else
            $display("PASS: 末态 of_count = 1");

        $display("=====================================================================");
        if (err == 0) $display("==== tb_flags: ALL PASS ====");
        else          $display("==== tb_flags: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: tb_flags 超时");
        $finish;
    end

endmodule
