`timescale 1ns / 1ps
// =============================================================================
// tb_ImmGen.v - 立即数生成单元自检
//   I/S/B/U/J 五种类型各取一条真实指令，比对生成的立即数
// =============================================================================
module tb_ImmGen;
    reg  [31:0] instr;
    reg  [2:0]  imm_type;
    wire [31:0] imm;
    integer errs;

    ImmediateGenerator uut (.instr(instr), .imm_type(imm_type), .imm(imm));

    task check;
        input [255:0] name;
        input [31:0]  exp;
        begin
            #10;
            if (imm !== exp) begin
                $display("FAIL: %0s  imm=%h  expected %h", name, imm, exp);
                errs = errs + 1;
            end else begin
                $display("PASS: %0s  imm=%h", name, imm);
            end
        end
    endtask

    initial begin
        errs = 0;
        // I-type : addi x1, x0, 0x80
        instr = 32'h08000093; imm_type = 3'b000; check("I-type addi x1,x0,0x80", 32'h00000080);
        // S-type : sw x1, 0x80(x0)
        instr = 32'h08102023; imm_type = 3'b001; check("S-type sw x1,0x80(x0)",  32'h00000080);
        // B-type : beq x0, x0, +8
        instr = 32'h00000463; imm_type = 3'b010; check("B-type beq x0,x0,+8",   32'h00000008);
        // U-type : auipc x8, 0x0fc10
        instr = 32'h0FC10417; imm_type = 3'b011; check("U-type auipc x8,0xfc10", 32'h0FC10000);
        // J-type : jal x1, +8
        instr = 32'h008000EF; imm_type = 3'b100; check("J-type jal x1,+8",      32'h00000008);

        if (errs == 0) $display("==== tb_ImmGen: ALL PASS ====");
        else           $display("==== tb_ImmGen: %0d FAIL ====", errs);
        $finish;
    end
endmodule
