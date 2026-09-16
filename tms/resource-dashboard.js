let portalJobs = [];
let portalPurchaseOrders = [];
let portalCompliance = null;
let portalAgreement = null;

const portalValue = id => String(document.getElementById(id)?.value || '').trim();
const portalMonth = date => date ? String(date).slice(0, 7) : '';
const portalCombinedId = provider => {
    const values = [provider?.registration_or_id_number, provider?.tax_vat_number]
        .map(value => String(value || '').trim()).filter(Boolean);
    return [...new Set(values)].join(' / ');
};

function portalCountryOptions(selected = '') {
    const values = [...(globalThis.TMS_REF?.countries || [])];
    if (selected && !values.includes(selected)) values.push(selected);
    return '<option value="">Select country…</option>' + values.map(country =>
        `<option value="${portalEsc(country)}" ${country === selected ? 'selected' : ''}>${portalEsc(country)}</option>`
    ).join('');
}

function portalExperienceDuration(month) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '')) return null;
    const [year, value] = month.split('-').map(Number);
    const now = new Date();
    const total = (now.getUTCFullYear() - year) * 12 + now.getUTCMonth() + 1 - value;
    if (total < 0) return null;
    const years = Math.floor(total / 12), months = total % 12;
    return `${years} ${years === 1 ? 'year' : 'years'} ${months} ${months === 1 ? 'month' : 'months'}`;
}

function updatePortalExperiencePreview() {
    for (const [inputId, outputId, label] of [
        ['portal-translation-since', 'portalTranslationExperience', 'Translation experience'],
        ['portal-revision-since', 'portalRevisionExperience', 'Revision experience'],
        ['portal-mtpe-since', 'portalMtpeExperience', 'MTPE experience'],
    ]) {
        const duration = portalExperienceDuration(portalValue(inputId));
        document.getElementById(outputId).textContent = `${label}: ${duration || 'Not recorded'}`;
    }
}

function togglePortalEducationFields() {
    const noDegree = portalValue('portal-degree-level') === 'No university degree';
    const other = portalValue('portal-field-category') === 'Other';
    const type = document.getElementById('portal-degree-type');
    type.disabled = noDegree || !portalCompliance?.editable;
    if (noDegree) type.value = 'No university degree';
    else if (type.value === 'No university degree') type.value = '';
    for (const id of ['portal-field-category', 'portal-institution', 'portal-education-country', 'portal-graduation-year']) {
        const input = document.getElementById(id);
        input.disabled = noDegree || !portalCompliance?.editable;
    }
    document.getElementById('portal-field-other-field').classList.toggle('hidden', noDegree || !other);
    document.getElementById('portal-field-other').disabled = noDegree || !other || !portalCompliance?.editable;
    document.getElementById('portalDiplomaUploadRow').classList.toggle('hidden', noDegree);
    document.getElementById('portalDiplomaEvidence').classList.toggle('hidden', noDegree);
    if (noDegree && portalCompliance?.editable) {
        document.getElementById('portal-field-category').value = '';
        document.getElementById('portal-field-other').value = '';
        document.getElementById('portal-institution').value = '';
        document.getElementById('portal-education-country').value = '';
        document.getElementById('portal-graduation-year').value = '';
    }
}

function portalComplianceFileCard(file) {
    const reviewed = file.review_status === 'Valid';
    const remove = portalCompliance?.editable
        ? `<button class="table-action danger" type="button" onclick="deletePortalComplianceFile('${file.file_id}')">Delete</button>`
        : '';
    return `<div class="data-card compliance-file-card"><div><strong>${portalEsc(file.filename)}</strong><small>${portalEsc(file.evidence_type)} · ${reviewed ? 'Reviewed' : 'Pending internal review'} · ${portalBytes(file.size_bytes)}</small></div><div class="table-actions"><button class="table-action" type="button" onclick="openPortalComplianceFile('${file.file_id}','View')">Open</button><button class="table-action" type="button" onclick="openPortalComplianceFile('${file.file_id}','Download')">Download</button>${remove}</div></div>`;
}

function renderPortalAgreement() {
    const data = portalAgreement || {visible: false, status: 'Not accepted', provider: {}};
    const card = document.getElementById('portalAgreementCard');
    card.classList.toggle('hidden', data.visible !== true);
    if (data.visible !== true) return;
    const accepted = data.status === 'Accepted', provider = data.provider || {};
    const pill = document.getElementById('portalAgreementPill');
    pill.textContent = data.status || 'Not accepted';
    pill.className = `pill ${accepted ? 'pill-green' : 'pill-amber'}`;
    document.getElementById('portalAgreementVersion').textContent = data.agreement_version || '1.0';
    const download = document.getElementById('portalAgreementDownload');
    download.onclick = null;
    if (accepted) {
        download.href = '#';
        download.removeAttribute('download');
        download.textContent = 'Download signed PDF';
        download.onclick = event => { event.preventDefault(); downloadPortalSignedAgreementPdf(); };
    } else {
        download.href = data.document_path || 'agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx';
        download.setAttribute('download', '');
        download.textContent = 'Download original DOCX';
    }
    const values = {
        'portal-agreement-provider-name': provider.service_provider_name,
        'portal-agreement-registration': portalCombinedId(provider),
        'portal-agreement-address': provider.service_provider_address,
        'portal-agreement-signatory': provider.signatory_name,
        'portal-agreement-email': provider.registration_email,
        'portal-agreement-effective-date': String(data.effective_date || '').slice(0, 10),
    };
    Object.entries(values).forEach(([id, value]) => {
        const input = document.getElementById(id);
        input.value = value || '';
        input.disabled = !data.can_accept || id === 'portal-agreement-email' || id === 'portal-agreement-effective-date';
    });
    document.getElementById('portal-agreement-accept').checked = accepted;
    document.getElementById('portal-agreement-accept').disabled = !data.can_accept;
    document.getElementById('portalAgreementAcceptControls').classList.toggle('hidden', accepted || !data.can_accept);
    const notice = document.getElementById('portalAgreementAcceptance');
    notice.textContent = accepted
        ? `Accepted electronically by ${provider.signatory_name || 'the Service Provider'} on ${portalDateTime(data.accepted_at)} · Agreement version ${data.agreement_version}.`
        : 'Complete any missing Service Provider details, read the Agreement and accept it before submitting Compliance.';
    notice.classList.toggle('hidden', !accepted && data.can_accept);
}

function renderPortalCompliance() {
    const data = portalCompliance || {visible: false, editable: false, status: 'Not requested', documents: []};
    const visible = data.visible === true;
    document.getElementById('portalComplianceNav').classList.toggle('hidden', !visible);
    document.getElementById('myCompliance').classList.toggle('hidden', !visible);
    document.getElementById('portalComplianceStatus').textContent = data.status || 'Not requested';
    if (!visible) { renderPortalAgreement(); return; }

    const status = data.status || 'Requested', pill = document.getElementById('portalCompliancePill');
    pill.textContent = status;
    pill.className = `pill ${status === 'Complete' ? 'pill-green' : status === 'Changes required' ? 'pill-red' : status === 'Submitted' ? 'pill-blue' : 'pill-amber'}`;
    const change = document.getElementById('portalComplianceChanges');
    change.textContent = data.change_reason ? `Requested changes: ${data.change_reason}` : '';
    change.classList.toggle('hidden', !data.change_reason);
    const readOnly = document.getElementById('portalComplianceReadOnly');
    const readOnlyMessages = {
        Submitted: 'Your submission is locked while Retodo Ops reviews the evidence.',
        Complete: 'Compliance review is complete. The information remains available to you as read-only.',
    };
    readOnly.textContent = data.editable ? '' : (readOnlyMessages[status] || 'This Compliance record is currently read-only.');
    readOnly.classList.toggle('hidden', !!data.editable);

    const education = data.education || {};
    document.getElementById('portal-degree-level').value = education.degree_level || '';
    document.getElementById('portal-degree-type').value = education.degree_type || '';
    document.getElementById('portal-field-category').value = education.field_of_study_category || '';
    document.getElementById('portal-field-other').value = education.field_of_study_other || '';
    document.getElementById('portal-institution').value = education.institution || '';
    document.getElementById('portal-education-country').innerHTML = portalCountryOptions(education.country || '');
    document.getElementById('portal-graduation-year').value = education.graduation_year || '';
    const legacyDegree = document.getElementById('portal-legacy-degree');
    legacyDegree.textContent = education.legacy_degree ? `Legacy degree label: ${education.legacy_degree}. Select the matching option before submitting.` : '';
    legacyDegree.classList.toggle('hidden', !legacyDegree.textContent);
    const legacyField = document.getElementById('portal-legacy-field');
    legacyField.textContent = education.legacy_field_of_study ? `Legacy field: ${education.legacy_field_of_study}. Select the matching option before submitting.` : '';
    legacyField.classList.toggle('hidden', !legacyField.textContent);

    const since = data.professional_since || {};
    document.getElementById('portal-translation-since').value = portalMonth(since.translation);
    document.getElementById('portal-revision-since').value = portalMonth(since.revision);
    document.getElementById('portal-mtpe-since').value = portalMonth(since.mtpe);
    const inputs = document.querySelectorAll('#myCompliance input, #myCompliance select');
    inputs.forEach(input => input.disabled = !data.editable);
    togglePortalEducationFields();
    updatePortalExperiencePreview();

    const documents = Array.isArray(data.documents) ? data.documents : [];
    const diploma = documents.filter(file => file.evidence_type === 'Diploma / certificate');
    const cv = documents.filter(file => file.evidence_type === 'CV');
    document.getElementById('portalDiplomaEvidence').innerHTML = diploma.length ? diploma.map(portalComplianceFileCard).join('') : '<div class="empty-compact">No diploma/certificate evidence uploaded.</div>';
    document.getElementById('portalCvEvidence').innerHTML = cv.length ? cv.map(portalComplianceFileCard).join('') : '<div class="empty-compact">No CV evidence uploaded.</div>';
    document.getElementById('portalComplianceActions').classList.toggle('hidden', !data.editable);
    for (const id of ['portalUploadDiplomaBtn', 'portalUploadCvBtn']) document.getElementById(id).disabled = !data.editable;
    renderPortalAgreement();
    if (location.hash === '#myCompliance') document.getElementById('myCompliance').scrollIntoView({block: 'start'});
}

function portalAgreementPayload() {
    return {
        service_provider_name: portalValue('portal-agreement-provider-name'),
        registration_or_id_number: portalValue('portal-agreement-registration'),
        service_provider_address: portalValue('portal-agreement-address'),
        tax_vat_number: portalValue('portal-agreement-registration'),
        signatory_name: portalValue('portal-agreement-signatory'),
        accepted: !!document.getElementById('portal-agreement-accept').checked,
    };
}

async function downloadPortalSignedAgreementPdf() {
    const data = portalAgreement || {};
    if (data.status !== 'Accepted') return portalShowError('Accept the Agreement before downloading the signed PDF.', 'portalAgreementError');
    const provider = data.provider || {};
    const legal = document.querySelector('#portalAgreementCard .agreement-legal-text');
    try {
        await tmsDownloadSignedAgreementPdf({
            agreement: data,
            provider,
            legalHtml: legal?.innerHTML,
        });
    } catch (error) {
        portalShowError(`Signed PDF generation failed: ${error.message}`, 'portalAgreementError');
    }
}

async function acceptPortalFrameworkAgreement() {
    portalClearError('portalAgreementError');
    if (!portalAgreement?.can_accept) return;
    if (!document.getElementById('portal-agreement-accept').checked) {
        return portalShowError('Confirm that you have read and accept the Agreement.', 'portalAgreementError');
    }
    if (!confirm('Accept Agreement version 1.0 electronically with the displayed Service Provider details?')) return;
    const button = document.getElementById('portalAcceptAgreementBtn');
    button.disabled = true;
    try {
        const {data, error} = await _sb.rpc('resource_portal_accept_framework_agreement_050', {p_payload: portalAgreementPayload()});
        if (error) throw error;
        portalAgreement = data;
        renderPortalAgreement();
        document.getElementById('portalComplianceProgress').textContent = 'Framework Agreement accepted electronically.';
    } catch (error) {
        portalShowError(error.message, 'portalAgreementError');
    } finally { button.disabled = false; }
}

function portalCompliancePayload() {
    const values = ['portal-translation-since', 'portal-revision-since', 'portal-mtpe-since'].map(portalValue);
    const now = new Date(), currentMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
    if (values.some(value => value && (!/^\d{4}-(0[1-9]|1[0-2])$/.test(value) || value > currentMonth))) throw new Error('Professional start months must be valid and not in the future.');
    const year = portalValue('portal-graduation-year');
    if (year && (!/^\d{4}$/.test(year) || Number(year) < 1900 || Number(year) > now.getUTCFullYear())) throw new Error('Enter a valid graduation year.');
    return {
        education: {
            degree_level: portalValue('portal-degree-level') || null,
            degree_type: portalValue('portal-degree-type') || null,
            field_of_study_category: portalValue('portal-field-category') || null,
            field_of_study_other: portalValue('portal-field-other') || null,
            institution: portalValue('portal-institution') || null,
            country: portalValue('portal-education-country') || null,
            end_year: year ? Number(year) : null,
        },
        translation_professional_since: values[0] ? `${values[0]}-01` : null,
        revision_professional_since: values[1] ? `${values[1]}-01` : null,
        mtpe_professional_since: values[2] ? `${values[2]}-01` : null,
    };
}

async function savePortalCompliance({quiet = false} = {}) {
    portalClearError('portalComplianceError');
    if (!portalCompliance?.editable) throw new Error('Compliance evidence is currently read-only.');
    const button = document.getElementById('portalSaveComplianceBtn');
    button.disabled = true;
    try {
        const {data, error} = await _sb.rpc('resource_portal_save_compliance_048', {p_payload: portalCompliancePayload()});
        if (error) throw error;
        portalCompliance = data;
        renderPortalCompliance();
        if (!quiet) document.getElementById('portalComplianceProgress').textContent = 'Progress saved.';
        return data;
    } catch (error) {
        portalShowError(error.message, 'portalComplianceError');
        if (quiet) throw error;
        return null;
    } finally { button.disabled = false; }
}

async function submitPortalCompliance() {
    portalClearError('portalComplianceError');
    const button = document.getElementById('portalSubmitComplianceBtn');
    button.disabled = true;
    try {
        await savePortalCompliance({quiet: true});
        const {data, error} = await _sb.rpc('resource_portal_submit_compliance_048');
        if (error) throw error;
        portalCompliance = data;
        renderPortalCompliance();
        try {
            const result = await portalComplianceWorkflowApi('notify_submission');
            document.getElementById('portalComplianceProgress').textContent = result.notification_sent || result.already_sent
                ? 'Submitted for internal review · Retodo Ops notified.'
                : 'Submitted for internal review.';
        } catch {
            document.getElementById('portalComplianceProgress').textContent = 'Submitted for internal review. The submission is visible internally; the email alert could not be delivered.';
        }
    } catch (error) {
        portalShowError(error.message, 'portalComplianceError');
    } finally { button.disabled = false; }
}

async function portalComplianceWorkflowApi(action) {
    const {data: {session}} = await _sb.auth.getSession();
    if (!session?.access_token) throw new Error('Session expired. Sign in again.');
    const response = await fetch('/.netlify/functions/resource-compliance', {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}`},
        body: JSON.stringify({action, resource_id: portalCompliance.resource_id}),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error || 'Retodo Ops could not be notified.');
    return result;
}

async function portalComplianceFileApi(action, payload = {}) {
    const {data: {session}} = await _sb.auth.getSession();
    if (!session?.access_token) throw new Error('Session expired. Sign in again.');
    const response = await fetch('/.netlify/functions/resource-compliance-files', {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}`},
        body: JSON.stringify({action, ...payload}),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error || 'The Compliance file request could not be completed.');
    return result;
}

async function uploadPortalComplianceFiles(type) {
    portalClearError('portalComplianceError');
    if (!portalCompliance?.editable) return portalShowError('Compliance evidence is currently read-only.', 'portalComplianceError');
    const input = document.getElementById(type === 'CV' ? 'portalCvFiles' : 'portalDiplomaFiles');
    const files = [...(input.files || [])];
    if (!files.length) return portalShowError('Choose at least one file.', 'portalComplianceError');
    if (!globalThis.TMS_FILE_HASH?.sha256Hex) return portalShowError('The secure file hasher is unavailable. Refresh the page.', 'portalComplianceError');
    const button = document.getElementById(type === 'CV' ? 'portalUploadCvBtn' : 'portalUploadDiplomaBtn');
    button.disabled = true;
    let uploaded = 0;
    try {
        await savePortalCompliance({quiet: true});
        const educationId = portalCompliance.education?.id || null;
        if (type === 'Diploma / certificate' && !educationId) throw new Error('Save the education record before uploading diploma evidence.');
        for (const file of files) {
            let prepared = null;
            try {
                document.getElementById('portalComplianceProgress').textContent = `Checking ${file.name} (${uploaded + 1}/${files.length})…`;
                const checksum = await TMS_FILE_HASH.sha256Hex(file);
                prepared = await portalComplianceFileApi('prepare_upload', {
                    resource_id: portalCompliance.resource_id,
                    education_id: type === 'Diploma / certificate' ? educationId : null,
                    evidence_type: type,
                    original_filename: file.name,
                    mime_type: file.type || 'application/octet-stream',
                    size_bytes: file.size,
                    checksum_sha256: checksum,
                });
                const response = await fetch(prepared.upload_url, {method: 'PUT', headers: prepared.upload_headers || {}, body: file});
                if (!response.ok) throw new Error(`Cloudflare R2 rejected the upload (HTTP ${response.status}).`);
                await portalComplianceFileApi('complete_upload', {file_id: prepared.file_id});
                uploaded++;
            } catch (error) {
                if (prepared?.file_id) await portalComplianceFileApi('discard_upload', {file_id: prepared.file_id}).catch(() => {});
                throw error;
            }
        }
        const result = await _sb.rpc('resource_portal_compliance_048');
        if (result.error) throw result.error;
        portalCompliance = result.data;
        input.value = '';
        renderPortalCompliance();
        document.getElementById('portalComplianceProgress').textContent = `${uploaded} file${uploaded === 1 ? '' : 's'} uploaded and pending internal review.`;
    } catch (error) {
        portalShowError(`${uploaded} uploaded; next file was not published: ${error.message}`, 'portalComplianceError');
    } finally { button.disabled = false; }
}

async function openPortalComplianceFile(fileId, action = 'View') {
    portalClearError('portalComplianceError');
    try {
        const signed = await portalComplianceFileApi('download', {file_id: fileId, file_action: action});
        triggerPortalDownload(signed.download_url, action === 'Download' ? signed.filename : '');
    } catch (error) { portalShowError(error.message, 'portalComplianceError'); }
}

async function deletePortalComplianceFile(fileId) {
    portalClearError('portalComplianceError');
    if (!portalCompliance?.editable) return portalShowError('Compliance evidence is currently read-only.', 'portalComplianceError');
    const filename = (portalCompliance.documents || []).find(file => file.file_id === fileId)?.filename || 'this file';
    if (!confirm(`Permanently delete ${filename} from private storage? This cannot be undone.`)) return;
    try {
        await portalComplianceFileApi('delete_file', {
            file_id: fileId,
            reason: 'Duplicate or incorrectly uploaded Compliance evidence deleted by the Resource',
        });
        const result = await _sb.rpc('resource_portal_compliance_048');
        if (result.error) throw result.error;
        portalCompliance = result.data;
        renderPortalCompliance();
        document.getElementById('portalComplianceProgress').textContent = 'Compliance evidence deleted.';
    } catch (error) { portalShowError(error.message, 'portalComplianceError'); }
}

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
        _sb.rpc('resource_portal_compliance_048'),
        _sb.rpc('resource_portal_framework_agreement_050'),
    ];
    const [jobsResult, poResult, complianceResult, agreementResult] = await Promise.all(requests);
    if (jobsResult.error) portalShowError(jobsResult.error.message);
    if (poResult.error) portalShowError(poResult.error.message);
    if (complianceResult.error) portalShowError(complianceResult.error.message);
    if (agreementResult.error) portalShowError(agreementResult.error.message);
    portalJobs = jobsResult.data || [];
    portalPurchaseOrders = poResult.data || [];
    portalCompliance = complianceResult.data || {
        visible: false,
        editable: false,
        status: 'Not requested',
        documents: [],
    };
    portalAgreement = agreementResult.data || {visible: false, status: 'Not accepted', provider: {}};
    renderPortalJobs();
    renderPortalPurchaseOrders();
    renderPortalCompliance();
}

document.getElementById('jobSearch').addEventListener('input', renderPortalJobs);
document.getElementById('poSearch').addEventListener('input', renderPortalPurchaseOrders);
document.getElementById('portal-degree-level').addEventListener('change', togglePortalEducationFields);
document.getElementById('portal-field-category').addEventListener('change', togglePortalEducationFields);
for (const id of ['portal-translation-since', 'portal-revision-since', 'portal-mtpe-since']) {
    document.getElementById(id).addEventListener('input', updatePortalExperiencePreview);
}
loadPortalDashboard();
