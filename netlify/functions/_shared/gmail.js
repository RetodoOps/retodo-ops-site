'use strict';

const {randomUUID} = require('node:crypto');

const htmlEscape = value => String(value ?? '')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
const cleanHeader = value => String(value ?? '').replace(/[\r\n]+/g, ' ').trim();
const encodeHeader = value => `=?UTF-8?B?${Buffer.from(String(value), 'utf8').toString('base64')}?=`;
const base64url = value => Buffer.from(value, 'utf8').toString('base64')
  .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');

async function gmailAccessToken() {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const refreshToken = process.env.GOOGLE_REFRESH_TOKEN;
  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error('Compliance notification delivery is not configured.');
  }
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
    signal: AbortSignal.timeout(15000),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token) {
    throw new Error(`Compliance notification authorization failed (HTTP ${response.status}).`);
  }
  return data.access_token;
}

function complianceNotificationMessage(ticket, portalUrl) {
  const fromEmail = cleanHeader(process.env.GMAIL_FROM_EMAIL || 'ops@retodo-ops.com');
  const fromName = cleanHeader(process.env.GMAIL_FROM_NAME || 'RetodoOps TMS');
  const recipientEmail = cleanHeader(ticket.email).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipientEmail)
      || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fromEmail)) {
    throw new Error('The Compliance notification email address is invalid.');
  }
  const recipientName = String(ticket.name || 'Resource').trim().slice(0, 200) || 'Resource';
  const changesRequired = ticket.notification_kind === 'changes_required';
  const subject = changesRequired
    ? 'Changes requested for your RetodoOps Compliance information'
    : 'Please complete your RetodoOps Compliance information';
  const heading = changesRequired ? 'Compliance changes requested' : 'Compliance information requested';
  const explanation = changesRequired
    ? `Retodo Ops reviewed your Compliance submission and requested changes.${ticket.change_reason ? `\n\nRequested changes:\n${ticket.change_reason}` : ''}`
    : 'Retodo Ops has opened a Compliance task for your Resource profile. Please enter your education and professional-experience details and upload your diploma/certificate and CV evidence.';
  const reasonHtml = changesRequired && ticket.change_reason
    ? `<div style="padding:14px 16px;background:#f5f3ff;border:1px solid #ddd6fe;border-radius:8px"><strong>Requested changes</strong><br>${htmlEscape(ticket.change_reason)}</div>`
    : '';
  const plain = `Hello ${recipientName},\n\n${explanation}\n\nOpen My Compliance:\n${portalUrl}\n\nYou may continue working on assigned Jobs while this task is in progress.\n\nBest regards,\nRetodo Ops\n${fromEmail}`;
  const html = `<!doctype html><html><body style="margin:0;background:#f5f3ff;font-family:Arial,sans-serif;color:#172033">
    <div style="max-width:640px;margin:24px auto;background:#fff;border:1px solid #ddd6fe;border-radius:12px;overflow:hidden">
      <div style="padding:22px 26px;background:#4c1d95;color:#fff"><div style="font-size:13px;opacity:.85">RETODO OPS TMS</div><h1 style="margin:5px 0 0;font-size:22px">${heading}</h1></div>
      <div style="padding:24px 26px"><p>Hello ${htmlEscape(recipientName)},</p><p>${htmlEscape(explanation.split('\n\n')[0])}</p>${reasonHtml}<p style="margin:26px 0"><a href="${htmlEscape(portalUrl)}" style="display:inline-block;padding:12px 18px;background:#6d28d9;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Open My Compliance</a></p><p style="font-size:13px;color:#475467">You may continue working on assigned Jobs while this task is in progress.</p><p style="margin-top:24px">Best regards,<br><strong>Retodo Ops</strong><br><a href="mailto:${htmlEscape(fromEmail)}">${htmlEscape(fromEmail)}</a></p></div>
    </div></body></html>`;
  const boundary = `retodo_${randomUUID()}`;
  return base64url([
    `From: ${encodeHeader(fromName)} <${fromEmail}>`,
    `Reply-To: ${fromEmail}`,
    `To: ${recipientEmail}`,
    `Subject: ${encodeHeader(subject)}`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    '', `--${boundary}`,
    'Content-Type: text/plain; charset="UTF-8"',
    'Content-Transfer-Encoding: base64', '',
    Buffer.from(plain, 'utf8').toString('base64'),
    `--${boundary}`,
    'Content-Type: text/html; charset="UTF-8"',
    'Content-Transfer-Encoding: base64', '',
    Buffer.from(html, 'utf8').toString('base64'),
    `--${boundary}--`, '',
  ].join('\r\n'));
}

async function sendComplianceNotification(ticket, portalUrl) {
  const accessToken = await gmailAccessToken();
  const response = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
    method: 'POST',
    headers: {Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json'},
    body: JSON.stringify({raw: complianceNotificationMessage(ticket, portalUrl)}),
    signal: AbortSignal.timeout(15000),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.id) {
    throw new Error(`Compliance notification delivery failed (HTTP ${response.status}).`);
  }
  return {message_id: data.id, thread_id: data.threadId || null};
}

module.exports = {
  sendComplianceNotification,
  complianceNotificationMessage,
};
