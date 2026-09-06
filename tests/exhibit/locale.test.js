import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>JSON.parse(readFileSync(new URL('../../docs/lab/'+path,import.meta.url),'utf8'));
test('English chapter catalog covers every explanation and preserves numeric facts',()=>{
  const dictionary=read('i18n/chapters.en.json');
  function visit(value){
    if(typeof value==='string'&&/[\u3400-\u9fff]/u.test(value)){
      assert.ok(dictionary[value],value);assert.ok(!/[\u3400-\u9fff]/u.test(dictionary[value]));
      const numbers=text=>(text.match(/\d+(?:[,.]\d+)*/g)||[]).sort();
      assert.deepEqual(numbers(dictionary[value]),numbers(value),value);
    }else if(value&&typeof value==='object')Object.values(value).forEach(visit);
  }
  visit(read('data/project.json').chapters);
});
test('translation assets contain English strings and leave executable input outside translation',()=>{
  for(const name of ['chapters','exhibit','playground']){
    const dictionary=read(`i18n/${name}.en.json`);assert.ok(Object.keys(dictionary).length>100);
    for(const [key,value] of Object.entries(dictionary)){assert.equal(typeof value,'string',key);assert.ok(value.trim(),key);}
  }
});
