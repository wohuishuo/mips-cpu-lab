"""Launch and record the real UART dashboard in one timed process sequence."""
from pathlib import Path
import argparse,subprocess,sys,time,json
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port',required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];work=root/'build/hardware';work.mkdir(parents=True,exist_ok=True)
(work/'recording_result.json').unlink(missing_ok=True)
(work/'live_session.jsonl').unlink(missing_ok=True)
video=work/'fpga_live_recording.mp4'
with (work/'dashboard-error.log').open('w') as errors:
 app=subprocess.Popen([str(Path(sys.executable).with_name('pythonw.exe')),str(root/'scripts/live_dashboard.py'),'--port',args.port,'--auto','--seconds','36'],cwd=root,stderr=errors,creationflags=subprocess.CREATE_NO_WINDOW)
 time.sleep(1)
 command=['ffmpeg','-hide_banner','-loglevel','warning','-f','gdigrab','-framerate','30','-draw_mouse','0','-i','title=MIPS CPU Lab - Live FPGA','-t','32','-vf','scale=1920:1080','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-y',str(video)]
 result=subprocess.run(command,cwd=root,capture_output=True,timeout=50)
 (work/'recording.log').write_bytes(result.stdout+result.stderr)
 app.wait(timeout=15)
 if result.returncode:raise RuntimeError((result.stdout+result.stderr).decode(errors='replace'))
 if app.returncode:raise RuntimeError(f'Dashboard exited with {app.returncode}; see dashboard-error.log')
duration=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(video)]))
assert 31.9<=duration<=32.1,duration
records=[json.loads(line) for line in (work/'live_session.jsonl').read_text(encoding='utf-8').splitlines()]
commands=[r['command'] for r in records if 'command' in r]
packets=[r['packet'] for r in records if 'packet' in r]
assert commands==['a','0','1','a','b','r','a'],commands
assert len(packets)>100 and all(p['status']==1 and p['errors']==0 and p['fibonacci']==89 for p in packets)
assert {p['gpio']&255 for p in packets}>={0,255},'Missing actual LED changes'
restart=next(i for i,r in enumerate(records) if r.get('command')=='r')
restart_packet=next(r for r in records[restart+1:] if 'packet' in r)
max_restart_cycles=int((restart_packet['t']-records[restart]['t']+.1)*10_000_000)
assert restart_packet['packet']['cycles']<=max_restart_cycles,'CPU did not restart after r command'
(work/'recording_result.json').write_text(json.dumps({'pass':True,'duration_seconds':duration,'packets':len(packets),'commands':commands,'source':'actual window capture of physical FPGA UART telemetry','audio':'none; beep command only, no microphone audio proof'},indent=2))
print(f'PASS LIVE_RECORDING seconds={duration} packets={len(packets)} commands={commands}')
