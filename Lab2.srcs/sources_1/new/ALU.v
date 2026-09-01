`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:57:54
// Design Name: 
// Module Name: ALU
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


// ALU.v
module ALU (
    input  [31:0] src1,
    input  [31:0] src2,
    input  [3:0]  alu_ctrl,   // 控制信号
    output reg [31:0] result,
    output zero               // 结果为零标志
);
    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = src1 + src2;   // ADD
            4'b0001: result = src1 - src2;   // SUB
            4'b0010: result = src1 | src2;   // OR
            4'b0011: result = src1 & src2;   // AND
            4'b0100: result = src1 ^ src2;   // XOR
            4'b0101: result = ($signed(src1) < $signed(src2)) ? 32'b1 : 32'b0; // SLT
            4'b0110: result = src1 << src2[4:0]; // SLL
            default: result = 32'b0;
        endcase
    end
    
    assign zero = (result == 32'b0);
    
endmodule
