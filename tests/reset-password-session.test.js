'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const vm = require('node:vm');

const html = fs.readFileSync('tms/reset-password.html', 'utf8');
const scriptStart = html.lastIndexOf('<script>') + '<script>'.length;
const resetScript = html.slice(scriptStart, html.indexOf('</script>', scriptStart));

function createHarness({
    hash = '',
    search = '',
    updateError = null,
    role = 'resource',
    access = true,
} = {}) {
    const listeners = {};
    const storage = new Map();
    const calls = [];
    let accessEnabled = access;
    let activeRole = role;
    const elements = {
        newPasswordForm: {
            addEventListener(type, callback) { listeners[type] = callback; },
        },
        passwordMessage: {textContent: '', className: ''},
        savePasswordBtn: {disabled: false, textContent: ''},
        newPassword: {value: 'ValidPassword1!', disabled: false},
        confirmPassword: {value: 'ValidPassword1!', disabled: false},
    };
    const session = {access_token: 'access', user: {id: 'resource-user'}};

    const context = {
        URLSearchParams,
        console,
        TMS_COMPANY_ROLES: new Set(['admin', 'pm', 'qa', 'client_relations']),
        document: {
            title: 'Reset',
            getElementById(id) { return elements[id]; },
        },
        history: {
            replaceState(_state, _title, url) { calls.push(['replaceState', url]); },
        },
        location: {
            hash,
            search,
            pathname: '/reset-password.html',
            replace(url) { calls.push(['replace', url]); },
        },
        sessionStorage: {
            getItem(key) { return storage.get(key) ?? null; },
            setItem(key, value) { storage.set(key, value); },
            removeItem(key) { storage.delete(key); },
        },
        updatePassword: async password => {
            calls.push(['updatePassword', password]);
            return {error: updateError};
        },
        accessIsEnabled: async () => {
            calls.push(['accessIsEnabled']);
            return accessEnabled;
        },
        currentAppRole: async refresh => {
            calls.push(['currentAppRole', refresh]);
            return activeRole;
        },
        _sb: {
            auth: {
                async setSession(tokens) {
                    calls.push(['setSession', tokens]);
                    return {data: {session}, error: null};
                },
                async exchangeCodeForSession(code) {
                    calls.push(['exchangeCodeForSession', code]);
                    return {data: {session}, error: null};
                },
                async getSession() { return {data: {session}, error: null}; },
                async signOut() { calls.push(['signOut']); },
            },
        },
    };

    vm.runInNewContext(resetScript, context);
    return {
        calls,
        context,
        elements,
        listeners,
        storage,
        setAccess(value) { accessEnabled = value; },
        setRole(value) { activeRole = value; },
    };
}

const settle = () => new Promise(resolve => setImmediate(resolve));
const submitted = harness => harness.listeners.submit({preventDefault() {}});

test('installs the callback session before saving and routes a Resource to its portal', async () => {
    const harness = createHarness({
        hash: '#access_token=access&refresh_token=refresh&type=invite',
    });
    await settle();

    assert.equal(harness.elements.savePasswordBtn.disabled, false);
    assert.equal(harness.calls[0][0], 'setSession');
    assert.equal(harness.calls[0][1].access_token, 'access');
    assert.equal(harness.calls[0][1].refresh_token, 'refresh');

    await submitted(harness);
    const sequence = harness.calls.map(call => call[0]);
    assert.ok(sequence.indexOf('setSession') < sequence.indexOf('updatePassword'));
    assert.ok(sequence.indexOf('updatePassword') < sequence.indexOf('accessIsEnabled'));
    assert.ok(sequence.indexOf('accessIsEnabled') < sequence.indexOf('currentAppRole'));
    assert.deepEqual(harness.calls.find(call => call[0] === 'replace'), ['replace', 'resource-dashboard.html']);
    assert.ok(!sequence.includes('signOut'));
    assert.equal(harness.storage.size, 0);
});

test('exchanges a PKCE callback and routes a company role to the company Dashboard', async () => {
    const harness = createHarness({
        search: '?code=pkce-code',
        role: 'admin',
    });
    await settle();
    await submitted(harness);

    assert.deepEqual(
        harness.calls.find(call => call[0] === 'exchangeCodeForSession'),
        ['exchangeCodeForSession', 'pkce-code'],
    );
    assert.deepEqual(harness.calls.find(call => call[0] === 'replace'), ['replace', 'dashboard.html']);
    assert.ok(!harness.calls.some(call => call[0] === 'signOut'));
});

test('blocks a direct visit without an authenticated callback', async () => {
    const harness = createHarness();
    await settle();

    assert.equal(harness.elements.savePasswordBtn.disabled, true);
    assert.equal(harness.elements.savePasswordBtn.textContent, 'Link unavailable');
    assert.match(harness.elements.passwordMessage.textContent, /invalid or has expired/i);
});

test('shows a password-policy error instead of mislabeling it as an expired link', async () => {
    const harness = createHarness({
        hash: '#access_token=access&refresh_token=refresh&type=invite',
        updateError: new Error('Password must contain a symbol'),
    });
    await settle();
    await submitted(harness);

    assert.equal(
        harness.elements.passwordMessage.textContent,
        'Password could not be saved: Password must contain a symbol',
    );
    assert.ok(!harness.calls.some(call => call[0] === 'accessIsEnabled'));
});

test('keeps the authenticated retry state when activation is not ready and never saves twice', async () => {
    const harness = createHarness({
        hash: '#access_token=access&refresh_token=refresh&type=invite',
        access: false,
    });
    await settle();
    await submitted(harness);

    assert.equal(harness.calls.filter(call => call[0] === 'updatePassword').length, 1);
    assert.equal(harness.storage.get('tms-password-session-user'), 'resource-user');
    assert.equal(harness.elements.savePasswordBtn.textContent, 'Retry opening workspace');
    assert.equal(harness.elements.newPassword.disabled, true);
    assert.match(harness.elements.passwordMessage.textContent, /Password saved, but the workspace could not be opened/);
    assert.ok(!harness.calls.some(call => call[0] === 'replace'));

    harness.setAccess(true);
    await submitted(harness);

    assert.equal(harness.calls.filter(call => call[0] === 'updatePassword').length, 1);
    assert.deepEqual(harness.calls.find(call => call[0] === 'replace'), ['replace', 'resource-dashboard.html']);
    assert.equal(harness.storage.size, 0);
});
