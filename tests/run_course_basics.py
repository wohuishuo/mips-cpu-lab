"""Verify owned lab1 plus local original lab1/lab3 integration; no teacher sources copied into git."""
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
    parser.add_argument('--mutate', choices=['lab1-missing', 'fib-store', 'adder-sum'])
    args = parser.parse_args()
    work = ROOT/'build/course_basics'/(args.mutate or 'normal')
    work.mkdir(parents=True, exist_ok=True)
    (work/'result.json').unlink(missing_ok=True)
    lab = Path(os.environ.get('BITMIPS_ROOT', ROOT.parent / 'bitmips_experiments-master/bitmips_experiments-master'))
    original1 = lab / 'lab1/num_led/num_led.srcs/sources_1/new/num_led.v'
    original3 = lab / 'lab3/single_cycle/single_cycle.srcs/sources_1/new'
    inputs = [original1, original3/'single_cycle.v', original3/'confreg/confreg.v']
    inputs += [original3/f'ip/{name}/{name}.xci' for name in ['inst_rom', 'data_ram']]
    inputs += [lab/f'lab3/soft/{name}.coe' for name in ['fibonacci', 'adder8bit']]
    for path in inputs:
        if not path.is_file():
            raise FileNotFoundError(f'Missing local course source {path}; set BITMIPS_ROOT')
    digests = {str(p.relative_to(lab)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    # Refuse to silently substitute the wrong IP latency/depth/width.
    for path in inputs[3:5]:
        config = dict(re.findall(r'referenceId="PARAM_VALUE\.(\w+)">([^<]+)', path.read_text()))
        required = {'depth': '1024', 'data_width': '32', 'input_options': 'non_registered', 'output_options': 'non_registered'}
        if any(config.get(k) != v for k, v in required.items()):
            raise ValueError(f'Unsupported original memory configuration: {path}')
    vivado = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))
    passes = []

    def run(name, sources, bench, plusargs=()):
        directory = work/name
        directory.mkdir(exist_ok=True)
        (directory/'testbench.sv').write_text(bench)
        top = f'tb_lab{1 if name.startswith("lab1") else 3}'
        waveform = name.startswith('lab1') or name == 'lab3_fibonacci_original'
        if waveform:
            (directory/'waves.tcl').write_text(f'log_wave -r /{top}/*\nrun all\nquit\n')
        commands = [('xvlog', ['--sv', *map(str, sources), str(directory/'testbench.sv')]),
                    ('xelab', [top, '-s', 'course_test']+(['-debug', 'typical'] if waveform else [])),
                    ('xsim', ['course_test', *(['-tclbatch', 'waves.tcl'] if waveform else ['-runall']),
                              *sum((['-testplusarg', p] for p in plusargs), [])])]
        transcript = []
        for tool, argv in commands:
            proc = subprocess.run([str(vivado/(tool+'.bat')), *argv], cwd=directory,
                                  capture_output=True, text=True, errors='replace', timeout=600)
            output = proc.stdout+proc.stderr
            transcript.append(output)
            (directory/'regression.log').write_text('\n'.join(transcript), encoding='utf-8')
            print(output, end='', flush=True)
            if proc.returncode or re.search(r'(?im)\b(FAIL|FATAL|ERROR)\b', output):
                raise RuntimeError(f'{name} failed; see {directory}/regression.log')
        markers = re.findall(r'^PASS LAB[13] .+$', output, re.M)
        if len(markers) != 1:
            raise RuntimeError(f'{name}: expected one PASS marker')
        passes.append({'test': name, 'result': markers[0]})

    tb1 = (ROOT/'tests/tb_lab1.sv').read_text()
    source1 = ROOT/'rtl/integration/lab1_num_led.v'
    if args.mutate in (None, 'lab1-missing'):
        if args.mutate is None:
            run('lab1_owned', [source1], tb1)
        # Locally retain course byte-write/button logic, replace its unfinished
        # display region by our owned helper, fix release typo and reset r2.
        text = original1.read_text()
        if args.mutate != 'lab1-missing':
            start = text.index('    reg [COUNTER_WIDTH - 1:0]  count;')
            end = text.index('    // center btn key', start)
            text = text[:start]+'''    lab1_hex_display #(.COUNTER_WIDTH(COUNTER_WIDTH)) display(
        .clk(clk),.rstn(rst),.value(num_led_value),.digital_num0(digital_num0),
        .digital_num1(digital_num1),.digital_cs(digital_cs));

'''+text[end:]
            text = text.replace('wire center_btn_key_end   = center_btn_key_r && center_btn_key;',
                                'wire center_btn_key_end   = center_btn_key_r && !center_btn_key;')
            text = text.replace('center_btn_key_r2 <= center_btn_key_r;', 'if (!rst) center_btn_key_r2 <= 0; else center_btn_key_r2 <= center_btn_key_r;')
        overlay = work/'original_num_led_filled.v'
        overlay.write_text(text)
        run('lab1_original_overlay', [source1, overlay], tb1.replace('`define LAB1_DUT lab1_num_led', '`define LAB1_DUT num_led'))

    def rom(name):
        coe = (lab/f'lab3/soft/{name}.coe').read_text()
        body = re.split(r'memory_initialization_vector\s*=', coe, flags=re.I)[1]
        values = [int(x, 16) for x in re.split(r'[\s,;]+', body.strip()) if x]
        if not 0 < len(values) <= 1024:
            raise ValueError('Invalid lab3 ROM length')
        return values

    def lab3(name, program, mode, fast=False):
        directory = work/name
        directory.mkdir(exist_ok=True)
        words = rom(program)
        if fast:
            index, old = (34, [0x3c070131, 0x34e72d00]) if program == 'fibonacci' else (39, [0x3c070001, 0x34e786a0])
            if words[index:index+2] != old:
                raise ValueError('Unrecognized delay loop; refusing image edit')
            words[index:index+2] = [0x3c070000, 0x34e70004]
        if args.mutate == 'fib-store':
            words[16] ^= 4  # first array store shifted by one word
        if args.mutate == 'adder-sum':
            words[30] = 0x016c6822  # SUB replaces ADD
        (directory/'program.hex').write_text('\n'.join(f'{w:08x}' for w in words+[0]*(1024-len(words)))+'\n')
        confreg = original3/'confreg/confreg.v'
        if mode == 3:
            # Explicit timing-only simulation overlay, original port/logic retained.
            text = confreg.read_text()
            for button in ['mid', 'left', 'right', 'up', 'down']:
                text = text.replace(f'reg [19:0]  {button}_btn_key_count;', f'reg [3:0]  {button}_btn_key_count;')
                text = text.replace(f'{button}_btn_key_count[19]', f'{button}_btn_key_count[3]')
            confreg = directory/'confreg_fast.v'
            confreg.write_text(text)
        sources = [original3/'single_cycle.v', confreg, ROOT/'rtl/core/single_cycle_cpu.v',
                   ROOT/'rtl/integration/lab3_mycpu.v', ROOT/'tests/course_memory_models.sv']
        run(name, sources, (ROOT/'tests/tb_lab3.sv').read_text(), [f'MODE{mode}'])

    if args.mutate in (None, 'fib-store'):
        lab3('lab3_fibonacci_original', 'fibonacci', 0)
    if args.mutate is None:
        lab3('lab3_fibonacci_fast_display', 'fibonacci', 1, True)
        lab3('lab3_adder_original', 'adder8bit', 2)
    if args.mutate in (None, 'adder-sum'):
        lab3('lab3_adder_boundaries', 'adder8bit', 3, True)
    if any(hashlib.sha256(p.read_bytes()).hexdigest()!=digests[str(p.relative_to(lab))] for p in inputs):
        raise RuntimeError('Original course input changed during run')
    (work/'result.json').write_text(json.dumps({'passes': passes, 'sources_sha256': digests,
        'scope': 'Simulation of original lab3 top with owned CPU and asynchronous distributed-memory models. '
                 'Original Fibonacci computes all 20 RAM words/first display; original adder tests 255+255. '
                 'Explicit accelerated overlays test all 20 display writes and 36 boundary input pairs. '
                 'Lab1 owned implementation and local original skeleton with display/button repairs. No board claim.'}, indent=2)+'\n')
    print(f'PASS COURSE_BASICS profiles={len(passes)}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'FAIL COURSE_BASICS: {error}', file=sys.stderr)
        sys.exit(1)
