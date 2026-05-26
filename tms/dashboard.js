// ── Language → flag emoji ──────────────────────────────────────────────────
const LANG_FLAGS = {
    'English (US)': '🇺🇸', 'English (UK)': '🇬🇧', 'English': '🇬🇧',
    'Bulgarian': '🇧🇬', 'Swedish': '🇸🇪', 'Danish': '🇩🇰',
    'Finnish': '🇫🇮', 'Norwegian (Bokmål)': '🇳🇴', 'Norwegian': '🇳🇴',
    'German': '🇩🇪', 'French': '🇫🇷', 'Spanish': '🇪🇸', 'Italian': '🇮🇹',
    'Dutch': '🇳🇱', 'Polish': '🇵🇱', 'Portuguese': '🇵🇹', 'Russian': '🇷🇺',
    'Chinese (Simplified)': '🇨🇳', 'Chinese (Traditional)': '🇹🇼',
    'Japanese': '🇯🇵', 'Korean': '🇰🇷', 'Arabic': '🇸🇦', 'Turkish': '🇹🇷',
    'Czech': '🇨🇿', 'Hungarian': '🇭🇺', 'Romanian': '🇷🇴',
    'Slovak': '🇸🇰', 'Ukrainian': '🇺🇦', 'Greek': '🇬🇷',
    'Hebrew': '🇮🇱', 'Thai': '🇹🇭', 'Vietnamese': '🇻🇳',
};

// ── Tab definitions ────────────────────────────────────────────────────────
const TABS = [
    { key: 'due_today',    label: 'Due Today' },
    { key: 'assign',       label: 'Assign' },
    { key: 'ongoing',      label: 'Ongoing' },
    { key: 'qa_ready',     label: 'QA Ready' },
    { key: 'qa_issues',    label: 'QA Issues' },
    { key: 'pm_ready',     label: 'PM Ready' },
    { key: 'delivery',     label: 'Delivery' },
    { key: 'completed',    label: 'Completed' },
    { key: 'due_tomorrow', label: 'Due Tomorrow' },
    { key: 'upcoming',     label: 'Upcoming' },
    { key: 'approved',     label: 'Approved' },
    { key: 'all',          label: 'All' },
    { key: 'missing_po',   label: 'Missing PO' },
];

let allProjects  = [];
let activeTab    = 'due_today';
let searchQuery  = '';

// ── Date helpers ───────────────────────────────────────────────────────────
function sameDay(dateStr, offset = 0) {
    if (!dateStr) return false;
    const d = new Date(dateStr);
    const t = new Date();
    t.setDate(t.getDate() + offset);
    return d.getFullYear() === t.getFullYear()
        && d.getMonth()    === t.getMonth()
        && d.getDate()     === t.getDate();
}
const isToday    = d => sameDay(d, 0);
const isTomorrow = d => sameDay(d, 1);
const isOverdue  = d => d && new Date(d) < new Date() && !isToday(d);

function fmtDate(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    const dd   = String(d.getDate()).padStart(2,'0');
    const mm   = String(d.getMonth()+1).padStart(2,'0');
    const yyyy = d.getFullYear();
    const hh   = String(d.getHours()).padStart(2,'0');
    const min  = String(d.getMinutes()).padStart(2,'0');
    return `${dd}.${mm}.${yyyy} | ${hh}:${min}`;
}

// ── Filter helpers ─────────────────────────────────────────────────────────
function filterByTab(projects, tab) {
    switch (tab) {
        case 'due_today':    return projects.filter(p => isToday(p.deadline));
        case 'assign':       return projects.filter(p => p.status === 'Assign');
        case 'ongoing':      return projects.filter(p => p.status === 'Ongoing');
        case 'qa_ready':     return projects.filter(p => p.status === 'QA Ready');
        case 'qa_issues':    return projects.filter(p => p.status === 'QA Issues');
        case 'pm_ready':     return projects.filter(p => p.status === 'PM Ready');
        case 'delivery':     return projects.filter(p => p.status === 'Delivery');
        case 'completed':    return projects.filter(p => p.status === 'Completed');
        case 'due_tomorrow': return projects.filter(p => isTomorrow(p.deadline));
        case 'upcoming':     return projects.filter(p => p.upcoming);
        case 'approved':     return projects.filter(p => p.status === 'Approved');
        case 'missing_po':   return projects.filter(p => p.missing_po);
        default:             return projects;
    }
}

function filterBySearch(projects, q) {
    if (!q) return projects;
    const lc = q.toLowerCase();
    return projects.filter(p =>
        (p.project_number    || '').toLowerCase().includes(lc) ||
        (p.clients?.name     || '').toLowerCase().includes(lc) ||
        (p.sub_client        || '').toLowerCase().includes(lc) ||
        (p.project_manager   || '').toLowerCase().includes(lc) ||
        (p.qa_specialist     || '').toLowerCase().includes(lc) ||
        (p.linguist          || '').toLowerCase().includes(lc) ||
        (p.project_type      || '').toLowerCase().includes(lc) ||
        (p.status            || '').toLowerCase().includes(lc)
    );
}

// ── Render tabs ────────────────────────────────────────────────────────────
function renderTabs() {
    const bar = document.getElementById('tabsBar');
    bar.innerHTML = TABS.map(t => {
        const count  = filterByTab(allProjects, t.key).length;
        const active = t.key === activeTab ? 'active' : '';
        return `<button class="tab ${active}" data-tab="${t.key}">
            ${t.label}
            <span class="tab-badge">${count}</span>
        </button>`;
    }).join('');

    bar.querySelectorAll('.tab').forEach(btn =>
        btn.addEventListener('click', () => {
            activeTab = btn.dataset.tab;
            renderTabs();
            renderTable();
        })
    );
}

// ── Render table ───────────────────────────────────────────────────────────
function renderTable() {
    const tbody = document.getElementById('projectsTbody');
    let rows = filterBySearch(filterByTab(allProjects, activeTab), searchQuery);

    if (!rows.length) {
        tbody.innerHTML = `<tr class="state-row"><td colspan="16">No projects found.</td></tr>`;
        return;
    }

    tbody.innerHTML = rows.map((p, i) => {
        const dlClass  = isOverdue(p.deadline) || isToday(p.deadline) ? 'deadline-today' : 'deadline-normal';
        const jdlClass = isOverdue(p.job_deadline) ? 'deadline-today' : 'deadline-normal';
        const srcFlag  = LANG_FLAGS[p.source_language] || '🌐';
        const tgtFlag  = LANG_FLAGS[p.target_language] || '🌐';
        const price    = p.price != null
            ? `${Number(p.price).toFixed(2)} ${p.currency || 'EUR'}`
            : '0 EUR';
        const margin   = p.scoop_margin != null
            ? `${Number(p.scoop_margin).toFixed(2)} %`
            : '—';

        return `<tr>
            <td><input type="checkbox" class="row-check" data-id="${p.id}"></td>
            <td>${i + 1}</td>
            <td><span class="proj-num">${p.project_number || '—'}</span></td>
            <td>
                <div class="customer-main">${p.clients?.name || '—'}</div>
                ${p.sub_client ? `<div class="customer-sub">${p.sub_client}</div>` : ''}
            </td>
            <td>
                <div class="lang-pair">
                    <div class="lang-row"><span class="lang-flag">${srcFlag}</span>${p.source_language || '—'}</div>
                    <div class="lang-row"><span class="lang-flag">${tgtFlag}</span>${p.target_language || '—'}</div>
                </div>
            </td>
            <td><span class="${dlClass}">${fmtDate(p.deadline)}</span></td>
            <td>${p.project_manager || '—'}</td>
            <td>${p.qa_specialist   || '—'}</td>
            <td>${p.linguist        || '—'}</td>
            <td>
                <button class="comment-btn" title="Comments">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
                    </svg>
                </button>
            </td>
            <td><span class="status-badge">${p.status || '—'}</span></td>
            <td>${p.project_type   || '—'}</td>
            <td>${p.project_volume || '—'}</td>
            <td><span class="${jdlClass}">${fmtDate(p.job_deadline)}</span></td>
            <td class="price-cell">${price}</td>
            <td class="margin-cell">${margin}</td>
        </tr>`;
    }).join('');
}

// ── Export to CSV ──────────────────────────────────────────────────────────
function exportCSV() {
    let rows = filterBySearch(filterByTab(allProjects, activeTab), searchQuery);
    const headers = ['Project Number','Customer','Sub-client','Source Language','Target Language',
        'Deadline','Project Manager','QA Specialist','Linguist','Status','Project Type',
        'Project Volume','Job Deadline','Price','Currency','Scoop Margin'];
    const lines = [headers.join(',')];
    rows.forEach(p => {
        lines.push([
            p.project_number, p.clients?.name, p.sub_client,
            p.source_language, p.target_language,
            p.deadline, p.project_manager, p.qa_specialist, p.linguist,
            p.status, p.project_type, p.project_volume, p.job_deadline,
            p.price, p.currency, p.scoop_margin
        ].map(v => `"${(v ?? '').toString().replace(/"/g,'""')}"`).join(','));
    });
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `projects-${activeTab}-${new Date().toISOString().slice(0,10)}.csv`;
    a.click();
}

// ── Sidebar submenu toggle ─────────────────────────────────────────────────
function toggleSub(id, item) {
    document.getElementById(id).classList.toggle('open');
    item.classList.toggle('open');
}

// ── Select all ────────────────────────────────────────────────────────────
document.getElementById('selectAll').addEventListener('change', e => {
    document.querySelectorAll('.row-check').forEach(cb => cb.checked = e.target.checked);
});

// ── Search ────────────────────────────────────────────────────────────────
document.getElementById('searchBox').addEventListener('input', e => {
    searchQuery = e.target.value;
    renderTable();
});

// ── Create Project placeholder (Phase 2) ──────────────────────────────────
document.getElementById('createProjectBtn').addEventListener('click', () => {
    alert('Create Project — coming in Phase 2');
});
document.getElementById('changeStatusBtn').addEventListener('click', () => {
    alert('Bulk status change — coming in Phase 2');
});

// ── Init ──────────────────────────────────────────────────────────────────
(async () => {
    const user = await requireAuth();
    if (!user) return;

    const { data, error } = await _sb
        .from('projects')
        .select('*, clients(name)')
        .order('deadline', { ascending: true });

    if (error) {
        document.getElementById('projectsTbody').innerHTML =
            `<tr class="state-row"><td colspan="16">Error: ${error.message}</td></tr>`;
        return;
    }

    allProjects = data || [];
    renderTabs();
    renderTable();
})();
