from pathlib import Path
import os
import subprocess
import json
import sys

root = Path(__file__).resolve().parents[1]
work = root / 'build/cp0'
tools = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))


def main():
    work.mkdir(parents=True, exist_ok=True)
    steps = [
        ('xvlog', ['--sv', '--work', 'xil_defaultlib', str(root/'rtl/core/cp0.v'),
                   str(root/'tests/tb_cp0.sv')]),
        ('xelab', ['xil_defaultlib.tb_cp0', '-s', 'cp0_test']),
        ('xsim', ['cp0_test', '-runall']),
    ]
    results = []
    try:
        for name, args in steps:
            tool = tools / (name + '.bat')
            if not tool.is_file():
                raise FileNotFoundError(f'Vivado tool not found: {tool}; set VIVADO_BIN')
            process = subprocess.run(
                [str(tool), *args], cwd=work, capture_output=True, timeout=180
            )
            text = (process.stdout + process.stderr).decode('utf-8', errors='replace')
            (work / (name + '.txt')).write_text(text, encoding='utf-8')
            results.append({'step': name, 'returncode': process.returncode})
            print(name, process.returncode, flush=True)
            if process.returncode or 'Fatal:' in text or 'FAIL ' in text:
                print(text[-2500:])
                return 1
            if name == 'xsim':
                lines = [line for line in text.splitlines() if line.startswith('PASS CP0')]
                if len(lines) != 1:
                    raise RuntimeError('Missing completion marker')
                print(lines[0])
                results[-1]['result'] = lines[0]
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'FAIL CP0 runner: {error}', file=sys.stderr)
        return 1
    (work / 'result.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
