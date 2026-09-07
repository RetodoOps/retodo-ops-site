'use strict';
const { randomUUID } = require('node:crypto');

// The service key belongs in Netlify Functions environment variables only.
// Browser payloads never supply actor IDs, Auth IDs, roles or redirect targets.
exports.handler = async event => {
    const reply = (statusCode, body) => ({statusCode, headers: {
        'Content-Type': 'application/json', 'Cache-Control': 'no-store'
    }, body: JSON.stringify(body)});
    if (event.httpMethod !== 'POST') return reply(405, {error:'POST required'});
    const base = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const site = process.env.TMS_SITE_URL || 'https://tms.retodo-ops.com';
    if (!base || !key) return reply(503, {error:'Resource onboarding is not configured. Contact the Administrator.'});
    let siteOrigin;
    try {
        siteOrigin = new URL(site).origin;
        if (new URL(site).protocol !== 'https:' || new URL(base).protocol !== 'https:') throw new Error('HTTPS required');
    } catch { return reply(503,{error:'Onboarding URL configuration is invalid.'}); }
    const headers = Object.fromEntries(Object.entries(event.headers || {}).map(([k,v])=>[k.toLowerCase(),v]));
    if (headers.origin && headers.origin !== siteOrigin) return reply(403,{error:'Origin not allowed'});
    if (!/^Bearer \S+$/.test(headers.authorization || '')) return reply(401,{error:'Sign in first'});
    let body;
    try { body = JSON.parse(event.body || '{}'); } catch { return reply(400,{error:'Invalid request'}); }
    if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(400,{error:'Invalid request'});
    if (!['invite','create_internal','register'].includes(body.action)) return reply(400,{error:'Unknown action'});
    const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
    if (body.action === 'invite' && !uuid(body.resource_id)) return reply(400,{error:'Resource ID required'});
    if (body.action === 'create_internal' && !uuid(body.request_id)) return reply(400,{error:'Request ID required'});

    async function api(path, payload, bearer = `Bearer ${key}`) {
        const response = await fetch(`${base.replace(/\/$/,'')}${path}`, {
            method: payload === undefined ? 'GET' : 'POST',
            headers: {apikey:key, Authorization:bearer, 'Content-Type':'application/json'},
            ...(payload === undefined ? {} : {body:JSON.stringify(payload)}),
            signal: AbortSignal.timeout(15000)
        });
        const data = await response.json().catch(()=>({}));
        if (!response.ok) {
            const error = new Error(path.startsWith('/rest/') ? (data.message || 'Onboarding check failed')
                : 'Authentication or email service rejected the request. Check Supabase Auth logs and SMTP configuration.');
            error.status = response.status;
            throw error;
        }
        return data;
    }
    let resourceId = body.resource_id || null;
    let attemptId;
    let rpc;
    let prepared = false;
    try {
        const user = await api('/auth/v1/user', undefined, headers.authorization);
        if (!user.id) return reply(401,{error:'Session expired. Sign in again.'});
        rpc = (action, payload = {}, requestId = null) => api('/rest/v1/rpc/resource_onboarding_040',{
            p_action:action,p_actor_id:user.id,p_resource_id:resourceId,p_payload:payload,p_request_id:requestId
        });
        if (body.action === 'register') {
            const result = await rpc('register',{name:String(body.name || '').slice(0,200)});
            return reply(200,result);
        }
        if (body.action === 'create_internal') {
            const result = await rpc('create_internal',body.payload || {},body.request_id);
            resourceId = result.resource_id;
        }
        attemptId = randomUUID();
        const invitation = await rpc('prepare_invite',{},attemptId);
        prepared = true;
        const redirect = encodeURIComponent(new URL('/reset-password.html',site).href);
        if (!invitation.confirmed) {
            // Supabase invites new or still-unconfirmed accounts; it does not set a password.
            await api(`/auth/v1/invite?redirect_to=${redirect}`,{email:invitation.email,data:{full_name:invitation.name}});
            await rpc('link_invite',{},attemptId);
        } else {
            // Existing verified users retain their password and role. Send a recovery link.
            await rpc('link_invite',{},attemptId);
            await api(`/auth/v1/recover?redirect_to=${redirect}`,{email:invitation.email});
        }
        await rpc('invite_sent',{},attemptId);
        return reply(200,{resource_id:resourceId,invitation_requested:true});
    } catch (error) {
        if (prepared) {
            try { await rpc('invite_failed',{},attemptId); } catch { /* Lease expires; no destructive rollback. */ }
        }
        // Never log tokens, email links, passwords or service responses.
        return reply(error.status === 401 ? 401 : 400, {
            error:error.name === 'TimeoutError' ? 'Request timed out. Retry from the resource profile in two minutes.' : error.message,
            ...(resourceId ? {resource_id:resourceId} : {})
        });
    }
};
