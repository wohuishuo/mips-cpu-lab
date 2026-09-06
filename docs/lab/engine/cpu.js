/** Browser teaching model: all 44 ordinary instructions in single-cycle.md.
 * ADD/ADDI/SUB report overflow (pipeline semantics). Errors stop execution;
 * no CP0, trap vectors, interrupts, HI/LO, multiply/divide or unaligned merges.
 * CUSTOM and HALT are browser extensions, not claims about the RTL.
 * Stage snapshots describe latches AFTER the clock edge; WB commits next edge.
 */
const NAMES = 'zero at v0 v1 a0 a1 a2 a3 t0 t1 t2 t3 t4 t5 t6 t7 s0 s1 s2 s3 s4 s5 s6 s7 t8 t9 k0 k1 gp sp fp ra'.split(' ');
const RF = {add:32,addu:33,sub:34,subu:35,and:36,or:37,xor:38,nor:39,slt:42,sltu:43};
const SHIFT = {sll:0,srl:2,sra:3,sllv:4,srlv:6,srav:7};
const IMM = {addi:8,addiu:9,slti:10,sltiu:11,andi:12,ori:13,xori:14,lui:15};
const MEM = {lb:32,lh:33,lw:35,lbu:36,lhu:37,sb:40,sh:41,sw:43};
const BRANCH = {beq:4,bne:5,blez:6,bgtz:7,bltz:1,bgez:1,bltzal:1,bgezal:1};
const REGIMM = {bltz:0,bgez:1,bltzal:16,bgezal:17};
const own = (o,k) => Object.prototype.hasOwnProperty.call(o,k);
const clone = o => JSON.parse(JSON.stringify(o));
const isLoad = i => i && ['lb','lbu','lh','lhu','lw'].includes(i.op);
const isMemory = i => i && own(MEM,i.op);
const isControl = i => i && (own(BRANCH,i.op) || ['j','jal','jr','jalr'].includes(i.op));
function fail(line,message) { throw new Error(`第 ${line} 行：${message}`); }
function number(token,line) {
  if (!/^[+-]?(?:0x[\da-f]+|\d+)$/i.test(token ?? '')) fail(line,`无效数字 ${token}`);
  const sign=token.startsWith('-')?-1:1;
  const value=sign*Number(token.replace(/^[+-]/,''));
  if (!Number.isSafeInteger(value)) fail(line,'数字超出安全范围');
  return value;
}
function register(token,line) {
  if (!/^\$/.test(token??'')) fail(line,`无效寄存器 ${token}`);
  const key=token.slice(1).toLowerCase();
  const value=/^\d+$/.test(key)?Number(key):key==='s8'?30:NAMES.indexOf(key);
  if(value<0||value>31) fail(line,`无效寄存器 ${token}`);
  return value;
}
function immediate(token,line,unsigned=false) {
  let n=number(token,line);
  if(!unsigned && /^\+?0x/i.test(token) && n>=32768 && n<=65535) n-=65536;
  if(n<(unsigned?0:-32768)||n>(unsigned?65535:32767)) fail(line,'立即数超出 16 位范围');
  return n;
}

export function assemble(source) {
  if(typeof source!=='string') throw new Error('第 1 行：程序必须是文本');
  const labels={}; const rows=[]; let pc=0;
  for(const [index,raw] of source.split(/\r?\n/).entries()) {
    const line=index+1; let text=raw.replace(/#.*$|;.*$|\/\/.*$/,'').trim();
    let match;
    while((match=text.match(/^([A-Za-z_][\w]*):/))) {
      if(own(labels,match[1])) fail(line,`重复标签 ${match[1]}`);
      Object.defineProperty(labels,match[1],{value:pc,enumerable:true,writable:true,configurable:true});
      text=text.slice(match[0].length).trim();
    }
    if(!text||/^\.(text|globl|global)(?:\s|$)/i.test(text)) continue;
    const parts=text.match(/^(\S+)(?:\s+(.*))?$/); const op=parts[1].toLowerCase();
    const args=parts[2]?parts[2].split(',').map(x=>x.trim()):[];
    if(args.some(x=>!x))fail(line,'操作数不能为空');
    const row={pc,op,args,text,line};
    if(op==='li') {
      if(args.length!==2) fail(line,'li 需要两个操作数');
      register(args[0],line); const n=number(args[1],line);
      if(n< -2147483648||n>4294967295) fail(line,'li 超出 32 位范围');
      if(n>=-32768&&n<=32767) rows.push({...row,op:'addiu',args:[args[0],'$zero',String(n)]});
      else if(n>=0&&n<=65535) rows.push({...row,op:'ori',args:[args[0],'$zero',String(n)]});
      else {
        rows.push({...row,op:'lui',args:[args[0],String(n>>>16)]}); pc+=4;
        rows.push({...row,pc,op:'ori',args:[args[0],args[0],String(n&65535)]});
      }
    } else if(op==='move') {
      if(args.length!==2) fail(line,'move 需要两个操作数');
      rows.push({...row,op:'addu',args:[args[0],args[1],'$zero']});
    } else rows.push(row);
    pc+=4;
    if(rows.length>16384) fail(line,'程序过长（最多 16384 条）');
  }
  const instructions=rows.map(row=>{
    const {op,args:a,line,pc}=row; const i={pc,word:0,op,text:row.text,line,rs:0,rt:0,rd:0,imm:0,reads:[],dest:0};
    const count=n=>{if(a.length!==n)fail(line,`${op} 需要 ${n} 个操作数`);};
    const reg=k=>register(a[k],line);
    const rword=fn=>(i.rs<<21)|(i.rt<<16)|(i.rd<<11)|((i.shamt??0)<<6)|fn;
    if(own(RF,op)||op==='custom') {
      count(3); i.rd=reg(0);i.rs=reg(1);i.rt=reg(2);i.dest=i.rd;i.reads=[i.rs,i.rt];
      i.word=op==='custom'?(0x70000000|rword(63)):rword(RF[op]);
    } else if(own(SHIFT,op)) {
      count(3);i.rd=reg(0);i.rt=reg(1);i.dest=i.rd;
      if(op.endsWith('v')){i.rs=reg(2);i.reads=[i.rs,i.rt];}
      else {i.shamt=number(a[2],line);if(i.shamt<0||i.shamt>31)fail(line,'移位量必须在 0–31');i.reads=[i.rt];}
      i.word=rword(SHIFT[op]);
    } else if(own(IMM,op)) {
      count(op==='lui'?2:3);i.rt=reg(0);i.dest=i.rt;
      if(op!=='lui'){i.rs=reg(1);i.reads=[i.rs];}
      i.imm=immediate(a[op==='lui'?1:2],line,['andi','ori','xori','lui'].includes(op));
      i.word=(IMM[op]<<26)|(i.rs<<21)|(i.rt<<16)|(i.imm&65535);
    } else if(own(MEM,op)) {
      count(2);i.rt=reg(0);const m=a[1].match(/^([^()]*)\(\s*(\$\w+)\s*\)$/);
      if(!m)fail(line,'内存操作数格式为 偏移($寄存器)');
      i.rs=register(m[2],line);i.imm=immediate(m[1].trim()||'0',line);i.reads=[i.rs];
      if(isLoad(i))i.dest=i.rt;else i.reads.push(i.rt);
      i.word=(MEM[op]<<26)|(i.rs<<21)|(i.rt<<16)|(i.imm&65535);
    } else if(own(BRANCH,op)) {
      const pair=op==='beq'||op==='bne';count(pair?3:2);i.rs=reg(0);i.reads=[i.rs];
      if(pair){i.rt=reg(1);i.reads.push(i.rt);}else i.rt=REGIMM[op]??0;
      const token=a[pair?2:1];
      i.imm=own(labels,token)?(labels[token]-pc-4)/4:immediate(token,line);
      if(!Number.isInteger(i.imm)||i.imm< -32768||i.imm>32767)fail(line,'分支目标超出范围');
      i.target=(pc+4+i.imm*4)>>>0;
      if(op.endsWith('al'))i.dest=31;
      i.word=(BRANCH[op]<<26)|(i.rs<<21)|(i.rt<<16)|(i.imm&65535);
    } else if(op==='j'||op==='jal') {
      count(1);i.target=own(labels,a[0])?labels[a[0]]:number(a[0],line);
      if(i.target<0||i.target>0xffffffff||i.target%4||((i.target>>>28)!==((pc+4)>>>28)))fail(line,'跳转地址必须对齐并位于同一 256 MB 区域');
      if(op==='jal')i.dest=31;
      i.word=((op==='j'?2:3)<<26)|((i.target>>>2)&0x3ffffff);
    } else if(op==='jr'||op==='jalr') {
      if(op==='jr'){count(1);i.rs=reg(0);}
      else if(a.length===1){i.rd=31;i.rs=reg(0);i.dest=31;}
      else {count(2);i.rd=reg(0);i.rs=reg(1);i.dest=i.rd;}
      i.reads=[i.rs];i.word=rword(op==='jr'?8:9);
    } else if(op==='nop'||op==='halt') {count(0);i.word=op==='halt'?0xfc000000:0;}
    else fail(line,`不支持指令 ${op}（无 CP0 / HI-LO 模拟）`);
    i.word>>>=0;return i;
  });
  return {instructions,labels};
}

export class PipelineCPU {
  constructor(program,{inputA=7,inputB=5,waitCycles=0,custom=(a,b)=>(a+b)>>>0}={}) {
    const instructions=Array.isArray(program)?program:program?.instructions;
    if(!Array.isArray(instructions))throw new Error('程序必须由 assemble 生成');
    if(!Number.isInteger(waitCycles)||waitCycles<0||waitCycles>1000)throw new Error('内存等待周期必须在 0–1000');
    if(typeof custom!=='function')throw new Error('CUSTOM 必须是函数');
    this.program=clone(instructions);this.custom=custom;
    const registers=Array(32).fill(0);registers[4]=inputA>>>0;registers[5]=inputB>>>0;
    this.state={cycle:0,pc:0,halted:false,registers,memory:Array(256).fill(0),stages:{IF:null,ID:null,EX:null,MEM:null,WB:null},events:[],writes:{registers:[],memory:[]},retired:0,customTrace:null,waitCycles,fetchStopped:false,nextId:1};
  }
  snapshot(){return clone(this.state);}
  restore(snapshot){this.state=clone(snapshot);return this.snapshot();}
  operand(reg,mem,wb) {
    if(!reg)return 0;
    for(const [stage,i] of [['MEM',mem],['WB',wb]]) {
      if(i?.dest===reg && i.result!==undefined) {
        this.state.events.push(`转发 ${stage} → EX：$${NAMES[reg]}`);return i.result>>>0;
      }
    }
    return this.state.registers[reg]>>>0;
  }
  execute(i,mem,wb) {
    const s=this.state;
    const a=i.reads.includes(i.rs)?this.operand(i.rs,mem,wb):0;
    const b=i.reads.includes(i.rt)?this.operand(i.rt,mem,wb):0;
    const imm=i.imm;let result;let target;
    i.a=a;i.b=b;
    switch(i.op) {
      case 'add': result=(a|0)+(b|0);break;
      case 'addi': result=(a|0)+imm;break;
      case 'sub': result=(a|0)-(b|0);break;
      case 'addu':result=a+b;break;case 'addiu':result=a+imm;break;
      case 'subu':result=a-b;break;
      case 'and':result=a&b;break;case 'or':result=a|b;break;
      case 'xor':result=a^b;break;case 'nor':result=~(a|b);break;
      case 'andi':result=a&imm;break;case 'ori':result=a|imm;break;case 'xori':result=a^imm;break;
      case 'lui':result=imm<<16;break;
      case 'slt':result=Number((a|0)<(b|0));break;case 'sltu':result=Number(a<b);break;
      case 'slti':result=Number((a|0)<imm);break;case 'sltiu':result=Number(a<(imm>>>0));break;
      case 'sll':result=b<<i.shamt;break;case 'srl':result=b>>>i.shamt;break;case 'sra':result=(b|0)>>i.shamt;break;
      case 'sllv':result=b<<(a&31);break;case 'srlv':result=b>>>(a&31);break;case 'srav':result=(b|0)>>(a&31);break;
      case 'custom':
        result=this.custom(a,b);
        if(!Number.isFinite(result)||!Number.isInteger(result))fail(i.line,'CUSTOM 输出必须是整数');
        s.customTrace={a,b,y:result>>>0};s.events.push(`CUSTOM：${a} 和 ${b} → ${result>>>0}`);break;
      case 'j':case 'jal':target=i.target;break;
      case 'jr':case 'jalr':target=a;break;
      case 'beq':target=a===b?i.target:i.pc+8;break;
      case 'bne':target=a!==b?i.target:i.pc+8;break;
      case 'blez':target=(a|0)<=0?i.target:i.pc+8;break;
      case 'bgtz':target=(a|0)>0?i.target:i.pc+8;break;
      case 'bltz':case 'bltzal':target=(a|0)<0?i.target:i.pc+8;break;
      case 'bgez':case 'bgezal':target=(a|0)>=0?i.target:i.pc+8;break;
    }
    if(['add','addi','sub'].includes(i.op)&&(result< -2147483648||result>2147483647))fail(i.line,'有符号算术溢出');
    if(isMemory(i)) {
      i.address=(a+imm)>>>0;i.storeValue=b;i.size=i.op.endsWith('w')?4:i.op.includes('h')?2:1;
      if(i.address%i.size)fail(i.line,`内存地址 ${i.address} 未按 ${i.size} 字节对齐`);
      if(i.address+i.size>s.memory.length)fail(i.line,`内存地址 ${i.address} 超出范围`);
      i.waitRemaining=s.waitCycles;
    }
    if(isControl(i)) {
      if(i.delaySlot)fail(i.line,'延迟槽中不允许控制转移');
      this.checkPC(target,i.line);
      if(i.dest)result=i.pc+8;
      i.redirect=target>>>0;
    }
    if(result!==undefined)i.result=result>>>0;
    return i;
  }
  checkPC(pc,line=1) {
    if(!Number.isInteger(pc)||pc<0||pc%4)fail(line,`取指地址 ${pc} 未对齐`);
    if(pc>this.program.length*4)fail(line,`取指地址 ${pc} 超出程序范围`);
  }
  step() {
    const s=this.state;if(s.halted)return this.snapshot();
    s.cycle++;s.events=[];s.writes={registers:[],memory:[]};
    const old=s.stages;
    try {
      // WB always drains, including while a younger memory request is waiting.
      if(old.WB) {
        if(old.WB.dest) {s.registers[old.WB.dest]=old.WB.result>>>0;s.writes.registers.push(old.WB.dest);}
        s.retired++;s.events.push(`提交 PC 0x${old.WB.pc.toString(16)}：${old.WB.op}`);
      }
      s.registers[0]=0;
      if(isMemory(old.MEM)&&old.MEM.waitRemaining>0) {
        old.MEM.waitRemaining--;s.stages={...old,WB:null};
        s.events.push(`内存等待：剩余 ${old.MEM.waitRemaining} 周期（上游保持）`);
        return this.snapshot();
      }
      if(isMemory(old.MEM)) {
        const i=old.MEM;
        if(isLoad(i)) {
          let value=0;for(let n=0;n<i.size;n++)value|=s.memory[i.address+n]<<(8*n);
          if(i.op==='lb')value=(value<<24)>>24;if(i.op==='lh')value=(value<<16)>>16;
          i.result=value>>>0;s.events.push(`读取 RAM[${i.address}] → ${i.result}`);
        } else {
          for(let n=0;n<i.size;n++){s.memory[i.address+n]=(i.storeValue>>>(8*n))&255;s.writes.memory.push(i.address+n);}
          s.events.push(`写入 RAM[${i.address}]：${i.storeValue}`);
        }
      }
      const executed=old.EX?this.execute({...old.EX},old.MEM,old.WB):null;
      const next={IF:null,ID:null,EX:null,MEM:executed,WB:old.MEM};
      const hazard=isLoad(old.EX)&&old.EX.dest&&old.ID?.reads.includes(old.EX.dest);
      if(executed?.op==='halt') {
        s.fetchStopped=true;s.events.push('HALT：停止取指，排空流水线');
      } else if(executed?.redirect!==undefined) {
        next.EX=old.ID?{...old.ID,delaySlot:true}:null;
        s.pc=executed.redirect;s.events.push(`分支：保留一个延迟槽，PC → 0x${s.pc.toString(16)}`);
      } else if(hazard) {
        next.ID=old.ID;next.IF=old.IF;
        s.events.push('加载使用 load-use：ID / IF 停顿，EX 插入气泡');
      } else {next.EX=old.ID;next.ID=old.IF;}
      if(!hazard&&!s.fetchStopped) {
        this.checkPC(s.pc);
        if(s.pc<this.program.length*4){next.IF={...this.program[s.pc/4],id:s.nextId++};s.pc+=4;}
      }
      s.stages=next;
      if(Object.values(next).every(i=>i===null)&&(s.fetchStopped||s.pc===this.program.length*4))s.halted=true;
      return this.snapshot();
    } catch(error) {
      s.halted=true;s.error=error.message;s.events.push(error.message);
      throw error;
    }
  }
}
