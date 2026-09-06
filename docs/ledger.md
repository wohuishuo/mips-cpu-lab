# Execution ledger

2026-09-05: the project-owned CPU, cache, peripheral, SoC and course adapters have
been implemented and independently reviewed. The complete eleven-runner suite
passed from a clean Git clone. A separate clean-clone board build assembled the
ROM, synthesized, placed, routed and generated a bitstream successfully.

The actual connected EES-338 was programmed with the single-cycle SoC. Physical
UART tests verified Fibonacci, memory stores, zero reported errors, LED drive
overrides and CPU restart. The 78-second Chinese demo contains a 32-second actual
UART window recording plus original teaching figures and trace-derived images.

Current authoritative scope and per-capability evidence are maintained in
[capabilities.md](capabilities.md), [report.md](report.md), and
[evidence/results.json](../evidence/results.json). This ledger supersedes the
intermediate implementation notes.

## Resolved review findings

- CP0 Count/Compare compares the committed next Count value, including writes.
- MMIO decoding covers the intended page without unintended high-byte aliases.
- Reset tests require cleared/recomputed state or a bounded counter age.
- Failed builds, board tests and recordings invalidate previous success markers.
- Programming verifies the bitstream SHA-256 against the successful build.
- Cache rejects illegal parameters; one-set/one-word and continuous-ready memory
  receive explicit coverage.
- MARS tests compare full store addresses, not only low RAM indices.
- Aggregate results retain run-time source revision and explicit SKIP/FAIL states.
- Vivado's Python 2 environment does not leak into the Python 3 ROM helper.

## Deliberate boundaries

- The programmed design is a single-cycle SoC. Pipeline/cache/teach_soc evidence
  is simulation evidence.
- Supplied lab5 ROM/golden trace enables 19 points. A subsequent actual GNU
  rebuild reproduced all46,951 ROM words and passed the unchanged golden trace.
  The default archive-order difference and compatibility adjustments are retained
  in gnu-rebuild.md. There is no claim that all89 points pass.
- Physical GPIO telemetry is preserved, but visible digit appearance, LED
  orientation and real buzzer sound have not been captured optically/acoustically.
- Teacher PDFs, textbook scans, historical XPR/XDC and unlicensed course sources
  remain outside the public repository.
