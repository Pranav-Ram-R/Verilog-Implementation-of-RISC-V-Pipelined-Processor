"""
Minimal RISC-V RV32I assembler for the test program.
Produces hex output, one 32-bit instruction per line.
"""

def reg(r):
    """Parse register name like 'x5' -> 5"""
    assert r.startswith('x')
    n = int(r[1:])
    assert 0 <= n < 32
    return n

def encode_R(rd, rs1, rs2, funct3, funct7, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_I(rd, rs1, imm, funct3, opcode):
    # imm is 12-bit signed
    imm12 = imm & 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_S(rs1, rs2, imm, funct3, opcode):
    imm12 = imm & 0xFFF
    imm_hi = (imm12 >> 5) & 0x7F   # bits [11:5]
    imm_lo = imm12 & 0x1F          # bits [4:0]
    return (imm_hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_lo << 7) | opcode

def encode_B(rs1, rs2, imm, funct3, opcode):
    # imm is 13-bit signed, LSB always 0
    assert imm % 2 == 0
    imm13 = imm & 0x1FFF
    bit12   = (imm13 >> 12) & 1
    bit11   = (imm13 >> 11) & 1
    bits_10_5 = (imm13 >> 5) & 0x3F
    bits_4_1  = (imm13 >> 1) & 0xF
    imm_31_25 = (bit12 << 6) | bits_10_5
    imm_11_7  = (bits_4_1 << 1) | bit11
    return (imm_31_25 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_11_7 << 7) | opcode

def encode_J(rd, imm, opcode):
    # imm is 21-bit signed, LSB always 0
    assert imm % 2 == 0
    imm21 = imm & 0x1FFFFF
    bit20   = (imm21 >> 20) & 1
    bits_10_1 = (imm21 >> 1) & 0x3FF
    bit11   = (imm21 >> 11) & 1
    bits_19_12 = (imm21 >> 12) & 0xFF
    imm_31_12 = (bit20 << 19) | (bits_10_1 << 9) | (bit11 << 8) | bits_19_12
    return (imm_31_12 << 12) | (rd << 7) | opcode

# Instruction encodings
def addi(rd, rs1, imm):  return encode_I(reg(rd), reg(rs1), imm, 0b000, 0b0010011)
def add(rd, rs1, rs2):   return encode_R(reg(rd), reg(rs1), reg(rs2), 0b000, 0b0000000, 0b0110011)
def sub(rd, rs1, rs2):   return encode_R(reg(rd), reg(rs1), reg(rs2), 0b000, 0b0100000, 0b0110011)
def beq(rs1, rs2, imm):  return encode_B(reg(rs1), reg(rs2), imm, 0b000, 0b1100011)
def jal(rd, imm):        return encode_J(reg(rd), imm, 0b1101111)
def lw(rd, rs1, imm):    return encode_I(reg(rd), reg(rs1), imm, 0b010, 0b0000011)
def sw(rs1, rs2, imm):   return encode_S(reg(rs1), reg(rs2), imm, 0b010, 0b0100011)

# Program:
#   addi x1, x0, 1       # x1 = 1
#   addi x2, x0, 1       # x2 = 1
#   addi x3, x0, 3       # x3 = 3 (counter)
#   addi x4, x0, 0       # x4 = 0
# loop:                  (address 0x10)
#   add  x5, x1, x2      # x5 = x1 + x2
#   add  x1, x2, x0      # x1 = x2
#   add  x2, x5, x0      # x2 = x5
#   addi x3, x3, -1      # x3 -= 1
#   beq  x3, x4, done    # if x3 == 0 goto done (offset = +8)
#   jal  x0, loop        # unconditional back to loop (offset = -20)
# done:                  (address 0x28)
#   sw   x0, x2, 0       # mem[0] = x2

# Address layout (each instr = 4 bytes):
# 0x00: addi x1
# 0x04: addi x2
# 0x08: addi x3
# 0x0C: addi x4
# 0x10: add x5    <- "loop"
# 0x14: add x1
# 0x18: add x2
# 0x1C: addi x3
# 0x20: beq x3,x4,done   -- offset to 0x28 from 0x20 = +8
# 0x24: jal x0, loop     -- offset to 0x10 from 0x24 = -20
# 0x28: sw  x0, x2, 0    <- "done"

program = [
    ("addi x1, x0, 1",   addi("x1", "x0", 1)),
    ("addi x2, x0, 1",   addi("x2", "x0", 1)),
    ("addi x3, x0, 3",   addi("x3", "x0", 3)),
    ("addi x4, x0, 0",   addi("x4", "x0", 0)),
    ("add  x5, x1, x2",  add("x5", "x1", "x2")),
    ("add  x1, x2, x0",  add("x1", "x2", "x0")),
    ("add  x2, x5, x0",  add("x2", "x5", "x0")),
    ("addi x3, x3, -1",  addi("x3", "x3", -1)),
    ("beq  x3, x4, +8",  beq("x3", "x4", 8)),
    ("jal  x0, -20",     jal("x0", -20)),
    ("sw   x0, x2, 0",   sw("x0", "x2", 0)),
]

print("# Verified program.hex")
print()
for asm, enc in program:
    print(f"{enc:08x}    // {asm}")

# Also write a plain hex file (no comments, for $readmemh)
with open("/home/claude/program.hex", "w") as f:
    for asm, enc in program:
        f.write(f"{enc:08x}\n")

print()
print("Wrote /home/claude/program.hex")
