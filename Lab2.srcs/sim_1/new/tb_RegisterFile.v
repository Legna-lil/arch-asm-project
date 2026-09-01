`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 17:02:03
// Design Name: 
// Module Name: tb_RegisterFile
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


// tb_RegisterFile.v
module tb_RegisterFile;
    reg clk;
    reg reg_we;
    reg [4:0] raddr1, raddr2, waddr;
    reg [31:0] wdata;
    wire [31:0] rdata1, rdata2;
    
    RegisterFile uut (
        .clk(clk),
        .reg_we(reg_we),
        .raddr1(raddr1),
        .raddr2(raddr2),
        .waddr(waddr),
        .wdata(wdata),
        .rdata1(rdata1),
        .rdata2(rdata2)
    );
    
    always #5 clk = ~clk;
    
    initial begin
        $monitor("time=%0t, reg_we=%b, waddr=%d, wdata=%h, rdata1=%h", $time, reg_we, waddr, wdata, rdata1);
        clk = 0;
        // 写 x1 = 0x12345678
        reg_we = 1; waddr = 1; wdata = 32'h12345678;
        #10;
        // 读 x1
        reg_we = 0; raddr1 = 1;
        #10;
        // 写 x0 应该无效
        reg_we = 1; waddr = 0; wdata = 32'hffffffff;
        #10;
        reg_we = 0; raddr1 = 0;
        #10;
        $finish;
    end
endmodule