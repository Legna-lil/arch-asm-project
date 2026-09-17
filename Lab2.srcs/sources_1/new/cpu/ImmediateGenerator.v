`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:59:10
// Design Name: 
// Module Name: ImmediateGenerator
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


module ImmediateGenerator(
    input  [31:0] instr,
    input  [2:0]  imm_type,   // 0:I-type, 1:S-type, 2:B-type, 3:U-type, 4:J-type
    output reg [31:0] imm
);
    always @(*) begin
        case (imm_type)
            3'b000: // I-type (LW, ORI, ADDI, etc.)
                imm = {{20{instr[31]}}, instr[31:20]};
            3'b001: // S-type (SW)
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            3'b010: // B-type (BEQ, BLT, BGE)
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            3'b011: // U-type (AUIPC)
                imm = {instr[31:12], 12'b0};
            3'b100: // J-type (JAL)
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'b0;
        endcase
    end
endmodule
