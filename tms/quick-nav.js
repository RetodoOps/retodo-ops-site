(function(){
  const STORAGE_KEY='retodo.quickRecent.v1';
  const MAX_RECENT=8;
  let projects=[],jobs=[],loaded=false,activeIndex=-1;
  const esc=value=>String(value??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
  const readRecent=()=>{try{const rows=JSON.parse(localStorage.getItem(STORAGE_KEY)||'[]');return Array.isArray(rows)?rows:[]}catch{return []}};
  const writeRecent=rows=>localStorage.setItem(STORAGE_KEY,JSON.stringify(rows.slice(0,MAX_RECENT)));
  function recordVisit(type,id,label,meta=''){
    if(!id||!label)return;
    const href=type==='Project'?`project.html?id=${encodeURIComponent(id)}`:`job.html?id=${encodeURIComponent(id)}`;
    writeRecent([{type,id,label,meta,href,visited_at:new Date().toISOString()},...readRecent().filter(row=>!(row.type===type&&row.id===id))]);
  }
  async function loadIndex(){
    if(loaded||typeof _sb==='undefined')return;
    loaded=true;
    const [projectResult,jobResult]=await Promise.all([
      _sb.from('projects').select('id,display_name,project_number,client_reference,status,source_language,target_language,updated_at').order('updated_at',{ascending:false}).limit(250),
      _sb.from('project_jobs').select('id,job_number,service_type,status,source_language,target_language,project_id,projects(display_name,project_number)').order('created_at',{ascending:false}).limit(250)
    ]);
    projects=(projectResult.data||[]).map(row=>({type:'Project',id:row.id,label:row.display_name||row.project_number,meta:[row.project_number,row.client_reference,row.status,`${row.source_language||''} → ${row.target_language||''}`].filter(Boolean).join(' · '),href:`project.html?id=${encodeURIComponent(row.id)}`}));
    jobs=(jobResult.data||[]).map(row=>({type:'Job',id:row.id,label:row.job_number,meta:[row.projects?.display_name||row.projects?.project_number,row.service_type,row.status,`${row.source_language||''} → ${row.target_language||''}`].filter(Boolean).join(' · '),href:`job.html?id=${encodeURIComponent(row.id)}`}));
  }
  function rowHtml(row,index){const type=row.type==='Project'?'Project':'Job',href=type==='Project'?`project.html?id=${encodeURIComponent(row.id)}`:`job.html?id=${encodeURIComponent(row.id)}`;return `<a class="quick-nav-result" data-index="${index}" href="${href}" data-type="${type}" data-id="${esc(row.id)}" data-label="${esc(row.label)}" data-meta="${esc(row.meta||'')}"><span class="quick-nav-kind">${type}</span><span class="quick-nav-copy"><strong>${esc(row.label)}</strong><small>${esc(row.meta||'')}</small></span></a>`}
  function render(){
    const input=document.getElementById('quickNavInput'),results=document.getElementById('quickNavResults');if(!input||!results)return;
    const query=input.value.trim().toLowerCase();let rows;
    if(query){rows=[...projects,...jobs].filter(row=>`${row.label} ${row.meta}`.toLowerCase().includes(query)).slice(0,12)}else rows=readRecent();
    activeIndex=-1;results.innerHTML=`<div class="quick-nav-caption">${query?'Projects and Jobs':'Recently visited'}</div>`+(rows.length?rows.map(rowHtml).join(''):`<div class="quick-nav-empty">${query?'No matching Projects or Jobs.':'Visited Projects and Jobs will appear here.'}</div>`);
    results.classList.remove('hidden');
    results.querySelectorAll('.quick-nav-result').forEach(link=>link.addEventListener('click',()=>recordVisit(link.dataset.type,link.dataset.id,link.dataset.label,link.dataset.meta)));
  }
  function move(delta){const rows=[...document.querySelectorAll('.quick-nav-result')];if(!rows.length)return;activeIndex=(activeIndex+delta+rows.length)%rows.length;rows.forEach((row,index)=>row.classList.toggle('active',index===activeIndex));rows[activeIndex].scrollIntoView({block:'nearest'})}
  function install(){
    if(document.getElementById('quickNav'))return;
    const host=document.querySelector('.main')||document.body;
    host.insertAdjacentHTML('afterbegin',`<div id="quickNav" class="quick-nav"><div class="quick-nav-shell"><span class="quick-nav-icon" aria-hidden="true">⌕</span><input id="quickNavInput" type="search" autocomplete="off" placeholder="Search Projects and Jobs…" aria-label="Quick search Projects and Jobs"><kbd>Ctrl K</kbd></div><div id="quickNavResults" class="quick-nav-results hidden"></div></div>`);
    const input=document.getElementById('quickNavInput'),results=document.getElementById('quickNavResults');let timer;
    input.addEventListener('focus',async()=>{await loadIndex();render()});
    input.addEventListener('input',()=>{clearTimeout(timer);timer=setTimeout(render,120)});
    input.addEventListener('keydown',event=>{if(event.key==='ArrowDown'){event.preventDefault();move(1)}else if(event.key==='ArrowUp'){event.preventDefault();move(-1)}else if(event.key==='Enter'&&activeIndex>=0){event.preventDefault();document.querySelectorAll('.quick-nav-result')[activeIndex]?.click()}else if(event.key==='Escape'){results.classList.add('hidden');input.blur()}});
    document.addEventListener('click',event=>{if(!event.target.closest('#quickNav'))results.classList.add('hidden')});
    document.addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='k'){event.preventDefault();input.focus();input.select()}else if(event.key==='/'&&!['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName)){event.preventDefault();input.focus()}});
  }
  window.TMS_QUICK_NAV={recordVisit};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();
