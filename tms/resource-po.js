let portalPoData = null;
let selectedPortalPoVersion = 0;

function latestPortalPoVersionNumber() {
    return Math.max(0, ...(portalPoData?.versions || []).map(version => Number(version.version_number || 0)));
}

function portalPoVersionStatus(version) {
    if (!version) return 'Version';
    return Number(version.version_number || 0) < latestPortalPoVersionNumber()
        ? 'Superseded'
        : (version.document_status || portalPoData?.purchase_order?.status || 'Version');
}

function renderPortalPoVersion(index) {
    const version = portalPoData?.versions?.[index];
    if (!version) return;
    selectedPortalPoVersion = index;
    document.querySelectorAll('#portalPoVersions button').forEach((button, buttonIndex) => {
        button.classList.toggle('selected', buttonIndex === index);
        button.setAttribute('aria-current', buttonIndex === index ? 'true' : 'false');
    });

    const po = portalPoData.purchase_order;
    const job = version.job || {};
    const currency = version.currency || po.currency || 'EUR';
    const displayStatus = portalPoVersionStatus(version);
    document.getElementById('documentPoNumber').textContent = po.po_number;
    document.getElementById('documentVersion').textContent = `Version ${Number(version.version_number || 0)} · ${displayStatus}`;
    document.getElementById('documentTotal').textContent = portalMoneyText(version.total, currency);
    document.getElementById('documentJob').textContent = job.job_number || '—';
    document.getElementById('documentStatus').textContent = displayStatus;
    document.getElementById('documentService').textContent = job.service_type || '—';
    document.getElementById('documentLanguages').textContent = `${job.source_language || '—'} → ${job.target_language || '—'}`;
    document.getElementById('documentDeadline').textContent = portalDateTime(job.deadline);
    document.getElementById('documentQuantity').textContent = job.quantity == null
        ? '—'
        : `${portalNumber(job.quantity)} ${job.unit || ''}`.trim();

    const lines = version.lines || [];
    document.getElementById('documentLines').innerHTML = lines.length
        ? lines.map(line => `<tr><td>${portalEsc(line.description || '—')}</td><td>${portalNumber(line.quantity)}</td><td>${portalEsc(line.unit || '—')}</td><td class="number-cell">${portalMoney(line.unit_price, currency)}</td><td>${portalEsc(line.adjustment_type || '—')}</td><td class="number-cell"><strong>${portalMoney(line.amount, currency)}</strong></td></tr>`).join('')
        : '<tr class="state-row"><td colspan="6">No lines are stored in this version.</td></tr>';
    document.getElementById('documentSubtotal').textContent = portalMoneyText(version.subtotal, currency);
    document.getElementById('documentAdjustments').textContent = portalMoneyText(version.adjustment_amount, currency);
    document.getElementById('documentGrandTotal').textContent = portalMoneyText(version.total, currency);
    document.getElementById('documentReasonLabel').textContent = version.change_reason ? 'Revision reason' : 'Initial issue';
    document.getElementById('documentReason').textContent = version.change_reason || portalDateTime(version.created_at);
}

function renderPortalPo(data) {
    const po = data.purchase_order;
    document.title = `${po.po_number} — RetodoOps Resource Portal`;
    document.getElementById('poBreadcrumb').textContent = po.po_number;
    document.getElementById('poTitle').textContent = po.po_number;
    document.getElementById('poStatus').textContent = po.status;
    document.getElementById('poStatus').className = `pill ${portalStatusClass(po.status)}`;
    document.getElementById('poProjectNumber').textContent = po.project_number || '—';
    document.getElementById('poScoopNumber').textContent = po.scoop_number || '—';
    document.getElementById('poIssuedAt').textContent = portalDateTime(po.issued_at);
    document.getElementById('poContext').classList.remove('hidden');
    document.getElementById('printPortalPoBtn').classList.remove('hidden');
    document.getElementById('poWorkspace').classList.remove('hidden');

    document.getElementById('portalPoVersions').innerHTML = data.versions.map((version, index) => `
      <button type="button" onclick="renderPortalPoVersion(${index})">
        <strong>V${Number(version.version_number || 0)}</strong>
        <span>${portalEsc(portalPoVersionStatus(version))}</span>
        <small>${portalDateTime(version.created_at)}</small>
        <b>${portalMoney(version.total, version.currency || po.currency)}</b>
      </button>`).join('');
    renderPortalPoVersion(0);
}

function printPortalPo() {
    document.body.classList.add('printing-resource-po');
    window.print();
    setTimeout(() => document.body.classList.remove('printing-resource-po'), 300);
}

async function loadPortalPo() {
    portalClearError();
    const context = await portalBoot();
    if (!context) return;
    const poId = new URLSearchParams(location.search).get('id');
    if (!poId) return portalShowError('No Supplier PO was selected.');
    const {data, error} = await _sb.rpc('resource_portal_purchase_order', {
        p_purchase_order_id: poId,
    });
    if (error || !data?.purchase_order) return portalShowError(error?.message || 'The Supplier PO could not be loaded.');
    portalPoData = data;
    renderPortalPo(data);
}

loadPortalPo();
