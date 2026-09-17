`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_EES338_sort.v - "数码管演示"整机自检（CPU + MMIO + 数码管 全链路）
//
//  跑 gen_uart_demo.py sort 生成的程序（五整数冒泡排序 9,3,7,1,5 → 1,3,5,7,9），
//  用数码管 8080 扫描总线模型把 8 位数字**从引脚上还原**出来：
//   ① 每个相位只有 1 条位选有效（独热），4 相位扫完 8 位（组0→digit0..3，组1→digit4..7）
//   ② 过滤掉连续 sw 造成的瞬态（同一状态连续 3 帧才算稳定）
//   ③ 把观察到的显示状态序列与 sort_demo.py 生成的期望轨迹逐状态比对
//      （值 + 高亮位：这就是"排序过程"的文字版视频，同时也证明了流水线算得对）
//   ④ 额外检查：值发生变化的那一步，变化的位置正好是上一状态高亮的两位
//   ⑤ 最后还检查程序会"重来一轮"（重新回到乱序初值）
//
//  延时/扫描都是 RTL 参数：这里用 SCAN_DIV=2、TIMER_DELAY=64 让仿真瞬间跑完，
//  上板时用真实参数，**跑的是同一份机器码**。
//////////////////////////////////////////////////////////////////////////////////
module tb_EES338_sort;

    localparam HEX_F = "../../../../Lab2.file/seg_sort.hex";
    localparam DAT_F = "../../../../Lab2.file/seg_sort_mem.hex";
    localparam VAL_F = "../../../../Lab2.file/seg_trace_val.hex";
    localparam MRK_F = "../../../../Lab2.file/seg_trace_mrk.hex";
    localparam LEN_F = "../../../../Lab2.file/seg_trace_len.hex";

    reg clk = 0;
    always #10 clk = ~clk;               // 50MHz

    reg  rst      = 1'b1;
    reg  uart_rxd = 1'b1;
    reg  bt_rxd   = 1'b1;
    wire uart_txd, bt_txd;
    wire [7:0] lcd_d;
    wire lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n;
    wire [7:0] seg_grp0, seg_grp1;
    wire [3:0] dn0, dn1;

    EES338_Core #(
        .HEX_FILE     (HEX_F),
        .DATA_FILE    (DAT_F),
        .SEG_SCAN_DIV (2),               // 仿真用快速扫描（上板是 16384）
        .TIMER_DELAY  (64)               // 仿真用短延时（上板是 20000000 = 0.4s）
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .bt_rxd   (bt_rxd),
        .bt_txd   (bt_txd),
        .lcd_d    (lcd_d),
        .lcd_wr_n (lcd_wr_n),
        .lcd_rd_n (lcd_rd_n),
        .lcd_cs_n (lcd_cs_n),
        .lcd_rs   (lcd_rs),
        .lcd_rst_n(lcd_rst_n),
        .seg_grp0 (seg_grp0),
        .dn0      (dn0),
        .seg_grp1 (seg_grp1),
        .dn1      (dn1)
    );

    // ================= 从段码反推数字 =================
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
            default:    seg2dig = 4'hF;          // 全灭 = 空白
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

    function hot_ok(input [3:0] v);
        hot_ok = (v == 4'b0001) || (v == 4'b0010) || (v == 4'b0100) || (v == 4'b1000);
    endfunction

    // 位选 bit -> 逻辑位编号（与 SegDisplay 的 GROUP_SWAP/REVERSE_K 语义一致）
    // 本板实测：组0 模块在右边(GSWAP=1)、模块内 K1..K4 与左→右相反(REVERSE_K=1)
    localparam integer GSWAP = 1;
    localparam integer RKV   = 1;
    function [2:0] log_of(input integer bus, input [1:0] b);
        integer base;
        begin
            if (bus == 0) base = GSWAP ? 4 : 0;
            else          base = GSWAP ? 0 : 4;
            log_of = base + (RKV ? (3 - b) : b);
        end
    endfunction

    // 4bit 值 -> 可打印字符（用于打印"文字动画"）
    function [7:0] hexchr(input [3:0] v);
        hexchr = (v < 4'd10) ? (8'h30 + {4'b0, v}) : (8'h41 + {4'b0, v} - 8'd10);
    endfunction

    // 5 位数字拼成字符串（digit0 在最左）
    function [39:0] s5dig(input [31:0] v);
        s5dig = {hexchr(v[3:0]), hexchr(v[7:4]), hexchr(v[11:8]),
                 hexchr(v[15:12]), hexchr(v[19:16])};
    endfunction

    // 高亮位拼成 5 个 '*'/'.'（按 digit0..4 从左到右，与 s5dig 对齐）
    function [39:0] s5mrk(input [7:0] m);
        integer k;
        begin
            for (k = 0; k < 5; k = k + 1)
                s5mrk[8*(4-k) +: 8] = ((m >> k) & 1) ? "*" : ".";
        end
    endfunction

    // 交换次数两位
    function [15:0] s2cnt(input [31:0] v);
        s2cnt = {hexchr(v[23:20]), hexchr(v[27:24])};
    endfunction

    // ================= 扫描总线 -> 完整显示帧 =================
    reg [31:0] acc_v, acc_m;             // 本帧累加
    reg [3:0]  seen_g0, seen_g1;         // 本帧已采到的相位
    reg [31:0] cand_v, cand_m;           // 稳定候选状态
    integer    cand_n;
    reg [31:0] last_v, last_m;           // 上一条已记录的状态
    reg [31:0] obs_v [0:255];            // 观察到的状态序列
    reg [7:0]  obs_m [0:255];
    integer    n_rec;
    reg [31:0] blank_v;                  // 全空白（上电初始），不计入轨迹
    integer    err = 0;
    integer    k, d;

    task chk(input [255:0] name, input cond);
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                err = err + 1;
            end
        end
    endtask

    // 每拍采样：位选独热时把"这一位的值/高亮"写进本帧；4 相位都采到 → 一帧结束
    always @(posedge clk) begin
        if (rst) begin
            seen_g0 = 4'b0000;
            seen_g1 = 4'b0000;
            cand_n  = 0;
            n_rec   = 0;
        end
        else begin
            if (hot_ok(dn0)) begin
                acc_v[4*log_of(0, hot(dn0)) +: 4] = seg2dig(seg_grp0[6:0]);
                acc_m[log_of(0, hot(dn0))]        = seg_grp0[7];
                seen_g0[hot(dn0)]                 = 1'b1;
            end
            if (hot_ok(dn1)) begin
                acc_v[4*log_of(1, hot(dn1)) +: 4] = seg2dig(seg_grp1[6:0]);
                acc_m[log_of(1, hot(dn1))]        = seg_grp1[7];
                seen_g1[hot(dn1)]                 = 1'b1;
            end

            if ((seen_g0 == 4'hF) && (seen_g1 == 4'hF)) begin
                seen_g0 = 4'b0000;              // 一帧结束，开始下一帧
                seen_g1 = 4'b0000;

                // "稳定"判据：同一个状态连续 3 帧才算稳定（滤掉连续 sw 造成的瞬态）
                if (acc_v === cand_v && acc_m === cand_m) begin
                    if (cand_n < 3) cand_n = cand_n + 1;
                end
                else begin
                    cand_v = acc_v;
                    cand_m = acc_m;
                    cand_n = 0;
                end

                // 稳定且与上一条不同 → 记录一条（全空白状态不计入）
                if (cand_n >= 2 && (cand_v !== last_v || cand_m !== last_m)
                    && !(cand_v === blank_v && cand_m === 8'h00)) begin
                    if (n_rec < 256) begin
                        obs_v[n_rec] = cand_v;
                        obs_m[n_rec] = cand_m;
                        $display("  [%0t] state %2d : [%s]  mark[%s]  swap[%s]",
                                 $time, n_rec, s5dig(cand_v), s5mrk(cand_m), s2cnt(cand_v));
                        n_rec = n_rec + 1;
                    end
                    last_v = cand_v;
                    last_m = cand_m;
                end
            end
        end
    end


    // ================= 期望轨迹（由 sort_demo.py 生成） =================
    reg [31:0] exp_v [0:255];
    reg [7:0]  exp_m [0:255];
    reg [31:0] len_w [0:0];
    integer    n_exp;

    integer    n_chg, msk_chg;
    reg [31:0] v0, v1;
    reg [7:0]  m_prev;
    integer    wait_ms;

    initial begin
        // ---- 读期望轨迹 ----
        $readmemh(LEN_F, len_w);
        $readmemh(VAL_F, exp_v);
        $readmemh(MRK_F, exp_m);
        n_exp = len_w[0];
        blank_v = 32'hFFFFFFFF;               // 8 位全空白

        $display("==== seg-display sort demo: %0d expected states ====", n_exp);

        // ---- 放复位，等 DSP 显示/记录稳定 ----
        repeat (10) @(posedge clk);
        rst = 1'b0;

        // ---- 等观察到的状态数够（一个完整轮次 + 1 条"重来"）----
        for (wait_ms = 0; wait_ms < 20000; wait_ms = wait_ms + 1) begin
            if (n_rec >= n_exp + 1) wait_ms = 20000;
            else #10;
        end
        $display("---- observed %0d states (expected %0d + 1 restart) ----", n_rec, n_exp);

        // ---- ① 状态数 ----
        chk("enough states observed", n_rec >= n_exp + 1);

        // ---- ② 逐状态比对（值 + 高亮位）----
        n_chg = 0;
        for (k = 0; k < n_exp; k = k + 1) begin
            if (obs_v[k] !== exp_v[k] || obs_m[k] !== exp_m[k]) begin
                if (n_chg < 10)
                    $display("  MISMATCH state %0d: got [%s] 高亮[%s] , expected [%s] 高亮[%s]",
                             k, s5dig(obs_v[k]), s5mrk(obs_m[k]),
                                s5dig(exp_v[k]), s5mrk(exp_m[k]));
                n_chg = n_chg + 1;
            end
        end
        chk("display trace matches expected (values)", n_chg == 0);

        // ---- ③ 第一/最后状态显式检查（排序结果）----
        chk("initial state = 9 3 7 1 5",  obs_v[0] === exp_v[0] && obs_m[0] === 8'h00);
        chk("final state = 1 3 5 7 9",
            obs_v[n_exp-1][19:0] === 20'h97531 && obs_m[n_exp-1] === 8'h00);
        chk("final swap count = 07", s2cnt(obs_v[n_exp-1]) === "07");

        // ---- ④ 变化的位置 == 上一状态高亮的两位 ----
        n_chg = 0;
        for (k = 1; k < n_exp; k = k + 1) begin
            msk_chg = 0;
            for (d = 0; d < 5; d = d + 1) begin
                v0 = (obs_v[k-1]   >> (4*d)) & 32'hF;
                v1 = (obs_v[k]     >> (4*d)) & 32'hF;
                if (v0 !== v1) msk_chg = msk_chg | (1 << d);
            end
            if (msk_chg != 0 && msk_chg !== obs_m[k-1]) begin
                if (n_chg < 5)
                    $display("  HIGHLIGHT MISMATCH state %0d->%0d: changed=%b marked=%b",
                             k-1, k, msk_chg[4:0], obs_m[k-1][4:0]);
                n_chg = n_chg + 1;
            end
        end
        chk("swapped digits were the highlighted ones", n_chg == 0);

        // ---- ⑤ 高亮位只能是相邻的两位（或全 0）----
        n_chg = 0;
        for (k = 0; k < n_exp; k = k + 1) begin
            m_prev = obs_m[k] & 8'h1F;
            if (m_prev !== 8'h00 &&
                !(m_prev == 8'h03 || m_prev == 8'h06 || m_prev == 8'h0C || m_prev == 8'h18)) begin
                if (n_chg < 5) $display("  BAD MARK PATTERN state %0d: %b", k, m_prev);
                n_chg = n_chg + 1;
            end
        end
        chk("highlight is always an adjacent pair", n_chg == 0);

        // ---- ⑥ 程序会重来一轮 ----
        chk("program restarts (state repeats)", 
            obs_v[n_exp] === exp_v[0] && obs_m[n_exp] === 8'h00);

        if (err == 0) $display("==== tb_EES338_sort: ALL PASS ====");
        else          $display("==== tb_EES338_sort: %0d FAIL ====", err);
        $finish;
    end

    // 看门狗
    initial begin
        #2000000;
        $display("FAIL: tb_EES338_sort timeout (n_rec=%0d)", n_rec);
        $finish;
    end

endmodule

