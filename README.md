# RISC-V RV32I Single-Cycle CPU

A single-cycle RV32I implementation in Verilog, with a verified test program.

## Files

| File | Purpose |
|---|---|
| `program_counter.v`     | PC register, advances on clock |
| `instruction_memory.v`  | ROM, preloaded from `program.hex` |
| `register_file.v`       | 32 GPRs, async read, sync write, x0 hardwired |
| `immediate_generator.v` | Sign-extends I/S/B/J-type immediates |
| `alu.v`                 | 6 ops: ADD, SUB, AND, OR, SLT, SRL + zero flag |
| `alu_control.v`         | Two-level decode from `alu_op` + `funct3`/`funct7` |
| `data_memory.v`         | RAM, async read, sync write |
| `control_unit.v`        | Decodes opcode, emits all control signals |
| `riscv_top.v`           | Structural top-level wiring |
| `tb_riscv_top.v`        | Testbench with cycle-by-cycle trace and PASS/FAIL |
| `program.hex`           | Test program: computes fib(5) |
| `assemble.py`           | Python encoder used to generate `program.hex` |

## Supported instructions

R-type: `add, sub, and, or, slt, srl`
I-type ALU: `addi, andi, ori`
Load: `lw`
Store: `sw`
Branch: `beq`
Jump: `jal, jalr`

## Simulating with iverilog

```bash
iverilog -o sim *.v
vvp sim
```

Expected last line:
```
PASS: mem[0] = 5 (expected 5 = fib(5))
```

## Loading into Vivado

1. Create a new RTL Project, target any FPGA part (e.g., Artix-7).
2. Add all `.v` files as design sources, except `tb_riscv_top.v`.
3. Add `tb_riscv_top.v` as a simulation source.
4. Add `program.hex` to the project (it must be in the run directory at simulation time).
5. Run Behavioral Simulation. Expected output in the Tcl console: `PASS: mem[0] = 5`.

## Test program (fib(5))

```
addi x1, x0, 1     # x1 = 1
addi x2, x0, 1     # x2 = 1
addi x3, x0, 3     # loop counter
addi x4, x0, 0     # constant 0
loop:
add  x5, x1, x2    # x5 = x1 + x2
add  x1, x2, x0    # x1 = x2
add  x2, x5, x0    # x2 = x5
addi x3, x3, -1
beq  x3, x4, done
jal  x0, loop
done:
sw   x2, 0(x0)     # mem[0] = x2
```

## Architecture notes

- **Harvard memory** — separate instruction and data memory, required for single-cycle.
- **Rising-edge synchronous state** — PC, register file writes, data memory writes all on `posedge clk`.
- **Combinational reads** — register file and data memory reads are combinational so the datapath gets values within the cycle.
- **Two-level ALU decoding** — main control emits a 2-bit `ALUOp` hint, ALU control block uses `funct3`/`funct7` for the final operation.
- **`PCSrc` is computed**, not a direct control output: `(Branch & zero_flag) | Jump`, with `jalr` selecting the ALU result instead of `PC+imm`.
- **Three-way write-back mux**: ALU result, memory data, or PC+4 (for `jal`/`jalr` link).
# Verilog-Implementation-of-RISC-V-Pipelined-Processor
