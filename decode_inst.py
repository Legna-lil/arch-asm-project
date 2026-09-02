import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else r"e:\VivadoProject\Lab2\Lab2.file\inst_code_clean.hex"
lines = open(path).read().split()
rv = ["x%d" % i for i in range(32)]
pc = 0x00400000


def se(x, n):
    x = x & ((1 << n) - 1)
    return x - (1 << n) if x & (1 << (n - 1)) else x


for h in lines:
    v = int(h, 16)
    op = v & 0x7F
    rd = (v >> 7) & 0x1F
    f3 = (v >> 12) & 0x7
    rs1 = (v >> 15) & 0x1F
    rs2 = (v >> 20) & 0x1F
    f7 = (v >> 25) & 0x7F
    name = ""
    if op == 0x37:
        name = "LUI %s, 0x%x" % (rv[rd], (v >> 12) & 0xFFFFF)
    elif op == 0x17:
        name = "AUIPC %s, 0x%x" % (rv[rd], (v >> 12) & 0xFFFFF)
    elif op == 0x6F:
        imm = ((v >> 31) << 20) | (((v >> 12) & 0xFF) << 12) | (((v >> 20) & 1) << 11) | (((v >> 21) & 0x3FF) << 1)
        name = "JAL %s, %d" % (rv[rd], se(imm, 21))
    elif op == 0x67:
        name = "JALR %s, %d(%s)" % (rv[rd], se(v >> 20, 12), rv[rs1])
    elif op == 0x63:
        imm = ((v >> 31) << 12) | (((v >> 7) & 1) << 11) | (((v >> 25) & 0x3F) << 5) | (((v >> 8) & 0xF) << 1)
        b = {0: "BEQ", 1: "BNE", 4: "BLT", 5: "BGE", 6: "BLTU", 7: "BGEU"}
        name = "%s %s, %s, 0x%08x" % (b.get(f3, "?"), rv[rs1], rv[rs2], pc + se(imm, 13))
    elif op == 0x03:
        name = "LW %s, %d(%s)" % (rv[rd], se(v >> 20, 12), rv[rs1])
    elif op == 0x23:
        imm = ((v >> 25) << 5) | ((v >> 7) & 0x1F)
        name = "SW %s, %d(%s)" % (rv[rs2], se(imm, 12), rv[rs1])
    elif op == 0x13:
        imm = se(v >> 20, 12)
        n = {0: "ADDI", 2: "SLTI", 3: "SLTIU", 4: "XORI", 6: "ORI", 7: "ANDI", 1: "SLLI", 5: "SRLI"}
        if f3 == 1:
            name = "SLLI %s, %s, %d" % (rv[rd], rv[rs1], v >> 20)
        elif f3 == 5:
            name = "SRLI/SRAI %s, %s, %d" % (rv[rd], rv[rs1], v >> 20)
        else:
            name = "%s %s, %s, %d" % (n.get(f3, "?"), rv[rd], rv[rs1], imm)
    elif op == 0x33:
        n = {(0, 0): "ADD", (0x20, 0): "SUB", (0, 1): "SLL", (0, 2): "SLT", (0, 4): "XOR", (0, 5): "SRL", (0x20, 5): "SRA", (0, 6): "OR", (0, 7): "AND"}
        name = "%s %s, %s, %s" % (n.get((f7, f3), "?"), rv[rd], rv[rs1], rv[rs2])
    else:
        name = "opcode=0x%02x" % op
    print("%08x: %s  %s" % (pc, h, name))
    pc += 4
