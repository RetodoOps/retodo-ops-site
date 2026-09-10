let serviceSettings = [];
let languageSettings = [];
let specializationSettings = [];
let retentionSettings = {policies: [], clients: [], accounts: []};
let settingsRole = 'user';

const canAddSetting = () => settingsRole === 'admin' || settingsRole === 'pm';
const canManageSetting = () => settingsRole === 'admin';

const settingsEl = id => document.getElementById(id);
const settingsEsc = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;')
  .replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');

function settingsError(message, id = 'settingsError') {
  const element = settingsEl(id); element.textContent = message; element.classList.remove('hidden'); element.focus?.();
}
function clearSettingsError(id = 'settingsError') { const element = settingsEl(id); element.textContent = ''; element.classList.add('hidden'); }
function closeServiceSetting() { settingsEl('serviceSettingModal').classList.add('hidden'); }
function normalizeServiceCode(value) { return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8); }

function renderServiceSettings() {
  const canAdd = canAddSetting(), canEdit = canManageSetting();
  settingsEl('addServiceBtn').disabled = !canAdd;
  settingsEl('addServiceBtn').title = canAdd ? '' : 'Administrator or Project Manager access required';
  settingsEl('servicesTbody').innerHTML = serviceSettings.length ? serviceSettings.map(service => `
    <tr>
      <td class="settings-order">${Number(service.sort_order || 0)}</td>
      <td><strong>${settingsEsc(service.name)}</strong></td>
      <td><span class="service-code">${settingsEsc(service.code)}</span></td>
      <td class="settings-description">${settingsEsc(service.description || '—')}</td>
      <td><span class="pill ${service.active ? 'pill-green' : ''}">${service.active ? 'Active' : 'Inactive'}</span></td>
      <td><div class="table-actions"><button class="table-action" type="button" onclick="openServiceSetting('${service.id}')" ${canEdit ? '' : 'disabled'}>Edit</button><button class="table-action ${service.active ? 'danger' : 'success'}" type="button" onclick="toggleServiceSetting('${service.id}')" ${canEdit ? '' : 'disabled'}>${service.active ? 'Deactivate' : 'Activate'}</button></div></td>
    </tr>`).join('') : '<tr class="state-row"><td colspan="6">No services configured.</td></tr>';
}

async function loadServiceSettings() {
  clearSettingsError();
  const { data, error } = await _sb.from('service_catalog').select('*').order('sort_order').order('name');
  if (error) return settingsError(error.message);
  serviceSettings = data || [];
  renderServiceSettings();
}

function renderCatalogSettings() {
  const canAdd = canAddSetting(), canEdit = canManageSetting();
  settingsEl('addLanguageBtn').disabled = !canAdd;
  settingsEl('addSpecializationBtn').disabled = !canAdd;
  settingsEl('addLanguageBtn').title = canAdd ? '' : 'Administrator or Project Manager access required';
  settingsEl('addSpecializationBtn').title = canAdd ? '' : 'Administrator or Project Manager access required';
  settingsEl('languagesTbody').innerHTML = languageSettings.length ? languageSettings.map(row => `<tr><td class="settings-order">${Number(row.sort_order || 0)}</td><td><strong>${settingsEsc(row.name)}</strong></td><td><span class="service-code">${settingsEsc(row.code)}</span></td><td><span class="pill ${row.active ? 'pill-green' : ''}">${row.active ? 'Active' : 'Inactive'}</span></td><td><div class="table-actions"><button class="table-action" onclick="openCatalogSetting('language','${row.id}')" ${canEdit?'':'disabled'}>Edit</button><button class="table-action ${row.active?'danger':'success'}" onclick="toggleCatalogSetting('language','${row.id}')" ${canEdit?'':'disabled'}>${row.active?'Deactivate':'Activate'}</button></div></td></tr>`).join('') : '<tr class="state-row"><td colspan="5">No languages configured.</td></tr>';
  settingsEl('specializationsTbody').innerHTML = specializationSettings.length ? specializationSettings.map(row => `<tr><td><strong>${settingsEsc(row.name)}</strong></td><td><span class="service-code">${settingsEsc(row.code || '—')}</span></td><td><span class="pill ${row.active ? 'pill-green' : ''}">${row.active ? 'Active' : 'Inactive'}</span></td><td><div class="table-actions"><button class="table-action" onclick="openCatalogSetting('specialization','${row.id}')" ${canEdit?'':'disabled'}>Edit</button><button class="table-action ${row.active?'danger':'success'}" onclick="toggleCatalogSetting('specialization','${row.id}')" ${canEdit?'':'disabled'}>${row.active?'Deactivate':'Activate'}</button></div></td></tr>`).join('') : '<tr class="state-row"><td colspan="4">No specializations configured.</td></tr>';
}

async function loadCatalogSettings() {
  const [languages, specializations] = await Promise.all([
    _sb.from('language_catalog').select('*').order('sort_order').order('name'),
    _sb.from('specializations').select('*').order('name')
  ]);
  if (languages.error) return settingsError(languages.error.message);
  if (specializations.error) return settingsError(specializations.error.message);
  languageSettings = languages.data || [];
  specializationSettings = specializations.data || [];
  renderCatalogSettings();
}

function closeCatalogSetting() { settingsEl('catalogSettingModal').classList.add('hidden'); }

function retentionScopeName(policy) { return policy.scope_name || policy.scope_type; }
function renderRetentionSettings() {
  const body = settingsEl('retentionPoliciesTbody'); if (!body) return;
  settingsEl('addRetentionPolicyBtn').classList.toggle('hidden', !canManageSetting());
  const rows = retentionSettings.policies || [];
  body.innerHTML = rows.length ? rows.map(policy => `<tr>
    <td><strong>${settingsEsc(retentionScopeName(policy))}</strong><div class="customer-sub">${settingsEsc(policy.scope_type)}</div></td>
    <td>${Number(policy.archive_after_months)} months after latest Project approval</td>
    <td>${Number(policy.delete_after_months)} continuous archived months</td>
    <td><span class="pill ${policy.retention_hold ? 'pill-amber' : 'pill-green'}">${policy.retention_hold ? 'Hold' : 'Automatic'}</span>${policy.hold_reason ? `<div class="customer-sub">${settingsEsc(policy.hold_reason)}</div>` : ''}</td>
    <td><div class="table-actions"><button class="table-action" type="button" onclick="openRetentionPolicy('${policy.id}')" ${canManageSetting() ? '' : 'disabled'}>Edit</button>${policy.scope_type === 'Default' ? '' : `<button class="table-action danger" type="button" onclick="deleteRetentionPolicy('${policy.id}')" ${canManageSetting() ? '' : 'disabled'}>Delete override</button>`}</div></td>
  </tr>`).join('') : '<tr class="state-row"><td colspan="5">No retention policies are available.</td></tr>';
}

async function loadRetentionSettings() {
  const {data, error} = await _sb.rpc('file_retention_settings_044');
  if (error) return settingsError(error.message);
  retentionSettings = data || {policies: [], clients: [], accounts: []};
  renderRetentionSettings();
}

function retentionScopeChanged() {
  const type = settingsEl('rp-scope-type').value, target = settingsEl('rp-scope-id');
  const rows = type === 'Client' ? retentionSettings.clients : type === 'Account' ? retentionSettings.accounts : [];
  target.innerHTML = type === 'Default' ? '<option value="">All Clients</option>' : '<option value="">Select…</option>' + rows.map(row => `<option value="${row.id}">${settingsEsc(row.name)}</option>`).join('');
  target.disabled = type === 'Default' || !!settingsEl('rp-id').value;
}

function retentionHoldChanged() {
  const hold = settingsEl('rp-hold').checked;
  settingsEl('rp-hold-reason-wrap').classList.toggle('hidden', !hold);
  settingsEl('rp-hold-reason').required = hold;
}

function closeRetentionPolicy() { settingsEl('retentionPolicyModal').classList.add('hidden'); }
function openRetentionPolicy(id = null) {
  if (!canManageSetting()) return settingsError('Only the Administrator can manage file retention.');
  const policy = retentionSettings.policies.find(row => row.id === id);
  settingsEl('rp-id').value = policy?.id || '';
  settingsEl('retentionPolicyTitle').textContent = policy ? 'Edit retention policy' : 'Add retention override';
  settingsEl('rp-scope-type').value = policy?.scope_type || 'Client';
  settingsEl('rp-scope-type').disabled = !!policy;
  retentionScopeChanged();
  settingsEl('rp-scope-id').value = policy?.scope_id || '';
  settingsEl('rp-archive-months').value = Number(policy?.archive_after_months ?? 3);
  settingsEl('rp-delete-months').value = Number(policy?.delete_after_months ?? 24);
  settingsEl('rp-hold').checked = !!policy?.retention_hold;
  settingsEl('rp-hold-reason').value = policy?.hold_reason || '';
  retentionHoldChanged(); clearSettingsError('retentionPolicyError');
  settingsEl('retentionPolicyModal').classList.remove('hidden');
}

async function saveRetentionPolicy() {
  clearSettingsError('retentionPolicyError');
  if (!canManageSetting()) return settingsError('Administrator access required.', 'retentionPolicyError');
  const scopeType = settingsEl('rp-scope-type').value;
  const scopeId = settingsEl('rp-scope-id').value || null;
  const archiveMonths = Number(settingsEl('rp-archive-months').value);
  const deleteMonths = Number(settingsEl('rp-delete-months').value);
  const hold = settingsEl('rp-hold').checked;
  const reason = settingsEl('rp-hold-reason').value.trim() || null;
  if (scopeType !== 'Default' && !scopeId) return settingsError('Select a Client or Account.', 'retentionPolicyError');
  if (!Number.isInteger(archiveMonths) || archiveMonths < 1 || !Number.isInteger(deleteMonths) || deleteMonths <= archiveMonths) return settingsError('Permanent deletion must be later than archive.', 'retentionPolicyError');
  if (hold && !reason) return settingsError('Enter a reason for Retention Hold.', 'retentionPolicyError');
  const button = settingsEl('saveRetentionPolicyBtn'); button.disabled = true;
  const {error} = await _sb.rpc('admin_save_file_retention_policy_044', {
    p_scope_type: scopeType, p_scope_id: scopeId,
    p_archive_after_months: archiveMonths, p_delete_after_months: deleteMonths,
    p_retention_hold: hold, p_hold_reason: reason,
  });
  button.disabled = false;
  if (error) return settingsError(error.message, 'retentionPolicyError');
  closeRetentionPolicy(); await loadRetentionSettings();
}

async function deleteRetentionPolicy(id) {
  const policy = retentionSettings.policies.find(row => row.id === id);
  if (!policy || policy.scope_type === 'Default' || !canManageSetting()) return;
  if (!confirm(`Delete the ${retentionScopeName(policy)} override? The next broader policy will apply.`)) return;
  const {error} = await _sb.rpc('admin_delete_file_retention_policy_044', {p_policy_id: id});
  if (error) return settingsError(error.message); await loadRetentionSettings();
}
function openCatalogSetting(kind, id = null) {
  const rows = kind === 'language' ? languageSettings : specializationSettings;
  const row = rows.find(item => item.id === id);
  if ((row && !canManageSetting()) || (!row && !canAddSetting())) {
    return settingsError(row ? 'Only the Administrator can edit catalogue values.' : 'Administrator or Project Manager access is required to add catalogue values.');
  }
  settingsEl('cs-kind').value = kind; settingsEl('cs-id').value = row?.id || '';
  settingsEl('catalogSettingTitle').textContent = `${row ? 'Edit' : 'Add'} ${kind}`;
  settingsEl('cs-name').value = row?.name || ''; settingsEl('cs-code').value = row?.code || '';
  settingsEl('cs-order').value = row?.sort_order ?? ((rows.length + 1) * 10);
  settingsEl('cs-active').checked = row?.active !== false;
  settingsEl('cs-active').disabled = !canManageSetting();
  settingsEl('cs-order-field').classList.toggle('hidden', kind !== 'language');
  clearSettingsError('catalogSettingError'); settingsEl('catalogSettingModal').classList.remove('hidden');
  settingsEl('cs-name').focus();
}
async function saveCatalogSetting() {
  clearSettingsError('catalogSettingError');
  const kind = settingsEl('cs-kind').value, id = settingsEl('cs-id').value;
  if ((id && !canManageSetting()) || (!id && !canAddSetting())) return settingsError('This role cannot save that catalogue change.', 'catalogSettingError');
  const name = settingsEl('cs-name').value.trim(), code = settingsEl('cs-code').value.trim().toUpperCase();
  if (!name || !code) return settingsError('Name and code are required.', 'catalogSettingError');
  const table = kind === 'language' ? 'language_catalog' : 'specializations';
  const payload = {name, code, active: canManageSetting() ? settingsEl('cs-active').checked : true};
  if (kind === 'language') payload.sort_order = Number(settingsEl('cs-order').value || 0);
  const result = id ? await _sb.from(table).update(payload).eq('id', id) : await _sb.from(table).insert(payload);
  if (result.error) return settingsError(result.error.message, 'catalogSettingError');
  closeCatalogSetting(); await loadCatalogSettings();
}
async function toggleCatalogSetting(kind, id) {
  if (!canManageSetting()) return;
  const rows = kind === 'language' ? languageSettings : specializationSettings;
  const row = rows.find(item => item.id === id); if (!row) return;
  if (!confirm(`${row.active ? 'Deactivate' : 'Activate'} ${row.name}? Historical records remain unchanged.`)) return;
  const table = kind === 'language' ? 'language_catalog' : 'specializations';
  const {error} = await _sb.from(table).update({active: !row.active}).eq('id', id);
  if (error) return settingsError(error.message); await loadCatalogSettings();
}

function openServiceSetting(id = null) {
  const service = serviceSettings.find(row => row.id === id);
  if ((service && !canManageSetting()) || (!service && !canAddSetting())) {
    return settingsError(service ? 'Only the Administrator can edit services.' : 'Administrator or Project Manager access is required to add services.');
  }
  settingsEl('serviceSettingTitle').textContent = service ? 'Edit service' : 'Add service';
  settingsEl('ss-id').value = service?.id || '';
  settingsEl('ss-name').value = service?.name || '';
  settingsEl('ss-code').value = service?.code || '';
  settingsEl('ss-order').value = service?.sort_order ?? ((serviceSettings.length + 1) * 10);
  settingsEl('ss-description').value = service?.description || '';
  settingsEl('ss-active').checked = service?.active !== false;
  settingsEl('ss-active').disabled = !canManageSetting();
  settingsEl('ss-name').readOnly = !!service;
  settingsEl('ss-code').readOnly = !!service;
  clearSettingsError('serviceSettingError');
  settingsEl('serviceSettingModal').classList.remove('hidden');
  settingsEl(service ? 'ss-order' : 'ss-name').focus();
}

async function saveServiceSetting() {
  clearSettingsError('serviceSettingError');
  const id = settingsEl('ss-id').value;
  if ((id && !canManageSetting()) || (!id && !canAddSetting())) return settingsError('This role cannot save that service change.', 'serviceSettingError');
  const name = settingsEl('ss-name').value.trim();
  const code = normalizeServiceCode(settingsEl('ss-code').value);
  const sortOrder = Number(settingsEl('ss-order').value || 0);
  if (!name) return settingsError('Enter a service name.', 'serviceSettingError');
  if (code.length < 2) return settingsError('Enter a Job code containing 2–8 letters or numbers.', 'serviceSettingError');
  const payload = { description: settingsEl('ss-description').value.trim() || null, sort_order: sortOrder, active: canManageSetting() ? settingsEl('ss-active').checked : true };
  const result = id
    ? await _sb.from('service_catalog').update(payload).eq('id', id)
    : await _sb.from('service_catalog').insert({ ...payload, name, code });
  if (result.error) return settingsError(result.error.message, 'serviceSettingError');
  closeServiceSetting();
  await loadServiceSettings();
}

async function toggleServiceSetting(id) {
  const service = serviceSettings.find(row => row.id === id); if (!service || !canManageSetting()) return;
  const action = service.active ? 'deactivate' : 'activate';
  if (!confirm(`${action[0].toUpperCase() + action.slice(1)} ${service.name}? Historical records will remain unchanged.`)) return;
  const { error } = await _sb.from('service_catalog').update({ active: !service.active }).eq('id', id);
  if (error) return settingsError(error.message);
  await loadServiceSettings();
}

settingsEl('ss-code').addEventListener('input', event => { event.target.value = normalizeServiceCode(event.target.value); });
settingsEl('serviceSettingModal').addEventListener('click', event => { if (event.target === event.currentTarget) closeServiceSetting(); });
settingsEl('catalogSettingModal').addEventListener('click', event => { if (event.target === event.currentTarget) closeCatalogSetting(); });
settingsEl('retentionPolicyModal').addEventListener('click', event => { if (event.target === event.currentTarget) closeRetentionPolicy(); });
settingsEl('rp-scope-type').addEventListener('change', retentionScopeChanged);
settingsEl('rp-hold').addEventListener('change', retentionHoldChanged);

function activateSettingsSection() {
  const hash = location.hash || '#services';
  document.querySelectorAll('.settings-nav-item[href]').forEach(link => {
    const active = link.getAttribute('href') === hash;
    link.classList.toggle('active', active);
    if (active) link.setAttribute('aria-current', 'page'); else link.removeAttribute('aria-current');
  });
}
document.querySelectorAll('.settings-nav-item[href]').forEach(link => link.addEventListener('click', () => {
  requestAnimationFrame(activateSettingsSection);
}));
window.addEventListener('hashchange', activateSettingsSection);
activateSettingsSection();

(async () => {
  const user = await requireAuth(); if (!user) return;
  const { data } = await _sb.rpc('current_app_role'); settingsRole = data || 'user';
  await Promise.all([loadServiceSettings(), loadCatalogSettings(), loadRetentionSettings()]);
})();
