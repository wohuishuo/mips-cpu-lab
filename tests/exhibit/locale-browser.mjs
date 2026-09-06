import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url),{chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHANNEL?{channel:process.env.PLAYWRIGHT_CHANNEL}:{})});
const page=await browser.newPage({viewport:{width:1500,height:1100}}),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));
const base=process.env.LAB_URL||'http://127.0.0.1:4173/lab/';
const output=new URL('../../build/exhibit/',import.meta.url);await mkdir(output,{recursive:true});
const pass=name=>{checks.push(name);console.log('PASS '+name);};
const ready=()=>page.waitForSelector('html[data-locale-ready=true]');
const english=async()=>{
  await page.waitForTimeout(30);
  const leftover=await page.evaluate(()=>{
    const strings=[],walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
    for(let node;node=walker.nextNode();)if(/[\u3400-\u9fff]/u.test(node.data)&&!node.parentElement.closest('#code,textarea,script,style,#language-toggle,#motion-toggle,[data-no-translate]')&&node.parentElement.checkVisibility())strings.push(node.data);
    for(const el of document.querySelectorAll('[aria-label],[title],[placeholder]'))if(el.checkVisibility()&&!el.closest('#code,#language-toggle'))for(const attr of ['aria-label','title','placeholder']){const value=el.getAttribute(attr);if(value&&/[\u3400-\u9fff]/u.test(value))strings.push(value);}
    return strings;
  });assert.deepEqual(leftover,[],`Untranslated visible text at ${page.url()}`);
};
const visit=async id=>{await page.locator(`#chapters a[href="#${id}"]`).click();await english();};
try{
  await page.goto(base+'?lang=en');await ready();await page.locator('#chapters a').first().waitFor();await english();
  assert.equal(await page.locator('html').getAttribute('lang'),'en');
  assert.match(await page.locator('a[href*="playground.html"]').first().getAttribute('href'),/lang=en/);
  await page.locator('[data-action="end"]').click();await english();
  const code=await page.locator('#code').textContent();assert.equal(await page.locator('[data-ram="11"] b').textContent(),'89');
  await page.locator('#language-toggle').click();assert.equal(await page.locator('html').getAttribute('lang'),'zh-CN');assert.equal(await page.locator('#code').textContent(),code);assert.equal(await page.locator('[data-ram="11"] b').textContent(),'89');
  await page.locator('#language-toggle').click();await english();await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:fileURLToPath(new URL('spectrum-en.png',output)),fullPage:true});
  pass('English/Chinese switch preserves executed state and verbatim source');
  for(const id of ['lab1','lab3','pipeline','lab5','exceptions','lab7','uart']){
    await visit(id);
    const actions={lab1:['[data-action="capture"]','[data-phase="3"]'],lab3:['[data-action="fib-all"]','[data-lab3="add"]','[data-action="lab3-add"]'],pipeline:['[data-action="next"]'],lab5:['[data-action="inject"]'],exceptions:['[data-action="next"]','[data-action="next"]','[data-action="next"]'],lab7:['[data-action="cache-read"]','[data-action="cache-write"]','[data-cache="256"]','[data-cache="512"]'],uart:['[data-action="next"]','[data-action="next"]','[data-action="next"]','[data-action="next"]']}[id];
    for(const action of actions){await page.locator(action).click();await english();}
    for(const step of await page.locator('[data-lesson]').all()){await step.click();await english();}
  }pass('All chapters, source notes and interactive results have English text');
  await visit('lab3');await page.locator('[data-lab3="add"]').click();await page.locator('#lab3-a').fill('17');await page.locator('#language-toggle').click();assert.equal(await page.locator('#lab3-a').inputValue(),'17');await page.locator('#language-toggle').click();await page.locator('[data-action="lab3-add"]').click();assert.equal(await page.locator('#lab3-sum').textContent(),'272');await english();
  await page.locator('#motion-toggle').click();assert.equal(await page.locator('html').getAttribute('data-motion'),'off');
  await page.reload();await ready();assert.equal(await page.locator('html').getAttribute('lang'),'en');assert.equal(await page.locator('html').getAttribute('data-motion'),'off');
  pass('Inputs and saved language/effects preferences survive switching and reload');
  await page.locator('a[href*="playground.html"]').first().click();await ready();assert.equal(await page.locator('html').getAttribute('lang'),'en');await english();
  const program=await page.locator('#program').inputValue();await page.locator('#language-toggle').click();assert.equal(await page.locator('#program').inputValue(),program);await page.locator('#language-toggle').click();
  await page.locator('#program').fill('addiu $oops, $zero, 1');await page.locator('#load').click();await english();assert.match(await page.locator('#notice').textContent(),/register/i);
  await page.locator('#example').selectOption('custom');for(let i=0;i<40&&!await page.locator('#step').isDisabled();i++)await page.locator('#step').click();assert.equal(await page.locator('[data-register="9"] .reg-value').textContent(),'0000000C');await english();
  for(const tab of ['circuit','guide','cpu']){await page.locator(`[data-tab="${tab}"]`).click();await english();if(tab==='circuit'){for(const option of await page.locator('[data-control="preset"] option').evaluateAll(xs=>xs.map(x=>x.value))){await page.locator('[data-control="preset"]').selectOption(option);await english();}}}
  pass('English playground executes CPU, reports errors, and translates circuit presets');
  await page.setViewportSize({width:390,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await page.goto(base+'?lang=en');await ready();await page.locator('#chapters a').first().waitFor();assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await english();
  await page.screenshot({path:fileURLToPath(new URL('spectrum-mobile-en.png',output)),fullPage:true});
  await page.emulateMedia({reducedMotion:'reduce'});assert.equal(await page.locator('.connection.lit').first().evaluate(e=>getComputedStyle(e).animationName),'none');
  pass('English mobile layouts and reduced-motion preference work');assert.deepEqual(errors,[]);
  await writeFile(new URL('locale-results.json',output),JSON.stringify({checks,errors},null,2));
}finally{await browser.close();}
