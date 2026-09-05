"""Deterministic pipeline regression. XSim fatal text is authoritative."""
from pathlib import Path
import os, re, subprocess, sys
from pipeline_reference import generate
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/pipeline'
def main():
    BUILD.mkdir(parents=True,exist_ok=True)
    generate(BUILD, mutate='--mutate' in sys.argv)
    vivado=Path(os.environ.get('VIVADO_BIN','E:/Xilinx/Vivado/2019.2/bin'))
    transcript=[]
    for tool,args in [('xvlog',['--sv','--work','xil_defaultlib',str(ROOT/'rtl/core/cp0.v'),str(ROOT/'rtl/core/pipeline_cpu.v'),str(ROOT/'tests/tb_pipeline.sv')]),('xelab',['xil_defaultlib.tb_pipeline','-s','pipeline_test']),('xsim',['pipeline_test','-runall'])]:
        p=subprocess.run([str(vivado/(tool+'.bat')),*args],cwd=BUILD,capture_output=True,text=True,errors='replace',timeout=180)
        out=p.stdout+p.stderr;transcript.append(out);print(out,end='')
        (BUILD/('mutation.log' if '--mutate' in sys.argv else 'regression.log')).write_text('\n'.join(transcript),encoding='utf-8')
        if p.returncode or re.search(r'(?im)\b(FAIL|FATAL|ERROR)\b',out):return 1
    return 0 if out.count('PASS pipeline')==1 else 1
if __name__=='__main__':sys.exit(main())
