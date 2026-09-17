`timescale 1ns / 1ps
// =============================================================================
// tb_RegisterFile.v - 寄存器堆自检
//   1) 初始全 0
//   2) 写 x1 = 0x12345678 能读回
//   3) 写 x0 被忽略（x0 恒为 0）
//   4) 两个读端口独立
//   5) reg_we = 0 时写不进去
// =============================================================================
module tb_RegisterFile;
    reg         clk, reg_we;
    reg  [4:0]  raddr1, raddr2, waddr;
    reg  [31:0] wdata;
    wire [31:0] rdata1, rdata2;
    integer errs;

    RegisterFile uut (
        .clk(clk), .reg_we(reg_we),
        .raddr1(raddr1), .raddr2(raddr2),
        .waddr(waddr), .wdata(wdata),
        .rdata1(rdata1), .rdata2(rdata2)
    );

    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s  got=%h  expected %h", name, got, exp);
                errs = errs + 1;
            end else begin
                $display("PASS: %0s  = %h", name, got);
            end
        end
    endtask

    initial begin
        errs = 0; clk = 0; reg_we = 0;
        waddr = 0; wdata = 0; raddr1 = 0; raddr2 = 0;
        #1;
        check("初始 x0", rdata1, 32'h00000000);

        // 1) 写 x1 = 0x12345678
        reg_we = 1; waddr = 5'd1; wdata = 32'h12345678;
        raddr1 = 5'd1; raddr2 = 5'd0;
        @(posedge clk); #1;
        check("写后读 x1", rdata1, 32'h12345678);
        check("另一端口读 x0", rdata2, 32'h00000000);

        // 2) 写 x0 必须被忽略
        reg_we = 1; waddr = 5'd0; wdata = 32'hFFFFFFFF; raddr1 = 5'd0;
        @(posedge clk); #1;
        check("写 x0 被忽略", rdata1, 32'h00000000);

        // 3) 两个读端口独立
        reg_we = 1; waddr = 5'd2; wdata = 32'hCAFEBABE;
        raddr1 = 5'd1; raddr2 = 5'd2;
        @(posedge clk); #1;
        check("x1 不受影响", rdata1, 32'h12345678);
        check("读 x2",      rdata2, 32'hCAFEBABE);

        // 4) reg_we = 0 时写不进
        reg_we = 0; waddr = 5'd1; wdata = 32'hDEADBEEF; raddr1 = 5'd1;
        @(posedge clk); #1;
        check("写使能关闭", rdata1, 32'h12345678);

        if (errs == 0) $display("==== tb_RegisterFile: ALL PASS ====");
        else           $display("==== tb_RegisterFile: %0d FAIL ====", errs);
        $finish;
    end
endmodule
