'use strict';
const { randomUUID } = require('node:crypto');

const htmlEscape = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
const cleanHeader = value => String(value ?? '').replace(/[\r\n]+/g, ' ').trim();
const encodeHeader = value => `=?UTF-8?B?${Buffer.from(String(value), 'utf8').toString('base64')}?=`;
const base64url = value => Buffer.from(value, 'utf8').toString('base64')
    .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');

const commonEmailDomainTypos = new Map([
    ['gmai.com', 'gmail.com'],
    ['gmial.com', 'gmail.com'],
    ['gamil.com', 'gmail.com'],
    ['gmail.con', 'gmail.com'],
    ['hotnail.com', 'hotmail.com'],
    ['outlok.com', 'outlook.com'],
    ['yaho.com', 'yahoo.com']
]);
const normalizeRecipientEmail = value => String(value ?? '').trim().toLowerCase();
function checkedRecipientEmail(value) {
    const email = normalizeRecipientEmail(value);
    if (!email || email.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        throw new Error('Enter a valid recipient email address.');
    }
    const domain = email.slice(email.lastIndexOf('@') + 1);
    const suggestion = commonEmailDomainTypos.get(domain);
    if (suggestion) {
        throw new Error(`The email domain “${domain}” looks mistyped. Did you mean “${suggestion}”?`);
    }
    return email;
}
function requireExactEmailConfirmation(expected, confirmed) {
    const confirmedEmail = checkedRecipientEmail(confirmed);
    if (confirmedEmail !== expected) {
        throw new Error('The confirmed recipient email does not exactly match the saved email address.');
    }
    return confirmedEmail;
}

async function gmailAccessToken() {
    const clientId = process.env.GOOGLE_CLIENT_ID;
    const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
    const refreshToken = process.env.GOOGLE_REFRESH_TOKEN;
    if (!clientId || !clientSecret || !refreshToken) {
        throw new Error('Invitation email delivery is not configured. Contact the Administrator.');
    }
    const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            refresh_token: refreshToken,
            grant_type: 'refresh_token'
        }),
        signal: AbortSignal.timeout(15000)
    });
    const data = await response.json().catch(()=>({}));
    if (!response.ok || !data.access_token) {
        throw new Error(`Invitation email authorization failed (HTTP ${response.status}). Retry in two minutes.`);
    }
    return data.access_token;
}

function invitationMessage(invitation, actionLink) {
    const fromEmail = cleanHeader(process.env.GMAIL_FROM_EMAIL || 'ops@retodo-ops.com');
    const fromName = cleanHeader(process.env.GMAIL_FROM_NAME || 'RetodoOps TMS');
    const recipientEmail = cleanHeader(invitation.email);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipientEmail)
        || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fromEmail)) {
        throw new Error('The invitation email address is invalid.');
    }
    const recipientName = String(invitation.name || 'Resource').trim().slice(0, 200) || 'Resource';
    const subject = 'Your RetodoOps TMS access invitation';
    const plain = `Hello ${recipientName},\n\nRetodo Ops has invited you to access the TMS. Use the secure link below to create or update your password. After saving it, you will be taken directly to your workspace.\n\nCreate password and open TMS:\n${actionLink}\n\nThis single-use link expires according to the TMS security policy. If you were not expecting this invitation, you can ignore this email.\n\nBest regards,\nRetodo Ops\n${fromEmail}`;
    const html = `<!doctype html><html><body style="margin:0;background:#f5f3ff;font-family:Arial,sans-serif;color:#172033">
      <div style="max-width:640px;margin:24px auto;background:#fff;border:1px solid #ddd6fe;border-radius:12px;overflow:hidden">
        <div style="padding:22px 26px;background:#4c1d95;color:#fff">
          <div style="font-size:13px;opacity:.85">RETODO OPS TMS</div>
          <h1 style="margin:5px 0 0;font-size:22px">Access invitation</h1>
        </div>
        <div style="padding:24px 26px">
          <p>Hello ${htmlEscape(recipientName)},</p>
          <p>Retodo Ops has invited you to access the TMS. Use the secure link below to create or update your password. After saving it, you will be taken directly to your workspace.</p>
          <p style="margin:26px 0"><a href="${htmlEscape(actionLink)}" style="display:inline-block;padding:12px 18px;background:#6d28d9;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Create password and open TMS</a></p>
          <p style="font-size:13px;color:#475467">This single-use link expires according to the TMS security policy. If you were not expecting this invitation, you can ignore this email.</p>
          <p style="margin-top:24px">Best regards,<br><strong>Retodo Ops</strong><br><a href="mailto:${htmlEscape(fromEmail)}">${htmlEscape(fromEmail)}</a></p>
        </div>
      </div></body></html>`;
    const boundary = `retodo_${randomUUID()}`;
    const mime = [
        `From: ${encodeHeader(fromName)} <${fromEmail}>`,
        `Reply-To: ${fromEmail}`,
        `To: ${recipientEmail}`,
        `Subject: ${encodeHeader(subject)}`,
        'MIME-Version: 1.0',
        `Content-Type: multipart/alternative; boundary="${boundary}"`,
        '',
        `--${boundary}`,
        'Content-Type: text/plain; charset="UTF-8"',
        'Content-Transfer-Encoding: base64',
        '',
        Buffer.from(plain, 'utf8').toString('base64'),
        `--${boundary}`,
        'Content-Type: text/html; charset="UTF-8"',
        'Content-Transfer-Encoding: base64',
        '',
        Buffer.from(html, 'utf8').toString('base64'),
        `--${boundary}--`,
        ''
    ].join('\r\n');
    return base64url(mime);
}

async function sendInvitationEmail(invitation, actionLink) {
    const accessToken = await gmailAccessToken();
    const response = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
        method: 'POST',
        headers: {Authorization:`Bearer ${accessToken}`, 'Content-Type':'application/json'},
        body: JSON.stringify({raw:invitationMessage(invitation, actionLink)}),
        signal: AbortSignal.timeout(15000)
    });
    const data = await response.json().catch(()=>({}));
    if (!response.ok || !data.id) {
        throw new Error(`Invitation email delivery failed (HTTP ${response.status}). Retry in two minutes.`);
    }
}

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
    if (!['invite','create_internal','register','correct_email'].includes(body.action)) return reply(400,{error:'Unknown action'});
    const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
    if (['invite','correct_email'].includes(body.action) && !uuid(body.resource_id)) return reply(400,{error:'Resource ID required'});
    if (body.action === 'create_internal' && !uuid(body.request_id)) return reply(400,{error:'Request ID required'});
    if (body.action === 'correct_email' && !uuid(body.request_id)) return reply(400,{error:'Request ID required'});

    let confirmedEmail = null;
    let correctedEmail = null;
    try {
        if (body.action === 'invite') confirmedEmail = checkedRecipientEmail(body.confirmed_email);
        if (body.action === 'create_internal') {
            const requestedEmail = checkedRecipientEmail(body.payload?.email);
            confirmedEmail = requireExactEmailConfirmation(requestedEmail, body.confirmed_email);
        }
        if (body.action === 'correct_email') {
            correctedEmail = checkedRecipientEmail(body.new_email);
            confirmedEmail = requireExactEmailConfirmation(correctedEmail, body.confirmed_email);
        }
    } catch (error) {
        return reply(400,{error:error.message});
    }

    async function api(path, payload, bearer = `Bearer ${key}`, method = payload === undefined ? 'GET' : 'POST') {
        const response = await fetch(`${base.replace(/\/$/,'')}${path}`, {
            method,
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
    let correctionPrepared = false;
    let corrected = false;
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
        if (body.action === 'correct_email') {
            const correctionRpc = (action, requestId) => api('/rest/v1/rpc/resource_email_correction_046',{
                p_action:action,
                p_actor_id:user.id,
                p_resource_id:resourceId,
                p_new_email:correctedEmail,
                p_request_id:requestId
            });
            const correction = await correctionRpc('prepare',body.request_id);
            correctionPrepared = true;
            const correctionRequestId = correction.request_id;
            if (!uuid(correctionRequestId)) throw new Error('Email correction could not be prepared. Retry from the Resource profile.');
            if (!correction.completed && correction.auth_update_required) {
                if (!uuid(correction.auth_user_id)) throw new Error('Linked login account could not be verified.');
                await api(`/auth/v1/admin/users/${correction.auth_user_id}`,
                    {email:correctedEmail},`Bearer ${key}`,'PUT');
            }
            await correctionRpc('complete',correctionRequestId);
            corrected = true;
        }
        attemptId = randomUUID();
        const invitation = await rpc('prepare_invite',{},attemptId);
        prepared = true;
        const invitationEmail = checkedRecipientEmail(invitation.email);
        requireExactEmailConfirmation(invitationEmail,confirmedEmail);
        const resetUrl = new URL('/reset-password.html', siteOrigin).href;
        // Generate the appropriate one-time Auth link without sending Supabase's generic
        // Invite/Recovery template. The recipient always receives a TMS access invitation.
        const generated = await api('/auth/v1/admin/generate_link', {
            type: invitation.confirmed ? 'recovery' : 'invite',
            email: invitationEmail,
            redirect_to: resetUrl,
            ...(!invitation.confirmed ? {data:{full_name:invitation.name}} : {})
        });
        let actionLink;
        try {
            const parsed = new URL(generated.action_link);
            if (parsed.protocol !== 'https:' || parsed.origin !== new URL(base).origin
                || parsed.searchParams.get('redirect_to') !== resetUrl) throw new Error('Unexpected link');
            actionLink = parsed.href;
        } catch {
            throw new Error('Authentication service returned an invalid invitation link. Retry in two minutes.');
        }
        await rpc('link_invite',{},attemptId);
        await sendInvitationEmail(invitation, actionLink);
        await rpc('invite_sent',{},attemptId);
        return reply(200,{resource_id:resourceId,invitation_requested:true,email_corrected:corrected});
    } catch (error) {
        if (prepared) {
            try { await rpc('invite_failed',{},attemptId); } catch { /* Lease expires; no destructive rollback. */ }
        }
        // Never log tokens, email links, passwords or service responses.
        return reply(error.status === 401 ? 401 : 400, {
            error:error.name === 'TimeoutError' ? 'Request timed out. Retry from the resource profile in two minutes.' : error.message,
            ...(resourceId ? {resource_id:resourceId} : {}),
            ...(corrected ? {email_corrected:true} : {}),
            ...(!corrected && correctionPrepared ? {email_correction_pending:true} : {})
        });
    }
};
