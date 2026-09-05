"""Run the single-cycle RTL regression with XSim; fail on missing PASS."""
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build' / 'single_cycle'
VIVADO = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))

def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    commands = [
        ['xvlog.bat', '--work', 'xil_defaultlib', '--sv', str(ROOT/'rtl/core/single_cycle_cpu.v'), str(ROOT/'tests/tb_single_cycle.sv')],
        ['xelab.bat', 'xil_defaultlib.tb_single_cycle', '-s', 'single_cycle_sim'],
        ['xsim.bat', 'single_cycle_sim', '-runall'],
    ]
    transcript = []
    for command in commands:
        command[0] = str(VIVADO / command[0])
        result = subprocess.run(command, cwd=BUILD, capture_output=True, text=True, errors='replace')
        output = result.stdout + result.stderr
        transcript.append('COMMAND: ' + subprocess.list2cmdline(command) + '\n' + output)
        print(output, end='')
        (BUILD/'regression.log').write_text('\n'.join(transcript), encoding='utf-8')
        if result.returncode:
            return result.returncode
    failed = re.search(r'(?im)\b(?:FAIL|FATAL|ERROR)\b', '\n'.join(transcript))
    return 0 if output.count('PASS single_cycle') == 1 and not failed else 1

if __name__ == '__main__':
    sys.exit(main())
