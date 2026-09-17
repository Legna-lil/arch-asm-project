# lcd_demo.py - LCD 演示程序生成辅助（由 gen_uart_demo.py 调用）
#
# 把"要显示什么"和"RTL 怎么做"彻底分开：
#   * RTL(LCD128128.v) 只负责 8080 并口的字节级写时序，完全不关心命令语义；
#   * 初始化命令序列、字符图案都在这里（Python）生成成 DMEM 里的数据表，
#     所以换屏/调对比度/改显示内容只需要改本文件再重新跑 gen_uart_demo.py，
#     不用动任何 Verilog。
#
# 硬件背景（EES-338 手册 §13）：板载 JLX128128G-81202，驱动 IC ST7571，
# 128×128 单色点阵，8 页（每页 8 行）× 128 列，字节的 bit0 是最上面一行。

# ---------------- 5×7 点阵字模（'#'=点亮），显示时放在 8×16 的字符格里 ----------------
FONT = {
    'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    'S': [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    '-': [".....", ".....", ".....", "#####", ".....", ".....", "....."],
    '3': ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    '8': [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    'L': ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    'C': [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
    'D': ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    'O': [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    'K': ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    ' ': [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}

# ---------------- 初始化命令表（ST7571 / ST7565 兼容命令集）----------------
# ★ 关键：电源命令（0x2C/0x2E/0x2F）之后必须等电源稳定再开显示（0xAF），
#   很多屏"不等就全黑不亮"。所以序列里插了 4 个 DELAY 标记：
#   上板每个 DELAY = 0.4s，仿真 = 64 拍（都由 RTL 的 TIMER_DELAY 参数决定）。
# 若上板后出现"不亮 / 花屏 / 对比度不对"，按下面注释逐项调：
#   0xA0/0xA1 段方向、0xC0/0xC8 行扫描方向、0xA2/0xA3 BIAS、
#   0x24~0x26 内部电阻比、0x81 后的那个字节就是对比度（0x00~0x3F）。
DELAY = 0x200        # 轨迹里的"等待一个硬件定时器周期"标记（bit9）
LCD_INIT = [
    0xE2,        # 软复位
    0xAE,        # 关显示
    0xA2,        # LCD BIAS = 1/9      （变体 LCD_INIT_ALT 用 0xA3 = 1/7）
    0xA0,        # ADC/段方向：正常
    0xC8,        # COM 扫描方向：反向
    0xA6,        # 正显
    0xA4,        # 正常显示（不是"全点亮"）
    0x40,        # 显示起始行 = 0
    0x24,        # 内部电阻比          （变体用 0x25）
    0x81, 0x28,  # 电子音量（对比度）  （变体用 0x30）
    0x2C,        # 电源：升压电路 VC
    DELAY,       # ← 等电源稳定
    0x2E,        # 电源：稳压电路 VR
    DELAY,
    0x2F,        # 电源：电压跟随 VF
    DELAY,
    0xAF,        # 开显示
    DELAY,       # ← 开显示后再等一拍才写像素数据
]

# 初始化变体（自检程序会用到的第二组参数：BIAS 1/7 + 电阻比 25 + 对比度 0x30）
LCD_INIT_ALT = [
    0xE2, 0xAE, 0xA3, 0xA0, 0xC8, 0xA6, 0xA4, 0x40, 0x25,
    0x81, 0x30,
    0x2C, DELAY, 0x2E, DELAY, 0x2F, DELAY, 0xAF, DELAY,
]

# 显示内容：(起始页, 起始列, 文字)，一个字符占 8 列 × 2 页（8×16）
DISPLAY_LINES = [
    (0, 8, "EES-338"),
    (4, 8, "LCD OK"),
]
UART_MSG = "LCD OK\r\n"


def _cell_byte(ch, cc, half):
    """字符 ch 在 8×16 字符格里第 cc 列、第 half(0/1) 页对应的一个字节"""
    g = FONT[ch]
    byte = 0
    for r in range(8):
        gy = half * 8 + r - 4      # 7 行字形在 16 行格里居中（上下各留白）
        gx = cc - 1                # 5 列字形在 8 列格里居中
        if 0 <= gy < 7 and 0 <= gx < 5 and g[gy][gx] == '#':
            byte |= (1 << r)       # bit0 = 页内最上一行
    return byte


def build_fb_words(lines=None, cols=128, pages=8):
    """把要显示的内容渲染成 128×128 的期望帧缓存（8 页 × 128 列，每格 1 字节），
    供仿真 $readmemh 后与 LCD 总线模型收到的数据逐字节比对。"""
    if lines is None:
        lines = DISPLAY_LINES
    fb = [0] * (cols * pages)
    for page, col0, text in lines:
        for half in (0, 1):
            for i, ch in enumerate(text):
                for cc in range(8):
                    idx = (page + half) * cols + col0 + i * 8 + cc
                    if 0 <= idx < len(fb):
                        fb[idx] = _cell_byte(ch, cc, half)
    return fb


def build_draw_stream(lines=None):
    """生成"命令/数据混合流"：每条目 = (RS<<8) | 字节"""
    if lines is None:
        lines = DISPLAY_LINES
    entries = []
    for page, col, text in lines:
        for half in (0, 1):
            entries.append((0, 0xB0 | (page + half)))         # 页地址
            entries.append((0, 0x10 | ((col >> 4) & 0x0F)))   # 列地址高 4 位
            entries.append((0, col & 0x0F))                   # 列地址低 4 位
            for ch in text:
                for cc in range(8):
                    entries.append((1, _cell_byte(ch, cc, half)))
    return entries


def build_dmem(draw=None, init=None):
    """DMEM 数据表：
         [0]            = 初始化命令条数
         [1 .. N]       = 初始化命令字节
         [N+1]          = 图案条目数
         [N+2 ..]       = 图案条目 (RS<<8)|字节
    """
    if draw is None:
        draw = build_draw_stream()
    if init is None:
        init = LCD_INIT
    words = [len(init)] + list(init) + [len(draw)]
    words += [(rs << 8) | (b & 0xFF) for (rs, b) in draw]
    return words


def _uart_print_block(text, prefix="uw"):
    """生成"轮询 UART 空闲后打印一个字节"的内联代码（ISA 无 jalr，不做子程序）"""
    out = []
    for i, ch in enumerate(text):
        out.append("        addi  x16, x0, %-4d          # %s" %
                   (ord(ch), repr(ch)))
        out.append("%s%d:" % (prefix, i))
        out.append("        lw    x12, 4(x10)           # UART_STATUS")
        out.append("        andi  x12, x12, 1           # TX_BUSY?")
        out.append("        bne   x12, x0, %s%d" % (prefix, i))
        out.append("        sw    x16, 0(x10)           # UART_DATA")
    return out


def _uart_put16_block(prefix):
    """生成"把 x16 当前值打印出去"的内联代码（x16 已算好）"""
    return [
        "%s_put:" % prefix,
        "        lw    x12, 4(x10)           # UART_STATUS",
        "        andi  x12, x12, 1",
        "        bne   x12, x0, %s_put" % prefix,
        "        sw    x16, 0(x10)           # UART_DATA",
    ]

PROG_TEMPLATE = '''
        # ============================================================
        # LCD 演示程序（由 gen_uart_demo.py lcd 自动生成，勿手改）
        #   1) 等 LCD 控制器上电复位脉宽结束（轮询 LCD_STATUS.busy）
        #   2) 发送初始化命令表（表在 DMEM，见 lcd_demo.py: LCD_INIT）
        #   3) 清屏（8 页 × 128 列全 0，用循环算，不占表空间）
        #   4) 逐字节写字符图案（命令/数据混合流，bit8 = RS）
        #   5) 通过 USB-UART 打印 "LCD OK" 作串口自检回执
        #
        # 寄存器分工：
        #   x10 = MMIO 基址 0x1000_0000     x11 = 数据区基址 0x1001_0000
        #   x12 = 轮询临时量                x13 = 剩余条目数
        #   x15 = 数据表指针                x16 = 字节 / (RS<<8)|字节
        #   x18 = RS 位                     x19/x20/x22 = 循环量
        # ============================================================
        auipc x10, 0x0fc00
        addi  x10, x10, 0             # x10 = 0x10000000
        auipc x11, 0x0fc10
        addi  x11, x11, -8            # x11 = 0x10010000
        # ---- 1) 等 LCD 上电复位结束 ----
lcd_boot:
        lw    x12, 264(x10)           # LCD_STATUS (0x1000_0108)
        andi  x12, x12, 1             # bit0 = LCD_BUSY
        bne   x12, x0, lcd_boot
        # ---- 2) 初始化命令表 ----
        lw    x13, 0(x11)             # [0] = 命令条数
        addi  x15, x11, 4             # 命令表从 [1] 开始
lcd_init:
        beq   x13, x0, lcd_clr0
        lw    x16, 0(x15)
        andi  x18, x16, 512           # bit9 = 延时标记?
        bne   x18, x0, lcd_idly
        andi  x16, x16, 255           # 低 8 位 = 命令字节
lcd_iw:
        lw    x12, 264(x10)
        andi  x12, x12, 1
        bne   x12, x0, lcd_iw
        sw    x16, 256(x10)           # LCD_CMD (0x1000_0100)
        jal   x0, lcd_inext
lcd_idly:
        addi  x12, x0, 1
        sw    x12, 580(x10)           # TIMER_CTRL: 启动一次硬件延时
lcd_iw2:
        lw    x12, 584(x10)           # TIMER_VALUE: 0 = 延时结束
        bne   x12, x0, lcd_iw2
lcd_inext:
        addi  x15, x15, 4
        addi  x13, x13, -1
        jal   x0, lcd_init
        # ---- 3) 清屏：8 页 × 128 列写 0 ----
lcd_clr0:
        addi  x20, x0, 0              # x20 = 页号
lcd_cpage:
        addi  x19, x0, 8
        bge   x20, x19, lcd_drw0
        ori   x16, x20, 176           # 0xB0 | 页号
lcd_cw1:
        lw    x12, 264(x10)
        andi  x12, x12, 1
        bne   x12, x0, lcd_cw1
        sw    x16, 256(x10)           # 页地址命令
        addi  x16, x0, 16             # 列地址高 4 位 = 0
lcd_cw2:
        lw    x12, 264(x10)
        andi  x12, x12, 1
        bne   x12, x0, lcd_cw2
        sw    x16, 256(x10)
lcd_cw3:
        lw    x12, 264(x10)
        andi  x12, x12, 1
        bne   x12, x0, lcd_cw3
        sw    x0, 256(x10)            # 列地址低 4 位 = 0
        addi  x22, x0, 0              # x22 = 列计数
lcd_ccol:
        addi  x19, x0, 128
        bge   x22, x19, lcd_cnext
lcd_cw4:
        lw    x12, 264(x10)
        andi  x12, x12, 1
        bne   x12, x0, lcd_cw4
        sw    x0, 260(x10)            # LCD_DAT (0x1000_0104) = 0
        addi  x22, x22, 1
        jal   x0, lcd_ccol
lcd_cnext:
        addi  x20, x20, 1
        jal   x0, lcd_cpage
        # ---- 4) 字符图案（bit8 = RS）----
lcd_drw0:
        lw    x13, __OFF_CNT__(x11)   # 图案条目数
        addi  x15, x11, __OFF_DRAW__  # 图案表首地址
lcd_dloop:
        beq   x13, x0, lcd_msg0
        lw    x16, 0(x15)
        andi  x18, x16, 256           # RS 位
        andi  x12, x16, 512           # 延时标记?
        bne   x12, x0, lcd_ddly
        andi  x16, x16, 255           # 低 8 位 = 字节
lcd_dw:
        lw    x12, 264(x10)
        andi  x12, x12, 1
        bne   x12, x0, lcd_dw
        beq   x18, x0, lcd_dcmd
        sw    x16, 260(x10)           # LCD_DAT
        jal   x0, lcd_dnext
lcd_dcmd:
        sw    x16, 256(x10)           # LCD_CMD
        jal   x0, lcd_dnext
lcd_ddly:
        addi  x12, x0, 1
        sw    x12, 580(x10)
lcd_dw2:
        lw    x12, 584(x10)
        bne   x12, x0, lcd_dw2
lcd_dnext:
        addi  x15, x15, 4
        addi  x13, x13, -1
        jal   x0, lcd_dloop
        # ---- 5) 串口回执 ----
lcd_msg0:
__UART_PRINT__
lcd_end:
        jal   x0, lcd_end
'''


def build_program(init=None, draw=None, uart_msg=None):
    """生成 LCD 演示汇编程序（IMEM 内容）"""
    if init is None:
        init = LCD_INIT
    if draw is None:
        draw = build_draw_stream()
    if uart_msg is None:
        uart_msg = UART_MSG
    n_init = len(init)
    off_cnt = 4 * (n_init + 1)
    off_draw = 4 * (n_init + 2)
    prog = PROG_TEMPLATE.replace("__OFF_CNT__", str(off_cnt))
    prog = prog.replace("__OFF_DRAW__", str(off_draw))
    prog = prog.replace("__UART_PRINT__", "\n".join(_uart_print_block(uart_msg)))
    return prog


# ============================================================================
# LCD 自检程序：自动试遍 8 种配置组合，串口报进度，屏上全屏点亮
#   组合 k = 0..7： rstp = k>>2（RST 极性），swap = (k>>1)&1（WR/RD 互换），var = k&1（初始化变体）
#   k 的含义会以 "CFG r s v" 的形式打到 USB-UART 上，方便对照
# ============================================================================
CFG_TAB_WORDS = 16        # 8 组配置 × 2 words
TAB_STRIDE_W  = 32        # 每个初始化表占 32 个字（首字 = 条目数）
SELFTEST_MSG  = "LCD SELFTEST\r\n"


def _pad_table(entries, n=TAB_STRIDE_W):
    e = list(entries)[:n - 1]
    return [len(entries)] + e + [0] * (n - 1 - len(e))


def build_test_dmem():
    """自检程序数据区：
         [0..15]   CFG 表（每 2 字：LCD_CTRL 值、初始化表条目首地址(字节偏移)）
         [16..]    初始化表 A（首字=条目数）
         [..]      初始化表 B
    """
    words = [0] * CFG_TAB_WORDS
    a_start = len(words)
    words += _pad_table(LCD_INIT)
    b_start = len(words)
    words += _pad_table(LCD_INIT_ALT)
    a_off = (a_start + 1) * 4
    b_off = (b_start + 1) * 4
    for k in range(8):
        var  = k & 1
        swap = (k >> 1) & 1
        rstp = (k >> 2) & 1
        ctrl = 1 | (rstp << 1) | (swap << 2)     # bit0=1 同时触发一次硬复位
        words[2 * k]     = ctrl
        words[2 * k + 1] = b_off if var else a_off
    return words


def _lcd_send16(tag):
    """把 x16 当前值作为命令写到 LCD_CMD（等 busy）"""
    return [
        "%s_w:" % tag,
        "        lw    x12, 264(x10)           # LCD_STATUS",
        "        andi  x12, x12, 1             # bit0 = BUSY?",
        "        bne   x12, x0, %s_w" % tag,
        "        sw    x16, 256(x10)           # LCD_CMD (0x1000_0100)",
    ]


def _lcd_send_data16(tag):
    """把 x16 当前值作为数据写到 LCD_DAT（等 busy）"""
    return [
        "%s_w:" % tag,
        "        lw    x12, 264(x10)",
        "        andi  x12, x12, 1",
        "        bne   x12, x0, %s_w" % tag,
        "        sw    x16, 260(x10)           # LCD_DAT (0x1000_0104)",
    ]


def _hw_delay(tag, n=1):
    """启动 n 个硬件定时器周期（上板 0.4s/个，仿真 64 拍/个）"""
    out = []
    for i in range(n):
        out.append("        addi  x12, x0, 1")
        out.append("        sw    x12, 580(x10)           # TIMER_CTRL = 1")
        out.append("%s_w%d:" % (tag, i))
        out.append("        lw    x12, 584(x10)           # TIMER_VALUE")
        out.append("        bne   x12, x0, %s_w%d" % (tag, i))
    return out


def build_test_program():
    """LCD 自检 v3：8 种配置 × {A5 全屏点亮 / 半屏图案 / 对比度扫描}

    每种配置 k=0..7（k = rstp*4 + swap*2 + variant）依次做：
      ① 写 LCD_CTRL（调试开关 + 硬复位脉冲）→ 等复位结束 → 发初始化表
      ② 命令 0xA5（不管 RAM 内容，强制全屏点亮）→ 停 0.8s     串口打印 A
      ③ 命令 0xA4（恢复正常显示）→ 停 0.4s
      ④ 画"半屏图案"：左半屏全亮(0xFF)、右半屏全灭(0x00)      串口打印 P
      ⑤ 对比度扫描 EV = 0x00,0x08,0x10,...,0x38，每档停 0.4s
         （每档开始时串口打印一个字符 '0'..'7'）
    串口每轮形如：  C0 / A / P / EV01234567

    判读方法：
      · 看到 A 之后屏变黑 → 面板/电源/对比度都活着；再看 P 之后有没有
        "左黑右白"的竖直分界 → 有 = 总线数据也通了（找到可用的 EV 档即可）
      · A 之后不变、但 EV 扫到某一档出现竖直分界 → 数据通、只需调对比度
      · 8 档 EV 全程毫无变化 → 总线/引脚层面数据没进屏（记下配置号）
    """
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # LCD 自检 v3（由 lcd_demo.py 生成，勿手改）")
    A("        #   串口输出：C<k> / A / P / EV01234567  （每轮 8 种配置）")
    A("        #   k = rstp*4 + swap*2 + variant（见文档 §3.4）")
    A("        # ============================================================")
    A("lcdtest_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    A("        auipc x11, 0x0fc10")
    A("        addi  x11, x11, -8            # x11 = 0x10010000 (数据表)")
    A("        addi  x21, x0, 0              # 配置号 k = 0")
    L += _uart_print_block("LCD TEST3\r\n", "st0_")

    # ---------------- 每种配置：设开关 + 复位 + 初始化 ----------------
    A("lcdtest_cfg:")
    A("        slli  x22, x21, 3             # k*8 字节 = 每配置 2 个字")
    A("        add   x22, x11, x22")
    A("        lw    x16, 0(x22)             # LCD_CTRL 值（bit0 触发硬复位）")
    A("        lw    x25, 4(x22)             # 初始化表首地址（字节偏移）")
    A("        sw    x16, 268(x10)           # 设调试开关 + 复位脉冲")
    A("lcdtest_rstw:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_rstw   # 等复位脉宽结束")
    A("        add   x15, x11, x25")
    A("        lw    x13, -4(x15)            # 初始化表条目数")
    A("lcdtest_init:")
    A("        beq   x13, x0, lcdtest_rep")
    A("        lw    x16, 0(x15)")
    A("        andi  x18, x16, 512           # bit9 = 延时标记?")
    A("        bne   x18, x0, lcdtest_dly1")
    A("        andi  x16, x16, 255")
    L += _lcd_send16("lcdtest_iw")
    A("        jal   x0, lcdtest_inext")
    A("lcdtest_dly1:")
    L += _hw_delay("lcdtest_iwd")
    A("lcdtest_inext:")
    A("        addi  x15, x15, 4")
    A("        addi  x13, x13, -1")
    A("        jal   x0, lcdtest_init")

    # ---- 串口报 "C<k>" ----
    A("lcdtest_rep:")
    L += _uart_print_block("C", "st1_")
    A("        addi  x16, x21, 48            # '0'+k")
    L += _uart_put16_block("st2_")
    L += _uart_print_block("\r\n", "st2b_")


    # ---- ② 0xA5：不管 RAM，强制全屏点亮（1/2）----
    A("        addi  x16, x0, 165            # 0xA5 = 全屏点亮")
    L += _lcd_send16("lcdtest_a5")
    A("        addi  x16, x0, 175            # 0xAF = 显示开（保险）")
    L += _lcd_send16("lcdtest_af")
    L += _uart_print_block("A\r\n", "st3_")
    L += _hw_delay("lcdtest_a5d", 2)       # 0.8s，看清"全屏变黑"

    # ---- ③ 0xA4：恢复正常显示 ----
    A("        addi  x16, x0, 164            # 0xA4 = 正常显示")
    L += _lcd_send16("lcdtest_a4")
    L += _hw_delay("lcdtest_a4d", 1)

    # ---- ④ 半屏图案：8 页 × (3 条命令 + 左 64 列 0xFF + 右 64 列 0x00) ----
    A("        addi  x20, x0, 0              # 页号 0..7")
    A("lcdtest_pg:")
    A("        addi  x19, x0, 8")
    A("        bge   x20, x19, lcdtest_pdone")
    A("        ori   x16, x20, 176           # 0xB0 | 页号")
    L += _lcd_send16("lcdtest_pp")
    A("        addi  x16, x0, 16             # 列地址高 4 位 = 0")
    L += _lcd_send16("lcdtest_pch")
    A("        addi  x16, x0, 0              # 列地址低 4 位 = 0")
    L += _lcd_send16("lcdtest_pcl")
    A("        addi  x16, x0, 255            # 左半屏：全亮")
    A("        addi  x19, x0, 64             # 64 列")
    A("lcdtest_pl:")
    L += _lcd_send_data16("lcdtest_plw")
    A("        addi  x19, x19, -1")
    A("        bne   x19, x0, lcdtest_pl")
    A("        addi  x16, x0, 0              # 右半屏：全灭")
    A("        addi  x19, x0, 64")
    A("lcdtest_pr:")
    L += _lcd_send_data16("lcdtest_prw")
    A("        addi  x19, x19, -1")
    A("        bne   x19, x0, lcdtest_pr")
    A("        addi  x20, x20, 1")
    A("        jal   x0, lcdtest_pg")
    A("lcdtest_pdone:")
    L += _uart_print_block("P\r\n", "st4_")
    L += _uart_print_block("EV", "st5_")
    L += _hw_delay("lcdtest_pd", 1)

    # ---- ⑤ 对比度扫描：EV = 0x00,0x08,0x10,...,0x38 ----
    A("        addi  x23, x0, 0              # EV 档号 i = 0..7")
    A("lcdtest_ev:")
    A("        addi  x19, x0, 8")
    A("        bge   x23, x19, lcdtest_cfgnext")
    A("        addi  x16, x0, 129            # 0x81 = 电子音量（对比度）")
    L += _lcd_send16("lcdtest_ev1")
    A("        slli  x16, x23, 3             # EV = i*8")
    L += _lcd_send16("lcdtest_ev2")
    A("        addi  x16, x23, 48            # 打印档号 '0'..'7'")
    L += _uart_put16_block("st6_")
    L += _hw_delay("lcdtest_evd", 1)
    A("        addi  x23, x23, 1")
    A("        jal   x0, lcdtest_ev")

    # ---------------- 下一种配置 ----------------
    A("lcdtest_cfgnext:")
    L += _uart_print_block("\r\n", "st7_")
    A("        addi  x21, x21, 1")
    A("        andi  x21, x21, 7             # 0..7 循环")
    A("        jal   x0, lcdtest_cfg")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def _lcd_read_byte(dst, tag):
    """触发一次 8080 读周期 → 等 busy 结束 → 把读回的字节装入 dst（8 条指令）"""
    return [
        "        addi  x24, x0, 1",
        "        sw    x24, 272(x10)           # LCD_RCTRL=1 启动读显示 RAM",
        "%s_w:" % tag,
        "        lw    x12, 264(x10)           # LCD_STATUS",
        "        andi  x12, x12, 1",
        "        bne   x12, x0, %s_w" % tag,
        "        lw    %s, 276(x10)           # LCD_RDATA（读回的字节）" % dst,
    ]


def _seg_show_byte(reg, tag):
    """把寄存器 reg 的 8 位逐位显示到数码管 dig0..dig7（dig0 = bit7）"""
    out = []
    for i in range(8):
        bit = 7 - i
        out.append("        slli  x21, %s, %d           # bit%d" % (reg, 31 - bit, bit))
        out.append("        slt   x21, x21, x0")
        out.append("        sw    x21, %d(x10)           # dig%d" % (512 + 4 * i, i))
    return out


def _uart_put_byte_bits(reg, tag):
    """把寄存器 reg 的 8 位以 '0'/'1' 字符打到 USB-UART（bit7 先打）"""
    out = []
    for i in range(8):
        bit = 7 - i
        out.append("        slli  x16, %s, %d           # bit%d" % (reg, 31 - bit, bit))
        out.append("        slt   x16, x16, x0")
        out.append("        addi  x16, x16, 48         # '0'/'1'")
        out += _uart_put16_block("%s%d" % (tag, i))
    return out


def build_readback_program():
    """LCD 读回自检（v4）：写已知字节进显示 RAM，再用 8080 读选通读回来比对。

    流程：硬复位 → 初始化 → 写 (页0,列0)=0x5A、(页0,列1)=0x3C → 循环：
          列地址设回 0 → 读 3 次（第 1 次是 ST7571 规定的"空读"）
          → 把第 2、3 次读到的字节显示到数码管（逐位）并从串口打 8 个 0/1
    判读：
      · 读到 01011010（0x5A）→ 总线与控制器都正常，问题只在"显示"
        （对比度/V0/显示模式），可以继续调初始化；
      · 读到 11111111 → LCD 侧完全没有驱动数据线（未接好/接口模式不是 8080/
        引脚与手册不符）；XDC 里给数据线加了弱上拉，所以悬空时读回全 1；
      · 读到别的值 → 位序或个别数据线有问题（把值告诉我）。
    """
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # LCD 读回自检 v4（由 lcd_demo.py 生成，勿手改）")
    A("        #   串口输出：\"LCD READBACK\" 后反复打印  1=<8bit>  2=<8bit>")
    A("        #   数码管 dig0..dig7 逐位显示最近读回的字节（dig0 = bit7）")
    A("        #   期望：1=01011010（写入的 0x5A）  2=00111100（写入的 0x3C）")
    A("        # ============================================================")
    A("lcdrb_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    A("        auipc x11, 0x0fc10")
    A("        addi  x11, x11, -8            # x11 = 0x10010000 (数据表)")
    L += _uart_print_block("LCD READBACK\r\n", "rb0_")

    # ---- ① 取 CFG[0]（标准配置，不含任何调试开关），设开关 + 复位 ----
    A("        lw    x16, 0(x11)             # CFG[0].ctrl（bit0=复位脉冲）")
    A("        lw    x25, 4(x11)             # CFG[0].init_ptr（初始化表偏移）")
    A("        sw    x16, 268(x10)           # 写 LCD_CTRL")
    A("lcdrb_rst:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdrb_rst      # 等复位脉宽结束")

    # ---- ② 发初始化表（表在 DMEM，条目 bit9=1 表示"等电源稳定"）----
    A("        add   x15, x11, x25")
    A("        lw    x13, -4(x15)            # 条目数")
    A("lcdrb_init:")
    A("        beq   x13, x0, lcdrb_fill")
    A("        lw    x16, 0(x15)")
    A("        andi  x18, x16, 512           # bit9 = 延时标记?")
    A("        bne   x18, x0, lcdrb_dly")
    A("        andi  x16, x16, 255")
    L += _lcd_send16("lcdrb_iw")
    A("        jal   x0, lcdrb_inext")
    A("lcdrb_dly:")
    L += _hw_delay("lcdrb_iwd")
    A("lcdrb_inext:")
    A("        addi  x15, x15, 4")
    A("        addi  x13, x13, -1")
    A("        jal   x0, lcdrb_init")

    # ---- ③ 写两个已知字节：(页0,列0) = 0x5A，(页0,列1) = 0x3C ----
    A("lcdrb_fill:")
    A("        addi  x16, x0, 176            # 0xB0 = 页 0")
    L += _lcd_send16("lcdrb_p")
    A("        addi  x16, x0, 16             # 列地址高 4 位 = 0")
    L += _lcd_send16("lcdrb_ch")
    A("        addi  x16, x0, 0              # 列地址低 4 位 = 0")
    L += _lcd_send16("lcdrb_cl")
    A("        addi  x16, x0, 90             # 0x5A")
    L += _lcd_send_data16("lcdrb_d1")
    A("        addi  x16, x0, 60             # 0x3C")
    L += _lcd_send_data16("lcdrb_d2")

    # ---- ④ 循环：列地址回到 0 → 读 3 次 → 显示/打印 ----
    A("lcdrb_loop:")
    A("        addi  x16, x0, 16             # 列地址 = 0（读同一地址）")
    L += _lcd_send16("lcdrb_ch2")
    A("        addi  x16, x0, 0")
    L += _lcd_send16("lcdrb_cl2")
    L += _lcd_read_byte("x17", "lcdrb_rd1")     # 空读（丢弃）
    L += _lcd_read_byte("x18", "lcdrb_rd2")     # 期望 0x5A
    L += _lcd_read_byte("x19", "lcdrb_rd3")     # 期望 0x3C
    # 显示 + 打印第 2 个字节
    L += _seg_show_byte("x18", "")
    L += _uart_print_block("1=", "rb1_")
    L += _uart_put_byte_bits("x18", "rb1b")
    L += _uart_print_block("\r\n", "rb1c")
    L += _hw_delay("lcdrb_d1d", 1)
    # 显示 + 打印第 3 个字节
    L += _seg_show_byte("x19", "")
    L += _uart_print_block("2=", "rb2_")
    L += _uart_put_byte_bits("x19", "rb2b")
    L += _uart_print_block("\r\n", "rb2c")
    L += _hw_delay("lcdrb_d2d", 1)
    A("        jal   x0, lcdrb_loop")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def build_test_program_v2():
    """LCD 自检 v2（历史版本，保留供对照）：8 种配置 + 全屏点亮 + 串口报 CFG r s v
    说明：v2 只做"全屏点亮"，无法区分"数据没进屏"和"对比度不对"，已被 v3 取代。"""

    L = []
    A = L.append
    A("        # ============================================================")
    A("        # LCD 自检（由 lcd_demo.py 生成，勿手改）")
    A("        #   每种配置：写 LCD_CTRL(开关+复位脉冲) → 等复位 → 初始化 → 全屏点亮")
    A("        #             → 串口打印 CFG r s v → 停 2s → 下一种")
    A("        #   r=1 表示 RST 高有效、s=1 表示 WR/RD 互换、v=初始化变体编号")
    A("        #   寄存器：x10=MMIO基址 x11=数据区基址 x15=表指针 x19/x20/x22=循环量")
    A("        #           x21=组合号 x16=临时/待打印字节 x18/x24/x25=临时")
    A("        # ============================================================")
    A("lcdtest_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000")
    A("        auipc x11, 0x0fc10")
    A("        addi  x11, x11, -8            # x11 = 0x10010000")
    A("        addi  x21, x0, 0              # 组合号 k = 0")
    L += _uart_print_block(SELFTEST_MSG, "st0_")
    A("lcdtest_cfg:")
    A("        slli  x22, x21, 3             # k*8 字节 = 每组合 2 个字")
    A("        add   x22, x11, x22")
    A("        lw    x16, 0(x22)             # LCD_CTRL 值（bit0 触发一次硬复位）")
    A("        lw    x25, 4(x22)             # 本组合的初始化表首地址（字节偏移）")
    A("        sw    x16, 268(x10)           # 写 LCD_CTRL：设置调试开关 + 复位脉冲")
    A("lcdtest_rstw:")
    A("        lw    x12, 264(x10)           # LCD_STATUS")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_rstw   # 等复位脉宽结束")
    A("        add   x15, x11, x25")
    A("        lw    x13, -4(x15)            # 条目数（放在表首字）")
    A("lcdtest_init:")
    A("        beq   x13, x0, lcdtest_fill0")
    A("        lw    x16, 0(x15)")
    A("        andi  x18, x16, 512           # bit9 = 延时标记?")
    A("        bne   x18, x0, lcdtest_dly1")
    A("        andi  x16, x16, 255")
    A("lcdtest_iw:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_iw")
    A("        sw    x16, 256(x10)           # LCD_CMD")
    A("        jal   x0, lcdtest_inext")
    A("lcdtest_dly1:")
    A("        addi  x12, x0, 1")
    A("        sw    x12, 580(x10)           # TIMER_CTRL")
    A("lcdtest_iw2:")
    A("        lw    x12, 584(x10)           # TIMER_VALUE")
    A("        bne   x12, x0, lcdtest_iw2")
    A("lcdtest_inext:")
    A("        addi  x15, x15, 4")
    A("        addi  x13, x13, -1")
    A("        jal   x0, lcdtest_init")

    # ---- 全屏点亮（8 页 × 128 列 全 0xFF）----
    A("lcdtest_fill0:")
    A("        addi  x20, x0, 0              # 页号")
    A("        addi  x18, x0, 255            # 全亮数据 0xFF")
    A("lcdtest_fpage:")
    A("        addi  x19, x0, 8")
    A("        bge   x20, x19, lcdtest_report")
    A("        ori   x16, x20, 176           # 0xB0 | 页号")
    A("lcdtest_fw1:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_fw1")
    A("        sw    x16, 256(x10)")
    A("        addi  x16, x0, 16             # 列地址高 4 位 = 0")
    A("lcdtest_fw2:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_fw2")
    A("        sw    x16, 256(x10)")
    A("lcdtest_fw3:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_fw3")
    A("        sw    x0, 256(x10)            # 列地址低 4 位 = 0")
    A("        addi  x22, x0, 0              # 列计数")
    A("lcdtest_fcol:")
    A("        addi  x19, x0, 128")
    A("        bge   x22, x19, lcdtest_fnext")
    A("lcdtest_fw4:")
    A("        lw    x12, 264(x10)")
    A("        andi  x12, x12, 1")
    A("        bne   x12, x0, lcdtest_fw4")
    A("        sw    x18, 260(x10)           # LCD_DAT = 0xFF")
    A("        addi  x22, x22, 1")
    A("        jal   x0, lcdtest_fcol")
    A("lcdtest_fnext:")
    A("        addi  x20, x20, 1")
    A("        jal   x0, lcdtest_fpage")
    # ---- 串口报进度 "CFG r s v\r\n" ----
    A("lcdtest_report:")
    L += _uart_print_block("CFG ", "st1_")
    A("        andi  x24, x21, 4             # rstp")
    A("        slt   x24, x0, x24")
    A("        addi  x16, x24, 48            # '0' / '1'")
    L += _uart_put16_block("st2_")
    A("        andi  x24, x21, 2             # swap")
    A("        slt   x24, x0, x24")
    A("        addi  x16, x24, 48")
    L += _uart_put16_block("st3_")
    A("        andi  x24, x21, 1             # var")
    A("        slt   x24, x0, x24")
    A("        addi  x16, x24, 48")
    L += _uart_put16_block("st4_")
    L += _uart_print_block("\r\n", "st5_")
    # ---- 停 2s（= 5 个硬件定时器周期），再试下一种配置 ----
    for i in range(5):
        A("        addi  x12, x0, 1")
        A("        sw    x12, 580(x10)")
        A("st6_%d:" % i)
        A("        lw    x12, 584(x10)")
        A("        bne   x12, x0, st6_%d" % i)
    A("        addi  x21, x21, 1             # 下一种组合")
    A("        andi  x21, x21, 7")
    A("        jal   x0, lcdtest_cfg")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"



if __name__ == '__main__':
    draw = build_draw_stream()
    dmem = build_dmem(draw)
    print('init 条目 %d 条, 图案条目 %d 条, DMEM 共 %d 字' %
          (len(LCD_INIT), len(draw), len(dmem)))
    print('前 4 条图案条目:', draw[:4])
    tmem = build_test_dmem()
    print('自检程序的 DMEM 共 %d 字（CFG 表 %d 字）' % (len(tmem), CFG_TAB_WORDS))
    # ASCII 预览：把期望帧缓存打出来，肉眼确认字模/排版正确
    fb = build_fb_words()
    print('---- 期望显示效果（%d 列 × %d 行）----' % (128, 128))
    blank = True
    for row in range(128):
        line = ''.join('#' if (fb[(row // 8) * 128 + c] >> (row % 8)) & 1
                       else '.' for c in range(128))
        if line.strip('.'):
            blank = False
        if not blank or row < 64:
            print(line)
    print('---- 非零像素 %d 个 ----' % sum(bin(b).count('1') for b in fb))

