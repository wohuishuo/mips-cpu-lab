import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = new URL('../../', import.meta.url);
const read = p => readFileSync(new URL(p, root), 'utf8').replace(/\r\n/g,'\n');
const data = () => JSON.parse(read('docs/lab/data/project.json'));
test('source bundle matches repository text with normalized line endings and all chapter ranges exist', () => {
 const d=data(); assert.equal(d.schema,1);
 for(const [path,s] of Object.entries(d.sources)) {
  assert.equal(s.path,path); assert.equal(s.text,read(path));
  assert.equal(s.sha256,createHash('sha256').update(read(path)).digest('hex'));
 }
 assert.deepEqual(d.chapters.map(c=>c.id),['board','lab1','lab3','pipeline','lab5','exceptions','lab7','uart']);
 for(const c of d.chapters) {
  for(const k of ['title','kicker','question','intro','limits']) assert.ok(c[k]?.length,`${c.id}.${k}`);
  assert.ok(c.steps.length>=3&&c.steps.length<=5);
  for(const s of c.steps){ assert.ok(d.sources[s.path]); assert.ok(Number.isInteger(s.start)&&s.start>0); assert.ok(s.end>=s.start&&s.end<=read(s.path).split('\n').length); }
  assert.ok(c.evidence.length);
  for(const e of c.evidence){ assert.ok(e.label&&e.value); assert.ok(['physical-board','rtl-simulation','principle-demo','documentation'].includes(e.kind)); assert.ok(existsSync(fileURLToPath(new URL(e.path,root)))); }
 }
 for(const p of ['software/board_demo.S','rtl/core/single_cycle_cpu.v','rtl/core/pipeline_cpu.v','rtl/soc/lab_soc.v','rtl/soc/ees338_top.v','rtl/core/cp0.v','rtl/cache/data_cache.v','rtl/peripherals/uart_control.v','rtl/integration/lab1_num_led.v','rtl/integration/lab3_mycpu.v','tests/run_teach_soc.py','tests/pipeline_reference.py']) assert.ok(d.sources[p],p);
});
test('evidence is copied exactly and CSV retains every hexadecimal cell',()=>{
 const d=data();
 for(const [key,path] of Object.entries({board:'evidence/board.json',results:'evidence/results.json',course:'evidence/course_basics.json'})) assert.deepEqual(d[key],JSON.parse(read(path)));
 assert.deepEqual(d.telemetry,read('evidence/live-telemetry.jsonl').trim().split(/\r?\n/).map(JSON.parse));
 const [header,...lines]=read('evidence/pipeline-stages.csv').trim().split(/\r?\n/); const keys=header.split(',');
 assert.equal(d.pipeline.length,lines.length);
 lines.forEach((line,i)=>line.split(',').forEach((cell,j)=>assert.equal(d.pipeline[i][keys[j]], /_(pc|instr)$/.test(keys[j])?cell:Number(cell))));
 assert.deepEqual([...new Set(d.pipeline.map(r=>r.mode))].sort(),[0,1,2]);
 assert.equal(d.course.passes.length,6); assert.equal(d.results.tests.length,11);
 assert.ok(d.chapters.find(c=>c.id==='lab5').limits.includes('89'));
 for(const id of ['pipeline','lab7']) assert.ok(d.chapters.find(c=>c.id===id).limits.includes('下板'));
 assert.equal(d.board.records[0].fibonacci,89); assert.equal(d.board.records[0].display,0x00810059);
});
