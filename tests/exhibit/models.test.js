import test from 'node:test';
import assert from 'node:assert/strict';
import {DisplayLab,CacheLab} from '../../docs/lab/exhibit-models.js';
test('display lab writes four bytes in order and scans paired nibbles',()=>{
  const lab=new DisplayLab();for(const value of [0x12,0x34,0x56,0x78])lab.capture(value);
  assert.equal(lab.value,0x78563412);assert.equal(lab.byte,0);
  assert.deepEqual(lab.scan(0),{digits:0x11,low:2,high:6,segments0:0b1101101,segments1:0b1011111});
  lab.capture(0xff);assert.equal(lab.value,0x785634ff);
});
test('two-way cache distinguishes hit, conflict and dirty writeback',()=>{
  const cache=new CacheLab();assert.equal(cache.access(0).kind,'miss');
  assert.equal(cache.access(0,99).kind,'hit');assert.equal(cache.backing.get(0)||0,0);
  cache.access(256);const result=cache.access(512);assert.equal(result.kind,'writeback');
  assert.equal(cache.backing.get(0),99);assert.equal(cache.writebacks,1);
  assert.equal(cache.access(0).value,99);assert.equal(cache.hits,1);assert.equal(cache.misses,4);
  assert.throws(()=>cache.access(1),/对齐/);
});
