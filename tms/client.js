let clientId = null;
let client = null;
let accounts = [];
let contacts = [];
let billingEntities = [];
let specializations = [];
let accountSpecializations = [];
let rateCards = [];
let rateItems = [];
let selectedRateCardId = null;
let activePane = 'basic';
const CLIENT_CAT_BANDS = ['50–74%', '75–84%', '85–94%', '95–99%', '100%', 'Repetitions'];

const escapeHtml = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');

const value = id => document.getElementById(id).value.trim();
const nullable = id => value(id) || null;
const accountById = id => accounts.find(account => account.id === id);
const specializationById = id => specializations.find(item => item.id === id);

function toggleSub(id, item) {
    document.getElementById(id).classList.toggle('open');
    item.classList.toggle('open');
}

function showError(message) {
    const el = document.getElementById('recordError');
    el.textContent = message;
    el.classList.remove('hidden');
    el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function setModalError(id, message) {
    const el = document.getElementById(id);
    el.textContent = message;
    el.classList.remove('hidden');
}

function closeModal(id) {
    document.getElementById(id).classList.add('hidden');
    document.querySelectorAll(`#${id} .error-msg`).forEach(el => el.classList.add('hidden'));
}

function normalizedCode(raw) {
    return raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
}

function setSaveStatus(message) {
    const el = document.getElementById('saveStatus');
    el.textContent = message;
    window.clearTimeout(setSaveStatus.timer);
    setSaveStatus.timer = window.setTimeout(() => { el.textContent = ''; }, 3000);
}

function pill(status) {
    const cls = status === 'Active' ? 'pill-green' : status === 'On Hold' ? 'pill-amber' : 'pill-red';
    return `<span class="pill ${cls}">${escapeHtml(status)}</span>`;
}

function setClientHeader() {
    document.getElementById('clientTitle').textContent = client.name;
    document.getElementById('clientBreadcrumb').textContent = client.name;
    document.getElementById('clientSubtitle').textContent = [
        client.code,
        client.client_type === 'Direct' ? 'Direct client' : 'LSP / Agency',
        client.country_code,
    ].filter(Boolean).join(' · ');
    document.title = `${client.name} — RetodoOps TMS`;
}

function populateBasic() {
    const fields = {
        'c-name': client.name, 'c-code': client.code, 'c-legal': client.legal_name,
        'c-type': client.client_type, 'c-website': client.website,
        'c-country': client.country_code, 'c-currency': client.default_currency,
        'c-payment': client.default_payment_days, 'c-cat': client.default_cat_system,
        'c-restriction': client.restriction_status,
        'c-restriction-reason': client.restriction_reason,
        'c-instructions': client.instructions,
        'c-confidentiality': client.confidentiality_notes,
    };
    Object.entries(fields).forEach(([id, fieldValue]) => {
        document.getElementById(id).value = fieldValue ?? '';
    });
}

async function saveBasic() {
    const name = value('c-name');
    const code = normalizedCode(value('c-code'));
    if (!name || !code) {
        showError('Display name and project code are required.');
        return;
    }
    const changes = {
        name,
        code,
        legal_name: nullable('c-legal'),
        client_type: value('c-type'),
        website: nullable('c-website'),
        country_code: value('c-country').toUpperCase() || null,
        default_currency: value('c-currency'),
        default_payment_days: value('c-payment') === '' ? null : Number(value('c-payment')),
        default_cat_system: nullable('c-cat'),
        restriction_status: value('c-restriction'),
        restriction_reason: nullable('c-restriction-reason'),
        instructions: nullable('c-instructions'),
        confidentiality_notes: nullable('c-confidentiality'),
    };
    const { data, error } = await _sb.from('clients').update(changes).eq('id', clientId).select('*').single();
    if (error) {
        showError(error.code === '23505' ? 'That client code is already in use.' : error.message);
        return;
    }
    client = data;
    setClientHeader();
    setSaveStatus('Saved ✓');
}

function saveActiveTab() {
    if (activePane === 'basic') saveBasic();
    else setSaveStatus('Changes in this tab are saved from each dialog.');
}

function switchPane(name) {
    activePane = name;
    document.querySelectorAll('.record-tab').forEach(tab => tab.classList.toggle('active', tab.dataset.tab === name));
    document.querySelectorAll('.record-pane').forEach(pane => pane.classList.toggle('active', pane.id === `pane-${name}`));
}

function renderAccounts() {
    document.getElementById('accountCount').textContent = accounts.length;
    const body = document.getElementById('accountsTbody');
    if (!accounts.length) {
        body.innerHTML = '<tr class="state-row"><td colspan="7">No accounts yet.</td></tr>';
        return;
    }
    body.innerHTML = accounts.map(account => {
        const names = accountSpecializations
            .filter(link => link.account_id === account.id)
            .map(link => specializationById(link.specialization_id)?.name)
            .filter(Boolean);
        return `<tr class="clickable-row" data-id="${account.id}">
            <td><span class="code-badge">${escapeHtml(account.code || '—')}</span></td>
            <td><div class="customer-main">${escapeHtml(account.name)}</div></td>
            <td><div class="tag-list">${names.length ? names.map(name => `<span class="tag">${escapeHtml(name)}</span>`).join('') : '<span class="muted">None</span>'}</div></td>
            <td>${escapeHtml(account.default_production_mode || 'Not selected')}</td>
            <td>${escapeHtml(account.default_cat_system || '—')}</td>
            <td>${escapeHtml(account.blind_cv_label || 'Confidential account')}</td>
            <td>${pill(account.restriction_status)}</td>
        </tr>`;
    }).join('');
    body.querySelectorAll('.clickable-row').forEach(row => row.addEventListener('click', () => openAccountModal(row.dataset.id)));
}

function renderSpecializationCheckboxes(selectedIds = []) {
    document.getElementById('a-specializations').innerHTML = specializations.map(item => `
        <label class="checkbox-row"><input type="checkbox" value="${item.id}" ${selectedIds.includes(item.id) ? 'checked' : ''}>${escapeHtml(item.name)}</label>
    `).join('');
}

function openAccountModal(accountId = null) {
    const account = accountId ? accountById(accountId) : null;
    document.getElementById('accountModalTitle').textContent = account ? 'Edit account' : 'Add account';
    const values = {
        'a-id': account?.id, 'a-name': account?.name, 'a-code': account?.code,
        'a-source': account?.default_source_language, 'a-cat': account?.default_cat_system,
        'a-production': account?.default_production_mode || 'Not selected',
        'a-blind': account?.blind_cv_label, 'a-instructions': account?.instructions,
        'a-terminology': account?.terminology_notes,
        'a-communication': account?.communication_boundaries,
        'a-confidentiality': account?.confidentiality_notes,
        'a-restriction': account?.restriction_status || 'Active',
        'a-restriction-reason': account?.restriction_reason,
    };
    Object.entries(values).forEach(([id, fieldValue]) => { document.getElementById(id).value = fieldValue ?? ''; });
    document.getElementById('a-disclose').checked = !!account?.allow_name_in_blind_cv;
    renderSpecializationCheckboxes(accountSpecializations.filter(link => link.account_id === accountId).map(link => link.specialization_id));
    document.getElementById('accountModal').classList.remove('hidden');
}

async function saveAccount() {
    const accountId = value('a-id');
    const name = value('a-name');
    if (!name) return setModalError('accountError', 'Account name is required.');
    const selected = [...document.querySelectorAll('#a-specializations input:checked')].map(input => input.value);
    if (!selected.length) return setModalError('accountError', 'Select at least one Account specialization.');
    const payload = {
        client_id: clientId,
        name,
        code: normalizedCode(value('a-code')) || null,
        default_source_language: nullable('a-source'),
        default_cat_system: nullable('a-cat'),
        default_production_mode: value('a-production'),
        blind_cv_label: nullable('a-blind'),
        allow_name_in_blind_cv: document.getElementById('a-disclose').checked,
        instructions: nullable('a-instructions'),
        terminology_notes: nullable('a-terminology'),
        communication_boundaries: nullable('a-communication'),
        confidentiality_notes: nullable('a-confidentiality'),
        restriction_status: value('a-restriction'),
        restriction_reason: nullable('a-restriction-reason'),
    };
    const result = accountId
        ? await _sb.from('client_accounts').update(payload).eq('id', accountId).select('id').single()
        : await _sb.from('client_accounts').insert(payload).select('id').single();
    if (result.error) return setModalError('accountError', result.error.message);

    const savedId = result.data.id;
    const deletion = await _sb.from('client_account_specializations').delete().eq('account_id', savedId);
    if (deletion.error) return setModalError('accountError', `Account saved, but defaults could not be updated: ${deletion.error.message}`);
    if (selected.length) {
        const insertion = await _sb.from('client_account_specializations').insert(selected.map(id => ({ account_id: savedId, specialization_id: id })));
        if (insertion.error) return setModalError('accountError', `Account saved, but defaults could not be updated: ${insertion.error.message}`);
    }
    closeModal('accountModal');
    await loadAccountData();
    setSaveStatus('Account saved ✓');
}

function accountOptions(selected = '') {
    return '<option value="">Client-wide</option>' + accounts.map(account =>
        `<option value="${account.id}" ${account.id === selected ? 'selected' : ''}>${escapeHtml(account.name)}</option>`
    ).join('');
}

function renderContacts() {
    document.getElementById('contactCount').textContent = contacts.length;
    const body = document.getElementById('contactsTbody');
    if (!contacts.length) {
        body.innerHTML = '<tr class="state-row"><td colspan="7">No contacts yet.</td></tr>';
        return;
    }
    body.innerHTML = contacts.map(contact => `<tr class="clickable-row" data-id="${contact.id}">
        <td><div class="customer-main">${escapeHtml(contact.full_name)}</div></td>
        <td>${escapeHtml(accountById(contact.account_id)?.name || 'Client-wide')}</td>
        <td>${escapeHtml(contact.job_title || '—')}</td><td>${contact.email ? `<a class="table-link" href="mailto:${escapeHtml(contact.email)}">${escapeHtml(contact.email)}</a>` : '—'}</td>
        <td>${escapeHtml(contact.phone || '—')}</td><td>${contact.is_primary ? '<span class="pill pill-blue">Primary</span>' : '—'}</td>
        <td>${contact.active ? '<span class="pill pill-green">Active</span>' : '<span class="pill">Inactive</span>'}</td>
    </tr>`).join('');
    body.querySelectorAll('.clickable-row').forEach(row => row.addEventListener('click', event => {
        if (!event.target.closest('a')) openContactModal(row.dataset.id);
    }));
}

function renderBillingEntities() {
    document.getElementById('billingCount').textContent = billingEntities.length;
    const body = document.getElementById('billingTbody');
    if (!billingEntities.length) {
        body.innerHTML = '<tr class="state-row"><td colspan="7">No billing entities yet. One is required before issuing an invoice.</td></tr>';
        return;
    }
    body.innerHTML = billingEntities.map(entity => `<tr class="clickable-row" data-id="${entity.id}">
        <td><div class="customer-main">${escapeHtml(entity.name)}</div>${entity.is_default ? '<span class="pill pill-blue">Default</span>' : ''}</td>
        <td>${escapeHtml(entity.legal_name)}</td><td>${escapeHtml(entity.country_code)}</td>
        <td>${escapeHtml(entity.vat_number || entity.registration_number || '—')}</td>
        <td>${entity.billing_email ? `<a class="table-link" href="mailto:${escapeHtml(entity.billing_email)}">${escapeHtml(entity.billing_email)}</a>` : '—'}</td>
        <td>${entity.payment_terms_days == null ? 'Client default' : `${entity.payment_terms_days} days`}</td>
        <td>${entity.active ? '<span class="pill pill-green">Active</span>' : '<span class="pill">Inactive</span>'}</td>
    </tr>`).join('');
    body.querySelectorAll('.clickable-row').forEach(row => row.addEventListener('click', event => {
        if (!event.target.closest('a')) openBillingModal(row.dataset.id);
    }));
}

function openBillingModal(entityId = null) {
    const entity = billingEntities.find(item => item.id === entityId);
    document.getElementById('billingModalTitle').textContent = entity ? 'Edit billing entity' : 'Add billing entity';
    const fields = {
        'be-id': entity?.id, 'be-name': entity?.name, 'be-legal': entity?.legal_name,
        'be-address1': entity?.address_line_1, 'be-address2': entity?.address_line_2,
        'be-city': entity?.city, 'be-postal': entity?.postal_code, 'be-region': entity?.region,
        'be-country': entity?.country_code, 'be-vat': entity?.vat_number,
        'be-registration': entity?.registration_number, 'be-email': entity?.billing_email,
        'be-currency': entity?.default_currency || client.default_currency || 'EUR',
        'be-terms': entity?.payment_terms_days, 'be-notes': entity?.invoice_notes,
    };
    Object.entries(fields).forEach(([id, fieldValue]) => { document.getElementById(id).value = fieldValue ?? ''; });
    document.getElementById('be-default').checked = entity ? entity.is_default : !billingEntities.some(item => item.is_default);
    document.getElementById('be-active').checked = entity ? entity.active : true;
    document.getElementById('billingModal').classList.remove('hidden');
}

async function saveBillingEntity() {
    const entityId = value('be-id');
    const required = ['be-name', 'be-legal', 'be-address1', 'be-city', 'be-country'];
    if (required.some(id => !value(id))) return setModalError('billingError', 'Label, legal name, address, city and country are required.');
    const payload = {
        client_id: clientId, name: value('be-name'), legal_name: value('be-legal'),
        address_line_1: value('be-address1'), address_line_2: nullable('be-address2'),
        city: value('be-city'), postal_code: nullable('be-postal'), region: nullable('be-region'),
        country_code: value('be-country').toUpperCase(), vat_number: nullable('be-vat'),
        registration_number: nullable('be-registration'), billing_email: nullable('be-email'),
        default_currency: value('be-currency'),
        payment_terms_days: value('be-terms') === '' ? null : Number(value('be-terms')),
        invoice_notes: nullable('be-notes'), is_default: document.getElementById('be-default').checked,
        active: document.getElementById('be-active').checked,
    };
    const { error } = entityId
        ? await _sb.from('client_billing_entities').update(payload).eq('id', entityId)
        : await _sb.from('client_billing_entities').insert(payload);
    if (error) return setModalError('billingError', error.message);
    closeModal('billingModal');
    await loadBillingData();
    setSaveStatus('Billing entity saved ✓');
}

function openContactModal(contactId = null) {
    const contact = contacts.find(item => item.id === contactId);
    document.getElementById('contactModalTitle').textContent = contact ? 'Edit contact' : 'Add contact';
    document.getElementById('ct-id').value = contact?.id || '';
    document.getElementById('ct-name').value = contact?.full_name || '';
    document.getElementById('ct-account').innerHTML = accountOptions(contact?.account_id || '');
    document.getElementById('ct-title').value = contact?.job_title || '';
    document.getElementById('ct-email').value = contact?.email || '';
    document.getElementById('ct-phone').value = contact?.phone || '';
    document.getElementById('ct-primary').checked = !!contact?.is_primary;
    document.getElementById('ct-active').checked = contact ? contact.active : true;
    document.getElementById('ct-notes').value = contact?.notes || '';
    document.getElementById('contactModal').classList.remove('hidden');
}

async function saveContact() {
    const contactId = value('ct-id');
    if (!value('ct-name')) return setModalError('contactError', 'Full name is required.');
    const payload = {
        client_id: clientId, account_id: nullable('ct-account'), full_name: value('ct-name'),
        job_title: nullable('ct-title'), email: nullable('ct-email'), phone: nullable('ct-phone'),
        is_primary: document.getElementById('ct-primary').checked,
        active: document.getElementById('ct-active').checked, notes: nullable('ct-notes'),
    };
    const { error } = contactId
        ? await _sb.from('client_contacts').update(payload).eq('id', contactId)
        : await _sb.from('client_contacts').insert(payload);
    if (error) return setModalError('contactError', error.message);
    closeModal('contactModal');
    await loadContactData();
    setSaveStatus('Contact saved ✓');
}

function renderRateCards() {
    document.getElementById('rateCardCount').textContent = rateCards.length;
    const list = document.getElementById('rateCardsList');
    if (!rateCards.length) {
        list.innerHTML = '<div class="empty-compact">No rate cards yet.</div>';
        return;
    }
    if (!selectedRateCardId || !rateCards.some(card => card.id === selectedRateCardId)) selectedRateCardId = rateCards[0].id;
    list.innerHTML = rateCards.map(card => `<button class="rate-card-choice ${card.id === selectedRateCardId ? 'active' : ''}" data-id="${card.id}">
        <span><strong>${escapeHtml(card.name)}</strong><small>${escapeHtml(accountById(card.account_id)?.name || 'Client-wide')}</small></span>
        <span><strong>${escapeHtml(card.currency)}</strong><small>${card.active ? 'Active' : 'Inactive'}</small></span>
    </button>`).join('');
    list.querySelectorAll('button').forEach(button => button.addEventListener('click', async () => {
        selectedRateCardId = button.dataset.id;
        renderRateCards();
        await loadRateItems();
    }));
    const selected = rateCards.find(card => card.id === selectedRateCardId);
    document.getElementById('selectedRateCardLabel').textContent = selected ? `${selected.name} · ${selected.currency}` : 'Select a rate card';
    document.getElementById('addRateItemBtn').disabled = !selected;
}

function renderRateItems() {
    const body = document.getElementById('rateItemsTbody');
    if (!selectedRateCardId) {
        body.innerHTML = '<tr class="state-row"><td colspan="6">Select a rate card.</td></tr>';
        return;
    }
    const activeItems = rateItems.filter(item => item.active !== false);
    const bases = activeItems.filter(item => !item.base_rate_id);
    if (!bases.length) {
        body.innerHTML = '<tr class="state-row"><td colspan="6">No base rates in this card.</td></tr>';
        return;
    }
    const currency = rateCards.find(card => card.id === selectedRateCardId)?.currency || 'EUR';
    const children = new Map();
    activeItems.filter(item => item.base_rate_id).forEach(item => {
        if (!children.has(item.base_rate_id)) children.set(item.base_rate_id, []);
        children.get(item.base_rate_id).push(item);
    });
    body.innerHTML = bases.map(base => {
        const baseRow = `<tr class="clickable-row rate-base-row" data-id="${base.id}">
            <td>${escapeHtml(clientRateLanguages(base, 'source').join(', ') || 'Any')} → ${escapeHtml(clientRateLanguages(base, 'target').join(', ') || 'Any')}</td>
            <td>${escapeHtml(base.service_type)}<div class="customer-sub">${escapeHtml(specializationById(base.specialization_id)?.name || 'Any specialization')}</div></td>
            <td>${escapeHtml(base.unit)}<div class="customer-sub">Base price / New words</div></td><td>—</td>
            <td class="number-cell"><strong>${Number(base.rate).toFixed(4)} ${escapeHtml(currency)}</strong></td><td class="number-cell">${base.minimum_fee == null ? '—' : `${Number(base.minimum_fee).toFixed(2)} ${escapeHtml(currency)}`}</td>
        </tr>`;
        const childRows = (children.get(base.id) || []).sort((a, b) => CLIENT_CAT_BANDS.indexOf(a.cat_band) - CLIENT_CAT_BANDS.indexOf(b.cat_band)).map(item => `<tr class="rate-band-row">
            <td></td><td></td><td>${escapeHtml(item.cat_band)}</td><td>${Number(item.discount_percent).toFixed(2).replace(/\.00$/, '')}%</td>
            <td class="number-cell">${Number(item.rate).toFixed(4)} ${escapeHtml(currency)}</td><td></td>
        </tr>`).join('');
        return baseRow + childRows;
    }).join('');
    body.querySelectorAll('.clickable-row').forEach(row => row.addEventListener('click', () => openRateItemModal(row.dataset.id)));
}

function openRateCardModal() {
    document.getElementById('rc-name').value = '';
    document.getElementById('rc-account').innerHTML = accountOptions();
    document.getElementById('rc-currency').value = client.default_currency || 'EUR';
    document.getElementById('rateCardModal').classList.remove('hidden');
}

async function saveRateCard() {
    if (!value('rc-name')) return setModalError('rateCardError', 'Rate-card name is required.');
    const { data, error } = await _sb.from('client_rate_cards').insert({
        client_id: clientId, account_id: nullable('rc-account'), name: value('rc-name'),
        currency: value('rc-currency'),
    }).select('*').single();
    if (error) return setModalError('rateCardError', error.message);
    selectedRateCardId = data.id;
    closeModal('rateCardModal');
    await loadRateCardData();
    setSaveStatus('Rate card created ✓');
}

function specializationOptions(selected = '') {
    return '<option value="">Any specialization</option>' + specializations.map(item =>
        `<option value="${item.id}" ${item.id === selected ? 'selected' : ''}>${escapeHtml(item.name)}</option>`
    ).join('');
}

function clientRateLanguages(rate, side) {
    const list = rate?.[`${side}_languages`];
    if (Array.isArray(list) && list.length) return list;
    const scalar = rate?.[`${side}_language`];
    return scalar ? [scalar] : [];
}

function selectedClientRateLanguages(containerId) {
    return [...document.querySelectorAll(`#${containerId} input:checked`)].map(input => input.value);
}

function renderClientRateLanguageOptions(item = null) {
    const selectedSources = new Set(clientRateLanguages(item, 'source'));
    const selectedTargets = new Set(clientRateLanguages(item, 'target'));
    const rows = selected => TMS_REF.languages.map(language =>
        `<label class="checkbox-row"><input type="checkbox" value="${escapeHtml(language)}" ${selected.has(language) ? 'checked' : ''}>${escapeHtml(language)}</label>`
    ).join('');
    document.getElementById('ri-sources').innerHTML = rows(selectedSources);
    document.getElementById('ri-targets').innerHTML = rows(selectedTargets);
}

function openRateItemModal(itemId = null) {
    if (!selectedRateCardId) return;
    const item = rateItems.find(row => row.id === itemId && !row.base_rate_id);
    document.getElementById('rateItemModalTitle').textContent = item ? 'Edit base rate' : 'Add base rate';
    document.getElementById('ri-id').value = item?.id || '';
    renderClientRateLanguageOptions(item);
    document.getElementById('ri-service').value = item?.service_type || 'Translation';
    document.getElementById('ri-specialization').innerHTML = specializationOptions(item?.specialization_id || '');
    document.getElementById('ri-unit').value = item?.unit || 'Source words';
    document.getElementById('ri-rate').value = item?.rate ?? '';
    document.getElementById('ri-minimum').value = item?.minimum_fee ?? '';
    document.getElementById('ri-notes').value = item?.notes || '';
    renderClientCatDiscountRows(item?.id || null);
    toggleClientCatDiscounts();
    document.getElementById('rateItemModal').classList.remove('hidden');
}

function renderClientCatDiscountRows(baseId = null) {
    const children = rateItems.filter(item => item.base_rate_id === baseId && item.active !== false);
    document.getElementById('clientCatDiscountRows').innerHTML = CLIENT_CAT_BANDS.map(band => {
        const child = children.find(item => item.cat_band === band);
        return `<tr><td>${escapeHtml(band)}</td><td><input class="client-cat-discount" data-band="${escapeHtml(band)}" type="number" min="0" max="100" step="0.01" placeholder="%" value="${child?.discount_percent ?? ''}"></td><td class="client-cat-calculated">—</td></tr>`;
    }).join('');
    document.querySelectorAll('#clientCatDiscountRows .client-cat-discount').forEach(input => input.addEventListener('input', calculateClientCatRates));
    calculateClientCatRates();
}

function calculateClientCatRates() {
    const rawBase = value('ri-rate');
    const base = Number(rawBase);
    const currency = rateCards.find(card => card.id === selectedRateCardId)?.currency || 'EUR';
    document.querySelectorAll('#clientCatDiscountRows tr').forEach(row => {
        const raw = row.querySelector('.client-cat-discount').value;
        const output = row.querySelector('.client-cat-calculated');
        output.textContent = raw === '' || rawBase === '' || !Number.isFinite(base)
            ? '—' : `${(base * (1 - Number(raw) / 100)).toFixed(4)} ${escapeHtml(currency)}`;
    });
}

function toggleClientCatDiscounts() {
    const enabled = ['Source words', 'Target words'].includes(value('ri-unit'));
    document.getElementById('clientCatDiscountSection').classList.toggle('hidden', !enabled);
}

async function saveRateItem() {
    const itemId = value('ri-id');
    const rate = Number(value('ri-rate'));
    if (value('ri-rate') === '' || Number.isNaN(rate) || rate < 0) return setModalError('rateItemError', 'A valid non-negative rate is required.');
    const sources = selectedClientRateLanguages('ri-sources');
    const targets = selectedClientRateLanguages('ri-targets');
    const discounts = [...document.querySelectorAll('#clientCatDiscountRows .client-cat-discount')]
        .filter(input => input.value !== '')
        .map(input => ({ cat_band: input.dataset.band, discount_percent: Number(input.value) }));
    if (discounts.some(item => item.discount_percent < 0 || item.discount_percent > 100)) return setModalError('rateItemError', 'CAT discounts must be between 0% and 100%.');
    const payload = {
        base_rate_id: itemId || null,
        rate_card_id: selectedRateCardId, source_languages: sources,
        target_languages: targets, service_type: value('ri-service'),
        specialization_id: nullable('ri-specialization'), unit: value('ri-unit'),
        base_rate: rate,
        minimum_fee: value('ri-minimum') === '' ? null : Number(value('ri-minimum')),
        notes: nullable('ri-notes'),
        cat_discounts: ['Source words', 'Target words'].includes(value('ri-unit')) ? discounts : [],
    };
    const { error } = await _sb.rpc('save_client_rate_card_item', { p_payload: payload });
    if (error) return setModalError('rateItemError', error.message);
    closeModal('rateItemModal');
    await loadRateItems();
    setSaveStatus('Base rate saved ✓');
}

async function loadAccountData() {
    const [{ data: accountRows, error }, { data: links }] = await Promise.all([
        _sb.from('client_accounts').select('*').eq('client_id', clientId).order('name'),
        _sb.from('client_account_specializations').select('account_id,specialization_id'),
    ]);
    if (error) return showError(error.message);
    accounts = accountRows || [];
    const ids = new Set(accounts.map(account => account.id));
    accountSpecializations = (links || []).filter(link => ids.has(link.account_id));
    renderAccounts();
    renderContacts();
    renderRateCards();
}

async function loadContactData() {
    const { data, error } = await _sb.from('client_contacts').select('*').eq('client_id', clientId).order('full_name');
    if (error) return showError(error.message);
    contacts = data || [];
    renderContacts();
}

async function loadBillingData() {
    const { data, error } = await _sb.from('client_billing_entities').select('*').eq('client_id', clientId)
        .order('is_default', { ascending: false }).order('name');
    if (error) return showError(error.message);
    billingEntities = data || [];
    renderBillingEntities();
}

async function loadRateCardData() {
    const { data, error } = await _sb.from('client_rate_cards').select('*').eq('client_id', clientId).order('name');
    if (error) return showError(error.message);
    rateCards = data || [];
    renderRateCards();
    await loadRateItems();
}

async function loadRateItems() {
    if (!selectedRateCardId) {
        rateItems = [];
        renderRateItems();
        return;
    }
    const { data, error } = await _sb.from('client_rate_items').select('*').eq('rate_card_id', selectedRateCardId).order('service_type').order('created_at');
    if (error) return showError(error.message);
    rateItems = data || [];
    renderRateItems();
}

async function loadClient() {
    const [clientResult, specResult] = await Promise.all([
        _sb.from('clients').select('*').eq('id', clientId).single(),
        _sb.from('specializations').select('*').eq('active', true).order('name'),
    ]);
    if (clientResult.error || !clientResult.data) {
        showError(clientResult.error?.message || 'Client not found.');
        return;
    }
    client = clientResult.data;
    specializations = specResult.data || [];
    setClientHeader();
    populateBasic();
    await Promise.all([loadAccountData(), loadContactData(), loadBillingData(), loadRateCardData()]);
}

document.querySelectorAll('.record-tab').forEach(tab => tab.addEventListener('click', () => switchPane(tab.dataset.tab)));
document.getElementById('c-code').addEventListener('input', event => { event.target.value = normalizedCode(event.target.value); });
document.getElementById('a-code').addEventListener('input', event => { event.target.value = normalizedCode(event.target.value); });
document.getElementById('ri-unit').addEventListener('change', toggleClientCatDiscounts);
document.getElementById('ri-rate').addEventListener('input', calculateClientCatRates);

(async () => {
    const user = await requireAuth();
    if (!user) return;
    TMS_REF.installDatalists();
    clientId = new URLSearchParams(location.search).get('id');
    if (!clientId) { location.href = 'clients.html'; return; }
    await loadClient();
})();
