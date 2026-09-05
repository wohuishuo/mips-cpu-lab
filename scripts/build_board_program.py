"""Assemble the actual board ROM with MARS, without executing its endless loop."""
from pathlib import Path
import os, subprocess, json, hashlib
root = Path(__file__).resolve().parents[1]
work = root/'build/board'; work.mkdir(parents=True, exist_ok=True)
jar = Path(os.environ.get('MARS_JAR', root.parent/'资源-20260905/mars4_5.jar'))
output = work/'program.hex'
p = subprocess.run(['java','-jar',str(jar),'nc','a','db','ae2','dump','.text','HexText',str(output),str(root/'software/board_demo.S')], capture_output=True, timeout=60)
(work/'mars.log').write_bytes(p.stdout+p.stderr)
if p.returncode: raise RuntimeError((p.stdout+p.stderr).decode(errors='replace'))
words = output.read_text().split()
assert 0 < len(words) <= 1024
rom = work/'board_rom.hex'
rom.write_text('\n'.join(words + ['00000000']*(1024-len(words)))+'\n')
(work/'rom.json').write_text(json.dumps({'assembler':'MARS 4.5','delay_slots':True,'reset_pc':'00400000','words':len(words),'sha256':hashlib.sha256(rom.read_bytes()).hexdigest()},indent=2))
print(f'PASS BOARD_ROM words={len(words)}')
