"""Original engineering figures; pipeline figure is drawn from actual XSim CSV."""
from pathlib import Path
import csv,re
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[1];out=root/'media';out.mkdir(exist_ok=True)
BG='#09121f';PANEL='#102236';EDGE='#28445d';TEXT='#edf6ff';MUTED='#97b1c9';CYAN='#4de2cc';AMBER='#ffbf69'
fonts={}
def font(size,mono=False):
 key=(size,mono)
 if key not in fonts:fonts[key]=ImageFont.truetype('C:/Windows/Fonts/consola.ttf' if mono else 'C:/Windows/Fonts/msyh.ttc',size)
 return fonts[key]
def base(title,subtitle):
 im=Image.new('RGB',(1920,1080),BG);d=ImageDraw.Draw(im)
 d.text((70,45),'MIPS CPU LAB',font=font(28,True),fill=CYAN)
 d.text((70,105),title,font=font(52),fill=TEXT)
 d.text((70,185),subtitle,font=font(24),fill=MUTED)
 return im,d
def rect(d,box,title,note,color=CYAN):
 d.rounded_rectangle(box,radius=18,fill=PANEL,outline=EDGE,width=2)
 x,y,xx,yy=box;d.rectangle((x+20,y+25,x+26,yy-25),fill=color)
 d.text((x+45,y+27),title,font=font(29),fill=TEXT)
 for i,line in enumerate(note.split('\n')):d.text((x+45,y+77+i*34),line,font=font(21,not any(ord(c)>127 for c in line)),fill=MUTED)
def arrow(d,points,color=CYAN):
 d.line(points,fill=color,width=5,joint='curve');x,y=points[-1];px,py=points[-2]
 if x>px:d.polygon([(x,y),(x-13,y-8),(x-13,y+8)],fill=color)
 elif x<px:d.polygon([(x,y),(x+13,y-8),(x+13,y+8)],fill=color)
 elif y>py:d.polygon([(x,y),(x-8,y-13),(x+8,y-13)],fill=color)
 else:d.polygon([(x,y),(x-8,y+13),(x+8,y+13)],fill=color)
im,d=base('程序怎样流过五级流水线','原创结构示意 · 信号名对应 pipeline_cpu / cached_cpu · 非物理布局图')
stages=[('IF / 取指','if_pc\nimem_rdata'),('ID / 译码','id_valid\nid_pc / id_instr'),('EX / 执行','a / b / write_data\nforward / branch'),('MEM / 访存','dmem_valid / ready\naddr / wstrb'),('WB / 提交','trace_valid\ntrace_pc / wdata')]
for i,(title,note) in enumerate(stages):
 x=70+360*i;rect(d,(x,300,x+310,500),title,note)
 if i<4:arrow(d,[(x+310,400),(x+353,400)])
arrow(d,[(1625,500),(1625,560),(965,560),(965,500)],AMBER)
d.text((675,913),'MEM / WB → EX：前推最新结果',font=font(23),fill=AMBER)
rect(d,(70,680,590,890),'CP0 / 精确异常','Status · Cause · EPC · BadVAddr\nCount / Compare · ERET',AMBER)
rect(d,(675,680,1195,890),'2-WAY DATA CACHE','Tag / Valid / Dirty / LRU\nWrite back · Write allocate')
rect(d,(1280,680,1850,890),'MMIO / 外设旁路','UART · LED · Display · Buzzer\n每次外设写入只生效一次',AMBER)
arrow(d,[(1305,500),(1305,630),(935,630),(935,680)])
arrow(d,[(1305,630),(1565,630),(1565,680)],AMBER)
arrow(d,[(1210,500),(1210,540),(965,540),(965,500)],AMBER)
d.text((82,620),'WB 异常提交 · EPC 返回 IF',font=font(23),fill=AMBER)
d.text((70,967),'观察方法：PC 标识指令，valid 标识气泡，握手标识访存完成，trace 标识退休。',font=font(27),fill=TEXT)
d.text((70,1024),'课程对应：10MIPS流水线CPU设计 / 11MIPS中断与异常 / 12MIPS存储系统',font=font(21),fill=MUTED)
im.save(out/'datapath.png')

rows=list(csv.DictReader((root/'build/pipeline/pipeline_stages.csv').open()))
rows=[r for r in rows if r['mode']=='1'][:13]
if not rows:raise RuntimeError('No actual mode1 pipeline trace')
im,d=base('把真实流水线轨迹展开成一张图','读取 XSim 的 pipeline_stages.csv · 每个格子标出该拍、该级的 PC')
left,top,cw,rh=260,292,303,49
stages=['if','id','ex','mem','wb']
for i,stage in enumerate(stages):d.text((left+i*cw+95,top-43),stage.upper(),font=font(25,True),fill=CYAN)
for n,row in enumerate(rows):
 y=top+n*rh;d.text((75,y+10),f"CYCLE {row['cycle']:>3}",font=font(23,True),fill=MUTED)
 waiting=row['dmem_valid']=='1' and row['dmem_ready']=='0'
 for i,stage in enumerate(stages):
  x=left+i*cw;valid=row[stage+'_valid']=='1';color=PANEL if valid else '#0c1826'
  d.rounded_rectangle((x,y,x+cw-12,y+rh-6),radius=6,fill=color,outline=AMBER if waiting and i<4 else EDGE)
  value=row[stage+'_pc'].upper() if valid else '— bubble —'
  d.text((x+57,y+8),value,font=font(23,True),fill=TEXT if valid else '#526b83')
d.text((70,978),'琥珀边框：MEM 等待期间，年轻阶段保持；WB 只排空一次。',font=font(27),fill=AMBER)
d.text((70,1024),'数据来源：三种真实 memory-ready 模式中的 mode 1；原始 CSV 可复查每个格子。',font=font(21),fill=MUTED)
im.save(out/'pipeline-trace.png')
im,d=base('等待改变性能，不应改变程序结果','CPU + Cache 联合回归 · 2 种几何配置 × 3 种存储就绪模式 · 实际 XSim 结果')
log=(root/'build/cpu-cache/regression.log').read_text()
stats=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',line)) for line in log.splitlines() if line.startswith('JOINT ')]
assert len(stats)==6
for i,row in enumerate(stats):
 y=280+i*94;label=['连续就绪','随机等待','每 13 拍就绪'][row['mode']]
 d.text((70,y+14),f"{row['sets']} sets × {row['words']} words",font=font(23,True),fill=TEXT)
 d.text((380,y+14),label,font=font(23),fill=MUTED)
 width=round(row['cycles']/5000*820)
 d.rounded_rectangle((630,y,630+width,y+55),radius=8,fill=CYAN if row['sets']==16 else '#729bd3')
 d.text((660+width,y+13),f"{row['cycles']:,} cycles  /  CPI {row['cycles']/row['retirements']:.2f}",font=font(23,True),fill=TEXT)
d.text((70,905),'每次均匹配 391 次退休、198 次数据事务、38 次 MMIO 存储和全部 8192 个 RAM 字。',font=font(26),fill=TEXT)
d.text((70,970),'这是等待模式对照，不是“开 / 关 Cache”的加速比实验。',font=font(26),fill=AMBER)
d.text((70,1024),'数据来源：build/cpu-cache/regression.log；CPI = 从复位释放到程序结束的周期数 / 391。',font=font(21),fill=MUTED)
im.save(out/'cache-performance.png')
im,d=base('从指令到电路','MIPS CPU Lab · 课程实现 / 自动验证 / 真实 FPGA 演示')
d.text((70,310),'89',font=font(210,True),fill=CYAN)
d.text((410,350),'Fibonacci',font=font(55,True),fill=TEXT)
d.text((414,428),'同一份 MARS 机器码，在 RTL 与真实开发板运行',font=font(28),fill=MUTED)
rect(d,(70,640,620,860),'单周期 / 44 条普通指令','MARS → RTL → FPGA\n程序、地址与字节写使能一起验证')
rect(d,(680,640,1230,860),'流水线 / 精确异常','28,970 golden trace writes\n19 个已启用课程功能点')
rect(d,(1290,640,1840,860),'Cache / 两路写回','6 joint regression cases\n等待、替换与外设旁路')
d.text((70,975),'画面类型将分别注明：真实串口录屏 / 基于真实轨迹的教学图。',font=font(27),fill=TEXT)
im.save(out/'cover.png')
print('PASS FIGURES four original engineering figures 1920x1080')
