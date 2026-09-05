# Board-independent peripherals

These modules implement the reusable peripheral interfaces from
`docs/design.md`. Every module uses the rising edge of `clk` and a synchronous,
active-high `rst`. Board pin polarity and package-pin assignments belong in the
SoC top level and its newly verified constraints.

## UART transmitter

`uart_tx` accepts one byte on a rising edge where both `tx_valid` and
`tx_ready` are high. `tx_ready` is high only while idle. The serialized frame is
one low start bit, eight data bits least-significant bit first, and one high stop
bit. `tx` remains high while idle and returns high immediately when reset
cancels a frame.

Each bit lasts `floor(CLOCK_HZ / BAUD)` input clocks. The default 100 MHz and
115200 baud settings therefore use 868 clocks per bit (approximately 115207
baud). Simulation-time parameter checks reject non-positive rates or a UART
divider below four clocks per bit. Accelerated tests can use any parameter pair
that meets that constraint.

## UART receiver

`uart_rx` passes `rx` through two flip-flops before interpreting it. It confirms
the start bit near its center, samples the eight data bits near their centers,
and then samples the stop bit. A correct stop produces a one-clock `rx_valid`
pulse with the byte on `rx_data`. A low stop produces a one-clock `frame_error`
pulse and suppresses `rx_valid`; the sampled byte remains visible on `rx_data`.
Reset cancels any partial frame without producing either pulse.

The receiver uses the same integer divider and parameter checks as the
transmitter. A shared nominal clock and baud rate should stay within normal UART
sampling tolerance; the divider does not implement fractional-baud dithering.

## Eight-digit seven-segment display

`seven_segment` continuously displays the eight hexadecimal nibbles of `value`.
Digit zero displays `value[3:0]`, followed in order through digit seven displaying
`value[31:28]`. `SCAN_HZ` is the digit-advance rate, so the complete eight-digit
frame rate is `SCAN_HZ / 8`. The default 1 kHz scan rate gives a 125 Hz frame
rate.

The outputs use a normalized active-low convention:

- `digit_n[i] == 0` selects digit `i`; exactly one digit is selected.
- `segment_n[6:0]` is `{g,f,e,d,c,b,a}` with zero meaning illuminated.
- `segment_n[7]` is the decimal point and remains high (off).

The physical board's display polarity and bank wiring are deliberately outside
this driver. The verified board integration must invert or remap these signals
as its schematic requires.

## Buzzer

`buzzer` generates a square wave when `enable` is high and `frequency_hz` is
nonzero. A phase accumulator requests `2 * frequency_hz` output transitions per
second, preserving the requested average frequency without a variable hardware
divider. When a transition falls between input-clock edges, adjacent
half-periods can differ by one input clock. Requests at or above half the input
clock clamp to one toggle per clock. Disabling the buzzer, selecting zero
frequency, or asserting reset drives `wave` low and clears the phase.

## Simulation

Run the complete peripheral regression from the repository root:

```powershell
python tests\run_peripherals.py
```

The runner invokes the Vivado 2019.2 `xvlog`, `xelab`, and `xsim` tools from
`E:\Xilinx\Vivado\2019.2\bin`. The self-checking testbench uses separately timed
serial stimulus and monitoring rather than UART loopback. It covers consecutive
TX and RX bytes, malformed stop bits, reset during active frames, idle behavior,
one-cycle RX pulses, all sixteen hexadecimal glyphs, scan order and one-hot
digit selection, buzzer frequency/disable/reset, and unknown output detection.

This is module-level simulation evidence. SoC integration, synthesis/timing,
pin mapping, programming, and observation on the physical board remain separate
work and are not established by this test.
