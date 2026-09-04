let serviceSettings = [];
let languageSettings = [];
let specializationSettings = [];
let settingsRole = 'user';

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
  const canEdit = settingsRole === 'admin';
  settingsEl('addServiceBtn').disabled = !canEdit;
  settingsEl('addServiceBtn').title = canEdit ? '' : 'Administrator access required';
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
  const canEdit = settingsRole === 'admin';
  settingsEl('addLanguageBtn').disabled = !canEdit;
  settingsEl('addSpecializationBtn').disabled = !canEdit;
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
function openCatalogSetting(kind, id = null) {
  if (settingsRole !== 'admin') return settingsError('Administrator access is required to change Settings.');
  const rows = kind === 'language' ? languageSettings : specializationSettings;
  const row = rows.find(item => item.id === id);
  settingsEl('cs-kind').value = kind; settingsEl('cs-id').value = row?.id || '';
  settingsEl('catalogSettingTitle').textContent = `${row ? 'Edit' : 'Add'} ${kind}`;
  settingsEl('cs-name').value = row?.name || ''; settingsEl('cs-code').value = row?.code || '';
  settingsEl('cs-order').value = row?.sort_order ?? ((rows.length + 1) * 10);
  settingsEl('cs-active').checked = row?.active !== false;
  settingsEl('cs-order-field').classList.toggle('hidden', kind !== 'language');
  clearSettingsError('catalogSettingError'); settingsEl('catalogSettingModal').classList.remove('hidden');
  settingsEl('cs-name').focus();
}
async function saveCatalogSetting() {
  clearSettingsError('catalogSettingError');
  const kind = settingsEl('cs-kind').value, id = settingsEl('cs-id').value;
  const name = settingsEl('cs-name').value.trim(), code = settingsEl('cs-code').value.trim().toUpperCase();
  if (!name || !code) return settingsError('Name and code are required.', 'catalogSettingError');
  const table = kind === 'language' ? 'language_catalog' : 'specializations';
  const payload = {name, code, active: settingsEl('cs-active').checked};
  if (kind === 'language') payload.sort_order = Number(settingsEl('cs-order').value || 0);
  const result = id ? await _sb.from(table).update(payload).eq('id', id) : await _sb.from(table).insert(payload);
  if (result.error) return settingsError(result.error.message, 'catalogSettingError');
  closeCatalogSetting(); await loadCatalogSettings();
}
async function toggleCatalogSetting(kind, id) {
  if (settingsRole !== 'admin') return;
  const rows = kind === 'language' ? languageSettings : specializationSettings;
  const row = rows.find(item => item.id === id); if (!row) return;
  if (!confirm(`${row.active ? 'Deactivate' : 'Activate'} ${row.name}? Historical records remain unchanged.`)) return;
  const table = kind === 'language' ? 'language_catalog' : 'specializations';
  const {error} = await _sb.from(table).update({active: !row.active}).eq('id', id);
  if (error) return settingsError(error.message); await loadCatalogSettings();
}

function openServiceSetting(id = null) {
  if (settingsRole !== 'admin') return settingsError('Administrator access is required to change Settings.');
  const service = serviceSettings.find(row => row.id === id);
  settingsEl('serviceSettingTitle').textContent = service ? 'Edit service' : 'Add service';
  settingsEl('ss-id').value = service?.id || '';
  settingsEl('ss-name').value = service?.name || '';
  settingsEl('ss-code').value = service?.code || '';
  settingsEl('ss-order').value = service?.sort_order ?? ((serviceSettings.length + 1) * 10);
  settingsEl('ss-description').value = service?.description || '';
  settingsEl('ss-active').checked = service?.active !== false;
  settingsEl('ss-name').readOnly = !!service;
  settingsEl('ss-code').readOnly = !!service;
  clearSettingsError('serviceSettingError');
  settingsEl('serviceSettingModal').classList.remove('hidden');
  settingsEl(service ? 'ss-order' : 'ss-name').focus();
}

async function saveServiceSetting() {
  clearSettingsError('serviceSettingError');
  const id = settingsEl('ss-id').value;
  const name = settingsEl('ss-name').value.trim();
  const code = normalizeServiceCode(settingsEl('ss-code').value);
  const sortOrder = Number(settingsEl('ss-order').value || 0);
  if (!name) return settingsError('Enter a service name.', 'serviceSettingError');
  if (code.length < 2) return settingsError('Enter a Job code containing 2–8 letters or numbers.', 'serviceSettingError');
  const payload = { description: settingsEl('ss-description').value.trim() || null, sort_order: sortOrder, active: settingsEl('ss-active').checked };
  const result = id
    ? await _sb.from('service_catalog').update(payload).eq('id', id)
    : await _sb.from('service_catalog').insert({ ...payload, name, code });
  if (result.error) return settingsError(result.error.message, 'serviceSettingError');
  closeServiceSetting();
  await loadServiceSettings();
}

async function toggleServiceSetting(id) {
  const service = serviceSettings.find(row => row.id === id); if (!service || settingsRole !== 'admin') return;
  const action = service.active ? 'deactivate' : 'activate';
  if (!confirm(`${action[0].toUpperCase() + action.slice(1)} ${service.name}? Historical records will remain unchanged.`)) return;
  const { error } = await _sb.from('service_catalog').update({ active: !service.active }).eq('id', id);
  if (error) return settingsError(error.message);
  await loadServiceSettings();
}

settingsEl('ss-code').addEventListener('input', event => { event.target.value = normalizeServiceCode(event.target.value); });
settingsEl('serviceSettingModal').addEventListener('click', event => { if (event.target === event.currentTarget) closeServiceSetting(); });
settingsEl('catalogSettingModal').addEventListener('click', event => { if (event.target === event.currentTarget) closeCatalogSetting(); });

(async () => {
  const user = await requireAuth(); if (!user) return;
  const { data } = await _sb.rpc('current_app_role'); settingsRole = data || 'user';
  await Promise.all([loadServiceSettings(), loadCatalogSettings()]);
})();
