const portalEsc = value => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

const portalDateTime = value => value
    ? new Intl.DateTimeFormat('en-GB', {
        dateStyle: 'medium',
        timeStyle: 'short',
    }).format(new Date(value))
    : 'Not specified';

const portalDate = value => value
    ? new Intl.DateTimeFormat('en-GB', {dateStyle: 'medium'}).format(new Date(value))
    : '—';

const portalMoney = (value, currency = 'EUR') =>
    `${Number(value || 0).toFixed(2)} ${portalEsc(currency || 'EUR')}`;

const portalMoneyText = (value, currency = 'EUR') =>
    `${Number(value || 0).toFixed(2)} ${String(currency || 'EUR')}`;

const portalNumber = value => value == null || value === ''
    ? '—'
    : Number(value).toLocaleString('en-GB', {maximumFractionDigits: 3});

const portalBytes = value => {
    const bytes = Number(value || 0);
    if (!bytes) return '—';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
    return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
};

function portalStatusClass(status = '') {
    const normalized = status.toLowerCase();
    if (/(approved|acknowledged|delivered|resolved|active)/.test(normalized)) return 'pill-green';
    if (/(progress|assigned|issued|ready|revised)/.test(normalized)) return 'pill-blue';
    if (/(revision|required|waiting|reported|investigating)/.test(normalized)) return 'pill-amber';
    if (/(cancelled|closed|critical|failed)/.test(normalized)) return 'pill-red';
    return '';
}

function portalShowError(message, id = 'portalError') {
    const element = document.getElementById(id);
    if (!element) return;
    element.textContent = message;
    element.classList.remove('hidden');
    element.scrollIntoView({behavior: 'smooth', block: 'nearest'});
}

function portalClearError(id = 'portalError') {
    const element = document.getElementById(id);
    if (!element) return;
    element.textContent = '';
    element.classList.add('hidden');
}

async function portalBoot() {
    const user = await requireAuth();
    if (!user) return null;
    const {data, error} = await _sb.rpc('resource_portal_context');
    if (error) {
        portalShowError(error.message);
        return null;
    }
    const name = document.getElementById('portalResourceName');
    const number = document.getElementById('portalResourceNumber');
    if (name) name.textContent = data.display_name || 'Resource';
    if (number) number.textContent = data.resource_number || '';
    document.body.dataset.portalStatus = data.portal_status || '';
    return data;
}

function safePortalUrl(value) {
    try {
        const url = new URL(value);
        return ['https:', 'http:'].includes(url.protocol) ? url.href : null;
    } catch {
        return null;
    }
}

function triggerPortalDownload(url, filename = '') {
    const link = document.createElement('a');
    link.href = url;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    if (filename) link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
}
