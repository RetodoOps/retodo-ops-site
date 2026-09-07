let assignedJobData = null;
let assignedJobFiles = [];

function renderAssignedJob(data) {
    const job = data.job;
    document.title = `${job.job_number} — RetodoOps Resource Portal`;
    document.getElementById('jobBreadcrumb').textContent = job.job_number;
    document.getElementById('jobTitle').textContent = job.job_number;
    document.getElementById('jobStatus').textContent = job.status;
    document.getElementById('jobStatus').className = `pill ${portalStatusClass(job.status)}`;
    document.getElementById('projectNumber').textContent = job.project_number || '—';
    document.getElementById('scoopNumber').textContent = job.scoop_number || '—';
    document.getElementById('jobDeadline').textContent = portalDateTime(job.deadline);
    document.getElementById('jobService').textContent = job.service_type || '—';
    document.getElementById('jobSpecialization').textContent = job.specialization || '—';
    document.getElementById('jobLanguages').textContent = `${job.source_language || '—'} → ${job.target_language || '—'}`;
    document.getElementById('jobQuantity').textContent = job.quantity == null
        ? '—'
        : `${portalNumber(job.quantity)} ${job.unit || ''}`.trim();
    document.getElementById('jobInstructions').textContent = job.instructions || 'No instructions recorded.';
    document.getElementById('jobContext').classList.remove('hidden');
    document.getElementById('jobDetailsCard').classList.remove('hidden');

    const purchaseOrders = data.purchase_orders || [];
    document.getElementById('jobPosTbody').innerHTML = purchaseOrders.length
        ? purchaseOrders.map(po => `
          <tr>
            <td><a class="table-link portal-primary-link" href="resource-po.html?id=${encodeURIComponent(po.id)}">${portalEsc(po.po_number)}</a></td>
            <td><span class="pill ${portalStatusClass(po.status)}">${portalEsc(po.status)}</span></td>
            <td>V${Number(po.current_version || 0)}</td>
            <td class="number-cell"><strong>${portalMoney(po.total, po.currency)}</strong></td>
            <td>${portalDateTime(po.issued_at)}</td>
            <td>${po.acknowledged_at ? portalDateTime(po.acknowledged_at) : '—'}</td>
          </tr>`).join('')
        : '<tr class="state-row"><td colspan="6">No issued Supplier PO is available for this Job.</td></tr>';
    document.getElementById('jobPoCard').classList.remove('hidden');

    assignedJobFiles = data.files || [];
    document.getElementById('jobFilesTbody').innerHTML = assignedJobFiles.length
        ? assignedJobFiles.map(file => {
            const canOpen = file.storage_provider === 'Supabase'
                ? file.bucket_name && file.object_key
                : !!safePortalUrl(file.external_url);
            const actions = canOpen
                ? `<button class="table-action" type="button" onclick="openAssignedJobFile('${file.id}','View')">Open</button>${file.storage_provider === 'Supabase' ? `<button class="table-action" type="button" onclick="openAssignedJobFile('${file.id}','Download')">Download</button>` : ''}`
                : '<span class="customer-sub">Link unavailable</span>';
            return `<tr><td><strong>${portalEsc(file.filename)}</strong></td><td>${portalEsc(file.file_role || '—')}</td><td>${portalEsc(file.mime_type || file.storage_provider || '—')}</td><td>${portalBytes(file.size_bytes)}</td><td>${portalDateTime(file.created_at)}</td><td><div class="table-actions">${actions}</div></td></tr>`;
        }).join('')
        : '<tr class="state-row"><td colspan="6">No files are linked to this assigned Job.</td></tr>';
    document.getElementById('jobFilesCard').classList.remove('hidden');

    const issues = data.issues || [];
    document.getElementById('jobIssuesTbody').innerHTML = issues.length
        ? issues.map(issue => `
          <tr>
            <td><span class="pill ${portalStatusClass(issue.status)}">${portalEsc(issue.status)}</span></td>
            <td>${portalEsc(issue.severity || '—')}</td>
            <td>${portalEsc(issue.description || '—')}</td>
            <td>${portalDateTime(issue.reported_at)}</td>
            <td>${portalEsc(issue.resolution || '—')}</td>
          </tr>`).join('')
        : '<tr class="state-row"><td colspan="5">No issues are recorded for this assigned Job.</td></tr>';
    document.getElementById('jobIssuesCard').classList.remove('hidden');
}

async function openAssignedJobFile(fileId, action) {
    portalClearError();
    const file = assignedJobFiles.find(row => row.id === fileId);
    if (!file) return portalShowError('This Job file is no longer available.');

    let targetUrl = null;
    if (file.storage_provider === 'Supabase') {
        if (!file.bucket_name || !file.object_key) return portalShowError('The stored file path is incomplete.');
        const options = action === 'Download' ? {download: file.filename || true} : {};
        const {data, error} = await _sb.storage
            .from(file.bucket_name)
            .createSignedUrl(file.object_key, 60, options);
        if (error || !data?.signedUrl) return portalShowError(error?.message || 'The private file link could not be created.');
        targetUrl = data.signedUrl;
    } else {
        targetUrl = safePortalUrl(file.external_url);
        if (!targetUrl) return portalShowError('The external file link is invalid or unavailable.');
    }

    const logResult = await _sb.rpc('record_resource_file_access', {
        p_file_record_id: file.id,
        p_action: action,
    });
    if (logResult.error) return portalShowError(`The file was not opened because access could not be logged: ${logResult.error.message}`);
    triggerPortalDownload(targetUrl, action === 'Download' ? file.filename : '');
}

async function loadAssignedJob() {
    portalClearError();
    const context = await portalBoot();
    if (!context) return;
    if (!context.can_view_jobs) {
        location.replace('resource-dashboard.html#myPurchaseOrders');
        return;
    }
    const jobId = new URLSearchParams(location.search).get('id');
    if (!jobId) return portalShowError('No assigned Job was selected.');
    const {data, error} = await _sb.rpc('resource_portal_job', {p_job_id: jobId});
    if (error || !data?.job) return portalShowError(error?.message || 'The assigned Job could not be loaded.');
    assignedJobData = data;
    renderAssignedJob(data);
}

loadAssignedJob();
