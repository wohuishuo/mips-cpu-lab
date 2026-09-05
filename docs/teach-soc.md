# Supplied lab5 synchronous SoC replay

The owned `mycpu_top` adapter runs the five-stage `pipeline_cpu` inside the
**unmodified locally supplied `teach_soc_top`**, with its actual `bridge_1x2`
and `confreg`. XSim 2019.2 verified the supplied ROM against every row of its
golden register-write trace. This is a simulation compatibility integration;
the independent board SoC must have its own synthesis and timing evidence.

## Reproduce

The original course package must be supplied locally. Its source, ROM and golden
trace are not redistributed in this repository. Set `BITMIPS_LAB5` to the `lab5`
directory and `VIVADO_BIN` to a Vivado directory containing `xvlog.bat`,
`xelab.bat`, and `xsim.bat`. Defaults match the local verification environment.

```powershell
$env:BITMIPS_LAB5 = 'D:/cpu/bitmips_experiments-master/bitmips_experiments-master/lab5'
$env:VIVADO_BIN = 'E:/Xilinx/Vivado/2019.2/bin'
python tests/run_teach_soc.py
python tests/run_teach_soc.py --mutate wrong-golden
python tests/run_teach_soc.py --mutate truncated-golden
python tests/run_teach_soc.py --mutate extra-golden
python tests/run_teach_soc.py --mutate missing-golden
python tests/run_teach_soc.py --mutate timeout
```

Normal replay exits 0; each mutation deliberately exits 1. Logs, generated ROM,
temporary golden files and retirement CSVs are isolated under ignored
`build/teach_soc/normal` or the named mutation directory. The original course
files are read only. `result.json` is written only after successful completion;
the runner rejects a tool error, FAIL/FATAL/ERROR text, missing/duplicate pass
marker, or a host timeout. The model itself rejects missing, malformed, shortened
or extra golden data. The supplied COE contains 46,951 newline-separated hex
words, without the conventional comma separators or final semicolon. Conversion
validates each word and pads the 65,536-word instruction array with zeros.

## Adapter timing and memory model

`rtl/integration/teach_mycpu_top.v` preserves the supplied top's CPU ports,
including active-low reset and debug WB signals. It strips the upper three
virtual address bits for the physical SRAM/bridge bus. Thus `0xbfaf8000` reaches
the actual bridge's `0x1faf0000` configuration region, while debug PCs retain
their original virtual values.

The existing CPU consumes combinational instructions and a valid/ready data bus.
For this lab simulation, the adapter drives its clock from `~soc_clk`; the
supplied SRAM, bridge and confreg remain on rising `soc_clk`. Requests settle
after one falling edge, synchronous memory/bridge returns data after the next
rising edge, and the CPU consumes it at the following falling edge. Data ready
is asserted while out of reset. Each MEM request spans one SRAM rising edge,
including consecutive requests; the store scoreboard checks actual bus writes
against their later retirement records. Debug WB is sampled immediately before
the falling edge's nonblocking updates.

This arrangement requires the half-cycle setup paths implied above. It is **not
a validated FPGA clocking scheme**, a variable-latency memory adapter, or evidence
that this CPU directly supports an arbitrary same-edge synchronous SRAM. There
are no clock constraints, PLL timing, place/route or board-frequency claims here.
The test releases reset just after a falling edge so the first instruction has
a rising-edge memory access before CPU consumption. Reset must cover both clock
phases; an already performed rising-edge store cannot be undone by a later reset.

`tests/teach_memory_models.sv` supplies original behavioral substitutes only for
the missing generated IP: a pass-through `clk_pll`, 64K-word synchronous
`inst_ram`, and 4K-word synchronous `data_ram`. Both memories retain their output
when disabled and implement byte strobes with read-before-write behavior. Data
RAM starts at zero and persists across reset. These are functional substitutes,
not verified reproductions of vendor primitive timing or initialization options.
The original top, bridge and confreg compile directly from their local paths;
they are never replaced with a simplified MMIO model. The original `.v` files
compile as Verilog because `int` is a legal Verilog port name. The adapter uses
its escaped spelling, and owned testbench/model files compile as SystemVerilog.

## Observed result and checks

```text
PASS TEACH_SOC rows=28970 cycles=49959 stores=420 display=13000013 led=0f enabled_points=19 reset_cancel=1 checked_tail=32
```

After a preliminary reset-cancellation probe, the complete restart consumes all
28,970 golden rows in 49,928 CPU clocks. The reported 49,959 clocks includes a
32-clock completion observation window, whose first clock is the completion
clock itself. All 420 actual SRAM/MMIO stores match one ordered retirement each.
The initial probe asserts reset after the first store request is presented but
before SRAM can accept it; no bus store occurs, debug/request outputs stay
inactive in reset, confreg resets, and the full program then restarts correctly.

Completion requires PC `0xbfc00100`, the final golden write, LED `0x0f`, and
confreg numeric display `0x13000013`. The latter encodes the program's final test
number and score, both 19. The actual `test_finish` loop keeps incrementing `t0`;
after the golden endpoint, the scoreboard independently checks its repeating
ADDIU / branch / NOP instruction sequence, exact register values and absence of
further memory writes. Unexpected additional writes fail; the legitimate loop
is not silently discarded. Unexpected CPU exceptions also fail this image replay.

| Negative test | Observed rejection |
|---|---|
| Wrong first golden value | Row 0, actual `ffffffff`, expected `fffffffe` |
| Missing final golden row | Row 28,969, scan result -1 |
| Appended golden row | Unconsumed tail, scan result 1 |
| Missing runtime golden file | Missing golden trace at time zero |
| 10-clock limit | Timeout at PC `bfc00124` |

## Exact supplied coverage and provenance

The startup source defines `TEST_NUM 19 // 89`. Removing block comments leaves
these 19 enabled calls, also recorded in `result.json`:

| Original point IDs | Enabled functions |
|---|---|
| 1, 4, 5, 6, 7, 8 | LUI, BEQ, BNE, LW, OR, SLT |
| 11, 12, 13, 14, 15 | SLL, SW, J, JAL, JR |
| 21, 22, 23, 25 | ADD, ADDI, SUB, SLTU |
| 29, 30, 31, 35 | ORI, XOR, XORI, SRL |

The other named functional calls and the supplied exception handler are disabled
in the startup source. Passing this supplied image does not establish all 89
points, HI/LO/multiply/divide, unaligned merge loads, CP0 exception suites, MMU/TLB,
cache integration, or complete MIPS32 compatibility. The separately documented
owned pipeline suite establishes its own directed/random and exception coverage.
This runner uses the supplied prebuilt image; it does not claim to rebuild it
with a MIPS GNU toolchain or prove correspondence to a fresh source build.

SHA-256 hashes of the exact local supplied inputs:

| Input (relative to lab5) | SHA-256 |
|---|---|
| `teach_soft/inst_ram.coe` | `c9dcea20a6dd95fdd0c3d7f28ed6bebbcfcc86db9ab8d70ed46257a136c934b9` |
| `golden_trace.txt` | `1047fc04c8408cd2eafc649f9f7f6898f47afba34743a1db7009d09e5039d6ab` |
| `teach_soc/teach_soc.srcs/sources_1/new/teach_soc_top.v` | `c01b21be99e45811d040f0e70b80561bbe4cb42bdbbaaf6097055ea8d40dff0f` |
| `teach_soc/teach_soc.srcs/sources_1/new/bridge/bridge_1x2.v` | `0ae93918e27ae69ee07621929154064babe6992a8423b765e913176233da69fb` |
| `teach_soc/teach_soc.srcs/sources_1/new/confreg/confeg.v` | `ed69b7540571b58ff097b55e79a21f24bda8cb294e97ac8e6a552bd10b3aff79` |
| `teach_soft/func_test/start.S` | `7330b701bea26a9cadb7ad537219a99173e88f069b0d58a2f7a61b15885aa3a9` |
