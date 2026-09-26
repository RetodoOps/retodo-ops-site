/* Update 059. Read-only, RLS-bound reporting; monetary totals never mix currencies. */
const ReportUI = (() => {
    const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const number = value => value == null ? '—' : Number(value).toLocaleString('en-GB', {minimumFractionDigits:2,maximumFractionDigits:2});
    const costs = row => Object.entries(row.costs || {}).map(([currency,amount]) => `${currency} ${number(amount)}`).join('; ') || '—';
    function warnings(row, type) {
        const messages = [];
        if (row.unknown_cost_count > 0) messages.push(`${row.unknown_cost_count} unknown cost(s)`);
        if (row.po_warning_count > 0) messages.push('PO conflict or missing snapshot');
        if (row.currency_warning_count > 0) messages.push('Incompatible or missing currency');
        if (row.unallocated_job_count > 0) messages.push('Jobs without a Scoop');
        if (type !== 'jobs' && row.job_count === 0) messages.push('No Jobs — cost incomplete');
        if (type === 'projects' && row.scoop_count === 0) messages.push('No Scoops — value unavailable');
        if (row.empty_scoop_count > 0) messages.push('Scoop without Jobs');
        if (row.estimate_count > 0) messages.push(`${row.estimate_count} estimated cost(s)`);
        if (row.excluded_job_count > 0) messages.push(`${row.excluded_job_count} cancelled Job(s) excluded`);
        return messages.join('; ');
    }
    function csvCell(value) {
        // Finite numbers stay numeric, including negative profit. Only text needs formula protection.
        if (typeof value === 'number' && Number.isFinite(value)) return String(value);
        let text = String(value ?? '');
        if (/^[\s\u0000-\u001f]*[=+\-@]/u.test(text) || /^[\t\r\n]/u.test(text)) text = "'" + text;
        return '"' + text.replaceAll('"','""') + '"';
    }
    function csv(data) {
        const type = data.report_type;
        const common = ['id','project_id','project_number','name','project_name','client','account','pm','status','date'];
        const fields = type === 'jobs'
            ? [...common,'scoop_id','scoop_number','deadline','service','source_language','target_language','resource','quantity','unit','currency','cost_basis','po_id','po_number','po_version']
            : [...common,...(type==='margin'?['source_language','target_language','deadline']:[]),'currency','client_value','profit','margin','scoop_count','job_count','estimate_count','unknown_cost_count','excluded_job_count'];
        const currencies = [...new Set(data.rows.flatMap(row=>Object.keys(row.costs||{})))].sort();
        const lines = [['Report',type],['Generated at',data.generated_at],['Date basis',data.date_basis],['Filters',JSON.stringify(data.filters)],['Total rows',data.total_count],['Currency conversion','None'],[],[...fields,...currencies.map(c=>'supplier_cost_'+c),'warnings']];
        for(const row of data.rows) lines.push([...fields.map(key=>row[key]),...currencies.map(c=>row.costs?.[c]),warnings(row,type)]);
        lines.push([],['Summary currency','Client value','Known supplier cost','Profit','Margin %','Incomplete rows','Estimated costs']);
        for(const s of data.summary_by_currency) lines.push([s.currency,s.client_value,s.supplier_cost,s.profit,s.margin,s.incomplete_rows,s.estimate_count]);
        if(data.groups?.length) {
            lines.push([],['Group','Currency','Rows','Client value','Known supplier cost','Profit','Margin %','Rows needing attention','Rows with estimates']);
            for(const s of data.groups) lines.push([s.label,s.currency,s.row_count,s.client_value,s.supplier_cost,s.profit,s.margin,s.issue_count,s.estimate_count]);
        }
        return '\ufeff'+lines.map(line=>line.map(csvCell).join(',')).join('\r\n');
    }
    return {escape,number,costs,warnings,csvCell,csv};
})();
if(typeof module!=='undefined') module.exports=ReportUI;
if(typeof document!=='undefined') {
    const el=id=>document.getElementById(id);
    const {escape:esc,number:num,costs,warnings}=ReportUI;
    let type=new URLSearchParams(location.search).get('type')||'projects';
    let offset=0,generation=0,current=null,busy=false,dirty=false,choices=null;
    let applied={filters:{},sort:'name',desc:false};
    const relationSources={client:'clients',account:'accounts',pm:'managers',resource:'resources'};
    const relationLabel=r=>`${r.name||r.internal_number||'Unnamed'} · ${r.id}`;
    const selectedId=key=>(choices?.[relationSources[key]]||[]).find(r=>relationLabel(r)===el(key).value)?.id;
    function controls(){
        el('previousPage').disabled=busy||dirty||!current||offset===0;
        el('nextPage').disabled=busy||dirty||!current||current.next_offset==null;
        el('exportReport').disabled=busy||dirty||!current||!current.total_count;
        el('applyReport').disabled=busy||!choices;
        el('filterState').textContent=dirty?'Filters changed · select View report':'';
    }
    function changed(){dirty=true;controls();}
    function relationOptions(){
        const clientId=selectedId('client');
        for(const key of Object.keys(relationSources)) {
            const rows=(choices[relationSources[key]]||[]).filter(r=>key!=='account'||!clientId||r.client_id===clientId);
            el(key+'Options').innerHTML=rows.map(r=>`<option value="${esc(relationLabel(r))}"></option>`).join('');
        }
    }
    function readFilters(){
        const filters=Object.fromEntries([...new FormData(el('reportFilters'))].filter(([,v])=>v!==''));
        filters.statuses=[...document.querySelectorAll('#statusOptions input:checked')].map(i=>i.value);
        filters.group_by=el('group_by').value;
        for(const key of Object.keys(relationSources)) {
            if(key==='resource'&&type!=='jobs') continue;
            if(el(key).value.trim()) {
                const id=selectedId(key);
                if(!id) throw new Error(`Choose ${key==='pm'?'a project manager':'a '+key} from the suggestions, or clear the field.`);
                filters[key+'_id']=id;
            }
        }
        if(filters.client_id&&filters.account_id&&!choices.accounts.some(r=>r.id===filters.account_id&&r.client_id===filters.client_id)) throw new Error('Choose an account belonging to the selected client.');
        if(filters.from&&filters.to&&filters.from>filters.to) throw new Error('From date must be on or before Through date.');
        if(filters.margin_min!=null&&filters.margin_max!=null&&Number(filters.margin_min)>Number(filters.margin_max)) throw new Error('Minimum margin must be at most the maximum.');
        if(['client_value','cost','profit'].includes(el('sort').value)&&!filters.currency) throw new Error('Choose a currency before sorting monetary values.');
        return {filters,sort:el('sort').value,desc:el('direction').value==='desc'};
    }
    function writeURL(){
        const p=new URLSearchParams({type});
        for(const [key,value] of Object.entries(applied.filters)) {
            if(Array.isArray(value)) value.forEach(v=>p.append('status',v));
            else if(value!==''&&value!=='all'&&value!=='none') p.set(key,value);
        }
        p.set('sort',applied.sort);if(applied.desc)p.set('desc','1');
        history.replaceState(null,'','reports.html?'+p);
        document.querySelectorAll('[data-report-type]').forEach(a=>{
            const target=a.dataset.reportType,q=new URLSearchParams(p);q.set('type',target);q.delete('status');
            q.delete('group_by');q.delete('sort');q.delete('desc');
            if(target!=='jobs')q.delete('resource_id');
            if(target==='jobs'){q.delete('margin_min');q.delete('margin_max');}
            a.href='reports.html?'+q;
        });
    }
    function restore(){
        const p=new URLSearchParams(location.search);
        for(const control of el('reportFilters').elements){
            if(control.tagName==='SELECT')control.selectedIndex=0;
            else if(control.type==='checkbox')control.checked=false;
            else if(control.tagName==='INPUT')control.value='';
        }
        el('date_basis').value=type==='jobs'?'deadline':'project';
        for(const control of el('reportFilters').elements) if(control.name&&p.has(control.name)) control.value=p.get(control.name);
        for(const key of Object.keys(relationSources)) {
            const row=(choices[relationSources[key]]||[]).find(r=>r.id===p.get(key+'_id'));
            el(key).value=row?relationLabel(row):'';
        }
        const statuses=p.getAll('status');
        document.querySelectorAll('#statusOptions input').forEach(i=>i.checked=statuses.includes(i.value));
        for(const key of ['sort','group_by']) {
            const value=p.get(key)|| (key==='sort'?'name':'none');
            el(key).value=[...el(key).options].some(o=>o.value===value&&!o.disabled)?value:(key==='sort'?'name':'none');
        }
        el('direction').value=p.get('desc')==='1'?'desc':'asc';
        el('period').value=el('from').value||el('to').value?'custom':'all';
        el('advancedFilters').open=['source_language','target_language','service','issue','cost_basis','margin_min','margin_max'].some(k=>p.has(k));
        relationOptions();statusLabel();el('statusSummary').parentElement.open=false;
    }
    function statusLabel(){const n=document.querySelectorAll('#statusOptions input:checked').length;el('statusSummary').textContent=n?`${n} status${n===1?'':'es'} selected`:'All statuses';}
    async function query(start,limit){
        const {data,error}=await _sb.rpc('tms_report',{p_type:type,p_filters:applied.filters,p_offset:start,p_limit:limit,p_sort:applied.sort,p_desc:applied.desc});
        if(error)throw error;
        if(data?.api_version!=='059') throw {code:'REPORT_VERSION',message:'The reporting database needs Update 059.'};
        return data;
    }
    function errorView(error){
        el('reportError').hidden=false;
        const setup=['PGRST202','42883','REPORT_VERSION'].includes(error.code);
        el('errorTitle').textContent=setup?'Reports need a database update':'Unable to load report';
        el('errorText').textContent=setup?'Ask your administrator to apply the reporting migration included with Update 059, then retry.':error.code==='42501'?'Your account does not have access to this report. Contact your administrator.':error.message||'Please retry.';
        el('errorDetails').textContent=[error.code,error.message,error.details,error.hint].filter(Boolean).join('\n');
    }
    const metric=(label,value)=>`<div class="report-metric"><dt>${esc(label)}</dt><dd class="${Number(value)<0?'report-negative':''}">${num(value)}</dd></div>`;
    function render(data){
        el('reportOverview').hidden=false;el('reportResults').hidden=false;
        el('reportBasis').textContent=`${data.date_basis} · ${type==='jobs'?'One row per Job; no client revenue allocation.':type==='margin'?'One row per Scoop; full Scoop costs.':'One row per Project; full Project totals.'} Date bounds are inclusive.`;
        el('reportGenerated').textContent='Updated '+new Date(data.generated_at).toLocaleString('en-GB');
        el('reportHealth').innerHTML=`<span><strong>${data.total_count}</strong> matching ${type==='margin'?'Scoops':type} · ${data.project_count} Projects</span><button type="button" data-quality="blocked" class="${data.warning_rows?'has-issues':''}"><strong>${data.warning_rows}</strong> need attention</button><button type="button" data-quality="estimates"><strong>${data.estimate_rows}</strong> include estimates</button>`;
        el('reportHealth').querySelectorAll('button').forEach(b=>b.onclick=()=>{el('issue').value=b.dataset.quality;el('advancedFilters').open=true;apply();});
        el('reportSummary').innerHTML=data.summary_by_currency.map(s=>`<section class="report-currency-card"><h3 class="report-currency-title">${esc(s.currency)}</h3><dl class="report-currency-values">${type!=='jobs'?metric('Client value',s.client_value):''}${metric('Known supplier cost',s.supplier_cost)}${type!=='jobs'?metric(s.estimate_count?'Estimated profit':'Profit',s.profit)+`<div class="report-metric is-margin"><dt>Margin</dt><dd>${s.margin==null?'—':num(s.margin)+'%'}</dd></div>`:''}</dl>${s.incomplete_rows>0&&type!=='jobs'?'<p class="report-note">Profit / margin unavailable: incomplete or incompatible data.</p>':''}${s.estimate_count>0?'<p class="report-note">Includes saved cost estimates.</p>':''}</section>`).join('')||'<p class="report-empty">No matching results. Try changing the filters.</p>';
        el('activeFilters').innerHTML=Object.entries(applied.filters).filter(([,v])=>Array.isArray(v)?v.length:v!==''&&!['all','none','active'].includes(v)).map(([k,v])=>`<span class="report-chip">${esc(k.replaceAll('_',' '))}: ${esc(Array.isArray(v)?v.join(', '):k.endsWith('_id')?el(k.slice(0,-3))?.value||v:v)}</span>`).join('');
        const headers=type==='jobs'?['Job / Project','Client / Account','Status / Date','Service / Languages','Resource','Quantity','Supplier cost / PO','Data quality']:['Project / Scoop','Client / Account','PM / Date','Status',...(type==='margin'?['Languages']:[]),'Jobs','Client value','Supplier costs','Profit / Margin','Data quality'];
        el('reportTable').querySelector('thead').innerHTML='<tr>'+headers.map(h=>`<th scope="col">${esc(h)}</th>`).join('')+'</tr>';
        el('reportTable').querySelector('tbody').innerHTML=data.rows.map(row=>{
            const href=type==='jobs'?`job.html?id=${encodeURIComponent(row.id)}`:`project.html?id=${encodeURIComponent(row.project_id)}${type==='margin'?'&scoop='+encodeURIComponent(row.id):''}`;
            const identity=`<div class="report-identity"><a href="${href}">${esc(row.name)}</a><small>${type!=='projects'?`<a href="project.html?id=${encodeURIComponent(row.project_id)}">${esc(row.project_name||row.project_number)}</a>`:esc(row.project_number)}</small></div>`;
            const client=`${esc(row.client||'—')}<small>${esc(row.account||'')}</small>`;
            const status=`<span class="report-status ${row.status==='Cancelled'?'is-cancelled':['Approved','Delivered','Delivered to Client'].includes(row.status)?'is-done':''}">${esc(row.status)}</span>`;
            const note=`<div class="report-quality"><span class="${row.blocking_issues?.length?'':row.estimate_count?'is-info':'is-clean'}">${esc(warnings(row,type)||'Complete')}</span></div>`;
            const language=`${esc(row.source_language||'—')} → ${esc(row.target_language||'—')}`;
            const cells=type==='jobs'?[identity,client,`${status}<small>${esc(row.date||'No date')}</small>`,`${esc(row.service||'—')}<small>${language}</small>`,row.resource_id?`<a href="resource.html?id=${encodeURIComponent(row.resource_id)}">${esc(row.resource||'Resource')}</a>`:'Unassigned',`${esc(row.quantity??'—')} ${esc(row.unit||'')}`,`${esc(costs(row))}<small>${esc(row.cost_basis)}${row.po_number?` · <a href="job.html?id=${encodeURIComponent(row.id)}">${esc(row.po_number)} v${esc(row.po_version)} (Job PO)</a>`:''}</small>`,note]:[identity,client,`${esc(row.pm||'—')}<small>${esc(row.date||'No date')}</small>`,status,...(type==='margin'?[language]:[]),esc(row.job_count),`${esc(row.currency||'')} ${num(row.client_value)}`,esc(costs(row)),`<span class="${row.profit<0?'report-negative':''}">${num(row.profit)}</span><small>${row.margin==null?'Unavailable':num(row.margin)+'%'}${row.estimate_count?' · estimated':''}</small>`,note];
            return '<tr>'+cells.map(c=>`<td>${c}</td>`).join('')+'</tr>';
        }).join('')||`<tr><td colspan="${headers.length}" class="report-empty">No matching results. Try changing the filters.</td></tr>`;
        el('resultsTitle').textContent=type==='jobs'?'Job details':type==='margin'?'Scoop profitability':'Project details';
        el('reportCount').textContent=data.total_count?`${offset+1}–${offset+data.rows.length} of ${data.total_count}`:'0 results';
        el('reportPage').textContent=`Page ${Math.floor(offset/50)+1} of ${Math.max(1,Math.ceil(data.total_count/50))} · Totals cover every matching row`;
        el('reportGroups').hidden=!data.groups?.length;
        if(data.groups?.length){
            el('groupTitle').textContent='Summary by '+el('group_by').selectedOptions[0].text.toLowerCase();
            const keys=['label','currency','row_count',...(type==='jobs'?[]:['client_value']),'supplier_cost',...(type==='jobs'?[]:['profit','margin']),'issue_count','estimate_count'];
            const labels={label:'Group',currency:'Currency',row_count:'Rows',client_value:'Client value',supplier_cost:'Known supplier cost',profit:'Profit',margin:'Margin %',issue_count:'Need attention',estimate_count:'With estimates'};
            el('groupTable').querySelector('thead').innerHTML='<tr>'+keys.map(k=>`<th scope="col">${labels[k]}</th>`).join('')+'</tr>';
            el('groupTable').querySelector('tbody').innerHTML=data.groups.map(g=>'<tr>'+keys.map(k=>`<td>${['label','currency'].includes(k)?esc(g[k]):num(g[k])}</td>`).join('')+'</tr>').join('');
        }
    }
    async function load(){
        const request=++generation;busy=true;current=null;controls();
        el('reportError').hidden=true;el('reportMessage').textContent='Loading report…';
        for(const id of ['reportOverview','reportResults','reportGroups'])el(id).hidden=true;
        try {const data=await query(offset,50);if(request!==generation)return;current=data;render(data);el('reportMessage').textContent='';}
        catch(error){if(request===generation){errorView(error);el('reportMessage').textContent='';}}
        finally {if(request===generation){busy=false;controls();}}
    }
    function apply(){
        try{applied=readFilters();el('statusSummary').parentElement.open=false;dirty=false;offset=0;writeURL();load();}
        catch(error){el('reportMessage').textContent=error.message;changed();}
    }
    async function exportReport(){
        busy=true;controls();const request=++generation;
        el('reportMessage').textContent='Preparing complete CSV…';
        try {
            const data=await query(0,10000);if(request!==generation)return;
            if(data.total_count>10000||data.rows.length!==data.total_count)throw new Error('Export is limited to 10,000 rows. Narrow the filters and try again.');
            const url=URL.createObjectURL(new Blob([ReportUI.csv(data)],{type:'text/csv;charset=utf-8'}));
            const a=document.createElement('a');a.href=url;a.download=`retodo-${type}-${new Date().toISOString().slice(0,10)}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
            el('reportMessage').textContent=`Exported all ${data.total_count} matching rows from a fresh snapshot.`;
        }catch(error){if(request===generation)el('reportMessage').textContent=error.message||'CSV export failed.';}
        finally{if(request===generation){busy=false;controls();}}
    }
    function periodDates(){
        const now=new Date(),y=now.getUTCFullYear(),m=now.getUTCMonth(),period=el('period').value;
        const date=(year,month,day)=>new Date(Date.UTC(year,month,day)).toISOString().slice(0,10);
        if(period==='all'){el('from').value='';el('to').value='';}
        if(period==='month'){el('from').value=date(y,m,1);el('to').value=date(y,m+1,0);}
        if(period==='last_month'){el('from').value=date(y,m-1,1);el('to').value=date(y,m,0);}
        if(period==='quarter'){const q=Math.floor(m/3)*3;el('from').value=date(y,q,1);el('to').value=date(y,q+3,0);}
        if(period==='year'){el('from').value=date(y,0,1);el('to').value=date(y,11,31);}
    }
    async function setup(){
        busy=true;controls();el('reportError').hidden=true;el('reportMessage').textContent='Loading filter choices…';
        try{
            const {data,error}=await _sb.rpc('tms_report_options_059');if(error)throw error;
            if(data?.api_version!=='059')throw {code:'REPORT_VERSION',message:'Update 059 reporting choices unavailable.'};
            choices=data;
            for(const [key,source] of [['currency','currencies'],['source_language','languages'],['target_language','languages'],['service','services']])el(key).innerHTML=el(key).options[0].outerHTML+(data[source]||[]).map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('');
            el('statusOptions').innerHTML=data[type==='jobs'?'job_statuses':'project_statuses'].map(s=>`<label><input type="checkbox" value="${esc(s)}">${esc(s)}</label>`).join('');
            restore();busy=false;apply();
        }catch(error){errorView(error);busy=false;el('reportMessage').textContent='';controls();}
    }
    (async()=>{
        if(!await requireAuth())return;
        if(!['projects','jobs','margin'].includes(type)){el('reportFilters').hidden=true;el('reportMessage').textContent='Invoice reporting is not available in this release. Select Projects, Jobs or Margin.';return;}
        document.querySelector(`[data-report-type="${type}"]`).classList.add('active');
        el('resourceField').hidden=type!=='jobs';
        document.querySelectorAll('.report-margin-filter').forEach(w=>{w.hidden=type==='jobs';w.querySelector('input').disabled=type==='jobs';});
        for(const option of el('sort').options)option.disabled=type==='jobs'&&['client_value','profit','margin'].includes(option.value);
        for(const option of el('group_by').options)option.disabled=(type!=='jobs'&&['resource','service'].includes(option.value))||(type==='projects'&&option.value==='language');
        el('reportFilters').addEventListener('submit',e=>{e.preventDefault();apply();});
        el('reportFilters').addEventListener('input',()=>{statusLabel();changed();});
        el('reportFilters').addEventListener('change',()=>{statusLabel();changed();});
        el('reportFilters').addEventListener('reset',e=>{
            e.preventDefault();queueMicrotask(()=>{history.replaceState(null,'','reports.html?type='+type);restore();apply();});
        });
        el('client').addEventListener('input',()=>{el('account').value='';if(choices)relationOptions();});
        el('period').addEventListener('change',periodDates);
        for(const key of ['from','to'])el(key).addEventListener('input',()=>el('period').value='custom');
        for(const key of ['sort','direction','group_by'])el(key).addEventListener('change',apply);
        el('previousPage').onclick=()=>{offset=Math.max(0,offset-50);load();};
        el('nextPage').onclick=()=>{offset=current.next_offset;load();};
        el('exportReport').onclick=exportReport;
        el('retryReport').onclick=()=>choices?load():setup();
        await setup();
    })();
}
function toggleSub(id,item){const open=document.getElementById(id).classList.toggle('open');item.classList.toggle('open',open);}
