# Pipeline implementation supplement

This supplements Task5/6; does not redefine completion. Own module
`pipeline_cpu #(RESET_PC=32'hbfc00000, EXCEPTION_PC=32'hbfc00380)`.

## Ports

- clk, rst synchronous active high.
- imem_addr[31:0] output, imem_rdata[31:0] input: combinational read. Instruction
adapter for lab5 synchronous memory is separate integration work.
- dmem_valid, dmem_write outputs; dmem_addr[31:0], dmem_wdata[31:0],
dmem_wstrb[3:0] outputs; dmem_ready and dmem_rdata[31:0] inputs. Exactly one
transaction completes at valid&&ready edge. Hold all request fields while waiting.
Read data is aligned containing word; CPU chooses signed/unsigned byte/half lane.
- hw_irq[5:0] input synchronous.
- trace_valid, trace_pc[31:0], trace_instr[31:0], trace_we, trace_rd[4:0],
trace_wdata[31:0] outputs: one retirement event per completed instruction,
including stores/branches, excluding faulting instructions. Trace must align
with architectural state and not duplicate on stalls.
- trace_mem_we[3:0], trace_mem_addr[31:0], trace_mem_wdata[31:0] accompany retirement.
- exception_valid output pulse plus exception_code[4:0], exception_epc[31:0],
exception_bd outputs for observation.
- cycle_count[31:0], retired_count[31:0], stall_count[31:0] outputs.

## Pipeline and semantics

Five explicit stages IF/ID/EX/MEM/WB with valid/PC/instruction retained. Register
file writes only at retirement. EX/MEM and MEM/WB bypass, load-use stalls, and
store data forwarding. Holds during memory backpressure must not repeat WB,
memory requests, exceptions or side effects. Branches with explicit one delay
slot; resolve once and flush only younger instructions beyond it. Correct branch
operand dependencies and link PC+8. Control transfer inside delay slot may raise
RI deterministically; document this handling of an unpredictable MIPS case.

Implement the single-cycle documented ISA for architectural comparisons. In
addition implement MFC0, MTC0, ERET, SYSCALL/BREAK and precise traps. ADD/ADDI/SUB
overflow traps instead of wrapping; unsigned variants wrap. Instruction fetch
AdEL, load AdEL/store AdES, RI and external/timer interrupt trap to EXCEPTION_PC.
For delay slot exception, EPC points to branch instruction and BD=1.

`rtl/core/cp0.v` already exists and passes its unit checks. Read cp0-contract.md.
CP0 writes and ERET must be serialized/forwarded correctly with MFC0. At an
exception all older instructions complete and no younger register/store side
effects occur. External interrupts must not discard a committed store or save
an EPC that restarts an already completed side effect. A simple precise policy
may defer interrupts to a safe boundary and drain the pipeline; document it.

## Testing evidence

Self-checking directed programs and deterministic random straight-line programs,
independent software expected state/trace, multiple memory wait patterns,
branch+dependent operands, load/use, both sources matching, stores, zero target,
back-to-back control flow separated by delay slots, zero/negative immediates,
reset. Functional exceptions verify EPC/BD, cause, handler, MFC0/MTC0/ERET, resume,
priority and forbidden younger store. Record per-stage trace for teaching media.
Mutate one expected result and prove the test harness rejects it, then restore.

Do not claim all C07/C08/C09 complete from the initial unit suite; supplied lab5
tests and SoC/hardware integration are additional acceptance items.
