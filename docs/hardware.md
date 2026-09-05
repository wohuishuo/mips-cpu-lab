# EES-338 hardware record

2026-09-05 discovery, before programming:

- Vivado Hardware Manager opened the connected target successfully.
- JTAG device: `xc7a35t_0`; IDCODE `0362D093`.
- Windows UART: COM6 through an FTDI dual-interface USB device.
- Vivado 2019.2 target database contains `xc7a35tcsg324-1`.
- Clock/documentation: EES-338 manual v1.0 PDF p5, 100MHz on T5.

JTAG identifies the die, not package marking or PCB revision. The local vendor
manual identifies XC7A35TCSG324 and the supplied schematic gives its pin nets.
Some document revisions disagree about LED/switch numbering and USB bridge
model; preserve the electrical pin mapping and verify logical orientation on
the actual board during bring-up.

## New design pin evidence

Sources: local `EES-338_UserManual_v1.0.pdf`, PDF pages shown below, and
`EES-338-V0.1-out.pdf`, sheet 4 (FPGA banks), sheet 9 (display), sheet 7 (buzzer).
These files remain local vendor references rather than republished assets.

| Our signal | FPGA pins | Evidence |
|---|---|---|
| clk100 | T5 | manual p5, schematic sheet4 SYS_CLK |
| reset_n | P15 | manual p8; verify electrical active-low pull-up |
| uart_tx | T4 | manual p15: FPGA transmit, USB bridge receive |
| uart_rx | N5 | manual p15: FPGA receive, USB bridge transmit |
| led[0:7] | K2,J2,J3,H4,J4,G3,G4,F6 | manual p10 logical numbering |
| switches[0:7] | R1,N4,M4,R2,P2,P3,P4,P5 | manual p9 logical numbering |
| segment0[a,b,c,d,e,f,g,dp] | B4,A4,A3,B1,A1,B3,B2,D5 | manual p11 |
| segment1[a,b,c,d,e,f,g,dp] | D4,E3,D3,F4,F3,E2,D2,H2 | manual p11 |
| digit[0:7] | G2,C2,C1,H1,G1,F1,E1,G6 | manual p11 |
| buzzer | G13 | manual p25 |

The board uses two groups of four digits with separate segment buses. Physical
digit and segment outputs are active HIGH per manual p10; normalized internal
active-low driver outputs must be inverted in board top. All listed I/O use
3.3V banks per schematic. Board integration must not simply reuse an old XDC.

## Implemented and programmed on 2026-09-05

The single-cycle SoC was synthesized, placed, routed and programmed successfully
with Vivado 2019.2. The verified bitstream uses 2,858 LUTs (512 LUT RAM) and
1,865 FFs at a 10 MHz CPU clock. Setup slack is 8.582 ns, hold slack 0.011 ns,
pulse-width slack 4.500 ns, DRC violations 0, with no unconstrained internal
endpoints. The original programmed image SHA-256 is
`219404a5d75730b3566fe3fafe8b977c6bf98b564e11b68344a59a2842aef0e7`.

Physical serial tests returned Fibonacci=89, RAM stores=12, errors=0,
switches=0x81, display=0x00810059 and CPU-controlled LED drive=0xD8.
UART off/on/auto and CPU restart were exercised, then captured in a 32-second
dashboard recording. See [board.json](../evidence/board.json) and
[the recording evidence](../evidence/recording.json).

This is electrical telemetry from the actual programmed FPGA. Physical LED
orientation, visible digit appearance and audible buzzer output remain separate
observation items. The dashboard is explicitly a telemetry illustration, not a
camera photograph. Pipeline/cache integration is simulation evidence, not this
programmed bitstream.

Raw discovery identifiers remain in ignored build/hardware. Public timing,
utilization and DRC reports omit the host identifier. A separate clean-clone
rebuild records its own bitstream hash; build metadata can change the hash even
when the RTL and resource/timing results agree.
