"""Assemble and execute original Fibonacci in MARS, retain verified images."""
from pathlib import Path
import os
import subprocess
import json
import hashlib

root=Path(__file__).resolve().parents[1]
work=root/'build/mars';work.mkdir(parents=True,exist_ok=True)
jar=Path(os.environ.get('MARS_JAR',str(root.parent/'资源-20260905/mars4_5.jar')))
cmd=['java','-jar',str(jar),'nc','db','ae2','se3','500','sm',
     'dump','.text','HexText',str(work/'program.hex'),
     'dump','.data','HexText',str(work/'data.hex'),str(root/'software/fibonacci_mars.S')]
p=subprocess.run(cmd,capture_output=True,timeout=30)
text=(p.stdout+p.stderr).decode('utf-8',errors='replace')
(work/'mars.txt').write_text(text,encoding='utf-8')
if p.returncode:raise RuntimeError(text)
expected=[0,1,1,2,3,5,8,13,21,34,55,89]
actual=[int(x,16) for x in (work/'data.hex').read_text().split()][:12]
assert actual==expected,(actual,expected)
words=(work/'program.hex').read_text().split()
assert len(words)<=1024
(work/'rom.hex').write_text('\n'.join(words+['00000000']*(1024-len(words)))+'\n')
(work/'program.coe').write_text('memory_initialization_radix=16;\nmemory_initialization_vector=\n'+',\n'.join(words)+';\n')
result={'tool':'MARS 4.5','delayed_branching':True,'max_steps':500,
        'source':'software/fibonacci_mars.S','instructions':len(words),
        'result':actual,'expected':expected,'passed':True,
        'program_sha256':hashlib.sha256((work/'program.hex').read_bytes()).hexdigest()}
(work/'result.json').write_text(json.dumps(result,indent=2))
print('PASS MARS Fibonacci:',actual)
