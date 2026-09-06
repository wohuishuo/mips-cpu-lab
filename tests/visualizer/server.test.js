import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

test('local launcher serves entry and modules while keeping requests inside docs',async()=>{
  const child=spawn(process.execPath,[fileURLToPath(new URL('../../tools/serve-lab.mjs',import.meta.url))],{env:{...process.env,PORT:'0'},stdio:['ignore','pipe','pipe'],windowsHide:true});
  try{
    const url=await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('Local server did not start')),8000);
      child.once('error',error=>{clearTimeout(timeout);reject(error);});
      child.once('exit',code=>{clearTimeout(timeout);reject(new Error(`Server exited ${code}`));});
      child.stdout.on('data',data=>{const match=String(data).match(/http:\/\/127\.0\.0\.1:\d+/);if(match){clearTimeout(timeout);resolve(match[0]);}});
    });
    const entry=await fetch(url+'/');assert.equal(entry.status,200);assert.match(await entry.text(),/CPU 工坊/);
    const module=await fetch(url+'/lab/engine/cpu.js');assert.equal(module.status,200);assert.match(module.headers.get('content-type'),/javascript/);
    const escape=await fetch(url+'/%2e%2e%2fREADME.md');assert.equal(escape.status,403);
    const missing=await fetch(url+'/lab/does-not-exist.js');assert.equal(missing.status,404);
  }finally{child.kill();}
});
