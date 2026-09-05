from pathlib import Path
import subprocess,sys,json,shutil,os
root=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'scripts/build_board_program.py')],check=True)
work=root/'build/soc';work.mkdir(parents=True,exist_ok=True)
shutil.copyfile(root/'build/board/board_rom.hex',work/'board_rom.hex')
bin=Path(os.environ.get('VIVADO_BIN','E:/Xilinx/Vivado/2019.2/bin'))
sources=['rtl/core/single_cycle_cpu.v',*[str(p.relative_to(root)) for p in (root/'rtl/peripherals').glob('*.v')],'rtl/soc/lab_soc.v','tests/tb_soc.sv']
steps=[('xvlog',['--sv',*[str(root/p) for p in sources]]),('xelab',['tb_soc','-s','soc_test']),('xsim',['soc_test','-runall'])]
results=[]
for tool,args in steps:
 p=subprocess.run([str(bin/(tool+'.bat')),*args],cwd=work,capture_output=True,timeout=180)
 text=(p.stdout+p.stderr).decode(errors='replace');(work/(tool+'.txt')).write_text(text)
 print(tool,p.returncode,flush=True)
 if p.returncode or 'FAIL ' in text or 'Fatal:' in text:print(text[-4000:]);sys.exit(1)
 results.append({'tool':tool,'returncode':p.returncode})
 if tool=='xsim':
  lines=[l for l in text.splitlines() if l.startswith('PASS SOC ')]
  if len(lines)!=1:raise RuntimeError('Missing PASS SOC')
  print(lines[0]);results[-1]['result']=lines[0]
(work/'result.json').write_text(json.dumps(results,indent=2))
