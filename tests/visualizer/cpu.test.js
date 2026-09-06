import test from 'node:test';
import assert from 'node:assert/strict';
import {assemble, PipelineCPU} from '../../docs/lab/engine/cpu.js';

function run(source, options = {}) {
  const cpu = new PipelineCPU(assemble(source), options);
  const history = [cpu.snapshot()];
  for (let n = 0; n < 500 && !cpu.snapshot().halted; n++) history.push(cpu.step());
  assert.equal(cpu.snapshot().halted, true, 'program must terminate');
  return {cpu, history, end: cpu.snapshot()};
}

test('assembler expands full-width li, resolves label PC and emits MIPS words', () => {
  const p = assemble('.text\n.globl main\nmain: li $t0, 0x12345678 # value\nmove $t1,$t0\nbeq $t0,$t1,end\nnop\nend: halt');
  assert.deepEqual(p.instructions.slice(0, 4).map(i => i.word), [0x3c081234, 0x35085678, 0x01004821, 0x11090001]);
  assert.equal(p.labels.end, 20);
  assert.equal(p.instructions[0].line, 3);
  for (const source of ['add $bad,$0,$0','addi $1,$0,32768','sll $1,$2,32','beq $0,$0,missing','foo: nop\nfoo: halt','mfc0 $2,$12']) assert.throws(() => assemble(source), /行|line/i);
});

test('five stages, register zero, EX forwarding and custom operand trace', () => {
  const {history,end} = run('addiu $t0,$a0,1\ncustom $t1,$t0,$a1\naddu $t2,$t1,$t1\naddu $zero,$t2,$t2\nhalt', {custom:(a,b)=>a^b});
  assert.equal(end.registers[8],8); assert.equal(end.registers[9],13); assert.equal(end.registers[10],26); assert.equal(end.registers[0],0);
  assert.deepEqual(end.customTrace,{a:8,b:5,y:13});
  assert.ok(history.some(s => s.stages.IF && s.stages.ID && s.stages.EX && s.stages.MEM && s.stages.WB));
  assert.ok(history.some(s => s.events.some(e => /转发|forward/i.test(e))));
  assert.equal(end.retired,5);
  assert.deepEqual(history.find(s=>s.stages.WB?.pc===0).registers[8],0);
});

test('load-use interlock costs one cycle and store forwards loaded data', () => {
  const a = run('addiu $8,$0,27\nsw $8,0($0)\nlw $9,0($0)\naddu $10,$9,$9\nsw $10,4($0)\nhalt');
  const b = run('addiu $8,$0,27\nsw $8,0($0)\nlw $9,0($0)\nnop\naddu $10,$9,$9\nsw $10,4($0)\nhalt');
  assert.equal(a.end.registers[10],54); assert.equal(a.end.memory[4],54);
  assert.equal(a.end.cycle,b.end.cycle);
  assert.equal(a.history.filter(s=>s.events.some(e=>/load.use|加载使用/i.test(e))).length,1);
});

test('memory backpressure adds exact cycles without repeating retirement or custom execution', () => {
  const source = 'custom $8,$a0,$a1\nsw $8,0($0)\nlw $9,0($0)\ncustom $10,$9,$a1\nhalt';
  const a = run(source);
  let calls=0;
  const b=run(source,{waitCycles:3,custom:(a,b)=>{calls++; return a+b;}});
  assert.equal(b.end.cycle,a.end.cycle+6); assert.equal(b.end.retired,5); assert.equal(calls,2);
  assert.equal(b.end.registers[10],17);
  assert.equal(b.history.filter(s=>s.writes.memory.length).length,1);
});

test('taken and untaken branches execute one delay slot, link even untaken, halt drains', () => {
  const {end}=run('addiu $8,$0,1\nbeq $8,$8,target\naddiu $9,$0,9\nsw $8,40($0)\ntarget: bltzal $8,wrong\nmove $10,$ra\nbne $8,$8,wrong\naddiu $11,$0,11\nhalt\nwrong: sw $8,44($0)');
  assert.equal(end.registers[9],9); assert.equal(end.registers[10],24); assert.equal(end.registers[11],11);
  assert.equal(end.memory[40],0); assert.equal(end.memory[44],0); assert.equal(end.retired,8);
});

test('backward branches and jalr source equals destination preserve PC+8 semantics', () => {
  const {end}=run('li $8,3\nloop: addiu $8,$8,-1\nbgtz $8,loop\naddiu $9,$9,1\nli $10,28\njalr $10,$10\nmove $11,$10\nhalt');
  assert.equal(end.registers[8],0); assert.equal(end.registers[9],3); assert.equal(end.registers[10],28); assert.equal(end.registers[11],28);
});

test('little endian signed and unsigned byte/half access and boundaries', () => {
  const {end}=run('li $8,0x80ff81fe\nsw $8,252($0)\nlb $9,255($0)\nlbu $10,255($0)\nlh $11,252($0)\nlhu $12,252($0)\nsb $8,0($0)\nsh $8,2($0)\nhalt');
  assert.deepEqual(end.memory.slice(252),[254,129,255,128]);
  assert.deepEqual(end.registers.slice(9,13),[0xffffff80,128,0xffff81fe,0x81fe]);
  assert.deepEqual(end.memory.slice(0,4),[254,0,254,129]);
  for(const source of ['lw $8,1($0)','sh $8,255($0)','sw $8,256($0)','lw $8,-4($0)','li $8,3\njr $8\nnop','j next\nj next\nnext: halt']) assert.throws(()=>run(source),/对齐|范围|地址|延迟/);
});

test('arithmetic, logic, comparison and shifts retain signed/unsigned semantics', () => {
  const {end}=run('li $8,-1\nli $9,1\nsltiu $10,$9,-1\nslt $11,$8,$9\nsltu $12,$8,$9\nsra $13,$8,3\nsrl $14,$8,31\nsllv $15,$9,$8\nsrav $16,$8,$9\nsrlv $17,$8,$9\nnor $18,$8,$9\nandi $19,$8,0xff\nxori $20,$19,0xaa\nori $21,$20,0x100\nsubu $22,$9,$19\nslti $23,$8,0\nhalt');
  assert.deepEqual(end.registers.slice(10,24),[1,1,0,0xffffffff,1,0x80000000,0xffffffff,0x7fffffff,0,255,85,341,0xffffff02,1]);
  assert.throws(()=>run('li $8,0x7fffffff\naddi $9,$8,1'),/溢出/);
});

test('snapshots are detached and restore exact in-flight wait/hazard/redirect state', () => {
  const cpu=new PipelineCPU(assemble('custom $8,$a0,$a1\nsw $8,0($0)\nlw $9,0($0)\nbeq $9,$8,end\naddiu $10,$9,1\nli $10,99\nend: halt'),{waitCycles:2,custom:(a,b)=>a*b});
  for(let i=0;i<9;i++)cpu.step();
  const saved=cpu.snapshot(); const expected=[];
  while(!cpu.snapshot().halted)expected.push(cpu.step());
  cpu.restore(JSON.parse(JSON.stringify(saved)));
  const actual=[]; while(!cpu.snapshot().halted)actual.push(cpu.step());
  assert.deepEqual(actual,expected); assert.equal(cpu.snapshot().registers[10],36);
  saved.registers[4]=999; saved.memory[0]=123;
  assert.equal(cpu.snapshot().registers[4],7); assert.equal(cpu.snapshot().memory[0],35);
});

test('each dynamic loop iteration has a distinct id and halt is idempotent', () => {
  const {cpu,history,end}=run('li $8,2\nloop: addiu $8,$8,-1\nbgtz $8,loop\nnop\nhalt');
  const ids=history.filter(s=>s.stages.WB?.pc===4).map(s=>s.stages.WB.id);
  assert.equal(ids.length,2);assert.ok(ids.every(Number.isInteger));assert.notEqual(ids[0],ids[1]);
  assert.deepEqual(cpu.step(),end);assert.ok(Object.values(end.stages).every(i=>i===null));
});

test('assembler rejects omitted operands instead of shifting later operands', () => {
  assert.throws(()=>assemble('addu $1,,$2,$3'),/行/);
  assert.throws(()=>assemble('nop,'),/行/);
});

test('remaining arithmetic and control instructions execute with exact delay slots', () => {
  const {end}=run('li $8,6\nli $9,3\nadd $10,$8,$9\nsub $11,$8,$9\nand $12,$8,$9\nor $13,$8,$9\nxor $14,$8,$9\nsll $15,$9,2\nj go\naddi $16,$0,1\nli $16,99\ngo: jal subroutine\naddiu $17,$ra,0\nhalt\nsubroutine: blez $zero,a\naddiu $18,$18,1\nli $18,99\na: bgez $zero,b\naddiu $18,$18,1\nli $18,99\nb: bltz $zero,c\naddiu $18,$18,1\nbgezal $zero,c\naddiu $19,$ra,0\nli $18,99\nc: jr $17\naddiu $18,$18,1');
  assert.deepEqual(end.registers.slice(10,20),[9,3,2,7,5,12,1,52,4,96]);
});
