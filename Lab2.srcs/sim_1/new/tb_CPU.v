`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 17:55:13
// Design Name: 
// Module Name: tb_CPU
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


module tb_CPU;
    reg clk, rst;
    
    SingleCycleCPU uut (
        .clk(clk), .rst(rst)
    );
    
    always #5 clk = ~clk;
    
    initial begin
        $monitor("T=%0t | PC=%h | Instr=%h | x5=%d x6=%d x7=%d x8=%d x9=%d x10=%d x17=%d\n| x28=%d, x29=%d, x30=%d\nMemory: m1=%d, m2=%d, m3=%d, m4=%d, m5=%d, m6=%d",
             $time, uut.curr_pc, uut.instruction,
             uut.rf_inst.regs[5], uut.rf_inst.regs[6], uut.rf_inst.regs[7], 
             uut.rf_inst.regs[8], uut.rf_inst.regs[9], uut.rf_inst.regs[10],
             uut.rf_inst.regs[17], uut.rf_inst.regs[28], uut.rf_inst.regs[29],
             uut.rf_inst.regs[30], uut.dm_inst.mem[0],
             uut.dm_inst.mem[1], uut.dm_inst.mem[2], uut.dm_inst.mem[3],
             uut.dm_inst.mem[4], uut.dm_inst.mem[5]);
        clk = 0;
        rst = 1;
        #10 rst = 0;
    end
endmodule
