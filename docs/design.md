# MIPS CPU Lab Design

## Authorized outcome

Complete C01–C12 from the local capability assessment, test each capability,
program the connected FPGA after simulation and timing checks, create attractive
teaching visuals and recorded demonstrations with crops, and publish a public
GitHub repository with accurate descriptions and reproducible evidence.
The user explicitly authorized autonomous execution and publication.

## Architecture

Develop an understandable single-cycle reference CPU and a real five-stage MIPS
pipeline. Keep unmodified upstream candidates outside the public source tree;
reuse attributed, compatible parts only after their correctness is demonstrated.
Independent modules provide a write-back two-way data cache, UART, multiplexed
seven-segment display, GPIO and a buzzer peripheral. A SoC maps program-visible
peripherals and exposes trace/results over UART for automated board verification.

Primary clock: actual board 100MHz oscillator, confirmed against vendor documents
and hardware identity before pin assignment. The implemented single-cycle board
SoC divides this to 10MHz, with measured timing in evidence/board-timing.rpt.
Target part: xc7a35tcsg324-1; JTAG confirmed the XC7A35T die.

## ISA and trace

MIPS 32-bit little endian, byte addresses, register zero immutable. Normal reset
PC is parameterized, default 0xbfc00000; standalone tests may choose 0. Implement
the course ten instructions plus practical MIPS arithmetic, logical, shift,
load/store and control-flow instructions required by supplied programs.
Explicit branch delay slot semantics: the instruction immediately following a
taken branch executes once. JAL/JALR link is branch PC+8. Unsupported instructions
must not silently acquire side effects. Pipeline extensions implement CP0 and
precise exceptions including instruction/data alignment, RI, syscall, break,
overflow, hardware interrupt, eret; delay-slot exceptions record BD and branch EPC.

Retirement trace fields: valid, PC, instruction, register write enable/address/data,
and memory write address/data/strobes. These support independent reference checks.
Do not declare full MIPS32 conformance or all 89 upstream functional points without
corresponding coverage. C08 must include supplied tests adapted transparently to
the actually documented subset, plus independent randomized/directed programs.

## Independent RTL module contracts

All new independent peripherals/cache use `clk`, synchronous active-high `rst`.
Each test starts reset and also checks reset during activity where relevant.

### Single-cycle core

`single_cycle_cpu #(RESET_PC=32'hbfc00000)` has clk, rst, combinational imem input
`imem_rdata[31:0]` and output `imem_addr[31:0]`; data interface outputs
`dmem_addr[31:0]`, `dmem_wdata[31:0]`, `dmem_wstrb[3:0]`, input `dmem_rdata[31:0]`.
Trace outputs `trace_valid`, `trace_pc[31:0]`, `trace_instr[31:0]`, `trace_we`,
`trace_rd[4:0]`, `trace_wdata[31:0]`; output `illegal`. Word memories are zero-cycle
read for this core; stores take effect on rising edge. Trace samples on rising
edge after reset release correspond to the instruction whose side effects occur.
No implicit reliance on original XPR, IP or original user-machine paths.

### Cache

`data_cache #(SETS=16, WORDS_PER_LINE=4)` is 2-way, write-back, write-allocate;
power-of-two parameters. CPU request ports: `cpu_valid`, `cpu_write`,
`cpu_addr[31:0]`, `cpu_wdata[31:0]`, `cpu_wstrb[3:0]`, output `cpu_ready`,
`cpu_rdata[31:0]`. A request is completed exactly on a rising edge with valid&&ready;
requester holds request until then. No duplicate completion or write.
Backing memory: outputs `mem_valid`, `mem_write`, `mem_addr[31:0]`,
`mem_wdata[31:0]`, `mem_wstrb[3:0]`, inputs `mem_ready`, `mem_rdata[31:0]`, with
identical completion semantics and word transactions. Counters `hit_count`,
`miss_count`, `writeback_count` are 32 bits. Backing memory owns contents; reset
invalidates cache and cancels transactions. Flush is not required for initial
interface, but tests must force dirty eviction to verify persistence.

### UART and board-independent peripherals

`uart_tx #(CLOCK_HZ=100000000, BAUD=115200)` input tx_valid/tx_data[7:0], output
tx_ready/tx; accepted byte valid&&ready at rising edge; 8N1, idle high.
`uart_rx` same parameters: input rx, output rx_valid (one pulse)/rx_data[7:0],
frame_error (one pulse on bad stop). Synchronize asynchronous RX.
`seven_segment #(CLOCK_HZ=100000000,SCAN_HZ=1000)` input value[31:0], output
digit_n[7:0], segment_n[7:0]; active-low normalized logical outputs, pin mapping
belongs to board top, not the reusable driver. Show 8 hex digits.
`buzzer #(CLOCK_HZ=100000000)` input enable, frequency_hz[15:0], output wave;
disabled output 0. Demonstration uses a short notification sequence controlled
through MMIO/UART. C11 selects the on-board buzzer extension; VGA remains out of
scope per prior user direction unless actual display requirements arise.

## Evidence and teaching deliverables

Maintain `docs/ledger.md` and machine-readable capability statuses. A capability
is complete only when its original requested software/hardware evidence exists.
Capture actual simulations, logs and board telemetry; label explanatory diagrams
and rendered animations as such, never as physical board photographs.
Create original diagrams using our signal names and cite local course PDF title
and page numbers. Do not publish full unlicensed teacher PDFs or textbook scans.
Create a polished narrated/subtitled demo video, screenshots/crops, diagrams,
Chinese teaching/report documents, public README and reproduction commands.

## Execution loops

For each module: failing test -> RTL -> passing directed/random tests -> review.
For each CPU: instruction matrix -> trace comparison -> hazards/exceptions -> SoC.
For hardware: identify -> new verified XDC -> synth/route -> timing -> program ->
UART proof and observable peripherals -> record demo.
For media: verified results -> storyboard -> render/record -> visually inspect ->
publish only results whose evidence is present. No fabricated pass indicators.
