# sort_demo.py - "五整数冒泡排序 + 8 位数码管实时显示" 演示程序生成器
#
# 目的：不依赖终端打印，用板载数码管把流水线 CPU 的排序过程**演**出来（可录视频）：
#   digit0..4 = a[0..4]（与 tb_CPU.v 里同一个冒泡排序、同一组数据 9,3,7,1,5）
#   digit5/6  = 累计交换次数（十位/个位）
#   digit7    = 空白
#   正在比较的两位用小节点亮（高亮），让"谁在和谁比、什么时候换了"一目了然
#
# 两个关键设计（都是为了"仿真能验、上板能看"）：
#   1) 每步之间的停顿用**硬件定时器**（PeriphMMIO 的 SimpleTimer），不是软件空循环：
#      延时长度是 RTL 参数，仿真是 64 拍、上板是 0.4s，**跑的是同一份机器码**。
#   2) 显示刷新完全由 RTL 扫描完成，CPU 只写"这一位显示什么"，不占 CPU 时间。
#
# 生成内容（由 gen_uart_demo.py sort 调用）：
#   Lab2.file/seg_sort.hex         程序机器码
#   Lab2.file/seg_sort_mem.hex     数据区初值（5 个数 + n=5，与 mem_clean.hex 相同）
#   Lab2.file/seg_trace_val.hex    期望显示轨迹（每一步的 8 位数字值，每行 1 字）
#   Lab2.file/seg_trace_mrk.hex    期望显示轨迹（每一步的小数点/高亮位，每行 1 字）
#   Lab2.file/seg_trace_len.hex    期望轨迹长度（1 字）
import asm

# 待排序的 5 个一位数（与 tb_CPU.v / inst_code_clean.hex 用的数据一致）
INIT = [9, 3, 7, 1, 5]
N    = 5

# 数码管寄存器相对 MMIO 基址(0x1000_0000)的字节偏移
OFF_SEG_BASE  = 512    # 0x1000_0200 + 4*i
OFF_TIMER_CTL = 580    # 0x1000_0244
OFF_TIMER_VAL = 584    # 0x1000_0248
OFF_DMEM      = 0      # x11 指向 0x1001_0000，a[0] 在 0，n 在 20

BLANK = 0xF            # 空白码
MARK  = 0x10           # 高亮位（点亮该位小数点的 bit4）


def delay_blocks(n, prefix):
    """生成 n 段“启动硬件定时器并轮询”的代码（标签唯一）"""
    out = []
    for i in range(n):
        lbl = "dl_%s%d" % (prefix, i)
        out.append("        addi  x12, x0, 1")
        out.append("        sw    x12, %d(x10)" % OFF_TIMER_CTL)
        out.append("%s:" % lbl)
        out.append("        lw    x12, %d(x10)" % OFF_TIMER_VAL)
        out.append("        bne   x12, x0, %s" % lbl)
    return out


def build_program():
    """生成汇编程序（只用到已有的 18 条指令子集）"""
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # 数码管演示：五整数冒泡排序实时显示（由 sort_demo.py 生成，勿手改）")
    A("        #   数据/算法与 tb_CPU.v 的流水线测试程序相同：9,3,7,1,5 → 1,3,5,7,9")
    A("        #   寄存器分工：")
    A("        #     x10=MMIO基址 x11=数据区基址 x5=轮次i x6=n-1 x8=j x9=j上界")
    A("        #     x7=&a[j] x20=第j位数码管指针 x28=a[j] x29=a[j+1]")
    A("        #     x14/x15=交换次数个位/十位 x16=带高亮的值 x12,x13=临时")
    A("        # ============================================================")
    A("start_top:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    A("        auipc x11, 0x0fc10")
    A("        addi  x11, x11, -8            # x11 = 0x10010000 (DMEM)")
    for i, v in enumerate(INIT):
        A("        addi  x12, x0, %d" % v)
        A("        sw    x12, %d(x11)           # a[%d] = %d" % (OFF_DMEM + 4 * i, i, v))
        A("        sw    x12, %d(x10)           # digit%d" % (OFF_SEG_BASE + 4 * i, i))
    A("        addi  x14, x0, 0              # 交换次数 个位")
    A("        addi  x15, x0, 0              # 交换次数 十位")
    A("        sw    x15, %d(x10)           # digit5 = 十位" % (OFF_SEG_BASE + 20))
    A("        sw    x14, %d(x10)           # digit6 = 个位" % (OFF_SEG_BASE + 24))
    A("        addi  x12, x0, %d             # 0xF = 空白" % BLANK)
    A("        sw    x12, %d(x10)           # digit7 = 空白" % (OFF_SEG_BASE + 28))
    L += delay_blocks(1, "init")
    A("        lw    x6, %d(x11)            # x6 = n (mem[5] = 5)" % (OFF_DMEM + 20))
    A("        addi  x6, x6, -1              # x6 = n-1 = 4")
    A("        addi  x5, x0, 0               # i = 0")
    A("outer:")
    A("        sub   x9, x6, x5              # x9 = (n-1)-i = j 的上界(不含)")
    A("        addi  x12, x0, 1")
    A("        blt   x9, x12, sort_end       # 上界 < 1 → 排序结束")
    A("        addi  x8, x0, 0               # j = 0")
    A("        add   x7, x11, x0             # x7 = &a[0]")
    A("        addi  x20, x10, %d            # x20 = &digit[0]" % OFF_SEG_BASE)
    A("inner:")
    A("        bge   x8, x9, next_pass       # j 到上界 → 本轮结束")
    A("        lw    x28, 0(x7)              # x28 = a[j]")
    A("        lw    x29, 4(x7)              # x29 = a[j+1]")
    A("        ori   x16, x28, %d            # 高亮：值 + 点亮小数点" % MARK)
    A("        sw    x16, 0(x20)             # digit j")
    A("        ori   x16, x29, %d" % MARK)
    A("        sw    x16, 4(x20)             # digit j+1")
    L += delay_blocks(1, "hl")
    A("        slt   x12, x29, x28           # a[j+1] < a[j] ?")
    A("        beq   x12, x0, no_swap")
    A("        sw    x29, 0(x7)              # 交换：a[j] = a[j+1]")
    A("        sw    x28, 4(x7)              #       a[j+1] = a[j]")
    A("        ori   x16, x29, %d" % MARK)
    A("        sw    x16, 0(x20)             # 显示新值（此时仍高亮）")
    A("        ori   x16, x28, %d" % MARK)
    A("        sw    x16, 4(x20)")
    A("        addi  x14, x14, 1             # 交换次数++（十进制进位）")
    A("        addi  x13, x0, 10")
    A("        blt   x14, x13, cnt_ok")
    A("        addi  x14, x0, 0")
    A("        addi  x15, x15, 1")
    A("cnt_ok:")
    A("        sw    x15, %d(x10)           # digit5 = 十位" % (OFF_SEG_BASE + 20))
    A("        sw    x14, %d(x10)           # digit6 = 个位" % (OFF_SEG_BASE + 24))
    A("no_swap:")
    A("        lw    x28, 0(x7)              # 取消高亮：写回当前值")
    A("        sw    x28, 0(x20)")
    A("        lw    x29, 4(x7)")
    A("        sw    x29, 4(x20)")
    L += delay_blocks(1, "post")
    A("        addi  x8, x8, 1               # j++")
    A("        addi  x7, x7, 4")
    A("        addi  x20, x20, 4")
    A("        jal   x0, inner")
    A("next_pass:")
    A("        addi  x5, x5, 1               # i++")
    A("        jal   x0, outer")
    A("sort_end:")
    L += delay_blocks(3, "end")            # 结果多停一会儿
    A("        jal   x0, start_top           # 再来一轮（方便录视频）")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"



def build_dmem():
    """数据区初值：5 个数 + n（与 mem_clean.hex 一致）"""
    return list(INIT) + [N]


def build_trace():
    """期望的显示轨迹：与程序写入顺序一一对应，只保留“能稳定看到”的状态。

    程序每步都会先启动硬件定时器再轮询，所以每个状态至少稳定一个延时周期；
    连续 sw 造成的瞬态（短于一个刷新周期）在 tb 里会被过滤掉，这里不列。
    返回 [(values_word, marks_word), ...]
    """
    a = list(INIT)
    nsw = 0
    trace = []

    def values_word():
        w = 0
        for i in range(5):
            w |= (a[i] & 0xF) << (4 * i)
        w |= ((nsw // 10) & 0xF) << 20      # digit5 = 十位
        w |= ((nsw % 10) & 0xF) << 24       # digit6 = 个位
        w |= BLANK << 28                    # digit7 = 空白
        return w

    def snap(marks):
        m = 0
        for d in marks:
            m |= (1 << d)
        trace.append((values_word(), m))

    snap([])                                    # 初始（乱序）
    for i in range(N - 1):                      # 轮次 i = 0..3
        for j in range((N - 1) - i):            # j = 0..(3-i)
            snap([j, j + 1])                    # 高亮 (j, j+1)
            if a[j] > a[j + 1]:
                a[j], a[j + 1] = a[j + 1], a[j]  # 交换
                nsw += 1
            snap([])                            # 取消高亮（交换已生效）
    return trace


HEXD = "0123456789ABCDEF"


def fmt_state(vals, marks):
    """把 (values_word, marks_word) 排版成一行好读的文本（打印“文字动画”用）"""
    cells = []
    for i in range(5):
        mk = "*" if (marks >> i) & 1 else " "
        cells.append("%s%s%s" % (mk, HEXD[(vals >> (4 * i)) & 0xF], mk))
    cnt = "".join(HEXD[(vals >> (4 * i)) & 0xF] for i in (5, 6))
    return "[ %s ]   交换次数 = %s" % (" ".join(cells), cnt)


if __name__ == '__main__':
    prog = build_program()
    words = asm.assemble(asm.parse(prog.splitlines()))
    tr = build_trace()
    print("程序长度 = %d 条指令" % len(words))
    print("DMEM 初值 = %s" % build_dmem())
    print("期望显示轨迹 %d 步（* 表示该位数码管被高亮）:" % len(tr))
    for k, (v, m) in enumerate(tr):
        print("  %2d  %s" % (k, fmt_state(v, m)))

