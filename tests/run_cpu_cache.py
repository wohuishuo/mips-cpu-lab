"""Actual pipeline/cache integration with independent ISA, memory and LRU oracles."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/cpu-cache'
MASK = 0xffffffff
MMIO = 0xffff0000


def ins_i(op, rs, rt, imm):
    return op << 26 | rs << 21 | rt << 16 | (imm & 65535)


def ins_r(rs, rt, rd, fn):
    return rs << 21 | rt << 16 | rd << 11 | fn


def program():
    code, listing = [], []

    def emit(word, comment):
        listing.append(f'    .word 0x{word:08x} # PC {len(code)*4:04x}: {comment}')
        code.append(word)

    def imm(op, rs, rt, value, comment):
        emit(ins_i(op, rs, rt, value), comment)

    imm(15, 0, 20, 0xffff, 'lui r20,0xffff ; uncached MMIO')
    imm(9, 0, 1, 0x1000, 'addiu r1,r0,0x1000 ; Fibonacci destination')
    imm(9, 0, 2, 0, 'addiu r2,r0,0 ; F0')
    imm(9, 0, 3, 1, 'addiu r3,r0,1 ; F1')
    imm(9, 0, 4, 20, 'addiu r4,r0,20')
    loop = len(code)
    imm(43, 1, 2, 0, 'sw r2,0(r1) ; actual Fibonacci loop')
    imm(35, 1, 5, 0, 'lw r5,0(r1)')
    emit(ins_r(5, 3, 6, 0x21), 'addu r6,r5,r3 ; immediate load use')
    emit(ins_r(3, 0, 2, 0x21), 'addu r2,r3,r0')
    emit(ins_r(6, 0, 3, 0x21), 'addu r3,r6,r0')
    imm(43, 20, 4, 0, 'sw r4,0(r20) ; exactly once per iteration')
    imm(9, 1, 1, 4, 'addiu r1,r1,4')
    imm(9, 4, 4, -1, 'addiu r4,r4,-1')
    imm(5, 4, 0, loop - len(code) - 1, 'bne r4,r0,fibonacci_loop')
    emit(0, 'nop ; branch delay slot')
    imm(8, 0, 7, -7, 'addi r7,r0,-7 ; successful signed arithmetic')
    imm(8, 7, 8, 12, 'addi r8,r7,12')
    emit(ins_r(7, 8, 9, 0x20), 'add r9,r7,r8')
    emit(ins_r(8, 7, 10, 0x22), 'sub r10,r8,r7')
    imm(15, 0, 11, 0x80ff, 'lui r11,0x80ff')
    imm(13, 11, 11, 0x81fe, 'ori r11,r11,0x81fe')
    imm(43, 0, 11, 0x2300, 'sw r11,0x2300(r0)')
    for lane in range(4):
        imm(9, 0, 12, 0x90 + lane, f'addiu r12,r0,{0x90+lane}')
        imm(40, 0, 12, 0x2300 + lane, f'sb r12,0x{0x2300+lane:x}(r0)')
        imm(32, 0, 13, 0x2300 + lane, 'lb r13,lane(r0) ; sign extend')
        imm(36, 0, 14, 0x2300 + lane, 'lbu r14,lane(r0)')
    for lane in (0, 2):
        imm(41, 0, 11, 0x2304 + lane, 'sh r11,halfword(r0)')
        imm(33, 0, 13, 0x2304 + lane, 'lh r13,halfword(r0)')
        imm(37, 0, 14, 0x2304 + lane, 'lhu r14,halfword(r0)')
    # Three dirty tags mapping to set zero in both tested geometries.
    for iteration in range(6):
        for tag in range(3):
            address = 0x2000 + tag * 0x100
            imm(9, 0, 15, 100 + iteration * 3 + tag, 'addiu r15,r0,unique_value')
            imm(43, 0, 15, address, f'sw r15,0x{address:x}(r0) ; conflicting dirty tag')
            imm(43, 20, 15, 4, 'sw r15,4(r20) ; MMIO behind cache miss')
            imm(35, 0, 16, address, 'lw r16,conflicting_address(r0)')
            emit(ins_r(16, 15, 17, 0x21), 'addu r17,r16,r15 ; load-use forwarding')
    imm(35, 20, 18, 8, 'lw r18,8(r20) ; uncached constant read')
    emit(ins_r(18, 10, 19, 0x21), 'addu r19,r18,r10')
    # Two fresh clean tags for every set evict every possible dirty way.
    for base in (0x4000, 0x5000):
        for offset in range(0, 256, 8):
            imm(35, 0, 21, base + offset, 'lw r21,flush_address(r0) ; eviction sweep')
    imm(9, 0, 22, 0x600d, 'addiu r22,r0,0x600d ; final retired marker')
    stop = len(code) * 4
    emit(2 << 26 | stop // 4, 'halt: j halt')
    emit(0, 'nop')
    return code, listing, stop


def generate(sets, words, mutate=False):
    code, listing, stop = program()
    (ROOT / 'software/cache_joint.S').write_text(
        '# Project-owned encoded MIPS fixture. Little endian; reset PC 0.\n'
        '# .word preserves exact instructions and explicit delay slots; no MARS claim.\n.text\n'
        + '\n'.join(listing) + '\n', encoding='utf-8', newline='\n')
    (ROOT / 'software/cache_joint.hex').write_text(''.join(f'{v:08x}\n' for v in code), newline='\n')
    (BUILD / 'cache_program.hex').write_text(''.join(f'{v:08x}\n' for v in code + [0] * (1024-len(code))))
    regs, memory = [0]*32, [0]*8192
    traces, requests = [], []
    lines = [[] for _ in range(sets)]  # oldest first, (line number, dirty)
    hits = misses = writebacks = mmio_writes = 0
    pc, pending = 0, None
    while pc != stop:
        assert len(traces) < 10000
        word = code[pc//4]
        op, rs, rt, rd, fn = word >> 26, (word >> 21)&31, (word >> 16)&31, (word >> 11)&31, word&63
        immediate = word & 65535
        signed = immediate if immediate < 32768 else immediate - 65536
        a, b = regs[rs], regs[rt]
        we = strobe = address = data = value = 0
        destination, target = rt, None
        if op == 0:
            destination, we = rd, 1
            if fn == 0:
                value = b << ((word >> 6)&31)
            elif fn in (0x20, 0x21):
                value = a+b
            elif fn == 0x22:
                value = a-b
            else:
                raise AssertionError(hex(word))
        elif op in (8, 9, 13, 15):
            we = 1
            value = {8: a+signed, 9: a+signed, 13: a|immediate, 15: immediate<<16}[op]
        elif op == 5:
            target = pc+4+signed*4 if a != b else pc+8
        elif op in (32, 33, 35, 36, 37, 40, 41, 43):
            address = (a+signed)&MASK
            write = op in (40, 41, 43)
            size = {32:1, 33:2, 35:4, 36:1, 37:2, 40:1, 41:2, 43:4}[op]
            assert address % size == 0
            uncached = address >= MMIO
            read_word = 0x13579bdf if uncached else memory[address//4]
            if write:
                strobe = ((1 << size)-1) << (address&3)
                data = (b << (8*(address&3)))&MASK
                if uncached:
                    mmio_writes += 1
                else:
                    for lane in range(4):
                        if strobe & (1 << lane):
                            memory[address//4] = (memory[address//4]&~(255 << (8*lane))) | (data&(255 << (8*lane)))
            else:
                we = 1
                value = (read_word >> (8*(address&3))) & ((1 << (8*size))-1)
                if op in (32, 33) and value & (1 << (8*size-1)):
                    value -= 1 << (8*size)
            requests.append((int(write), address, data, strobe, read_word))
            if not uncached:
                line = address // (4*words)
                ways = lines[line % sets]
                match = next((entry for entry in ways if entry[0] == line), None)
                if match is not None:
                    hits += 1
                    ways.remove(match)
                    ways.append((line, match[1] or write))
                else:
                    misses += 1
                    if len(ways) == 2:
                        writebacks += int(ways.pop(0)[1])
                    ways.append((line, write))
        else:
            raise AssertionError(hex(word))
        value &= MASK
        we = int(bool(we and destination))
        if we:
            regs[destination] = value
        traces.append((pc, word, we, destination if we else 0, value if we else 0,
                       strobe, address if strobe else 0, data if strobe else 0))
        pc, pending = pending if pending is not None else pc+4, target
    fib = [0, 1]
    for _ in range(18):
        fib.append(fib[-1]+fib[-2])
    assert memory[0x1000//4:0x1000//4+20] == fib
    assert memory[0x2300//4] == 0x93929190 and memory[0x2304//4] == 0x81fe81fe
    assert all(not dirty for ways in lines for _, dirty in ways), 'flush did not evict every dirty line'
    if mutate:
        row = list(traces[0]); row[4] ^= 1; traces[0] = tuple(row)
    for name, rows in [('cache_trace.txt', traces), ('cache_requests.txt', requests)]:
        (BUILD/name).write_text(str(len(rows))+'\n'+''.join(' '.join(f'{v:x}' for v in row)+'\n' for row in rows))
    (BUILD/'cache_memory.hex').write_text(''.join(f'{v:08x}\n' for v in memory))
    summary = dict(sets=sets, words=words, retirements=len(traces), requests=len(requests),
                   hits=hits, misses=misses, writebacks=writebacks, mmio_writes=mmio_writes)
    (BUILD/'cache_counts.txt').write_text(f'{hits} {misses} {writebacks} {mmio_writes}\n')
    (BUILD/f'oracle_{sets}_{words}.json').write_text(json.dumps(summary, indent=2)+'\n')
    print('ORACLE', summary, flush=True)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    mutate = '--mutate' in sys.argv
    vivado = Path(os.environ.get('VIVADO_BIN', 'E:/Xilinx/Vivado/2019.2/bin'))
    transcript = []
    log = BUILD / ('mutation.log' if mutate else 'regression.log')
    for sets, words in [(16, 4), (4, 2)]:
        generate(sets, words, mutate)
        for tool, args in [
            ('xvlog', ['--sv', '--work', 'xil_defaultlib',
                       *(['--define', 'JOINT_SMALL'] if sets == 4 else []),
                       *[str(ROOT/name) for name in ['rtl/core/cp0.v', 'rtl/core/pipeline_cpu.v',
                         'rtl/cache/data_cache.v', 'rtl/integration/cached_cpu.v', 'tests/tb_cpu_cache.sv']]]),
            ('xelab', ['--debug', 'typical', 'xil_defaultlib.tb_cpu_cache', '-s', 'cpu_cache_test']),
            ('xsim', ['cpu_cache_test', '-runall'])]:
            p = subprocess.run([str(vivado/(tool+'.bat')), *args], cwd=BUILD,
                               capture_output=True, text=True, errors='replace', timeout=180)
            output = p.stdout+p.stderr
            transcript.append(output)
            print(output, end='', flush=True)
            log.write_text('\n'.join(transcript), encoding='utf-8')
            if p.returncode or re.search(r'(?im)\b(FAIL|FATAL|ERROR)\b', output):
                return 1
        if output.count(f'PASS cpu-cache SETS={sets} WORDS={words}') != 1:
            return 1
    print('CPU_CACHE_TESTS_PASS configurations=2 memory_modes=3')
    return 0


if __name__ == '__main__':
    sys.exit(main())
