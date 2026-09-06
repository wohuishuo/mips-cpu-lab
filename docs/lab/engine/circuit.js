/** Bounded, deterministic digital netlists. null denotes an unknown whole bus. */
export const GATE_TYPES = Object.freeze({
  INPUT:{label:'输入',inputs:[],outputs:['out']}, OUTPUT:{label:'输出',inputs:['in'],outputs:[]},
  CONST:{label:'常量',inputs:[],outputs:['out']}, NOT:{label:'非门',inputs:['in'],outputs:['out']},
  AND:{label:'与门',inputs:['a','b'],outputs:['out']}, OR:{label:'或门',inputs:['a','b'],outputs:['out']},
  XOR:{label:'异或',inputs:['a','b'],outputs:['out']}, NAND:{label:'与非',inputs:['a','b'],outputs:['out']},
  NOR:{label:'或非',inputs:['a','b'],outputs:['out']}, MUX:{label:'选择器',inputs:['a','b','sel'],outputs:['out']},
  ADD:{label:'加法器',inputs:['a','b'],outputs:['out']}, DFF:{label:'触发器',inputs:['d'],outputs:['out']},
});
const own=(obj,key)=>Object.prototype.hasOwnProperty.call(obj,key);
const validKey=s=>typeof s==='string' && /^[A-Za-z_][A-Za-z0-9_]{0,47}$/.test(s) && !['__proto__','prototype','constructor'].includes(s);
const mask=w=>w===32 ? 0xffffffff : 2**w-1;
const normalize=(v,w)=>v===null || !Number.isSafeInteger(v) ? null : ((v>>>0)&mask(w))>>>0;
const portWidth=(n,p)=>n.type==='MUX' && p==='sel' ? 1 : n.width;

function inspect(net) {
  const errors=[], nodes=new Map(), drivers=new Map(), order=[];
  if (!net || typeof net!=='object' || !Array.isArray(net.nodes) || !Array.isArray(net.wires))
    return {errors:['电路必须包含 nodes 和 wires 数组。'],nodes,drivers,order};
  if(net.nodes.length>256 || net.wires.length>1024) return {errors:['电路上限为 256 个元件、1024 条连线。'],nodes,drivers,order};
  const names=new Set();
  for(const n of net.nodes) {
    if(!n || typeof n!=='object' || !validKey(n.id)) {errors.push('元件 id 必须是有效且安全的英文标识符。');continue;}
    if(nodes.has(n.id)) errors.push(`重复的元件 id：${n.id}`);
    if(!own(GATE_TYPES,n.type)) errors.push(`${n.id}：未知元件类型。`);
    if(!Number.isInteger(n.width) || n.width<1 || n.width>32) errors.push(`${n.id}：位宽必须在 1–32 之间。`);
    if(!Number.isFinite(n.x) || !Number.isFinite(n.y) || Math.abs(n.x)>10000 || Math.abs(n.y)>10000) errors.push(`${n.id}：坐标无效或超出范围。`);
    if(n.value!==undefined && n.value!==null && !Number.isSafeInteger(n.value)) errors.push(`${n.id}：值必须为整数或 null。`);
    if(n.type==='INPUT' || n.type==='OUTPUT') {
      if(!validKey(n.name)) errors.push(`${n.id}：输入 / 输出需要英文名称。`);
      else if(names.has(n.name)) errors.push(`重复的接口名称：${n.name}`);
      names.add(n.name);
    }
    nodes.set(n.id,n);
  }
  if(errors.length) return {errors,nodes,drivers,order};
  const successors=new Map([...nodes.keys()].map(id=>[id,[]]));
  const degree=new Map([...nodes.keys()].map(id=>[id,0]));
  for(const w of net.wires) {
    const a=nodes.get(w?.from?.node), b=nodes.get(w?.to?.node);
    if(!a || !b) {errors.push('连线引用了不存在的元件。');continue;}
    if(!GATE_TYPES[a.type].outputs.includes(w.from.port) || !GATE_TYPES[b.type].inputs.includes(w.to.port)) {errors.push(`${a.id} → ${b.id}：端口名称或方向无效。`);continue;}
    if(portWidth(a,w.from.port)!==portWidth(b,w.to.port)) errors.push(`${a.id} → ${b.id}：位宽不匹配。`);
    const key=`${b.id}:${w.to.port}`;
    if(drivers.has(key)) errors.push(`${b.id}.${w.to.port} 存在多个驱动。请先删除旧线。`);
    drivers.set(key,w.from);
    // A flip-flop output is already available from state; D is sampled afterwards.
    if(b.type!=='DFF') {successors.get(a.id).push(b.id);degree.set(b.id,degree.get(b.id)+1);}
  }
  const queue=[...degree].filter(([,d])=>d===0).map(([id])=>id);
  for(let i=0;i<queue.length;i++) {
    const id=queue[i]; order.push(id);
    for(const next of successors.get(id)) {degree.set(next,degree.get(next)-1);if(degree.get(next)===0) queue.push(next);}
  }
  if(order.length!==nodes.size) errors.push('检测到组合逻辑环路；反馈路径必须经过 DFF。');
  return {errors,nodes,drivers,order};
}

export function validateCircuit(netlist) {return inspect(netlist).errors;}

function run(graph,inputs={},state={}) {
  const {nodes,drivers,order,errors}=graph;
  const outputs={},values={},nextState={};
  if(errors.length) return {outputs,values,nextState,errors:[...errors]};
  const read=(id,port)=> {const source=drivers.get(`${id}:${port}`);return source ? values[source.node]?.[source.port] ?? null : null;};
  for(const id of order) {
    const n=nodes.get(id), a=read(id,'a'), b=read(id,'b'); let result=null;
    switch(n.type) {
      case 'INPUT': result=own(inputs,n.name) ? inputs[n.name] : n.value===undefined ? 0 : n.value; break;
      case 'CONST': result=n.value===undefined ? 0 : n.value; break;
      case 'DFF': result=own(state,id) ? state[id] : n.value===undefined ? 0 : n.value; break;
      case 'OUTPUT': outputs[n.name]=normalize(read(id,'in'),n.width);values[id]={};continue;
      case 'NOT': {const v=read(id,'in');result=v===null ? null : ~v;break;}
      case 'AND': case 'NAND': result=a===0 || b===0 ? 0 : a===null || b===null ? null : a&b; if(n.type==='NAND' && result!==null) result=~result;break;
      case 'OR': case 'NOR': result=a===mask(n.width) || b===mask(n.width) ? mask(n.width) : a===null || b===null ? null : a|b; if(n.type==='NOR' && result!==null) result=~result;break;
      case 'XOR': result=a===null || b===null ? null : a^b;break;
      case 'ADD': result=a===null || b===null ? null : a+b;break;
      case 'MUX': {const sel=read(id,'sel');result=sel===null ? a===b ? a : null : sel===0 ? a : b;break;}
    }
    values[id]={out:normalize(result,n.width)};
  }
  for(const [id,n] of nodes) if(n.type==='DFF') nextState[id]=normalize(read(id,'d'),n.width);
  return {outputs,values,nextState,errors:[]};
}

export function evaluateCircuit(netlist,inputs={},state={}) {return run(inspect(netlist),inputs,state);}

export function makeCustomUnit(netlist) {
  const errors=validateCircuit(netlist);
  if(errors.length) throw new Error(errors.join('\n'));
  const graph=inspect(JSON.parse(JSON.stringify(netlist)));
  const ins=[...graph.nodes.values()].filter(n=>n.type==='INPUT'), outs=[...graph.nodes.values()].filter(n=>n.type==='OUTPUT');
  if(ins.length!==2 || outs.length!==1 || !ins.some(n=>n.name==='A' && n.width===32) || !ins.some(n=>n.name==='B' && n.width===32) || outs[0].name!=='Y' || outs[0].width!==32)
    throw new Error('CUSTOM 接口必须恰好为 32 位输入 A、B 和 32 位输出 Y。');
  if([...graph.nodes.values()].some(n=>n.type==='DFF')) throw new Error('CUSTOM 仅支持组合电路，不能含 DFF。');
  // Refuse incomplete graphs even when a controlling value could mask an open port.
  for(const [id,n] of graph.nodes) for(const p of GATE_TYPES[n.type].inputs) if(!graph.drivers.has(`${id}:${p}`)) throw new Error(`${id}.${p} 尚未接线，不能装入 CUSTOM。`);
  const custom=(a,b)=> {
    const result=run(graph,{A:a>>>0,B:b>>>0});
    if(result.outputs.Y===null) throw new Error('CUSTOM 输出未知；检查输入和连线。');
    return result.outputs.Y>>>0;
  };
  custom(0,0);
  return custom;
}

export function fullAdder(a,b,cin) {a&=1;b&=1;cin&=1;const axb=a^b;return {sum:axb^cin,carry:(a&b)|(axb&cin)};}
export function rippleAdd(a,b,width=32) {
  if(!Number.isInteger(width) || width<1 || width>32) throw new Error('位宽必须为 1–32。');
  const bits=[];let carry=0,value=0;
  for(let i=0;i<width;i++) {const ai=(a>>>i)&1,bi=(b>>>i)&1,cin=carry,result=fullAdder(ai,bi,cin);carry=result.carry;value+=result.sum*2**i;bits.push({a:ai,b:bi,cin,...result});}
  return {value:value>>>0,bits};
}

const n=(id,type,width,x,y,extra={})=>({id,type,width,x,y,...extra});
const w=(from,to,port='a')=>({from:{node:from,port:'out'},to:{node:to,port}});
const busPreset=type=>({nodes:[n('a','INPUT',32,55,100,{name:'A',value:7}),n('b','INPUT',32,55,285,{name:'B',value:5}),n('op',type,32,400,190),n('y','OUTPUT',32,760,190,{name:'Y'})],wires:[w('a','op'),w('b','op','b'),w('op','y','in')]});
export const PRESETS=[
  {id:'add32',name:'32 位加法器',description:'A + B → Y，可装入 CPU 的 CUSTOM 指令。',netlist:busPreset('ADD')},
  {id:'xor32',name:'32 位异或器',description:'A XOR B → Y。装入后，同一段程序会产生不同结果。',netlist:busPreset('XOR')},
  {id:'nand',name:'与非门入门',description:'点击输入的 0 / 1 开关，观察 NAND 的真值表。',netlist:{nodes:[n('a','INPUT',1,55,100,{name:'A',value:1}),n('b','INPUT',1,55,285,{name:'B',value:1}),n('g','NAND',1,400,190),n('y','OUTPUT',1,760,190,{name:'Y'})],wires:[w('a','g'),w('b','g','b'),w('g','y','in')]}},
  {id:'fulladder',name:'1 位全加器',description:'两个 XOR、两个 AND、一个 OR；Cin 是前一位的进位。',netlist:{nodes:[n('a','INPUT',1,30,55,{name:'A',value:1}),n('b','INPUT',1,30,230,{name:'B',value:1}),n('c','INPUT',1,30,410,{name:'Cin',value:0}),n('x1','XOR',1,260,75),n('x2','XOR',1,515,65),n('g1','AND',1,260,255),n('g2','AND',1,515,275),n('o','OR',1,750,325),n('s','OUTPUT',1,990,65,{name:'Sum'}),n('cy','OUTPUT',1,990,325,{name:'Carry'})],wires:[w('a','x1'),w('b','x1','b'),w('x1','x2'),w('c','x2','b'),w('a','g1'),w('b','g1','b'),w('x1','g2'),w('c','g2','b'),w('g1','o'),w('g2','o','b'),w('x2','s','in'),w('o','cy','in')]}},
  {id:'dff',name:'时钟与反馈',description:'Q 经非门反馈到 D。每次时钟上升沿，Q 翻转一次。',netlist:{nodes:[n('q','DFF',1,180,160),n('n','NOT',1,490,160),n('y','OUTPUT',1,800,160,{name:'Y'})],wires:[w('q','n','in'),w('n','q','d'),w('q','y','in')]}},
  {id:'challenge',name:'空白接线挑战',description:'从元件库添加逻辑门，完成 A、B → Y 的异或真值表。',netlist:{nodes:[n('a','INPUT',1,55,100,{name:'A',value:0}),n('b','INPUT',1,55,285,{name:'B',value:0}),n('y','OUTPUT',1,760,190,{name:'Y'})],wires:[]}},
];
