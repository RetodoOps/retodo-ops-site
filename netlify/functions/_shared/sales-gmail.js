'use strict';

// Intentionally separate from operational email. No default-sender mutation or fallback.
const FROM = 'eli.s@retodo-ops.com';
const NAME = 'Eli Stoyanova';
const API = 'https://gmail.googleapis.com/gmail/v1/users/me';
const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const b64url = value => Buffer.from(value).toString('base64url');
const header = value => {
  const text = String(value || '');
  if (/[\r\n\0]/.test(text)) throw new Error('Invalid email header');
  return text;
};
const encoded = value => {
  const chunks=[];let chunk='';
  for(const char of header(value)){
    if(Buffer.byteLength(chunk+char)>42){chunks.push(chunk);chunk='';}
    chunk+=char;
  }
  if(chunk)chunks.push(chunk);
  return chunks.map(text=>`=?UTF-8?B?${Buffer.from(text).toString('base64')}?=`).join('\r\n ');
};
const folded = value => Buffer.from(value).toString('base64').match(/.{1,76}/g)?.join('\r\n') || '';
const address = value => {
  const text = header(value).trim().toLowerCase();
  if (!emailPattern.test(text) || text.length > 254) throw new Error('Invalid recipient address');
  return text;
};

async function accessToken() {
  const client = process.env.GOOGLE_CLIENT_ID;
  const secret = process.env.GOOGLE_CLIENT_SECRET;
  const refresh = process.env.GOOGLE_REFRESH_TOKEN;
  if (!client || !secret || !refresh) throw new Error('The Google mail connection is not configured');
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({client_id: client, client_secret: secret, refresh_token: refresh, grant_type: 'refresh_token'}),
    signal: AbortSignal.timeout(15000),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) throw new Error('Google mail authorization failed. Reconnect the mailbox with the required scopes');
  return data.access_token;
}

async function request(token, path, body) {
  const res = await fetch(`${API}${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {Authorization: `Bearer ${token}`, ...(body === undefined ? {} : {'Content-Type': 'application/json'})},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error(`Sales Gmail request failed (HTTP ${res.status}). Check the mailbox connection and scopes`);
  return res.json();
}

async function verifyMailbox(token) {
  const [profile, aliases] = await Promise.all([
    request(token, '/profile'), request(token, '/settings/sendAs'),
  ]);
  const expected = (process.env.SALES_GMAIL_ACCOUNT_EMAIL || 'ops@retodo-ops.com').toLowerCase();
  if (profile.emailAddress?.toLowerCase() !== expected) throw new Error('The connected Gmail account does not match the Sales mailbox');
  const alias = aliases.sendAs?.find(a => a.sendAsEmail?.toLowerCase() === FROM);
  if (!alias || alias.verificationStatus !== 'accepted') throw new Error('Eli’s Sales alias is missing or is not verified');
  // Prove read access, including messages.list used for send reconciliation.
  await request(token, '/messages?maxResults=1&q=' + encodeURIComponent(`from:${FROM}`));
  return {account: profile.emailAddress, alias: FROM, reply_to: FROM};
}

function validateAttachments(items = []) {
  if (!Array.isArray(items) || items.length > 3) throw new Error('Attach at most 3 files');
  let total = 0;
  return items.map(item => {
    const name = header(item.name);
    const mime = header(item.mime || 'application/octet-stream');
    if (!name || name.length > 150 || !/^[\w.+-]+\/[\w.+-]+$/.test(mime)) throw new Error('Invalid attachment details');
    if (typeof item.content !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(item.content)) throw new Error('Attachment content is invalid');
    const bytes = Buffer.from(item.content, 'base64');
    total += bytes.length;
    if (total > 1000000) throw new Error('The total attachment limit is 1 MB');
    return {name, mime, bytes};
  });
}

function buildMime(message, conversation, reference) {
  if (conversation.sender !== FROM || conversation.reply_to !== FROM) throw new Error('Sales sender configuration does not match Eli’s alias');
  const to = address(conversation.recipient);
  const subject = header(message.subject);
  if (!subject.trim() || subject.length > 200 || !String(message.body || '').trim()) throw new Error('A subject and message are required');
  const id = header(message.rfc_id);
  if (!/^<sales\.[a-f0-9-]{36}@retodo-ops\.com>$/.test(id)) throw new Error('A stable Sales message identifier is required');
  const files = validateAttachments(message.attachments);
  const boundary = 'sales_' + message.id.replace(/[^a-z0-9]/gi, '');
  const lines = [`From: ${encoded(NAME)} <${FROM}>`, `Reply-To: ${FROM}`, `To: ${to}`, `Subject: ${encoded(subject)}`, `Message-ID: ${id}`, 'MIME-Version: 1.0'];
  if (conversation.thread_id) {
    if (!reference || !/^<[^\s<>]+@[^\s<>]+>$/.test(header(reference))) throw new Error('A verified reply reference is required');
    lines.push(`In-Reply-To: ${reference}`, `References: ${reference}`);
  }
  lines.push(`Content-Type: multipart/mixed; boundary="${boundary}"`, '', `--${boundary}`, 'Content-Type: text/plain; charset=UTF-8', 'Content-Transfer-Encoding: base64', '', folded(String(message.body).replace(/\r?\n/g, '\r\n')));
  for (const file of files) lines.push(`--${boundary}`, `Content-Type: ${file.mime}`, `Content-Disposition: attachment; filename*=UTF-8''${encodeURIComponent(file.name).replace(/'/g,'%27')}`, 'Content-Transfer-Encoding: base64', '', folded(file.bytes));
  lines.push(`--${boundary}--`, '');
  return b64url(lines.join('\r\n'));
}

const getHeader = (payload, name) => payload?.headers?.find(h => h.name.toLowerCase() === name.toLowerCase())?.value || '';
function textBody(payload) {
  if (payload?.mimeType === 'text/plain' && payload.body?.data) return Buffer.from(payload.body.data, 'base64url').toString('utf8');
  return (payload?.parts || []).map(textBody).filter(Boolean).join('\n');
}
function reportBody(payload) {
  const own=payload?.body?.data?Buffer.from(payload.body.data,'base64url').toString('utf8'):'';
  return [own,...(payload?.parts||[]).map(reportBody)].filter(Boolean).join('\n');
}
const extractAddress = value => (String(value).match(/<([^<>]+)>/)?.[1] || String(value)).trim().toLowerCase();

function classify(message, account) {
  const p = message.payload;
  const from = extractAddress(getHeader(p, 'From'));
  // Inspect only new text for opt-outs, not a quoted copy of our own opt-out footer.
  const body = (textBody(p) || message.snippet || '').slice(0, 20000);
  const newText = body.split(/\n(?:On .+wrote:|Le .+écrit|From:|>)/i)[0].split(/\r?\n/).filter(l => !/^>/.test(l)).join('\n');
  const subject = getHeader(p, 'Subject');
  let classification = 'reply';
  if (message.labelIds?.includes('SENT') || [FROM, account.toLowerCase()].includes(from)) classification = 'outbound';
  else if (/mailer-daemon|postmaster/i.test(from) || /delivery (status notification|failure)|undeliverable|mail delivery subsystem/i.test(subject) || p?.mimeType === 'multipart/report') classification = 'bounce';
  else if (/unsubscribe|remove me|remove (us|my email)|do not (email|contact)|don't (email|contact)|stop (emailing|contacting)|not interested/i.test(newText)) classification = 'optout';
  else if (/out of (the )?office|automatic reply|auto.?reply|on (annual )?leave/i.test(subject) || /auto-replied|auto-generated/i.test(getHeader(p, 'Auto-Submitted'))) classification = 'ooo';
  return {gmail_id: message.id, rfc_id: getHeader(p, 'Message-ID'), subject: subject.replace(/[\r\n]/g, ' ').slice(0, 200), body, classification, sent_at: new Date(Number(message.internalDate)).toISOString()};
}

async function readThread(token, conversation, account) {
  const thread = await request(token, `/threads/${encodeURIComponent(conversation.thread_id)}?format=full`);
  if (thread.id !== conversation.thread_id || !Array.isArray(thread.messages) || !thread.messages.length) throw new Error('The Gmail thread could not be verified');
  const last = [...thread.messages].sort((a,b) => Number(b.internalDate)-Number(a.internalDate))[0];
  const messages=thread.messages.map(m => classify(m, account));
  // Delivery status reports may have their own Gmail thread. Match a known
  // outbound RFC Message-ID, or an exact final recipient in a delivery report.
  const outboundIds=new Set(thread.messages.filter(m=>m.labelIds?.includes('SENT') || extractAddress(getHeader(m.payload,'From'))===FROM).map(m=>getHeader(m.payload,'Message-ID')).filter(Boolean));
  const after=Math.max(0,Math.floor(new Date(conversation.created_at).getTime()/1000)-60);
  const query=`in:anywhere after:${after} (from:mailer-daemon OR from:postmaster) "${address(conversation.recipient)}"`;
  const candidates=await request(token,'/messages?maxResults=5&q='+encodeURIComponent(query));
  if(candidates.nextPageToken)throw new Error('Several delivery reports need review before this conversation can send');
  for(const candidate of candidates.messages||[]){
    if(thread.messages.some(m=>m.id===candidate.id))continue;
    const report=await request(token,`/messages/${encodeURIComponent(candidate.id)}?format=full`);
    const reportText=reportBody(report.payload);
    const finalRecipients=[...reportText.matchAll(/(?:Final|Original)-Recipient:\s*rfc822\s*;\s*([^\s<>;]+)/gi)].map(m=>m[1].toLowerCase());
    const exactId=[...outboundIds].some(id=>reportText.includes(id));
    if(exactId || (report.payload?.mimeType==='multipart/report' && finalRecipients.includes(conversation.recipient))){
      messages.push({...classify(report,account),classification:'bounce'});
    }
  }
  // A known contact may answer with a new subject. Only mail from that contact
  // addressed to the Sales alias is considered; never import the whole mailbox.
  const replyQuery=`in:anywhere after:${after} from:${address(conversation.recipient)} to:${FROM}`;
  const replies=await request(token,'/messages?maxResults=5&q='+encodeURIComponent(replyQuery));
  if(replies.nextPageToken)throw new Error('Several separate replies need review before this conversation can send');
  for(const candidate of replies.messages||[]){
    if(messages.some(m=>m.gmail_id===candidate.id))continue;
    const reply=await request(token,`/messages/${encodeURIComponent(candidate.id)}?format=full`);
    const to=[getHeader(reply.payload,'To'),getHeader(reply.payload,'Cc')].join(',').split(',').map(extractAddress);
    if(extractAddress(getHeader(reply.payload,'From'))===conversation.recipient && to.includes(FROM))messages.push(classify(reply,account));
  }
  return {messages, reference: getHeader(last.payload, 'Message-ID')};
}

async function findSent(token, message, recipient) {
  const list = await request(token, '/messages?q=' + encodeURIComponent(`in:sent rfc822msgid:${message.rfc_id}`) + '&maxResults=5');
  if (!list.messages?.length) return null; // Absence is not proof that Gmail did not send.
  if (list.messages.length !== 1) throw new Error('More than one Gmail message matches; manual reconciliation required');
  const found = await request(token, `/messages/${encodeURIComponent(list.messages[0].id)}?format=metadata`);
  if (extractAddress(getHeader(found.payload, 'From')) !== FROM || extractAddress(getHeader(found.payload, 'To')) !== recipient || getHeader(found.payload, 'Message-ID') !== message.rfc_id) throw new Error('The reconciled message does not match the approved sender and recipient');
  return {gmail_id: found.id, thread_id: found.threadId, sent_at: new Date(Number(found.internalDate)).toISOString()};
}

async function send(token, raw, threadId) {
  const result = await request(token, '/messages/send', {raw, ...(threadId ? {threadId} : {})});
  if (!result.id || !result.threadId) throw new Error('Gmail did not return a message confirmation');
  return {gmail_id: result.id, thread_id: result.threadId};
}

module.exports = {FROM, NAME, accessToken, verifyMailbox, buildMime, validateAttachments, readThread, findSent, send, classify, getHeader, textBody};
