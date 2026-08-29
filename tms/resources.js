let page = 0;
const pageSize = 50;
let totalRows = 0;
let resourceType = 'external';
let searchTimer;

const escapeHtml = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
const initialsFromName = name => String(name||'').trim().split(/[\s-]+/).filter(Boolean).map(part=>Array.from(part)[0]||'').join('').toLocaleUpperCase().slice(0,12);
function toggleSub(id,item){document.getElementById(id).classList.toggle('open');item.classList.toggle('open')}
function formatDate(value){return value?new Intl.DateTimeFormat('en-GB',{month:'short',year:'numeric'}).format(new Date(`${value}T00:00:00`)):'—'}
function chips(items,limit=3){const values=(items||[]).filter(Boolean);if(!values.length)return '<span class="muted">—</span>';const shown=values.slice(0,limit).map(item=>`<span class="mini-chip">${escapeHtml(item)}</span>`).join('');return `${shown}${values.length>limit?`<span class="mini-chip more-chip">+${values.length-limit}</span>`:''}`}
function eligibilityClass(value){if(value==='Eligible')return 'pill pill-green';if(['Restricted','Review'].includes(value))return 'pill pill-amber';return 'pill pill-red'}
function availabilityClass(value){if(value==='Available')return 'pill pill-green';if(value==='Limited')return 'pill pill-amber';if(value==='Unavailable')return 'pill pill-red';return 'pill'}

function filterValue(id){return document.getElementById(id).value||null}
function rpcFilters(){return {p_search:filterValue('resourceSearch'),p_source_language:filterValue('sourceFilter'),p_target_language:filterValue('targetFilter'),p_service_type:filterValue('serviceFilter'),p_specialization_id:filterValue('specializationFilter'),p_classification:filterValue('classificationFilter'),p_eligibility:filterValue('eligibilityFilter'),p_availability:filterValue('availabilityFilter'),p_only_approved_capabilities:document.getElementById('approvedOnly').checked,p_resource_type:resourceType,p_limit:pageSize,p_offset:page*pageSize}}

async function loadResources(){
    const body=document.getElementById('resourcesTbody');body.innerHTML='<tr class="state-row"><td colspan="9">Loading Resources…</td></tr>';
    const {data,error}=await _sb.rpc('search_resources',rpcFilters());
    if(error){body.innerHTML=`<tr class="state-row"><td colspan="9">${escapeHtml(error.message)}</td></tr>`;return}
    const rows=data||[];totalRows=Number(rows[0]?.total_count||0);document.getElementById('resourceCount').textContent=`${totalRows.toLocaleString('en-GB')} resource${totalRows===1?'':'s'}`;
    if(!rows.length){body.innerHTML='<tr class="state-row"><td colspan="9">No matching Resources.</td></tr>'}else body.innerHTML=rows.map(row=>`<tr class="clickable-row" data-id="${row.id}">
        <td><span class="code-badge">${escapeHtml(row.internal_number)}</span></td>
        <td><div class="customer-main">${escapeHtml(row.legal_name||row.company_name||'Unnamed resource')}</div>${row.company_name&&row.company_name!==row.legal_name?`<div class="customer-sub">${escapeHtml(row.company_name)}</div>`:''}${row.linkedin_url?`<a class="resource-linkedin" href="${escapeHtml(row.linkedin_url)}" target="_blank" rel="noopener">LinkedIn ↗</a>`:''}</td>
        <td><div>${escapeHtml(row.classification)}</div><div class="customer-sub"><span class="${eligibilityClass(row.eligibility_status)}">${escapeHtml(row.eligibility_status)}</span>${row.assignment_approved?' · Assignment approved':''}</div></td>
        <td><div class="resource-pairs"><span>${chips(row.source_languages,2)}</span><strong>→</strong><span>${chips(row.target_languages,3)}</span></div></td>
        <td><div class="chip-list">${chips(row.services,3)}</div></td><td><div class="chip-list">${chips(row.specializations,3)}</div></td>
        <td>${escapeHtml(row.country_of_residence||'—')}</td><td><span class="${availabilityClass(row.availability_status)}">${escapeHtml(row.availability_status)}</span></td><td>${formatDate(row.last_recorded_job)}</td>
    </tr>`).join('');
    body.querySelectorAll('tr[data-id]').forEach(row=>row.addEventListener('click',event=>{if(event.target.closest('a'))return;location.href=`resource.html?id=${encodeURIComponent(row.dataset.id)}`}));
    document.getElementById('pageStatus').textContent=totalRows?`${page*pageSize+1}–${Math.min((page+1)*pageSize,totalRows)} of ${totalRows.toLocaleString('en-GB')}`:'0 results';
    document.getElementById('previousPage').disabled=page===0;document.getElementById('nextPage').disabled=(page+1)*pageSize>=totalRows;
}

async function loadFilterOptions(){
    const [{data,error},{data:specializations}]=await Promise.all([_sb.rpc('resource_filter_options'),_sb.from('specializations').select('id,name').eq('active',true).order('name')]);
    if(error)return;
    const add=(id,items)=>{const select=document.getElementById(id);(items||[]).forEach(value=>select.insertAdjacentHTML('beforeend',`<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`))};
    add('sourceFilter',data?.source_languages);add('targetFilter',data?.target_languages);add('serviceFilter',data?.services);
    (specializations||[]).forEach(spec=>document.getElementById('specializationFilter').insertAdjacentHTML('beforeend',`<option value="${spec.id}">${escapeHtml(spec.name)}</option>`));
}

function resetAndLoad(){page=0;loadResources()}
function changePage(delta){page=Math.max(0,page+delta);loadResources()}
function clearFilters(){['resourceSearch','sourceFilter','targetFilter','serviceFilter','specializationFilter','classificationFilter','eligibilityFilter','availabilityFilter'].forEach(id=>document.getElementById(id).value='');document.getElementById('approvedOnly').checked=false;resetAndLoad()}
function openCreateResource(){document.getElementById('resourceModal').classList.remove('hidden');document.getElementById('newResourceName').focus()}
function closeCreateResource(){document.getElementById('resourceModal').classList.add('hidden');document.getElementById('resourceCreateError').classList.add('hidden')}
async function createResource(){const errorEl=document.getElementById('resourceCreateError'),button=document.getElementById('createResourceBtn');const payload={resource_type:document.getElementById('newResourceType').value,legal_name:document.getElementById('newResourceName').value.trim()||null,company_name:document.getElementById('newResourceCompany').value.trim()||null,initials:document.getElementById('newResourceInitials').value.trim()||null,nationality:document.getElementById('newResourceNationality').value.trim()||null,country_of_residence:document.getElementById('newResourceCountry').value.trim()||null,email:document.getElementById('newResourceEmail').value.trim()||null,phone:document.getElementById('newResourcePhone').value.trim()||null,linkedin_url:document.getElementById('newResourceLinkedIn').value.trim()||null};if(!payload.legal_name&&!payload.company_name){errorEl.textContent='Enter a person or company name.';errorEl.classList.remove('hidden');return}button.disabled=true;button.textContent='Creating…';const {data,error}=await _sb.rpc('create_resource',{p_payload:payload});button.disabled=false;button.textContent='Create and open';if(error){errorEl.textContent=error.message;errorEl.classList.remove('hidden');return}location.href=`resource.html?id=${encodeURIComponent(data[0].created_resource_id)}`}

['sourceFilter','targetFilter','serviceFilter','specializationFilter','classificationFilter','eligibilityFilter','availabilityFilter','approvedOnly'].forEach(id=>document.getElementById(id).addEventListener('change',resetAndLoad));
document.getElementById('resourceSearch').addEventListener('input',()=>{clearTimeout(searchTimer);searchTimer=setTimeout(resetAndLoad,250)});
document.getElementById('newResourceName').addEventListener('input',event=>{document.getElementById('newResourceInitials').value=initialsFromName(event.target.value)});
(async()=>{const user=await requireAuth();if(!user)return;TMS_REF.installDatalists();resourceType=new URLSearchParams(location.search).get('type')==='internal'?'internal':'external';document.getElementById('moduleTitle').textContent=resourceType==='internal'?'Internal Resources':'External Resources';await loadFilterOptions();await loadResources()})();
