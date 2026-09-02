`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 16:37:40
// Design Name: 
// Module Name: RegisterFile
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


// RegisterFile.v
module RegisterFile (
    input        clk,
    input        reg_we,        // дʹ��
    input  [4:0] raddr1,        // ���˿�1��ַ
    input  [4:0] raddr2,        // ���˿�2��ַ
    input  [4:0] waddr,         // д��ַ
    input  [31:0] wdata,        // д����
    output [31:0] rdata1,       // ������1
    output [31:0] rdata2        // ������2
);
    reg [31:0] regs [0:31];
    integer i;
    
    // ��ʼ�����мĴ���Ϊ0��Ϊ�˲���ADD����x1, x2����ֵ
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
        // regs[1] = 32'd5;   // x1 = 5
        // regs[2] = 32'd10;  // x2 = 10
    end
    
    // д������ͬ����x0����д��
    always @(posedge clk) begin
        if (reg_we && (waddr != 0))
            regs[waddr] <= wdata;
    end
    
    // ������������߼���x0��0��
    assign rdata1 = (raddr1 == 0) ? 32'b0 :
                    (reg_we && (waddr == raddr1)) ? wdata : regs[raddr1];
    assign rdata2 = (raddr2 == 0) ? 32'b0 :
                    (reg_we && (waddr == raddr2)) ? wdata : regs[raddr2];
    
endmodule
