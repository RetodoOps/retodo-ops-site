const SUPABASE_URL = 'https://taughuvjgbgfwrabvpey.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRhdWdodXZqZ2JnZndyYWJ2cGV5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3OTMzMjIsImV4cCI6MjA5NTM2OTMyMn0.Uyb0K4xh3Me6izqs-RyxKPMhlMsAVOq-9Yqx-9s71mA';

const jsonResponse = (statusCode, body) => ({
  statusCode,
  headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
  body: JSON.stringify(body)
});

const htmlEscape = value => String(value ?? '')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
const cleanHeader = value => String(value ?? '').replace(/[\r\n]+/g, ' ').trim();

const money = (value, currency) => `${Number(value || 0).toFixed(2)} ${currency}`;
const unitPrice = value => Number(value || 0).toFixed(4).replace(/0+$/, '').replace(/\.$/, '') || '0';
const dateTime = value => value ? new Intl.DateTimeFormat('en-GB', {
  dateStyle: 'medium', timeStyle: 'short', timeZone: 'Europe/Sofia'
}).format(new Date(value)) : 'Not specified';
const encodeHeader = value => `=?UTF-8?B?${Buffer.from(String(value), 'utf8').toString('base64')}?=`;
const base64url = value => Buffer.from(value, 'utf8').toString('base64')
  .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');

async function rpc(name, payload, bearer) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: bearer,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });
  const text = await response.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!response.ok) throw new Error(data?.message || data?.error_description || String(data || `Supabase RPC ${name} failed`));
  return data;
}

async function gmailAccessToken() {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const refreshToken = process.env.GOOGLE_REFRESH_TOKEN;
  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error('Gmail credentials are not configured in Netlify');
  }
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token'
    })
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    const code = data.error || `HTTP ${response.status}`;
    const description = data.error_description || response.statusText || 'Token exchange failed';
    throw new Error(`${code}: ${description}`);
  }
  return data.access_token;
}

function buildMessage(po) {
  const fromEmail = cleanHeader(process.env.GMAIL_FROM_EMAIL || 'ops@retodo-ops.com');
  const fromName = cleanHeader(process.env.GMAIL_FROM_NAME || 'Retodo Ops');
  const recipientEmail = cleanHeader(po.recipient_email);
  const poLabel = po.po_display_name || po.display_name || [po.job_number, po.po_number].filter(Boolean).join(' · ') || 'Supplier PO';
  const subject = cleanHeader(`${poLabel} · V${po.version} · Supplier Purchase Order`);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipientEmail)) {
    throw new Error('The assigned Resource email address is invalid');
  }
  const lineRows = (po.lines || []).map(line => `
    <tr>
      <td style="padding:8px;border-bottom:1px solid #e5e7eb">${htmlEscape(line.description || '')}</td>
      <td style="padding:8px;border-bottom:1px solid #e5e7eb;text-align:right">${htmlEscape(line.quantity ?? '')}</td>
      <td style="padding:8px;border-bottom:1px solid #e5e7eb">${htmlEscape(line.unit || '')}</td>
      <td style="padding:8px;border-bottom:1px solid #e5e7eb;text-align:right">${unitPrice(line.unit_price)} ${htmlEscape(po.currency)}</td>
      <td style="padding:8px;border-bottom:1px solid #e5e7eb;text-align:right;font-weight:600">${money(line.amount, po.currency)}</td>
    </tr>`).join('');
  const html = `<!doctype html><html><body style="margin:0;background:#f5f3ff;font-family:Arial,sans-serif;color:#172033">
    <div style="max-width:760px;margin:24px auto;background:#fff;border:1px solid #ddd6fe;border-radius:12px;overflow:hidden">
      <div style="padding:22px 26px;background:#4c1d95;color:#fff">
        <div style="font-size:13px;opacity:.85">RETODO OPS</div>
        <h1 style="margin:5px 0 0;font-size:22px">Supplier Purchase Order ${htmlEscape(poLabel)} · V${htmlEscape(po.version)}</h1>
        <div style="margin-top:6px;font-size:13px">Version ${htmlEscape(po.version)} · Issued ${htmlEscape(dateTime(po.issued_at))}</div>
      </div>
      <div style="padding:24px 26px">
        <p>Hello ${htmlEscape(po.recipient_name)},</p>
        <p>This purchase order confirms that Job <strong>${htmlEscape(po.job_number)}</strong> is assigned to you and work may begin.</p>
        <table style="width:100%;border-collapse:collapse;margin:18px 0;background:#fafafa">
          <tr><td style="padding:7px 10px;color:#667085">Service</td><td style="padding:7px 10px;font-weight:600">${htmlEscape(po.service)}</td></tr>
          <tr><td style="padding:7px 10px;color:#667085">Languages</td><td style="padding:7px 10px;font-weight:600">${htmlEscape(po.source_language)} → ${htmlEscape(po.target_language)}</td></tr>
          <tr><td style="padding:7px 10px;color:#667085">Deadline</td><td style="padding:7px 10px;font-weight:600">${htmlEscape(dateTime(po.deadline))}</td></tr>
        </table>
        <table style="width:100%;border-collapse:collapse;margin-top:20px;font-size:13px">
          <thead><tr style="background:#ede9fe;color:#3b0764"><th style="padding:9px;text-align:left">Description</th><th style="padding:9px;text-align:right">Qty</th><th style="padding:9px;text-align:left">Unit</th><th style="padding:9px;text-align:right">Rate</th><th style="padding:9px;text-align:right">Amount</th></tr></thead>
          <tbody>${lineRows}</tbody>
        </table>
        <div style="margin-top:18px;text-align:right;font-size:18px;font-weight:700;color:#4c1d95">Total: ${money(po.total, po.currency)}</div>
        <p style="margin-top:24px;font-size:13px;color:#475467">Payment terms: ${htmlEscape(po.payment_terms_days || 60)} days${po.invoice_cycle ? ` · Invoice cycle: ${htmlEscape(po.invoice_cycle)}` : ''}.</p>
        <p style="font-size:13px;color:#475467">Client and Account identity remain confidential unless expressly disclosed. Confidentiality, non-disclosure and non-circumvention obligations continue to apply.</p>
        <p style="margin-top:24px">Best regards,<br><strong>Retodo Ops</strong><br><a href="mailto:${htmlEscape(fromEmail)}">${htmlEscape(fromEmail)}</a></p>
      </div>
    </div></body></html>`;
  const plainLines = (po.lines || []).map(line =>
    `${line.description || ''} | ${line.quantity ?? ''} ${line.unit || ''} × ${unitPrice(line.unit_price)} ${po.currency} = ${money(line.amount, po.currency)}`
  ).join('\n');
  const plain = `Hello ${po.recipient_name},\n\nThis purchase order confirms that Job ${po.job_number} is assigned to you and work may begin.\n\nPO: ${poLabel} · Version ${po.version}\nService: ${po.service}\nLanguages: ${po.source_language} → ${po.target_language}\nDeadline: ${dateTime(po.deadline)}\n\n${plainLines}\n\nTotal: ${money(po.total, po.currency)}\nPayment terms: ${po.payment_terms_days || 60} days${po.invoice_cycle ? ` · Invoice cycle: ${po.invoice_cycle}` : ''}.\n\nBest regards,\nRetodo Ops\n${fromEmail}`;
  const boundary = `retodo_${Date.now()}_${Math.random().toString(16).slice(2)}`;
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

exports.handler = async event => {
  if (event.httpMethod !== 'POST') return jsonResponse(405, {error: 'Method not allowed'});
  const bearer = event.headers.authorization || event.headers.Authorization;
  if (!bearer?.startsWith('Bearer ')) return jsonResponse(401, {error: 'Authentication required'});
  let emailRecordId;
  let stage = 'request validation';
  try {
    const body = JSON.parse(event.body || '{}');
    if (!body.purchase_order_id) return jsonResponse(400, {error: 'purchase_order_id is required'});
    stage = 'PO preparation';
    const po = await rpc('prepare_supplier_po_email', {p_po_id: body.purchase_order_id}, bearer);
    emailRecordId = po.email_record_id;
    stage = 'Google OAuth';
    const accessToken = await gmailAccessToken();
    stage = 'Gmail delivery';
    const gmailResponse = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
      method: 'POST',
      headers: {Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({raw: buildMessage(po)})
    });
    const gmail = await gmailResponse.json();
    if (!gmailResponse.ok || !gmail.id) {
      const code = gmail.error?.status || `HTTP ${gmailResponse.status}`;
      throw new Error(`${code}: ${gmail.error?.message || 'Gmail did not accept the message'}`);
    }
    stage = 'delivery audit';
    await rpc('complete_supplier_po_email', {
      p_email_record_id: emailRecordId,
      p_gmail_message_id: gmail.id,
      p_gmail_thread_id: gmail.threadId || null
    }, bearer);
    return jsonResponse(200, {ok: true, message_id: gmail.id, thread_id: gmail.threadId || null});
  } catch (error) {
    const detail = String(error?.message || error || 'Unknown PO email error');
    const message = `${stage}: ${detail}`.slice(0, 1000);
    console.error('Supplier PO email failed', {stage, detail});
    if (emailRecordId) {
      try {
        await rpc('fail_supplier_po_email', {
          p_email_record_id: emailRecordId,
          p_failure_reason: message
        }, bearer);
      } catch { /* Preserve the original delivery error. */ }
    }
    return jsonResponse(500, {ok: false, stage, error: message});
  }
};
