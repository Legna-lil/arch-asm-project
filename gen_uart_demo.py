# gen_uart_demo.py
# 生成 UART 演示程序 / 数据 hex，以及综合阶段(bitstream)用的字面量初始化文件。
#
# 用法:
#   python gen_uart_demo.py hello       # 默认: 上电打印 "Hello, EES-338!" (同步刷新 imem/dmem init)
#   python gen_uart_demo.py helloecho   # 自检: 先打印 Hello, 再回显 PC 发来的字节 (TX+RX 全测)
#   python gen_uart_demo.py echo        # 生成: PC 发字符原样回显 (同步刷新 imem/dmem init)
#   python gen_uart_demo.py bt          # 生成: 蓝牙(BLE-CC41-A/9600)回显程序
#   python gen_uart_demo.py lcd         # 生成: LCD(JLX128128G-81202)演示程序 + 图案数据表
#   python gen_uart_demo.py sort        # 生成: 数码管演示程序(五整数排序实时显示) + 期望显示轨迹
#
# 生成内容:
#   Lab2.file/uart_hello.hex      程序机器码
#   Lab2.file/uart_hello_mem.hex  字符串数据(每字一个字符)
#   Lab2.file/uart_echo.hex       回显程序机器码
#   Lab2.file/uart_echo_mem.hex   回显数据(空)
#   Lab2.file/bt_echo.hex         蓝牙回显程序机器码 (bt 模式)
#   Lab2.file/lcd_demo.hex        LCD 演示程序机器码 (lcd 模式)
#   Lab2.file/lcd_demo_mem.hex    LCD 初始化命令表 + 字符图案数据表 (lcd 模式)
#   Lab2.file/seg_sort.hex        数码管演示程序机器码 (sort 模式)
#   Lab2.file/seg_sort_mem.hex    数码管演示程序的数据区初值 (sort 模式)
#   sources_1/new/imem_boot_init.vh  综合阶段 InstructionMemory 的字面量初始化
#   sources_1/new/dmem_boot_init.vh  综合阶段 DataMemory 的字面量初始化
#        (说明: InstructionMemory.v / DataMemory.v 在 `ifdef SYNTHESIS 下
#         会 include 这两个文件，保证程序/数据被烘焙进 bitstream)
#   注意: imem_boot_init.vh / dmem_boot_init.vh 每次都会被"当前模式"覆盖，
#         所以出 bitstream 前最后一次运行必须是想要的那个模式！
import asm
import os
import sys

FILE_DIR = r'e:\VivadoProject\Lab2\Lab2.file'
SRC_DIR  = r'e:\VivadoProject\Lab2\Lab2.srcs\sources_1\new'

HELLO_MSG = "Hello, EES-338!\r\n"

PROG_HELLO = '''
        # UART 演示：周期打印 "Hello, EES-338!"（约 0.3s 一次）
        # 用重复发送解决“上电/复位瞬间串口只收到半截”的丢开头问题
        auipc x10, 0x0fc00     # x10 = 0x10000000 (UART_BASE)
        addi  x10, x10, 0
        auipc x11, 0x0fc10     # pc(0x00400008)+0x0fc10000 = 0x10010008
        addi  x11, x11, -8     # => 0x10010000 (DMEM_BASE)
        addi  x12, x0, 0       # 字符串字偏移
print_loop:
        add   x13, x11, x12
        lw    x14, 0(x13)      # 取一个字符
        beq   x14, x0, delay_start
wait_tx1:
        lw    x15, 4(x10)
        andi  x16, x15, 1
        bne   x16, x0, wait_tx1
        sw    x14, 0(x10)
        addi  x12, x12, 4
        jal   x0, print_loop
delay_start:
        addi  x17, x0, 0
        addi  x20, x0, 0
delay_inner:
        addi  x17, x17, 1
        addi  x19, x0, 2047
        blt   x17, x19, delay_inner
        addi  x17, x0, 0
        addi  x20, x20, 1
        addi  x19, x0, 2000
        blt   x20, x19, delay_inner
        addi  x12, x0, 0       # 重新打印
        addi  x20, x0, 0
        jal   x0, print_loop
'''

PROG_ECHO = '''
        # UART 回显：PC 每发一个字节，CPU 读回后原样回发
        auipc x10, 0x0fc00     # x10 = 0x10000000 (UART_BASE)
        addi  x10, x10, 0
poll_rx:
        lw    x11, 4(x10)      # 读 UART_STATUS
        andi  x12, x11, 2      # bit1 = RX_READY?
        beq   x12, x0, poll_rx # 无数据继续轮询
        lw    x13, 0(x10)      # 读 UART_DATA（硬件同时清除 RX_READY）
wait_tx:
        lw    x14, 4(x10)      # 读 UART_STATUS
        andi  x15, x14, 1      # bit0 = TX_BUSY?
        bne   x15, x0, wait_tx # 忙则等待
        sw    x13, 0(x10)      # 回发该字节
        jal   x0, poll_rx
'''

PROG_BT_ECHO = '''
        # 蓝牙回显：手机/PC 通过 BLE-CC41-A 每发一个字节，CPU 读回后原样回发
        # 与 UART 回显逻辑相同，只把地址换成蓝牙寄存器：
        #   0x1000_0010 BT_DATA（sw 发送 / lw 读取）
        #   0x1000_0014 BT_STATUS（bit0 TX_BUSY, bit1 RX_READY）
        # 注意：还要先把蓝牙模块**上电并复位**（0x1000_0018 BT_CTRL，见官方 lab08）
        auipc x10, 0x0fc00     # x10 = 0x10000000 (MMIO 基址)
        addi  x10, x10, 0
        addi  x16, x0, 27      # BT_CTRL=0x1B：上电 + 从模式 + 释放复位（其余位见文档 §4.7）
        sw    x16, 24(x10)
poll_rx:
        lw    x11, 20(x10)     # 读 BT_STATUS (0x1000_0014)
        andi  x12, x11, 2      # bit1 = RX_READY?
        beq   x12, x0, poll_rx # 无数据继续轮询
        lw    x13, 16(x10)     # 读 BT_DATA (0x1000_0010)，同时清 RX_READY
wait_tx:
        lw    x14, 20(x10)     # 读 BT_STATUS
        andi  x15, x14, 1      # bit0 = TX_BUSY?
        bne   x15, x0, wait_tx # 忙则等待
        sw    x13, 16(x10)     # 原样回发
        jal   x0, poll_rx
'''

PROG_HELLO_ECHO = '''
        # 自检/日常演示程序：
        #   1) 周期打印 "Hello, EES-338!"（约 0.8s 一次，重复发送避免漏开头）；
        #   2) 任何时刻收到 PC 字节立即原样回显（回显优先，不因打印而丢）。
        # 寄存器分工：
        #   x10=UART基址 x11=字符串基址 x12=发送字偏移(-1=处于间隔期)
        #   x17=间隔内计 inner  x20=间隔内计 outer
        #   x18=待回显字节(0=无)
        auipc x10, 0x0fc00
        addi  x10, x10, 0
        auipc x11, 0x0fc10
        addi  x11, x11, -8
        addi  x12, x0, 0          # 先打印一次
        addi  x18, x0, 0
        addi  x17, x0, 0
        addi  x20, x0, 0
        addi  x21, x0, 0
main:
        # ---- 1) 回显捕获：RX 可读就读进 x18（新字节覆盖旧待回显） ----
        lw    x14, 4(x10)
        andi  x15, x14, 2
        beq   x15, x0, do_send
        lw    x18, 0(x10)
do_send:
        # ---- 2) 有待回显字节且 TX 空闲 -> 先回显 ----
        beq   x18, x0, do_msg
        lw    x14, 4(x10)
        andi  x15, x14, 1
        bne   x15, x0, main       # TX 忙则下轮再发（保留 x18）
        sw    x18, 0(x10)
        addi  x18, x0, 0
        jal   x0, main
do_msg:
        # ---- 3) 处于打印期：逐个发送字符串字符 ----
        blt   x12, x0, do_delay   # x12=-1 表示处于打印间隔
        add   x13, x11, x12
        lw    x16, 0(x13)
        beq   x16, x0, msg_over
        lw    x14, 4(x10)
        andi  x15, x14, 1
        bne   x15, x0, main       # TX 忙则稍后再发本字符
        sw    x16, 0(x10)
        addi  x12, x12, 4
        jal   x0, main
msg_over:
        addi  x12, x0, -1         # 打印完成 -> 进入间隔期
        addi  x17, x0, 0
        addi  x20, x0, 0
        jal   x0, main
do_delay:
        # ---- 4) 间隔期计数（约 2s 重发一次；每轮主循环都经过回显捕获） ----
        addi  x17, x17, 1
        addi  x19, x0, 2047
        blt   x17, x19, main
        addi  x17, x0, 0
        addi  x20, x20, 1
        addi  x19, x0, 2047
        blt   x20, x19, main
        addi  x20, x0, 0
        addi  x21, x21, 1
        addi  x19, x0, 6
        blt   x21, x19, main
        addi  x21, x0, 0
        addi  x12, x0, 0          # 间隔结束 -> 重新打印
        jal   x0, main
'''


def words_of(prog_text):
    items = asm.parse(prog_text.splitlines())
    return asm.assemble(items)


def write_hex(path, words):
    with open(path, 'w') as f:
        for w in words:
            f.write('%08x\n' % w)


def char_words(msg):
    # 每字存一个字符(低 8 位)，以 0 结尾
    words = [ord(c) for c in msg] + [0]
    return words


def write_init_vh(path, words, memname='mem'):
    with open(path, 'w') as f:
        f.write('// AUTO-GENERATED by gen_uart_demo.py - DO NOT EDIT\n')
        f.write('// Literal init for InstructionMemory/DataMemory under `ifdef SYNTHESIS\n')
        for i, w in enumerate(words):
            f.write('        %s[%d] = 32\'h%08X;\n' % (memname, i, w))


def build_btcheck_program():
    """蓝牙自检程序：周期性在蓝牙口发 'K'，把蓝牙收到的字节经 USB-UART 打印出来。
      · 上板做法1（硬件环回冷测）：用跳线/镊子短接 N2 与 L3 → 串口应每 ~0.4s 出现 "RX=K"
        → 证明 FPGA 侧蓝牙收发通道与引脚方向都对（和模组、手机无关）。
      · 做法2（真机）：手机 BLE 助手连上模组后发什么字符 → 串口显示 "RX=<字符>"。
    """
    from lcd_demo import _uart_print_block, _uart_put16_block
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # 蓝牙自检（由 gen_uart_demo.py btcheck 生成，勿手改）")
    A("        #   每 0.4s 在蓝牙口发一个 'K'；收到蓝牙字节就用 USB-UART 打印 RX=<字符>")
    A("        #   N2↔L3 短接时应看到 RX=K 反复出现（硬件环回自检）")
    A("        # ============================================================")
    A("bt_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    L += _bt_power_on_block("btp_")        # 先给模块上电 + 复位（官方 lab08 的 SW2 动作）
    L += _uart_print_block("BT SELF-TEST\r\n", "bt0_")
    A("bt_period:")
    A("        addi  x12, x0, 1")
    A("        sw    x12, 580(x10)           # 启动一个硬件延时周期（0.4s）")
    A("bt_main:")
    A("        lw    x11, 20(x10)            # BT_STATUS (0x1000_0014)")
    A("        andi  x12, x11, 2             # RX_READY?")
    A("        beq   x12, x0, bt_chk_tx")
    A("        lw    x17, 16(x10)            # 读走收到的字节 (0x1000_0010)")
    L += _uart_print_block("RX=", "bt1_")
    A("        add   x16, x17, x0            # 把收到的字符放到 x16")
    L += _uart_put16_block("bt9_")
    L += _uart_print_block("\r\n", "bt2_")
    A("bt_chk_tx:")
    A("        lw    x12, 584(x10)           # TIMER_VALUE")
    A("        bne   x12, x0, bt_main        # 周期未到 → 继续轮询接收")
    A("        lw    x11, 20(x10)            # 周期到了：发一个 'K'")
    A("        andi  x12, x11, 1             # TX_BUSY?")
    A("        bne   x12, x0, bt_main")
    A("        addi  x14, x0, 75             # 'K'")
    A("        sw    x14, 16(x10)            # 送到蓝牙发送器")
    A("        jal   x0, bt_period")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def _seg_bit_code(bit_idx, src_reg, prefix="x21"):
    """生成"取出 src_reg 的第 bit_idx 位（用 slli+slt 落地到 0/1）"的内联代码。
    本 ISA 只有 slli/andi，没有 srl/sra，所以取任意位用"左移到位 31 + 与 0 比较"：
        slli t, src, (31-bit)   ; t 的符号位 = src 的第 bit 位
        slt  t, t, x0           ; t<0 => 该位是 1"""
    return [
        "        slli  %s, %s, %d          # 取第 %d 位" % (prefix, src_reg, 31 - bit_idx, bit_idx),
        "        slt   %s, %s, x0" % (prefix, prefix),
    ]


def _flags_show_block():
    """把标志寄存器（rdflags）与 MMIO 的溢出计数显示到 8 位数码管。
    约定（从左到右）：SF ZF CF OF STK PF SEEN CNT
      · CNT 显示"溢出累计次数的奇偶"（1 = 溢出过奇数次）
      · STK 那一位的小数点同时点亮 => 溢出过就非常醒目"""
    out = []
    out.append("        rdflags x20                  # 读标志寄存器 (custom-0)")
    out.append("        lw    x22, 772(x10)          # MMIO OF_COUNT (0x1000_0304)")
    for i in range(8):
        if i == 7:
            out.append("        andi  x21, x22, 1            # CNT 奇偶")
        else:
            out += _seg_bit_code(i, "x20")
        if i == 4:
            out.append("        slli  x23, x21, 4            # 粘滞位同时点亮小数点")
            out.append("        or    x21, x21, x23")
        out.append("        sw    x21, %d(x10)           # dig%d" % (512 + 4 * i, i))
    return out


def build_flags_demo_program():
    """溢出标志位上板演示程序（8 位数码管直观显示标志寄存器）。
    循环 5 个场景：
      ① 0x80000000 + 0xFFFFFFFF  -> 溢出、进位
      ② 0x7FFFFFFF + 0          -> 不溢出（但粘滞位保持）
      ③ 0 - 5                   -> SF=1、借位 CF=1
      ④ INT_MIN × INT_MIN       -> ZF=1、OF=1、PF=1
      ⑤ clrflags                -> 全灭（演示"清除标志"）
    """
    from lcd_demo import _uart_print_block
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # 溢出标志位演示（由 gen_uart_demo.py flags 生成，勿手改）")
    A("        #   8 位数码管从左到右：SF ZF CF OF STK PF SEEN CNT(奇偶)")
    A("        #   STK 位的小数点点亮 = 曾经溢出过（粘滞位）")
    A("        #   场景顺序：①溢出加法 ②不溢出加法 ③减出负数(借位)")
    A("        #              ④乘法溢出 ⑤clrflags 清标志")
    A("        # ============================================================")
    A("flags_demo:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO 基址)")
    L += _uart_print_block("FLAGS DEMO\r\n", "fl0_")
    L += _uart_print_block("SEG:SF ZF CF OF STK PF SE CNT\r\n", "fl1_")
    A("        addi  x18, x0, 1              # 启动硬件延时用的固定值")

    A("flag_loop:")
    # ---- 场景 ①：负+负=正 -> OF=1, CF=1 ----
    A("        addi  x6, x0, 1")
    A("        slli  x6, x6, 31              # x6 = 0x80000000 (INT_MIN)")
    A("        addi  x7, x0, -1              # x7 = 0xFFFFFFFF (-1)")
    A("        add   x5, x6, x7              # 0x7FFFFFFF：OF=1、CF=1")
    L += _flags_show_block()
    A("        sw    x18, 580(x10)           # 启动 0.4s 硬件延时")
    A("flag_w1:")
    A("        lw    x19, 584(x10)")
    A("        bne   x19, x0, flag_w1")
    # ---- 场景 ②：不溢出（粘滞位应保持）----
    A("        add   x5, x5, x0              # 0x7FFFFFFF+0：OF=0，粘滞位不动")
    L += _flags_show_block()
    A("        sw    x18, 580(x10)")
    A("flag_w2:")
    A("        lw    x19, 584(x10)")
    A("        bne   x19, x0, flag_w2")
    # ---- 场景 ③：0 - 5 -> SF=1、借位 CF=1 ----
    A("        addi  x8, x0, 5")
    A("        sub   x9, x0, x8              # -5：SF=1、CF(借位)=1")
    L += _flags_show_block()
    A("        sw    x18, 580(x10)")
    A("flag_w3:")
    A("        lw    x19, 584(x10)")
    A("        bne   x19, x0, flag_w3")
    # ---- 场景 ④：INT_MIN × INT_MIN -> ZF=1、OF=1、PF=1 ----
    A("        mul   x11, x6, x6             # 低 32 位 = 0，溢出")
    L += _flags_show_block()
    A("        sw    x18, 580(x10)")
    A("flag_w4:")
    A("        lw    x19, 584(x10)")
    A("        bne   x19, x0, flag_w4")
    # ---- 场景 ⑤：clrflags -> 全灭 ----
    A("        clrflags")
    L += _flags_show_block()
    A("        sw    x18, 580(x10)")
    A("flag_w5:")
    A("        lw    x19, 584(x10)")
    A("        bne   x19, x0, flag_w5")
    A("        jal   x0, flag_loop")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def _bt_power_on_block(tag):
    """蓝牙模块上电/复位序列（官方 lab08 步骤 5：SW1 低、SW0/2/3/4 高，再用 SW2 复位一次）

    写 0x1000_0018 BT_CTRL（bit0 pw_on, bit1 master_slave, bit2 sw_hw, bit3 sw, bit4 rst_n）：
      先 0x0B（上电+从模式，rst_n=0 复位有效）→ 等一拍硬件延时
      → 再 0x1B（rst_n=1 释放复位）→ 等一拍硬件延时
    对应的就是官方"用 SW2 把蓝牙拉低再拉高"那一步。
    """
    return [
        "        addi  x16, x0, 11             # BT_CTRL=0x0B：上电+从模式，复位拉低",
        "        sw    x16, 24(x10)            # 0x1000_0018",
        "        addi  x12, x0, 1",
        "        sw    x12, 580(x10)           # 等一个硬件延时",
        "%s_r1:" % tag,
        "        lw    x12, 584(x10)           # TIMER_VALUE",
        "        bne   x12, x0, %s_r1" % tag,
        "        addi  x16, x0, 27             # BT_CTRL=0x1B：rst_n=1 释放复位",
        "        sw    x16, 24(x10)",
        "        addi  x12, x0, 1",
        "        sw    x12, 580(x10)",
        "%s_r2:" % tag,
        "        lw    x12, 584(x10)",
        "        bne   x12, x0, %s_r2" % tag,
    ]


def _bt_send_byte(ch, tag):
    """往蓝牙口(TX)发送一个字节（含 TX_BUSY 轮询）"""
    return [
        "        addi  x16, x0, %-4d          # %s" % (ord(ch), repr(ch)),
        "%s_w:" % tag,
        "        lw    x12, 20(x10)           # BT_STATUS",
        "        andi  x12, x12, 1            # TX_BUSY?",
        "        bne   x12, x0, %s_w" % tag,
        "        sw    x16, 16(x10)           # BT_DATA",
    ]


# AT 探针轮次表：(标签, 命令)
#  · btat  模式 → BTAT_ROUNDS_BASIC（3 轮）
#  · btat2 模式 → BTAT_ROUNDS_INFO（8 轮，把版本/名字/地址/角色/波特率都问出来）
#  实测（2026-09-17 上板）：本板模组**必须有行结束符**——裸 "AT" 无应答，`AT\r\n` 才回 `OK`；
#  而 `AT+NAME?` 回的是 `+NAME=?` + `OK`，说明它的 AT 集不是 HM-10 那种，需要逐条探测。
BTAT_ROUNDS_BASIC = (
    ("A: ", "AT"),
    ("B: ", "AT\r\n"),
    ("C: ", "AT+NAME?\r\n"),
)
BTAT_ROUNDS_INFO = (
    ("A: ", "AT\r\n"),           # 链路确认（期望 OK）
    ("B: ", "AT+VERSION?\r\n"),  # 固件版本（用来识别模块型号）
    ("C: ", "AT+NAME?\r\n"),     # 名字
    ("D: ", "AT+NAME\r\n"),      # 名字（无问号变体）
    ("E: ", "AT+ADDR?\r\n"),     # MAC 地址
    ("F: ", "AT+ROLE?\r\n"),     # 主/从角色
    ("G: ", "AT+BAUD?\r\n"),     # 波特率
    ("H: ", "AT+RESET\r\n"),     # 复位（让它重新开始广播）
)


def build_btat_program(rounds=None):
    """蓝牙 AT 探针：轮流往蓝牙口发 AT / AT\\r\\n / AT+NAME?\\r\\n，
    并把模组回过来的任何字节直接打印到 USB-UART。

    用途：把"模组在不在听、上电没有、引脚方向与波特率对不对"变成**看得见的回显**：
      · 出现 `OK` / `OK+NAME` / 其它回显 → FPGA↔模组 双向链路通，
        问题在模组的广播/手机扫描方式（与 FPGA 程序无关）；
      · 三个命令都毫无回显 → 模组没在听：未上电 / RX-TX 与手册相反 /
        波特率不是 9600 / 模组已坏。
    注意：用跳线短接 N2↔L3 时本程序也会把发出去的字节自己收回来（能看到回显），
          所以做"环回自检"和做"AT 探针"要分开看：**不接跳线才有模组回显的含义**。
    """
    from lcd_demo import _uart_print_block, _uart_put16_block
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # 蓝牙 AT 探针（由 gen_uart_demo.py btat 生成，勿手改）")
    A("        #   轮回：A: 发 AT      B: 发 AT\\r\\n    C: 发 AT+NAME?\\r\\n")
    A("        #   每个命令后开 0.4s 接收窗口，把模组回的字节直接打到 USB-UART")
    A("        # ============================================================")
    if rounds is None:                     # btat 用 3 轮；btat2 传 8 轮
        rounds = BTAT_ROUNDS_BASIC
    A("btat_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    L += _bt_power_on_block("bap_")        # 先给模块上电 + 复位（官方 lab08 的 SW2 动作）
    L += _uart_print_block("BT AT PROBE\r\n", "ba0_")

    for idx, (label, cmd) in enumerate(rounds):
        tag = "bb%d" % (idx + 1)
        L += _uart_print_block(label, tag + "l_")
        for i, ch in enumerate(cmd):
            L += _bt_send_byte(ch, "%s%d" % (tag, i))
        # 开 0.4s 接收窗口
        A("        addi  x12, x0, 1")
        A("        sw    x12, 580(x10)           # TIMER_CTRL（0.4s 窗口）")
        A("%s_rx:" % tag)
        A("        lw    x11, 20(x10)            # BT_STATUS")
        A("        andi  x12, x11, 2             # bit1 = RX_READY?")
        A("        beq   x12, x0, %s_tm" % tag)
        A("        lw    x17, 16(x10)            # 读走一个字节（清 ready）")
        A("        add   x16, x17, x0            # 把收到的字符打到 USB-UART")
        L += _uart_put16_block(tag + "p_")
        A("        jal   x0, %s_rx" % tag)
        A("%s_tm:" % tag)
        A("        lw    x12, 584(x10)           # TIMER_VALUE")
        A("        bne   x12, x0, %s_rx" % tag)
        L += _uart_print_block("\r\n", tag + "e_")

    A("        jal   x0, btat_start")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def _hw_delay_loop(tag, units=25):
    """等 units 个硬件定时器周期（用循环实现，避免展开成几百条指令）

    上板 0.4s/单位（默认 25 单位 ≈ 10s，留给手机端试连接）；仿真 64 拍/单位。
    """
    return [
        "        addi  x25, x0, %d          # 等 %d × 硬件延时" % (units, units),
        "%s_l:" % tag,
        "        addi  x12, x0, 1",
        "        sw    x12, 580(x10)           # TIMER_CTRL",
        "%s_w:" % tag,
        "        lw    x12, 584(x10)           # TIMER_VALUE",
        "        bne   x12, x0, %s_w" % tag,
        "        addi  x25, x25, -1",
        "        bne   x25, x0, %s_l" % tag,
    ]


def build_btcfg_program():
    """蓝牙**模式脚扫描**：把 BT_CTRL 的 3 个模式位（bit1 主/从、bit2 sw_hw、bit3 sw）
    组合成 8 种，每种都"先复位、再按该组合释放"，然后停 ~10s 让手机端试连接。

    背景：实测该模组只认极少 AT 命令（`AT`/`AT+RESET` → `OK`，`AT+ROLE?`/`AT+BAUD?` → `ERR`），
    说明"能不能被连接"是**硬件模式脚**决定的，于是逐个组合试。

    串口打印形如：`T3 m=1 h=0 s=1` —— **哪一行在的时候 nRF Connect 能连上（模组 LED2 常亮），
    就把那一行发我**，我把这组值固化进正常演示程序。
    """
    from lcd_demo import _uart_print_block, _uart_put16_block, _hw_delay
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # 蓝牙模式脚扫描（由 gen_uart_demo.py btcfg 生成，勿手改）")
    A("        #   BT_CTRL = 0x11 | (m<<1) | (h<<2) | (s<<3)")
    A("        #     m = bit1 bt_master_slave（1=从，官方 lab08：SW0 高）")
    A("        #     h = bit2 bt_sw_hw       （官方：SW1 低）")
    A("        #     s = bit3 bt_sw          （官方：SW3 高）")
    A("        #   每种组合：先复位 → 按该组合释放 → 停 ~10s 让手机试连接")
    A("        # ============================================================")
    A("btcfg_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    L += _uart_print_block("BT CFG SWEEP\r\n", "cf0_")
    A("        addi  x21, x0, 0              # 组合号 k = 0..7")

    A("btcfg_loop:")
    A("        addi  x19, x0, 8")
    A("        bge   x21, x19, btcfg_wrap")
    # ---- 由 k 算出 BT_CTRL ----
    A("        andi  x22, x21, 7             # k 的低 3 位 → 模式位")
    A("        slli  x22, x22, 1             # 移到 bit1..bit3")
    A("        ori   x22, x22, 17            # 0x11：pw_on=1、rst_n=1")
    A("        andi  x23, x22, 239           # 0xEF：清 bit4 → rst_n=0（复位有效）")
    A("        sw    x23, 24(x10)            # 先复位")
    L += _hw_delay("cfgd_", 1)
    A("        sw    x22, 24(x10)            # 释放复位 + 本组合模式位")
    # ---- 打印 "T<k> m=<m> h=<h> s=<s>" ----
    L += _uart_print_block("T", "cf1_")
    A("        addi  x16, x21, 48            # '0'+k")
    L += _uart_put16_block("cf2_")
    L += _uart_print_block(" m", "cf3_")
    A("        andi  x24, x21, 1             # m = bit0")
    A("        addi  x16, x24, 48")
    L += _uart_put16_block("cf4_")
    L += _uart_print_block(" h", "cf5_")
    A("        andi  x24, x21, 2             # h = bit1")
    A("        slt   x24, x0, x24")
    A("        addi  x16, x24, 48")
    L += _uart_put16_block("cf6_")
    L += _uart_print_block(" s", "cf7_")
    A("        andi  x24, x21, 4             # s = bit2")
    A("        slt   x24, x0, x24")
    A("        addi  x16, x24, 48")
    L += _uart_put16_block("cf8_")
    L += _uart_print_block("\r\n", "cf9_")
    # ---- 停 ~10s（25 × 0.4s）让手机端试连接 ----
    L += _hw_delay_loop("cfw_", 25)
    A("        addi  x21, x21, 1")
    A("        jal   x0, btcfg_loop")
    A("btcfg_wrap:")
    A("        addi  x21, x0, 0")
    A("        jal   x0, btcfg_loop")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def _nibble_to_dig(reg, lo, dig_idx, mark=False):
    """把寄存器 reg 的第 lo..lo+3 位（一个十六进制位）算成 0..15，
    写到数码管第 dig_idx 位；mark=True 时同时点亮该位的小数点。

    本 ISA 没有右移指令，所以"取某一位"用 slli 左移到位 31 + slt 与 0 比较，
    再把 4 个位按 1/2/4/8 加权相加得到十六进制值。"""
    L = []
    L.append("        addi  x27, x0, 0")
    for i in range(4):
        bit = lo + i
        L.append("        slli  x28, %s, %d          # 取第 %d 位" % (reg, 31 - bit, bit))
        L.append("        slt   x29, x28, x0")
        if i != 0:
            L.append("        slli  x29, x29, %d" % i)
        L.append("        add   x27, x27, x29")
    if mark:
        L.append("        ori   x27, x27, 16         # 小数点 = 最新收到的字节")
    L.append("        sw    x27, %d(x10)          # dig%d" % (512 + 4 * dig_idx, dig_idx))
    return L


def build_btseg_program():
    """蓝牙 → 8 位数码管：手机发来的字节以**十六进制滚动显示**在数码管上。

    显示格式（从左到右）：`b3 b2 b1 b0`，每个字节 2 位十六进制，
    **最新收到的那个字节在最右边两位，并把小数点一起点亮**便于辨认。
    收到后还会**原样回发给手机**（手机上立刻能看到自己发的字符回来了）。

    ★ 关键：本程序**全程不发任何 AT 命令**——
      实测该模组处于 AT 命令交互状态时会拒绝手机的连接（见文档 §4.8），
      所以只写 `BT_CTRL = 0x1B`（上电 + 从模式 + 释放复位）就去轮询数据。
    """
    from lcd_demo import _uart_print_block, _uart_put16_block
    L = []
    A = L.append
    A("        # ============================================================")
    A("        # 蓝牙→数码管（由 gen_uart_demo.py btseg 生成，勿手改）")
    A("        #   手机发一个字节：数码管按 16 进制滚动显示最近 4 个字节")
    A("        #   （最右两位 = 最新字节，小数点同时点亮），并原样回发给手机")
    A("        #   寄存器：x10=MMIO  x17=新字节  x20..x23=最近 4 个字节")
    A("        # ============================================================")
    A("btseg_start:")
    A("        auipc x10, 0x0fc00")
    A("        addi  x10, x10, 0             # x10 = 0x10000000 (MMIO)")
    A("        addi  x16, x0, 27             # BT_CTRL=0x1B：上电+从模式+释放复位")
    A("        sw    x16, 24(x10)            # ★ 只写控制脚，绝不发 AT 命令")
    L += _uart_print_block("BT SEG DEMO\r\n", "bs0_")
    # 清屏：8 位数码管全显示 0
    A("        addi  x16, x0, 0")
    for i in range(8):
        A("        sw    x16, %d(x10)          # dig%d = 0" % (512 + 4 * i, i))
    # 历史字节清零
    A("        addi  x20, x0, 0              # b0 = 最新字节")
    A("        addi  x21, x0, 0              # b1")
    A("        addi  x22, x0, 0              # b2")
    A("        addi  x23, x0, 0              # b3 = 最旧")
    # ---- 主循环：轮询蓝牙接收 ----
    A("btseg_main:")
    A("        lw    x11, 20(x10)            # BT_STATUS")
    A("        andi  x12, x11, 2             # bit1 = RX_READY?")
    A("        beq   x12, x0, btseg_main")
    A("        lw    x17, 16(x10)            # 读走新字节（同时清 ready）")
    # 滚动历史
    A("        add   x23, x22, x0            # b3 = b2")
    A("        add   x22, x21, x0            # b2 = b1")
    A("        add   x21, x20, x0            # b1 = b0")
    A("        add   x20, x17, x0            # b0 = 新字节")
    # 显示 4 个字节（十六进制）
    L += _nibble_to_dig("x23", 4, 0)
    L += _nibble_to_dig("x23", 0, 1)
    L += _nibble_to_dig("x22", 4, 2)
    L += _nibble_to_dig("x22", 0, 3)
    L += _nibble_to_dig("x21", 4, 4)
    L += _nibble_to_dig("x21", 0, 5)
    L += _nibble_to_dig("x20", 4, 6, mark=True)
    L += _nibble_to_dig("x20", 0, 7, mark=True)
    # 原样回发给手机
    A("        add   x16, x17, x0")
    A("btseg_tx:")
    A("        lw    x12, 20(x10)            # BT_STATUS")
    A("        andi  x12, x12, 1             # TX_BUSY?")
    A("        bne   x12, x0, btseg_tx")
    A("        sw    x16, 16(x10)            # 回发该字节")
    # 串口日志：RX=<字符>
    L += _uart_print_block("RX=", "bs1_")
    A("        add   x16, x17, x0")
    L += _uart_put16_block("bs2_")
    L += _uart_print_block("\r\n", "bs3_")
    A("        jal   x0, btseg_main")
    A("        addi  x0, x0, 0")
    return "\n".join(L) + "\n"


def main():
    mode = (sys.argv[1] if len(sys.argv) > 1 else 'hello').lower()
    if mode in ('hello', 'helloecho'):
        prog  = PROG_HELLO if mode == 'hello' else PROG_HELLO_ECHO
        words = words_of(prog)
        hexn  = 'uart_hello.hex' if mode == 'hello' else 'uart_helloecho.hex'
        memn  = 'uart_hello_mem.hex'
        cw    = char_words(HELLO_MSG)
    elif mode == 'echo':
        prog  = PROG_ECHO
        words = words_of(prog)
        hexn  = 'uart_echo.hex'
        memn  = 'uart_echo_mem.hex'
        cw    = []                     # 回显不需要数据区
    elif mode == 'bt':
        # 蓝牙回显（BLE-CC41-A，默认 9600）：手机 BLE 串口助手发什么回什么
        prog  = PROG_BT_ECHO
        words = words_of(prog)
        hexn  = 'bt_echo.hex'
        memn  = 'bt_echo_mem.hex'
        cw    = []                     # 回显不需要数据区
    elif mode == 'lcd':
        # LCD 演示（JLX128128G-81202 / ST7571）：初始化 -> 清屏 -> 显示图案 -> 串口回执
        # 显示内容/初始化命令都在 lcd_demo.py 里，改完重跑本脚本即可（不用动 Verilog）
        import lcd_demo
        prog  = lcd_demo.build_program()
        words = words_of(prog)
        hexn  = 'lcd_demo.hex'
        memn  = 'lcd_demo_mem.hex'
        cw    = lcd_demo.build_dmem()
    elif mode == 'sort':
        # 数码管演示：五整数冒泡排序 + 8 位数码管实时显示（含期望显示轨迹，供 tb 比对）
        # 显示内容/数据都在 sort_demo.py 里，改完重跑本脚本即可（不用动 Verilog）
        import sort_demo
        prog  = sort_demo.build_program()
        words = words_of(prog)
        hexn  = 'seg_sort.hex'
        memn  = 'seg_sort_mem.hex'
        cw    = sort_demo.build_dmem()
    elif mode == 'lcdtest':
        # LCD 自检：自动试遍 8 种配置（RST 极性 × WR/RD 互换 × 初始化变体），串口报进度
        import lcd_demo
        prog  = lcd_demo.build_test_program()
        words = words_of(prog)
        hexn  = 'lcd_test.hex'
        memn  = 'lcd_test_mem.hex'
        cw    = lcd_demo.build_test_dmem()
    elif mode == 'btcheck':
        # 蓝牙自检：周期在蓝牙口发 'K'，并把蓝牙收到的字节经 USB-UART 打印（可做环回冷测）
        prog  = build_btcheck_program()
        words = words_of(prog)
        hexn  = 'bt_check.hex'
        memn  = 'bt_check_mem.hex'
        cw    = []
    elif mode == 'flags':
        # 溢出标志位演示：8 位数码管显示 SF/ZF/CF/OF/粘滞/PF/SEEN/溢出计数奇偶
        prog  = build_flags_demo_program()
        words = words_of(prog)
        hexn  = 'flags_demo.hex'
        memn  = 'flags_demo_mem.hex'
        cw    = []
    elif mode == 'lcdread':
        # LCD 读回自检 v4：写 0x5A/0x3C 进显示 RAM 再读回来，数码管+串口显示读到的值
        import lcd_demo
        prog  = lcd_demo.build_readback_program()
        words = words_of(prog)
        hexn  = 'lcd_read.hex'
        memn  = 'lcd_read_mem.hex'
        cw    = lcd_demo.build_test_dmem()
    elif mode == 'btat':
        # 蓝牙 AT 探针：发 AT / AT+CRLF / AT+NAME?，把模组回显打到 USB-UART
        prog  = build_btat_program()
        words = words_of(prog)
        hexn  = 'bt_at.hex'
        memn  = 'bt_at_mem.hex'
        cw    = []
    elif mode == 'btat2':
        # 蓝牙 AT 探索器（8 轮）：问版本/名字/地址/角色/波特率，最后复位让它重新广播
        prog  = build_btat_program(BTAT_ROUNDS_INFO)
        words = words_of(prog)
        hexn  = 'bt_at2.hex'
        memn  = 'bt_at2_mem.hex'
        cw    = []
    elif mode == 'btcfg':
        # 蓝牙模式脚扫描：8 种 BT_CTRL 组合（主从/sw_hw/sw），每种停 10s 让手机试连接
        prog  = build_btcfg_program()
        words = words_of(prog)
        hexn  = 'bt_cfg.hex'
        memn  = 'bt_cfg_mem.hex'
        cw    = []
    elif mode == 'btseg':
        # 蓝牙→数码管：手机发来的字节以 16 进制滚动显示在 8 位数码管上（并原样回发）
        prog  = build_btseg_program()
        words = words_of(prog)
        hexn  = 'bt_seg.hex'
        memn  = 'bt_seg_mem.hex'
        cw    = []
    else:
        print('usage: python gen_uart_demo.py [hello|helloecho|echo|bt|lcd|sort|lcdtest|btcheck|flags|lcdread|btat|btat2|btcfg|btseg]')
        sys.exit(1)

    write_hex(os.path.join(FILE_DIR, hexn), words)
    write_hex(os.path.join(FILE_DIR, memn), cw)

    if mode == 'lcd':
        # 额外输出期望帧缓存（128×128，8 页×128 列，每字 1 字节），
        # 供 tb_EES338_lcd.v 做"LCD 总线上收到的数据 == 期望图案"的逐字节比对
        write_hex(os.path.join(FILE_DIR, 'lcd_fb_expected.hex'),
                  lcd_demo.build_fb_words())

    if mode == 'sort':
        # 额外输出期望的数码管显示轨迹（值 + 高亮位 + 步数），
        # 供 tb_EES338_sort.v 逐状态比对（这就是"排序过程"的文字版视频）
        trace = sort_demo.build_trace()
        write_hex(os.path.join(FILE_DIR, 'seg_trace_val.hex'), [v for v, m in trace])
        write_hex(os.path.join(FILE_DIR, 'seg_trace_mrk.hex'), [m for v, m in trace])
        write_hex(os.path.join(FILE_DIR, 'seg_trace_len.hex'), [len(trace)])

    # 综合初始化文件内容与当前演示程序保持一致（切换程序后请重新运行本脚本）
    write_init_vh(os.path.join(SRC_DIR, 'imem_boot_init.vh'), words)
    write_init_vh(os.path.join(SRC_DIR, 'dmem_boot_init.vh'), cw)

    print('==== %s (%d instructions) ====' % (hexn, len(words)))
    pc = asm.PC_BASE
    for w in words:
        print('%08x  %08x' % (pc, w))
        pc += 4
    print('==== %s (%d words) ====' % (memn, len(cw)))
    for c in cw:
        print('%08x' % c)
    print('imem_boot_init.vh / dmem_boot_init.vh updated -> %s' % mode)


if __name__ == '__main__':
    main()
