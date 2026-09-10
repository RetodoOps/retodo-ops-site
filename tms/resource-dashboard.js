let portalJobs = [];
let portalPurchaseOrders = [];

function renderPortalJobs() {
    const query = document.getElementById('jobSearch').value.trim().toLowerCase();
    const rows = portalJobs.filter(row => [
        row.job_number,
        row.project_number,
        row.scoop_number,
        row.service_type,
        row.source_language,
        row.target_language,
        row.job_status,
        row.purchase_order_number,
    ].some(value => String(value || '').toLowerCase().includes(query)));

    document.getElementById('portalJobsTbody').innerHTML = rows.length
        ? rows.map(row => `
          <tr>
            <td><a class="table-link portal-primary-link" href="resource-job.html?id=${encodeURIComponent(row.job_id)}">${portalEsc(row.job_number)}</a>${row.instructions ? '<div class="customer-sub">Instructions available</div>' : ''}</td>
            <td><strong>${portalEsc(row.project_number || '—')}</strong><div class="customer-sub">${portalEsc(row.scoop_number || '—')}</div></td>
            <td>${portalEsc(row.service_type || '—')}<div class="customer-sub">${portalEsc(row.specialization_name || '—')}</div></td>
            <td>${portalEsc(row.source_language || '—')} → ${portalEsc(row.target_language || '—')}</td>
            <td>${portalDateTime(row.deadline)}</td>
            <td><span class="pill ${portalStatusClass(row.job_status)}">${portalEsc(row.job_status)}</span></td>
            <td>${row.purchase_order_id ? `<a class="table-link" href="resource-po.html?id=${encodeURIComponent(row.purchase_order_id)}">${portalEsc(row.purchase_order_number)} · V${Number(row.purchase_order_version || 0)}</a><div class="customer-sub">${portalMoney(row.purchase_order_total, row.purchase_order_currency)}</div>` : '—'}</td>
          </tr>`).join('')
        : `<tr class="state-row"><td colspan="7">${portalJobs.length ? 'No assigned Jobs match this search.' : 'No Jobs are currently assigned to this Resource account.'}</td></tr>`;
}

function renderPortalPurchaseOrders() {
    const query = document.getElementById('poSearch').value.trim().toLowerCase();
    const rows = portalPurchaseOrders.filter(row => [
        row.purchase_order_number,
        row.job_number,
        row.project_number,
        row.scoop_number,
        row.purchase_order_status,
    ].some(value => String(value || '').toLowerCase().includes(query)));

    document.getElementById('portalPosTbody').innerHTML = rows.length
        ? rows.map(row => `
          <tr>
            <td><a class="table-link portal-primary-link" href="resource-po.html?id=${encodeURIComponent(row.purchase_order_id)}">${portalEsc(row.purchase_order_number)}</a></td>
            <td>${portalEsc(row.job_number || '—')}</td>
            <td><strong>${portalEsc(row.project_number || '—')}</strong><div class="customer-sub">${portalEsc(row.scoop_number || '—')}</div></td>
            <td><span class="pill ${portalStatusClass(row.purchase_order_status)}">${portalEsc(row.purchase_order_status)}</span></td>
            <td>V${Number(row.current_version || 0)}</td>
            <td class="number-cell"><strong>${portalMoney(row.total, row.currency)}</strong></td>
            <td>${portalDateTime(row.issued_at)}</td>
          </tr>`).join('')
        : `<tr class="state-row"><td colspan="7">${portalPurchaseOrders.length ? 'No purchase orders match this search.' : 'No issued Supplier POs belong to this Resource account yet.'}</td></tr>`;
}

async function loadPortalDashboard() {
    portalClearError();
    const context = await portalBoot();
    if (!context) return;

    document.getElementById('portalJobCount').textContent = Number(context.job_count || 0);
    document.getElementById('portalPoCount').textContent = Number(context.purchase_order_count || 0);
    document.getElementById('portalAccessLabel').textContent = context.portal_status || 'Read only';
    document.getElementById('portalMode').textContent = context.portal_status || 'Read only';
    document.getElementById('financialOnlyBanner').classList.toggle('hidden', context.can_view_jobs !== false);
    document.getElementById('myJobs').classList.toggle('hidden', context.can_view_jobs === false);

    const requests = [
        context.can_view_jobs
            ? _sb.rpc('resource_portal_jobs')
            : Promise.resolve({data: [], error: null}),
        _sb.rpc('resource_portal_purchase_orders'),
    ];
    const [jobsResult, poResult] = await Promise.all(requests);
    if (jobsResult.error) portalShowError(jobsResult.error.message);
    if (poResult.error) portalShowError(poResult.error.message);
    portalJobs = jobsResult.data || [];
    portalPurchaseOrders = poResult.data || [];
    renderPortalJobs();
    renderPortalPurchaseOrders();
}

document.getElementById('jobSearch').addEventListener('input', renderPortalJobs);
document.getElementById('poSearch').addEventListener('input', renderPortalPurchaseOrders);
loadPortalDashboard();

