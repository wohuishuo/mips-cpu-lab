import {DisplayLab,CacheLab} from './exhibit-models.js';
const $=id=>document.getElementById(id);
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const hex=(n,d=8)=>n===null?'—':(Number(n)>>>0).toString(16).toUpperCase().padStart(d,'0');
const github=path=>'https://github.com/wohuishuo/mips-cpu-lab/blob/main/'+path;
const names='zero at v0 v1 a0 a1 a2 a3 t0 t1 t2 t3 t4 t5 t6 t7 s0 s1 s2 s3 s4 s5 s6 s7 t8 t9 k0 k1 gp sp fp ra'.split(' ');
let project,boardTrace,chapter,cursor=0,timer=null,sourcePath='',sourceStart=1,sourceEnd=1;
let boardMode='rtl',pipeMode=0,displayLab=new DisplayLab(),switchValue=0x81,phase=0,lab3Mode='fib',lab3A=255,lab3B=255,fibCount=0,injectFault=false,delaySlot=false,cache=new CacheLab(),cacheResult=null,cacheAddress=0,cacheValue=99;
const shortTitles={board:'板子上的 CPU',lab1:'开关与数码管',lab3:'单周期与程序',pipeline:'五级流水线',lab5:'指令对照验证',exceptions:'异常与返回',lab7:'两路 Cache',uart:'实板串口记录'};
const navIds={board:'起点',lab1:'lab1',lab3:'lab3',pipeline:'进阶',lab5:'lab5',exceptions:'进阶',lab7:'lab7',uart:'实板'};
const kinds={'physical-board':'实板串口记录','rtl-simulation':'RTL 仿真记录','principle-demo':'可交互原理演示','documentation':'项目文档'};
// Course lab3 starts at 2,3 (tests/tb_lab3.sv); the board demo starts at 0,1.
const fib=Array(20).fill(0);fib[0]=2;fib[1]=3;for(let i=2;i<20;i++)fib[i]=fib[i-1]+fib[i-2];

function stop(){if(timer!==null){clearInterval(timer);timer=null;}const button=$('demo').querySelector('[data-action="play"]');if(button)button.textContent='播放';}
function source(path,start=1,end=start,note='这段代码来自仓库原文件，行号可以直接对照。'){
  const file=project.sources[path];if(!file)return;
  sourcePath=path;sourceStart=start;sourceEnd=end;$('source-file').value=path;
  $('source-lines').textContent=`L${start}–${end} · ${file.text.split('\n').length} 行`;
  $('source-link').href=github(path)+`#L${start}-L${end}`;$('source-note').textContent=note;
  $('code').innerHTML=file.text.split('\n').map((line,i)=>`<div class="code-line ${i+1>=start&&i+1<=end?'highlight':''}" data-line="${i+1}"><span>${i+1}</span><code>${esc(line)}</code></div>`).join('');
  const first=$('code').querySelector('.highlight');if(first)$('code').scrollTop=Math.max(0,first.offsetTop-$('code').firstElementChild.offsetTop-75);
}
function followStep(index){if(!$('follow-source').checked)return;const step=chapter.steps[Math.min(index,chapter.steps.length-1)];if(step)source(step.path,step.start,step.end,step.body);}
function chooseChapter(id){
  stop();chapter=project.chapters.find(c=>c.id===id)||project.chapters[0];cursor=0;boardMode='rtl';
  $('chapter-title').textContent=chapter.id==='board'?'这块板子，怎样算出 89？':chapter.title;
  $('chapter-kicker').textContent=chapter.kicker;$('chapter-intro').textContent=chapter.intro;$('chapter-question').textContent=chapter.question;
  const index=project.chapters.indexOf(chapter);$('page-number').textContent=`${String(index+1).padStart(2,'0')} / 08`;
  $('chapters').innerHTML=project.chapters.map(c=>`<a href="#${c.id}" class="${c.id===chapter.id?'active':''}" ${c.id===chapter.id?'aria-current="page"':''}><span>${navIds[c.id]}</span>${shortTitles[c.id]}</a>`).join('');
  const files=[...new Set([...chapter.steps.map(s=>s.path),...(chapter.id==='board'?['rtl/core/single_cycle_cpu.v','rtl/soc/lab_soc.v']:[])])];
  $('source-file').innerHTML=files.map(path=>`<option value="${esc(path)}">${esc(path)}</option>`).join('');$('follow-source').checked=true;
  $('lesson-steps').innerHTML=chapter.steps.map((step,i)=>`<button class="lesson-step" data-lesson="${i}"><small>${String(i+1).padStart(2,'0')}</small><h3>${esc(step.title)}</h3><p>${esc(step.body)}</p></button>`).join('');
  $('evidence').innerHTML=chapter.evidence.map(e=>`<div><span>${esc(e.label)}<br><small>${esc(kinds[e.kind]||e.kind)}</small></span><span class="evidence-value">${esc(e.value)}</span><a href="${github(e.path)}" target="_blank" rel="noopener">原始记录 ↗</a></div>`).join('');
  $('scope-note').textContent=Array.isArray(chapter.limits)?chapter.limits.join(' '):chapter.limits;
  followStep(0);renderDemo();
}
function setDemo(title,kind,html,explanation){$('demo-title').textContent=title;$('demo-kind').textContent=kind;$('demo').innerHTML=html;$('explanation').innerHTML=explanation;}
function controls(length,{end=true,extra=''}={}){return `<div class="demo-controls"><button class="play" data-action="play">${timer===null?'播放':'暂停'}</button><button data-action="prev" ${cursor===0?'disabled':''}>←</button><button data-action="next" ${cursor>=length-1?'disabled':''}>单步 →</button>${end?'<button data-action="end">看结果</button>':''}${extra}<output>${cursor+1} / ${length}</output><input aria-label="演示进度" data-control="cursor" type="range" min="0" max="${length-1}" value="${cursor}"></div>`;}
function facts(items){return `<div class="cpu-facts">${items.map(([label,value])=>`<div><small>${label}</small><strong>${esc(value)}</strong></div>`).join('')}</div>`;}
function memory(values,base=0x10010000,changed=-1,extra=''){return `<div class="memory-title"><span>RAM · ${values.length} 个 32 位字</span><span>地址 → 内容</span></div><div class="memory-grid ${extra}">${values.map((value,i)=>`<div class="memory-cell ${i===changed?'changed':''}" data-ram="${i}"><small>${hex(base+i*4)}</small><b>${value===null?'—':value}</b></div>`).join('')}</div>`;}
function chip(x,y,w,label,sub,value,active=false){return `<rect class="chip ${active?'lit':''}" x="${x}" y="${y}" width="${w}" height="66" rx="2"/><text class="chip-label" x="${x+12}" y="${y+22}">${esc(label)}</text><text class="chip-sub" x="${x+12}" y="${y+41}">${esc(sub)}</text><text class="chip-value" x="${x+12}" y="${y+56}">${esc(value)}</text>`;}
function cpuDiagram(row){
  const load=(row.instr>>>26)===35,store=row.memWrite;
  return `<div class="board-label">EES-338 / XC7A35T · 自研单周期 CPU · 10 MHz</div><div class="schematic"><svg viewBox="0 0 760 265" role="img" aria-label="单周期 CPU 数据通路示意"><defs><marker id="arrow" markerWidth="7" markerHeight="7" refX="6" refY="3" orient="auto"><path d="M0 0L6 3L0 6" fill="#a34431"/></marker></defs><text class="wire-label" x="25" y="28">一条指令在一个时钟内完成这条通路；这些不是五个流水级。</text><path class="connection lit" d="M100 95H137 M265 95H306 M434 95H475 M596 95H632" marker-end="url(#arrow)"/>${chip(24,61,76,'PC','指令地址',hex(row.pc),true)}${chip(137,61,128,'指令 ROM','取出 32 位指令',hex(row.instr),true)}${chip(306,61,128,'译码 / 寄存器','读源寄存器','rs / rt',true)}${chip(475,61,121,'ALU','运算或算地址',store||load?hex(row.address):hex(row.value),true)}${chip(632,61,104,'RAM / I/O',load?'读取数据':store?'写入数据':'本条不访存',store?hex(row.storeValue):load?hex(row.readValue):'—',store||load)}<path class="connection ${row.regWrite?'lit':''}" d="M684 127V190H368V127" marker-end="url(#arrow)"/><text class="chip-sub" x="465" y="182">${row.regWrite?`写回 $${names[row.rd]} = ${hex(row.value)}`:'结果通路 · 本条不写寄存器'}</text><path class="connection" d="M368 61V41H62V61"/><text class="wire-label" x="24" y="233">CLK ↑ 每一个边沿锁存结果</text><text class="wire-label" x="735" y="233" text-anchor="end">连接示意，非板卡照片</text></svg></div>`;
}
const segments=['9,3 31,3 35,7 30,11 10,11 5,7','33,10 37,7 37,28 33,32 29,28 31,13','33,35 37,32 37,53 33,58 29,53 31,38','10,55 30,55 34,59 30,63 9,63 5,59','3,33 7,37 9,52 5,57 1,53 1,35','3,8 7,12 9,27 5,32 1,28 1,11','10,29 29,29 33,33 29,37 9,37 5,33'];
const codes=[126,48,109,121,51,91,95,112,127,123,119,31,78,61,79,71];
function digits(value,enabled=255){return `<div class="display-row" aria-label="显示寄存器 ${hex(value)}">${hex(value).split('').map((c,i)=>`<svg class="digit" viewBox="0 0 40 68" aria-hidden="true">${segments.map((p,s)=>`<polygon points="${p}" class="${enabled&(1<<(7-i))&&codes[parseInt(c,16)]&(1<<(6-s))?'on':''}"/>`).join('')}</svg>`).join('')}</div>`;}
function leds(value){return `<div class="led-strip" aria-label="LED 驱动值 ${hex(value,2)}">${Array.from({length:8},(_,i)=>`<span class="led-dot ${value&(1<<(7-i))?'on':''}" title="bit ${7-i}"></span>`).join('')}</div>`;}
function renderBoard(){
  if(boardMode==='telemetry'){renderTelemetry(false);return;}
  const row=boardTrace.rows[cursor],changed=row.memWrite&&row.address>=0x10010000&&row.address<0x10010030?(row.address-0x10010000)/4:-1;
  const asm=project.sources['software/board_demo.S'].text.split('\n'),lines=asm.map((line,i)=>({line,i:i+1})).filter(x=>/^\s+[a-z]/i.test(x.line)&&!/^\s*[.#]/.test(x.line));
  const instruction=lines[(row.pc-0x00400000)/4];
  if($('follow-source').checked&&instruction)source('software/board_demo.S',instruction.i,instruction.i,'高亮的是这一拍真正执行的汇编；数值取自相同 SoC 的 XSim 记录。');
  const words=row.ram.filter(v=>v!==null).length;
  const explanation=changed>=0?`<strong>第 ${row.cycle} 拍：把 ${row.storeValue} 存进内存。</strong> 地址 0x${hex(row.address)} 对应第 ${changed+1} 项。寄存器保存的前两项相加，下一圈继续写入。`:row.done?`<strong>12 项已经算完，最后一项是 89。</strong> CPU 随后循环读开关 0x81，写显示值 0x${hex(row.display)}，并用 0x81 XOR 0x59 驱动 LED。`:row.regWrite?`<strong>${esc(instruction?.line.trim()||'当前指令')}</strong> → 把 ${row.value}（0x${hex(row.value)}）写入 $${names[row.rd]}。右侧高亮同一条汇编，下方保留已经写入的内存。`:`<strong>${esc(instruction?.line.trim()||'当前指令')}</strong>。这一拍不写寄存器；分支、存储也有自己的工作。`;
  setDemo('跟着板上程序走一遍','相同 SoC 的 RTL 仿真回放',`<div class="mode-tabs"><button data-boardmode="rtl" class="selected">逐指令过程</button><button data-boardmode="telemetry">查看真实串口记录</button></div>${controls(boardTrace.rows.length)}${cpuDiagram(row)}${facts([['已写入 RAM',`${words} / 12`],['当前显示寄存器',hex(row.display)],['LED 驱动',hex(row.led,2)]])}${memory(row.ram,0x10010000,changed)}<div class="register-peek">${[8,9,11,16,18].map(i=>`<span class="${row.regWrite&&row.rd===i?'changed':''}">$${names[i]} = ${row.registers[i]}</span>`).join('')}</div><p class="record-note">逐指令值来自新导出的 XSim 轨迹；实板串口独立验证 89 / 12 次存储。未写 RAM 显示“—”，不假设硬件已清零。</p>`,explanation);
}
function renderTelemetry(uart){
  const records=uart?project.board.records:project.telemetry;
  cursor=Math.min(cursor,records.length-1);const record=records[cursor],packet=uart?record:record.packet;
  const steps={automatic:'CPU 自动控灯',led_off:'串口发送 0：关灯',led_on:'串口发送 1：开灯',automatic_restored:'串口发送 a：恢复 CPU 控灯',cpu_restarted:'串口发送 r：重新执行'};
  const html=`${uart?'':`<div class="mode-tabs"><button data-boardmode="rtl">逐指令过程</button><button data-boardmode="telemetry" class="selected">查看真实串口记录</button></div>`}${controls(records.length)}<div class="board-label">${uart?steps[record.step]:`记录时间 ${Number(record.t).toFixed(3)} s`} · physical serial 115200 8N1</div><div class="display-board">${digits(packet.display)}<div class="display-caption">显示寄存器的逻辑图形 · 非实物拍摄</div>${leds(packet.gpio&255)}</div>${facts([['Fibonacci',packet.fibonacci],['RAM 写入次数',packet.stores],['错误计数',packet.errors]])}<table class="sample-table"><tr><th>字段</th><th>记录值</th><th>意味着什么</th></tr><tr><td>PC</td><td>0x${hex(packet.pc)}</td><td>采样时正在执行的位置</td></tr><tr><td>switches</td><td>0x${hex((packet.gpio>>>8)&255,2)}</td><td>同步后的开关输入</td></tr><tr><td>LED</td><td>0x${hex(packet.gpio&255,2)}</td><td>实际驱动值</td></tr><tr><td>cycles</td><td>${packet.cycles}</td><td>复位后周期计数，32 位回绕</td></tr></table>${uart?`<div class="decode-box"><div><small>包头 · 4 字节</small><b>MCPU</b></div><div><small>负载 · 9 × 32 位</small><b>36 bytes</b></div><div><small>总长度 / 小端</small><b>40 bytes</b></div></div>`:''}`;
  setDemo(uart?'选择一次实际发生过的板卡操作':'回放这块板子发出的数据','实板串口记录 · 不是实时连接',html,`<strong>${uart?esc(steps[record.step]):'这是从真实 FPGA 串口读到的一条记录。'}</strong> ${uart?'这里的按钮只选择历史记录，不向板卡发送命令。':'播放会沿着原采样时间顺序读记录，不会把软件运算伪装成板卡数据。'} 数码管与灯是驱动信号的图解，物理外观和声音仍需现场观察。`);
  if(uart)followStep(cursor===4?3:cursor===0?0:2);
}
function renderLab1(){
  const scan=displayLab.scan(phase);
  const switches=Array.from({length:8},(_,i)=>7-i).map(bit=>`<button data-switch="${bit}" class="${switchValue&(1<<bit)?'on':''}" aria-label="开关 ${bit}" aria-pressed="${!!(switchValue&(1<<bit))}">${switchValue&(1<<bit)?1:0}<small>${bit}</small></button>`).join('');
  setDemo('拨一个数，按一次，写入一个字节','按自写 lab1 RTL 放慢演示',`<div class="board-label">SW[7:0] → 同步 / 消抖 → 32 位显示值 → 扫描</div><div class="switches">${switches}</div><div class="demo-controls"><button class="play" data-action="capture">模拟稳定按下一次</button><button data-action="display-reset">从头演示</button><output>下次写 byte ${displayLab.byte}</output></div><div class="display-board">${digits(displayLab.value,scan.digits)}<div class="display-caption">一次只点亮每组中的一位；四相位快速循环，人眼看到八位。</div></div><div class="scan-phases">${[0,1,2,3].map(i=>`<button data-phase="${i}" class="${phase===i?'selected':''}">相位 ${i}</button>`).join('')}</div>${facts([['完整显示值',hex(displayLab.value)],['位选 digital_cs',hex(scan.digits,2)],['段码组 0',scan.segments0.toString(2).padStart(7,'0')]])}<p class="record-note">按键代表已经同步、消抖的一次上升沿。这里没有模拟真实按键抖动时间；对应 RTL 的 672 次输出检查独立记录。</p>`,`<strong>开关给出 0x${hex(switchValue,2)}，CPU 还没登场。</strong> lab1 先教会 FPGA 怎样保存输入、轮流选通显示位。相位 ${phase} 取出低组的 ${scan.low.toString(16).toUpperCase()} 和高组的 ${scan.high.toString(16).toUpperCase()}，再查表变成七根段线。`);
}
function renderLab3(){
  const isFib=lab3Mode==='fib';
  setDemo(isFib?'同一套接口，运行 Fibonacci':'两个输入，由程序完成加法','课程算法的交互讲解 · 非原波形',`<div class="mode-tabs"><button data-lab3="fib" class="${isFib?'selected':''}">Fibonacci · 20 项</button><button data-lab3="add" class="${!isFib?'selected':''}">8 位输入加法</button></div>${isFib?`<div class="demo-controls"><button class="play" data-action="fib-next" ${fibCount>=20?'disabled':''}>计算下一项</button><button data-action="fib-all">算完 20 项</button><button data-action="fib-reset">重新开始</button><output>${fibCount} / 20</output></div><div class="math-line">${fibCount<2?'2，3':`${fib[fibCount-2]} + ${fib[fibCount-1]}`} ${fibCount>=2&&fibCount<20?`→ <span class="result">${fib[fibCount]}</span>`:''}</div>${memory(fib.map((n,i)=>i<fibCount?n:null),0,fibCount-1,'lab3-memory')}`:`<div class="input-row"><label>输入 A · 0–255<input id="lab3-a" type="number" min="0" max="255" value="${lab3A}"></label><label>输入 B · 0–255<input id="lab3-b" type="number" min="0" max="255" value="${lab3B}"></label><button data-action="lab3-add">执行加法</button></div><div class="math-line">${lab3A} + ${lab3B} = <span class="result" id="lab3-sum">${lab3A+lab3B}</span></div><div class="display-board">${digits(lab3A+lab3B)}</div>${facts([['十六进制',hex(lab3A+lab3B,4)],['LED 低 8 位',(lab3A+lab3B)&255],['实际边界用例','36 组']])}`}<p class="record-note">表内地址为第几个字的相对偏移，帮助观察算法。原课程实验的 ROM、RAM、confreg 接口由右侧适配器保留，真实结果见下方记录。</p>`,isFib?`<strong>每次把前两项相加，再写入下一格。</strong> 课程 lab3 从 2、3 开始，算 20 项，最后是 17711；板上程序从 0、1 开始，算 12 项，最后是 89。两者不要混在一起。`:`<strong>和可能超过一个字节。</strong> 255 + 255 = 510，完整结果是 0x01FE；LED 只取低 8 位，因此显示的驱动数值是 254。`);
}
function pipeRows(){return project.pipeline.filter(row=>Number(row.mode)===pipeMode);}
function renderPipeline(){
  const rows=pipeRows();cursor=Math.min(cursor,rows.length-1);const row=rows[cursor],last=rows[cursor-1];
  const held=last&&['if','id','ex','mem'].some(s=>row[s+'_valid']&&row[s+'_pc']===last[s+'_pc']);
  const stages=['if','id','ex','mem','wb'];
  setDemo('同一个时钟，不同指令各做一段工作','真实 RTL 阶段 CSV 回放',controls(rows.length,{extra:`<label>等待模式<select data-control="pipe-mode"><option value="0" ${pipeMode===0?'selected':''}>0</option><option value="1" ${pipeMode===1?'selected':''}>1</option><option value="2" ${pipeMode===2?'selected':''}>2</option></select></label>`})+`<div class="pipeline-grid">${stages.map(s=>`<div class="pipeline-stage ${row[s+'_valid']?'valid':''}"><b>${s.toUpperCase()}</b><small>${{if:'取指',id:'译码',ex:'执行',mem:'访存',wb:'写回'}[s]}</small><small>PC ${row[s+'_valid']?row[s+'_pc']:'—'}</small><em>${row[s+'_valid']?row[s+'_instr']:'空泡'}</em></div>`).join('')}</div>${facts([['RTL 周期',row.cycle],['dmem_valid',row.dmem_valid],['dmem_ready',row.dmem_ready]])}<div class="trace-scroll"><table class="sample-table"><tr><th>cycle</th><th>IF / PC</th><th>EX / PC</th><th>WB / PC</th></tr>${rows.slice(Math.max(0,cursor-5),cursor+1).map(r=>`<tr class="${r===row?'active':''}"><td>${r.cycle}</td><td>${r.if_valid?r.if_pc:'—'}</td><td>${r.ex_valid?r.ex_pc:'—'}</td><td>${r.wb_valid?r.wb_pc:'—'}</td></tr>`).join('')}</table></div>`,`<strong>${row.dmem_valid&&!row.dmem_ready?'存储器还没准备好，请求必须保持。':held?'有阶段保留同一个 PC，观察它是在等待还是循环。':'有效位为 1 的阶段里，保存着一条真实指令。'}</strong> 这份 CSV 来自项目流水线的 XSim 回归。它是另一个已经通过仿真的核，当前 FPGA 镜像仍是单周期版本。`);
  followStep(row.dmem_valid&&!row.dmem_ready?2:held?1:0);
}
function renderLab5(){
  const sample=[{pc:0xbfc00000,rd:1,value:7},{pc:0xbfc00004,rd:2,value:4},{pc:0xbfc00008,rd:3,value:8}];
  setDemo('每完成一条指令，就对一次答案','对照机制演示 + 原回归结果',`<div class="demo-controls"><button data-action="inject" class="${injectFault?'play':''}">${injectFault?'恢复正确结果':'故意改错一次写回'}</button><output>机制示例 · 3 条记录</output></div><div class="status-stamp ${injectFault?'fail':''}">${injectFault?'发现第一处差异：第 2 条':'三条示例记录一致'}</div><table class="sample-table"><tr><th>提交 PC</th><th>目的寄存器</th><th>参考值</th><th>CPU 值</th></tr>${sample.map((r,i)=>`<tr class="${injectFault&&i===1?'active':''}"><td>${hex(r.pc)}</td><td>$${names[r.rd]}</td><td>${r.value}</td><td>${injectFault&&i===1?5:r.value} ${injectFault&&i===1?'≠':'='}</td></tr>`).join('')}</table>${facts([['原回归对照行数','28,970'],['实际启用功能点','19'],['实际存储次数','420']])}<p class="record-note">上面三行专门用于解释对照方法，不能当作原始 golden trace。下方项目验证记录才是实际运行结果。</p>`,`<strong>${injectFault?'第一处差异比最后一个错误结果更有用。':'CPU 算出答案，还要证明每一步都对。'}</strong> 对照器检查提交 PC、寄存器编号和写回值。资料提到 89 个功能点，本地配置实际启用了 19 个；当前验证结果严格对应这 19 个。`);
  followStep(injectFault?2:1);
}
function renderExceptions(){
  const pc=0xbfc00020,epc=delaySlot?pc-4:pc,active=cursor>0;
  setDemo('出错时先记住位置，再去处理','CP0 原理演示 · 依据已验证 RTL',`${controls(4)}<div class="demo-controls"><label><input type="checkbox" data-control="delay-slot" ${delaySlot?'checked':''}> 错误发生在分支延迟槽</label></div><div class="schematic"><svg viewBox="0 0 760 200" role="img" aria-label="异常保存和返回">${chip(35,63,175,'原程序','溢出指令 PC',hex(pc),cursor===0||cursor===3)}${chip(285,63,180,'CP0','保存 EPC / Cause',active?hex(epc):'等待异常',cursor===1)}${chip(540,63,180,'异常处理程序','异常入口',hex(0xbfc00380),cursor===2)}<path class="connection lit" d="M210 96H285 M465 96H540"/><path class="connection" d="M630 129V172H122V129"/><text class="chip-sub" x="343" y="164">ERET → EPC</text></svg></div>${facts([['EPC',active?hex(epc):'—'],['Cause.BD',active?(delaySlot?1:0):'—'],['Status.EXL',cursor===1||cursor===2?1:0]])}<p class="record-note">本例选择整数溢出，ExcCode=12。它说明保存与返回机制；真实流水线的 13 个异常处理流程另有断言验证。</p>`,`<strong>${['正常执行，还没有异常。','把故障位置写入 EPC，并进入异常状态。','跳到 0xBFC00380，执行处理程序。','ERET 清除 EXL，回到 EPC。'][cursor]}</strong> ${delaySlot?'延迟槽出错时 BD=1，EPC 保存的是前一条分支的地址，返回时才能重新执行这段控制流。':'普通指令出错时 EPC 就是故障指令的地址。处理软件决定如何修复或调整返回位置。'}`);
  followStep([0,1,0,2][cursor]);
}
function renderCache(){
  const set=cacheResult?.set||0,group=cache.sets[set];
  setDemo('先找近处的副本，再决定是否访问内存','两路写回 Cache 的浏览器原理模型',`<div class="input-row"><label>字节地址<input id="cache-address" value="0x${hex(cacheAddress,3)}"></label><label>写入值<input id="cache-value" value="${cacheValue}"></label><button data-action="cache-read">读</button><button data-action="cache-write">写</button></div><div class="mode-tabs"><button data-cache="0">访问 0x000</button><button data-cache="256">访问 0x100</button><button data-cache="512">访问 0x200</button><button data-action="cache-reset">清空演示</button></div><div class="decode-box"><div><small>Tag · 高 24 位</small><b>${hex(cacheAddress>>>8,6)}</b></div><div><small>Set · 4 位</small><b>${(cacheAddress>>>4)&15}</b></div><div><small>Offset · 4 位</small><b>${cacheAddress&15}</b></div></div><div class="cache-ways">${group.ways.map((line,i)=>`<div class="cache-way ${cacheResult?.way===i?'selected':''}"><h3>SET ${set} / WAY ${i}</h3><p>VALID ${line?1:0} · DIRTY ${line?.dirty?1:0}<br>TAG ${line?hex(line.tag,6):'—'}</p><div class="cache-words">${(line?.data||[null,null,null,null]).map(v=>`<span>${v??'—'}</span>`).join('')}</div></div>`).join('')}</div>${facts([['命中',cache.hits],['未命中',cache.misses],['脏行写回',cache.writebacks]])}<p class="record-note">16 组 × 2 路，每行 4 个字。为了容易看清，模型的后备内存初值设为 0；不提供 MMIO、总线等待或板级时序模拟。</p>`,`<strong>${cacheResult?cacheResult.kind==='hit'?'命中：这份数据已经在 Cache 里。':cacheResult.kind==='writeback'?`需要替换脏行：先把地址 0x${hex(cacheResult.evicted)} 的旧数据写回内存。`:'未命中：从内存取回一整行。':'试试：读 0x000，写 99，再访问 0x100 和 0x200。'}</strong> 这三个地址映射到同一组，但这里只有两路。右侧源码能看到 tag、valid、dirty 和替换选择；项目已有 6 组真实 CPU + Cache 联合回归。`);
  followStep(cacheResult?.kind==='writeback'?2:cacheResult?.kind==='miss'?3:0);
}
function renderDemo(){({board:renderBoard,lab1:renderLab1,lab3:renderLab3,pipeline:renderPipeline,lab5:renderLab5,exceptions:renderExceptions,lab7:renderCache,uart:()=>renderTelemetry(true)})[chapter.id]();}
function length(){return chapter.id==='board'?boardMode==='rtl'?boardTrace.rows.length:project.telemetry.length:chapter.id==='pipeline'?pipeRows().length:chapter.id==='uart'?project.board.records.length:4;}
function advance(){if(cursor>=length()-1){stop();return;}cursor++;renderDemo();}
function action(name){
  if(name==='play'){if(timer!==null){stop();return;}if(cursor>=length()-1)cursor=0;timer=setInterval(advance,chapter.id==='board'&&boardMode==='rtl'?180:750);renderDemo();return;}
  if(['next','prev','end'].includes(name)){stop();cursor=name==='end'?length()-1:Math.max(0,Math.min(length()-1,cursor+(name==='next'?1:-1)));renderDemo();return;}
  if(name==='capture'){displayLab.capture(switchValue);followStep(1);}
  if(name==='display-reset'){displayLab=new DisplayLab();phase=0;}
  if(name==='fib-next'){fibCount=Math.min(20,fibCount+1);followStep(3);}
  if(name==='fib-all'){fibCount=20;followStep(3);}
  if(name==='fib-reset')fibCount=0;
  if(name==='lab3-add'){const a=Number($('lab3-a').value),b=Number($('lab3-b').value);if(!Number.isInteger(a)||!Number.isInteger(b)||a<0||a>255||b<0||b>255)throw new Error('A 和 B 都需要是 0–255 的整数。');lab3A=a;lab3B=b;followStep(2);}
  if(name==='inject')injectFault=!injectFault;
  if(name==='cache-reset'){cache=new CacheLab();cacheResult=null;cacheAddress=0;}
  if(name==='cache-read'||name==='cache-write'){const address=parseInput($('cache-address').value),value=parseInput($('cache-value').value);const result=cache.access(address,name==='cache-write'?value:undefined);cacheAddress=address;cacheValue=value;cacheResult=result;}
  renderDemo();
}
function parseInput(text){if(!/^(0x[\da-f]+|\d+)$/i.test(text.trim()))throw new Error('请输入十进制或 0x 十六进制整数。');const value=Number(text);if(!Number.isInteger(value)||value<0||value>0xffffffff)throw new Error('数值超出 32 位范围。');return value;}
$('demo').addEventListener('click',event=>{try{const target=event.target.closest('button');if(!target)return;
  if(target.dataset.action)action(target.dataset.action);
  if(target.dataset.boardmode){stop();boardMode=target.dataset.boardmode;cursor=0;renderDemo();}
  if(target.dataset.switch!==undefined){switchValue^=1<<Number(target.dataset.switch);renderDemo();}
  if(target.dataset.phase!==undefined){phase=Number(target.dataset.phase);followStep(2);renderDemo();}
  if(target.dataset.lab3){lab3Mode=target.dataset.lab3;renderDemo();}
  if(target.dataset.cache!==undefined){cacheAddress=Number(target.dataset.cache);cacheResult=cache.access(cacheAddress);renderDemo();}
}catch(error){$('explanation').textContent=error.message;}});
$('demo').addEventListener('change',event=>{const control=event.target.dataset.control;if(control==='cursor'){stop();cursor=Number(event.target.value);renderDemo();}if(control==='pipe-mode'){stop();pipeMode=Number(event.target.value);cursor=0;renderDemo();}if(control==='delay-slot'){delaySlot=event.target.checked;renderDemo();}});
$('lesson-steps').addEventListener('click',event=>{const step=event.target.closest('[data-lesson]');if(!step)return;stop();const i=Number(step.dataset.lesson),item=chapter.steps[i];$('follow-source').checked=false;source(item.path,item.start,item.end,item.body);document.querySelectorAll('.lesson-step').forEach(b=>b.classList.toggle('selected',b===step));});
$('source-file').addEventListener('change',()=>{$('follow-source').checked=false;const step=chapter.steps.find(s=>s.path===$('source-file').value);source($('source-file').value,step?.start||1,step?.end||15);});
$('follow-source').onchange=()=>{if($('follow-source').checked){followStep(0);renderDemo();}};
$('copy-source').onclick=async()=>{try{await navigator.clipboard.writeText(project.sources[sourcePath].text);$('copy-source').textContent='已复制';}catch{$('copy-source').textContent='可选中复制';}setTimeout(()=>$('copy-source').textContent='复制',1500);};
$('next-chapter').onclick=()=>{const i=project.chapters.indexOf(chapter);location.hash=project.chapters[(i+1)%project.chapters.length].id;};
$('tour').onclick=()=>{if(chapter.id==='board'){stop();boardMode='rtl';const milestones=[0,5,12,40,68,88,93,97,99,159];let index=0;cursor=0;renderDemo();timer=setInterval(()=>{index++;if(index>=milestones.length){stop();return;}cursor=milestones[index];renderDemo();},1300);}else{const first=$('demo').querySelector('button.play,button[data-action]');first?.click();}};
window.addEventListener('hashchange',()=>{if(project)chooseChapter(location.hash.slice(1));});window.addEventListener('pagehide',stop);
try{
  const responses=await Promise.all([fetch('./data/project.json'),fetch('./data/board-trace.json')]);for(const response of responses)if(!response.ok)throw new Error(`资料加载失败：HTTP ${response.status}`);
  [project,boardTrace]=await Promise.all(responses.map(r=>r.json()));chooseChapter(location.hash.slice(1)||'board');
}catch(error){$('load-error').hidden=false;$('load-error').textContent=`页面资料暂时无法读取：${error.message}。请刷新，或从仓库重新运行 npm run lab。`;}
