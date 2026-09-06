import { GATE_TYPES, PRESETS, evaluateCircuit, validateCircuit, makeCustomUnit } from './engine/circuit.js';

const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const clone=value=>JSON.parse(JSON.stringify(value));
const WIDTH=166, HEIGHT=122;
const fmt=(v,width)=>v===null || v===undefined ? 'X · 未知' : width===1 ? String(v) : `0x${v.toString(16).toUpperCase().padStart(Math.ceil(width/4),'0')}`;
const signalClass=v=>v===null || v===undefined ? 'unknown' : v===0 ? 'low' : 'high';
const portPosition=(node,port,direction)=> {
  const ports=GATE_TYPES[node.type][direction==='in'?'inputs':'outputs'];
  return {x:node.x+(direction==='in'?0:WIDTH),y:node.y+49+ports.indexOf(port)*25};
};

/** Standalone editor. Its mutable draft does not alter an already installed unit. */
export function mountCircuitEditor(container,{onInstall=()=>{}}={}) {
  let net=clone(PRESETS[0].netlist), state={}, selected=null, pending=null, drag=null, skipClick=false, zoom=1, count=1, ticks=0, destroyed=false;
  let evaluation=evaluateCircuit(net), truthRows=null, challengeKind='xor';
  const root=document.createElement('section');root.className='circuit-editor';root.tabIndex=-1;
  root.innerHTML=`
    <div class="ce-topbar"><div><span class="ce-eyebrow">CIRCUIT WORKBENCH</span><h2>把逻辑接成电路</h2></div>
      <button type="button" class="ce-install" data-action="install">装入 CPU · CUSTOM <span aria-hidden="true">↗</span></button></div>
    <p class="ce-intro">从输出端口接到输入端口，让信号在连线上流动。32 位 A / B → Y 可作为 CPU 的自定义运算。</p>
    <div class="ce-toolbar"><label>电路示例 <select data-control="preset" aria-label="电路示例">${PRESETS.map(p=>`<option value="${p.id}">${p.name}</option>`).join('')}</select></label>
      <button type="button" data-action="clock">时钟上升沿 ↑ <span data-role="ticks">0</span></button><button type="button" data-action="reset-state">重置时钟</button>
      <span class="ce-toolbar-spacer"></span><button type="button" data-action="export">导出 JSON</button><button type="button" data-action="import">导入 JSON</button>
      <input type="file" accept=".json,application/json" data-control="file" hidden></div>
    <div class="ce-workspace"><aside class="ce-library"><div class="ce-panel-label">元件库 <span>点击添加</span></div>
      <label class="ce-width-label">新元件位宽 <select data-control="add-width" aria-label="新元件位宽"><option>1</option><option>8</option><option>16</option><option>32</option></select></label>
      <div class="ce-gates">${Object.entries(GATE_TYPES).map(([type,g])=>`<button type="button" data-add="${type}" aria-label="添加 ${type} ${g.label}"><b>${type==='DFF'?'▹ D':type==='ADD'?'+':type==='XOR'?'⊕':type==='NOT'?'¬':type==='AND'?'&':type==='OR'?'≥1':type==='INPUT'?'→':type==='OUTPUT'?'◉':type==='CONST'?'01':type==='MUX'?'▱':type==='NAND'?'⊼':'⊽'}</b><span>${g.label}<small>${type}</small></span></button>`).join('')}</div>
    </aside><div class="ce-board"><div class="ce-board-heading"><span><i></i> 实时信号 <small data-role="count"></small></span><div class="ce-zoom"><button type="button" data-action="zoom-out" aria-label="缩小电路">−</button><output data-role="zoom">100%</output><button type="button" data-action="zoom-in" aria-label="放大电路">+</button></div></div>
      <div class="ce-viewport" tabindex="0" aria-label="电路画布，可滚动查看"><svg xmlns="http://www.w3.org/2000/svg" class="ce-svg" aria-label="可交互逻辑电路" role="group"></svg></div>
      <div class="ce-board-footer"><span><i class="ce-dot high"></i> 有值</span><span><i class="ce-dot low"></i> 0</span><span><i class="ce-dot unknown"></i> 未知 X</span><span class="ce-help">拖动元件 · 点击端口接线 · 选中后 Delete 删除</span></div>
    </div><aside class="ce-inspector"><div class="ce-panel-label">信号与属性</div><div data-role="inspector"></div></aside></div>
    <div class="ce-status" role="status" aria-live="polite"></div>
    <div class="ce-bottom"><div class="ce-io"><div class="ce-panel-label">输入开关 <span>即时求值</span></div><div data-role="inputs"></div></div>
      <div class="ce-challenge"><div class="ce-challenge-header"><div><span class="ce-eyebrow">LOGIC CHALLENGE</span><h3>用真值表验证你的电路</h3></div><div><select aria-label="逻辑挑战" data-control="challenge"><option value="xor">异或 · 4 行真值表</option><option value="and">与门 · 4 行真值表</option><option value="fulladder">全加器 · 8 行真值表</option><option value="add32">32 位加法 · 5 组测试向量</option></select><button type="button" data-action="challenge">运行验证</button></div></div><div data-role="truth"><p>选择目标后运行验证。每一行都会实际求值当前电路，不会改变输入开关。</p></div></div></div>`;
  container.append(root);
  const $=selector=>root.querySelector(selector), svg=$('svg'), viewport=$('.ce-viewport'), status=$('.ce-status');
  const tell=(text,error=false)=>{status.textContent=text;status.classList.toggle('ce-error',error);};
  const setZoom=value=>{zoom=Math.max(.5,Math.min(1.5,value));$('[data-role="zoom"]').textContent=`${Math.round(zoom*100)}%`;draw();};
  const nodeValue=n=>n.type==='OUTPUT'?evaluation.outputs[n.name]:evaluation.values[n.id]?.out;

  function draw() {
    const boardW=Math.max(1160,...net.nodes.map(n=>n.x+WIDTH+75)), boardH=Math.max(540,...net.nodes.map(n=>n.y+HEIGHT+60));
    svg.setAttribute('viewBox',`0 0 ${boardW} ${boardH}`);svg.style.width=`${boardW*zoom}px`;svg.style.height=`${boardH*zoom}px`;
    const wires=net.wires.map((w,index)=> {
      const source=net.nodes.find(n=>n.id===w.from.node),target=net.nodes.find(n=>n.id===w.to.node);
      if(!source || !target) return '';
      const a=portPosition(source,w.from.port,'out'),b=portPosition(target,w.to.port,'in'),value=evaluation.values[source.id]?.[w.from.port];
      let d;
      if(b.x>a.x+35) {const middle=(a.x+b.x)/2;d=`M ${a.x} ${a.y} H ${middle} V ${b.y} H ${b.x}`;}
      else {const below=Math.max(source.y,target.y)+HEIGHT+30+index%3*14;d=`M ${a.x} ${a.y} H ${a.x+25} V ${below} H ${b.x-25} V ${b.y} H ${b.x}`;}
      return `<g class="ce-wire ${signalClass(value)} ${selected?.wire===index?'selected':''}" data-wire="${index}" tabindex="0" role="button" aria-label="连线 ${escape(source.name||source.id)}.${w.from.port} 到 ${escape(target.name||target.id)}.${w.to.port}"><path class="ce-wire-hit" d="${d}"/><path class="ce-wire-line" d="${d}"/><title>${escape(fmt(value,source.width))} · 点击选中，Delete 删除</title></g>`;
    }).join('');
    const nodes=net.nodes.map(n=> {
      const type=GATE_TYPES[n.type],value=nodeValue(n);
      const ports=(direction)=>type[direction==='in'?'inputs':'outputs'].map(p=> {
        const pt=portPosition(n,p,direction),active=pending?.node===n.id && pending?.port===p;
        const busWidth=n.type==='MUX' && p==='sel'?1:n.width;
        return `<g class="ce-port ${active?'pending':''}" data-node="${n.id}" data-port="${p}" data-direction="${direction}" tabindex="0" role="button" aria-label="${escape(n.name||n.id)} ${direction==='out'?'输出':'输入'}端口 ${p}，${busWidth} 位"><circle cx="${pt.x-n.x}" cy="${pt.y-n.y}" r="13" class="ce-port-hit"/><circle cx="${pt.x-n.x}" cy="${pt.y-n.y}" r="5"/><text x="${pt.x-n.x+(direction==='in'?13:-13)}" y="${pt.y-n.y+4}" text-anchor="${direction==='in'?'start':'end'}">${p}</text></g>`;
      }).join('');
      return `<g class="ce-node ${signalClass(value)} ${selected?.node===n.id?'selected':''}" data-node="${n.id}" transform="translate(${n.x} ${n.y})" tabindex="0" role="button" aria-label="元件 ${escape(n.name||n.id)} ${n.type}，${n.width} 位；方向键移动"><rect class="ce-node-shell" width="${WIDTH}" height="${HEIGHT}" rx="10"/><path class="ce-node-divider" d="M 1 32 H ${WIDTH-1}"/><text class="ce-node-title" x="13" y="22">${escape(n.name||n.type)}</text><text class="ce-node-width" x="${WIDTH-12}" y="22" text-anchor="end">${n.width} BIT</text><text class="ce-node-symbol" x="${WIDTH/2}" y="68" text-anchor="middle">${n.type==='ADD'?'A + B':n.type==='DFF'?'▹ D → Q':n.type==='INPUT'?'IN':n.type==='OUTPUT'?'OUT':n.type}</text><text class="ce-node-value" x="${WIDTH/2}" y="105" text-anchor="middle">${escape(fmt(value,n.width))}</text>${ports('in')}${ports('out')}</g>`;
    }).join('');
    svg.innerHTML=`<g class="ce-wires">${wires}</g><g class="ce-nodes">${nodes}</g>`;
    $('[data-role="count"]').textContent=`${net.nodes.length} 元件 / ${net.wires.length} 连线`;
  }

  function showInspector() {
    const dest=$('[data-role="inspector"]');
    if(selected?.wire!==undefined) {
      const w=net.wires[selected.wire];
      dest.innerHTML=`<div class="ce-selection-title">连线 #${selected.wire+1}</div><p class="ce-mono">${escape(w.from.node)}.${w.from.port}<br>↓<br>${escape(w.to.node)}.${w.to.port}</p><button type="button" class="ce-danger" data-action="delete">删除选中连线</button>`;return;
    }
    const n=net.nodes.find(n=>n.id===selected?.node);
    if(!n) {
      dest.innerHTML=`<div class="ce-empty-symbol">⌁</div><p>选中元件查看属性。<br>点击输出圆点，再点输入圆点即可接线。</p><div class="ce-output-list">${Object.entries(evaluation.outputs).map(([name,v])=>`<div><span>${escape(name)}</span><strong class="${signalClass(v)}">${escape(fmt(v,net.nodes.find(n=>n.name===name)?.width||32))}</strong></div>`).join('')}</div><p class="ce-note">开放端口显示 X；组合环路和位宽不匹配会被阻止。</p>`;return;
    }
    dest.innerHTML=`<div class="ce-selection-title">${GATE_TYPES[n.type].label} <small>${n.id}</small></div>
      ${n.type==='INPUT'||n.type==='OUTPUT'?`<label>接口名称<input data-property="name" aria-label="元件接口名称" maxlength="48" value="${escape(n.name)}"></label>`:''}
      <label>位宽<input data-property="width" aria-label="元件位宽" type="number" min="1" max="32" value="${n.width}"></label>
      ${['INPUT','CONST','DFF'].includes(n.type)?`<label>${n.type==='DFF'?'复位值':'输入值'}<input data-property="value" aria-label="元件输入值" value="${n.value??0}" spellcheck="false"></label>`:''}
      <div class="ce-inspector-value"><span>当前信号</span><strong>${escape(fmt(nodeValue(n),n.width))}</strong></div>
      ${n.type==='DFF'?`<p class="ce-note">下一拍 D：${escape(fmt(evaluation.nextState[n.id],n.width))}<br>仅在点击时钟上升沿后更新 Q。</p>`:''}
      <button type="button" class="ce-danger" data-action="delete">删除元件与连线</button><p class="ce-note">端口必须同位宽；MUX 的 sel 始终为 1 位。选中元件后也可用方向键移动。</p>`;
  }

  function showInputs() {
    const inputs=net.nodes.filter(n=>n.type==='INPUT');
    $('[data-role="inputs"]').innerHTML=inputs.length?inputs.map(n=>{
      const value=nodeValue(n),unknown=value===null || value===undefined;
      return `<div class="ce-input-row"><label for="ce-input-${n.id}">${escape(n.name)} <small>${n.width} BIT</small></label>${n.width===1?`<button id="ce-input-${n.id}" type="button" role="${unknown?'checkbox':'switch'}" aria-checked="${unknown?'mixed':value===1}" data-toggle="${n.id}" aria-label="输入 ${escape(n.name)} 开关${unknown?'，未知 X':''}" class="ce-switch ${value===1?'on':''}"><i></i><span>${unknown?'X':value}</span></button>`:`<input id="ce-input-${n.id}" data-input="${n.id}" aria-label="输入 ${escape(n.name)} 数值" value="${n.value??0}" spellcheck="false">`}</div>`;
    }).join(''):'<p>添加 INPUT 元件以提供输入。</p>';
  }

  function refresh({inputs=true}={}) {
    evaluation=evaluateCircuit(net,{},state);draw();showInspector();if(inputs) showInputs();
    if(truthRows) {$('[data-role="truth"]').innerHTML='<p>电路或输入已改变，请重新运行验证。</p>';truthRows=null;}
    $('[data-role="ticks"]').textContent=ticks;
    if(evaluation.errors.length) tell(evaluation.errors.join(' '),true);
  }

  function removeSelected() {
    if(selected?.node) {const id=selected.node;net.nodes=net.nodes.filter(n=>n.id!==id);net.wires=net.wires.filter(w=>w.from.node!==id && w.to.node!==id);delete state[id];}
    else if(selected?.wire!==undefined) net.wires.splice(selected.wire,1);
    else {tell('先选择一个元件或连线。');return;}
    selected=null;pending=null;refresh();tell('已删除选中对象。');
  }

  function connectPort(element) {
    const {node,port,direction}=element.dataset;
    if(direction==='out') {pending=pending?.node===node && pending?.port===port?null:{node,port};draw();tell(pending?'已选输出端口，请点击目标输入端口。':'已取消接线。');return;}
    if(!pending) {tell('先点击一个输出端口，再点击输入端口。');return;}
    const candidate={nodes:net.nodes,wires:[...net.wires,{from:{...pending},to:{node,port}}]}, errors=validateCircuit(candidate);
    if(errors.length) {tell(errors.join(' '),true);return;}
    net=candidate;pending=null;refresh();tell('连线已接通。');
  }

  function challenge() {
    const kind=challengeKind, inputNames=kind==='fulladder'?['A','B','Cin']:['A','B'], outputNames=kind==='fulladder'?['Sum','Carry']:['Y'];
    const requiredWidth=kind==='add32'?32:1;
    const missing=[...inputNames.map(name=>({name,type:'INPUT'})),...outputNames.map(name=>({name,type:'OUTPUT'}))].filter(item=>!net.nodes.some(n=>n.name===item.name && n.type===item.type && n.width===requiredWidth));
    if(missing.length) {tell(`此挑战需要 ${requiredWidth} 位接口：${inputNames.join(' / ')} → ${outputNames.join(' / ')}。`,true);return;}
    if(net.nodes.some(n=>n.type==='DFF')) {tell('真值表挑战使用组合电路，请移除 DFF。',true);return;}
    const rows=kind==='add32'?[[0,0],[7,5],[255,1],[2147483647,1],[4294967295,1]]:Array.from({length:kind==='fulladder'?8:4},(_,i)=>kind==='fulladder'?[(i>>2)&1,(i>>1)&1,i&1]:[(i>>1)&1,i&1]);
    const expected32=[0,12,256,2147483648,0];let passed=0;
    truthRows=rows.map((row,i)=> {
      const inp=Object.fromEntries(inputNames.map((name,j)=>[name,row[j]])),r=evaluateCircuit(net,inp);
      const sum=row.reduce((a,b)=>a+b,0);
      const expected=kind==='add32'?[expected32[i]]:kind==='fulladder'?[sum%2,sum>=2?1:0]:[kind==='and'?(row[0] && row[1]?1:0):row[0]!==row[1]?1:0];
      const actual=outputNames.map(name=>r.outputs[name]??null),ok=!r.errors.length && actual.every((v,j)=>v===expected[j]);if(ok) passed++;
      return `<tr class="${ok?'ce-pass':'ce-fail'}">${row.map(v=>`<td>${v}</td>`).join('')}<td>${expected.join(' / ')}</td><td>${actual.map(v=>v===null?'X':v).join(' / ')}</td><td>${ok?'✓':'×'}</td></tr>`;
    });
    $('[data-role="truth"]').innerHTML=`<div class="ce-challenge-result ${passed===rows.length?'ce-pass':'ce-fail'}">${passed===rows.length?'验证通过':'继续接线'} · ${passed} / ${rows.length} ${kind==='add32'?'测试向量':'真值表行'}</div><div class="ce-table-scroll"><table><thead><tr>${inputNames.map(n=>`<th>${n}</th>`).join('')}<th>预期 ${outputNames.join(' / ')}</th><th>实际</th><th>结果</th></tr></thead><tbody>${truthRows.join('')}</tbody></table></div>`;
    tell(passed===rows.length?'挑战通过！所有列出的输入组合均得到正确输出。':'部分输出不符合目标，请检查元件与接线。',passed!==rows.length);
  }

  async function click(event) {
    if(skipClick) {skipClick=false;return;}
    const port=event.target.closest('[data-port]');if(port) {connectPort(port);return;}
    const add=event.target.closest('[data-add]');
    if(add) {
      if(net.nodes.length>=256) {tell('已达到 256 个元件上限。',true);return;}
      const type=add.dataset.add,width=Number($('[data-control="add-width"]').value);let id;
      do{id=`g${count++}`;}while(net.nodes.some(n=>n.id===id));
      const n={id,type,width,x:Math.max(30,Math.min(900,viewport.scrollLeft/zoom+230+(count%3)*45)),y:Math.max(30,Math.min(650,viewport.scrollTop/zoom+90+(count%4)*65))};
      if(type==='INPUT' || type==='OUTPUT') {let i=1;while(net.nodes.some(n=>n.name===`${type==='INPUT'?'I':'O'}${i}`)) i++;n.name=`${type==='INPUT'?'I':'O'}${i}`;}
      if(['INPUT','CONST','DFF'].includes(type)) n.value=0;
      net.nodes.push(n);selected={node:id};refresh();tell(`已添加 ${GATE_TYPES[type].label}；拖动到合适位置，再接线。`);return;
    }
    const toggle=event.target.closest('[data-toggle]');if(toggle) {const n=net.nodes.find(n=>n.id===toggle.dataset.toggle);n.value=nodeValue(n)===1?0:1;refresh();tell(`${n.name} = ${n.value}`);return;}
    const action=event.target.closest('[data-action]')?.dataset.action;
    if(action) {
      if(action==='delete') removeSelected();
      if(action==='clock') {if(evaluation.errors.length) {tell('请先修复电路错误。',true);return;}state={...evaluation.nextState};ticks++;refresh();tell(`时钟 ↑ ${ticks}：所有 DFF 同时采样 D。`);}
      if(action==='reset-state') {state={};ticks=0;refresh();tell('DFF 已恢复初值。');}
      if(action==='zoom-in') setZoom(zoom+.1);
      if(action==='zoom-out') setZoom(zoom-.1);
      if(action==='challenge') challenge();
      if(action==='import') $('[data-control="file"]').click();
      if(action==='export') {const blob=new Blob([JSON.stringify(net,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='my-custom-circuit.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);tell('电路 JSON 已导出。');}
      if(action==='install') {try {makeCustomUnit(net);await onInstall(clone(net));tell('已装入 CPU。CUSTOM 现在执行这份电路；后续编辑需再次装入。');}catch(error) {tell(error.message,true);}}
      return;
    }
    const wire=event.target.closest('[data-wire]');if(wire) {selected={wire:Number(wire.dataset.wire)};draw();showInspector();root.focus({preventScroll:true});return;}
    const el=event.target.closest('.ce-node');if(el) {selected={node:el.dataset.node};draw();showInspector();root.focus({preventScroll:true});return;}
    if(event.target===svg) {selected=null;pending=null;draw();showInspector();tell('点击输出端口 → 输入端口接线。');}
  }

  async function change(event) {
    const el=event.target;
    if(el.dataset.control==='preset') {net=clone(PRESETS.find(p=>p.id===el.value).netlist);state={};ticks=0;selected=null;pending=null;viewport.scrollLeft=0;viewport.scrollTop=0;refresh();tell(PRESETS.find(p=>p.id===el.value).description);return;}
    if(el.dataset.control==='challenge') {challengeKind=el.value;truthRows=null;$('[data-role="truth"]').innerHTML='<p>目标已改变，点击运行验证。</p>';return;}
    if(el.dataset.control==='file') {
      const file=el.files[0];if(!file) return;
      try {if(file.size>512000) throw new Error('JSON 文件不能超过 500 KB。');const draft=JSON.parse(await file.text()),errors=validateCircuit(draft);if(errors.length) throw new Error(errors.join(' '));if(destroyed) return;net=clone(draft);state={};ticks=0;selected=null;pending=null;refresh();tell(`已导入 ${net.nodes.length} 个元件。`);}catch(error) {tell(`导入失败：${error.message}`,true);}finally {el.value='';}return;
    }
    const inputId=el.dataset.input,property=el.dataset.property;
    if(!inputId && !property) return;
    const n=net.nodes.find(n=>n.id===(inputId||selected?.node));if(!n) return;
    const draft=clone(net),edited=draft.nodes.find(x=>x.id===n.id),key=inputId?'value':property;
    let value=el.value.trim();
    if(key!=='name') {value=Number(value);if(!Number.isSafeInteger(value)) {tell('请输入有效整数，可使用 0x 十六进制。',true);el.value=n[key]??0;return;}}
    edited[key]=value;const errors=validateCircuit(draft);
    if(errors.length) {tell(errors.join(' '),true);el.value=n[key]??'';return;}
    net=draft;refresh();tell(`${edited.name||edited.id} 的属性已更新。`);
  }

  function pointerDown(event) {
    if(event.button!==0 || event.target.closest('[data-port]')) return;
    const element=event.target.closest('.ce-node');if(!element) return;
    const n=net.nodes.find(n=>n.id===element.dataset.node);selected={node:n.id};
    drag={id:n.id,clientX:event.clientX,clientY:event.clientY,x:n.x,y:n.y,moved:false};
  }
  function pointerMove(event) {
    if(!drag) return;const dx=(event.clientX-drag.clientX)/zoom,dy=(event.clientY-drag.clientY)/zoom;
    if(Math.abs(dx)+Math.abs(dy)<4 && !drag.moved) return;
    if(!drag.moved) svg.setPointerCapture(event.pointerId);
    drag.moved=true;const n=net.nodes.find(n=>n.id===drag.id);n.x=Math.max(20,Math.min(9500,Math.round(drag.x+dx)));n.y=Math.max(20,Math.min(9500,Math.round(drag.y+dy)));draw();
  }
  function pointerUp(event) {
    if(!drag) return;skipClick=drag.moved;const moved=drag.moved;drag=null;if(svg.hasPointerCapture(event.pointerId)) svg.releasePointerCapture(event.pointerId);
    if(moved) {draw();root.focus({preventScroll:true});}showInspector();
    // Replacing the dragged SVG node can suppress its synthetic click entirely.
    // Never carry that suppression into the user's next deliberate port click.
    setTimeout(()=>{skipClick=false;},0);
  }
  function keydown(event) {
    if(event.target.matches('input,select,textarea')) return;
    if(event.key==='Delete' || event.key==='Backspace') {event.preventDefault();removeSelected();return;}
    if(event.key==='Escape') {pending=null;selected=null;draw();showInspector();return;}
    const focusPort=event.target.closest('[data-port]'),focusNode=event.target.closest('.ce-node'),focusWire=event.target.closest('[data-wire]');
    if((event.key==='Enter'||event.key===' ') && (focusPort||focusNode||focusWire)) {
      event.preventDefault();
      const selector=focusPort?`.ce-port[data-node="${focusPort.dataset.node}"][data-port="${focusPort.dataset.port}"]`:focusWire?`.ce-wire[data-wire="${focusWire.dataset.wire}"]`:`.ce-node[data-node="${focusNode.dataset.node}"]`;
      click({target:event.target});svg.querySelector(selector)?.focus();return;
    }
    if(focusNode && !focusPort && ['ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(event.key)) {
      event.preventDefault();const n=net.nodes.find(n=>n.id===focusNode.dataset.node),step=event.shiftKey?40:10;
      n.x=Math.max(20,Math.min(9500,n.x+(event.key==='ArrowRight'?step:event.key==='ArrowLeft'?-step:0)));n.y=Math.max(20,Math.min(9500,n.y+(event.key==='ArrowDown'?step:event.key==='ArrowUp'?-step:0)));selected={node:n.id};draw();svg.querySelector(`.ce-node[data-node="${n.id}"]`)?.focus();showInspector();
    }
  }
  root.addEventListener('click',click);root.addEventListener('change',change);root.addEventListener('keydown',keydown);
  svg.addEventListener('pointerdown',pointerDown);svg.addEventListener('pointermove',pointerMove);svg.addEventListener('pointerup',pointerUp);svg.addEventListener('pointercancel',pointerUp);
  refresh();tell(PRESETS[0].description);
  return {getNetlist:()=>clone(net),destroy(){destroyed=true;root.remove();}};
}
