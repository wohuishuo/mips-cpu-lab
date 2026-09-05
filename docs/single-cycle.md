# Single-cycle MIPS teaching reference

`rtl/core/single_cycle_cpu.v` implements an original, independently written
32-bit little-endian core. It runs one instruction per rising clock edge with
combinational instruction/data reads. The checked-in demonstration writes all
twelve Fibonacci words `0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89` to byte addresses
`0x00` through `0x2c`.

## Interface and integration

The ports match `docs/design.md`. `rst` is synchronous and active high. Reset
sets PC to `RESET_PC` (default `0xbfc00000`), clears every register, and cancels
any pending branch redirect. Register `$zero` always reads zero and never writes.
Instruction/data memories must provide a zero-cycle combinational read; this
core has no ready/stall handshake and cannot directly use a variable-latency cache.

`dmem_addr` is a **byte address**. The memory returns the aligned 32-bit word
containing that address; the core selects/sign-extends the requested lane.
Stores present data shifted into the selected byte lanes and four byte write
enables. The memory applies enabled lanes on the rising edge. Disabled lanes of
`dmem_wdata` are unspecified and must be ignored. For example, SH of `0x5678` at
address `0x102` presents strobes `1100` and data `0x56780000`.

`trace_valid`, `trace_pc`, `trace_instr`, `trace_we`, `trace_rd`, `trace_wdata`
are combinational descriptions of the current instruction. Sample them **at
the rising edge before nonblocking assignments update PC/registers**. At that
edge, the same register/store side effects occur. `trace_we` is suppressed for
register zero, reset, and rejected instructions. When `trace_we=0`, destination
and register data are not meaningful. Store trace data comes directly from
the data interface; the fixed core contract has no duplicate memory trace ports.

## Supported instructions

| Group | Instructions |
|---|---|
| Wrapping integer arithmetic | ADD, ADDU, SUB, SUBU, ADDI, ADDIU |
| Comparison | SLT, SLTU, SLTI, SLTIU |
| Logic and upper immediate | AND, OR, XOR, NOR, ANDI, ORI, XORI, LUI |
| Immediate and variable shifts | SLL, SRL, SRA, SLLV, SRLV, SRAV |
| Conditional branches | BEQ, BNE, BLEZ, BGTZ, BLTZ, BGEZ, BLTZAL, BGEZAL |
| Jumps | J, JAL, JR, JALR |
| Loads | LB, LBU, LH, LHU, LW |
| Stores | SB, SH, SW |

This is a 44-instruction practical subset; NOP is the standard SLL encoding.
Immediate arithmetic/SLTIU sign-extend the 16-bit immediate; logical immediates
zero-extend it. Variable shifts use only the low five shift-count bits.

Every supported branch or jump executes its following instruction once as a
delay slot. A taken branch targets `branch_PC + 4 + (sign_extended_offset << 2)`;
an untaken branch continues at `branch_PC + 8` after the slot. JAL/JALR and
REGIMM link variants write `branch_PC + 8`; BLTZAL/BGEZAL write the link even
when their condition is false. J/JAL take the upper four destination bits from
`PC + 4`. JALR reads the old source before writing the destination, including
when `rs == rd`.

## Explicit limitations

ADD, ADDI and SUB produce wrapping results in this reference: **overflow traps
are not implemented**. This differs from trapping MIPS32 behavior. HI/LO,
multiply/divide, CP0, syscall/break traps, eret, interrupts, branch-likely,
unaligned merge loads/stores and atomic instructions are unsupported. Precise
exceptions are the separate pipeline/CP0 work.

`illegal` marks unsupported or reserved encodings, unaligned word/halfword
accesses, unaligned instruction/JR/JALR addresses, and a control transfer in a
delay slot. The latter is architecturally unpredictable and this reference
rejects it deterministically. Rejected instructions cause no register/store or
new branch side effects, remain visible as `trace_valid=1`, and advance normally
(or complete the already pending delay-slot redirect). No trap vector is entered.
Misaligned JR/JALR is rejected at the jump instruction. This behavior must not
be confused with the later precise-exception CPU.

## Reproduce verification

From the repository root, run:

```powershell
python tests/run_single_cycle.py
```

The runner uses `E:/Xilinx/Vivado/2019.2/bin` by default; set `VIVADO_BIN` to
another installation's `bin` directory. It runs `xvlog --work xil_defaultlib
--sv`, `xelab`, and `xsim -runall` in `build/single_cycle`, avoiding non-ASCII
tool working directories. Keep the repository/build path ASCII with XSim 2019.2.
It rejects any FAIL/FATAL/ERROR marker and requires exactly one completion PASS,
because a simulator process exit code alone does not establish test success.

The self-checking testbench checks 64 deterministic operand pairs, all 32 shift
counts, signed boundaries/overflow wrapping, zero writes, signed and unsigned
immediates, negative offsets, all store lanes, positive/negative load extension,
alignment rejection, reserved instructions, every branch condition both ways,
delay-slot writes, backward branches, links, JALR source/destination overlap,
reset during a pending redirect, and a JAL across a 256 MiB address boundary.
It drives explicit expected register results at retirement and checks the
Fibonacci ROM as a complete program with all twelve stores and final words.

Successful execution creates `build/single_cycle/regression.log` and
`build/single_cycle/retirements.csv` (PC, instruction, register write,
memory write fields and rejection flag). Initial missing-core evidence is
recorded separately as `build/single_cycle/red-absent-core.log` when developing.

`software/singlecycle_fibonacci.S` is the original source at origin zero;
the corresponding `.hex` contains instruction words for `$readmemh` and
`singlecycle_fibonacci_expected.hex` lists the twelve expected memory words.
The test checks arrival at `done` at PC `0x3c` and two repetitions of its terminal
J/NOP loop.

These directed and deterministic checks are project-owned coverage. They do
not establish full MIPS32 compliance, completion of 89 official functional test
points, physical FPGA operation, or pipeline/cache correctness.
