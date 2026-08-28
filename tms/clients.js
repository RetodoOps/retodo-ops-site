let clients = [];
let accountCounts = new Map();

const escapeHtml = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');

function toggleSub(id, item) {
    document.getElementById(id).classList.toggle('open');
    item.classList.toggle('open');
}

function formatDate(value) {
    if (!value) return '—';
    return new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
        .format(new Date(value));
}

function statusClass(status) {
    if (status === 'Active') return 'pill pill-green';
    if (status === 'On Hold') return 'pill pill-amber';
    return 'pill pill-red';
}

function renderClients() {
    const query = document.getElementById('clientSearch').value.trim().toLowerCase();
    const type = document.getElementById('clientTypeFilter').value;
    const restriction = document.getElementById('restrictionFilter').value;
    const rows = clients.filter(client => {
        const haystack = `${client.name || ''} ${client.code || ''} ${client.legal_name || ''}`.toLowerCase();
        return (!query || haystack.includes(query))
            && (!type || client.client_type === type)
            && (!restriction || client.restriction_status === restriction);
    });

    document.getElementById('clientCount').textContent = `${rows.length} client${rows.length === 1 ? '' : 's'}`;
    const body = document.getElementById('clientsTbody');
    if (!rows.length) {
        body.innerHTML = '<tr class="state-row"><td colspan="8">No matching clients.</td></tr>';
        return;
    }
    body.innerHTML = rows.map(client => `<tr class="clickable-row" data-id="${client.id}">
        <td><span class="code-badge">${escapeHtml(client.code || '—')}</span></td>
        <td><div class="customer-main">${escapeHtml(client.name)}</div>${client.legal_name && client.legal_name !== client.name ? `<div class="customer-sub">${escapeHtml(client.legal_name)}</div>` : ''}</td>
        <td>${client.client_type === 'Direct' ? 'Direct client' : 'LSP / Agency'}</td>
        <td>${escapeHtml(client.country_code || '—')}</td>
        <td>${accountCounts.get(client.id) || 0}</td>
        <td>${escapeHtml(client.default_currency || 'EUR')}</td>
        <td><span class="${statusClass(client.restriction_status)}">${escapeHtml(client.restriction_status)}</span></td>
        <td>${formatDate(client.updated_at || client.created_at)}</td>
    </tr>`).join('');
    body.querySelectorAll('.clickable-row').forEach(row => row.addEventListener('click', () => {
        location.href = `client.html?id=${encodeURIComponent(row.dataset.id)}`;
    }));
}

function openCreateClient() {
    document.getElementById('clientModal').classList.remove('hidden');
    document.getElementById('newClientName').focus();
}

function closeCreateClient() {
    document.getElementById('clientModal').classList.add('hidden');
    document.getElementById('clientCreateError').classList.add('hidden');
}

function normalizedCode(value) {
    return value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
}

async function createClient() {
    const errorEl = document.getElementById('clientCreateError');
    const button = document.getElementById('createClientBtn');
    const name = document.getElementById('newClientName').value.trim();
    const code = normalizedCode(document.getElementById('newClientCode').value);
    if (!name || !code) {
        errorEl.textContent = 'Client name and code are required.';
        errorEl.classList.remove('hidden');
        return;
    }
    button.disabled = true;
    button.textContent = 'Creating…';
    const { data, error } = await _sb.from('clients').insert({
        name,
        code,
        client_type: document.getElementById('newClientType').value,
        country_code: document.getElementById('newClientCountry').value.trim().toUpperCase() || null,
        default_currency: document.getElementById('newClientCurrency').value,
    }).select('id').single();
    button.disabled = false;
    button.textContent = 'Create and open';
    if (error) {
        errorEl.textContent = error.code === '23505' ? 'That client code is already in use.' : error.message;
        errorEl.classList.remove('hidden');
        return;
    }
    location.href = `client.html?id=${encodeURIComponent(data.id)}`;
}

async function loadClients() {
    const [{ data: clientRows, error }, { data: accounts }] = await Promise.all([
        _sb.from('clients').select('*').order('name'),
        _sb.from('client_accounts').select('client_id'),
    ]);
    if (error) {
        document.getElementById('clientsTbody').innerHTML = `<tr class="state-row"><td colspan="8">${escapeHtml(error.message)}</td></tr>`;
        return;
    }
    clients = clientRows || [];
    accountCounts = new Map();
    (accounts || []).forEach(account => accountCounts.set(account.client_id, (accountCounts.get(account.client_id) || 0) + 1));
    renderClients();
}

['clientSearch', 'clientTypeFilter', 'restrictionFilter'].forEach(id =>
    document.getElementById(id).addEventListener('input', renderClients)
);
document.getElementById('newClientCode').addEventListener('input', event => {
    event.target.value = normalizedCode(event.target.value);
});

(async () => {
    const user = await requireAuth();
    if (user) await loadClients();
})();
