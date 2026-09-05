"""Run unmodified local lab5 teach_soc with owned adapter and synchronous IP models."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mutate', choices=['wrong-golden', 'truncated-golden',
                                            'extra-golden', 'missing-golden', 'timeout'])
    args = parser.parse_args()
    work = ROOT / 'build/teach_soc' / (args.mutate or 'normal')
    work.mkdir(parents=True, exist_ok=True)
    # Remove stale success evidence before any run can fail.
    (work / 'result.json').unlink(missing_ok=True)
    lab = Path(os.environ.get('BITMIPS_LAB5', ROOT.parent /
               'bitmips_experiments-master/bitmips_experiments-master/lab5')).resolve()
    sources = {
        'rom': lab / 'teach_soft/inst_ram.coe',
        'golden': lab / 'golden_trace.txt',
        'top': lab / 'teach_soc/teach_soc.srcs/sources_1/new/teach_soc_top.v',
        'bridge': lab / 'teach_soc/teach_soc.srcs/sources_1/new/bridge/bridge_1x2.v',
        'confreg': lab / 'teach_soc/teach_soc.srcs/sources_1/new/confreg/confeg.v',
        'startup': lab / 'teach_soft/func_test/start.S',
    }
    for name, path in sources.items():
        if not path.is_file():
            raise FileNotFoundError(f'Missing local supplied {name}: {path}; set BITMIPS_LAB5')
    startup = re.sub(r'/\*.*?\*/', '', sources['startup'].read_text(), flags=re.S)
    enabled = re.findall(r'^\s*jal\s+(n\d+_\w+_test)\b', startup, flags=re.M)
    if len(enabled) != 19 or not re.search(r'#define\s+TEST_NUM\s+19\b', startup):
        raise ValueError('This replay profile requires the supplied 19-point startup')
    coe = sources['rom'].read_text()
    if not re.search(r'memory_initialization_radix\s*=\s*16\s*;', coe, re.I):
        raise ValueError('Expected hexadecimal supplied COE')
    body = re.split(r'memory_initialization_vector\s*=', coe, flags=re.I)[1]
    # Supplied file has newline-separated words and omits commas/final semicolon.
    words = re.split(r'[\s,]+', body.strip().removesuffix(';').strip())
    if not 0 < len(words) <= 65536 or any(not re.fullmatch(r'[0-9a-fA-F]{8}', w) for w in words):
        raise ValueError('Invalid COE vector')
    (work / 'upstream_rom.hex').write_text('\n'.join(words + ['00000000'] * (65536-len(words)))+'\n')
    golden = sources['golden'].read_text().splitlines()
    if len(golden) != 28970 or any(not re.fullmatch(r'\s*[0-9a-fA-F]{8}\s+[0-9a-fA-F]{8}\s+[0-9a-fA-F]{2}\s+[0-9a-fA-F]{8}\s*', row) for row in golden):
        raise ValueError('Expected the supplied 28,970-row golden trace')
    if args.mutate == 'wrong-golden':
        fields = golden[0].split()
        fields[3] = f'{int(fields[3], 16) ^ 1:08x}'
        golden[0] = ' '.join(fields)
    elif args.mutate == 'truncated-golden':
        golden = golden[:-1]
    elif args.mutate == 'extra-golden':
        golden.append(golden[-1])
    golden_path = work / 'golden_trace.txt'
    if args.mutate == 'missing-golden':
        golden_path.unlink(missing_ok=True)
    else:
        golden_path.write_text('\n'.join(golden)+'\n')

    vivado = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))
    # Original top uses the legal Verilog identifier `int`; parse original .v
    # in Verilog mode and owned testbench/models in SystemVerilog mode.
    steps = [
        ('xvlog', [str(sources[k]) for k in ('top', 'bridge', 'confreg')] +
         [str(ROOT / p) for p in ('rtl/core/cp0.v', 'rtl/core/pipeline_cpu.v',
                                  'rtl/integration/teach_mycpu_top.v')]),
        ('xvlog', ['--sv', str(ROOT/'tests/teach_memory_models.sv'), str(ROOT/'tests/tb_teach_soc.sv')]),
        ('xelab', ['tb_teach_soc', '-s', 'teach_soc_test']),
        ('xsim', ['teach_soc_test', '-runall'] +
         (['-testplusarg', 'EARLY_TIMEOUT'] if args.mutate == 'timeout' else [])),
    ]
    transcript = []
    for tool, argv in steps:
        process = subprocess.run([str(vivado/(tool+'.bat')), *argv], cwd=work,
                                 capture_output=True, text=True, errors='replace', timeout=180)
        output = process.stdout + process.stderr
        transcript.append(output)
        (work/'regression.log').write_text('\n'.join(transcript), encoding='utf-8')
        print(output, end='', flush=True)
        if process.returncode or re.search(r'(?im)\b(FAIL|FATAL|ERROR)\b', output):
            return 1
    markers = re.findall(r'^PASS TEACH_SOC .+$', output, re.M)
    if len(markers) != 1:
        raise RuntimeError('Expected exactly one PASS TEACH_SOC marker')
    result = {
        'result': markers[0], 'mutation': args.mutate,
        'rom_words': len(words),
        'enabled_startup_calls': enabled,
        'sources_sha256': {name: hashlib.sha256(path.read_bytes()).hexdigest()
                           for name, path in sources.items()},
        'scope': 'Unmodified supplied teach_soc_top/bridge/confreg; pipeline falling-edge '
                 'simulation adapter; synchronous behavioral SRAMs; 19 enabled supplied points. '
                 'No all-89, vendor-IP timing, synthesis, FPGA or board claim.',
    }
    (work/'result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'FAIL TEACH_SOC runner: {error}', file=sys.stderr)
        sys.exit(1)
