/* Read-only report client. All totals and filtering are supplied by one RLS-bound RPC. */
const ReportUI = (() => {
    const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const number = value => value == null ? '—' : Number(value).toLocaleString('en-GB', {minimumFractionDigits:2,maximumFractionDigits:2});
    const costs = row => Object.entries(row.costs || {}).map(([currency,amount]) => `${currency} ${number(amount)}`).join('; ') || '—';
    function warnings(row, type) {
        const messages = [];
        if (row.unknown_cost_count > 0) messages.push(`${row.unknown_cost_count} unknown cost(s)`);
        if (row.po_warning_count > 0) messages.push('PO version conflict or missing snapshot');
        if (row.currency_warning_count > 0) messages.push('Currency conversion required or currency missing');
        if (row.unallocated_job_count > 0) messages.push('Jobs without a Scoop');
        if (type !== 'jobs' && row.job_count === 0) messages.push('No Jobs — cost incomplete');
        if (type === 'projects' && row.scoop_count === 0) messages.push('No Scoops — client value unavailable');
        if (row.empty_scoop_count > 0) messages.push('Scoop without Jobs — cost incomplete');
        if (row.estimate_count > 0) messages.push(`${row.estimate_count} estimated cost(s)`);
        if (row.excluded_job_count > 0) messages.push(`${row.excluded_job_count} cancelled/declined Job(s) excluded`);
        return messages.join('; ');
    }
    // Quoting alone does not stop spreadsheet formulas, including whitespace-prefixed ones.
    function csvCell(value) {
        if(typeof value==='number') return Number.isFinite(value)?String(value):'';
        let text = String(value ?? '');
        if (/^[\s\u0000-\u001f]*[=+\-@]/u.test(text) || /^[\t\r\n]/u.test(text)) text = "'" + text;
        return '"' + text.replaceAll('"','""') + '"';
    }
    const exportFields = {
        projects: ['id','project_id','project_number','name','client_id','client','account_id','account','pm_id','pm','date','project_date','deadline','status','scoop_count','job_count','currency','client_value','profit','margin'],
        jobs: ['id','project_id','project_number','project_name','scoop_id','scoop_number','name','client_id','client','account_id','account','pm_id','pm','resource_id','resource','source_language','target_language','service','status','date','deadline','quantity','unit','currency','cost_basis','po_id','po_number','po_version'],
        margin: ['id','project_id','project_number','project_name','name','client_id','client','account_id','account','pm_id','pm','source_language','target_language','status','date','deadline','job_count','currency','client_value','profit','margin']
    };
    const labels = {unknown_cost:'Unknown cost',po_conflict:'PO conflict / snapshot issue',currency_mismatch:'Currency mismatch / missing',incomplete_margin:'Margin unavailable',estimate:'Estimated costs',excluded:'Cancelled / declined Jobs excluded'};
    function csv(data) {
        const currencies=[...new Set(data.rows.flatMap(r=>Object.keys(r.costs||{})))].sort();
        const fields=exportFields[data.report_type];
        const lines=[['REPORT METADATA'],['Report',data.report_type],['Generated at',data.generated_at],['Date basis',data.date_basis],['Filters',JSON.stringify(data.filters)],['Total rows',data.total_count],['Currency conversion','None'],[],['REPORT ROWS'],[...fields,...currencies.map(c=>'supplier_cost_'+c),'estimate_count','unknown_cost_count','issue_codes','info_codes','source_reference']];
        for(const row of data.rows) lines.push([...fields.map(k=>row[k]),...currencies.map(c=>row.costs?.[c]??null),row.estimate_count,row.unknown_cost_count,(row.issue_codes||[]).join(';'),(row.info_codes||[]).join(';'),data.report_type==='jobs'?`job.html?id=${encodeURIComponent(row.id)}`:`project.html?id=${encodeURIComponent(row.project_id)}${data.report_type==='margin'?'&scoop='+encodeURIComponent(row.id):''}`]);
        lines.push([],['CURRENCY TOTALS'],['Currency','Client value','Supplier cost','Profit','Weighted margin %','Incomplete rows','Estimated costs']);
        for(const r of data.summary_by_currency)lines.push([r.currency,r.client_value,r.supplier_cost,r.profit,r.margin,r.incomplete_rows,r.estimate_count]);
        if(data.groups?.length){lines.push([],['GROUP SUMMARY'],['Group ID','Group','Currency','Rows','Client value','Supplier cost','Profit','Weighted margin %','Issue rows']);for(const r of data.groups)lines.push([r.id,r.label,r.currency,r.row_count,r.client_value,r.supplier_cost,r.profit,r.margin,r.issue_rows]);}
        return '\ufeff'+lines.map(line=>line.map(csvCell).join(',')).join('\r\n');
    }
    function errorState(error) {
        if(['PGRST202','42883','VERSION'].includes(error.code))return ['unavailable','Reports service is unavailable. An administrator needs to verify the reporting database update.'];
        if(['42501','PGRST301','401','403'].includes(String(error.code)))return ['denied','You do not have access to this report. Contact an administrator.'];
        if(['TIMEOUT','57014'].includes(error.code))return ['timeout','The report timed out. Narrow the filters or retry.'];
        if(error instanceof TypeError || /fetch|network/i.test(error.message||''))return ['network','Cannot reach the reporting service. Check your connection and retry.'];
        return ['query','The report could not be loaded. Retry or contact an administrator.'];
    }
    return {escape,number,costs,warnings,csvCell,csv,exportFields,labels,errorState};
})();
if (typeof module !== 'undefined') module.exports = ReportUI;
if (typeof document !== 'undefined') {
    window.reportStarted=true;clearTimeout(window.reportBootTimer);
    const el=id=>document.getElementById(id), {escape:esc,number:num,costs,labels}=ReportUI;
    const types=['projects','jobs','margin'];
    const type=new URLSearchParams(location.search).get('type')||'projects';
    const relationKeys=['client_id','account_id','pm_id','resource_id'];
    const filterKeys=['search',...relationKeys,'pm','source_language','target_language','service','currency','scope','cost_basis','quality','margin_min','margin_max','from','to','date_basis','group_by'];
    let current=null, options=null, ready=false, busy=false, generation=0, offset=0;
    let applied={filters:{scope:'active'},sort:'name',desc:false};
    const lookupMaps={};
    function controls(){
        el('viewReport').disabled=!ready||busy;
        el('previousPage').disabled=busy||!current||offset===0;
        el('nextPage').disabled=busy||!current||current.next_offset==null;
        el('exportReport').disabled=busy||!current||!current.total_count;
    }
    async function timed(promise,controller){
        let timer;
        try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>{controller?.abort();reject(Object.assign(new Error('Request exceeded 20 seconds'),{code:'TIMEOUT'}));},20000);})]);}
        finally{clearTimeout(timer);}
    }
    async function rpc(name,args){
        const controller=new AbortController();
        let request=_sb.rpc(name,args);
        if(request.abortSignal)request=request.abortSignal(controller.signal);
        const {data,error}=await timed(request,controller);
        if(error)throw error;
        if(data?.api_version!==59)throw Object.assign(new Error('Expected report API 59. Verify migrations 052/053, function signatures and PostgREST schema cache.'),{code:'VERSION'});
        return data;
    }
    function showError(error){
        const [state,message]=ReportUI.errorState(error);
        el('reportMessage').textContent=message;el('reportMessage').dataset.state=state;el('retryReport').hidden=false;
        const admin=document.body.dataset.appRole==='admin';
        el('reportDiagnostics').hidden=!admin;
        el('reportDiagnostics').querySelector('pre').textContent=admin?`Reports UI 059 · ${new Date().toISOString()}\nCode: ${error.code||error.name||'unknown'}\n${error.message||'Unknown error'}\n${error.details||''}\nVerify tms_report and tms_report_options with an authenticated company role. Missing function, permission, schema cache and network failures need different remedies.`:'';
    }
    function fromUrl(){
        const params=new URLSearchParams(location.search),filters={scope:'active'};
        for(const key of filterKeys)if(params.get(key))filters[key]=params.get(key);
        filters.statuses=params.getAll('statuses');
        if(type==='jobs'){delete filters.margin_min;delete filters.margin_max;}
        if(type!=='jobs'&&filters.group_by==='resource')delete filters.group_by;
        const allowed=['name','date','status','client','cost',...(type==='jobs'?[]:['client_value','profit','margin'])];
        let sort=allowed.includes(params.get('sort'))?params.get('sort'):'name';
        if(['cost','profit','margin','client_value'].includes(sort)&&!filters.currency)sort='name';
        applied={filters,sort,desc:params.get('direction')==='desc'};offset=0;
    }
    function stateUrl(target=type){
        const p=new URLSearchParams({type:target});
        for(const [key,value]of Object.entries(applied.filters)){
            if(target!==type&&['statuses','date_basis','group_by','margin_min','margin_max','quality'].includes(key))continue;
            if(Array.isArray(value)){for(const v of value)p.append(key,v);}else if(value)p.set(key,value);
        }
        p.set('sort',target==='jobs'&&['profit','margin','client_value'].includes(applied.sort)?'name':applied.sort);
        p.set('direction',applied.desc?'desc':'asc');return 'reports.html?'+p;
    }
    function displayState(push=false){
        if(push)history.pushState(null,'',stateUrl());
        document.querySelectorAll('a[href*="reports.html?type="]').forEach(a=>{const target=new URL(a.href).searchParams.get('type');if(types.includes(target))a.href=stateUrl(target);});
        const chips=[];
        for(const[key,value]of Object.entries(applied.filters)){
            if(!value||Array.isArray(value)&&!value.length||key==='scope'&&value==='active'||key==='group_by'&&value==='none')continue;
            let label=Array.isArray(value)?value.join(', '):String(value);
            if(lookupMaps[key])label=[...lookupMaps[key]].find(([,id])=>id===value)?.[0]||label;
            chips.push(`${key.replaceAll('_',' ')}: ${label}`);
        }
        el('activeFilters').textContent=chips.length?'Applied — '+chips.join(' · '):'All active work · no additional filters';
    }
    function fillLookup(key,rows){
        lookupMaps[key]=new Map(rows.map(r=>[`${r.label||'Unnamed'} [${r.id}]`,r.id]));
        el(key+'Options').innerHTML=[...lookupMaps[key].keys()].map(label=>`<option value="${esc(label)}"></option>`).join('');
    }
    function accounts(clientId){fillLookup('account_id',options.accounts.filter(a=>!clientId||a.client_id===clientId));}
    function restoreForm(){
        el('reportFilters').reset();
        accounts(applied.filters.client_id);
        for(const key of filterKeys){if(!el(key))continue;const value=applied.filters[key]||'';el(key).value=relationKeys.includes(key)?([...lookupMaps[key]].find(([,id])=>id===value)?.[0]||''):value;}
        if(applied.filters.pm)el('pm_id').value=[...lookupMaps.pm_id].find(([,id])=>id==='legacy:'+applied.filters.pm)?.[0]||'';
        el('scope').value=applied.filters.scope||'active';el('group_by').value=applied.filters.group_by||'none';
        el('date_basis').value=applied.filters.date_basis||(type==='jobs'?'deadline':'project_date');
        el('statuses').querySelectorAll('input').forEach(c=>c.checked=(applied.filters.statuses||[]).includes(c.value));
        el('sort').value=applied.sort;el('direction').value=applied.desc?'desc':'asc';
        updateSort();
    }
    function updateSort(){
        for(const o of el('sort').options)o.disabled=['cost','client_value','profit','margin'].includes(o.value)&&!el('currency').value;
        if(el('sort').selectedOptions[0]?.disabled)el('sort').value='name';
    }
    function readForm(){
        const filters={};
        for(const key of filterKeys){if(key==='pm'||!el(key)||el(key).disabled)continue;const value=el(key).value.trim();if(!value)continue;
            if(relationKeys.includes(key)){const id=lookupMaps[key].get(value);if(!id)throw new Error('Select a listed '+el(key).labels[0].textContent.toLowerCase()+'.');if(id.startsWith('legacy:'))filters.pm=id.slice(7);else filters[key]=id;}
            else filters[key]=value;
        }
        filters.statuses=[...el('statuses').querySelectorAll('input:checked')].map(c=>c.value);
        if(filters.from&&filters.to&&filters.from>filters.to)throw new Error('From date must be on or before To date.');
        if(filters.margin_min&&filters.margin_max&&Number(filters.margin_min)>Number(filters.margin_max))throw new Error('Minimum margin must be no greater than maximum margin.');
        return {filters,sort:el('sort').value,desc:el('direction').value==='desc'};
    }
    const link=(url,label)=>`<a class="table-link" href="${esc(url)}">${esc(label||'Open')}</a>`;
    const projectLink=r=>link(`project.html?id=${encodeURIComponent(r.project_id)}`,r.project_number||r.project_name||r.name);
    const scoopLink=r=>link(`project.html?id=${encodeURIComponent(r.project_id)}&scoop=${encodeURIComponent(type==='margin'?r.id:r.scoop_id)}`,type==='margin'?r.name:r.scoop_number||'Scoop');
    const deadline=t=>t?new Date(t).toISOString().slice(0,16).replace('T',' ')+' UTC':'No deadline';
    const small=t=>`<small>${esc(t||'—')}</small>`;
    function quality(r){
        return [...(r.issue_codes||[]).map(c=>`<span class="report-badge issue">${esc(labels[c]||c)}</span>`),...(r.info_codes||[]).map(c=>`<span class="report-badge info">${esc(labels[c]||c)}</span>`)].join(' ')||'<span class="report-ok">No issues</span>';
    }
    function render(data){
        const grain=type==='projects'?'One row per Project. Related language, service and resource filters select whole Projects; totals include all their active work.':type==='margin'?'One row per Scoop. Related Job filters select whole Scoops; costs include all their active Jobs.':'One row per Job. No client revenue allocated to Jobs.';
        el('reportBasis').textContent=`${data.date_basis} · ${grain} Dates include both selected days.`;
        el('reportSummary').innerHTML=data.summary_by_currency.map(s=>`<section class="section-card"><h2>${esc(s.currency)}</h2><dl>${type!=='jobs'?`<dt>Client value</dt><dd>${num(s.client_value)}</dd>`:''}<dt>Known supplier cost</dt><dd>${num(s.supplier_cost)}</dd>${type!=='jobs'?`<dt>${s.estimate_count?'Estimated profit':'Profit'}</dt><dd>${num(s.profit)}</dd><dt>Weighted margin</dt><dd>${s.margin==null?'Unavailable':num(s.margin)+'%'}</dd>`:''}</dl>${s.incomplete_rows&&type!=='jobs'?'<p class="report-warning">Margin unavailable: incomplete or incompatible data.</p>':''}${s.estimate_count?'<p class="report-note">Includes saved estimates.</p>':''}</section>`).join('');
        el('reportWarnings').innerHTML=Object.entries(data.issue_counts||{}).map(([code,count])=>`<button type="button" class="report-badge ${Number(count)===0?'neutral':['estimate','excluded'].includes(code)?'info':'issue'}" data-quality="${esc(code)}">${esc(code==='blocking'?'Blocking issues':labels[code]||code)}: ${Number(count)}</button>`).join('');
        el('reportWarnings').querySelectorAll('button').forEach(b=>b.onclick=()=>{applied.filters.quality=b.dataset.quality;el('quality').value=b.dataset.quality;offset=0;displayState(true);load();});
        const headers=type==='projects'?['Project','Client / Account','PM / Project date / Deadline','Status','Scoops / Jobs','Client value','Supplier costs','Profit / Margin','Data quality']:type==='jobs'?['Job / Project / Scoop','Resource','Languages / Service','Deadline / Status','Quantity','Cost / Basis','PO / Version','Data quality']:['Scoop / Project','Client / Account','Language pair','Status / Date / Deadline','Jobs','Client value','Supplier costs','Profit / Margin','Data quality'];
        el('reportTable').querySelector('thead').innerHTML='<tr>'+headers.map(h=>`<th scope="col">${esc(h)}</th>`).join('')+'</tr>';
        el('reportTable').querySelector('tbody').innerHTML=data.rows.length?data.rows.map(r=>{
            const money=`${esc(r.currency||'Unknown')} ${num(r.client_value)}`,profit=`${num(r.profit)}${small(r.margin==null?'Unavailable':num(r.margin)+'%')}`,client=esc(r.client||'—')+small(r.account),languages=esc(r.source_language||'—')+' → '+esc(r.target_language||'—');
            let cells;
            if(type==='projects')cells=[projectLink(r)+small(r.name),client,esc(r.pm||'—')+small(r.project_date)+small(deadline(r.deadline)),esc(r.status),`${r.scoop_count} / ${r.job_count}`,money,esc(costs(r)),profit,quality(r)];
            else if(type==='margin')cells=[scoopLink(r)+small(r.project_name)+'<br>'+projectLink(r),client,languages,esc(r.status)+small(r.date)+small(deadline(r.deadline)),esc(r.job_count),money,esc(costs(r)),profit,quality(r)];
            else cells=[link(`job.html?id=${encodeURIComponent(r.id)}`,r.name)+'<br>'+projectLink(r)+(r.scoop_id?'<br>'+scoopLink(r):''),r.resource_id?link(`resource.html?id=${encodeURIComponent(r.resource_id)}`,r.resource):'Unassigned',languages+small(r.service),esc(r.deadline?new Date(r.deadline).toISOString().slice(0,16).replace('T',' ')+' UTC':'No deadline')+small(r.status),esc(r.quantity??'—')+small(r.unit),esc(costs(r))+small(r.cost_basis),r.po_id?link(`job.html?id=${encodeURIComponent(r.id)}&po=${encodeURIComponent(r.po_id)}&version=${encodeURIComponent(r.po_version)}`,`${r.po_number} · V${r.po_version}`):'—',quality(r)];
            return '<tr>'+cells.map((c,i)=>`<td${type!=='jobs'&&i>=4&&i<=7?' class="report-numeric"':''}>${c}</td>`).join('')+'</tr>';
        }).join(''):`<tr><td colspan="${headers.length}">No matching results. Try changing the filters.</td></tr>`;
        el('reportCount').textContent=data.total_count?`${offset+1}–${offset+data.rows.length} of ${data.total_count}`:'0 results';
        el('reportGroups').innerHTML=data.groups?.length?'<h2>Grouped summary</h2><div class="report-table-wrap"><table class="module-table"><thead><tr>'+['Group','Currency','Rows','Client value','Known cost','Profit','Weighted margin'].map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+data.groups.map(r=>'<tr>'+[esc(r.label)+small(r.id),esc(r.currency),r.row_count??'—',num(r.client_value),num(r.supplier_cost),num(r.profit),r.margin==null?'—':num(r.margin)+'%'].map(c=>'<td>'+c+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>':'';
    }
    async function query(start,limit){return rpc('tms_report',{p_type:type,p_filters:applied.filters,p_offset:start,p_limit:limit,p_sort:applied.sort,p_desc:applied.desc});}
    async function load(){
        const request=++generation;busy=true;current=null;controls();
        el('reportMessage').textContent='Loading report…';el('reportMessage').dataset.state='loading';el('retryReport').hidden=true;el('reportDiagnostics').hidden=true;
        for(const id of ['reportSummary','reportWarnings','reportGroups','reportCount','reportBasis'])el(id).replaceChildren();el('reportTable').querySelector('tbody').replaceChildren();el('reportTable').querySelector('thead').replaceChildren();
        try{const data=await query(offset,50);if(request!==generation)return;current=data;render(data);el('reportMessage').dataset.state='ready';el('reportMessage').textContent=`Generated ${new Date(data.generated_at).toLocaleString('en-GB')} · ${data.total_count} matching rows`;}catch(e){if(request===generation)showError(e);}finally{if(request===generation){busy=false;controls();}}
    }
    async function exportReport(){
        busy=true;controls();const request=generation;
        try{const data=await query(0,10000);if(request!==generation)return;if(data.total_count>10000||data.rows.length!==data.total_count)throw new Error('Export is limited to 10,000 rows. Narrow the filters and try again.');
            const url=URL.createObjectURL(new Blob([ReportUI.csv(data)],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=url;a.download=`retodo-${type}-${new Date().toISOString().slice(0,10)}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);el('reportMessage').textContent=`Exported ${data.total_count} rows from a fresh snapshot. Numeric cost columns are separated by currency.`;
        }catch(e){if(request===generation){if(e.message?.startsWith('Export is limited'))el('reportMessage').textContent=e.message;else showError(e);}}finally{if(request===generation){busy=false;controls();}}
    }
    let restoring=false;
    el('reportFilters').addEventListener('submit',e=>{e.preventDefault();if(!ready||busy)return;try{applied=readForm();offset=0;displayState(true);load();}catch(error){el('reportMessage').textContent=error.message;}});
    el('reportFilters').addEventListener('reset',e=>{if(restoring)return;e.preventDefault();if(!ready)return;applied={filters:{scope:'active'},sort:'name',desc:false};offset=0;restore();displayState(true);load();});
    function restore(){restoring=true;try{restoreForm();}finally{restoring=false;}}
    el('client_id').addEventListener('change',()=>{accounts(lookupMaps.client_id.get(el('client_id').value));el('account_id').value='';});
    el('currency').addEventListener('change',updateSort);
    el('preset').addEventListener('change',()=>{
        const now=new Date(),end=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate())),start=new Date(end),preset=el('preset').value;
        if(preset==='month')start.setUTCDate(1);if(preset==='year'){start.setUTCMonth(0,1);}if(preset==='last_month'){end.setUTCDate(0);start.setUTCMonth(end.getUTCMonth(),1);start.setUTCFullYear(end.getUTCFullYear());}if(preset==='30')start.setUTCDate(start.getUTCDate()-29);
        el('from').value=preset?start.toISOString().slice(0,10):'';el('to').value=preset?end.toISOString().slice(0,10):'';
    });
    for(const id of ['from','to'])el(id).addEventListener('change',()=>el('preset').value='');
    el('previousPage').onclick=()=>{offset=Math.max(0,offset-50);load();};el('nextPage').onclick=()=>{offset=current.next_offset;load();};el('exportReport').onclick=exportReport;
    window.addEventListener('popstate',()=>{if(!ready)return;fromUrl();restore();displayState();load();});
    async function start(){
        busy=true;controls();el('retryReport').hidden=true;el('reportMessage').textContent='Connecting to Reports…';
        try{
            if(typeof requireAuth!=='function')throw new TypeError('Authentication scripts did not load');
            if(!await timed(requireAuth()))return;
            if(!types.includes(type)){el('reportFilters').hidden=true;el('reportMessage').textContent='Invoice reporting is not available in this release. Select Projects, Jobs or Margin.';return;}
            options=await rpc('tms_report_options',{});
            if(!options.statuses?.[type]?.length)throw Object.assign(new Error('Report status contract is missing from database constraints'),{code:'VERSION'});
            fillLookup('client_id',options.clients);accounts();fillLookup('pm_id',[...options.pms,...(options.legacy_pms||[]).map(n=>({id:'legacy:'+n,label:n+' (legacy name)'}))]);fillLookup('resource_id',options.resources);
            for(const[key,list]of [['currency',options.currencies],['source_language',options.languages],['target_language',options.languages],['service',options.services]])el(key).innerHTML='<option value="">All</option>'+list.map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('');
            el('statuses').innerHTML=options.statuses[type].map(s=>`<label><input type="checkbox" value="${esc(s)}"> ${esc(s)}</label>`).join('');
            el('date_basis').innerHTML='<option value="project_date">Project date</option><option value="deadline">'+(type==='jobs'?'Job':type==='margin'?'Scoop':'Project')+' deadline (UTC)</option>';
            if(type==='jobs'){for(const id of ['margin_min','margin_max']){el(id).disabled=true;el(id).closest('.field').hidden=true;}for(const o of [...el('sort').options])if(['profit','margin','client_value'].includes(o.value))o.remove();}
            if(type!=='jobs')el('group_by').querySelector('[value="resource"]').remove();
            document.querySelector(`.tabs-bar a[href*="type=${type}"]`)?.classList.add('active');
            el('filterHelp').textContent='Type to select a specific record. Financial sorting requires one currency. Legacy PM names cannot distinguish people with identical names.';
            ready=true;fromUrl();restore();displayState();await load();
        }catch(e){ready=false;showError(e);}finally{busy=false;controls();}
    }
    el('retryReport').onclick=()=>ready?load():start();start();
}
function toggleSub(id,item){const open=document.getElementById(id).classList.toggle('open');item.classList.toggle('open',open);}
