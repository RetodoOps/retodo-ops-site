let serviceSettings = [];
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

(async () => {
  const user = await requireAuth(); if (!user) return;
  const { data } = await _sb.rpc('current_app_role'); settingsRole = data || 'user';
  await loadServiceSettings();
})();
