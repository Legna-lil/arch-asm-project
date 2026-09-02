# asm.py - 极简 RISC-V 汇编器，用于生成测试程序 hex
# 支持指令：AUIPC ADDI ANDI ORI SLLI SW LW ADD SUB AND OR XOR SLT BEQ BNE BLT BGE JAL（含标签）
import re

PC_BASE = 0x00400000


def r_type(f7, f3, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33


def i_type(f3, rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x13


def load(f3, rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x03


def store(f3, rs2, rs1, imm):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23


def u_type(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0x17  # AUIPC


def b_type(f3, rs2, rs1, imm):
    imm &= 0x1FFF  # 13 位有符号立即数
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def j_type(rd, imm):
    imm &= 0x1FFFFF  # 21 位有符号立即数
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def reg(s):
    return int(s[1:])  # x0..x31


def parse(lines):
    """返回 (pc, mnemonic, args) 列表"""
    items = []
    pc = PC_BASE
    for line in lines:
        line = re.sub(r'#.*', '', line).strip()
        if not line:
            continue
        m = re.match(r'^(\w+):\s*(.*)$', line)
        label = None
        if m:
            label, line = m.group(1), m.group(2).strip()
        if line:
            parts = line.replace(',', ' ').split()
            items.append((label, pc, parts[0], parts[1:]))
            pc += 4
        else:
            items.append((label, pc, None, None))
    return items


def assemble(items):
    # 第一遍：记录标签地址
    labels = {}
    for label, pc, _, _ in items:
        if label:
            labels[label] = pc
    # 第二遍：编码
    words = []
    for label, pc, mnem, args in items:
        if mnem is None:
            continue
        op = None
        if mnem == 'auipc':
            op = u_type(reg(args[0]), int(args[1], 0))
        elif mnem == 'addi':
            op = i_type(0, reg(args[0]), reg(args[1]), int(args[2], 0))
        elif mnem == 'andi':
            op = i_type(7, reg(args[0]), reg(args[1]), int(args[2], 0))
        elif mnem == 'ori':
            op = i_type(6, reg(args[0]), reg(args[1]), int(args[2], 0))
        elif mnem == 'slli':
            op = i_type(1, reg(args[0]), reg(args[1]), int(args[2], 0))
        elif mnem == 'lw':
            mm = re.match(r'(\d+)\((\w+)\)', args[1])
            op = load(2, reg(args[0]), reg(mm.group(2)), int(mm.group(1)))
        elif mnem == 'sw':
            mm = re.match(r'(\d+)\((\w+)\)', args[1])
            op = store(2, reg(args[0]), reg(mm.group(2)), int(mm.group(1)))
        elif mnem in ('add', 'sub', 'and', 'or', 'xor', 'slt'):
            f7 = 0x20 if mnem == 'sub' else 0
            f3 = {'add': 0, 'sub': 0, 'and': 7, 'or': 6, 'xor': 4, 'slt': 2}[mnem]
            op = r_type(f7, f3, reg(args[0]), reg(args[1]), reg(args[2]))
        elif mnem in ('beq', 'bne', 'blt', 'bge'):
            f3 = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5}[mnem]
            op = b_type(f3, reg(args[1]), reg(args[0]), labels[args[2]] - pc)
        elif mnem == 'jal':
            op = j_type(reg(args[0]), labels[args[1]] - pc)
        else:
            raise ValueError("unknown instruction: %s" % mnem)
        words.append(op)
    return words


if __name__ == '__main__':
    programs = {}

    # ---------------- 程序1：冒险专项（前递/load-use/分支flush/JAL链接） ----------------
    programs['hazard_test.hex'] = r'''
        auipc x10, 0x0fc10    # x10 = 0x00400000 + 0x0fc10000 = 0x10010000 (数据区基址)
        addi  x10, x10, 0
        addi  x5, x0, 10      # x5 = 10
        addi  x6, x5, 5       # x6 = 15  （RAW 前递：addi 紧跟 addi）
        addi  x7, x6, 20      # x7 = 35  （RAW 前递）
        sw    x5, 0(x10)      # mem[0] = 10
        lw    x11, 0(x10)     # x11 = 10
        addi  x12, x11, 1     # x12 = 11  （load-use：需要 stall 1 拍 + 前递）
        sw    x12, 4(x10)     # mem[1] = 11
        addi  x13, x0, 0
loop:
        addi  x13, x13, 1     # x13 自增
        blt   x13, x5, loop   # 控制冒险：分支回跳 flush 两条错误路径指令
        jal   x1, done        # JAL 链接：x1 = PC+4，跳转
        addi  x14, x0, 99     # 该指令必须被 flush，x14 保持 0
done:
        addi  x15, x1, 0      # x15 = 链接值（JAL 的 PC+4）
        sw    x15, 8(x10)     # mem[2] = 链接值
        sw    x13, 12(x10)    # mem[3] = 10
        addi  x0, x0, 0       # 结尾 NOP
    '''

    # ---------------- 程序2：18条指令逐条测试 ----------------
    programs['inst_alu.hex'] = r'''
        auipc x10, 0x0fc10    # x10 = 0x10010000
        addi  x10, x10, 0
        addi  x5, x0, 10      # x5 = 10
        addi  x6, x0, 3       # x6 = 3
        add   x7, x5, x6      # x7 = 13
        sub   x8, x5, x6      # x8 = 7
        and   x9, x5, x6      # x9 = 10&3 = 2
        or    x11, x5, x6     # x11 = 10|3 = 11
        xor   x12, x5, x6     # x12 = 10^3 = 9
        slt   x13, x6, x5     # x13 = 1 (3<10)
        slt   x14, x5, x6     # x14 = 0 (10<3)
        addi  x15, x5, 5      # x15 = 15
        andi  x16, x5, 6      # x16 = 10&6 = 2
        ori   x17, x5, 6      # x17 = 10|6 = 14
        slli  x18, x5, 2      # x18 = 40
        auipc x19, 0          # x19 = 本指令地址 0x0040003c
        lw    x20, 0(x10)     # x20 = mem[0] = 9（初始数据）
        sw    x7,  0(x10)     # mem[0] = 13
        sw    x8,  4(x10)     # mem[1] = 7
        sw    x9,  8(x10)     # mem[2] = 2
        sw    x11, 12(x10)    # mem[3] = 11
        sw    x12, 16(x10)    # mem[4] = 9
        sw    x13, 20(x10)    # mem[5] = 1
        sw    x14, 24(x10)    # mem[6] = 0
        sw    x15, 28(x10)    # mem[7] = 15
        sw    x16, 32(x10)    # mem[8] = 2
        sw    x17, 36(x10)    # mem[9] = 14
        sw    x18, 40(x10)    # mem[10] = 40
        sw    x19, 44(x10)    # mem[11] = 0x0040003c
        addi  x0, x0, 0
    '''
    # ---------------- 程序3：前递专项（ALU-ALU / add->sw / MEM-WB 前递） ----------------
    programs['inst_forward.hex'] = r'''
        auipc x10, 0x0fc10
        addi  x10, x10, 0
        addi  x5, x0, 100
        addi  x6, x5, 1       # EX/MEM 前递 -> 101
        addi  x7, x6, 1       # EX/MEM 前递 -> 102
        addi  x8, x5, 0       # 100
        addi  x0, x0, 0       # 间隔指令
        addi  x9, x8, 5       # MEM/WB 前递 -> 105
        addi  x5, x0, 20
        add   x13, x5, x5     # 40
        sw    x13, 0(x10)     # mem[0] = 40  (add->sw 写数据 EX/MEM 前递)
        add   x14, x5, x5     # 40
        addi  x0, x0, 0       # 间隔指令
        sw    x14, 4(x10)     # mem[1] = 40  (add->sw 写数据 MEM/WB 前递)
        lw    x11, 0(x10)     # x11 = 40
        addi  x12, x11, 5     # load-use stall + 前递 -> 45
        sw    x12, 8(x10)     # mem[2] = 45
        beq   x12, x13, T1    # 45==40? 不跳（分支操作数走前递）
        addi  x15, x0, 1      # x15 = 1
T1:
        addi  x16, x0, 0
        addi  x16, x16, 2
        lw    x17, 8(x10)     # x17 = 45
        beq   x17, x12, T2    # 45==45 跳（lw->branch：stall + 前递 + flush）
        addi  x15, x0, 99     # 被 flush
T2:
        addi  x15, x15, 1     # x15 = 2
        sw    x15, 12(x10)    # mem[3] = 2
        sw    x16, 16(x10)    # mem[4] = 2
        addi  x0, x0, 0
    '''

    # ---------------- 程序4：分支/跳转专项 ----------------
    programs['inst_branch.hex'] = r'''
        auipc x10, 0x0fc10
        addi  x10, x10, 0
        addi  x5, x0, 7
        addi  x6, x0, 7
        addi  x7, x0, 3
        beq   x5, x6, L1      # 跳 (7==7)
        addi  x28, x0, 99     # flush
L1:
        addi  x8, x0, 1       # x8=1
        beq   x5, x7, L2      # 不跳 (7!=3)
        addi  x8, x8, 1       # x8=2
L2:
        bne   x5, x7, L3      # 跳 (7!=3)
        addi  x28, x0, 99     # flush
L3:
        addi  x8, x8, 1       # x8=3
        bne   x5, x6, L4      # 不跳 (7==7)
        addi  x8, x8, 1       # x8=4
L4:
        blt   x7, x5, L5      # 跳 (3<7)
        addi  x28, x0, 99     # flush
L5:
        addi  x8, x8, 1       # x8=5
        blt   x5, x7, L6      # 不跳 (7<3)
        addi  x8, x8, 1       # x8=6
L6:
        bge   x5, x7, L7      # 跳 (7>=3)
        addi  x28, x0, 99     # flush
L7:
        addi  x8, x8, 1       # x8=7
        bge   x7, x5, L8      # 不跳 (3>=7)
        addi  x8, x8, 1       # x8=8
L8:
        jal   x9, L9          # x9=PC+4，跳转
        addi  x28, x0, 99     # flush
L9:
        addi  x8, x8, 1       # x8=9
        sw    x8, 0(x10)      # mem[0]=9
        sw    x9, 4(x10)      # mem[1]=链接值
        sw    x28, 8(x10)     # mem[2]=0（错误路径未写）
        addi  x0, x0, 0
    '''

    # ---------------- 程序5：溢出检测专项 ----------------
    programs['inst_overflow.hex'] = r'''
        auipc x10, 0x0fc10
        addi  x10, x10, 0
        auipc x5, 0x7fc00     # 20位字段 0x7fc00<<12=0x7fc00000，x5 = 0x00400008+0x7fc00000 = 0x80000008
        addi  x6, x5, -16     # 溢出: 0x80000008+(-16)=0x7ffffff8（两负得正）
        addi  x7, x5, 1       # 不溢出: 0x80000009
        add   x8, x5, x5      # 溢出: 0x80000008+0x80000008=0x10（两负得正）
        addi  x13, x0, 9
        sub   x9, x13, x5     # 溢出: 9-0x80000008=0x80000001（正减负得负）
        sub   x11, x5, x5     # 不溢出: 0
        sw    x6, 0(x10)      # mem[0] = 0x7ffffff8
        sw    x7, 4(x10)      # mem[1] = 0x80000009
        sw    x8, 8(x10)      # mem[2] = 0x10
        sw    x9, 12(x10)     # mem[3] = 0x80000001
        sw    x11, 16(x10)    # mem[4] = 0
        addi  x0, x0, 0
    '''

    out_dir = r'e:\VivadoProject\Lab2\Lab2.file'
    for fname, prog in programs.items():
        items = parse(prog.splitlines())
        words = assemble(items)
        out = '\n'.join('%08x' % w for w in words)
        with open(out_dir + '\\' + fname, 'w') as f:
            f.write(out + '\n')
        print('==== %s (%d instr) ====' % (fname, len(words)))
        print(out)
        for label, pc, _, _ in items:
            if label:
                print('  %s: 0x%08x' % (label, pc))
