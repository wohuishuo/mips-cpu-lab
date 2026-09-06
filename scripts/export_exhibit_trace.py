"""Reassemble board_demo.S, run the actual board SoC in XSim, export snapshots.

Requires Java/MARS (MARS_JAR) and Vivado (VIVADO_BIN). No FPGA interaction.
"""
from pathlib import Path
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/exhibit-trace'
FIBONACCI = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hex_value(value):
    return None if any(c in value.lower() for c in 'xz') else int(value, 16)


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / 'scripts/build_board_program.py')], check=True)
    rom = ROOT / 'build/board/board_rom.hex'
    shutil.copyfile(rom, WORK / 'board_rom.hex')
    vivado = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))
    sources = ['rtl/core/single_cycle_cpu.v',
               *sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'rtl/peripherals').glob('*.v')),
               'rtl/soc/lab_soc.v', 'tests/tb_exhibit_soc.sv']
    commands = [('xvlog', ['--sv', *[str(ROOT / p) for p in sources]]),
                ('xelab', ['tb_exhibit_soc', '-s', 'exhibit_trace']),
                ('xsim', ['exhibit_trace', '-runall'])]
    pass_line = None
    for tool, args in commands:
        run = subprocess.run([str(vivado / (tool + '.bat')), *args], cwd=WORK,
                             capture_output=True, timeout=180)
        output = (run.stdout + run.stderr).decode(errors='replace')
        (WORK / (tool + '.txt')).write_text(output, encoding='utf-8')
        print(f'{tool}: exit {run.returncode}', flush=True)
        if run.returncode or 'FAIL EXHIBIT' in output or 'Fatal:' in output:
            raise RuntimeError(output[-6000:])
        if tool == 'xsim':
            passes = [line for line in output.splitlines() if line.startswith('PASS EXHIBIT ')]
            if len(passes) != 1:
                raise RuntimeError('Missing unique PASS EXHIBIT marker')
            pass_line = passes[0]
    rows = []
    with (WORK / 'board-trace.csv').open(newline='') as stream:
        for raw in csv.DictReader(stream):
            row = {key: hex_value(raw[key]) for key in
                   ('pc', 'instr', 'value', 'address', 'storeValue', 'readValue', 'display', 'led')}
            row.update({key: int(raw[key]) for key in ('cycle', 'rd')})
            row.update({key: bool(int(raw[key])) for key in ('regWrite', 'memWrite', 'done')})
            row['registers'] = [hex_value(raw[f'r{i}']) for i in range(32)]
            row['ram'] = [hex_value(raw[f'ram{i}']) for i in range(12)]
            rows.append(row)
    assert len(rows) == 160
    previous_registers = [0] * 32
    previous_ram = [None] * 12
    stores = []
    words = [int(word, 16) for word in rom.read_text().split()]
    for cycle, row in enumerate(rows, 1):
        assert row['cycle'] == cycle
        assert row['instr'] == words[(row['pc'] - 0x00400000) // 4]
        if row['regWrite']:
            assert row['rd'] != 0 and row['value'] is not None
            previous_registers[row['rd']] = row['value']
        assert row['registers'] == previous_registers
        if row['memWrite'] and 0x10010000 <= row['address'] < 0x10011000:
            stores.append((row['address'], row['storeValue']))
            previous_ram[(row['address'] - 0x10010000) // 4] = row['storeValue']
        assert row['ram'] == previous_ram
    assert stores == [(0x10010000 + i * 4, value) for i, value in enumerate(FIBONACCI)]
    assert rows[-1]['ram'] == FIBONACCI
    assert rows[-1]['done'] and rows[-1]['display'] == 0x00810059 and rows[-1]['led'] == 0xD8
    provenance = [*sources, 'software/board_demo.S', 'scripts/build_board_program.py',
                  'scripts/export_exhibit_trace.py']
    data = {
        'kind': 'rtl-simulation',
        'description': 'Fresh XSim simulation of lab_soc + single_cycle_cpu with board_demo.S and switches 0x81. Instruction/bus sampled before each rising edge; architectural state after that edge. This is not physical FPGA instruction telemetry. Unknown bus/RAM values are null; RAM is not reset.',
        'sourcePaths': provenance,
        'sourceSha256': {path: sha256(ROOT / path) for path in provenance},
        'sourceCanonicalSha256': {path: hashlib.sha256((ROOT / path).read_text(encoding='utf-8').replace('\r\n', '\n').encode('utf-8')).hexdigest() for path in provenance},
        'romSha256': sha256(rom), 'switches': 0x81,
        'simulator': 'Xilinx Vivado XSim 2019.2',
        'reproduce': 'python scripts/export_exhibit_trace.py',
        'rows': rows,
        'checks': {'passed': True, 'cycles': len(rows), 'ramStores': len(stores),
                   'fibonacci': FIBONACCI, 'result': 89, 'done': True,
                   'display': 0x00810059, 'led': 0xD8, 'illegalInstructions': 0,
                   'registerTransitions': True, 'ramTransitions': True,
                   'instructionsMatchRom': True, 'xsimPass': pass_line}}
    destination = ROOT / 'docs/lab/data/board-trace.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    print(pass_line)
    print(f'Exported {destination} ({len(rows)} rows)', flush=True)


if __name__ == '__main__':
    main()
