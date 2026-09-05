"""Native teaching window backed exclusively by current physical UART packets."""
import argparse,json,struct,time,ctypes
from pathlib import Path
import tkinter as tk
import serial

p=argparse.ArgumentParser();p.add_argument('--port',default='COM6');p.add_argument('--auto',action='store_true');p.add_argument('--seconds',type=float,default=0);args=p.parse_args()
root=Path(__file__).resolve().parents[1];out=root/'build/hardware';out.mkdir(parents=True,exist_ok=True)
log=(out/'live_session.jsonl').open('w',encoding='utf-8')
ctypes.windll.shcore.SetProcessDpiAwareness(1)
app=tk.Tk();app.tk.call('tk','scaling',4/3);app.title('MIPS CPU Lab - Live FPGA');app.geometry('1280x720+80+80');app.resizable(False,False)
canvas=tk.Canvas(app,width=1280,height=720,bg='#09121f',highlightthickness=0);canvas.pack()
font='Microsoft YaHei UI';mono='Consolas'
bg='#09121f';panel='#101e2f';edge='#20354b';muted='#8ba4be';white='#e9f3fd';cyan='#4de2cc';amber='#ffbf69';red='#ff6376'
names=['status','pc','fibonacci','cycles','stores','display','gpio','retired','errors']
data=None;error='连接串口…';event='等待开发板返回真实运行数据';start=time.monotonic();last_good=0;step=0;closed=False
schedule=[(2,b'a','CPU 自动控制：开关 → MIPS 程序 → LED / 数码管'),(6,b'0','UART 命令 0：全部 LED 关闭'),(10,b'1','UART 命令 1：全部 LED 点亮'),(14,b'a','UART 命令 a：恢复 CPU 程序控制'),(18,b'b','UART 命令 b：触发 0.5 秒蜂鸣器'),(23,b'r','UART 命令 r：CPU 复位并重新计算 Fibonacci'),(27,b'a','运行结果回到 89，RAM 存储次数回到 12')]
try:ser=serial.Serial(args.port,115200,timeout=.2,write_timeout=.2);ser.reset_input_buffer()
except Exception as exc:ser=None;error=str(exc)
def text(x,y,s,size=16,color=white,face=font,anchor='nw'):
 canvas.create_text(x,y,text=s,font=(face,size),fill=color,anchor=anchor)
def box(x,y,w,h):canvas.create_rectangle(x,y,x+w,y+h,fill=panel,outline=edge,width=1)
def digit(x,y,n):
 patterns=[0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f,0x77,0x7c,0x39,0x5e,0x79,0x71]
 shapes=[(9,0,43,7),(43,8,50,40),(43,49,50,81),(9,82,43,89),(1,49,8,81),(1,8,8,40),(9,41,43,48)]
 for b,(x0,y0,x1,y1) in enumerate(shapes):canvas.create_rectangle(x+x0,y+y0,x+x1,y+y1,fill=cyan if patterns[n]&(1<<b) else '#192b3b',outline='')
def draw():
 canvas.delete('all');elapsed=time.monotonic()-start
 text(42,29,'MIPS CPU LAB',26,white,mono);text(42,77,'从一条指令，到真实电路',17,muted)
 healthy=data is not None and not error and time.monotonic()-last_good<1
 canvas.create_oval(1023,38,1035,50,fill=cyan if healthy else red,outline='')
 text(1045,31,'LIVE FPGA' if healthy else 'NO LIVE DATA',15,cyan if healthy else red,mono)
 text(1004,66,f'{args.port}  ·  115200 / 8N1',12,muted,mono)
 if data:
  cards=[('FIBONACCI / 最后结果',str(data['fibonacci']),'12 个数列项写入 RAM'),('FETCH PC / 当前取指',f"{data['pc']:08X}",'MIPS32 · 单周期 CPU'),('CPU CLOCK / 实现频率','10 MHz','100 MHz → ÷10 → BUFG'),('RAM STORES / 存储次数',str(data['stores']),'由 CPU 的实际 RAM 写入计数')]
 else:cards=[('FIBONACCI','—','等待真实数据'),('FETCH PC','—','等待真实数据'),('CPU CLOCK','10 MHz','构建配置值'),('RAM STORES','—','等待真实数据')]
 for i,(label,value,note) in enumerate(cards):
  x=42+303*i;box(x,123,286,148);text(x+19,140,label,11,muted,mono);text(x+19,167,value,34,cyan if i==0 else white,mono);text(x+19,231,note,10,muted)
 box(42,295,700,221);text(62,315,'MEMORY-MAPPED DISPLAY',14,white,mono);text(62,343,'真实 GPIO 遥测示意 · 非开发板照片',11,muted)
 display=data['display'] if data else 0
 for i in range(8):digit(70+80*i,392,(display>>((7-i)*4))&15)
 box(762,295,475,221);text(784,315,'GPIO · CPU 与外界交互',14)
 gpio=data['gpio'] if data else 0
 for row,(label,value,color) in enumerate([('SWITCH',(gpio>>8)&255,muted),('LED',gpio&255,amber)]):
  y=371+67*row;text(784,y,label,11,muted,mono)
  for i in range(8):
   x=893+i*39;on=value&(1<<(7-i));canvas.create_oval(x,y,x+22,y+22,fill=color if on else '#1b3044',outline=edge);text(x+11,y+29,str(7-i),8,muted,mono,'n')
 box(42,538,1195,126);text(62,555,'正在演示',11,cyan);text(62,585,error if error else event,18,red if error else white)
 if data:text(1217,563,f"CYCLES  {data['cycles']:,}\nRETIRED {data['retired']:,}\nERRORS  {data['errors']}",11,muted,mono,'ne')
 text(42,686,'EES-338 / Artix-7    ·    MARS → Verilog → XSim → Vivado → FPGA',10,muted,mono)
 text(1237,686,f'{elapsed:05.1f} s',10,muted,mono,'ne')
def poll():
 global data,error,event,last_good,step
 if closed:return
 now=time.monotonic();elapsed=now-start
 try:
  if ser is None:raise RuntimeError(error)
  if args.auto and step<len(schedule) and elapsed>=schedule[step][0]:
   _,command,event=schedule[step];ser.write(command);log.write(json.dumps({'t':elapsed,'command':command.decode(),'event':event},ensure_ascii=False)+'\n');step+=1
  ser.write(b'?');raw=ser.read(40)
  if len(raw)!=40 or raw[:4]!=b'MCPU':ser.reset_input_buffer();raise RuntimeError(f'串口数据无效：{len(raw)} / 40 bytes')
  data=dict(zip(names,struct.unpack('<9I',raw[4:])));last_good=time.monotonic();error=''
  if event=='等待开发板返回真实运行数据':event='已连接开发板：Fibonacci / PC / GPIO 正在实时更新'
  log.write(json.dumps({'t':elapsed,'packet':data})+'\n');log.flush()
 except Exception as exc:error=str(exc)
 draw()
 if args.seconds and elapsed>=args.seconds:close()
 else:app.after(100,poll)
def close():
 global closed
 closed=True
 if ser:ser.close()
 log.close();app.destroy()
app.protocol('WM_DELETE_WINDOW',close);draw();app.after(100,poll);app.mainloop()
