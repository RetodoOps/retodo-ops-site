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
        let text = String(value ?? '');
        if (/^[\s\u0000-\u001f]*[=+\-@]/u.test(text) || /^[\t\r\n]/u.test(text)) text = "'" + text;
        return '"' + text.replaceAll('"','""') + '"';
    }
    function csv(data) {
        const type = data.report_type;
        const fields = type === 'jobs'
            ? ['id','project_id','scoop_id','name','project_name','client','account','pm','status','date','deadline','service','source_language','target_language','resource','quantity','unit','cost_basis','po_id','po_number','po_version']
            : ['id','project_id','name','project_name','client','account','pm','status','date','currency','client_value','profit','margin','scoop_count','job_count','estimate_count','unknown_cost_count','excluded_job_count'];
        const lines = [ ['Report',type],['Generated at',data.generated_at],['Date basis',data.date_basis],['Filters',JSON.stringify(data.filters)],['Total rows',data.total_count],['Currency conversion','None'],[],[...fields,'costs_by_currency','warnings'] ];
        for (const row of data.rows) lines.push([...fields.map(key=>row[key]),JSON.stringify(row.costs || {}),warnings(row,type)]);
        lines.push([],['Summary currency','Client value','Supplier cost','Profit','Margin %','Incomplete rows','Estimated costs']);
        for (const s of data.summary_by_currency) lines.push([s.currency,s.client_value,s.supplier_cost,s.profit,s.margin,s.incomplete_rows,s.estimate_count]);
        return '\ufeff' + lines.map(line=>line.map(csvCell).join(',')).join('\r\n');
    }
    return {escape,number,costs,warnings,csvCell,csv};
})();
if (typeof module !== 'undefined') module.exports = ReportUI;
if (typeof document !== 'undefined') {
    let type = new URLSearchParams(location.search).get('type') || 'projects';
    let offset = 0, generation = 0, current = null, busy = false;
    let applied = {filters:{scope:'active'},sort:'name',desc:false};
    const el = id => document.getElementById(id);
    const {escape:esc,number:num,costs,warnings} = ReportUI;
    function controls() {
        el('previousPage').disabled = busy || !current || offset===0;
        el('nextPage').disabled = busy || !current || current.next_offset == null;
        el('exportReport').disabled = busy || !current || !current.total_count;
    }
    async function query(start,limit) {
        const {data,error} = await _sb.rpc('tms_report',{p_type:type,p_filters:applied.filters,p_offset:start,p_limit:limit,p_sort:applied.sort,p_desc:applied.desc});
        if (error) throw error;
        return data;
    }
    function render(data) {
        el('reportBasis').textContent = `${data.date_basis} · ${type === 'margin' ? 'One row per Scoop; client value counted once.' : type === 'projects' ? 'One row per Project; values from included Scoops and Jobs.' : 'One row per Job; no client value allocated to Jobs.'} Dates include both selected days.`;
        el('reportWarnings').textContent = `${data.warning_rows} row(s) need attention. Totals cover all ${data.total_count} matching rows across ${data.project_count} Project(s).`;
        el('reportSummary').innerHTML = data.summary_by_currency.map(s=>`<section class="section-card"><h2>${esc(s.currency)}</h2><dl>${type!=='jobs'?`<dt>Client value</dt><dd>${num(s.client_value)}</dd>`:''}<dt>Supplier cost (known)</dt><dd>${num(s.supplier_cost)}</dd>${type!=='jobs'?`<dt>${s.estimate_count>0?'Estimated profit':'Profit'}</dt><dd>${num(s.profit)}</dd><dt>Margin</dt><dd>${s.margin==null?'—':num(s.margin)+'%'}</dd>`:''}</dl>${s.incomplete_rows>0&&type!=='jobs'?'<p class="report-warning">Margin unavailable: incomplete or incompatible data.</p>':''}${s.estimate_count>0?'<p class="report-note">Includes saved cost estimates.</p>':''}</section>`).join('');
        const headers=type==='jobs'?['Job / Project','Client / Account','Status / Deadline (UTC)','Service / Languages','Resource','Quantity','Supplier cost / PO','Warnings']:['Project / Scoop','Client / Account','PM / Date','Status','Jobs','Client value','Supplier costs','Profit / Margin','Warnings'];
        el('reportTable').querySelector('thead').innerHTML='<tr>'+headers.map(h=>`<th scope="col">${esc(h)}</th>`).join('')+'</tr>';
        el('reportTable').querySelector('tbody').innerHTML=data.rows.length?data.rows.map(row=>{
            const href=type==='jobs'?`job.html?id=${encodeURIComponent(row.id)}`:`project.html?id=${encodeURIComponent(row.project_id)}${type==='margin'?'&scoop='+encodeURIComponent(row.id):''}`;
            const identity=`<a class="table-link" href="${href}">${esc(row.name)}</a>${row.project_name?`<small>${esc(row.project_name)}</small>`:''}`;
            const client=`${esc(row.client||'—')}<small>${esc(row.account||'')}</small>`;
            const note=`<span class="report-warning">${esc(warnings(row,type)||'—')}</span>`;
            const cells=type==='jobs'?[identity,client,`${esc(row.status)}<small>${esc(row.deadline?new Date(row.deadline).toISOString().replace('T',' ').slice(0,16):'No deadline')}</small>`,`${esc(row.service)}<small>${esc(row.source_language)} → ${esc(row.target_language)}</small>`,esc(row.resource||'Unassigned'),`${esc(row.quantity??'—')} ${esc(row.unit||'')}`,`${esc(costs(row))}<small>${esc(row.cost_basis)}${row.po_number?' · '+esc(row.po_number)+' v'+esc(row.po_version):''}</small>`,note]:[identity,client,`${esc(row.pm||'—')}<small>${esc(row.date||'')}</small>`,esc(row.status),esc(row.job_count),`<span class="report-money">${esc(row.currency)} ${num(row.client_value)}</span>`,esc(costs(row)),`${num(row.profit)}<small>${row.margin==null?'Unavailable':num(row.margin)+'%'}${row.estimate_count>0?' · estimated':''}</small>`,note];
            return '<tr>'+cells.map(c=>`<td>${c}</td>`).join('')+'</tr>';
        }).join(''):`<tr><td colspan="${headers.length}">No matching results. Try changing the filters.</td></tr>`;
        el('reportCount').textContent=data.total_count?`${offset+1}–${offset+data.rows.length} of ${data.total_count}`:'0 results';
    }
    async function load() {
        const request=++generation; busy=true; current=null; controls();
        el('reportMessage').textContent='Loading report…';
        el('reportSummary').replaceChildren(); el('reportWarnings').textContent='';
        el('reportTable').querySelector('tbody').replaceChildren();el('reportCount').textContent='';
        try {
            const data=await query(offset,50);
            if(request!==generation) return;
            current=data;render(data);el('reportMessage').textContent=`Generated ${new Date(data.generated_at).toLocaleString('en-GB')} · UTC date filters`;
        } catch(error) {
            if(request!==generation) return;
            el('reportMessage').textContent=['PGRST202','42883'].includes(error.code)?'Reports are not available yet. The reporting database migration must be applied.':`Unable to load report: ${error.message||'Please try again.'}`;
        } finally {if(request===generation){busy=false;controls();}}
    }
    async function exportReport() {
        busy=true;controls(); const request=generation;
        el('reportMessage').textContent='Preparing CSV…';
        try {
            // One request = one DB snapshot. Never silently export a partial dataset.
            const data=await query(0,10000);
            if(request!==generation) return;
            if(data.total_count>10000 || data.rows.length!==data.total_count) throw new Error('Export is limited to 10,000 rows. Narrow the filters and try again.');
            const url=URL.createObjectURL(new Blob([ReportUI.csv(data)],{type:'text/csv;charset=utf-8'}));
            const link=document.createElement('a');link.href=url;link.download=`retodo-${type}-${new Date().toISOString().slice(0,10)}.csv`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
            el('reportMessage').textContent=`Exported ${data.total_count} rows from a fresh snapshot (${data.generated_at}).`;
        } catch(error) {if(request===generation) el('reportMessage').textContent=error.message||'CSV export failed.';}
        finally {if(request===generation){busy=false;controls();}}
    }
    (async()=>{
        if(!await requireAuth()) return;
        if(!['projects','jobs','margin'].includes(type)) {
            el('reportFilters').hidden=true;
            el('reportMessage').textContent='Invoice reporting is not available in this release. Select Projects, Jobs or Margin.';return;
        }
        document.querySelector(`.tabs-bar a[href="reports.html?type=${type}"]`).classList.add('active');
        const statuses=type==='jobs'?['Unassigned','Offered','Assigned','In Progress','Delivered','Revision Required','Approved','Declined','Cancelled']:['Assign','Ongoing','Ready for QA','Waiting','Ready to Deliver','Delivered to Client','Approved','Cancelled'];
        el('status').insertAdjacentHTML('beforeend',statuses.map(s=>`<option>${esc(s)}</option>`).join(''));
        el('reportFilters').addEventListener('submit',event=>{
            event.preventDefault();const filters=Object.fromEntries(new FormData(event.target));
            if(filters.from&&filters.to&&filters.from>filters.to){el('reportMessage').textContent='From date must be on or before To date.';return;}
            applied={filters,sort:el('sort').value,desc:el('direction').value==='desc'};offset=0;load();
        });
        el('reportFilters').addEventListener('reset',()=>{applied={filters:{scope:'active'},sort:'name',desc:false};offset=0;load();});
        el('previousPage').onclick=()=>{offset=Math.max(0,offset-50);load();};
        el('nextPage').onclick=()=>{offset=current.next_offset;load();};
        el('exportReport').onclick=exportReport;
        await load();
    })();
}

function toggleSub(id,item) {
    const sub=document.getElementById(id);
    const open=sub.classList.toggle('open');
    item.classList.toggle('open',open);
}
