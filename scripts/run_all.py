#!/usr/bin/env python3
"""Run the reproducible MIPS CPU lab regressions and retain evidence."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from typing import Mapping, Sequence


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Runner:
    """One independently logged regression command."""

    name: str
    command: tuple[str, ...]
    optional: bool = False
    prerequisites: tuple[Path, ...] = ()
    missing_reason: str = "optional prerequisites are unavailable"


def _result(
    runner: Runner,
    output_dir: Path,
    status: str = "NOT_RUN",
    duration_seconds: float = 0.0,
    returncode: int | None = None,
    reason: str = "stopped after an earlier failure",
) -> dict[str, object]:
    return {
        "name": runner.name,
        "status": status,
        "duration_seconds": round(duration_seconds, 3),
        "returncode": returncode,
        "command": list(runner.command),
        "log": str((output_dir / f"{runner.name}.log").resolve()),
        "reason": reason,
    }


def _write_summary(output_dir: Path, results: Sequence[dict[str, object]], provenance: dict[str, object]) -> None:
    statuses = {row["status"] for row in results}
    if "FAIL" in statuses:
        overall = "FAIL"
    elif "NOT_RUN" in statuses:
        overall = "RUNNING"
    elif "SKIP" in statuses:
        overall = "PASS_WITH_SKIPS"
    else:
        overall = "PASS"
    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "overall_status": overall,
        "tests": list(results),
        **provenance,
    }
    (output_dir / "summary.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )


def _timeout_output(error: subprocess.TimeoutExpired) -> str:
    chunks: list[str] = []
    for value in (error.stdout, error.stderr):
        if isinstance(value, bytes):
            chunks.append(value.decode("utf-8", errors="replace"))
        elif value:
            chunks.append(value)
    return "".join(chunks)


def _run_command(
    command: tuple[str, ...],
    timeout_seconds: float,
    env: Mapping[str, str] | None,
) -> tuple[int, str]:
    options: dict[str, object] = {}
    if os.name == "nt":
        options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        options["start_new_session"] = True
    process = subprocess.Popen(
        command,
        cwd=ROOT,
        env=dict(env) if env is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        **options,
    )
    try:
        output, _ = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        raise subprocess.TimeoutExpired(command, timeout_seconds, output=output)
    return process.returncode, output


def run_suite(
    runners: Sequence[Runner],
    output_dir: Path,
    timeout_seconds: float,
    env: Mapping[str, str] | None = None,
) -> list[dict[str, object]]:
    """Run in order, writing one log per command and stopping at first failure."""

    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")
    provenance: dict[str, object] = {"source_commit": None, "source_dirty": None}
    try:
        provenance['source_commit'] = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
        provenance['source_dirty'] = bool(subprocess.check_output(
            ['git', 'status', '--porcelain'], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip())
    except (OSError, subprocess.CalledProcessError):
        pass
    output_dir.mkdir(parents=True, exist_ok=True)
    results = [_result(runner, output_dir) for runner in runners]
    for runner in runners:
        (output_dir / f"{runner.name}.log").write_text(
            f"NOT_RUN {runner.name}: waiting to run\n", encoding="utf-8"
        )
    _write_summary(output_dir, results, provenance)
    stopped = False

    for index, runner in enumerate(runners):
        if stopped:
            continue
        missing = [path for path in runner.prerequisites if not path.is_file()]
        if missing and runner.optional:
            reason = f"{runner.missing_reason}: " + ", ".join(str(path) for path in missing)
            results[index] = _result(runner, output_dir, status="SKIP", reason=reason)
            (output_dir / f"{runner.name}.log").write_text(
                f"SKIP {runner.name}: {reason}\n", encoding="utf-8"
            )
            print(f"SKIP {runner.name}: {reason}", flush=True)
            _write_summary(output_dir, results, provenance)
            continue

        log_path = output_dir / f"{runner.name}.log"
        command_text = subprocess.list2cmdline(list(runner.command))
        print(f"RUN  {runner.name}", flush=True)
        started = time.monotonic()
        status = "FAIL"
        returncode: int | None = None
        reason = ""
        captured = ""
        try:
            returncode, captured = _run_command(runner.command, timeout_seconds, env)
            if returncode == 0:
                status = "PASS"
                reason = "completed successfully"
            else:
                reason = f"runner exited with code {returncode}"
        except subprocess.TimeoutExpired as error:
            captured = _timeout_output(error)
            reason = f"timed out after {timeout_seconds:g} seconds"
        except OSError as error:
            reason = f"could not start runner: {error}"

        duration = time.monotonic() - started
        log_path.write_text(
            f"COMMAND: {command_text}\n\n{captured}", encoding="utf-8"
        )
        results[index] = _result(
            runner,
            output_dir,
            status=status,
            duration_seconds=duration,
            returncode=returncode,
            reason=reason,
        )
        _write_summary(output_dir, results, provenance)
        print(f"{status:4} {runner.name} ({duration:.1f}s): {reason}", flush=True)
        stopped = status == "FAIL"

    _write_summary(output_dir, results, provenance)
    return results


def _python_runner(name: str, relative_path: str, **kwargs: object) -> Runner:
    return Runner(name, (sys.executable, str(ROOT / relative_path)), **kwargs)


def _course_prerequisites() -> list[Runner]:
    lab5_value = os.environ.get("BITMIPS_LAB5")
    lab5 = Path(lab5_value).resolve() if lab5_value else ROOT / "__BITMIPS_LAB5_NOT_SET__"
    lab5_replay_files = (
        lab5 / "teach_soft" / "inst_ram.coe",
        lab5 / "golden_trace.txt",
    )
    lab5_soc_files = (
        *lab5_replay_files,
        lab5 / "teach_soc" / "teach_soc.srcs" / "sources_1" / "new" / "teach_soc_top.v",
        lab5 / "teach_soc" / "teach_soc.srcs" / "sources_1" / "new" / "bridge" / "bridge_1x2.v",
        lab5 / "teach_soc" / "teach_soc.srcs" / "sources_1" / "new" / "confreg" / "confeg.v",
        lab5 / "teach_soft" / "func_test" / "start.S",
    )
    lab5_reason = "set BITMIPS_LAB5 to the locally supplied lab5 directory"

    course_value = os.environ.get("BITMIPS_ROOT")
    course = Path(course_value).resolve() if course_value else ROOT / "__BITMIPS_ROOT_NOT_SET__"
    course_files = (
        ROOT / "tests" / "run_course_basics.py",
        course / "lab1" / "num_led" / "num_led.srcs" / "sources_1" / "new" / "num_led.v",
        course / "lab3" / "single_cycle" / "single_cycle.srcs" / "sources_1" / "new" / "single_cycle.v",
        course / "lab3" / "single_cycle" / "single_cycle.srcs" / "sources_1" / "new" / "confreg" / "confreg.v",
        course / "lab3" / "single_cycle" / "single_cycle.srcs" / "sources_1" / "new" / "ip" / "inst_rom" / "inst_rom.xci",
        course / "lab3" / "single_cycle" / "single_cycle.srcs" / "sources_1" / "new" / "ip" / "data_ram" / "data_ram.xci",
        course / "lab3" / "soft" / "fibonacci.coe",
        course / "lab3" / "soft" / "adder8bit.coe",
    )
    return [
        _python_runner(
            "upstream_sc",
            "tests/run_upstream_sc.py",
            optional=True,
            prerequisites=(ROOT / "tests" / "run_upstream_sc.py", *lab5_replay_files),
            missing_reason=lab5_reason,
        ),
        _python_runner(
            "teach_soc",
            "tests/run_teach_soc.py",
            optional=True,
            prerequisites=(ROOT / "tests" / "run_teach_soc.py", *lab5_soc_files),
            missing_reason=lab5_reason,
        ),
        _python_runner(
            "course_basics",
            "tests/run_course_basics.py",
            optional=True,
            prerequisites=course_files,
            missing_reason="set BITMIPS_ROOT to the locally supplied course repository",
        ),
    ]


def build_runners(args: argparse.Namespace) -> list[Runner]:
    runners = [
        _python_runner("single_cycle", "tests/run_single_cycle.py"),
        _python_runner("cp0", "tests/run_cp0.py"),
        _python_runner("peripherals", "tests/run_peripherals.py"),
        _python_runner("cache", "tests/run_cache.py"),
        _python_runner("pipeline", "tests/run_pipeline.py"),
        _python_runner("mars", "tests/run_mars_program.py"),
        _python_runner("soc", "tests/run_soc.py"),
        _python_runner("cpu_cache", "tests/run_cpu_cache.py"),
    ]
    if args.with_course:
        runners.extend(_course_prerequisites())
    if args.program_board:
        vivado_bin = Path(os.environ.get("VIVADO_BIN", "C:/Xilinx/Vivado/2019.2/bin"))
        runners.append(
            Runner(
                "program_board",
                (
                    str(vivado_bin / "vivado.bat"),
                    "-mode",
                    "batch",
                    "-source",
                    str(ROOT / "scripts" / "program_board.tcl"),
                ),
            )
        )
    if args.test_board:
        runners.append(
            _python_runner(
                "physical_board",
                "scripts/board_test.py",
            )
        )
        runners[-1] = Runner(
            runners[-1].name,
            (*runners[-1].command, "--port", args.serial_port),
        )
    return runners


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--with-course",
        action="store_true",
        help="also run checks that use locally supplied course files",
    )
    parser.add_argument(
        "--program-board",
        action="store_true",
        help="program a connected board from an already verified bitstream",
    )
    parser.add_argument(
        "--test-board",
        action="store_true",
        help="run the physical UART board test (requires --serial-port)",
    )
    parser.add_argument("--serial-port", help="serial port for --test-board, such as COM6")
    parser.add_argument(
        "--timeout",
        type=float,
        default=900.0,
        help="maximum seconds for each runner (default: 900)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "build" / "run-all",
        help="directory for per-runner logs and summary.json",
    )
    parser.add_argument("--list", action="store_true", help="list selected runners without executing")
    args = parser.parse_args(argv)
    if args.test_board and not args.serial_port:
        parser.error("--test-board requires --serial-port")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    runners = build_runners(args)
    if args.list:
        for runner in runners:
            print(runner.name)
        return 0
    results = run_suite(runners, args.output.resolve(), args.timeout)
    return 1 if any(row["status"] == "FAIL" for row in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
