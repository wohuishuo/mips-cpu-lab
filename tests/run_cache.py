#!/usr/bin/env python3
"""Compile and run the standalone data-cache verification with XSim 2019.2."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "cache"
DEFAULT_VIVADO_BIN = Path("E:/Xilinx/Vivado/2019.2/bin")
VIVADO_BIN = Path(os.environ.get("VIVADO_BIN", DEFAULT_VIVADO_BIN)).expanduser()
COMMAND_TIMEOUT_SECONDS = 180

PARAMETER_TESTBENCH_TEMPLATE = r"""
`timescale 1ns/1ps

module __MODULE__;
    localparam integer SETS_VALUE = __SETS__;
    localparam integer WORDS_VALUE = __WORDS__;
    reg clk;
    reg rst;
    reg cpu_valid;
    reg cpu_write;
    reg [31:0] cpu_addr;
    reg [31:0] cpu_wdata;
    reg [3:0] cpu_wstrb;
    wire cpu_ready;
    wire [31:0] cpu_rdata;
    wire mem_valid;
    wire mem_write;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0] mem_wstrb;
    wire [31:0] hit_count;
    wire [31:0] miss_count;
    wire [31:0] writeback_count;
    reg [31:0] read_result;
    integer watchdog;

    wire mem_ready = 1'b1;
    wire [31:0] mem_rdata = 32'h1234_5678 ^ mem_addr;

    data_cache #(
        .SETS(SETS_VALUE),
        .WORDS_PER_LINE(WORDS_VALUE)
    ) dut (
        .clk(clk), .rst(rst),
        .cpu_valid(cpu_valid), .cpu_write(cpu_write),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
        .cpu_ready(cpu_ready), .cpu_rdata(cpu_rdata),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .hit_count(hit_count), .miss_count(miss_count),
        .writeback_count(writeback_count)
    );

    always #5 clk = ~clk;

    task transact;
        input write_request;
        input [31:0] address;
        input [31:0] write_data;
        input [3:0] write_strobes;
        output [31:0] result;
        begin
            @(negedge clk);
            cpu_valid = 1'b1;
            cpu_write = write_request;
            cpu_addr = address;
            cpu_wdata = write_data;
            cpu_wstrb = write_strobes;
            watchdog = 0;
            while (cpu_ready !== 1'b1) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 50) begin
                    $display("CACHE_PARAMETER_TOP_FAIL timeout");
                    $finish;
                end
            end
            result = cpu_rdata;
            @(negedge clk);
            cpu_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        cpu_valid = 1'b0;
        cpu_write = 1'b0;
        cpu_addr = 32'b0;
        cpu_wdata = 32'b0;
        cpu_wstrb = 4'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        transact(1'b0, 32'h0, 32'h0, 4'b0, read_result);
        if (read_result !== 32'h1234_5678) begin
            $display("CACHE_PARAMETER_TOP_FAIL singleton refill data");
            $finish;
        end
        transact(1'b1, 32'h0, 32'habcd_ef01, 4'b0101, read_result);
        transact(1'b0, 32'h0, 32'h0, 4'b0, read_result);
        if (read_result !== 32'h12cd_5601 || hit_count !== 2
            || miss_count !== 1 || writeback_count !== 0) begin
            $display("CACHE_PARAMETER_TOP_FAIL singleton cache behavior");
            $finish;
        end
        $display("CACHE_PARAMETER_TOP_PASS SETS=%0d WORDS_PER_LINE=%0d",
                 SETS_VALUE, WORDS_VALUE);
        $finish;
    end
endmodule
"""


def executable(name: str) -> str:
    for suffix in (".bat", ".exe", ""):
        candidate = VIVADO_BIN / f"{name}{suffix}"
        if candidate.exists():
            return str(candidate)
    raise FileNotFoundError(f"Vivado tool not found: {VIVADO_BIN / name}")


def run(command: list[str]) -> str:
    print("+", " ".join(command), flush=True)
    try:
        result = subprocess.run(
            command,
            cwd=BUILD,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env={**os.environ, "TERM": "dumb"},
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        captured = error.stdout or ""
        if isinstance(captured, bytes):
            captured = captured.decode(errors="replace")
        print(captured, end="")
        raise SystemExit(
            f"command timed out after {COMMAND_TIMEOUT_SECONDS} seconds: "
            f"{command[0]}"
        ) from error
    print(result.stdout, end="")
    if result.returncode:
        raise SystemExit(result.returncode)
    return result.stdout


def run_variant(name: str, sets: int, words_per_line: int, defines: list[str]) -> None:
    snapshot = f"tb_cache_{name}"
    sources = [
        str(ROOT / "rtl" / "cache" / "data_cache.v"),
        str(ROOT / "tests" / "tb_cache.sv"),
    ]
    run(
        [
            executable("xvlog"),
            "--sv",
            "--work",
            "xil_defaultlib",
            *[item for define in defines for item in ("--define", define)],
            *sources,
        ]
    )
    run(
        [
            executable("xelab"),
            "--debug",
            "typical",
            "xil_defaultlib.tb_cache",
            "-s",
            snapshot,
        ]
    )
    output = run([executable("xsim"), snapshot, "-runall"])
    marker = f"TB_CACHE_PASS SETS={sets} WORDS_PER_LINE={words_per_line}"
    lowered = output.lower()
    if "tb_cache_fail" in lowered or "fatal:" in lowered:
        raise SystemExit(f"simulation reported a fatal failure for {name}")
    if marker not in output:
        raise SystemExit(f"missing pass marker: {marker}")


def run_parameter_case(
    name: str,
    sets: int,
    words_per_line: int,
    expected_error: str | None,
) -> None:
    snapshot = f"tb_cache_params_{name}"
    run(
        [
            executable("xelab"),
            "--debug",
            "typical",
            f"xil_defaultlib.tb_cache_params_{name}",
            "-s",
            snapshot,
        ]
    )
    output = run([executable("xsim"), snapshot, "-runall"])
    if "CACHE_PARAMETER_TOP_FAIL" in output:
        raise SystemExit(f"parameter smoke test failed for {name}")
    if expected_error is None:
        marker = (
            f"CACHE_PARAMETER_TOP_PASS SETS={sets} "
            f"WORDS_PER_LINE={words_per_line}"
        )
        if "DATA_CACHE_PARAMETER_ERROR" in output or marker not in output:
            raise SystemExit(f"legal parameter case was rejected: {name}")
    else:
        if expected_error not in output:
            raise SystemExit(f"missing explicit parameter rejection: {name}")
        if "CACHE_PARAMETER_TOP_PASS" in output:
            raise SystemExit(f"invalid parameter case reached pass marker: {name}")
        print(f"CACHE_INVALID_PARAMETER_REJECTED {name}")


def main() -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    run_variant("default", 16, 4, [])
    run_variant("small", 4, 2, ["CACHE_SMALL_VARIANT"])
    parameter_source = BUILD / "tb_cache_parameters.sv"
    cases = [
        ("singleton", 1, 1),
        ("sets_zero", 0, 4),
        ("sets_three", 3, 4),
        ("words_zero", 4, 0),
        ("words_three", 4, 3),
    ]
    parameter_source.write_text(
        "\n".join(
            PARAMETER_TESTBENCH_TEMPLATE
            .replace("__MODULE__", f"tb_cache_params_{name}")
            .replace("__SETS__", str(sets))
            .replace("__WORDS__", str(words))
            for name, sets, words in cases
        ),
        encoding="utf-8",
    )
    run(
        [
            executable("xvlog"),
            "--sv",
            "--work",
            "xil_defaultlib",
            str(parameter_source),
        ]
    )
    run_parameter_case("singleton", 1, 1, None)
    run_parameter_case(
        "sets_zero", 0, 4,
        "DATA_CACHE_PARAMETER_ERROR SETS=0 expected positive power of two",
    )
    run_parameter_case(
        "sets_three", 3, 4,
        "DATA_CACHE_PARAMETER_ERROR SETS=3 expected positive power of two",
    )
    run_parameter_case(
        "words_zero", 4, 0,
        "DATA_CACHE_PARAMETER_ERROR WORDS_PER_LINE=0 expected positive power of two",
    )
    run_parameter_case(
        "words_three", 4, 3,
        "DATA_CACHE_PARAMETER_ERROR WORDS_PER_LINE=3 expected positive power of two",
    )
    print("CACHE_TESTS_PASS variants=3 invalid_parameter_cases=4")


if __name__ == "__main__":
    main()
