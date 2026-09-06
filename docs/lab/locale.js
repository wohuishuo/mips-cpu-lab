// Translate presentation text only. Programs, source excerpts and input values stay verbatim.
const button=document.getElementById('language-toggle');
const motionButton=document.getElementById('motion-toggle');
const remembered=key=>{try{return localStorage.getItem(key);}catch{return null;}};
const remember=(key,value)=>{try{localStorage.setItem(key,value);}catch{/* Storage may be unavailable. */}};
let language=new URL(location.href).searchParams.get('lang')||remembered('cpu-language')||'zh';
language=language==='en'?'en':'zh';
let motion=remembered('cpu-motion')??(matchMedia('(prefers-reduced-motion: reduce)').matches?'off':'on');
const originals=new WeakMap(),attributes=new WeakMap();
const excluded=node=>node.parentElement?.closest('#code,textarea,script,style,[data-no-translate],.code-editor');
let translationFailed=false;
const dictionaries=await Promise.all(['chapters','exhibit','playground'].map(async name=>{
  const response=await fetch(`./i18n/${name}.en.json`);
  if(!response.ok)throw new Error(`Translation unavailable: ${name}`);
  return response.json();
})).catch(()=>{translationFailed=true;language='zh';return [];});
const dictionary=Object.assign({},...dictionaries);
const fragments=Object.entries(dictionary).filter(([key])=>key.length>=3).sort((a,b)=>b[0].length-a[0].length);
function translate(text){
  if(!/[\u3400-\u9fff]/u.test(text))return text;
  const core=text.trim();
  if(dictionary[core])return text.replace(core,dictionary[core]);
  let result=text
    .replace(/第 (\d+) 行：/g,'Line $1: ')
    .replace(/第 (\d+) 拍：把 (\d+) 存进内存。/g,'Cycle $1: store $2 in RAM.')
    .replace(/地址 (0x[\dA-F]+) 对应第 (\d+) 项。/g,'Address $1 holds term $2. ')
    .replace(/寄存器保存的前两项相加，下一圈继续写入。/g,'Add the two preceding register values; the next iteration stores another term.')
    .replace(/→ 把 (\d+)（(0x[\dA-F]+)）写入 (\$\w+)。/g,'→ Write $1 ($2) to $3. ')
    .replace(/开关给出 (0x[\dA-F]+)/g,'Switch input is $1')
    .replace(/相位 (\d+) 取出低组的 ([\dA-F]) 和高组的 ([\dA-F])，/g,'Phase $1 selects $2 from the low group and $3 from the high group. ')
    .replace(/^相位 (\d+)$/g,'Phase $1').replace(/^开关 (\d+)$/g,'Switch $1')
    .replace(/访问 (0x[\dA-Fa-f]+)/g,'Access $1')
    .replace(/写回 (\$\w+)/g,'Write back $1')
    .replace(/(\d+) 行/g,'$1 lines');
  for(const [from,to] of fragments)if(result.includes(from))result=result.split(from).join(to);
  result=result.replace(/位 (\d+)/g,'Bit $1').replace(/(\d+) 位/g,'$1 bits');
  return result;
}
function renderLanguage(){
  observer.disconnect();
  const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
  for(let node;node=walker.nextNode();){
    if(excluded(node)||node.parentElement?.closest('#language-toggle,#motion-toggle'))continue;
    const saved=originals.get(node),original=saved&&node.data===saved.rendered?saved.original:node.data;
    const rendered=language==='en'?translate(original):original;
    if(node.data!==rendered)node.data=rendered;
    originals.set(node,{original,rendered});
  }
  for(const element of document.querySelectorAll('[title],[aria-label],[placeholder]')){
    if(element.closest('#code,[data-no-translate]'))continue;
    const saved=attributes.get(element)||{};
    for(const name of ['title','aria-label','placeholder'])if(element.hasAttribute(name)){
      const current=element.getAttribute(name),old=saved[name];
      const original=old&&current===old.rendered?old.original:current;
      const rendered=language==='en'?translate(original):original;
      if(current!==rendered)element.setAttribute(name,rendered);
      saved[name]={original,rendered};
    }
    attributes.set(element,saved);
  }
  document.documentElement.lang=language==='en'?'en':'zh-CN';
  document.documentElement.dataset.language=language;
  document.documentElement.dataset.motion=motion;
  document.title=language==='en'?'MIPS CPU Lab · From code to silicon':document.body.classList.contains('playground')?'CPU 工坊 · 从一位到一台 CPU':'一台 CPU 是怎样工作的 · MIPS 实验记录';
  button.textContent=language==='en'?'中文':'English';
  button.setAttribute('aria-label',language==='en'?'切换到中文':'Switch to English');
  button.disabled=translationFailed;
  if(translationFailed)button.title='English translation could not load. Refresh to retry.';
  motionButton.textContent=language==='en'?`Effects ${motion==='on'?'on':'off'}`:`动效${motion==='on'?'开启':'关闭'}`;
  motionButton.setAttribute('aria-pressed',String(motion==='on'));
  for(const anchor of document.querySelectorAll('a[href]')){
    const url=new URL(anchor.href,location.href);
    if(url.origin===location.origin&&url.pathname!==location.pathname&&(/\/lab\/$|\/lab\/index\.html$|\/playground\.html$/.test(url.pathname))){url.searchParams.set('lang',language);anchor.href=url.href;}
  }
  observer.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['title','aria-label','placeholder']});
  document.documentElement.dataset.localeReady='true';
}
const observer=new MutationObserver(renderLanguage);
button.addEventListener('click',()=>{
  language=language==='en'?'zh':'en';remember('cpu-language',language);
  const url=new URL(location.href);url.searchParams.set('lang',language);history.replaceState(null,'',url);
  renderLanguage();
});
motionButton.addEventListener('click',()=>{motion=motion==='on'?'off':'on';remember('cpu-motion',motion);renderLanguage();});
// Links are stamped during rendering, so middle-click and copy-link retain language too.
renderLanguage();
