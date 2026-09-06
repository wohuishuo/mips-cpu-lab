import {assemble,PipelineCPU} from './engine/cpu.js';
import {PRESETS,makeCustomUnit,rippleAdd} from './engine/circuit.js';
import {mountCircuitEditor} from './circuit-editor.js';

const $=id=>document.getElementById(id);
const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const hex=(value,digits=8)=>(Number(value)>>>0).toString(16).toUpperCase().padStart(digits,'0');
const registerNames=['zero','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7','s0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','fp','ra'];
const stages=['IF','ID','EX','MEM','WB'];
const stageInfo={IF:['取指','PC → 指令存储器','程序计数器给出地址，取出下一条指令。顺序地址按 4 字节递增。'],ID:['译码','控制器 · 寄存器堆','解析操作码与寄存器编号，读取两个源操作数，扩展立即数。'],EX:['执行','ALU · 定制单元','ALU 与定制单元接收操作数；转发网络选择最新值。分支在此决定，保留一个延迟槽。'],MEM:['访存','数据 RAM','按有效地址读写小端字节 RAM。存储器未就绪时保留请求并暂停前级。'],WB:['写回','结果 → 寄存器','将结果写入目标寄存器并完成指令；$zero 的值始终保持为 0。']};
const examples={
  custom:`# A / B 输入到定制电路\naddiu $t0, $a0, 0\ncustom $t1, $t0, $a1\nsw $t1, 0($zero)\nlw $t2, 0($zero)\naddu $t3, $t2, $a1\nsw $t3, 4($zero)\nhalt`,
  fibonacci:`# 前 12 项 Fibonacci → RAM\nli $t0, 0\nli $t1, 1\nli $t2, 12\nli $t3, 0\nloop:\nsw $t0, 0($t3)\naddu $t4, $t0, $t1\nmove $t0, $t1\nmove $t1, $t4\naddiu $t3, $t3, 4\naddiu $t2, $t2, -1\nbne $t2, $zero, loop\nnop # 分支延迟槽\nhalt`,
  hazards:`# RAW 转发 + load-use 停顿\naddu $t0, $a0, $a1\nsw $t0, 0($zero)\nlw $t1, 0($zero)\naddu $t2, $t1, $t1\naddu $t3, $t2, $t1\nsw $t3, 4($zero)\nhalt`,
  bytes:`# 0x12345678 的小端布局\nlui $t0, 0x1234\nori $t0, $t0, 0x5678\nsw $t0, 0($zero)\nli $t1, 0xAB\nsb $t1, 1($zero)\nlbu $t2, 1($zero)\nlb $t3, 1($zero)\nlhu $t4, 0($zero)\nhalt`
};

let cpu,snapshot,timer=null,history=[],timeline=[],selectedStage='EX',stateMode='registers',showHex=true,memoryBase=0,selectedBit=0,editor;
let customNetlist=structuredClone(PRESETS[0].netlist),customName='ADD32 定制单元';
let activeTab='cpu';

function parseWord(text,label){
  const value=String(text).trim();
  if(!/^-?(?:0x[\da-f]+|\d+)$/i.test(value))throw new Error(`${label} 请输入整数（十进制或 0x 十六进制）。`);
  const negative=value.startsWith('-');
  const parsed=Number(negative?value.slice(1):value)*(negative?-1:1);
  if(!Number.isSafeInteger(parsed)||parsed< -2147483648||parsed>4294967295)throw new Error(`${label} 超出 32 位范围。`);
  return parsed>>>0;
}
function notify(text,type=''){$('notice').textContent=text;$('notice').className=`notice ${type}`;}
function pause(){if(timer!==null){clearInterval(timer);timer=null;}$('run').textContent='▶ 运行';if(snapshot)$('status').textContent=snapshot.halted?'已完成':snapshot.cycle?'已暂停':'就绪';renderBoard();}
function loadProgram(message='程序与输入已加载。每次单步推进一个时钟。'){
  pause();
  try{
    const program=assemble($('program').value);
    if(!program.instructions.length)throw new Error('请至少输入一条指令。');
    const custom=makeCustomUnit(customNetlist);
    const next=new PipelineCPU(program,{inputA:parseWord($('input-a').value,'A'),inputB:parseWord($('input-b').value,'B'),waitCycles:Number($('wait').value),custom});
    cpu=next;snapshot=cpu.snapshot();history=[];timeline=[];
    $('program-length').textContent=`${program.instructions.length} 条指令`;
    $('gate-a').value=$('input-a').value;$('gate-b').value=$('input-b').value;
    render();notify(message,'success');return true;
  }catch(error){notify(error.message,'error');return false;}
}
function step(){
  if(!cpu||snapshot.halted)return;
  const before=cpu.snapshot();
  try{
    snapshot=cpu.step();history.push(before);if(history.length>600)history.shift();
    timeline.push(structuredClone(snapshot));if(timeline.length>100)timeline.shift();
    if(snapshot.halted){pause();notify(`执行完成：${snapshot.cycle} 个时钟，${snapshot.retired} 条指令。可回退检查过程。`,'success');}
    render();
  }catch(error){cpu.restore(before);snapshot=cpu.snapshot();pause();render();notify(`运行停止：${error.message}`,'error');}
}
function run(){if(timer!==null){pause();return;}if(!cpu||snapshot.halted)return;timer=setInterval(step,1000/Number($('speed').value));$('run').textContent='Ⅱ 暂停';$('status').textContent='运行中';renderBoard();}
function back(){pause();if(!history.length)return;snapshot=history.pop();cpu.restore(snapshot);timeline=timeline.filter(item=>item.cycle<=snapshot.cycle);render();notify('已回退一个时钟；寄存器、内存与流水线同步恢复。');}
function render(){
  $('cycle').textContent=String(snapshot.cycle).padStart(3,'0');$('retired').textContent=snapshot.retired;
  $('status').textContent=snapshot.halted?'已完成':timer!==null?'运行中':snapshot.cycle?'已暂停':'就绪';
  $('status').className=`status ${snapshot.halted?'finished':''}`;
  $('step').disabled=snapshot.halted;$('run').disabled=snapshot.halted;$('back').disabled=!history.length;
  renderBoard();renderState();renderTimeline();renderGates();
  $('events').textContent=snapshot.events?.length?snapshot.events.join(' · '):snapshot.cycle?'时钟上升沿已完成，流水级状态如上。':'还没有事件。加载程序后，从取指开始。';
}
function chip(stage,x){
  const item=snapshot?.stages?.[stage];const info=stageInfo[stage];
  const pins=Array.from({length:5},(_,i)=>`<path class="pin" d="M${x+18+i*23} 135v-10 M${x+18+i*23} 251v10"/>`).join('');
  const extras=stage==='EX'?`<rect x="${x+13}" y="207" width="123" height="26" rx="4" fill="#443425" stroke="#8b704b"/><text x="${x+74}" y="224" text-anchor="middle" fill="#eac086" font-size="9">⌘ CUSTOM / ALU</text>`:`<text class="chip-sub" x="${x+75}" y="223" text-anchor="middle">${escape(info[1])}</text>`;
  return `<g class="stage-chip ${item?'active':''} ${selectedStage===stage?'selected':''}" data-stage="${stage}" role="button" tabindex="0" aria-label="${stage} ${info[0]}${item?' '+escape(item.text):' 空闲'}">${pins}<rect class="chip-body" x="${x}" y="135" width="150" height="116" rx="8"/><text class="chip-label" x="${x+16}" y="163">${stage}<tspan x="${x+134}" text-anchor="end" font-size="11">${info[0]}</tspan></text><path d="M${x+12} 174H${x+138}" stroke="#455e6670"/><text class="chip-op" x="${x+16}" y="193">${escape(item?String(item.op).toUpperCase():'— 空闲 —')}</text>${extras}<text class="chip-pc" x="${x+75}" y="283" text-anchor="middle">${item?'PC '+hex(item.pc):'等待指令'}</text></g>`;
}
function renderBoard(){
  if(!snapshot)return;
  const moving=timer!==null?'running':'';
  const buses=stages.slice(0,4).map((s,i)=>{const x=40+i*185+150,on=snapshot.stages[s];return `<path class="bus ${on?'active':''} ${moving}" d="M${x} 192H${x+35}" marker-end="url(#arrow)"/><circle class="port ${on?'active':''}" cx="${x}" cy="192" r="3"/><circle class="port ${on?'active':''}" cx="${x+35}" cy="192" r="3"/><text class="board-label" x="${x+17}" y="179" text-anchor="middle">32</text><rect x="${x+13}" y="207" width="10" height="26" rx="2" fill="#263545"/><text class="board-label" x="${x+18}" y="244" text-anchor="middle" font-size="7">D</text>`;}).join('');
  const forwarding=(snapshot.events||[]).some(e=>/forward|转发/i.test(e));
  $('pipeline-board').innerHTML=`<svg viewBox="0 0 1000 380" aria-label="时钟 ${snapshot.cycle} 的五级电路"><defs><marker id="arrow" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0 0L5 2.5L0 5" fill="#678c88"/></marker></defs><text class="board-label" x="42" y="48">DATA PATH / 32-BIT</text><text class="board-label" x="946" y="48" text-anchor="end">CLK ${String(snapshot.cycle).padStart(3,'0')} ↑</text><path class="bus ${snapshot.stages.WB?'active':''} ${moving}" d="M855 125V79H300V125" marker-end="url(#arrow)"/><text class="board-label" x="562" y="71" text-anchor="middle">寄存器写回总线 · WRITE BACK</text><path class="bus ${forwarding?'active forward '+moving:''}" d="M670 261V314H484V261" marker-end="url(#arrow)"/><path class="bus ${forwarding?'active forward '+moving:''}" d="M855 261V337H461V261" marker-end="url(#arrow)"/><text class="board-label" x="575" y="329" text-anchor="middle" style="fill:${forwarding?'#eab46c':'#647b94'}">MEM / WB → EX 转发网络</text>${buses}${stages.map((s,i)=>chip(s,40+i*185)).join('')}<path class="bus" d="M35 362H965"/><path d="M42 362v-6h7v12h7v-12h7v6" fill="none" stroke="#7396a8" stroke-width="1.5"/><text class="board-label" x="80" y="366">时钟总线 · 每次上升沿锁存级间寄存器</text></svg>`;
  $('pipeline-board').querySelectorAll('[data-stage]').forEach(node=>{const choose=()=>{selectedStage=node.dataset.stage;renderBoard();};node.addEventListener('click',choose);node.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();choose();$('pipeline-board').querySelector(`[data-stage="${selectedStage}"]`).focus({preventScroll:true});}});});
  const item=snapshot.stages[selectedStage];$('selected-stage-name').textContent=`${selectedStage} · ${stageInfo[selectedStage][0]}单元`;
  const signalLabels={a:'A',b:'B',result:'结果',address:'地址',storeValue:'写入值',waitRemaining:'等待拍数',redirect:'跳转',dest:'目标',rs:'源1',rt:'源2',imm:'立即数'};
  const priority=selectedStage==='MEM'?['address','storeValue','result','waitRemaining','a','b']:['a','b','result','address','redirect','dest','rs','rt','imm'];
  const signals=item?priority.filter(key=>typeof item[key]==='number'&&(key!=='storeValue'||['sb','sh','sw'].includes(item.op))).slice(0,5).map(key=>`${signalLabels[key]}=${['dest','rs','rt'].includes(key)?'$'+registerNames[item[key]]:key==='waitRemaining'?item[key]:'0x'+hex(item[key])}`).join(' · '):'';
  $('selected-stage-detail').textContent=item?`PC 0x${hex(item.pc)} · ${item.text}${signals?' ｜ '+signals:''}`:stageInfo[selectedStage][2];
}
function renderState(){
  if(!snapshot)return;
  const format=v=>showHex?hex(v):String(v>>>0);
  $('number-format').textContent=showHex?'HEX':'DEC';
  $('state-note').textContent=stateMode==='registers'?'写回时更新 · 变化值高亮':'小端字节 RAM · 每行 4 字节 / 1 个字';
  $('memory-controls').hidden=stateMode!=='memory';
  if(stateMode==='registers'){
    $('state-table').innerHTML=snapshot.registers.map((value,i)=>`<div class="state-row ${snapshot.writes?.registers?.includes(i)?'changed':''} ${value?'nonzero':''}" data-register="${i}"><span class="reg-index">${String(i).padStart(2,'0')}</span><span class="reg-name">$${registerNames[i]}</span><span class="reg-value">${format(value)}</span></div>`).join('');
  }else{
    const rows=[];for(let address=memoryBase;address<Math.min(memoryBase+128,snapshot.memory.length);address+=4){const bytes=snapshot.memory.slice(address,address+4);let word=0;for(let i=0;i<bytes.length;i++)word|=bytes[i]<<(8*i);const changed=bytes.some((_,i)=>snapshot.writes?.memory?.includes(address+i));rows.push(`<div class="state-row memory-row ${changed?'changed':''}" data-address="${address}" title="低地址 → 高地址：${bytes.map(b=>hex(b,2)).join(' ')}"><span class="reg-name" style="grid-column:1/3">${hex(address,4)}</span><span class="reg-value">${format(word)}</span><span class="byte-values">${bytes.map((b,i)=>`<span class="${snapshot.writes?.memory?.includes(address+i)?'byte-changed':''}">${hex(b,2)}</span>`).join('')}<small>+0 → +3</small></span></div>`);} $('state-table').innerHTML=rows.join('')||'<p class="state-note">地址超出 RAM 范围。</p>';
  }
}
function renderTimeline(){
  if(!timeline.length){$('timeline').innerHTML='<div class="empty-timeline">IF → ID → EX → MEM → WB &nbsp; · &nbsp; 按下时钟，第一条指令即将进入。</div>';return;}
  const recent=timeline.slice(-18),rows=new Map();
  for(const snap of recent)for(const stage of stages){const item=snap.stages[stage];if(!item)continue;const id=item.uid??item.id??item.seq??item.pc;const key=String(id);if(!rows.has(key))rows.set(key,{item,cells:{}});rows.get(key).cells[snap.cycle]=stage;}
  const visible=[...rows.values()].slice(-10);
  $('timeline').innerHTML=`<table class="timeline"><thead><tr><th class="instruction-cell">PC / 指令</th>${recent.map(s=>`<th>${s.cycle}</th>`).join('')}</tr></thead><tbody>${visible.map(({item,cells})=>`<tr><td class="instruction-cell" title="${escape(item.text)}"><small>${hex(item.pc,4)}</small>${escape(item.text.length>24?item.text.slice(0,23)+'…':item.text)}</td>${recent.map((s,i)=>{const phase=cells[s.cycle];const stalled=phase&&i>0&&cells[recent[i-1].cycle]===phase;return `<td class="${phase?'filled':''} ${phase==='EX'?'ex':''} ${stalled?'stalled':''}" title="时钟 ${s.cycle}${stalled?' · 本级保持':''}">${phase||'·'}${stalled?'·':''}</td>`;}).join('')}</tr>`).join('')}</tbody></table>`;
  $('timeline').scrollLeft=$('timeline').scrollWidth;
}
function renderGates(){
  let a,b;
  try{
    if($('follow-cpu').checked&&snapshot?.customTrace){a=snapshot.customTrace.a>>>0;b=snapshot.customTrace.b>>>0;$('gate-a').value=a;$('gate-b').value=b;}
    else {a=parseWord($('gate-a').value,'门级 A');b=parseWord($('gate-b').value,'门级 B');}
  }catch(error){$('gate-equation').textContent=error.message;return;}
  const sum=rippleAdd(a,b,32),bit=sum.bits[selectedBit];
  $('selected-bit').textContent=String(selectedBit).padStart(2,'0');$('sum-caption').textContent=`0x${hex(a)} + 0x${hex(b)} = 0x${hex(sum.value)}`;
  $('bit-strip').innerHTML=[...sum.bits.entries()].reverse().map(([i,v])=>`<button data-bit="${i}" class="${i===selectedBit?'active':''}" aria-label="观察第 ${i} 位，和为 ${v.sum}" aria-pressed="${i===selectedBit}">${v.sum}<span class="bit-index">${i}</span></button>`).join('');
  $('bit-strip').querySelectorAll('button').forEach(button=>button.onclick=()=>{selectedBit=Number(button.dataset.bit);renderGates();});
  const xor=bit.a^bit.b,and=bit.a&bit.b,carryAnd=xor&bit.cin;
  const wire=(d,on)=>`<path class="logic-wire ${on?'on':''}" d="${d}"/>`;
  const gate=(x,y,label,on,type='xor')=>{
    let d=type==='and'?`M${x} ${y}h24a24 24 0 0 1 0 48h-24z`:type==='or'?`M${x} ${y}Q${x+35} ${y} ${x+56} ${y+24}Q${x+35} ${y+48} ${x} ${y+48}Q${x+17} ${y+24} ${x} ${y}`:`M${x} ${y}Q${x+35} ${y} ${x+56} ${y+24}Q${x+35} ${y+48} ${x} ${y+48}Q${x+17} ${y+24} ${x} ${y}M${x-6} ${y}Q${x+11} ${y+24} ${x-6} ${y+48}`;
    return `<path class="logic-gate ${on?'on':''}" d="${d}"/><text class="logic-label" x="${x+24}" y="${y+68}" text-anchor="middle">${label}</text><text x="${x+72}" y="${y+29}" fill="${on?'#63dfbb':'#73879c'}" font-size="13">${on?1:0}</text>`;
  };
  $('gate-diagram').innerHTML=`<svg viewBox="0 0 800 270" role="img" aria-label="位 ${selectedBit} 全加器 A=${bit.a} B=${bit.b} Cin=${bit.cin} Sum=${bit.sum} Cout=${bit.carry}">${wire('M52 49H165V62H198',bit.a)}${wire('M52 96H145V86H198',bit.b)}${wire('M52 221H346V87H410',bit.cin)}${wire('M254 74H335V62H410',xor)}${wire('M464 74H720',bit.sum)}${wire('M125 49V154H198',bit.a)}${wire('M100 96V178H198',bit.b)}${wire('M305 74V176H410',xor)}${wire('M346 221H382V200H410',bit.cin)}${wire('M247 166H543V163H595',and)}${wire('M459 188H569V187H595',carryAnd)}${wire('M651 175H720',bit.carry)}${gate(198,50,'XOR',xor)}${gate(410,50,'XOR',bit.sum)}${gate(198,142,'AND',and,'and')}${gate(410,164,'AND',carryAnd,'and')}${gate(595,151,'OR',bit.carry,'or')}<g font-size="13" fill="#a4b5c8"><text x="14" y="53">A ${bit.a}</text><text x="14" y="101">B ${bit.b}</text><text x="3" y="226">Cᵢ ${bit.cin}</text><text x="726" y="79" fill="#63dfbb">S ${bit.sum}</text><text x="726" y="180" fill="#eab46c">Cₒ ${bit.carry}</text></g><circle cx="125" cy="49" r="3" fill="${bit.a?'#63dfbb':'#53697b'}"/><circle cx="100" cy="96" r="3" fill="${bit.b?'#63dfbb':'#53697b'}"/><circle cx="305" cy="74" r="3" fill="${xor?'#63dfbb':'#53697b'}"/><circle cx="346" cy="221" r="3" fill="${bit.cin?'#63dfbb':'#53697b'}"/></svg>`;
  $('gate-equation').innerHTML=`S = ${bit.a} ⊕ ${bit.b} ⊕ ${bit.cin} = <b>${bit.sum}</b> &nbsp; · &nbsp; Cₒ = (${bit.a} ∧ ${bit.b}) ∨ (${xor} ∧ ${bit.cin}) = <b>${bit.carry}</b>`;
  $('gate-source').textContent=`ADD32 加法结构${snapshot?.customTrace&&$('follow-cpu').checked?' · 使用最近一次 CUSTOM 的输入':''}。当前安装：${customName}；自定义网络请在电路工坊查看。`;
}
function switchTab(tab){activeTab=tab;if(tab!=='cpu')pause();for(const name of ['cpu','circuit','guide'])$(`${name}-view`).hidden=name!==tab;document.querySelectorAll('[data-tab]').forEach(button=>{button.classList.toggle('active',button.dataset.tab===tab);button.setAttribute('aria-selected',button.dataset.tab===tab);});if(tab==='circuit'&&!editor){editor=mountCircuitEditor($('circuit-root'),{onInstall(netlist){
    try{makeCustomUnit(netlist);const program=assemble($('program').value);if(!program.instructions.length)throw new Error('请先在 CPU 运行页输入有效程序，再安装电路。');parseWord($('input-a').value,'A');parseWord($('input-b').value,'B');customNetlist=structuredClone(netlist);const preset=PRESETS.find(p=>JSON.stringify(p.netlist)===JSON.stringify(netlist));customName=preset?.name||'已安装的定制电路';$('unit-name').textContent=customName;switchTab('cpu');loadProgram('定制电路已接入 CUSTOM。程序已复位，运行后可比较寄存器和 RAM 结果。');}catch(error){notify(error.message,'error');throw error;}
  }});} }

$('program').value=examples.custom;
$('load').onclick=()=>loadProgram();$('reset').onclick=()=>loadProgram('CPU 已复位，程序与定制电路已保留。');$('step').onclick=()=>{pause();step();};$('run').onclick=run;$('back').onclick=back;
$('speed').oninput=()=>{const wasRunning=timer!==null;$('speed-label').textContent=`${$('speed').value} Hz`;if(wasRunning){pause();run();}};
$('example').onchange=()=>{$('program').value=examples[$('example').value];loadProgram('已切换示例并复位 CPU。');};
$('wait').onchange=()=>loadProgram('存储等待参数已更新，CPU 已复位。');
$('number-format').onclick=()=>{showHex=!showHex;renderState();};
document.querySelectorAll('[data-state]').forEach(button=>button.onclick=()=>{stateMode=button.dataset.state;document.querySelectorAll('[data-state]').forEach(b=>b.classList.toggle('active',b===button));renderState();});
$('memory-show').onclick=()=>{try{const address=parseWord($('memory-base').value,'内存地址');if(address>=snapshot.memory.length)throw new Error(`内存地址范围为 0–${snapshot.memory.length-1}。`);memoryBase=address&~3;$('memory-base').value=memoryBase;renderState();}catch(error){notify(error.message,'error');}};
document.querySelectorAll('[data-tab]').forEach(button=>button.onclick=()=>switchTab(button.dataset.tab));$('go-circuit').onclick=()=>{switchTab('circuit');window.scrollTo({top:0,behavior:'smooth'});};
for(const id of ['gate-a','gate-b'])$(id).oninput=()=>{$('follow-cpu').checked=false;renderGates();};$('follow-cpu').onchange=renderGates;
document.addEventListener('keydown',event=>{if(event.defaultPrevented||activeTab!=='cpu'||event.ctrlKey||event.metaKey||event.altKey||/INPUT|TEXTAREA|SELECT|BUTTON/.test(event.target.tagName)||event.target.isContentEditable)return;if(event.key===' '){event.preventDefault();run();}if(event.key.toLowerCase()==='n'){pause();step();}if(event.key.toLowerCase()==='b')back();});
window.addEventListener('pagehide',()=>{pause();editor?.destroy();});
loadProgram('已加载定制单元示例。A = 7，B = 5；预期 RAM[0] = 12，RAM[4] = 17。');
