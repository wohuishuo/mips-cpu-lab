"""Test real 115200-baud telemetry and UART light commands on the connected FPGA."""
from pathlib import Path
import argparse, json, struct, time
import serial
parser=argparse.ArgumentParser()
parser.add_argument('--port',default='COM6')
parser.add_argument('--beep',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
out=root/'build/hardware';out.mkdir(parents=True,exist_ok=True)
(out/'board_test.json').unlink(missing_ok=True)
names=['status','pc','fibonacci','cycles','stores','display','gpio','retired','errors']
cpu_hz=10_000_000
history=[]
with serial.Serial(args.port,115200,timeout=2,write_timeout=2) as ser:
 time.sleep(.1);ser.reset_input_buffer()
 def query(label):
  ser.write(b'?');raw=ser.read(40)
  if len(raw)!=40 or raw[:4]!=b'MCPU':raise RuntimeError(f'Invalid telemetry ({len(raw)} bytes): {raw.hex()}')
  data=dict(zip(names,struct.unpack('<9I',raw[4:])))
  data['step']=label;history.append(data)
  print(json.dumps(data),flush=True)
  return data
 def validate(data):
  assert data['status']==1 and data['fibonacci']==89 and data['stores']==12 and data['errors']==0,data
  switches=(data['gpio']>>8)&255
  assert data['display']==(switches<<16)|89,data
 ser.write(b'a');time.sleep(.05)
 initial=query('automatic');validate(initial)
 assert initial['gpio']&255==89^((initial['gpio']>>8)&255)
 ser.write(b'0');time.sleep(.02)
 off=query('led_off');validate(off);assert off['gpio']&255==0
 ser.write(b'1');time.sleep(.02)
 on=query('led_on');validate(on);assert on['gpio']&255==255
 ser.write(b'a');time.sleep(.02)
 restored=query('automatic_restored');validate(restored)
 assert restored['gpio']&255==89^((restored['gpio']>>8)&255)
 if args.beep:ser.write(b'b');time.sleep(.05)
 restart_requested=time.monotonic()
 ser.write(b'r');ser.flush();time.sleep(.05)
 restarted=query('cpu_restarted');validate(restarted)
 restart_age_seconds=time.monotonic()-restart_requested
 max_restart_cycles=int((restart_age_seconds+.010)*cpu_hz)
 assert restarted['cycles']<=max_restart_cycles,(restarted,restart_age_seconds,max_restart_cycles)
 result={'pass':True,'transport':'physical serial 115200 8N1','records':history,'beep_command_sent':args.beep,
         'restart_check':{'host_age_seconds':restart_age_seconds,'reported_cycles':restarted['cycles'],
                          'max_post_reset_cycles':max_restart_cycles},
         'limits':'GPIO telemetry proves driven signals; physical LED/display appearance and sound need separate capture.'}
 (out/'board_test.json').write_text(json.dumps(result,indent=2)+'\n')
 print('PASS PHYSICAL_BOARD fibonacci=89 stores=12 uart_lights=off,on,auto cpu_restart=pass')
