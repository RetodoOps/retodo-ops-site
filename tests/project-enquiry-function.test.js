const test = require('node:test');
const assert = require('node:assert/strict');
const { handler } = require('../netlify/functions/submit-project-enquiry.js');

const originalFetch = global.fetch;
const envKeys = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN', 'GMAIL_FROM_EMAIL', 'GMAIL_FROM_NAME', 'PROJECT_ENQUIRY_RECIPIENT'];
const originalEnvironment = Object.fromEntries(envKeys.map(key => [key, process.env[key]]));

function restoreRuntime() {
  global.fetch = originalFetch;
  for (const key of envKeys) {
    if (originalEnvironment[key] === undefined) delete process.env[key];
    else process.env[key] = originalEnvironment[key];
  }
}

function configureGmailMock(calls) {
  process.env.GOOGLE_CLIENT_ID = 'test-client-id';
  process.env.GOOGLE_CLIENT_SECRET = 'test-client-secret';
  process.env.GOOGLE_REFRESH_TOKEN = 'test-refresh-token';
  process.env.GMAIL_FROM_EMAIL = 'ops@retodo-ops.com';
  process.env.GMAIL_FROM_NAME = 'Retodo Ops';
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url === 'https://oauth2.googleapis.com/token') {
      return { ok: true, status: 200, json: async () => ({ access_token: 'test-access-token' }) };
    }
    if (url === 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send') {
      return { ok: true, status: 200, json: async () => ({ id: 'gmail-message-id' }) };
    }
    throw new Error(`Unexpected URL: ${url}`);
  };
}

function event(body, extra = {}) {
  return {
    httpMethod: 'POST',
    headers: {
      origin: 'https://retodo-ops.com',
      'content-type': 'application/json',
      ...extra.headers
    },
    body: JSON.stringify(body),
    ...extra
  };
}

function decodeBase64Url(value) {
  const padding = '='.repeat((4 - (value.length % 4)) % 4);
  return Buffer.from(value.replaceAll('-', '+').replaceAll('_', '/') + padding, 'base64').toString('utf8');
}

test('sends a valid website enquiry only to the configured Retodo inbox', async t => {
  t.after(restoreRuntime);
  const calls = [];
  configureGmailMock(calls);

  const response = await handler(event({
    first_name: 'Erik',
    last_name: 'Lindqvist',
    email: 'erik@example.com',
    company: 'Example LSP',
    source_language: 'English',
    target_language: 'Swedish',
    word_count: '500–2,000 words',
    deadline: '2026-09-15',
    message: 'We need Nordic overflow support for a recurring software account.',
    website: ''
  }));

  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), { ok: true });
  assert.equal(calls.length, 2);
  const gmailPayload = JSON.parse(calls[1].options.body);
  const email = decodeBase64Url(gmailPayload.raw);
  assert.match(email, /To: ops@retodo-ops\.com/);
  assert.match(email, /Reply-To: erik@example\.com/);
  const plainPart = email.match(/Content-Type: text\/plain; charset="UTF-8"\r\nContent-Transfer-Encoding: base64\r\n\r\n([^\r\n]+)/);
  assert.ok(plainPart);
  assert.match(Buffer.from(plainPart[1], 'base64').toString('utf8'), /New Retodo Ops project enquiry/);
});

test('returns a generic success without email delivery when the honeypot is filled', async t => {
  t.after(restoreRuntime);
  let delivered = false;
  global.fetch = async () => { delivered = true; throw new Error('A bot submission must not be delivered'); };

  const response = await handler(event({ website: 'https://spam.example' }));

  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), { ok: true });
  assert.equal(delivered, false);
});

test('supports a standard URL-encoded form fallback with a success redirect', async t => {
  t.after(restoreRuntime);
  const calls = [];
  configureGmailMock(calls);
  const form = new URLSearchParams({
    first_name: 'Erik',
    last_name: 'Lindqvist',
    email: 'erik@example.com',
    company: 'Example LSP',
    source_language: 'English',
    target_language: 'Swedish',
    word_count: 'Under 500 words',
    deadline: '',
    message: 'Please contact me about a Nordic translation project.',
    website: ''
  });

  const response = await handler({
    httpMethod: 'POST',
    headers: {
      origin: 'https://retodo-ops.com',
      'content-type': 'application/x-www-form-urlencoded'
    },
    body: form.toString()
  });

  assert.equal(response.statusCode, 303);
  assert.equal(response.headers.Location, 'https://retodo-ops.com/contact.html?submitted=1');
  assert.equal(calls.length, 2);
});

test('rejects requests that do not originate from the Retodo website', async t => {
  t.after(restoreRuntime);
  const response = await handler(event({}, { headers: { origin: 'https://example.com' } }));

  assert.equal(response.statusCode, 403);
  assert.deepEqual(JSON.parse(response.body), { ok: false, error: 'Origin not allowed' });
});

test('allows the browser CORS preflight only for the Retodo website', async t => {
  t.after(restoreRuntime);
  const response = await handler({
    httpMethod: 'OPTIONS',
    headers: { origin: 'https://retodo-ops.com' },
    body: ''
  });

  assert.equal(response.statusCode, 204);
  assert.equal(response.headers['Access-Control-Allow-Origin'], 'https://retodo-ops.com');
  assert.equal(response.headers['Access-Control-Allow-Methods'], 'POST, OPTIONS');
});
