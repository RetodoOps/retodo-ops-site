const ALLOWED_ORIGINS = new Set(['https://retodo-ops.com','https://www.retodo-ops.com']);
const SUCCESS_REDIRECT = 'https://retodo-ops.com/contact.html?submitted=1';
const TURNSTILE_VERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
const SOURCES = new Set(['English','German','French','Other']);
const TARGETS = new Set(['Norwegian (Bokmål)','Norwegian (Nynorsk)','Swedish','Danish','Finnish','Icelandic','Other']);
const WORD_COUNTS = new Set(['','Under 500 words','500–2,000 words','2,000–10,000 words','10,000–50,000 words','50,000+ words / Ongoing']);

function header(event,name){const t=String(name).toLowerCase(),h=event.headers||{};for(const k of Object.keys(h))if(k.toLowerCase()===t)return String(h[k]||'');return '';}
function approvedOrigin(event){const o=header(event,'origin');return ALLOWED_ORIGINS.has(o)?o:null;}
function isAllowedWebsiteRequest(event){if(approvedOrigin(event))return true;const r=header(event,'referer');return [...ALLOWED_ORIGINS].some(o=>r.startsWith(`${o}/`));}
function corsHeaders(event){const o=approvedOrigin(event);return o?{'Access-Control-Allow-Origin':o,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'Content-Type','Vary':'Origin'}:{};}
function jsonResponse(event,statusCode,body){return{statusCode,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...corsHeaders(event)},body:JSON.stringify(body)};}
function redirectResponse(event){return{statusCode:303,headers:{Location:SUCCESS_REDIRECT,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...corsHeaders(event)},body:''};}
function plainFormRequest(event){return header(event,'content-type').toLowerCase().includes('application/x-www-form-urlencoded');}
function successResponse(event){return plainFormRequest(event)?redirectResponse(event):jsonResponse(event,200,{ok:true});}
function readBody(event){const raw=event.isBase64Encoded?Buffer.from(event.body||'','base64').toString('utf8'):(event.body||'');const ct=header(event,'content-type').toLowerCase();if(ct.includes('application/json')){try{return JSON.parse(raw||'{}')}catch{throw new Error('Invalid request body')}}if(ct.includes('application/x-www-form-urlencoded'))return Object.fromEntries(new URLSearchParams(raw));throw new Error('Unsupported request format');}
function text(v,max,n,lines=false){const raw=String(v??'').replace(/\u0000/g,'').trim();if(raw.length>max)throw new Error(`${n} is too long`);return lines?raw.replace(/\r\n?/g,'\n'):raw.replace(/\s+/g,' ');}
function requiredText(v,max,n,lines=false){const x=text(v,max,n,lines);if(!x)throw new Error(`${n} is required`);return x;}
function utcToday(){return new Date().toISOString().slice(0,10);}
function validateEnquiry(body){
  const e={firstName:requiredText(body.first_name,100,'First name'),lastName:requiredText(body.last_name,100,'Last name'),email:requiredText(body.email,254,'Work email'),company:text(body.company,160,'Company'),sourceLanguage:requiredText(body.source_language,100,'Source language'),targetLanguage:requiredText(body.target_language,100,'Target language'),wordCount:text(body.word_count,100,'Word count'),deadline:text(body.deadline,10,'Deadline'),message:requiredText(body.message,5000,'Project details',true)};
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e.email))throw new Error('Work email is invalid');
  if(!SOURCES.has(e.sourceLanguage)||!TARGETS.has(e.targetLanguage)||!WORD_COUNTS.has(e.wordCount))throw new Error('Invalid form selection');
  if(e.deadline&&(!/^\d{4}-\d{2}-\d{2}$/.test(e.deadline)||e.deadline<utcToday()))throw new Error('Deadline is invalid');
  if(e.message.length<10)throw new Error('Project details are too short');
  return e;
}
async function verifyTurnstile(event,body){
  const secret=process.env.TURNSTILE_SECRET_KEY;
  if(!secret)throw new Error('Turnstile secret is not configured');
  const token=requiredText(body['cf-turnstile-response'],2048,'Security token');
  const remoteip=header(event,'x-nf-client-connection-ip')||header(event,'x-forwarded-for').split(',')[0].trim();
  const params=new URLSearchParams({secret,response:token}); if(remoteip)params.set('remoteip',remoteip);
  const response=await fetch(TURNSTILE_VERIFY_URL,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:params});
  const result=await response.json().catch(()=>({}));
  if(!response.ok||result.success!==true)throw new Error(`Turnstile verification failed: ${(result['error-codes']||[]).join(',')||response.status}`);
}
function htmlEscape(v){return String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'","&#039;");}
function cleanHeader(v){return String(v??'').replace(/[\r\n]+/g,' ').trim();}
function encodeHeader(v){return `=?UTF-8?B?${Buffer.from(String(v),'utf8').toString('base64')}?=`;}
function base64url(v){return Buffer.from(v,'utf8').toString('base64').replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');}
async function gmailAccessToken(){const clientId=process.env.GOOGLE_CLIENT_ID,clientSecret=process.env.GOOGLE_CLIENT_SECRET,refreshToken=process.env.GOOGLE_REFRESH_TOKEN;if(!clientId||!clientSecret||!refreshToken)throw new Error('Gmail credentials are not configured');const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:refreshToken,grant_type:'refresh_token'})});const payload=await response.json().catch(()=>({}));if(!response.ok||!payload.access_token)throw new Error(`Google OAuth failed: ${payload.error||response.status}`);return payload.access_token;}
function buildMessage(e){
 const fromEmail=cleanHeader(process.env.GMAIL_FROM_EMAIL||'ops@retodo-ops.com'),fromName=cleanHeader(process.env.GMAIL_FROM_NAME||'Retodo Ops'),recipientEmail=cleanHeader(process.env.PROJECT_ENQUIRY_RECIPIENT||'ops@retodo-ops.com'),subject=cleanHeader(`New project enquiry — ${e.firstName} ${e.lastName}`);
 const rows=[['Name',`${e.firstName} ${e.lastName}`],['Work email',e.email],['Company',e.company||'Not provided'],['Language pair',`${e.sourceLanguage} → ${e.targetLanguage}`],['Approximate word count',e.wordCount||'Not provided'],['Deadline',e.deadline||'Not provided']].map(([l,v])=>`<tr><td style="padding:8px 10px;color:#64748b;border-bottom:1px solid #e2e8f0">${htmlEscape(l)}</td><td style="padding:8px 10px;border-bottom:1px solid #e2e8f0;font-weight:600">${htmlEscape(v)}</td></tr>`).join('');
 const plain=['New Retodo Ops project enquiry','',`Name: ${e.firstName} ${e.lastName}`,`Work email: ${e.email}`,`Company: ${e.company||'Not provided'}`,`Language pair: ${e.sourceLanguage} → ${e.targetLanguage}`,`Approximate word count: ${e.wordCount||'Not provided'}`,`Deadline: ${e.deadline||'Not provided'}`,'','Project details:',e.message,'','Submitted through retodo-ops.com.'].join('\n');
 const html=`<!doctype html><html><body style="margin:0;background:#f8fafc;font-family:Arial,sans-serif;color:#0f172a"><div style="max-width:680px;margin:24px auto;background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden"><div style="padding:20px 24px;background:#0a1628;color:#fff"><div style="font-size:12px;letter-spacing:.08em;opacity:.7">RETODO OPS</div><h1 style="margin:6px 0 0;font-size:22px">New project enquiry</h1></div><div style="padding:24px"><table style="width:100%;border-collapse:collapse;font-size:14px;background:#fff">${rows}</table><h2 style="margin:24px 0 10px;font-size:16px">Project details</h2><div style="padding:14px 16px;background:#f8fafc;border-radius:8px;white-space:pre-wrap;line-height:1.6;font-size:14px">${htmlEscape(e.message)}</div><p style="margin:24px 0 0;color:#64748b;font-size:12px">Submitted through retodo-ops.com.</p></div></div></body></html>`;
 const boundary=`retodo_enquiry_${Date.now()}_${Math.random().toString(16).slice(2)}`;
 const mime=[`From: ${encodeHeader(fromName)} <${fromEmail}>`,`Reply-To: ${e.email}`,`To: ${recipientEmail}`,`Subject: ${encodeHeader(subject)}`,'MIME-Version: 1.0',`Content-Type: multipart/alternative; boundary="${boundary}"`,'',`--${boundary}`,'Content-Type: text/plain; charset="UTF-8"','Content-Transfer-Encoding: base64','',Buffer.from(plain,'utf8').toString('base64'),`--${boundary}`,'Content-Type: text/html; charset="UTF-8"','Content-Transfer-Encoding: base64','',Buffer.from(html,'utf8').toString('base64'),`--${boundary}--`,''].join('\r\n'); return base64url(mime);
}
async function sendEnquiry(e){const accessToken=await gmailAccessToken();const response=await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send',{method:'POST',headers:{Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json'},body:JSON.stringify({raw:buildMessage(e)})});const payload=await response.json().catch(()=>({}));if(!response.ok||!payload.id)throw new Error(`Gmail delivery failed: ${payload.error?.message||response.status}`);}
exports.handler=async event=>{
 if(event.httpMethod==='OPTIONS')return approvedOrigin(event)?{statusCode:204,headers:corsHeaders(event),body:''}:jsonResponse(event,403,{ok:false,error:'Origin not allowed'});
 if(event.httpMethod!=='POST')return jsonResponse(event,405,{ok:false,error:'Method not allowed'});
 if(!isAllowedWebsiteRequest(event))return jsonResponse(event,403,{ok:false,error:'Origin not allowed'});
 let body,enquiry;
 try{body=readBody(event);if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('Invalid request body');if(text(body.website,200,'Website'))return successResponse(event);enquiry=validateEnquiry(body);await verifyTurnstile(event,body);}
 catch(error){console.warn('Project enquiry rejected',{error:String(error?.message||error)});return jsonResponse(event,400,{ok:false,error:'Unable to send project enquiry'});}
 try{await sendEnquiry(enquiry);return successResponse(event);}
 catch(error){console.error('Project enquiry delivery failed',{error:String(error?.message||error)});return jsonResponse(event,500,{ok:false,error:'Unable to send project enquiry'});}
};
