`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 17:06:48
// Design Name: 
// Module Name: tb_ALU
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


// tb_ALU.v
// 自检式 ALU 单元测试：逐条比对 ADD/SUB/OR/AND/XOR/SLT/SLL 的结果
// （标志位 SF/ZF/CF/OF/PF 与 M 扩展乘法见 tb_alu_flags.v）
module tb_ALU;
    reg  [31:0] src1, src2;
    reg  [3:0]  alu_ctrl;
    wire [31:0] result;
    wire        zero;
    integer     err;

    ALU uut (.src1(src1), .src2(src2), .alu_ctrl(alu_ctrl), .result(result), .zero(zero));

    task chk(input [31:0] a, input [31:0] b, input [3:0] c,
             input [31:0] e_res, input e_zero, input [255:0] name);
        begin
            src1 = a; src2 = b; alu_ctrl = c;
            #1;
            if (result !== e_res || zero !== e_zero) begin
                $display("FAIL: %0s  a=%h b=%h ctrl=%b -> res=%h zero=%b, exp res=%h zero=%b",
                         name, a, b, c, result, zero, e_res, e_zero);
                err = err + 1;
            end
            else
                $display("PASS: %0s  %h %b %h = %h (zero=%b)", name, a, c, b, result, zero);
        end
    endtask

    initial begin
        err = 0;
        chk(32'd5,  32'd3,  4'b0000, 32'd8,      1'b0, "ADD");
        chk(32'd5,  32'd3,  4'b0001, 32'd2,      1'b0, "SUB");
        chk(32'd10, 32'd3,  4'b0010, 32'd11,     1'b0, "OR");
        chk(32'd10, 32'd3,  4'b0011, 32'd2,      1'b0, "AND");
        chk(32'd10, 32'd3,  4'b0100, 32'd9,      1'b0, "XOR");
        chk(-32'd1, 32'd1,  4'b0101, 32'd1,      1'b0, "SLT(-1<1)");
        chk(32'd10, 32'd3,  4'b0101, 32'd0,      1'b1, "SLT(10<3)=0");
        chk(32'd1,  32'd31, 4'b0110, 32'h80000000, 1'b0, "SLL(1<<31)");
        chk(32'd5,  32'd5,  4'b0001, 32'd0,      1'b1, "SUB 结果为 0 -> zero=1");
        chk(32'hFFFFFFFF, 32'd1, 4'b0000, 32'd0, 1'b1, "ADD 回绕到 0 -> zero=1");
        if (err == 0) $display("==== tb_ALU: ALL PASS ====");
        else          $display("==== tb_ALU: %0d FAIL ====", err);
        $finish;
    end
endmodule
