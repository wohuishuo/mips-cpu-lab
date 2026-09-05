# Single-cycle SoC and UART protocol

The original MARS-assembled `software/board_demo.S` runs from 0x00400000.
It stores 12 Fibonacci words starting at 0x10010000, then displays 89 (hex 59).
Switches occupy the upper displayed halfword; LEDs show switches XOR 0x59.
The CPU executes the MMIO loads and stores; they are not fabricated host values.

RAM is 1024 little-endian words, initialized by software where used. It is not
cleared by CPU reset. ROM is 1024 words produced by `build_board_program.py`.
Unmapped reads return zero. This SoC's RAM read is combinational, matching the
single-cycle contract. The later pipelined/cache SoC uses a separate handshake.

| Address | Meaning |
|---|---|
| 0x1f000000 | synchronized switches, read only |
| 0x1f000004 | CPU LED value, low byte |
| 0x1f000008 | eight hex digits |
| 0x1f00000c | bit0: continuous 2kHz buzzer enable |
| 0x1f00001c | CPU cycles since reset, read only |
| 0x1f000020 | bit0: software completion flag |

UART control is a separate reusable module: ASCII `0` turns LEDs off, `1` on,
`a` restores CPU LED control, `b` plays a half-second beep, `r` resets the CPU.
`?` atomically snapshots 40 response bytes: ASCII MCPU, then nine little-endian
32-bit values: status, current fetch PC, the observed last value stored to RAM
word 11, cycles, RAM store count, display, GPIO (switches in bits15:8 and driven
LEDs in7:0), retired count, combined CPU illegal-instruction and UART frame-error
count. The telemetry result is captured from the store; it is not a fresh RAM
read. The CPU's displayed result still depends on its real RAM load. Status bit0
is done, bit1 indicates a CPU illegal instruction. Requests during a response are
dropped; the host must wait for all40 bytes before polling again. Counters wrap
at32 bits.

Board CPU/peripheral clock is10MHz derived from the documented100MHz oscillator
using a divided register routed through BUFG. Constraints declare the generated
clock; implementation checks both setup and hold before bitstream generation.
External reset asserts asynchronously into a three-stage reset synchronizer;
switches and UART RX each have input synchronization. Physical active-high
display outputs invert the normalized active-low driver signals.

`tests/run_soc.py` validates actual serialized packet bits, CPU/MMIO Fibonacci,
the documented MMIO page boundary, switch changes, LED overrides, beep
trigger, and restart reset/clear/recomputation. `scripts/board_test.py` performs
the same UART exchange on the physical COM port and bounds the post-reset cycle
age using measured host time, which remains valid across counter wrap. Its report
explicitly distinguishes telemetry from photographic observation of LEDs and
digits. A board build removes prior success evidence at entry and records the
generated bitstream's SHA-256 only after timing checks and bitstream generation;
programming requires the marker hash to match the selected bitstream.
