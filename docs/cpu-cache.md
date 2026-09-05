# Pipeline and data-cache joint verification

`rtl/integration/cached_cpu.v` connects the real five-stage `pipeline_cpu` to
`data_cache` through the documented ready/valid port. The wrapper exposes a
separate uncached MMIO port for addresses matching `MMIO_BASE`/`MMIO_MASK`
(default `0xffff0000` through `0xffffffff`). Its backing-memory port carries
cache refill/writeback word transactions only. Instruction memory remains
combinational. CPU exceptions, retirement trace, IRQ input and counters are
passed through. This wrapper does not add a memory controller or peripherals.

A waiting memory-stage request freezes the upstream pipeline. Address decoding
therefore remains stable until completion. The selected cache or MMIO ready
signal completes the request on a rising edge; MMIO valid is never presented
to the cache. Peripherals must apply writes only on `mmio_valid && mmio_ready`.
MMIO address/data/direction are meaningful only while valid is asserted.

## Program and independent oracles

`software/cache_joint.S` is a project-owned, explicitly encoded `.word` fixture
with instruction comments and byte PCs. `software/cache_joint.hex` contains the
same instructions. This test does not claim a MARS assembly run. The runner
regenerates both fixtures reproducibly from the program builder.

The actual CPU executes a loop generating and storing F0 through F19 at
`0x1000`; it immediately reloads each result and uses load-use forwarding for
the next value. The expected sequence is independently checked against the
Python Fibonacci recurrence and ends at 4181. Other instructions exercise:

- All four SB lanes, both SH lanes, signed/unsigned byte and halfword loads;
  persisted words must be `0x93929190` and `0x81fe81fe`.
- Successful ADDI, ADD and SUB, complementing the overflow exception tests.
- Eighteen writes rotating through three same-set tags at `0x2000`, `0x2100`
  and `0x2200`, forcing repeated dirty evictions in a two-way cache.
- 38 uncached MMIO stores, including stores following cache misses, plus an
  uncached load whose result participates in dependent arithmetic.
- Clean load sweeps over `0x4000..0x40f8` and `0x5000..0x50f8`; these replace
  both ways of every set, persisting every dirty line before comparison.

The independent Python interpreter decodes the instruction words and computes
391 complete retirement records and 198 ordered CPU data requests. The HDL
checks every retirement PC/instruction, register write and byte-strobed store,
and checks every data handshake and load word. Neither expected memory nor
expected register values are taken from RTL state or its retirement trace.

A separate Python LRU list model predicts exact hits, misses and dirty line
writebacks from the architectural request sequence. The final comparison
checks all 8192 words of backing RAM, after the eviction sweeps, against the
architectural memory oracle. The generator also asserts no dirty entries
remain in its independent cache model. Backing reads must equal misses times
words per line; backing writes must equal writebacks times words per line.
Each CPU, backing-memory and MMIO request must remain stable while stalled.
Unexpected exceptions, extra/missing completions, malformed backing strobes,
out-of-range backing addresses and simultaneous cache/MMIO activity fail.

## Reproduce

```powershell
python tests/run_cpu_cache.py
python tests/run_cpu_cache.py --mutate  # intentionally exits 1
python tests/run_cpu_cache.py           # restores all generated expectations
```

Vivado Simulator defaults to `E:/Xilinx/Vivado/2019.2/bin`; `VIVADO_BIN` can
override it. All simulator files and oracles are in `build/cpu-cache`. The
runner rejects FAIL/FATAL/ERROR text even if a tool exits zero and requires
exactly one pass marker per cache geometry. `--mutate` changes the first
expected register result from `0xffff0000` to `0xffff0001`; the observed run
failed at retirement zero and returned exit status 1. A restored full run
then passed. The initial missing-wrapper failure is preserved separately.

Each geometry runs three memory modes: continuously ready, seeded xorshift32
random readiness (seed `0xc01dcafe`, nominal backing readiness 1/4), and one
ready clock in thirteen. MMIO is always ready in mode 0 and independently
randomly ready in modes 1 and 2. The continuous-ready mode checks adjacent
backing-memory completions, covering transfers without a valid-low gap.

Observed XSim 2019.2 results on 2026-09-05:

| Sets / words per line | Mode | Cycles | Stalls | Hits | Misses | Dirty writebacks |
|---|---|---:|---:|---:|---:|---:|
| 16 / 4 | Continuous ready | 1155 | 740 | 103 | 56 | 24 |
| 16 / 4 | Random ready | 2285 | 1870 | 103 | 56 | 24 |
| 16 / 4 | 1/13 ready | 4894 | 4479 | 103 | 56 | 24 |
| 4 / 2 | Continuous ready | 1079 | 664 | 66 | 93 | 29 |
| 4 / 2 | Random ready | 2097 | 1682 | 66 | 93 | 29 |
| 4 / 2 | 1/13 ready | 3919 | 3504 | 66 | 93 | 29 |

Every row has 391 retirements, 198 CPU data completions, and exactly 38 MMIO
stores. Default geometry has 224 refill-word reads and 96 writeback-word
writes; small geometry has 186 and 58 respectively. The continuously ready
runs observed 264 and 151 adjacent backing completions. Different line sizes
change this workload's cycle counts; these are not general performance claims.

`regression.log` and `mutation.log` retain simulator output. The per-geometry
`cache_retirements_*.csv` and `cache_bus_*.csv` contain actual sampled signal
data for teaching visuals. `oracle_*.json` records expected counts.

This establishes joint CPU/cache/MMIO simulation for the tested workload and
geometries. It does not establish cache-enabled FPGA operation, cache flush
instructions, DMA coherence, an instruction cache, bus faults, or CP0/interrupt
behavior during cache misses. Reset during active refill/writeback remains
covered by the standalone cache suite; it is not an additional claim of this
joint regression. The board SoC and full C10 course acceptance remain separate
evidence decisions.
