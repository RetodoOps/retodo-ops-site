const LANGUAGES = [
    'English (US)','English (UK)','Bulgarian','Swedish','Danish','Finnish',
    'Norwegian (Bokmål)','German','French','Spanish','Italian','Dutch',
    'Polish','Portuguese','Russian','Chinese (Simplified)','Chinese (Traditional)',
    'Japanese','Korean','Arabic','Turkish','Czech','Hungarian','Romanian',
    'Slovak','Ukrainian','Greek','Hebrew','Thai','Vietnamese',
];

const PRICE_UNITS = [
    'Words','Words TEP (New)','Words TEP (Fuzzy)','Words TEP (Rep)',
    'Hours','Pages','Lines','Characters','Minutes','Fixed fee',
];

let projectId   = null;
let projectData = null;
let lineItems   = [];   // { id?, qty, unit, unitPrice, price, isNew?, isDeleted? }

// ── Sidebar toggle ─────────────────────────────────────────────────────────
function toggleSub(id, item) {
    document.getElementById(id).classList.toggle('open');
    item.classList.toggle('open');
}

// ── Tab switching ──────────────────────────────────────────────────────────
document.querySelectorAll('.proj-tab').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.proj-tab').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    });
});

// ── Populate language selects ──────────────────────────────────────────────
function populateLangSelect(id, selected) {
    const opts = '<option value="">Select…</option>' +
        LANGUAGES.map(l => `<option${l === selected ? ' selected' : ''}>${l}</option>`).join('');
    document.getElementById(id).innerHTML = opts;
}

// ── Format datetime-local value ────────────────────────────────────────────
function toLocalDT(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    const pad = n => String(n).padStart(2,'0');
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// ── Populate all form fields ───────────────────────────────────────────────
async function populateForm(p, clients) {
    // Header
    document.title = `${p.project_number} — RetodoOps TMS`;
    document.getElementById('projHeaderTitle').textContent =
        `Project: ${p.project_number}${p.sub_client ? ' ' + p.sub_client : ''}${p.clients?.name ? ' (' + p.clients.name + ')' : ''}`;

    // Client dropdown
    const clientSel = '<option value="">Select…</option>' +
        clients.map(c => `<option value="${c.id}"${c.id === p.client_id ? ' selected' : ''}>${c.name}</option>`).join('');
    document.getElementById('g-client').innerHTML = clientSel;

    // General tab
    document.getElementById('g-num').value       = p.project_number || '';
    document.getElementById('g-sub').value       = p.sub_client     || '';
    document.getElementById('g-status').value    = p.status         || 'Assign';
    document.getElementById('g-volume').value    = p.project_volume || '';
    document.getElementById('g-price').value     = p.price          || '';
    document.getElementById('g-currency').value  = p.currency       || 'EUR';
    document.getElementById('g-margin').value    = p.scoop_margin   || '';
    document.getElementById('g-po').value        = p.po_number      || '';
    document.getElementById('g-pm').value        = p.project_manager || '';
    document.getElementById('g-qa').value        = p.qa_specialist  || '';
    document.getElementById('g-ling').value      = p.linguist       || '';
    document.getElementById('g-contact').value   = p.client_contact || '';
    document.getElementById('g-delivery').value  = p.place_of_delivery || '';
    document.getElementById('g-comment').value   = p.accounting_comment || '';
    document.getElementById('g-deadline').value  = toLocalDT(p.deadline);
    document.getElementById('g-jobdl').value     = toLocalDT(p.job_deadline);
    document.getElementById('g-upcoming').checked = !!p.upcoming;
    document.getElementById('g-urgent').checked   = !!p.urgent;
    document.getElementById('g-onhold').checked   = !!p.on_hold;
    document.getElementById('g-missingpo').checked = !!p.missing_po;
    if (p.project_type) document.getElementById('g-type').value = p.project_type;
    populateLangSelect('g-src', p.source_language);
    populateLangSelect('g-tgt', p.target_language);

    // Scoop tab mirrors
    populateLangSelect('s-src', p.source_language);
    populateLangSelect('s-tgt', p.target_language);
    if (p.project_type) document.getElementById('s-type').value = p.project_type;
    document.getElementById('s-deadline').value  = toLocalDT(p.deadline);
    document.getElementById('s-po').value        = p.po_number       || '';
    document.getElementById('s-email-subject').value = p.email_subject || '';
    document.getElementById('s-status').value    = p.status          || 'Assign';
    document.getElementById('s-upcoming').checked = !!p.upcoming;
    document.getElementById('s-urgent').checked   = !!p.urgent;
    document.getElementById('s-onhold').checked   = !!p.on_hold;
    document.getElementById('s-volume').value    = p.project_volume  || '';
    document.getElementById('s-coordinator').value = p.project_coordinator || '';
    document.getElementById('s-pm').value        = p.project_manager  || '';
    document.getElementById('s-qa').value        = p.qa_specialist   || '';
    document.getElementById('s-contact').value   = p.client_contact  || '';
    document.getElementById('s-delivery').value  = p.place_of_delivery || '';
    document.getElementById('s-comment').value   = p.accounting_comment || '';

    // Scoop header
    document.getElementById('scoopId').textContent   = p.project_number || '';
    document.getElementById('scoopName').textContent =
        [p.source_language, p.target_language].filter(Boolean).join(' → ') +
        (p.clients?.name ? ' | ' + p.clients.name : '');
    updateScoopAmount();
}

// ── Line items ─────────────────────────────────────────────────────────────
function updateScoopAmount() {
    const total = lineItems
        .filter(li => !li.isDeleted)
        .reduce((sum, li) => sum + (parseFloat(li.price) || 0), 0);
    const currency = document.getElementById('g-currency')?.value || 'EUR';
    document.getElementById('scoopAmount').textContent =
        `Total: ${total.toFixed(2)} ${currency}`;
}

function renderLineItems() {
    const tbody = document.getElementById('lineItemsTbody');
    const rows = lineItems.filter(li => !li.isDeleted);
    if (!rows.length) {
        tbody.innerHTML = `<tr><td colspan="5" style="text-align:center;color:#9ca3af;padding:20px">No line items yet. Click "+ Add line" to add one.</td></tr>`;
        return;
    }
    tbody.innerHTML = rows.map((li, i) => {
        const unitOpts = PRICE_UNITS.map(u =>
            `<option${u === li.unit ? ' selected' : ''}>${u}</option>`).join('');
        return `<tr data-idx="${i}">
            <td><input type="number" step="0.01" value="${li.qty||''}" placeholder="0"
                onchange="updateLineItem(${i},'qty',this.value)"></td>
            <td><select onchange="updateLineItem(${i},'unit',this.value)">
                <option value="">Select…</option>${unitOpts}</select></td>
            <td><input type="number" step="0.0001" value="${li.unitPrice||''}" placeholder="0.0000"
                onchange="updateLineItem(${i},'unitPrice',this.value)"></td>
            <td><input type="number" step="0.01" value="${li.price||''}" placeholder="0.00"
                onchange="updateLineItem(${i},'price',this.value)"></td>
            <td><button class="del-line-btn" onclick="removeLineItem(${i})" title="Remove">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>
                </svg>
            </button></td>
        </tr>`;
    }).join('');
}

function addLineItem() {
    lineItems.push({ qty: '', unit: '', unitPrice: '', price: '', isNew: true });
    renderLineItems();
}

function updateLineItem(idx, field, val) {
    lineItems[idx][field] = val;
    // Auto-calculate price = qty * unitPrice
    if (field === 'qty' || field === 'unitPrice') {
        const q = parseFloat(lineItems[idx].qty)       || 0;
        const u = parseFloat(lineItems[idx].unitPrice)  || 0;
        if (q && u) {
            lineItems[idx].price = (q * u).toFixed(2);
            renderLineItems();
        }
    }
    updateScoopAmount();
}

function removeLineItem(idx) {
    if (lineItems[idx].id) {
        lineItems[idx].isDeleted = true;
    } else {
        lineItems.splice(idx, 1);
    }
    renderLineItems();
    updateScoopAmount();
}

// ── Collect form data ──────────────────────────────────────────────────────
function collectFormData() {
    return {
        client_id:            document.getElementById('g-client').value      || null,
        sub_client:           document.getElementById('g-sub').value.trim()  || null,
        status:               document.getElementById('s-status').value      || document.getElementById('g-status').value,
        source_language:      document.getElementById('s-src').value         || document.getElementById('g-src').value || null,
        target_language:      document.getElementById('s-tgt').value         || document.getElementById('g-tgt').value || null,
        deadline:             document.getElementById('s-deadline').value     || document.getElementById('g-deadline').value || null,
        job_deadline:         document.getElementById('g-jobdl').value       || null,
        project_type:         document.getElementById('s-type').value        || document.getElementById('g-type').value || null,
        project_volume:       document.getElementById('s-volume').value.trim() || document.getElementById('g-volume').value.trim() || null,
        price:                parseFloat(document.getElementById('g-price').value)  || 0,
        currency:             document.getElementById('g-currency').value,
        scoop_margin:         parseFloat(document.getElementById('g-margin').value) || 0,
        po_number:            document.getElementById('s-po').value.trim()   || document.getElementById('g-po').value.trim() || null,
        email_subject:        document.getElementById('s-email-subject').value.trim() || null,
        project_manager:      document.getElementById('g-pm').value.trim()   || null,
        qa_specialist:        document.getElementById('g-qa').value.trim()   || null,
        linguist:             document.getElementById('g-ling').value.trim() || null,
        client_contact:       document.getElementById('g-contact').value.trim() || null,
        place_of_delivery:    document.getElementById('g-delivery').value.trim() || null,
        accounting_comment:   document.getElementById('g-comment').value.trim() || null,
        project_coordinator:  document.getElementById('s-coordinator').value.trim() || null,
        upcoming:             document.getElementById('g-upcoming').checked  || document.getElementById('s-upcoming').checked,
        urgent:               document.getElementById('g-urgent').checked    || document.getElementById('s-urgent').checked,
        on_hold:              document.getElementById('g-onhold').checked    || document.getElementById('s-onhold').checked,
        missing_po:           document.getElementById('g-missingpo').checked,
        updated_at:           new Date().toISOString(),
    };
}

// ── Save project ───────────────────────────────────────────────────────────
async function saveProject() {
    const btn     = document.getElementById('saveBtn');
    const msg     = document.getElementById('saveMsg');
    const errEl   = document.getElementById('generalError');
    btn.disabled  = true; btn.textContent = 'Saving…';
    msg.textContent = ''; errEl.classList.add('hidden');

    const updates = collectFormData();
    const { error } = await _sb.from('projects').update(updates).eq('id', projectId);
    if (error) {
        errEl.textContent = error.message; errEl.classList.remove('hidden');
        btn.disabled = false; btn.textContent = 'Save'; return;
    }

    // Save line items
    for (const li of lineItems) {
        if (li.isDeleted && li.id) {
            await _sb.from('scope_items').delete().eq('id', li.id);
        } else if (li.isNew && !li.isDeleted) {
            await _sb.from('scope_items').insert({
                project_id: projectId,
                quantity:   parseFloat(li.qty)       || null,
                price_unit: li.unit                  || null,
                unit_price: parseFloat(li.unitPrice) || null,
                price:      parseFloat(li.price)     || null,
            });
        } else if (li.id && !li.isDeleted) {
            await _sb.from('scope_items').update({
                quantity:   parseFloat(li.qty)       || null,
                price_unit: li.unit                  || null,
                unit_price: parseFloat(li.unitPrice) || null,
                price:      parseFloat(li.price)     || null,
            }).eq('id', li.id);
        }
    }

    btn.disabled = false; btn.textContent = 'Save';
    msg.textContent = 'Saved ✓';
    setTimeout(() => msg.textContent = '', 3000);
}

// ── Init ───────────────────────────────────────────────────────────────────
(async () => {
    const user = await requireAuth();
    if (!user) return;

    projectId = new URLSearchParams(location.search).get('id');
    if (!projectId) { location.href = 'dashboard.html'; return; }

    const [{ data: p, error }, { data: clients }, { data: items }] = await Promise.all([
        _sb.from('projects').select('*, clients(name)').eq('id', projectId).single(),
        _sb.from('clients').select('id,name').order('name'),
        _sb.from('scope_items').select('*').eq('project_id', projectId).order('created_at'),
    ]);

    if (error || !p) { location.href = 'dashboard.html'; return; }

    projectData = p;
    lineItems   = (items || []).map(i => ({
        id: i.id, qty: i.quantity, unit: i.price_unit,
        unitPrice: i.unit_price, price: i.price,
    }));

    await populateForm(p, clients || []);
    renderLineItems();
    document.getElementById('editingBadge').style.display = 'flex';
})();
