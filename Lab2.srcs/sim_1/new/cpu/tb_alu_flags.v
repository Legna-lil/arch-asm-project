`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_alu_flags.v - ALU 状态标志位（SF/ZF/CF/OF/PF）与 M 扩展乘法单元测试
//
// 验证"迁移自 Lab1 alu.v 的溢出标志位生成方法"：
//   * ADD/SUB：符号判定式溢出（同号相加/异号相减结果符号翻转）
//   * MUL：64 位积不能被低 32 位符号扩展表示 => OF=1（Lab1 mult_alu 判据）
//   * 逻辑/移位运算：CF=OF=0
//   * CF：ADD 取 33 位进位；SUB 取 33 位借位
//   * SF/ZF/PF：结果符号位 / 全零 / ~^result（偶校验）
//////////////////////////////////////////////////////////////////////////////////
module tb_alu_flags;

    reg  [31:0] src1, src2;
    reg  [3:0]  ctrl;
    wire [31:0] result;
    wire        zero, sign, carry, parity, overflow;
    integer     err;

    ALU dut (
        .src1(src1), .src2(src2), .alu_ctrl(ctrl),
        .result(result), .zero(zero), .sign(sign), .carry(carry),
        .parity(parity), .overflow(overflow)
    );

    task chk(input [31:0] er, input e_sf, input e_zf, input e_cf, input e_of, input e_pf,
             input [255:0] name);
        begin
            #1;
            if (result !== er || sign !== e_sf || zero !== e_zf || carry !== e_cf ||
                overflow !== e_of || parity !== e_pf) begin
                $display("FAIL: %0s  ctrl=%b a=%h b=%h", name, ctrl, src1, src2);
                $display("      res=%h sf=%b zf=%b cf=%b of=%b pf=%b",
                         result, sign, zero, carry, overflow, parity);
                $display("      exp res=%h sf=%b zf=%b cf=%b of=%b pf=%b",
                         er, e_sf, e_zf, e_cf, e_of, e_pf);
                err = err + 1;
            end
            else
                $display("PASS: %0s  res=%h sf=%b zf=%b cf=%b of=%b pf=%b",
                         name, result, sign, zero, carry, overflow, parity);
        end
    endtask

    initial begin
        err = 0;
        $display("================ ALU 标志位 / M 扩展乘法 ================");

        // ---------- ADD ----------
        src1 = 32'h7FFFFFFF; src2 = 32'h00000001; ctrl = 4'b0000;
        chk(32'h80000000, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, "ADD 0x7FFFFFFF+1 溢出");
        src1 = 32'h80000000; src2 = 32'hFFFFFFFF; ctrl = 4'b0000;
        chk(32'h7FFFFFFF, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, "ADD 负+负=正 溢出且有进位");
        src1 = 32'd5;        src2 = 32'd5;        ctrl = 4'b0000;
        chk(32'd10, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, "ADD 5+5 不溢出");
        src1 = 32'hFFFFFFFF; src2 = 32'd1;        ctrl = 4'b0000;
        chk(32'h00000000, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, "ADD -1+1 = 0 有进位");

        // ---------- SUB ----------
        src1 = 32'd0;        src2 = 32'd5;        ctrl = 4'b0001;
        chk(32'hFFFFFFFB, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, "SUB 0-5 借位，SF=1");
        src1 = 32'h80000000; src2 = 32'd1;        ctrl = 4'b0001;
        chk(32'h7FFFFFFF, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, "SUB 负减正=正 溢出");
        src1 = 32'd5;        src2 = 32'd5;        ctrl = 4'b0001;
        chk(32'h00000000, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, "SUB 5-5 = 0");

        // ---------- 逻辑 / 移位：CF=OF=0 ----------
        src1 = 32'hF0F0F0F0; src2 = 32'h0000FFFF; ctrl = 4'b0011;
        chk(32'h0000F0F0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, "AND 不产生 CF/OF");
        src1 = 32'h0F0F0F0F; src2 = 32'hF0F00000; ctrl = 4'b0010;
        chk(32'hFFFF0F0F, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, "OR  不产生 CF/OF");
        src1 = 32'hFFFFFFFF; src2 = 32'hFFFFFFFF; ctrl = 4'b0100;
        chk(32'h00000000, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, "XOR 结果为 0");
        src1 = 32'hFFFFFFFF; src2 = 32'd1;        ctrl = 4'b0101;
        chk(32'd1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, "SLT -1<1");
        src1 = 32'd1;        src2 = 32'd31;       ctrl = 4'b0110;
        chk(32'h80000000, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, "SLL 1<<31");

        // ---------- MUL（Lab1 溢出判据）----------
        src1 = 32'd12;       src2 = 32'd11;       ctrl = 4'b0111;
        chk(32'd132, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, "MUL 12*11 不溢出");
        src1 = 32'h80000000; src2 = 32'hFFFFFFFF; ctrl = 4'b0111;
        chk(32'h80000000, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, "MUL INT_MIN*(-1) 溢出");
        src1 = 32'h80000000; src2 = 32'h80000000; ctrl = 4'b0111;
        chk(32'h00000000, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, "MUL INT_MIN^2 溢出且低32=0");
        src1 = 32'hFFFFFFFF; src2 = 32'd1;        ctrl = 4'b0111;
        chk(32'hFFFFFFFF, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, "MUL -1*1 = -1 不溢出,PF=1");

        // ---------- MULH / MULHU / MULHSU（高 32 位）----------
        src1 = 32'h80000000; src2 = 32'h80000000; ctrl = 4'b1000;
        chk(32'h40000000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, "MULH  INT_MIN^2 高32");
        src1 = 32'h80000000; src2 = 32'h80000000; ctrl = 4'b1001;
        chk(32'h40000000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, "MULHU 2^31*2^31 高32");
        src1 = 32'h80000000; src2 = 32'h80000000; ctrl = 4'b1010;
        chk(32'hC0000000, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, "MULHSU (-2^31)*(2^31) 高32");
        src1 = 32'hFFFFFFFF; src2 = 32'h80000000; ctrl = 4'b1000;
        chk(32'h00000000, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, "MULH  (-1)*INT_MIN 高32");

        // ---------- DIV/REM 编码在 ALU 上不产生结果（由 DivUnit 提供）----------
        src1 = 32'd100;      src2 = 32'd3;        ctrl = 4'b1011;
        chk(32'h00000000, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, "DIV 编码：ALU 结果为 0");

        $display("========================================================");
        if (err == 0) $display("==== tb_alu_flags: ALL PASS ====");
        else          $display("==== tb_alu_flags: %0d FAIL ====", err);
        $finish;
    end

endmodule
