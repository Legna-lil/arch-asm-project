`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_segdisplay.v - 数码管扫描控制器 + 硬件定时器 单元测试（自动 PASS/FAIL）
//
//  检查项：
//   ① 上电后 8 位全空白；每相位只有 1 条位选有效（独热），4 相位扫完 8 位
//   ② 写入"值"后，总线上扫描出来的确实是该位该值，且位置正确（组0→0..3，组1→4..7）
//   ③ 高亮位（bit4）会在该位点亮小数点 DP
//   ④ 0xF = 空白；en=0 时全部熄灭
//   ⑤ 刷新周期 = 4×SCAN_DIV
//   ⑥ SimpleTimer：start 后 value 从 DELAY_CYCLES 倒到 0，busy 同步正确
//////////////////////////////////////////////////////////////////////////////////
module tb_segdisplay;

    reg clk = 0;
    always #10 clk = ~clk;               // 50MHz

    localparam integer SCAN_DIV = 4;
    localparam integer TDIV     = 50;
    // 与 DUT 参数一致（本板实测：组0 模块在右边、模块内 K1..K4 与左→右相反）
    localparam integer GSWAP    = 1;
    localparam integer RKV      = 1;

    reg        rst     = 1'b1;
    reg        en      = 1'b1;
    reg        wr      = 1'b0;
    reg [2:0]  wr_idx  = 3'd0;
    reg [4:0]  wr_data = 5'h0F;

    wire [7:0] seg0, seg1;
    wire [3:0] dn0, dn1;
    wire [7:0] seg0b, seg1b;
    wire [3:0] dn0b, dn1b;

    SegDisplay #(.SCAN_DIV(SCAN_DIV), .GROUP_SWAP(GSWAP), .REVERSE_K(RKV)) dut (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .wr       (wr),
        .wr_idx   (wr_idx),
        .wr_data  (wr_data),
        .seg_grp0 (seg0),
        .dn0      (dn0),
        .seg_grp1 (seg1),
        .dn1      (dn1)
    );

    // 同一份写入接给"另一组映射参数"的实例，用来验证 GROUP_SWAP/REVERSE_K 的语义
    SegDisplay #(.SCAN_DIV(SCAN_DIV), .GROUP_SWAP(0), .REVERSE_K(0)) dut_b (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .wr       (wr),
        .wr_idx   (wr_idx),
        .wr_data  (wr_data),
        .seg_grp0 (seg0b),
        .dn0      (dn0b),
        .seg_grp1 (seg1b),
        .dn1      (dn1b)
    );

    // ---------------- SimpleTimer 被测实例 ----------------
    reg         t_start = 1'b0;
    wire [31:0] t_val;
    wire        t_busy;
    integer     t_started_at = 0;

    SimpleTimer #(.DELAY_CYCLES(TDIV)) u_timer (
        .clk   (clk),
        .rst   (rst),
        .start (t_start),
        .value (t_val),
        .busy  (t_busy)
    );

    always @(posedge clk)
        if (t_start) t_started_at <= t_val;      // 启动瞬间装进去的值

    // ---------------- 段码 -> 数字 ----------------
    function [3:0] seg2dig(input [6:0] s);
        case (s)
            7'b0111111: seg2dig = 4'd0;
            7'b0000110: seg2dig = 4'd1;
            7'b1011011: seg2dig = 4'd2;
            7'b1001111: seg2dig = 4'd3;
            7'b1100110: seg2dig = 4'd4;
            7'b1101101: seg2dig = 4'd5;
            7'b1111101: seg2dig = 4'd6;
            7'b0000111: seg2dig = 4'd7;
            7'b1111111: seg2dig = 4'd8;
            7'b1101111: seg2dig = 4'd9;
            7'b1110111: seg2dig = 4'd10;
            7'b1111100: seg2dig = 4'd11;
            7'b0111001: seg2dig = 4'd12;
            7'b1011110: seg2dig = 4'd13;
            7'b1111001: seg2dig = 4'd14;
            default:    seg2dig = 4'hF;              // 全灭 = 空白
        endcase
    endfunction

    function [1:0] hot(input [3:0] v);
        case (v)
            4'b0001: hot = 2'd0;
            4'b0010: hot = 2'd1;
            4'b0100: hot = 2'd2;
            4'b1000: hot = 2'd3;
            default: hot = 2'd0;
        endcase
    endfunction

    function is_hot(input [3:0] v);
        is_hot = (v == 4'b0001) || (v == 4'b0010) || (v == 4'b0100) || (v == 4'b1000);
    endfunction

    // 位选 bit -> 逻辑位编号（依 GROUP_SWAP / REVERSE_K 的语义）
    function [2:0] log_of(input integer bus, input [1:0] b, input integer gsw, input integer rkv);
        integer base;
        begin
            if (bus == 0) base = gsw ? 4 : 0;      // 组0 总线；GSWAP=1 时它显示右半边
            else          base = gsw ? 0 : 4;      // 组1 总线
            log_of = base + (rkv ? (3 - b) : b);
        end
    endfunction

    // ---------------- 扫描总线采样模型 ----------------
    reg [3:0]  got  [0:7];      // 从总线还原出来的 8 位数字（逻辑序）
    reg        gmk  [0:7];      // 高亮（小数点）
    reg [3:0]  gotb [0:7];      // 另一组映射参数(dut_b)还原出来的数字
    reg [3:0]  bseen0, bseen1;  // 本刷新周期已采到的相位
    reg        bad_hot;
    integer    err = 0;
    integer    i;

    always @(posedge clk) begin
        if (rst) begin
            bseen0  <= 4'b0000;
            bseen1  <= 4'b0000;
            bad_hot <= 1'b0;
        end
        else if (en) begin
            if (dn0 != 4'b0000) begin
                if (!is_hot(dn0)) bad_hot <= 1'b1;
                else begin
                    got[log_of(0, hot(dn0), GSWAP, RKV)] = seg2dig(seg0[6:0]);
                    gmk[log_of(0, hot(dn0), GSWAP, RKV)] = seg0[7];
                    bseen0[hot(dn0)] = 1'b1;
                end
            end
            if (dn1 != 4'b0000) begin
                if (!is_hot(dn1)) bad_hot <= 1'b1;
                else begin
                    got[log_of(1, hot(dn1), GSWAP, RKV)] = seg2dig(seg1[6:0]);
                    gmk[log_of(1, hot(dn1), GSWAP, RKV)] = seg1[7];
                    bseen1[hot(dn1)] = 1'b1;
                end
            end
            if (&bseen0 && &bseen1) begin     // 8 位都采到 → 一个刷新周期结束
                bseen0 <= 4'b0000;
                bseen1 <= 4'b0000;
            end
        end
    end

    // dut_b（GROUP_SWAP=0, REVERSE_K=0）的采样
    always @(posedge clk) begin
        if (!rst && en) begin
            if (is_hot(dn0b))
                gotb[log_of(0, hot(dn0b), 0, 0)] = seg2dig(seg0b[6:0]);
            if (is_hot(dn1b))
                gotb[log_of(1, hot(dn1b), 0, 0)] = seg2dig(seg1b[6:0]);
        end
    end

    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    task put(input [2:0] idx, input [4:0] d);
        begin
            @(posedge clk);
            wr = 1'b1; wr_idx = idx; wr_data = d;
            @(posedge clk);
            wr = 1'b0;
        end
    endtask

    // 等 n 个完整刷新周期
    integer k;
    task wait_refresh(input integer n);
        begin
            for (k = 0; k < n; k = k + 1) begin
                bseen0 = 4'b0000;
                bseen1 = 4'b0000;
                repeat (4 * SCAN_DIV + 4) @(posedge clk);
            end
            #1;
        end
    endtask

    integer t0, t1, period;
    integer n_ph, d0, d1, dper;
    integer n_bad;
    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            got[i] = 4'hF; gmk[i] = 1'b0; gotb[i] = 4'hF;
        end

        // ---- ① 上电 ----
        repeat (5) @(posedge clk);
        rst = 1'b0;
        wait_refresh(2);
        chk("power-on: all digits blank", seg0 === 8'h00 && seg1 === 8'h00);
        chk("digit select one-hot", !bad_hot);

        // ---- ② 写入 8 位数字（值 = 位号+1）----
        for (i = 0; i < 8; i = i + 1)
            put(i[2:0], (i[3:0] + 4'd1));
        wait_refresh(2);
        chk("digit0 shows 1", got[0] == 4'd1);
        chk("digit1 shows 2", got[1] == 4'd2);
        chk("digit2 shows 3", got[2] == 4'd3);
        chk("digit3 shows 4", got[3] == 4'd4);
        chk("digit4 shows 5 (grp1/K1)", got[4] == 4'd5);
        chk("digit5 shows 6", got[5] == 4'd6);
        chk("digit6 shows 7", got[6] == 4'd7);
        chk("digit7 shows 8", got[7] == 4'd8);
        chk("no DP when bit4=0", gmk[0] == 1'b0);

        // ---- ③ 高亮位点亮小数点 ----
        put(3'd2, 5'h13);                 // 值 3 + 高亮
        put(3'd6, 5'h17);                 // 值 7 + 高亮
        wait_refresh(2);
        chk("highlight lights DP (d2)", gmk[2] == 1'b1 && got[2] == 4'd3);
        chk("highlight lights DP (d6)", gmk[6] == 1'b1 && got[6] == 4'd7);
        chk("other digits DP off",      gmk[5] == 1'b0);

        // ---- ④ 空白 / 使能 ----
        put(3'd0, 5'h0F);
        wait_refresh(2);
        chk("0xF means blank", got[0] == 4'hF);
        put(3'd0, 5'h01);
        en = 1'b0;
        wait_refresh(2);
        chk("en=0 turns display off",
            seg0 === 8'h00 && seg1 === 8'h00 && dn0 === 4'h0 && dn1 === 4'h0);
        en = 1'b1;

        // ---- ⑤ 刷新周期 = 4×SCAN_DIV ----
        @(posedge clk);
        while (dn0 !== 4'b0001) @(posedge clk);   // 等相位0出现
        t0 = $time;
        while (dn0 === 4'b0001) @(posedge clk);   // 等它过去
        while (dn0 !== 4'b0001) @(posedge clk);   // 再等下一次出现
        t1 = $time;
        // ---- ⑤ 扫描周期：精确量 10 个刷新周期 ----
        // 先同步到"相位0 窗口的第一拍"（先离开再进入），再量 10 个周期，
        // 这样没有起始相位带来的 ±1~±4 拍误差。
        d0 = 0; d1 = 0; dper = 0;
        @(posedge clk);
        while (dn0 === 4'b0001) @(posedge clk);      // 离开相位0
        while (dn0 !== 4'b0001) @(posedge clk);      // 进入相位0（窗口第一拍）
        d0 = $time;
        for (n_ph = 0; n_ph < 10; n_ph = n_ph + 1) begin
            while (dn0 === 4'b0001) @(posedge clk);
            while (dn0 !== 4'b0001) @(posedge clk);
        end
        d1 = $time;
        dper = (d1 - d0) / 20;                       // $time 单位 1ns，时钟周期 20ns
        chk("10 scans = 10*4*SCAN_DIV cycles",
            dper == 10 * 4 * SCAN_DIV);

        // ---- ⑥ SimpleTimer ----
        @(posedge clk);
        t_start = 1'b1;
        @(posedge clk); #1;
        t_start = 1'b0;
        chk("timer reloads DELAY_CYCLES", t_started_at == TDIV);
        chk("timer busy after start", t_busy === 1'b1);
        repeat (TDIV + 4) @(posedge clk);
        chk("timer counts down to zero", t_val == 32'd0);
        chk("timer not busy at zero", t_busy === 1'b0);

        // ---- ⑦ 另一组映射参数(GSWAP=0,RKV=0)：还原出的逻辑数字应完全一致 ----
        n_bad = 0;
        for (i = 0; i < 8; i = i + 1)
            if (gotb[i] !== got[i]) n_bad = n_bad + 1;
        if (n_bad != 0)
            $display("  mapping mismatch: got=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d  gotb=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                     got[0],got[1],got[2],got[3],got[4],got[5],got[6],got[7],
                     gotb[0],gotb[1],gotb[2],gotb[3],gotb[4],gotb[5],gotb[6],gotb[7]);
        chk("alt params(0,0) same digits", n_bad == 0);

        if (err == 0) $display("==== tb_segdisplay: ALL PASS ====");
        else          $display("==== tb_segdisplay: %0d FAIL ====", err);
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: tb_segdisplay timeout");
        $finish;
    end

endmodule

