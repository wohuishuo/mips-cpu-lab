#!/usr/bin/env python3
"""Compile and run the peripheral RTL testbench with Vivado XSim 2019.2."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "peripherals"
XILINX_BIN = Path(os.environ.get("VIVADO_BIN", r"E:\Xilinx\Vivado\2019.2\bin"))
SOURCES = [
    ROOT / "rtl" / "peripherals" / "uart_tx.v",
    ROOT / "rtl" / "peripherals" / "uart_rx.v",
    ROOT / "rtl" / "peripherals" / "seven_segment.v",
    ROOT / "rtl" / "peripherals" / "buzzer.v",
    ROOT / "tests" / "tb_peripherals.sv",
]


def run_batch(name: str, *args: str) -> str:
    tool = XILINX_BIN / f"{name}.bat"
    if not tool.is_file():
        raise RuntimeError(f"required XSim tool not found: {tool}")
    command = ["cmd.exe", "/d", "/c", str(tool), *args]
    completed = subprocess.run(
        command,
        cwd=BUILD,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=180,
    )
    print(f"$ {' '.join(command)}")
    print(completed.stdout, end="")
    if completed.returncode != 0:
        raise RuntimeError(f"{name} failed with exit code {completed.returncode}")
    return completed.stdout


def main() -> int:
    missing = [path for path in SOURCES if not path.is_file()]
    if missing:
        print("Missing peripheral sources:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 2

    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)

    try:
        run_batch("xvlog", *(str(path) for path in SOURCES[:-1]))
        run_batch("xvlog", "-sv", str(SOURCES[-1]))
        run_batch("xelab", "tb_peripherals", "-s", "tb_peripherals_sim")
        simulation_output = run_batch("xsim", "tb_peripherals_sim", "-runall")
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    failure_markers = ("FAIL:", "FATAL:", "FATAL_ERROR", "ERROR:")
    normalized_output = simulation_output.upper()
    if any(marker in normalized_output for marker in failure_markers):
        print("ERROR: simulation output contains a failure marker", file=sys.stderr)
        return 1
    if "PASS: all peripheral tests passed" not in simulation_output:
        print("ERROR: simulation ended without the peripheral PASS marker", file=sys.stderr)
        return 1
    print("Peripheral XSim regression passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
