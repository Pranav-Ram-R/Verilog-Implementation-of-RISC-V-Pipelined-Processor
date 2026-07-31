# RISC-V RV32I 5-Stage Pipelined Processor

A synthesisable 5-stage pipelined RV32I CPU written in structural Verilog-2001,
with full operand forwarding, a load-use interlock, branch resolution in the
execute stage, and a self-checking testbench.

The design is deliberately built out of small single-purpose modules wired
together at the top level, rather than one large behavioural block, so that
each piece of the datapath can be pointed at and explained in isolation.

**Verified:** compiles with zero errors and zero warnings under Vivado xsim
2019.2 and Icarus Verilog; the bundled test program runs to
`PASS: mem[0] = 5`.

---

## Table of contents

1. [Quick start](#quick-start)
2. [Architecture overview](#architecture-overview)
3. [Stage-by-stage walkthrough](#stage-by-stage-walkthrough)
4. [Module reference](#module-reference)
5. [Instruction formats](#instruction-formats)
6. [Control signal reference](#control-signal-reference)
7. [Two-level ALU decode](#two-level-alu-decode)
8. [Hazards: the interesting part](#hazards-the-interesting-part)
9. [The falling-edge register file](#the-falling-edge-register-file)
10. [Worked example: cycle-by-cycle trace](#worked-example-cycle-by-cycle-trace)
11. [Performance](#performance)
12. [Verification coverage](#verification-coverage)
13. [Known limitations](#known-limitations)
14. [Design decisions and trade-offs](#design-decisions-and-trade-offs)

---

## Quick start

**Icarus Verilog:**

```bash
iverilog -o sim *.v
vvp sim
```

**Vivado xsim, command line:**

```bash
xvlog *.v
xelab tb_riscv_top -s tbsim
xsim tbsim -runall
```

**Vivado GUI:**

1. Create a new RTL Project, target any part (e.g. Artix-7 `xc7a35t`).
2. Add all `.v` files as design sources except `tb_riscv_top.v`.
3. Add `tb_riscv_top.v` as a simulation source.
4. Add `program.hex` — it must sit in the run directory when the simulation
   starts, since `$readmemh` resolves it relative to the working directory.
5. Run Behavioral Simulation.

Expected final output in every flow:

```
==========================================
PASS: mem[0] = 5 (expected 5 = fib(5))
==========================================
```

To regenerate the program image after editing the assembler:

```bash
python assemble.py      # writes program.hex
```

---

## Architecture overview

Five stages, separated by four pipeline registers. Each pipeline register is a
bank of flip-flops that carries both the datapath values and the control bits
an instruction will need in every stage downstream of it.

```
            IF/ID           ID/EX           EX/MEM          MEM/WB
              |               |               |               |
   IF ────────┼────── ID ─────┼────── EX ─────┼────── MEM ────┼────── WB
              |               |               |               |
   PC         |  reg file     |  forward mux  |  data memory  |  wb mux
   imem       |  imm gen      |  ALU          |               |
   pc + 4     |  control unit |  branch target|               |
              |  alu control  |  branch taken?|               |
```

The three feedback paths are what turn a chain of registers into an actual
pipeline:

| Path | From | To | Purpose |
|---|---|---|---|
| **Forwarding** | `EX/MEM.alu_result`, WB mux output | EX operand muxes | Bypass RAW hazards |
| **Writeback** | WB mux output | Register file write port | Commit results |
| **Redirect** | EX branch logic | PC mux, IF/ID flush, ID/EX flush | Control hazards |

A fourth path, `stall`, runs backwards from the hazard detection unit to the
PC and IF/ID.

The core is Harvard-style: instruction and data memory are separate arrays.
This is not just tradition — a unified memory would need two ports anyway,
because IF and MEM are active in the same cycle on different addresses.

**Top-level interface.** `riscv_top` exposes only `clk` and an active-low
asynchronous `rst_n`. Both memories are internal, 256 words deep, parameterised
by `MEM_DEPTH`.

---

## Stage-by-stage walkthrough

### IF — Instruction Fetch

The PC mux has three inputs and a strict priority order
([riscv_top.v:35-37](riscv_top.v#L35-L37)):

```verilog
wire [31:0] pc_next = take_branch ? ex_pc_target :
                      stall       ? pc_current   :
                                    pc_plus_4_if;
```

`take_branch` outranks `stall`. That ordering matters: if a branch resolves in
EX during the same cycle that a load-use hazard is detected in ID, the
instructions being stalled are on the wrong path anyway and are about to be
flushed, so the redirect must win. Getting this backwards produces a core that
occasionally executes one wrong-path instruction after a branch.

`instruction_memory` is a combinational ROM — the fetch completes within the
cycle, so no `IF` register is needed ahead of IF/ID.

### ID — Instruction Decode

Four things happen in parallel, all combinationally:

- **`register_file`** reads `rs1` and `rs2` from fixed instruction fields
  `[19:15]` and `[24:20]`. Because those fields sit in the same place in every
  format, the read starts before the instruction is decoded at all.
- **`immediate_generator`** selects and sign-extends the immediate based on
  opcode.
- **`control_unit`** decodes the opcode into every control signal.
- **`alu_control`** performs the second decode level using `funct3`/`funct7`.

`id_pc_plus_4` is computed here rather than reused from IF. Both are `PC + 4`,
but the IF one belongs to whatever instruction is *currently being fetched*,
which after a redirect is a different instruction entirely. Computing the link
value in ID costs one small adder and removes the possibility of `jal` writing
the wrong return address.

The ALU control decode is done in ID and the resulting 4-bit `alu_ctrl` is
piped through ID/EX, rather than decoding in EX. This shortens the EX critical
path, which already contains the forwarding mux, the ALU, and the branch
comparison.

### EX — Execute

The busiest stage:

1. `forwarding_unit` compares ID/EX source registers against in-flight
   destinations and drives two 3-input muxes.
2. `alu_operand_a` is always the forwarded `rs1`. `alu_operand_b` is
   `ex_alu_src ? ex_immediate : fwd_rs2` — the immediate/register mux sits
   *after* the forwarding mux, so a forwarded value can never be silently
   dropped for a register-operand instruction.
3. The ALU computes, and `zero_flag` falls out of the result.
4. Branch resolution ([riscv_top.v:216-219](riscv_top.v#L216-L219)):

```verilog
wire [31:0] branch_target = ex_pc + ex_immediate;
wire        pc_src_jalr   = ex_jump & ex_alu_src;
assign      ex_pc_target  = pc_src_jalr ? (alu_result & ~32'd1) : branch_target;
assign      take_branch   = (ex_branch & zero_flag) | ex_jump;
```

Three details worth knowing:

- **`beq` is implemented as SUB + zero flag.** `alu_control` maps `alu_op = 01`
  to `ALU_SUB`, so `rs1 - rs2 == 0` means equal. No dedicated comparator.
- **`jalr` is distinguished by `ex_jump & ex_alu_src`.** `jalr` is the only
  jump that takes an immediate through the ALU, so that pair uniquely
  identifies it without piping the opcode into EX.
- **`& ~32'd1`** clears bit 0 of the `jalr` target, as the ISA requires.
- **`take_branch` is computed, not a control output.** The control unit emits
  `branch` and `jump` separately; whether the PC actually redirects depends on
  a datapath value (`zero_flag`) that does not exist until EX.

### MEM — Memory Access

`data_memory` has a combinational read gated by `mem_read` and a synchronous
write. The store data comes from `fwd_rs2` — the *forwarded* `rs2`, not the raw
register read. This is the path people forget: `add x5, x1, x2` immediately
followed by `sw x5, 0(x0)` needs the forwarded value even though the store
never touches the ALU with it.

### WB — Write Back

A three-way mux on `wb_src`:

| `wb_src` | Source | Used by |
|---|---|---|
| `2'b00` | `alu_result` | R-type, I-type ALU |
| `2'b01` | `mem_read_data` | `lw` |
| `2'b10` | `pc_plus_4` | `jal`, `jalr` (link register) |

---

## Module reference

| File | Ports in / out | Responsibility |
|---|---|---|
| [riscv_top.v](riscv_top.v) | `clk`, `rst_n` | Stage wiring, forwarding muxes, PC redirect, WB mux |
| [program_counter.v](program_counter.v) | `pc_next` → `pc_current` | 32-bit PC register, async reset to 0 |
| [instruction_memory.v](instruction_memory.v) | `addr` → `instruction` | 256×32 ROM, `$readmemh("program.hex")` |
| [register_file.v](register_file.v) | `rs1/rs2/rd_addr`, `rd_data` → `rs1/rs2_data` | 32 GPRs, combinational read, **negedge** write, x0 hardwired |
| [immediate_generator.v](immediate_generator.v) | `instruction` → `immediate` | Selects and sign-extends I/S/B/J immediates |
| [control_unit.v](control_unit.v) | `opcode` → 8 control signals | First-level decode |
| [alu_control.v](alu_control.v) | `alu_op`, `funct3`, `funct7` → `alu_ctrl` | Second-level decode |
| [alu.v](alu.v) | `operand_a/b`, `alu_ctrl` → `alu_result`, `zero_flag` | 6 operations |
| [data_memory.v](data_memory.v) | `addr`, `write_data` → `read_data` | 256×32 RAM, combinational read, sync write |
| [if_id_reg.v](if_id_reg.v) | `pc`, `instruction` | IF/ID register — **stall and flush both live** |
| [id_ex_reg.v](id_ex_reg.v) | 9 datapath + 7 control fields | ID/EX register — flush live, stall tied off |
| [ex_mem_reg.v](ex_mem_reg.v) | 4 datapath + 4 control fields | EX/MEM register — both tied off |
| [mem_wb_reg.v](mem_wb_reg.v) | 3 datapath + 3 control fields | MEM/WB register — both tied off |
| [forwarding_unit.v](forwarding_unit.v) | source/dest addrs → `forward_a/b` | Combinational bypass control |
| [hazard_detection_unit.v](hazard_detection_unit.v) | load + addr compare → `stall` | Load-use interlock |
| [tb_riscv_top.v](tb_riscv_top.v) | — | Cycle trace + self-checking PASS/FAIL |
| [assemble.py](assemble.py) | — | Minimal RV32I encoder producing `program.hex` |

All four pipeline registers share the same port shape and the same priority
ladder — **reset > flush > stall > advance** — even where a port is tied off.
The uniformity means the four modules can be read once and understood
everywhere, and adding a real stall to EX/MEM later (for a multi-cycle memory,
say) is a one-line change at the instantiation rather than a module rewrite.

The `stall` branch of each register is an empty `begin/end`. In a **clocked**
always block, omitting an assignment means the flip-flop holds its value — no
latch is inferred. That would not be true in a combinational `always @(*)`
block.

---

## Instruction formats

RV32I is fixed-width 32-bit. `opcode` is always `[6:0]`, and `rd`, `rs1`, `rs2`
never move between formats. Five of the six formats are used here — no U-type,
since there is no `lui`/`auipc`.

```
       31        25 24    20 19    15 14  12 11         7 6      0
R    | funct7     | rs2    | rs1    |funct3| rd         | opcode |
I    | imm[11:0]           | rs1    |funct3| rd         | opcode |
S    | imm[11:5]  | rs2    | rs1    |funct3| imm[4:0]   | opcode |
B    |imm[12|10:5]| rs2    | rs1    |funct3|imm[4:1|11] | opcode |
J    | imm[20|10:1|11|19:12]               | rd         | opcode |
```

**Why the immediates look scrambled.** S splits its immediate purely so `rs2`
stays put. B and J go further: the sign bit is pinned to bit 31 in *every*
format, so one sign-extension structure is shared across all of them; and both
encode a halfword offset with an implicit zero LSB, buying an extra bit of
range for free. That is why [immediate_generator.v:29-34](immediate_generator.v#L29-L34)
reassembles B as `{sign, i[7], i[30:25], i[11:8], 1'b0}` instead of slicing a
contiguous field.

### Supported instruction set

| Format | Instructions | opcode | funct3 | funct7 |
|---|---|---|---|---|
| R | `add` / `sub` | `0110011` | `000` | `0000000` / `0100000` |
| R | `and`, `or`, `slt`, `srl` | `0110011` | `111`, `110`, `010`, `101` | `0000000` |
| I | `addi`, `andi`, `ori` | `0010011` | `000`, `111`, `110` | — |
| I | `lw` | `0000011` | `010` | — |
| I | `jalr` | `1100111` | `000` | — |
| S | `sw` | `0100011` | `010` | — |
| B | `beq` | `1100011` | `000` | — |
| J | `jal` | `1101111` | — | — |

---

## Control signal reference

`control_unit` looks *only* at the 7-bit opcode. Every output is assigned a
default at the top of the `always @(*)` block before the `case`, which
guarantees no inferred latches and — importantly — makes opcode `0000000`
decode to all-controls-off. That is what makes a zeroed pipeline register a
harmless NOP, which is exactly what flush and reset produce.

| Instruction | opcode | `branch` | `jump` | `reg_write` | `alu_src` | `alu_op` | `mem_read` | `mem_write` | `wb_src` |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| R-type | `0110011` | 0 | 0 | 1 | 0 | `10` | 0 | 0 | `00` |
| I-type ALU | `0010011` | 0 | 0 | 1 | 1 | `11` | 0 | 0 | `00` |
| `lw` | `0000011` | 0 | 0 | 1 | 1 | `00` | 1 | 0 | `01` |
| `sw` | `0100011` | 0 | 0 | 0 | 1 | `00` | 0 | 1 | — |
| `beq` | `1100011` | 1 | 0 | 0 | 0 | `01` | 0 | 0 | — |
| `jal` | `1101111` | 0 | 1 | 1 | 0 | `00` | 0 | 0 | `10` |
| `jalr` | `1100111` | 0 | 1 | 1 | 1 | `00` | 0 | 0 | `10` |
| bubble / NOP | `0000000` | 0 | 0 | 0 | 0 | `00` | 0 | 0 | `00` |

The single most important column is `reg_write`. A bubble has `reg_write = 0`,
and the forwarding unit gates every bypass on `reg_write`, so a bubble can
never become a forwarding source. The "don't forward from a bubble" guard is
not extra logic — it comes free from the control defaults.

---

## Two-level ALU decode

Rather than decoding the full instruction into an ALU operation in one step,
the control unit emits a 2-bit *hint* and `alu_control` finishes the job.

| `alu_op` | Meaning | Result |
|---|---|---|
| `00` | Address arithmetic — `lw`, `sw`, `jalr` | Always `ALU_ADD` |
| `01` | Comparison — `beq` | Always `ALU_SUB` |
| `10` | R-type — look at `funct3` **and** `funct7` | `add`, `sub`, `and`, `or`, `slt`, `srl` |
| `11` | I-type ALU — look at `funct3` **only** | `addi`, `andi`, `ori` |

```
alu_op=10, funct3=000, funct7=0100000 -> SUB      (R-type)
alu_op=10, funct3=000, funct7=0000000 -> ADD
alu_op=10, funct3=111 -> AND    funct3=110 -> OR
alu_op=10, funct3=010 -> SLT    funct3=101 -> SRL

alu_op=11, funct3=000 -> ADD    (addi - funct7 is NOT consulted)
alu_op=11, funct3=111 -> AND    (andi)
alu_op=11, funct3=110 -> OR     (ori)
```

**R-type and I-type deliberately get different `alu_op` encodings.** It is
tempting to share `10` between them, since both need a `funct3` lookup — but
`funct7` only exists in R-type. In an I-type instruction, bits `[31:25]` are
the top of the immediate. Sharing the encoding means `addi` with an immediate
whose `imm[11:5]` happens to equal `0100000` (decimal 1024–1055) decodes as
SUB and computes `rs1 - imm`. Splitting the encoding makes the distinction
structural: the `funct7` test is unreachable for any I-type instruction.

ALU encodings are `localparam`s duplicated in both `alu.v` and `alu_control.v`
so each module stands alone. The obvious improvement is a shared header
included by both.

The `default` arms assign `4'bXXXX` rather than a safe value. This is
deliberate: an unsupported `funct3` propagates X through the datapath and
shows up immediately in simulation, instead of silently behaving like an ADD.
Fail loudly in simulation, and let synthesis treat it as a don't-care.

---

## Hazards: the interesting part

A pipeline is only correct if it produces the same results as sequential
execution. Three things threaten that.

### 1. Data hazards (RAW) — solved by forwarding

An instruction needs a register value at the start of its EX stage, but the
producer has not written it back yet. Two cases matter:

| Distance | Producer is in | Fix | `forward_*` code |
|---|---|---|---|
| 1 instruction | EX/MEM | Bypass the ALU result | `2'b10` |
| 2 instructions | MEM/WB | Bypass the writeback value | `2'b01` |
| 3 instructions | Already written back | Register file read | `2'b00` |

The distance-3 case is only safe because of the falling-edge register file —
see the next section.

**Priority.** EX/MEM is checked *first*. If both stages hold a pending write to
the same register, EX/MEM holds the newer value and must win. Reversing these
two `if` arms produces a core that reads stale data whenever a register is
written twice in three instructions — a bug that passes most simple test
programs.

**The `rd != 0` guard.** Every comparison is gated on
`reg_write && rd_addr != 5'd0`. Without it, any instruction with `rd = x0`
(including every bubble) would match a consumer reading `x0` and forward
garbage in place of the architectural zero.

Real example from the test program:

```asm
0x1c:  addi x3, x3, -1        # writes x3
0x20:  beq  x3, x4, done      # reads x3, one instruction later
```

When `beq` is in EX, `addi` is in MEM, so `forward_a = 2'b10`. Its other
operand `x4` has no pending write, so `forward_b = 2'b00`.

And a distance-2 case in the same loop:

```asm
0x10:  add x5, x1, x2         # writes x5
0x14:  add x1, x2, x0
0x18:  add x2, x5, x0         # reads x5, two instructions later
```

When the third `add` is in EX, the first is in WB, so `forward_a = 2'b01`.

### 2. Load-use hazard — solved by stalling

Forwarding cannot fix everything. A load produces its data at the *end* of MEM,
but the instruction directly behind it needs that value at the *start* of its
EX — one cycle earlier. Forwarding moves values across space, not backwards
through time.

```asm
lw  x5, 0(x1)
add x6, x5, x2     # needs x5 one cycle too early
```

`hazard_detection_unit` catches exactly this:

```verilog
assign stall = id_ex_mem_read &&
               (id_ex_rd_addr != 5'd0) &&
               ((id_ex_rd_addr == if_id_rs1_addr) ||
                (id_ex_rd_addr == if_id_rs2_addr));
```

Note which stages it inspects: the **load** is already in ID/EX, and the
**consumer** is still in IF/ID being decoded. On a stall, three things happen
at once:

- PC holds (`pc_next = pc_current`),
- IF/ID holds, re-presenting the same instruction next cycle,
- ID/EX is flushed, injecting a bubble so the load can advance alone.

Freezing two stages and bubbling the third is the whole trick: the consumer
stays put for one cycle, the load moves ahead, and the dependency becomes a
distance-1 forward that the forwarding unit can now handle. Cost: 1 cycle.

### 3. Control hazards — solved by flushing

Branches resolve in EX. By then, two more instructions have been fetched. The
core has no branch predictor, so it implicitly predicts not-taken and pays for
being wrong:

```verilog
wire if_id_flush = take_branch;
wire id_ex_flush = take_branch | stall;
```

On a taken branch, IF/ID and ID/EX are both cleared and the PC is redirected —
killing exactly the two wrong-path instructions. Cost: **2 cycles per taken
branch**. Not-taken branches are free.

Note that `id_ex_flush` serves double duty: `take_branch` for control hazards
and `stall` for the load-use bubble. Both need the same thing — a bubble in
ID/EX — so they share one signal.

---

## The falling-edge register file

This is the design decision most likely to be asked about, because it violates
the project's own "everything is posedge" convention.

**The problem.** In a 5-stage pipeline, a producer in WB and a consumer in ID
occupy the *same cycle* when they are three instructions apart. There is no
forwarding path back into ID — forwarding targets the EX operand muxes. So the
register file itself must deliver the value being written in that very cycle.

**Why posedge writes break.** If the write committed on the rising edge, the
array update and the ID/EX register latching the read result would happen at
the same instant. Which one wins depends on delta-cycle ordering between a
nonblocking array write and a combinational read propagating through. Icarus
and Vivado xsim resolve that ordering differently — *identical RTL, different
results*.

**The fix.** Commit on the falling edge. The write lands half a cycle early, so
the value is already in the array before the next rising edge samples the read.
This is the classic "write in the first half of the cycle, read in the second
half" register file assumed by the standard 5-stage design. It is race-free and
simulator-independent.

Note the read is not "on posedge" — it is combinational
(`assign rs1_data = ...`). The posedge is merely when ID/EX samples it.

**The trade-off, stated honestly.** The write path now only gets half a clock
period, which hurts at synthesis and limits Fmax. Production designs keep
everything posedge and add an **internal bypass mux** instead:

```verilog
assign rs1_data = (reg_write && rd_addr == rs1_addr && rd_addr != 0)
                  ? rd_data : registers[rs1_addr];
```

Same behaviour, no half-cycle penalty. The falling-edge version was chosen here
because it is the textbook construction and keeps the module trivially readable;
the bypass mux is the right answer if this were being taped out.

---

## Worked example: cycle-by-cycle trace

The bundled program computes fib(5) and stores it to `mem[0]`:

```asm
        addi x1, x0, 1     # x1 = 1
        addi x2, x0, 1     # x2 = 1
        addi x3, x0, 3     # loop counter
        addi x4, x0, 0     # constant 0
loop:                      # 0x10
        add  x5, x1, x2    # x5 = x1 + x2
        add  x1, x2, x0    # x1 = x2
        add  x2, x5, x0    # x2 = x5
        addi x3, x3, -1
        beq  x3, x4, done
        jal  x0, loop
done:                      # 0x28
        sw   x2, 0(x0)     # mem[0] = x2
```

Here is the `jal` at `0x24` redirecting at the end of the first iteration.
`(sp)` marks a speculatively fetched instruction on the wrong path:

| Cycle | IF | ID | EX | MEM | WB |
|---:|---|---|---|---|---|
| 10 | `jal @24` | `beq @20` | `addi @1c` | `add @18` | `add @14` |
| 11 | `sw @28` *(sp)* | `jal @24` | `beq @20` | `addi @1c` | `add @18` |
| 12 | `-- @2c` *(sp)* | `sw @28` *(sp)* | **`jal @24`** | `beq @20` | `addi @1c` |
| 13 | `add @10` | *flushed* | *flushed* | `jal @24` | `beq @20` |
| 14 | `add @14` | `add @10` | bubble | bubble | `jal @24` |

At cycle 12 `jal` reaches EX and asserts `take_branch`. On that clock edge:

- `ex_pc_target = 0x10` is loaded into the PC,
- IF/ID is flushed, killing `-- @2c`,
- ID/EX is flushed, killing `sw @28`.

Both wrong-path instructions die, one at each boundary. Cycle 13 fetches the
correct target. The two lost slots are the branch penalty, visible as bubbles
draining through EX and MEM in cycle 14.

This matches the testbench trace exactly — `PC = 0x28` at cycle 11,
`PC = 0x2c` at cycle 12, `PC = 0x10` at cycle 13.

---

## Performance

Measured from the actual simulation run:

| Metric | Value |
|---|---|
| Instructions retired | 22 |
| Issue cycles | 28 |
| Flush bubbles | 6 (3 taken transfers × 2) |
| Load-use stalls | 0 (program has no loads) |
| **CPI** | **28 / 22 ≈ 1.27** |
| Store commits at cycle | 31 (3 further cycles to drain to MEM) |

Every non-ideal cycle is a branch flush. With no taken control transfers the
core sustains CPI = 1.0, since forwarding removes every data stall this program
would otherwise incur.

The obvious next optimisation is not a branch predictor but **moving branch
resolution from EX to ID**. That drops the penalty from 2 cycles to 1 and needs
only a comparator plus an extra forwarding path into ID. A predictor is the
step after that.

---

## Verification coverage

`tb_riscv_top.v` drives a 100 MHz clock, releases the active-low reset after
20 ns, prints a per-cycle trace of the PC, the fetched instruction, `x1`, `x2`,
`x3`, `x5` and `mem[0]`, then asserts `mem[0] == 5` and prints PASS or FAIL.
It uses hierarchical references (`dut.regfile.registers[1]`) to peek inside the
design without adding debug ports to the RTL.

Being precise about what the bundled program actually proves:

| Exercised | Implemented but not exercised |
|---|---|
| `addi`, `add`, `beq` (taken **and** not-taken), `jal`, `sw` | `sub`, `and`, `or`, `slt`, `srl`, `andi`, `ori` |
| EX/MEM forwarding (distance 1) | `lw`, `jalr` |
| MEM/WB forwarding (distance 2) | Load-use stall path |
| Branch flush on 3 taken transfers | Store-data forwarding (`fwd_rs2` → `sw`) |
| Back-to-back dependent ALU ops | |

The loop body is a chain in which every instruction depends on the one before
it, so both forwarding paths are hit on every iteration — that part is well
covered. The gap is loads: with no `lw` in the program, the load-use interlock
is elaborated and simulated but never actually triggered. Closing that gap
needs one more test program, not more RTL.

---

## Known limitations

**1. Only a subset of RV32I is implemented.** No `lui`, `auipc`, `bne`/`blt`/
`bge`/`bltu`/`bgeu`, `slti`, `xori`, `slli`/`srli`/`srai`, `sll`, `sra`, `xor`,
`sltu`, `lb`/`lh`/`lbu`/`lhu`, or `sb`/`sh`. Word-granular memory only.
Unsupported `funct3` values decode to `4'bXXXX` rather than silently behaving
like some other instruction.

**2. No branch prediction.** Static not-taken, 2-cycle penalty per taken branch.

**3. No exceptions, CSRs, interrupts, or privilege modes.**

**4. Memory is unrealistically fast.** Both memories are single-cycle
combinational reads. A real cache miss would need a stall path into EX/MEM and
MEM/WB — which is precisely why those registers already carry tied-off `stall`
ports.

**5. `data_memory` reads return 0 when `mem_read` is low** rather than being
don't-care. Harmless, and it keeps waveforms clean.

---

## Design decisions and trade-offs

A summary of the choices worth defending, with the alternative in each case.

| Decision | Why | Alternative |
|---|---|---|
| Structural top level, one module per block | Each block is separately readable and testable | One behavioural module — shorter, much harder to explain |
| Two-level ALU decode | Keeps the opcode decoder tiny and format-driven | Single flat decoder — wider, duplicates work |
| Separate `alu_op` for R-type and I-type ALU | `funct7` does not exist in I-type; sharing one encoding misdecodes `addi` in the 1024–1055 immediate range | Share `2'b10` and gate the `funct7` test on the opcode — needs an extra port into `alu_control` |
| ALU decode in ID, piped through ID/EX | Shortens the EX critical path | Decode in EX — simpler wiring, slower clock |
| `pc_plus_4` recomputed in ID | Link value must follow the instruction, not the fetch | Pipe IF's value — wrong after a redirect |
| Branch resolved in EX | Reuses the ALU; no extra comparator | Resolve in ID — 1-cycle penalty, needs a comparator and ID forwarding |
| `take_branch` computed, not a control output | Depends on `zero_flag`, a datapath value | PCSrc from control — impossible without predication |
| Falling-edge register file write | Removes a real simulator-dependent race | Internal bypass mux — better Fmax, slightly more logic |
| Uniform stall/flush ports on all four pipeline registers | Read once, understood everywhere; easy to extend | Minimal ports — less code, harder to add memory stalls |
| Flush clears datapath fields too, not just control | Readable waveforms while debugging | Clear control only — strictly sufficient, noisier waveforms |
| `4'bXXXX` on unsupported decode | Fails loudly in simulation | Default to ADD — hides bugs |
| Harvard memory | IF and MEM are active in the same cycle | Unified memory — needs dual ports anyway |
