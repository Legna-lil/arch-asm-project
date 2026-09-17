`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_lcd128128.v - LCD128128 并口控制器单元测试（自动 PASS/FAIL）
//
//  检查项：
//   ① 上电复位：LCD_RST# 低电平保持 RST_CYCLES 拍，期间 busy=1，之后 busy=0
//   ② 一次写时序：CS# 低 (建立4 + WR#低10 + 保持4) 拍，WR# 上升沿锁存 D/RS
//   ③ busy 期间的写请求必须被忽略
//   ④ 软复位（LCD_CTRL bit0）能产生一次复位脉冲
//   ⑤ LCD_RD# 始终为高（本设计只写不读）
//////////////////////////////////////////////////////////////////////////////////
module tb_lcd128128;

    reg clk = 0;
    always #10 clk = ~clk;              // 50MHz：20ns/拍

    reg        rst     = 1'b1;
    reg        wr_req  = 1'b0;
    reg        rs      = 1'b0;
    reg [7:0]  wdata   = 8'h00;
    reg        rst_req = 1'b0;
    reg        rd_req  = 1'b0;          // 读请求（读显示 RAM）
    reg        inv_rst   = 1'b0;        // 调试开关：RST 极性反转
    reg        swap_wrrd = 1'b0;        // 调试开关：WR#/RD# 互换
    wire       busy;
    wire [7:0] lcd_d;
    wire [7:0] rd_data;
    wire       lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n;

    // 本 tb 同时扮演"LCD 屏"：读周期里把数据总线驱动成 RD_PAT，模拟屏返回数据
    localparam [7:0] RD_PAT = 8'h5A;
    wire rd_drive = (!lcd_cs_n && !lcd_rd_n);
    assign lcd_d = rd_drive ? RD_PAT : 8'hZZ;

    localparam integer RSTC = 20;       // 缩短复位脉宽（RTL 默认 200000 = 4ms）

    LCD128128 #(
        .WR_CYCLES    (10),
        .SETUP_CYCLES (4),
        .HOLD_CYCLES  (4),
        .RST_CYCLES   (RSTC),
        .RD_CYCLES    (12)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .wr_req    (wr_req),
        .rs        (rs),
        .wdata     (wdata),
        .rst_req   (rst_req),
        .rd_req    (rd_req),
        .inv_rst   (inv_rst),
        .swap_wrrd (swap_wrrd),
        .busy      (busy),
        .rd_data   (rd_data),
        .lcd_d     (lcd_d),
        .lcd_wr_n  (lcd_wr_n),
        .lcd_rd_n  (lcd_rd_n),
        .lcd_cs_n  (lcd_cs_n),
        .lcd_rs    (lcd_rs),
        .lcd_rst_n (lcd_rst_n)
    );

    // ---------------- 总线时序测量 ----------------
    integer cs_low = 0, cs_low_last = 0;
    integer wr_low = 0, wr_low_last = 0;
    integer rd_low = 0, rd_low_last = 0;
    reg [7:0] d_lat = 8'h00;
    reg       rs_lat = 1'b0;
    integer   err = 0;

    always @(posedge clk) begin
        if (!lcd_cs_n) cs_low <= cs_low + 1;
        else begin
            if (cs_low != 0) cs_low_last <= cs_low;
            cs_low <= 0;
        end
        if (!lcd_wr_n) wr_low <= wr_low + 1;
        else begin
            if (wr_low != 0) wr_low_last <= wr_low;
            wr_low <= 0;
        end
        if (!lcd_rd_n) rd_low <= rd_low + 1;
        else begin
            if (rd_low != 0) rd_low_last <= rd_low;
            rd_low <= 0;
        end
    end

    // WR# 上升沿就是 LCD 内部锁存数据的时刻，这里记录被锁存的值
    always @(posedge lcd_wr_n) begin
        if (!lcd_cs_n) begin
            d_lat  = lcd_d;
            rs_lat = lcd_rs;
        end
    end

    // ---------------- 检查任务 ----------------
    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    task do_write(input r, input [7:0] d);
        begin
            @(posedge clk);
            wr_req = 1'b1; rs = r; wdata = d;
            @(posedge clk);
            wr_req = 1'b0;
        end
    endtask

    // 等一次写事务彻底结束，并让测量信号（cs_low_last 等）完成更新。
    // 注意：不能在请求后立刻 wait(busy==0)——busy 是寄存器，
    //       非阻塞赋值还没生效时 wait 会"假成立"，所以先 #1 确认 busy=1。
    task wait_done;
        begin
            @(posedge clk); #1;
            if (busy !== 1'b1) $display("FAIL: busy did not assert");
            wait (busy === 1'b0);
            @(posedge clk); #1;
        end
    endtask

    task expect_busy_high;
        begin
            @(posedge clk); #1;
            chk("busy after write req", busy === 1'b1);
        end
    endtask

    // ---------------- 主流程 ----------------
    initial begin
        // ---- ① 上电复位 ----
        repeat (5) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;
        chk("POR: LCD_RST# low",        lcd_rst_n === 1'b0);
        chk("POR: busy=1",              busy      === 1'b1);
        repeat (RSTC + 3) @(posedge clk); #1;
        chk("POR: LCD_RST# released",   lcd_rst_n === 1'b1);
        chk("POR: busy=0 after pulse",  busy      === 1'b0);
        chk("LCD_RD# always high",      lcd_rd_n  === 1'b1);

        // ---- ② 一次写时序（命令 0x81）----
        cs_low_last = 0;
        wr_low_last = 0;
        do_write(1'b0, 8'h81);
        expect_busy_high;
        wait (busy === 1'b0);
        @(posedge clk); #1;
        chk("latch data = 0x81",        d_lat  === 8'h81);
        chk("latch RS = 0 (command)",   rs_lat === 1'b0);
        chk("WR# low for 10 cycles",    wr_low_last == 10);
        chk("CS# low for 18 cycles",    cs_low_last == 18);

        // ---- ② 再写一次数据（RS=1，数据 0xA5）----
        do_write(1'b1, 8'hA5);
        expect_busy_high;
        wait (busy === 1'b0);
        @(posedge clk); #1;
        chk("latch data = 0xA5",        d_lat  === 8'hA5);
        chk("latch RS = 1 (data)",      rs_lat === 1'b1);

        // ---- ③ busy 期间的写请求必须被忽略 ----
        do_write(1'b1, 8'h3C);
        @(posedge clk); #1;              // 此时 busy 已为 1
        wr_req = 1'b1; rs = 1'b0; wdata = 8'hFF;   // 忙时抢写
        @(posedge clk);
        wr_req = 1'b0;
        wait (busy === 1'b0);
        @(posedge clk); #1;
        chk("write during busy ignored", d_lat === 8'h3C);

        // ---- ④ 软复位 ----
        rst_req = 1'b1;
        @(posedge clk); #1;
        rst_req = 1'b0;
        chk("soft reset pulls LCD_RST# low", lcd_rst_n === 1'b0);
        repeat (RSTC + 3) @(posedge clk); #1;
        chk("soft reset released", lcd_rst_n === 1'b1 && busy === 1'b0);

        // ---- ⑤ 调试开关 1：RST 极性反转（inv_rst=1 时输出取反）----
        inv_rst = 1'b1;
        rst_req = 1'b1;
        @(posedge clk); #1;
        rst_req = 1'b0;
        chk("inv_rst: RST pin inverted (high during reset)",
            lcd_rst_n === 1'b1 && dut.rst_n_r === 1'b0);
        repeat (RSTC + 3) @(posedge clk); #1;
        chk("inv_rst: released becomes low", lcd_rst_n === 1'b0 && busy === 1'b0);
        inv_rst = 1'b0;

        // ---- ⑥ 调试开关 2：WR#/RD# 互换（交换的是输出脚，时序照旧）----
        swap_wrrd = 1'b1;
        @(posedge clk); #1;
        chk("swap_wrrd: outputs swapped",
            lcd_wr_n === dut.rd_n_r && lcd_rd_n === dut.wr_n_r);
        rd_low_last = 0;
        wr_low_last = 0;
        do_write(1'b1, 8'h5A);
        wait_done;
        chk("swap_wrrd: write strobe on RD pin, 10 cycles", rd_low_last == 10);
        chk("swap_wrrd: WR pin stays high",              wr_low_last == 0);
        swap_wrrd = 1'b0;

        // ---- ⑦ 读显示 RAM（8080 读选通）：RD# 低 12 拍、RS=1、结束时采样总线 ----
        rd_low_last = 0;
        rd_req = 1'b0;
        @(posedge clk); #1;
        chk("read: idle before request", busy === 1'b0);
        rd_req = 1'b1;
        @(posedge clk); #1;
        rd_req = 1'b0;
        chk("read: busy asserted",  busy === 1'b1);
        chk("read: RS=1 (data)",    lcd_rs === 1'b1);
        chk("read: CS# low",        lcd_cs_n === 1'b0);
        repeat (30) @(posedge clk);
        #1;
        chk("read: RD# was low 12 cycles", rd_low_last == 12);
        chk("read: busy released",         busy === 1'b0);
        chk("read: bus data latched 5A", rd_data === 8'h5A);
        chk("read: CS# high after read",   lcd_cs_n === 1'b1);
        chk("read: RD# high after read",   lcd_rd_n === 1'b1);

        if (err == 0) $display("==== tb_lcd128128: ALL PASS ====");
        else          $display("==== tb_lcd128128: %0d FAIL ====", err);
        $finish;
    end

    // 看门狗
    initial begin
        #200000;
        $display("FAIL: tb_lcd128128 timeout");
        $finish;
    end

endmodule
