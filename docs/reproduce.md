# Reproducing the MIPS CPU lab results

The main regression entry point is `scripts/run_all.py`. It runs the project-owned
single-cycle, CP0, peripheral, cache, pipeline, MARS-to-RTL, SoC, and CPU/cache
checks in that order. It stops at the first failure.

## Prerequisites

Use a Windows host with:

- Python 3.10 or newer;
- Xilinx Vivado Design Suite 2019.2, including XSim;
- a Java runtime and a local MARS 4.5 JAR;
- enough free space for Vivado simulation output under `build/`.

Set tool locations in PowerShell before running the suite. Substitute paths from
your own installation:

```powershell
$env:VIVADO_BIN = 'C:/Xilinx/Vivado/2019.2/bin'
$env:MARS_JAR = 'C:/tools/mars4_5.jar'
python scripts/run_all.py
```

The suite does not download tools, course files, or credentials. Confirm that
`xvlog.bat`, `xelab.bat`, and `xsim.bat` exist in `VIVADO_BIN`, and that Java can
open `MARS_JAR`. The MARS source used by the core suite is
`software/fibonacci_mars.S`.

Each selected check gets a log in `build/run-all/`. `summary.json` records its
status, elapsed time, return code, command, log path, and reason. The summary also
captures the source commit and dirty state when the run starts, so later commits
cannot be silently attributed to an earlier test run. The statuses
have these meanings:

- `PASS`: the runner exited successfully;
- `FAIL`: the runner failed, could not start, or exceeded its timeout;
- `NOT_RUN`: an earlier failure stopped the suite;
- `SKIP`: an explicitly requested optional check lacked external input.

The overall status is `PASS_WITH_SKIPS` when optional checks are skipped. A skip
does not constitute evidence that the skipped design passed. Use `--timeout` to
change the default 900-second limit per runner, and `--output` to choose another
evidence directory:

```powershell
python scripts/run_all.py --timeout 1200 --output build/reproduction-2026-09-05
```

`python scripts/run_all.py --list` prints the default runner set without invoking
Vivado, Java, a serial port, or board programming.

## Optional supplied-course checks

Course source, ROM, trace, and generated-IP metadata remain external teaching
materials and are not redistributed by this repository. If you have authorized
local copies, set both roots and request the course checks explicitly:

```powershell
$env:BITMIPS_LAB5 = 'C:/course/bitmips_experiments/lab5'
$env:BITMIPS_ROOT = 'C:/course/bitmips_experiments'
python scripts/run_all.py --with-course
```

`BITMIPS_LAB5` supplies the lab5 ROM, golden trace, and teaching SoC sources used
by `upstream_sc` and `teach_soc`. `BITMIPS_ROOT` supplies the lab1 and lab3 trees
used by `course_basics`. The runners validate the files they consume and keep the
original inputs unchanged. If a root or required file is absent, the associated
row is `SKIP`; the runner does not try to fetch it.

## Optional GNU source rebuild

For actual GNU source compilation of the supplied nineteen-point lab5 program,
see [GNU rebuild](gnu-rebuild.md). It is an explicit additional workflow using
a private Ubuntu image under a working WSL distribution; it is not an implicit
download or environment change performed by the ordinary eleven-runner suite.

## Physical board work

The default and `--with-course` suites do not synthesize, program, open a serial
port, or contact hardware. Install the pinned serial dependency only when using
the physical UART check:

```powershell
python -m pip install -r requirements.txt
```

Build and inspect a bitstream explicitly:

```powershell
& "$env:VIVADO_BIN/vivado.bat" -mode batch -source scripts/build_board.tcl
```

The build first invokes `python scripts/build_board_program.py`, assembling
`software/board_demo.S` with the configured `MARS_JAR` into a fresh 1,024-word
ROM. Keep `python` and `java` on PATH. No pre-existing ROM or Vivado project is
needed. A successful build writes a SHA-256-bound result marker; programming
rejects a missing marker or a changed bitstream.

Review `build/board/build_result.txt`, the timing reports, DRC report, and the
target identity before programming. Programming requires an already verified
bitstream and exactly one connected XC7A35T target:

```powershell
# Start once if Hardware Manager / hw_server is not already running:
Start-Process -FilePath "$env:VIVADO_BIN/hw_server.bat" -WindowStyle Hidden
python scripts/run_all.py --program-board
```

Run the physical UART exercise only after programming, replacing the example
port with the port assigned to your board:

```powershell
python scripts/run_all.py --test-board --serial-port COM4
```

The two flags are independent and can be supplied together if the bitstream is
already built. Board output, LEDs, seven-segment orientation, switches, and sound
still require observation on the actual hardware; simulation output alone does
not establish those physical results.

## Portable repository check

The inactive template `docs/ci/portable-check.yml` performs Python syntax checks,
lists core runners, and runs fixture-based tests of timeout, logging, skip and
stop-on-fail behavior. The publishing GitHub authorization lacked `workflow`
scope, so this release contains a template rather than an active workflow. No
GitHub Actions run is claimed. The same checks passed locally.

GitHub-hosted runners do not include Vivado 2019.2, so even an enabled template
would not establish an RTL simulation pass. Run the main command on a configured
Windows/Vivado host to reproduce the RTL evidence. See [CI notes](ci/README.md).

## Printable report

`docs/report.pdf` is generated from the original Chinese `docs/report.md` and
the project's teaching figures. On Windows with Microsoft YaHei and Consolas:

```powershell
python -m pip install reportlab
python scripts/render_report.py
```

Its layout has been rendered and visually checked. The Markdown remains the
editable source; regenerate the PDF when measured results change.
