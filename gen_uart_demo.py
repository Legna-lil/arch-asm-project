# gen_uart_demo.py
# 生成 UART 演示程序 / 数据 hex，以及综合阶段(bitstream)用的字面量初始化文件。
#
# 用法:
#   python gen_uart_demo.py hello       # 默认: 上电打印 "Hello, EES-338!" (同步刷新 imem/dmem init)
#   python gen_uart_demo.py helloecho   # 自检: 先打印 Hello, 再回显 PC 发来的字节 (TX+RX 全测)
#   python gen_uart_demo.py echo        # 生成: PC 发字符原样回显 (同步刷新 imem/dmem init)
#
# 生成内容:
#   Lab2.file/uart_hello.hex      程序机器码
#   Lab2.file/uart_hello_mem.hex  字符串数据(每字一个字符)
#   Lab2.file/uart_echo.hex       回显程序机器码
#   Lab2.file/uart_echo_mem.hex   回显数据(空)
#   sources_1/new/imem_boot_init.vh  综合阶段 InstructionMemory 的字面量初始化
#   sources_1/new/dmem_boot_init.vh  综合阶段 DataMemory 的字面量初始化
#        (说明: InstructionMemory.v / DataMemory.v 在 `ifdef SYNTHESIS 下
#         会 include 这两个文件，保证程序/数据被烘焙进 bitstream)
import asm
import os
import sys

FILE_DIR = r'e:\VivadoProject\Lab2\Lab2.file'
SRC_DIR  = r'e:\VivadoProject\Lab2\Lab2.srcs\sources_1\new'

HELLO_MSG = "Hello, EES-338!\r\nHello, EES-338!\r\n"   # 一个 burst 连发两条(34B)，第二条紧跟无空闲，
                                                        # 规避“空闲后再起传丢开头字节”的接收端问题

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
        # ---- 4) 间隔期计数（每轮主循环都经过回显捕获，保持回显灵敏） ----
        addi  x17, x17, 1
        addi  x19, x0, 2047
        blt   x17, x19, main
        addi  x17, x0, 0
        addi  x20, x20, 1
        addi  x19, x0, 1000
        blt   x20, x19, main
        addi  x20, x0, 0
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
    else:
        print('usage: python gen_uart_demo.py [hello|helloecho|echo]')
        sys.exit(1)

    write_hex(os.path.join(FILE_DIR, hexn), words)
    write_hex(os.path.join(FILE_DIR, memn), cw)

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
