"""Rebuild the local lab5 19-point program in a private Ubuntu GNU environment.

Requires an already working root-capable WSL distribution. The ext4 image,
downloads, copied course inputs and all outputs stay below build/gnu-rebuild.
No distribution is registered and no Docker/WSL system setting is changed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE_URL = 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.4/release/'
ARCHIVE = 'ubuntu-base-24.04.4-base-amd64.tar.gz'
ARCHIVE_SHA256 = 'c1e67ef7b17a6300e136118bd1dc04725009cb376c1aad10abcf8cd453628d58'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def source_hashes(source):
    return {p.relative_to(source).as_posix(): digest(p)
            for p in sorted(source.rglob('*')) if p.is_file()}


def coe_words(path):
    text = path.read_text()
    if not re.search(r'memory_initialization_radix\s*=\s*16\s*;', text, re.I):
        raise ValueError('Expected hexadecimal COE')
    body = re.split(r'memory_initialization_vector\s*=', text, flags=re.I)[1]
    words = re.split(r'[\s,;]+', body.strip())
    return [int(w, 16) for w in words if w]


def linux_path(path, host_root):
    value = path.resolve().as_posix()
    if not re.match(r'^[A-Za-z]:/', value):
        raise ValueError('This WSL bootstrap runner expects an absolute Windows drive path')
    return host_root.rstrip('/') + '/' + value[0].lower() + value[2:]


def run_logged(command, log, timeout, env=None):
    # Capture separately: WSL's relay can write stdout/stderr using independent
    # offsets when both refer to the same Windows file handle.
    try:
        process = subprocess.run(command, capture_output=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired as error:
        log.write_bytes((error.stdout or b'') + b'\n' + (error.stderr or b''))
        raise
    log.write_bytes(process.stdout + b'\n' + process.stderr)
    if process.returncode:
        raise RuntimeError(f'Command exited {process.returncode}; see {log}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lab5', type=Path, default=Path(os.environ.get(
        'BITMIPS_LAB5', ROOT.parent/'bitmips_experiments-master/bitmips_experiments-master/lab5')))
    parser.add_argument('--distro', default='docker-desktop')
    parser.add_argument('--wsl-host-root', default='/mnt/host',
                        help='Use /mnt for ordinary Ubuntu WSL; Docker Desktop uses /mnt/host')
    parser.add_argument('--bootstrap', action='store_true',
                        help='Download Ubuntu Base and install GNU packages only in the private image')
    parser.add_argument('--match-supplied-layout', action='store_true',
                        help='Order archive members by original startup JAL targets, preserving golden PCs')
    parser.add_argument('--verify', action='store_true',
                        help='Run unchanged supplied golden in an isolated teach_soc copy; requires identical ROM')
    parser.add_argument('--timeout', type=int, default=1800)
    args = parser.parse_args()
    work = ROOT/'build/gnu-rebuild'
    work.mkdir(parents=True, exist_ok=True)
    result_file = work/'result.json'
    result_file.unlink(missing_ok=True)
    lab = args.lab5.resolve()
    source = lab/'teach_soft/func_test'
    before = source_hashes(source)
    if not before or 'start.S' not in before:
        raise FileNotFoundError(f'No course source tree at {source}')
    startup = re.sub(r'/\*.*?\*/', '', (source/'start.S').read_text(), flags=re.S)
    calls = re.findall(r'^\s*jal\s+(n\d+_\w+_test)\b', startup, re.M)
    if len(calls) != 19 or not re.search(r'#define\s+TEST_NUM\s+19\b', startup):
        raise ValueError('This build profile requires the original 19-point configuration')
    (work/'source-sha256.json').write_text(json.dumps(before, indent=2)+'\n')
    archive = work/ARCHIVE
    if args.bootstrap and not archive.exists():
        temporary = archive.with_suffix('.download')
        urllib.request.urlretrieve(BASE_URL+ARCHIVE, temporary)
        if digest(temporary) != ARCHIVE_SHA256:
            raise ValueError('Official Ubuntu Base archive SHA-256 mismatch')
        temporary.replace(archive)
    if not archive.is_file() or digest(archive) != ARCHIVE_SHA256:
        raise ValueError('Missing or incorrect Ubuntu Base archive; use --bootstrap')
    if not args.bootstrap and not (work/'ubuntu.ext4').is_file():
        raise ValueError('Missing private environment; use --bootstrap')

    # A fresh source-only staging tree prevents precompiled objects or the old
    # 32-bit host converter from satisfying Makefile timestamps.
    copy = Path(tempfile.mkdtemp(prefix='source-', dir=work))
    for rel in before:
        path = Path(rel)
        if path.suffix.lower() in ('.s', '.h', '.c', '.make') or path.name == 'Makefile':
            target = copy/path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source/path, target)
    # GCC 12's default FP register width conflicts with the original -mips1.
    # The course program uses integer instructions; preserve all original flags
    # and add the explicit MIPS-I-compatible register width in the copy only.
    makefile = copy/'Makefile'
    make_text = makefile.read_text()
    if make_text.count('export TOPDIR AR CFLAGS') != 1:
        raise ValueError('Unexpected course Makefile export anchor')
    makefile.write_text(make_text.replace('export TOPDIR AR CFLAGS',
                       'CFLAGS += -mfp32\n\nexport TOPDIR AR CFLAGS'), newline='\n')
    # Binutils 2.42 emits .MIPS.abiflags, absent from the historic linker script.
    # Its orphan LMA overlaps the script's AT(rodata_end) .data placement.
    # This is ELF ABI metadata, not executed code or initialized CPU memory.
    linker = copy/'bin.lds.S'
    link_text = linker.read_text()
    end = link_text.rfind('}')
    if end < 0:
        raise ValueError('Unexpected course linker script')
    linker.write_text(link_text[:end] + '  /DISCARD/ : { *(.MIPS.abiflags) }\n' +
                      link_text[end:], newline='\n')
    layout = []
    if args.match_supplied_layout:
        original_rom = coe_words(lab/'teach_soft/inst_ram.coe')
        # Startup occupies 0x000..0x31f in this specific supplied profile.
        # The 19 direct JALs call the 19 source-listed functions in the same
        # order. Their encoded targets give an independent original layout.
        targets = [0xb0000000 | ((word & 0x3ffffff) << 2)
                   for word in original_rom[:0x320//4] if word >> 26 == 3
                   and (0xb0000000 | ((word & 0x3ffffff) << 2)) >= 0xbfc00320]
        if len(targets) != 19 or len(set(targets)) != 19:
            raise ValueError('Unexpected supplied startup JAL layout')
        layout = sorted(zip(calls, targets), key=lambda item: item[1])
        members = [name.removesuffix('_test')+'.o' for name, _ in layout]
        available = sorted(path.stem+'.o' for path in (copy/'inst').glob('*.S'))
        if any(member not in available for member in members):
            raise ValueError('Startup call does not map to its assembly unit')
        members += [member for member in available if member not in members]
        inst_make = copy/'inst/Makefile'
        text = inst_make.read_text()
        anchor = 'objs = $(patsubst %.S, %.o, $(srcs))'
        if text.count(anchor) != 1:
            raise ValueError('Unexpected archive member definition')
        inst_make.write_text(text.replace(anchor, 'objs = '+' '.join(members)), newline='\n')

    base = shlex.quote(linux_path(work, args.wsl_host_root))
    install = '''
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Languages=none -o Acquire::Retries=2 -o Acquire::http::Timeout=30 update
apt-get -y --no-install-recommends -o Acquire::Retries=2 -o Acquire::http::Timeout=30 install gcc make libc6-dev gcc-mipsel-linux-gnu binutils-mipsel-linux-gnu
''' if args.bootstrap else ''
    inner = '''set -eu
''' + install + '''
dpkg-query -W > /work/packages.txt
{ gcc --version; mipsel-linux-gnu-gcc --version; mipsel-linux-gnu-ld --version; } > /work/tool-versions.txt
cd /work/SOURCE_DIRECTORY
make CROSS_COMPILE=mipsel-linux-gnu-
mipsel-linux-gnu-readelf -a obj/main.elf > /work/readelf.txt
mipsel-linux-gnu-nm -n obj/main.elf > /work/symbols.txt
'''
    inner = inner.replace('SOURCE_DIRECTORY', copy.name)
    (work/'inside.sh').write_text(inner, encoding='utf-8', newline='\n')
    shell = f'''#!/bin/sh
set -eu
base={base}
root="$base/rootfs"
mount --make-rprivate /
mkdir -p "$root"
if [ ! -f "$base/ubuntu.ext4" ]; then
    truncate -s 2G "$base/ubuntu.ext4"
    mkfs.ext4 -F "$base/ubuntu.ext4"
fi
mount -o loop "$base/ubuntu.ext4" "$root"
trap 'umount -R "$root"' EXIT
if [ ! -f "$root/etc/os-release" ]; then
    tar -xzf "$base/{ARCHIVE}" -C "$root"
fi
cp /etc/resolv.conf "$root/etc/resolv.conf"
mount --bind /dev "$root/dev"
mount -t proc proc "$root/proc"
mkdir -p "$root/work"
mount --bind "$base" "$root/work"
chroot "$root" /bin/bash /work/inside.sh
'''
    shell_file = work/'rebuild.sh'
    shell_file.write_text(shell, encoding='utf-8', newline='\n')
    run_logged(['wsl', '-d', args.distro, '-u', 'root', '--', 'timeout', '-k', '15',
                str(args.timeout), 'unshare', '-m', 'sh',
                linux_path(shell_file, args.wsl_host_root)], work/'rebuild.log', args.timeout+30)
    shutil.copy2(work/'rebuild.log', copy/'rebuild.log')
    shutil.copy2(work/'packages.txt', copy/'packages.txt')
    shutil.copy2(work/'tool-versions.txt', copy/'tool-versions.txt')
    after = source_hashes(source)
    if after != before:
        raise RuntimeError('Original course source hashes changed during the build')
    rebuilt = coe_words(copy/'obj/inst_ram.coe')
    supplied = coe_words(lab/'teach_soft/inst_ram.coe')
    differences = [{'word': i, 'supplied': f'{a:08x}', 'rebuilt': f'{b:08x}'}
                   for i, (a, b) in enumerate(zip(supplied, rebuilt)) if a != b]
    result = {
        'status': 'PASS GNU_REBUILD', 'enabled_points': len(calls), 'enabled_calls': calls,
        'ubuntu_base_url': BASE_URL+ARCHIVE, 'ubuntu_base_sha256': ARCHIVE_SHA256,
        'original_sources_unchanged': before == after,
        'source_files': len(before), 'source_hashes': before,
        'build_source_directory': copy.relative_to(ROOT).as_posix(),
        'supplied_layout_order': [{'function': name, 'address': f'{addr:08x}'}
                                  for name, addr in layout],
        'compatibility_adjustments': ['CROSS_COMPILE=mipsel-linux-gnu-',
                                     'CFLAGS += -mfp32 in copied Makefile only',
                                     'Discard .MIPS.abiflags in copied linker script only'],
        'outputs_sha256': {p.name: digest(p) for p in sorted((copy/'obj').iterdir()) if p.is_file()},
        'supplied_rom_sha256': digest(lab/'teach_soft/inst_ram.coe'),
        'rom_comparison': {'supplied_words': len(supplied), 'rebuilt_words': len(rebuilt),
                           'identical_words': rebuilt == supplied,
                           'differing_common_words': len(differences),
                           'first_differences': differences[:32]},
        'tool_versions': (work/'tool-versions.txt').read_text(),
        'scope': 'Actual GNU preprocessing, assembly, linking and host converter build. '
                 'Compilation does not by itself establish CPU functional correctness.',
    }
    if args.verify:
        if rebuilt != supplied:
            raise ValueError('Unchanged golden requires an identical ROM; use --match-supplied-layout')
        project = copy/'verification-project'
        shutil.copytree(ROOT/'rtl', project/'rtl')
        shutil.copytree(ROOT/'tests', project/'tests', ignore=shutil.ignore_patterns('__pycache__'))
        overlay = copy/'verification-lab5'
        original_files = (
            'golden_trace.txt', 'teach_soft/func_test/start.S',
            'teach_soc/teach_soc.srcs/sources_1/new/teach_soc_top.v',
            'teach_soc/teach_soc.srcs/sources_1/new/bridge/bridge_1x2.v',
            'teach_soc/teach_soc.srcs/sources_1/new/confreg/confeg.v',
        )
        for relative in original_files:
            destination = overlay/relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(lab/relative, destination)
        shutil.copy2(copy/'obj/inst_ram.coe', overlay/'teach_soft/inst_ram.coe')
        golden_digest = digest(lab/'golden_trace.txt')
        environment = dict(os.environ, BITMIPS_LAB5=str(overlay))
        run_logged([sys.executable, str(project/'tests/run_teach_soc.py')],
                   copy/'verification.log', 600, environment)
        result['simulation'] = json.loads((project/'build/teach_soc/normal/result.json').read_text())
        if digest(lab/'golden_trace.txt') != golden_digest or digest(overlay/'golden_trace.txt') != golden_digest:
            raise RuntimeError('Golden trace changed')
        result['golden_sha256_unchanged'] = golden_digest
    (copy/'build-result.json').write_text(json.dumps(result, indent=2)+'\n')
    result_file.write_text(json.dumps(result, indent=2)+'\n')
    print(f'PASS GNU_REBUILD points=19 words={len(rebuilt)} identical_supplied={rebuilt == supplied}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'FAIL GNU_REBUILD: {error}', file=sys.stderr)
        sys.exit(1)
