from pathlib import Path
import json
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
work = root / 'build/mars_rtl'
tools = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))


def main():
    work.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            [sys.executable, str(root / 'scripts/build_mars_program.py')],
            check=True,
            timeout=60,
        )
        for tool, args in [
            ('xvlog', ['--sv', '--work', 'xil_defaultlib',
                       str(root/'rtl/core/single_cycle_cpu.v'),
                       str(root/'tests/tb_mars_program.sv')]),
            ('xelab', ['xil_defaultlib.tb_mars_program', '-s', 'mars_program']),
            ('xsim', ['mars_program', '-runall']),
        ]:
            executable = tools / (tool + '.bat')
            if not executable.is_file():
                raise FileNotFoundError(
                    f'Vivado tool not found: {executable}; set VIVADO_BIN'
                )
            process = subprocess.run(
                [str(executable), *args], cwd=work, capture_output=True, timeout=180
            )
            text = (process.stdout + process.stderr).decode('utf-8', errors='replace')
            (work / (tool + '.txt')).write_text(text, encoding='utf-8')
            if process.returncode or 'FAIL ' in text or 'Fatal:' in text:
                raise RuntimeError(text)
            if tool == 'xsim':
                markers = [line for line in text.splitlines()
                           if line.startswith('PASS MARS_TO_RTL')]
                if len(markers) != 1:
                    raise RuntimeError('Missing PASS MARS_TO_RTL marker')
                (work / 'result.json').write_text(
                    json.dumps({'passed': True, 'result': markers[0]}, indent=2) + '\n',
                    encoding='utf-8',
                )
                print(markers[0])
    except (OSError, RuntimeError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as error:
        print(f'FAIL MARS_TO_RTL runner: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
