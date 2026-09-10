'use strict';

function supabaseConfig() {
  const base = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !serviceKey) throw new Error('TMS database access is not configured. Contact the Administrator.');
  let parsed;
  try { parsed = new URL(base); } catch { throw new Error('TMS database configuration is invalid.'); }
  if (parsed.protocol !== 'https:' || !['', '/'].includes(parsed.pathname) || parsed.search || parsed.hash) {
    throw new Error('TMS database configuration is invalid.');
  }
  return {base, serviceKey};
}

async function request(path, {method = 'GET', body, bearer, timeout = 20000} = {}) {
  const {base, serviceKey} = supabaseConfig();
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      apikey: serviceKey,
      Authorization: bearer || `Bearer ${serviceKey}`,
      ...(body === undefined ? {} : {'Content-Type': 'application/json'}),
    },
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
    signal: AbortSignal.timeout(timeout),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!response.ok) {
    const error = new Error(data?.message || data?.error_description || `Database request failed (HTTP ${response.status}).`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function verifyUser(bearer) {
  if (!/^Bearer \S+$/.test(bearer || '')) throw Object.assign(new Error('Sign in first.'), {status: 401});
  const user = await request('/auth/v1/user', {bearer});
  if (!user?.id) throw Object.assign(new Error('Session expired. Sign in again.'), {status: 401});
  return user;
}

async function serviceRpc(name, payload = {}, timeout = 20000) {
  return request(`/rest/v1/rpc/${encodeURIComponent(name)}`, {
    method: 'POST',
    body: payload,
    timeout,
  });
}

function normalizedHeaders(event) {
  return Object.fromEntries(Object.entries(event?.headers || {}).map(([key, value]) => [key.toLowerCase(), value]));
}

function requireSameOrigin(event) {
  const headers = normalizedHeaders(event);
  const configured = process.env.TMS_SITE_URL || 'https://tms.retodo-ops.com';
  let origin;
  try { origin = new URL(configured).origin; } catch { throw Object.assign(new Error('TMS site URL is invalid.'), {status: 503}); }
  if (headers.origin && headers.origin !== origin) throw Object.assign(new Error('Origin not allowed.'), {status: 403});
  return {headers, origin};
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'",
    },
    body: JSON.stringify(body),
  };
}

function publicError(error, fallback = 'The file request could not be completed.') {
  if (error?.name === 'TimeoutError') return 'The request timed out. Try again.';
  const message = String(error?.message || '').trim();
  if (/credential|secret|service.?role|access.?key|signature|authorization/i.test(message)) return fallback;
  return message.slice(0, 400) || fallback;
}

module.exports = {
  supabaseConfig,
  request,
  verifyUser,
  serviceRpc,
  normalizedHeaders,
  requireSameOrigin,
  jsonResponse,
  publicError,
};
