// ── Language → flag emoji ──────────────────────────────────────────────────
const LANG_FLAGS = {
    'English (US)': '🇺🇸', 'English (UK)': '🇬🇧', 'English': '🇬🇧',
    'Bulgarian': '🇧🇬', 'Swedish': '🇸🇪', 'Danish': '🇩🇰',
    'Finnish': '🇫🇮', 'Norwegian (Bokmål)': '🇳🇴', 'Norwegian': '🇳🇴',
    'German': '🇩🇪', 'French': '🇫🇷', 'Spanish': '🇪🇸', 'Italian': '🇮🇹',
    'Dutch': '🇳🇱', 'Polish': '🇵🇱', 'Portuguese': '🇵🇹', 'Russian': '🇷🇺',
    'Chinese (Simplified)': '🇨🇳', 'Chinese (Traditional)': '🇹🇼',
    'Japanese': '🇯🇵', 'Korean': '🇰🇷', 'Arabic': '🇸🇦', 'Turkish': '🇹🇷',
    'Czech': '🇨🇿', 'Hungarian': '🇭🇺', 'Romanian': '🇷🇴',
    'Slovak': '🇸🇰', 'Ukrainian': '🇺🇦', 'Greek': '🇬🇷',
    'Hebrew': '🇮🇱', 'Thai': '🇹🇭', 'Vietnamese': '🇻🇳',
};

// ── Tab definitions ────────────────────────────────────────────────────────
const TABS = [
    { key: 'due_today',    label: 'Due Today' },
    { key: 'assign',       label: 'Assign' },
    { key: 'ongoing',      label: 'Ongoing' },
    { key: 'ready_for_qa', label: 'Ready for QA' },
    { key: 'waiting',      label: 'Waiting' },
    { key: 'ready_delivery', label: 'Ready to Deliver' },
    { key: 'delivered',    label: 'Delivered to Client' },
    { key: 'due_tomorrow', label: 'Due Tomorrow' },
    { key: 'upcoming',     label: 'Upcoming' },
    { key: 'approved',     label: 'Approved' },
    { key: 'all',          label: 'All' },
    { key: 'missing_po',   label: 'Missing PO' },
];

let allProjects  = [];
let activeTab    = 'due_today';
let searchQuery  = '';
const escapeHtml = value => String(value ?? '')
    .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
    .replaceAll('"','&quot;').replaceAll("'",'&#039;');

// ── Date helpers ───────────────────────────────────────────────────────────
function sameDay(dateStr, offset = 0) {
    if (!dateStr) return false;
    const d = new Date(dateStr);
    const t = new Date();
    t.setDate(t.getDate() + offset);
    return d.getFullYear() === t.getFullYear()
        && d.getMonth()    === t.getMonth()
        && d.getDate()     === t.getDate();
}
const isToday    = d => sameDay(d, 0);
const isTomorrow = d => sameDay(d, 1);
const isOverdue  = d => d && new Date(d) < new Date() && !isToday(d);

function fmtDate(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    const dd   = String(d.getDate()).padStart(2,'0');
    const mm   = String(d.getMonth()+1).padStart(2,'0');
    const yyyy = d.getFullYear();
    const hh   = String(d.getHours()).padStart(2,'0');
    const min  = String(d.getMinutes()).padStart(2,'0');
    return `${dd}.${mm}.${yyyy} | ${hh}:${min}`;
}

// ── Filter helpers ─────────────────────────────────────────────────────────
function filterByTab(projects, tab) {
    switch (tab) {
        case 'due_today':    return projects.filter(p => isToday(p.deadline));
        case 'assign':       return projects.filter(p => p.status === 'Assign');
        case 'ongoing':      return projects.filter(p => p.status === 'Ongoing');
        case 'ready_for_qa': return projects.filter(p => p.status === 'Ready for QA');
        case 'waiting':      return projects.filter(p => p.status === 'Waiting');
        case 'ready_delivery': return projects.filter(p => p.status === 'Ready to Deliver');
        case 'delivered':    return projects.filter(p => p.status === 'Delivered to Client');
        case 'due_tomorrow': return projects.filter(p => isTomorrow(p.deadline));
        case 'upcoming':     return projects.filter(p => p.upcoming);
        case 'approved':     return projects.filter(p => p.status === 'Approved');
        case 'missing_po':   return projects.filter(p => p.missing_po);
        default:             return projects;
    }
}

function filterBySearch(projects, q) {
    if (!q) return projects;
    const lc = q.toLowerCase();
    return projects.filter(p =>
        (p.display_name     || p.project_number || '').toLowerCase().includes(lc) ||
        (p.clients?.name     || '').toLowerCase().includes(lc) ||
        (p.client_accounts?.name || '').toLowerCase().includes(lc) ||
        (p.client_reference  || '').toLowerCase().includes(lc) ||
        (p.email_reference   || '').toLowerCase().includes(lc) ||
        (p.project_manager   || '').toLowerCase().includes(lc) ||
        (p.qa_specialist     || '').toLowerCase().includes(lc) ||
        (p.linguist          || '').toLowerCase().includes(lc) ||
        (p.project_type      || '').toLowerCase().includes(lc) ||
        (p.status            || '').toLowerCase().includes(lc)
    );
}

// ── Render tabs ────────────────────────────────────────────────────────────
function renderTabs() {
    const bar = document.getElementById('tabsBar');
    bar.innerHTML = TABS.map(t => {
        const count  = filterByTab(allProjects, t.key).length;
        const active = t.key === activeTab ? 'active' : '';
        return `<button class="tab ${active}" data-tab="${t.key}">
            ${t.label}
            <span class="tab-badge">${count}</span>
        </button>`;
    }).join('');

    bar.querySelectorAll('.tab').forEach(btn =>
        btn.addEventListener('click', () => {
            activeTab = btn.dataset.tab;
            renderTabs();
            renderTable();
        })
    );
}

// ── Render table ───────────────────────────────────────────────────────────
function renderTable() {
    const tbody = document.getElementById('projectsTbody');
    let rows = filterBySearch(filterByTab(allProjects, activeTab), searchQuery);

    if (!rows.length) {
        tbody.innerHTML = `<tr class="state-row"><td colspan="15">No projects found.</td></tr>`;
        return;
    }

    tbody.innerHTML = rows.map((p, i) => {
        const dlClass  = isOverdue(p.deadline) || isToday(p.deadline) ? 'deadline-today' : 'deadline-normal';
        const srcFlag  = LANG_FLAGS[p.source_language] || '🌐';
        const tgtFlag  = LANG_FLAGS[p.target_language] || '🌐';
        const price    = p.price != null
            ? `${Number(p.price).toFixed(2)} ${p.currency || 'EUR'}`
            : '0 EUR';
        const expense  = `${Number(p.expense || 0).toFixed(2)} ${p.currency || 'EUR'}`;
        const margin   = `${Number(p.margin_amount || 0).toFixed(2)} ${p.currency || 'EUR'}`;
        const emailReference = p.email_reference || '—';

        return `<tr>
            <td><input type="checkbox" class="row-check" data-id="${p.id}"></td>
            <td>${i + 1}</td>
            <td><a class="proj-num" href="project.html?id=${p.id}">${escapeHtml(p.display_name || p.project_number || '—')}</a>${p.client_reference ? `<div class="customer-sub">Client ref: ${escapeHtml(p.client_reference)}</div>` : ''}</td>
            <td><div class="customer-main">${escapeHtml(p.clients?.name || '—')}</div></td>
            <td>${escapeHtml(p.client_accounts?.name || 'Non-defined')}</td>
            <td>
                <div class="lang-pair">
                    <div class="lang-row"><span class="lang-flag">${srcFlag}</span>${escapeHtml(p.source_language || '—')}</div>
                    <div class="lang-row"><span class="lang-flag">${tgtFlag}</span>${escapeHtml(p.target_language || '—')}</div>
                </div>
            </td>
            <td><span class="${dlClass}">${fmtDate(p.deadline)}</span></td>
            <td>${escapeHtml(p.project_manager || '—')}</td>
            <td><span class="status-badge">${escapeHtml(p.status || '—')}</span></td>
            <td>${escapeHtml(p.project_type || '—')}</td>
            <td>${escapeHtml(p.po_number || (p.missing_po ? 'Missing' : '—'))}</td>
            <td class="price-cell">${price}</td>
            <td class="price-cell">${expense}</td>
            <td class="margin-cell">${margin}<div class="customer-sub">${Number(p.scoop_margin || 0).toFixed(2)}%</div></td>
            <td title="${escapeHtml(emailReference)}">${escapeHtml(emailReference.length > 34 ? emailReference.slice(0,31)+'…' : emailReference)}</td>
        </tr>`;
    }).join('');
}

// ── Export to CSV ──────────────────────────────────────────────────────────
function exportCSV() {
    let rows = filterBySearch(filterByTab(allProjects, activeTab), searchQuery);
    const headers = ['Project','Client','Account','Source Language','Target Language',
        'Deadline','Project Manager','Status','Type','PO','Price','Expense',
        'Margin','Margin %','Currency','Email Reference'];
    const lines = [headers.join(',')];
    rows.forEach(p => {
        lines.push([
            p.display_name || p.project_number, p.clients?.name, p.client_accounts?.name,
            p.source_language, p.target_language,
            p.deadline, p.project_manager, p.status, p.project_type, p.po_number,
            p.price, p.expense, p.margin_amount, p.scoop_margin, p.currency,
            p.email_reference
        ].map(v => `"${(v ?? '').toString().replace(/"/g,'""')}"`).join(','));
    });
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `projects-${activeTab}-${new Date().toISOString().slice(0,10)}.csv`;
    a.click();
}

// ── Sidebar submenu toggle ─────────────────────────────────────────────────
function toggleSub(id, item) {
    document.getElementById(id).classList.toggle('open');
    item.classList.toggle('open');
}

// ── Select all ────────────────────────────────────────────────────────────
document.getElementById('selectAll').addEventListener('change', e => {
    document.querySelectorAll('.row-check').forEach(cb => cb.checked = e.target.checked);
});

// ── Search ────────────────────────────────────────────────────────────────
document.getElementById('searchBox').addEventListener('input', e => {
    searchQuery = e.target.value;
    renderTable();
});

// ── Languages and Project creation ─────────────────────────────────────────
const LANGUAGES = [
    'English (US)','English (UK)','Bulgarian','Swedish','Danish','Finnish',
    'Norwegian (Bokmål)','Icelandic','German','French','Spanish','Italian','Dutch',
    'Polish','Portuguese','Russian','Chinese (Simplified)','Chinese (Traditional)',
    'Japanese','Korean','Arabic','Turkish','Czech','Hungarian','Romanian',
    'Slovak','Ukrainian','Greek','Hebrew','Thai','Vietnamese',
];
const LANGUAGE_CODES = {
    'English (US)':'EN-US','English (UK)':'EN-GB','Bulgarian':'BG','Swedish':'SV',
    'Danish':'DA','Finnish':'FI','Norwegian (Bokmål)':'NB','Icelandic':'IS',
    'German':'DE','French':'FR','Spanish':'ES','Italian':'IT','Dutch':'NL',
    'Polish':'PL','Portuguese':'PT','Russian':'RU','Chinese (Simplified)':'ZH-CN',
    'Chinese (Traditional)':'ZH-TW','Japanese':'JA','Korean':'KO','Arabic':'AR',
    'Turkish':'TR','Czech':'CS','Hungarian':'HU','Romanian':'RO','Slovak':'SK',
    'Ukrainian':'UK','Greek':'EL','Hebrew':'HE','Thai':'TH','Vietnamese':'VI',
};
let clientsList = [], projectAccounts = [], projectContacts = [], projectBillingEntities = [], internalResources = [];
let projectSpecializationCatalog = [], projectAccountSpecializationIds = [];

function projectOptions(rows, label, selected = '', empty = 'Non-defined') {
    return `<option value="">${empty}</option>` + rows.map(row =>
        `<option value="${row.id}" ${row.id === selected ? 'selected' : ''}>${escapeHtml(row[label])}</option>`
    ).join('');
}
function localDateValue(date = new Date()) {
    const pad = n => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}`;
}
function combineDateTime(dateId,timeId) {
    const date=document.getElementById(dateId).value;
    if(!date)return null;
    return `${date}T${document.getElementById(timeId).value||'17:00'}`;
}
function internalResourceName(resource) {
    return resource.legal_name || resource.company_name || resource.internal_number;
}
function internalResourceOptions(selected='',empty='Non-defined') {
    return `<option value="">${empty}</option>`+internalResources.map(resource=>
        `<option value="${resource.id}" ${resource.id===selected?'selected':''}>${escapeHtml(internalResourceName(resource))}</option>`
    ).join('');
}
function renderCreateSpecializations(){
    const accountId=document.getElementById('f-account').value;
    const allowed=accountId?projectSpecializationCatalog.filter(spec=>projectAccountSpecializationIds.includes(spec.id)):projectSpecializationCatalog;
    document.getElementById('f-specializations').innerHTML=allowed.map(spec=>`<label class="checkbox-row"><input type="checkbox" value="${spec.id}" ${accountId?'checked disabled':''}>${escapeHtml(spec.name)}</label>`).join('')||'<span class="muted">No specializations configured.</span>';
    document.getElementById('f-specializations-help').textContent=accountId?'Inherited from the selected Account. Edit the Account to change this list.':'No Account selected: choose at least one specialization.';
}
function installLanguageShortcut(select) {
    const singleKey={s:'Swedish',d:'Danish',n:'Norwegian (Bokmål)',b:'Bulgarian',g:'German',e:'English (UK)',p:'Polish',r:'Russian',t:'Turkish'};
    let buffer='',timer;
    select.addEventListener('keydown',event=>{
        if(event.ctrlKey||event.altKey||event.metaKey||event.key.length!==1)return;
        const key=event.key.toLowerCase();buffer+=key;clearTimeout(timer);timer=setTimeout(()=>buffer='',800);
        const wanted=buffer.length===1?singleKey[key]:null;
        const option=[...select.options].find(item=>wanted?item.value===wanted:item.text.toLowerCase().startsWith(buffer));
        if(option){event.preventDefault();select.value=option.value;select.dispatchEvent(new Event('input',{bubbles:true}));select.dispatchEvent(new Event('change',{bubbles:true}))}
    });
}
function updateProjectNamePreview() {
    const client = clientsList.find(row => row.id === document.getElementById('f-client').value);
    const target = document.getElementById('f-tgt').value;
    if (!client || !target) {
        document.getElementById('f-name-preview').textContent = 'Select a Client and target language';
        return;
    }
    const date = (document.getElementById('f-date').value || localDateValue()).replaceAll('-', '').slice(2);
    const ref = (document.getElementById('f-client-ref').value.trim() || 'NOREF')
        .toUpperCase().replace(/[^A-Z0-9]/g, '') || 'NOREF';
    document.getElementById('f-name-preview').textContent =
        `${date}_${client.code || 'CLIENT'}_${LANGUAGE_CODES[target] || 'XX'}_${ref}`;
}
async function loadProjectClientDefaults() {
    const clientId = document.getElementById('f-client').value;
    if (!clientId) {
        projectAccounts = []; projectContacts = []; projectBillingEntities = [];
    } else {
        const [a, c, b] = await Promise.all([
            _sb.from('client_accounts').select('*').eq('client_id', clientId).eq('active', true).order('name'),
            _sb.from('client_contacts').select('*').eq('client_id', clientId).eq('active', true).order('full_name'),
            _sb.from('client_billing_entities').select('*').eq('client_id', clientId).eq('active', true).order('is_default', { ascending: false }),
        ]);
        projectAccounts = a.data || []; projectContacts = c.data || []; projectBillingEntities = b.data || [];
        const client = clientsList.find(row => row.id === clientId);
        document.getElementById('f-currency').value = client?.default_currency || 'EUR';
        document.getElementById('f-cat').value = client?.default_cat_system || '';
        document.getElementById('f-instructions').value = client?.instructions || '';
    }
    document.getElementById('f-account').innerHTML = projectOptions(projectAccounts, 'name');
    document.getElementById('f-contact').innerHTML = projectOptions(projectContacts, 'full_name');
    document.getElementById('f-billing').innerHTML = projectOptions(projectBillingEntities, 'name', projectBillingEntities.find(row => row.is_default)?.id || '', 'Default billing entity');
    projectAccountSpecializationIds=[];
    renderCreateSpecializations();
    updateProjectNamePreview();
}
async function loadProjectAccountDefaults() {
    const account = projectAccounts.find(row => row.id === document.getElementById('f-account').value);
    projectAccountSpecializationIds=[];
    if (account) {
        document.getElementById('f-production').value = account.default_production_mode || 'Not selected';
        if (account.default_cat_system) document.getElementById('f-cat').value = account.default_cat_system;
        if (account.instructions) document.getElementById('f-instructions').value = account.instructions;
        const {data}=await _sb.from('client_account_specializations').select('specialization_id').eq('account_id',account.id);
        projectAccountSpecializationIds=(data||[]).map(row=>row.specialization_id);
    }
    renderCreateSpecializations();
}
async function openCreateModal() {
    document.getElementById('createModal').classList.remove('hidden');
    if (!clientsList.length) {
        const { data } = await _sb.from('clients').select('*').eq('restriction_status', 'Active').order('name');
        clientsList = data || [];
    }
    if (!internalResources.length) {
        const {data}=await _sb.from('resources').select('id,internal_number,legal_name,company_name,lifecycle_status').eq('resource_type','Internal').eq('assignment_approved',true).eq('lifecycle_status','Active').order('legal_name');
        internalResources=data||[];
    }
    if (!projectSpecializationCatalog.length) {
        const {data}=await _sb.from('specializations').select('id,name').eq('active',true).order('name');
        projectSpecializationCatalog=data||[];
    }
    document.getElementById('f-client').innerHTML = '<option value="">Select client…</option>' + clientsList.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    ['f-src','f-tgt'].forEach(id => document.getElementById(id).innerHTML = '<option value="">Select…</option>' + LANGUAGES.map(l => `<option value="${escapeHtml(l)}">${escapeHtml(l)}</option>`).join(''));
    document.getElementById('f-src').value = 'English (UK)';
    document.getElementById('f-date').value = localDateValue();
    document.getElementById('f-deadline-date').value = '';
    document.getElementById('f-deadline-time').value = '';
    document.getElementById('f-pm').innerHTML = internalResourceOptions(currentUserResourceId(),'Select Project Manager…');
    document.getElementById('f-qa').innerHTML = internalResourceOptions();
    document.getElementById('f-coordinator').innerHTML = internalResourceOptions();
    document.getElementById('f-missingpo').checked = true;
    document.getElementById('f-account').innerHTML = '<option value="">Non-defined</option>';
    document.getElementById('f-contact').innerHTML = '<option value="">Non-defined</option>';
    document.getElementById('f-billing').innerHTML = '<option value="">Default billing entity</option>';
    projectAccountSpecializationIds=[];
    renderCreateSpecializations();
    updateProjectNamePreview();
}
function currentUserResourceId(){return internalResources[0]?.id||''}
function closeCreateModal() {
    document.getElementById('createModal').classList.add('hidden');
    document.getElementById('createError').classList.add('hidden');
}
async function submitCreateProject() {
    const btn = document.getElementById('createBtn'), err = document.getElementById('createError');
    err.classList.add('hidden');
    const clientId = document.getElementById('f-client').value, target = document.getElementById('f-tgt').value;
    if (!clientId || !target) { err.textContent = 'Client and target language are required.'; err.classList.remove('hidden'); return; }
    const priceSource = document.getElementById('f-price-source').value;
    const specializationIds=[...document.querySelectorAll('#f-specializations input:checked')].map(input=>input.value);
    if(!specializationIds.length){err.textContent='Select at least one Project specialization.';err.classList.remove('hidden');return}
    if (['Manual','Fixed'].includes(priceSource) && !document.getElementById('f-price-reason').value.trim()) { err.textContent = 'Explain why a manual or fixed price is being used.'; err.classList.remove('hidden'); return; }
    btn.disabled = true; btn.textContent = 'Creating…';
    const payload = {
        client_id: clientId, account_id: document.getElementById('f-account').value || null,
        contact_id: document.getElementById('f-contact').value || null, billing_entity_id: document.getElementById('f-billing').value || null,
        client_reference: document.getElementById('f-client-ref').value.trim() || null, email_reference: document.getElementById('f-email-ref').value.trim() || null,
        project_date: document.getElementById('f-date').value, source_language: document.getElementById('f-src').value || null,
        source_language_code: LANGUAGE_CODES[document.getElementById('f-src').value] || null,
        target_language: target, target_language_code: LANGUAGE_CODES[target], deadline: combineDateTime('f-deadline-date','f-deadline-time'),
        project_manager: internalResourceName(internalResources.find(resource=>resource.id===document.getElementById('f-pm').value)||{} ) || null,
        qa_specialist: internalResourceName(internalResources.find(resource=>resource.id===document.getElementById('f-qa').value)||{} ) || null,
        project_coordinator: internalResourceName(internalResources.find(resource=>resource.id===document.getElementById('f-coordinator').value)||{} ) || null, status: 'Assign', project_type: document.getElementById('f-type').value,
        production_mode: document.getElementById('f-production').value, cat_system: document.getElementById('f-cat').value.trim() || null,
        client_instructions: document.getElementById('f-instructions').value.trim() || null, price: Number(document.getElementById('f-price').value || 0),
        currency: document.getElementById('f-currency').value, price_source: priceSource || null,
        price_override_reason: document.getElementById('f-price-reason').value.trim() || null, po_number: document.getElementById('f-po').value.trim() || null,
        missing_po: document.getElementById('f-missingpo').checked, upcoming: document.getElementById('f-upcoming').checked,
        urgent: document.getElementById('f-urgent').checked,
        specialization_ids: specializationIds,
    };
    const { data, error } = await _sb.rpc('create_project_with_specializations', { p_payload: payload });
    btn.disabled = false; btn.textContent = 'Create Project';
    if (error) { err.textContent = error.message; err.classList.remove('hidden'); return; }
    if (data?.[0]?.created_project_id) {
        const staff={project_manager_resource_id:document.getElementById('f-pm').value||null,qa_specialist_resource_id:document.getElementById('f-qa').value||null,project_coordinator_resource_id:document.getElementById('f-coordinator').value||null};
        const staffUpdate=await _sb.from('projects').update(staff).eq('id',data[0].created_project_id);
        if(staffUpdate.error){err.textContent=`Project created, but staff assignment failed: ${staffUpdate.error.message}`;err.classList.remove('hidden');return}
        location.href = `project.html?id=${data[0].created_project_id}`;
    }
}

document.getElementById('createProjectBtn').addEventListener('click', openCreateModal);
document.getElementById('f-client').addEventListener('change', loadProjectClientDefaults);
document.getElementById('f-account').addEventListener('change', loadProjectAccountDefaults);
['f-tgt','f-date','f-client-ref'].forEach(id => document.getElementById(id).addEventListener('input', updateProjectNamePreview));
installLanguageShortcut(document.getElementById('f-src'));
installLanguageShortcut(document.getElementById('f-tgt'));
document.getElementById('f-po').addEventListener('input', event => {
    if (event.target.value.trim()) document.getElementById('f-missingpo').checked = false;
});
function selectedProjectIds() {
    return [...document.querySelectorAll('.row-check:checked')].map(input => input.dataset.id);
}
function openBulkStatus() {
    const ids = selectedProjectIds();
    if (!ids.length) { alert('Select at least one Project.'); return; }
    document.getElementById('bulkStatusModal').classList.remove('hidden');
}
function closeBulkStatus() {
    document.getElementById('bulkStatusModal').classList.add('hidden');
    document.getElementById('bulkStatusError').classList.add('hidden');
}
async function applyBulkStatus() {
    const ids = selectedProjectIds(), status = document.getElementById('bulk-status').value;
    const reason = document.getElementById('bulk-wait-reason').value.trim();
    const follow = combineDateTime('bulk-wait-follow-date','bulk-wait-follow-time');
    const errorEl = document.getElementById('bulkStatusError');
    if (status === 'Waiting' && (!reason || !follow)) {
        errorEl.textContent = 'Waiting requires a reason and follow-up date.';
        errorEl.classList.remove('hidden'); return;
    }
    const { error } = await _sb.from('projects').update({
        status,
        waiting_reason: status === 'Waiting' ? reason : null,
        waiting_follow_up_at: status === 'Waiting' ? follow : null,
    }).in('id', ids);
    if (error) { errorEl.textContent = error.message; errorEl.classList.remove('hidden'); return; }
    closeBulkStatus();
    await reloadProjects();
}
document.getElementById('changeStatusBtn').addEventListener('click', openBulkStatus);

async function reloadProjects() {
    const { data, error } = await _sb.from('projects')
        .select('*, clients(name), client_accounts(name)')
        .order('deadline', { ascending: true });
    if (error) {
        document.getElementById('projectsTbody').innerHTML =
            `<tr class="state-row"><td colspan="15">Error: ${escapeHtml(error.message)}</td></tr>`;
        return;
    }
    allProjects = data || [];
    renderTabs(); renderTable();
}

// ── Init ──────────────────────────────────────────────────────────────────
(async () => {
    const user = await requireAuth();
    if (!user) return;

    await reloadProjects();
})();
