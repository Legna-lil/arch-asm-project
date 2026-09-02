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
module tb_ALU;
    reg [31:0] src1, src2;
    reg [3:0] alu_ctrl;
    wire [31:0] result;
    wire zero;
    
    ALU uut (.src1(src1), .src2(src2), .alu_ctrl(alu_ctrl), .result(result), .zero(zero));
    
    initial begin
        src1 = 5; src2 = 3;
        alu_ctrl = 4'b0000; #10 $display("ADD: %d + %d = %d", src1, src2, result); // 8
        alu_ctrl = 4'b0001; #10 $display("SUB: %d - %d = %d", src1, src2, result); // 2
        alu_ctrl = 4'b0010; #10 $display("OR:  %d | %d = %d", src1, src2, result); // 7
        $finish;
    end
endmodule
