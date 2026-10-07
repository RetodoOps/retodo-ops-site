'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const signature=require('../tms/sales-signature'),gmail=require('../netlify/functions/_shared/sales-gmail'),ai=require('../netlify/functions/_shared/sales-ai');
const id='00000000-0000-0000-0000-000000000064';
const message={id,subject:'Partnership — Здравейте',body:'Hello Alex,\n\nReviewed <wording> & Unicode: å ø æ.',rfc_id:`<sales.${id}@retodo-ops.com>`,attachments:[],signature:{...signature.DEFAULTS}};
const conversation={recipient:'alex@example.invalid',sender:'eli.s@retodo-ops.com',reply_to:'eli.s@retodo-ops.com'};
function parse(message,convo=conversation,reference){
 const raw=Buffer.from(gmail.buildMime(message,convo,reference),'base64url');
 // Python's independent standards-based parser verifies nesting/decoded bytes.
 const result=spawnSync('python3',['-c',`import sys,json,base64,email.policy
from email.parser import BytesParser
m=BytesParser(policy=email.policy.default).parsebytes(sys.stdin.buffer.read())
def part(p):
 return {'type':p.get_content_type(),'disposition':p.get_content_disposition(),'cid':str(p.get('Content-ID','')),'filename':p.get_filename(),'defects':[str(d) for d in p.defects],'parts':[part(c) for c in p.iter_parts()]} if p.is_multipart() else {'type':p.get_content_type(),'disposition':p.get_content_disposition(),'cid':str(p.get('Content-ID','')),'filename':p.get_filename(),'bytes':base64.b64encode(p.get_payload(decode=True)).decode(),'text':p.get_content() if p.get_content_maintype()=='text' else None,'defects':[str(d) for d in p.defects]}
print(json.dumps({'headers':dict(m.items()),'message':part(m)}))`],{input:raw,maxBuffer:3*1024*1024});
 assert.equal(result.status,0,String(result.stderr));return JSON.parse(result.stdout);
}
const leaves=p=>p.parts?p.parts.flatMap(leaves):[p];
test('Rendered signature has the requested text, smaller original logo and direct links without an address',()=>{
 const html=signature.html(signature.DEFAULTS),text=signature.text(signature.DEFAULTS);
 assert.match(html,/width="110" height="35"/);assert.match(html,/Best Regards,/);assert.match(html,/Eli Stoyanova/);assert.match(html,/href="https:\/\/retodo-ops.com\/"/);assert.match(html,/href="https:\/\/www.linkedin.com\/in\/eli-stoyanova-667831410\/"/);
 assert.ok(signature.DEFAULTS.confidentiality.split(' ').length<=25);assert.doesNotMatch(text,/address|Norway|Bulgaria|Sofia/i);
 assert.deepEqual(Buffer.from(signature.LOGO_BASE64,'base64'),fs.readFileSync(path.join(__dirname,'../tms/Logo-440x140.png')));
});
test('HTML and plain text contain the same captured signature; MIME embeds the exact logo inline and keeps attachments separate',()=>{
 const bytes=Buffer.from('Capability attachment\0\xff');
 const parsed=parse({...message,attachments:[{name:'Capabilities.pdf',mime:'application/pdf',content:bytes.toString('base64')}]},{...conversation,thread_id:'known-thread'},'<previous@example.invalid>');
 assert.equal(parsed.headers.From,'Eli Stoyanova <eli.s@retodo-ops.com>');assert.equal(parsed.headers['Reply-To'],'eli.s@retodo-ops.com');assert.equal(parsed.headers.Subject,message.subject);assert.equal(parsed.headers['In-Reply-To'],'<previous@example.invalid>');
 assert.equal(parsed.message.type,'multipart/mixed');assert.equal(parsed.message.parts[0].type,'multipart/alternative');assert.equal(parsed.message.parts[0].parts[1].type,'multipart/related');
 const parts=leaves(parsed.message);assert.ok(parts.every(p=>p.defects.length===0));
 assert.equal(parts.find(p=>p.type==='text/plain').text.replace(/\r\n/g,'\n'),signature.messageText(message.body,message.signature));
 const html=parts.find(p=>p.type==='text/html').text;assert.ok(html.includes(signature.messageHtml(message.body,message.signature,{logoSrc:'cid:retodo-logo-v1@retodo-ops.com'})));assert.doesNotMatch(html,/<img[^>]+src="https?:/);
 const logo=parts.find(p=>p.type==='image/png');assert.equal(logo.disposition,'inline');assert.equal(logo.cid,'<retodo-logo-v1@retodo-ops.com>');assert.equal(logo.bytes,signature.LOGO_BASE64);
 const file=parts.find(p=>p.disposition==='attachment');assert.equal(file.filename,'Capabilities.pdf');assert.equal(file.bytes,bytes.toString('base64'));
});
test('Legacy and opted-out messages retain the original body and do not acquire a signature or logo',()=>{
 for(const sig of [undefined,{},null]){const parts=leaves(parse({...message,signature:sig}).message);assert.equal(parts.length,1);assert.equal(parts[0].type,'text/plain');assert.equal(parts[0].text.replace(/\r\n/g,'\n'),message.body);}
});
test('Signature without a logo or LinkedIn still has valid alternative MIME and working website text',()=>{
 const sig={...signature.DEFAULTS,show_logo:false,linkedin_url:'',confidentiality:''};
 const parsed=parse({...message,signature:sig}),parts=leaves(parsed.message);
 assert.deepEqual(parts.map(p=>p.type),['text/plain','text/html']);assert.doesNotMatch(parts[1].text,/<img|LinkedIn|confidential/);assert.match(parts[0].text,/https:\/\/retodo-ops.com\//);
});
test('Signature text is escaped and unsafe links, raw HTML fields, control characters and unknown renderer versions fail closed',()=>{
 const html=signature.html({...signature.DEFAULTS,position:'<img src=x onerror=alert(1)> & Sales'});
 assert.match(html,/&lt;img src=x onerror=alert\(1\)&gt; &amp; Sales/);assert.doesNotMatch(html,/<img src=x/);
 for(const change of [{website_url:'javascript:alert(1)'},{website_url:'https://retodo-ops.com@evil.invalid/'},{linkedin_url:'https://linkedin.com.evil.invalid/in/eli/'},{linkedin_url:'https://www.linkedin.com/in/eli/" onmouseover="x'},{closing:'Hello\r\nBcc: bad'},{name:null},{version:2},{show_logo:'true'},{html:'<script>alert(1)</script>'},{position:'x'.repeat(161)}])assert.throws(()=>gmail.buildMime({...message,signature:{...signature.DEFAULTS,...change}},conversation));
});
test('Current settings cannot silently change a captured signature; AI drafts request body-only text with opt-out retained',()=>{
 const captured={...signature.DEFAULTS,position:'Previously approved role'};
 const html=signature.messageHtml(message.body,captured);assert.match(html,/Previously approved role/);assert.doesNotMatch(html,/Business Development/);
 const task=ai.prepare('draft',{}, {approved_facts:'Verified services'}).task;
 assert.match(task,/no closing, sender name, signature/);assert.match(task,/reply-to-opt-out sentence in the body/);
});
