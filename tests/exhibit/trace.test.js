import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const root=new URL('../../',import.meta.url);
const trace=JSON.parse(readFileSync(new URL('docs/lab/data/board-trace.json',root),'utf8'));
test('board recording uses current RTL and reproduces every architectural transition',()=>{
  assert.equal(trace.kind,'rtl-simulation');
  for(const path of trace.sourcePaths){
    const text=readFileSync(new URL(path,root),'utf8').replace(/\r\n/g,'\n');
    assert.equal(createHash('sha256').update(text).digest('hex'),trace.sourceCanonicalSha256[path],path);
  }
  const registers=Array(32).fill(0),ram=Array(12).fill(null),stores=[];
  assert.equal(trace.rows.length,160);
  trace.rows.forEach((row,i)=>{
    assert.equal(row.cycle,i+1);
    if(row.regWrite&&row.rd)registers[row.rd]=row.value;
    if(row.memWrite&&row.address>=0x10010000&&row.address<0x10010030){
      assert.equal(row.address%4,0);ram[(row.address-0x10010000)/4]=row.storeValue;stores.push(row.storeValue);
    }
    assert.deepEqual(row.registers,registers,`registers at cycle ${row.cycle}`);
    assert.deepEqual(row.ram,ram,`RAM at cycle ${row.cycle}`);
  });
  assert.deepEqual(stores,[0,1,1,2,3,5,8,13,21,34,55,89]);
  assert.equal(trace.rows.at(-1).display,0x00810059);
  assert.equal(trace.rows.at(-1).led,0xd8);
  assert.equal(trace.rows.at(-1).done,true);
});
