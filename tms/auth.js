const _isPasswordCallbackPage = /\/reset-password\.html$/.test(window.location.pathname);

const _sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
        persistSession: true,
        autoRefreshToken: true,
        // The reset page validates and installs the callback session explicitly so
        // an existing company session can never be used to change the wrong account.
        detectSessionInUrl: !_isPasswordCallbackPage,
    },
});

const TMS_COMPANY_ROLES = new Set(['admin', 'pm', 'qa', 'client_relations']);
const TMS_RESOURCE_PAGES = new Set([
    'resource-dashboard.html',
    'resource-job.html',
    'resource-po.html',
]);
let _tmsRolePromise = null;
let _qaObserver = null;
let _qaUiScheduled = false;

function currentTmsPage() {
    return location.pathname.split('/').pop() || 'index.html';
}

function homeForRole(role) {
    return role === 'resource' ? 'resource-dashboard.html' : 'dashboard.html';
}

async function checkSession() {
    const { data: { session } } = await _sb.auth.getSession();
    return session?.user ?? null;
}

async function currentAppRole(refresh = false) {
    if (refresh) _tmsRolePromise = null;
    if (!_tmsRolePromise) {
        _tmsRolePromise = _sb.rpc('current_app_role').then(({data, error}) => {
            if (error) throw error;
            return data || null;
        }).catch(error => {
            _tmsRolePromise = null;
            throw error;
        });
    }
    return _tmsRolePromise;
}

async function accessIsEnabled() {
    const {data, error} = await _sb.rpc('current_user_access_enabled');
    if (error) throw error;
    return data === true;
}

function redirectToLogin(reason = 'unauthorized') {
    const suffix = reason ? `?access=${encodeURIComponent(reason)}` : '';
    location.replace(`index.html${suffix}`);
}

function routeMatchesRole(role) {
    const page = currentTmsPage();
    if (role === 'resource') return TMS_RESOURCE_PAGES.has(page);
    if (TMS_COMPANY_ROLES.has(role)) return !TMS_RESOURCE_PAGES.has(page);
    return false;
}

function addQaReadOnlyBanner() {
    if (document.getElementById('qaReadOnlyBanner')) return;
    const main = document.querySelector('.main, main');
    if (!main) return;
    const banner = document.createElement('div');
    banner.id = 'qaReadOnlyBanner';
    banner.className = 'role-readonly-banner';
    banner.setAttribute('role', 'status');
    banner.textContent = 'QA read-only access — operational changes are disabled.';
    const header = main.querySelector('.module-header, .record-header, .tabs-bar');
    if (header) header.insertAdjacentElement('afterend', banner);
    else main.prepend(banner);
}

function isQaReadAction(control) {
    const onclick = control.getAttribute?.('onclick') || '';
    const text = String(control.textContent || '').trim();
    if (/\b(print|download|exportCSV|openPOVersion|openBlindCv|close\w*|toggleSub)\b/i.test(onclick)) return true;
    if (/^(View|Open|Print|Download|Export|Close|Back|Clear filters?)\b/i.test(text)) return true;
    return control.classList?.contains('record-tab') || control.classList?.contains('sort-header');
}

function isQaWriteAction(control) {
    if (isQaReadAction(control)) return false;
    const signature = [
        control.id,
        control.getAttribute?.('name'),
        control.getAttribute?.('onclick'),
        control.textContent,
        control.getAttribute?.('aria-label'),
        control.getAttribute?.('title'),
    ].filter(Boolean).join(' ');
    return /\b(save|send|create|add|edit|remove|delete|assign|reassign|issue|revise|deactivate|activate|withdraw|update selected|change status|cancel po|cancel job|record result|mark as)\b/i.test(signature)
        || /open\w*(Modal|Setting)\s*\(/i.test(signature)
        || /toggle\w*Setting\s*\(/i.test(signature)
        || /recordTestResult\s*\(/i.test(signature);
}

function disableQaControl(control) {
    if (!control || (control.dataset.qaReadOnly === 'true' && control.disabled)) return;
    control.dataset.qaReadOnly = 'true';
    control.disabled = true;
    control.setAttribute('aria-disabled', 'true');
    if (!control.title) control.title = 'QA read-only access';
}

function applyQaReadOnlyUi() {
    if (document.body?.dataset.appRole !== 'qa') return;
    document.body.classList.add('role-qa-readonly');
    addQaReadOnlyBanner();

    const page = currentTmsPage();
    const recordPages = new Set([
        'project.html', 'job.html', 'client.html', 'resource.html', 'quote.html'
    ]);
    if (recordPages.has(page)) {
        document.querySelectorAll('main input:not([type="search"]), .main input:not([type="search"]), main select, .main select, main textarea, .main textarea')
            .forEach(disableQaControl);
    }

    document.querySelectorAll('button, [role="button"]')
        .forEach(control => {
            if (isQaWriteAction(control)) disableQaControl(control);
        });
}

function scheduleRoleUi(role) {
    if (document.body) document.body.dataset.appRole = role || '';
    if (role !== 'qa') return;
    if (!_qaObserver && document.body) {
        _qaObserver = new MutationObserver(() => {
            if (_qaUiScheduled) return;
            _qaUiScheduled = true;
            queueMicrotask(() => {
                _qaUiScheduled = false;
                applyQaReadOnlyUi();
            });
        });
        _qaObserver.observe(document.body, {
            subtree: true,
            childList: true,
            attributes: true,
            attributeFilter: ['disabled'],
        });
    }
    applyQaReadOnlyUi();
}

async function requireAuth() {
    const user = await checkSession();
    if (!user) {
        redirectToLogin('');
        return null;
    }

    try {
        if (!await accessIsEnabled()) {
            await _sb.auth.signOut();
            redirectToLogin('inactive');
            return null;
        }

        const role = await currentAppRole();
        if (!role || (!TMS_COMPANY_ROLES.has(role) && role !== 'resource')) {
            await _sb.auth.signOut();
            redirectToLogin('unauthorized');
            return null;
        }
        if (!routeMatchesRole(role)) {
            location.replace(homeForRole(role));
            return null;
        }

        scheduleRoleUi(role);
        return user;
    } catch (error) {
        console.error('TMS access check failed', error);
        await _sb.auth.signOut();
        redirectToLogin('error');
        return null;
    }
}

async function redirectAuthenticatedUser() {
    const user = await checkSession();
    if (!user) return false;
    try {
        if (!await accessIsEnabled()) {
            await _sb.auth.signOut();
            redirectToLogin('inactive');
            return true;
        }
        const role = await currentAppRole(true);
        if (!role || (!TMS_COMPANY_ROLES.has(role) && role !== 'resource')) {
            await _sb.auth.signOut();
            redirectToLogin('unauthorized');
            return true;
        }
        location.replace(homeForRole(role));
        return true;
    } catch (error) {
        console.error('TMS sign-in routing failed', error);
        await _sb.auth.signOut();
        redirectToLogin('error');
        return true;
    }
}

async function signIn(email, password) {
    _tmsRolePromise = null;
    return _sb.auth.signInWithPassword({ email, password });
}

async function requestPasswordReset(email) {
    const redirectTo = new URL('reset-password.html', window.location.href).href;
    return _sb.auth.resetPasswordForEmail(email, { redirectTo });
}

async function updatePassword(password) {
    return _sb.auth.updateUser({ password });
}

async function signOut() {
    _tmsRolePromise = null;
    await _sb.auth.signOut();
    window.location.href = 'index.html';
}

