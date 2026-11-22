'use strict';
window.GateI18n=(()=>{
  const names={nl:'Nederlands',en:'English',de:'Deutsch'}, files=new Map();
  const sources=new WeakMap(), key='cb19-language';
  const originalTitle=document.title;
  let active={},lang='nl',revision=0,choice;
  const messages={"title":"Toegangshek","language":"Taal","closed":"Hek gesloten","open":"Beide hekken open","pedOpen":"Loophek open","pedOpening":"Loophek opent","pedClosing":"Loophek sluit","opening":"Hek opent","closing":"Hek sluit","stopped":"Hek gestopt","pedStopped":"Loophek gestopt","noPosition":"Stand onbekend","on":"Aan","off":"Uit","unknown":"Onbekend","offline":"Geen verbinding","awaitDevice":"Wachten op antwoord","stale":"Laatst bekende instellingen","lastRead":"Laatst opgehaalde instellingen","reading":"Wachten op uitlezing","confirmed":"Instelling door de CB19 bevestigd.","noAck":"Geen bevestiging ontvangen. Controleer de actuele instelling.","pending":"Wachten op bevestiging van de CB19…","settingTimeout":"Geen bevestiging ontvangen. Controleer de instelling.","remembered":"Deze wachttijd wordt gebruikt zodra je automatisch sluiten aanzet.","sending":"Opdracht versturen…","sent":"{action} · opdracht verstuurd.","gateTimeout":"Geen bevestiging ontvangen. Controleer de stand.","netError":"De ESP32 is niet bereikbaar.","requestError":"Aanvraag mislukt.","langError":"Taalbestand niet beschikbaar.","both":"Beide openen","ped":"Loophek openen","close":"Sluiten","stop":"Stop"};
  const t=id=>active[messages[id]]??messages[id];
  function translate(raw){
    if(!raw)return raw;
    const text=raw.trim();
    let value;
    if(Object.hasOwn(active,text))value=active[text];
    else if(/^F[1-9A-J] /.test(text)){
      const prefix=text.match(/^F[1-9A-J] (?:[–-] )?/)[0];
      value=prefix+translate(text.slice(prefix.length));
    }else if(/ \[\d+\]$/.test(text)){
      const pos=text.lastIndexOf(' [');value=translate(text.slice(0,pos))+text.slice(pos);
    }else if(/^Aan, \d/.test(text))value=t('on')+text.slice(3);
    else if(text.includes('. ')&&text.endsWith('.'))value=text.split(/(?<=\.)\s+/).map(s=>Object.hasOwn(active,s)?active[s]:s).join(' ');
    else if(lang==='en'&&/^[+\d][\d,]* (A|s)$/.test(text))value=text.replace(',','.');
    else return raw;
    return raw.replace(text,()=>value);
  }
  // Keep original messages so that already visible feedback changes language too.
  function format(source){
    if(typeof source==='string')return translate(source);
    const value=t(source.id);
    return source.action?value.replace('{action}',()=>t(source.action)):value;
  }
  function put(node,source){
    const value=format(source);
    if(node.textContent!==value)node.textContent=value;
    if(node.firstChild)sources.set(node.firstChild,source);
  }
  const say=(node,id,action)=>put(node,{id,action});
  function render(){
    document.documentElement.lang=lang;
    const walk=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
    for(let n=walk.nextNode();n;n=walk.nextNode()){
      if(!n.data.trim()||n.parentElement.closest('script,style,noscript,#locale')||(n.parentElement.id==='dev'&&!sources.has(n)))continue;
      if(!sources.has(n))sources.set(n,n.data);
      const value=format(sources.get(n));if(n.data!==value)n.data=value;
    }
    for(const e of document.querySelectorAll('[aria-label]')){
      if(e===choice)continue;
      if(!sources.has(e))sources.set(e,e.getAttribute('aria-label'));
      e.setAttribute('aria-label',translate(sources.get(e)));
    }
    document.title=document.getElementById('gate')?t('title')+' · CB19':originalTitle.replace(/CB19-instellingen|CB19 inleren/g,s=>translate(s));
    choice.setAttribute('aria-label',t('language'));choice.title=t('language');
    choice.value=lang;
  }
  async function load(code){
    if(files.has(code))return files.get(code);
    const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),5500);
    try{
      const res=await fetch('/hek?bestand='+code+'.json',{signal:abort.signal,mode:'same-origin'});
      if(!res.ok)throw Error('language');
      const data=await res.json();
      if(!data||typeof data!=='object'||!['Toegangshek','Taal','Hek gesloten','Automatisch sluiten'].every(k=>typeof data[k]==='string')||!Object.values(data).every(v=>typeof v==='string'))throw Error('language');
      files.set(code,data);return data;
    }finally{clearTimeout(timer)}
  }
  async function select(code,save){
    if(!Object.hasOwn(names,code))code='nl';
    const seq=++revision;let data,failed=false;
    try{data=await load(code)}catch{
      failed=true;
      if(Object.keys(active).length){code=lang;data=active}else{code='nl';try{data=await load('nl')}catch{data={}}}
    }
    if(seq!==revision)return;
    lang=code;active=data;render();
    const status=document.getElementById('langError');status.textContent=failed?t('langError'):'';
    if(save&&!failed)try{localStorage.setItem(key,lang)}catch{}
  }
  async function init(){
    choice=document.getElementById('locale');
    if(!choice){
      const bar=document.createElement('p');choice=document.createElement('select');choice.id='locale';
      bar.append(choice);(document.querySelector('h2')||document.body.firstElementChild)?.after(bar);
      choice.style.cssText='width:auto;max-width:100%;padding:3px 8px';
    }
    if(!document.getElementById('langError')){
      const status=document.createElement('small');status.id='langError';status.setAttribute('role','status');choice.after(status);
    }
    for(const [code,name] of Object.entries(names))choice.add(new Option(name,code));
    let saved='';try{saved=localStorage.getItem(key)}catch{}
    const browserLang=(navigator.languages||[navigator.language]).map(l=>l.toLowerCase().split('-')[0]).find(l=>Object.hasOwn(names,l));
    choice.onchange=()=>select(choice.value,true);
    await select(Object.hasOwn(names,saved)?saved:browserLang||'nl',false);
  }
  const ready=document.readyState==='loading'?new Promise(done=>document.addEventListener('DOMContentLoaded',()=>done(init()),{once:true})):init();
  return {t,put,say,ready};
})();
