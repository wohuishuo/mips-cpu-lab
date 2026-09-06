/** Real browser regression. Start npm run lab, then npm run test:browser.
 * npm install --no-save playwright; npx playwright install chromium
 * Or PLAYWRIGHT_CHANNEL=msedge and PLAYWRIGHT_MODULE=<existing package dir>.
 */
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const url=new URL('playground.html',process.env.LAB_URL||'http://127.0.0.1:4173/lab/').href;
const output=new URL('../../build/visual-lab/',import.meta.url);
await mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHANNEL?{channel:process.env.PLAYWRIGHT_CHANNEL}:{})});
const page=await browser.newPage({viewport:{width:1440,height:1080},deviceScaleFactor:1});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
const checks=[];
const check=(name)=>{checks.push(name);console.log('PASS '+name);};
async function clock(count){for(let i=0;i<count;i++)await page.locator('#step').click();}
async function finish(limit=300){for(let i=0;i<limit;i++){if(await page.locator('#step').isDisabled())return;await page.locator('#step').click();}throw new Error('Program did not halt');}
const value=async index=>page.locator(`[data-register="${index}"] .reg-value`).textContent();
try{
  await page.goto(url);await page.locator('#step').waitFor();
  assert.equal(await page.locator('#cycle').textContent(),'000');
  await page.locator('#speed').fill('10');
  await page.locator('[data-stage="MEM"]').focus();await page.keyboard.press('Space');
  assert.match(await page.locator('#selected-stage-name').textContent(),/^MEM/);
  assert.equal(await page.locator('#status').textContent(),'就绪','stage Space must not start execution');
  await page.waitForTimeout(250);
  assert.equal(await page.locator('#cycle').textContent(),'000','stage Space must not advance the CPU');
  assert.equal(await page.locator('[data-stage="MEM"]').evaluate(el=>el===document.activeElement),true,'stage keyboard selection retains focus');
  await page.locator('[data-stage="MEM"]').evaluate(el=>el.blur());await page.keyboard.press('Space');
  assert.equal(await page.locator('#status').textContent(),'运行中','body Space still starts execution');
  await page.waitForTimeout(250);await page.keyboard.press('Space');
  assert.equal(await page.locator('#status').textContent(),'已暂停','body Space still pauses execution');
  assert.ok(Number(await page.locator('#cycle').textContent())>0);
  await page.locator('#reset').click();check('流水级空格选择保留焦点，页面空格运行与暂停');
  await clock(7);assert.equal(await value(8),'00000007');
  await page.locator('[data-stage="MEM"]').click();assert.match(await page.locator('#selected-stage-detail').textContent(),/地址=0x00000000/);
  const before=await page.locator('#cycle').textContent();await page.locator('#back').click();assert.equal(Number(await page.locator('#cycle').textContent()),Number(before)-1);await page.locator('#step').click();assert.equal(await page.locator('#cycle').textContent(),before);
  check('真实时钟、写回与回退');
  await page.screenshot({path:fileURLToPath(new URL('cpu-desktop.png',output))});
  await page.screenshot({path:fileURLToPath(new URL('cpu-full.png',output)),fullPage:true});
  await finish();assert.equal(await value(9),'0000000C');assert.equal(await value(11),'00000011');
  await page.locator('[data-state="memory"]').click();assert.equal(await page.locator('[data-address="0"] .reg-value').textContent(),'0000000C');assert.equal(await page.locator('[data-address="4"] .reg-value').textContent(),'00000011');check('默认 CUSTOM 输入 7/5 → RAM 12/17');
  await page.locator('#program').fill('addiu $oops, $zero, 1');await page.locator('#load').click();assert.match(await page.locator('#notice').textContent(),/行|寄存器/);assert.ok(await page.locator('#notice').evaluate(el=>el.classList.contains('error')));check('汇编错误定位');
  await page.locator('#example').selectOption('fibonacci');await finish();assert.equal(await page.locator('[data-address="44"] .reg-value').textContent(),'00000059');check('循环与延迟槽 → Fibonacci 第 12 项 89');
  await page.locator('#example').selectOption('bytes');await finish();assert.equal(await page.locator('[data-address="0"] .reg-value').textContent(),'1234AB78');check('小端字节写入');
  await page.locator('#example').selectOption('custom');await page.locator('#wait').selectOption('3');await finish();const waited=Number(await page.locator('#cycle').textContent());await page.locator('#wait').selectOption('0');await finish();const fast=Number(await page.locator('#cycle').textContent());assert.equal(waited-fast,9);check('3 次访存各等待 3 拍，结果不重复');
  await page.locator('#reset').click();await page.locator('#speed').fill('10');await page.locator('#run').click();assert.equal(await page.locator('#status').textContent(),'运行中');await page.waitForTimeout(360);await page.locator('#run').click();assert.equal(await page.locator('#status').textContent(),'已暂停');const paused=await page.locator('#cycle').textContent();assert.ok(Number(paused)>0);await page.waitForTimeout(230);assert.equal(await page.locator('#cycle').textContent(),paused);check('运行、速度与暂停');
  await page.locator('#gate-a').fill('0xFFFFFFFF');await page.locator('#gate-b').fill('1');await page.locator('[data-bit="31"]').click();assert.match(await page.locator('#gate-diagram svg').getAttribute('aria-label'),/Cout=1/);check('32 位全加器进位展开');
  await page.locator('[data-tab="circuit"]').click();await page.locator('.circuit-editor').waitFor();
  await page.screenshot({path:fileURLToPath(new URL('circuit-desktop.png',output))});
  // The editor itself is exercised in a separate browser probe once its UI is mounted.
  check('电路工坊装载');
  await page.locator('[data-tab="cpu"]').click();await page.locator('#reset').click();await page.locator('#input-a').fill('11');await page.locator('#input-b').fill('2');await page.locator('#load').click();await finish();assert.equal(await page.locator('[data-address="0"] .reg-value').textContent(),'0000000D');check('用户重新输入改变结果');
  await page.setViewportSize({width:390,height:844});await page.locator('#reset').click();await page.screenshot({path:fileURLToPath(new URL('cpu-mobile.png',output)),fullPage:true});
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1));check('390px 布局无整页横向溢出');
  assert.deepEqual(errors,[]);check('浏览器无未捕获异常');
  await writeFile(new URL('browser-results.json',output),JSON.stringify({time:new Date().toISOString(),url,checks,errors},null,2));
}finally{await browser.close();}
