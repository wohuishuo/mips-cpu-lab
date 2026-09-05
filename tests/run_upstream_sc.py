"""Replay local supplied ROM/golden trace; no unlicensed materials copied to source."""
from pathlib import Path
import os,subprocess,re,shutil,sys,json,hashlib
root=Path(__file__).resolve().parents[1]
lab=Path(os.environ.get('BITMIPS_LAB5',root.parent/'bitmips_experiments-master/bitmips_experiments-master/lab5'))
work=root/'build/upstream_sc';work.mkdir(parents=True,exist_ok=True)
coe=lab/'teach_soft/inst_ram.coe';gold=lab/'golden_trace.txt'
text=coe.read_text().split('memory_initialization_vector',1)[1].split('=',1)[1]
words=re.findall(r'\b[0-9a-fA-F]{8}\b',text)
if not 0<len(words)<=65536:raise ValueError('Invalid supplied COE')
(work/'upstream_rom.hex').write_text('\n'.join(words+['00000000']*(65536-len(words)))+'\n')
shutil.copyfile(gold,work/'golden_trace.txt')
bin=Path(os.environ.get('VIVADO_BIN','E:/Xilinx/Vivado/2019.2/bin'))
steps=[('xvlog',['--sv',str(root/'rtl/core/single_cycle_cpu.v'),str(root/'tests/tb_upstream_sc.sv')]),('xelab',['tb_upstream_sc','-s','upstream_sc']),('xsim',['upstream_sc','-runall'])]
for name,args in steps:
 p=subprocess.run([str(bin/(name+'.bat')),*args],cwd=work,capture_output=True,timeout=180)
 output=(p.stdout+p.stderr).decode(errors='replace');(work/(name+'.log')).write_text(output)
 print(name,p.returncode,flush=True)
 if p.returncode or 'FAIL ' in output or 'Fatal:' in output:print(output[-3000:]);sys.exit(1)
 if name=='xsim':
  markers=[line for line in output.splitlines() if line.startswith('PASS UPSTREAM_SC ')]
  if len(markers)!=1:raise RuntimeError('Missing completion')
  print(markers[0])
  (work/'result.json').write_text(json.dumps({'result':markers[0],'rom_sha256':hashlib.sha256(coe.read_bytes()).hexdigest(),'golden_sha256':hashlib.sha256(gold.read_bytes()).hexdigest(),'scope':'supplied ROM + golden trace, SC combinational memory; synchronous teach_soc integration remains separate'},indent=2))
