# Five-stage MIPS pipeline

`rtl/core/pipeline_cpu.v` implements the interface in `pipeline-contract.md`.
Instruction memory is combinational; data memory completes exactly once on a
rising edge with `dmem_valid && dmem_ready`. All addresses are byte addresses,
little endian. Read data is the aligned containing word. Reset is synchronous
and active high, with default PC `0xbfc00000` and exception PC `0xbfc00380`.

## Stages and dependencies

IF holds `if_pc`; its combinational instruction is `if_instr`. ID, EX, MEM and
WB each retain valid, PC and instruction. These names are deliberately visible
in simulation for teaching traces. EX reads the register file and bypasses the
newest applicable result from MEM, then WB. Both operands, including store data
and branch comparisons, use this path. Loads introduce one dependency bubble.
The source matcher conservatively includes unused instruction fields, so some
unnecessary bubbles are possible. A waiting MEM transaction freezes IF/ID/EX/MEM;
WB drains once and clears its valid bit. Register writes occur only at WB.

Branches resolve in EX. ID becomes the one delay slot, receives the branch PC
and BD metadata, and IF restarts at the taken target or PC+8. This deliberately
inserts a redirect bubble. JAL/JALR and REGIMM links use PC+8; REGIMM links write
even when untaken. A control transfer or ERET in a delay slot raises RI.
Unaligned JR/JALR destinations execute the delay slot, then raise instruction
AdEL at the unaligned target address.

## Precise exceptions and CP0

The 44-instruction single-cycle subset is implemented, with ADD/ADDI/SUB changed
to trap on signed overflow. MFC0, MTC0, ERET, SYSCALL and BREAK are added.
Unsupported/reserved encodings raise RI. Misaligned instruction, load and store
addresses raise AdEL/AdES. CP0 operations serialize against older instructions;
younger instructions wait until CP0 retirement. MFC0 samples its register in EX
(therefore Count is the EX-time value). MTC0 and ERET update CP0 at WB.

A synchronous EX fault suppresses the instruction's writes and memory request,
flushes younger instructions, and carries the fault through MEM/WB. Older MEM
requests must complete first. Exception entry occurs once at WB and redirects
fetch to the handler. Delay-slot EPC is the branch PC and BD is one. The shared
CP0 preserves the first EPC/BD while EXL is set; this CPU has no nested exception
stack, TLB, or operating-system compatibility claim.

Interrupts are sampled at a non-delay-slot EX boundary and replace that
uncommitted instruction with an interrupt event. Synchronous faults take
priority. If an older MEM transaction is waiting, EX cannot advance until that
transaction completes. The older store is thus never restarted, and ERET resumes
the interrupted instruction from its saved EPC. Interrupts during a delay slot
wait until the next non-delay instruction. External and CP0 timer interrupt
sources share this policy.

## Trace and counters

Sample trace and exception outputs at the rising edge before nonblocking
updates. WB produces one `trace_valid` event per completed instruction, including
stores, branches, MTC0 and ERET; faulting instructions have no retirement event.
Register data is meaningful when `trace_we` is set. Store trace fields describe
the transaction completed in MEM on the preceding rising edge; stores are
irrevocable at their MEM handshake, and younger exceptions drain behind them.
Other instructions have zero `trace_mem_we`. Reset suppresses trace and requests.

`cycle_count` counts non-reset clocks. `retired_count` counts `trace_valid`
events. `stall_count` counts clocks with memory backpressure, a dependency or
serialization stall, or an exception drain. Branch redirect bubbles are not
counted as stalls. All counters wrap at 32 bits.

## Reproduce and evidence

```powershell
python tests/run_pipeline.py
python tests/run_pipeline.py --mutate  # intentionally exits 1
python tests/run_pipeline.py           # restores generated expectations
```

The runner uses `VIVADO_BIN`, default `E:/Xilinx/Vivado/2019.2/bin`, and rejects
FAIL/FATAL/ERROR text even if XSim exits zero. Exactly one completion marker is
required. All outputs stay in `build/pipeline`.

The Python interpreter generates a seeded (`0x5A17`) program and independently
computes 494 retirement records. The RTL compares PC, instruction, register
writes and byte-strobed stores, under always-ready, 2/7 ready, and 1/13 ready
memory patterns. Checks cover random arithmetic/logic, all shift amounts,
variable shifts, load-use and both-source forwarding, store lanes, signed and
unsigned loads, branch dependencies, forward/backward/zero targets, delay slots,
links, JALR source/destination overlap and register zero. Additional programs
exercise 13 synchronous exception cases with actual MFC0/MTC0/ERET handlers,
including BD, BadVAddr, overflow, RI, syscall/break, fetch/data alignment,
synchronous-fault priority over IRQ and forbidden younger stores. Three IRQ
programs cover a waiting older store, delay-slot deferral and timer interrupt;
all 20 stores in each must occur exactly once. Reset cancels an unaccepted store
and clears architectural state before successful restart.

Observed reference-program results on XSim 2019.2:

| Memory pattern | Retirements | Cycles | Stall clocks |
|---|---:|---:|---:|
| Always ready | 494 | 542 | 21 |
| Two clocks per seven | 494 | 602 | 81 |
| One clock per thirteen | 494 | 1051 | 530 |

`regression.log` contains tool output and completion; `mutation.log` records
the deliberately wrong first expected result (7 changed to 6) being rejected.
`pipeline_stages.csv` records all five stages each clock and memory handshake;
`pipeline_retirements.csv` records retirement events for media and inspection.
The initial absent-core failure is `build/pipeline-red.log`.

This project-owned regression establishes the documented tested subset. It does
not establish all 89 supplied functional test points, full MIPS32 compliance,
cache/SoC integration, FPGA timing, or board operation. Those remain separate
acceptance work. HI/LO, multiply/divide, branch-likely, unaligned merge accesses,
atomics and MMU/TLB are unsupported and raise RI where their encodings occur.
