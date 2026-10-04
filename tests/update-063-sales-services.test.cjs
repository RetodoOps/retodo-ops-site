'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const gmail=require('../netlify/functions/_shared/sales-gmail');
const ai=require('../netlify/functions/_shared/sales-ai');
const root=path.join(__dirname,'..');
const id='00000000-0000-0000-0000-000000000123';
const message={id,subject:'Nordic support — introduction',body:'Hello,\n\nA reviewed message.\nEli',rfc_id:`<sales.${id}@retodo-ops.com>`,attachments:[]};
const conversation={recipient:'person@example.invalid',sender:'eli.s@retodo-ops.com',reply_to:'eli.s@retodo-ops.com'};
const response=(body,status=200)=>({ok:status>=200&&status<300,status,json:async()=>body,text:async()=>JSON.stringify(body)});

test('Sales MIME explicitly pins From and Reply-To; operational defaults cannot leak',()=>{
 process.env.GMAIL_FROM_EMAIL='ops@retodo-ops.com';process.env.GMAIL_FROM_NAME='General sender';
 const mime=Buffer.from(gmail.buildMime(message,conversation),'base64url').toString();
 assert.match(mime,/Reply-To: eli\.s@retodo-ops\.com/);assert.match(mime,/<eli\.s@retodo-ops\.com>/);assert.doesNotMatch(mime,/<ops@/);assert.match(mime,new RegExp(`Message-ID: <sales\\.${id}@retodo-ops\\.com>`));
 assert.equal(process.env.GMAIL_FROM_EMAIL,'ops@retodo-ops.com');
 assert.throws(()=>gmail.buildMime(message,{...conversation,sender:'ops@retodo-ops.com'}),/does not match/);
});
test('Gmail thread references and attachment bytes survive MIME construction',()=>{
 const bytes=Buffer.from('Attachment bytes\0\xff');
 const mime=Buffer.from(gmail.buildMime({...message,attachments:[{name:'Capabilities.pdf',mime:'application/pdf',content:bytes.toString('base64')}]},{...conversation,thread_id:'thread-1'},'<first@example.invalid>'),'base64url').toString();
 assert.match(mime,/In-Reply-To: <first@example.invalid>/);assert.match(mime,/References: <first@example.invalid>/);assert.ok(mime.includes(bytes.toString('base64')));
 assert.throws(()=>gmail.buildMime(message,{...conversation,thread_id:'thread'}),/reference/);
});
test('Header injection, malformed attachment content and attachment oversize are rejected',()=>{
 assert.throws(()=>gmail.buildMime({...message,subject:'Hi\r\nBcc: victim@invalid'},conversation),/header/);
 assert.throws(()=>gmail.buildMime(message,{...conversation,recipient:'test@example.invalid\nCc: bad@invalid'}),/header/);
 assert.throws(()=>gmail.validateAttachments([{name:'a\r\nEvil',content:'YQ=='}]),/header/);
 assert.throws(()=>gmail.validateAttachments([{name:'a',content:'@bad'}]),/invalid/);
 assert.throws(()=>gmail.validateAttachments([{name:'a',content:Buffer.alloc(1000001).toString('base64')}]),/1 MB/);
});
const mail=(body,headers=[],labels=[])=>({id:'inbound',internalDate:'1791010000000',labelIds:labels,payload:{mimeType:'text/plain',headers:[{name:'From',value:'Person <person@example.invalid>'},{name:'Subject',value:'Nordic support'},...headers],body:{data:Buffer.from(body).toString('base64url')}}});
test('Replies, OOO, bounce and opt-out classification stop automation; quoted footer is ignored',()=>{
 assert.equal(gmail.classify(mail('Please tell me more.\n\nOn Fri, Eli wrote:\nReply to unsubscribe.'),'ops@retodo-ops.com').classification,'reply');
 assert.equal(gmail.classify(mail('Please remove me from this list.'),'ops@retodo-ops.com').classification,'optout');
 assert.equal(gmail.classify(mail('Away until next week',[{name:'Auto-Submitted',value:'auto-replied'}]),'ops@retodo-ops.com').classification,'ooo');
 const bounce=mail('Failed');bounce.payload.headers[0].value='mailer-daemon@example.invalid';assert.equal(gmail.classify(bounce,'ops@retodo-ops.com').classification,'bounce');
 assert.equal(gmail.classify(mail('Sent manually',[],['SENT']),'ops@retodo-ops.com').classification,'outbound');
});
test('Mailbox verification fails closed for wrong account, missing alias, unverified alias or missing read access',async()=>{
 const original=global.fetch;
 try{
  for(const scenario of ['wrong','missing','unverified','readonly']){
   global.fetch=async url=>url.endsWith('/profile')?response({emailAddress:scenario==='wrong'?'wrong@example.invalid':'ops@retodo-ops.com'}):url.endsWith('/settings/sendAs')?response({sendAs:scenario==='missing'?[]:[{sendAsEmail:gmail.FROM,verificationStatus:scenario==='unverified'?'pending':'accepted'}]}):response({},403);
   await assert.rejects(gmail.verifyMailbox('test'),/match|missing|verified|HTTP 403/);
  }
  global.fetch=async url=>url.endsWith('/profile')?response({emailAddress:'ops@retodo-ops.com'}):url.endsWith('/settings/sendAs')?response({sendAs:[{sendAsEmail:gmail.FROM,verificationStatus:'accepted'}]}):response({messages:[]});
  assert.equal((await gmail.verifyMailbox('test')).alias,gmail.FROM);
 }finally{global.fetch=original;}
});
test('Unknown sends use exact stable Message-ID and do not infer that absence means failure',async()=>{
 const original=global.fetch;const paths=[];
 try{
  global.fetch=async url=>{paths.push(url);return response({messages:[]});};assert.equal(await gmail.findSent('test',message,conversation.recipient),null);assert.ok(decodeURIComponent(paths[0]).includes(`rfc822msgid:${message.rfc_id}`));
  global.fetch=async url=>url.includes('/messages?q=')?response({messages:[{id:'found'}]}):response({id:'found',threadId:'thread',internalDate:'1791010000000',payload:{headers:[{name:'From',value:gmail.FROM},{name:'To',value:conversation.recipient},{name:'Message-ID',value:message.rfc_id}]}});
  assert.equal((await gmail.findSent('test',message,conversation.recipient)).gmail_id,'found');await assert.rejects(gmail.findSent('test',message,'wrong@example.invalid'),/does not match/);
 }finally{global.fetch=original;}
});
test('Gmail send sends exactly the approved raw message and original thread id',async()=>{
 const original=global.fetch;let called;
 try{global.fetch=async(url,opts)=>{called={url,...opts};return response({id:'sent',threadId:'existing'});};assert.deepEqual(await gmail.send('test','approved-raw','existing'),{gmail_id:'sent',thread_id:'existing'});assert.deepEqual(JSON.parse(called.body),{raw:'approved-raw',threadId:'existing'});assert.match(called.url,/messages\/send$/);}
 finally{global.fetch=original;}
});
function priceEnv(){process.env.OPENAI_API_KEY='fixture-no-live-key';process.env.SALES_AI_PRICING_REVIEWED_ON=new Date().toISOString().slice(0,10);process.env.SALES_AI_EUR_PER_USD='1.25';}
test('Cost bounds include tool turns, tool fees and output; missing/stale pricing blocks work',()=>{
 priceEnv();const p=ai.pricing(),bound=ai.estimate('research',p);assert.ok(bound>ai.estimate('draft',p));
 const response={usage:{input_tokens:30000,output_tokens:4000},output:[{type:'web_search_call'},{type:'web_search_call'}]};assert.ok(ai.actualCost(response,p)<bound);assert.equal(ai.actualCost({},p),null);
 process.env.SALES_AI_PRICING_REVIEWED_ON='2020-01-01';assert.throws(ai.pricing,/Review/);priceEnv();
 process.env.SALES_AI_EUR_PER_USD='0.01';assert.throws(ai.pricing,/invalid/);priceEnv();
});
test('Research drops unsourced companies, invalid emails and unsafe LinkedIn URLs',()=>{
 const p={name:'Company',domain:'company.invalid',source_url:'https://company.invalid/vendor',fit_note:'Fits',contacts:[{name:'Person',email:'bad\n@example.invalid',linkedin_url:'javascript:alert(1)',source_url:'https://company.invalid/vendor'}]};
 const r=ai.validateResult('research',{prospects:[p,{...p,name:'Unverified',source_url:'https://made-up.invalid'}],notes:'Test'},[{url:p.source_url,title:'Evidence'}]);
 assert.equal(r.prospects.length,1);assert.equal(r.prospects[0].contacts[0].email,null);assert.equal(r.prospects[0].contacts[0].linkedin_url,'');
 assert.throws(()=>ai.prepare('draft',{},{}),/approved company facts/);
});
test('AI timeout and invalid/incomplete results retain cost accounting; no implicit retry',async()=>{
 priceEnv();const original=global.fetch;let calls=0;
 try{
  global.fetch=async()=>{calls++;throw new Error('timeout');};const job={kind:'research',cost_config:ai.pricing(),reserved_eur:ai.estimate('research'),payload:{brief:'Test'}};
  assert.equal((await ai.run(job)).state,'uncertain');assert.equal(calls,1);
  global.fetch=async()=>response({id:'resp_fixture',status:'incomplete',usage:{input_tokens:100,output_tokens:100},output:[]});const r=await ai.run(job);assert.equal(r.state,'failed');assert.ok(r.cost_eur>0);
 }finally{global.fetch=original;}
});
test('Operational Gmail and supplier PO implementations are untouched by Sales',()=>{
 const operational=fs.readFileSync(path.join(root,'netlify/functions/_shared/gmail.js'),'utf8');
 const supplier=fs.readFileSync(path.join(root,'netlify/functions/send-supplier-po.js'),'utf8');
 assert.match(operational,/GMAIL_FROM_EMAIL/);assert.match(supplier,/GMAIL_FROM_EMAIL/);assert.doesNotMatch(operational,/sales-gmail|eli\.s@/);assert.doesNotMatch(supplier,/sales-gmail|eli\.s@/);
});
test('Worker key comparison rejects missing, short and mismatched credentials',()=>{
 const {validWorkerKey}=require('../netlify/functions/_shared/sales-worker');process.env.SALES_WORKER_SECRET='x'.repeat(32);assert.equal(validWorkerKey('x'.repeat(32)),true);assert.equal(validWorkerKey('y'.repeat(32)),false);assert.equal(validWorkerKey('x'),false);delete process.env.SALES_WORKER_SECRET;assert.equal(validWorkerKey(undefined),false);
});

test('Long Unicode subjects fold into valid encoded words without header injection',()=>{
 const mime=Buffer.from(gmail.buildMime({...message,subject:'Здравейте '.repeat(18)},conversation),'base64url').toString();
 for(const line of mime.split('\r\n'))assert.ok(Buffer.byteLength(line)<998);
 for(const word of mime.match(/=\?UTF-8\?B\?[^?]+\?=/g)||[])assert.ok(word.length<=75);
});
test('Related delivery reports and new-subject Sales replies are checked outside the original thread',async()=>{
 const original=global.fetch;
 const sent={id:'original',threadId:'thread',internalDate:'1791010000000',labelIds:['SENT'],payload:{mimeType:'text/plain',headers:[{name:'From',value:gmail.FROM},{name:'To',value:conversation.recipient},{name:'Message-ID',value:message.rfc_id}],body:{data:Buffer.from('Sent').toString('base64url')}}};
 const bounced={id:'bounce',threadId:'other-thread',internalDate:'1791010010000',payload:{mimeType:'multipart/report',headers:[{name:'From',value:'mailer-daemon@example.invalid'},{name:'Subject',value:'Delivery failure'},{name:'Message-ID',value:'<bounce@example.invalid>'}],parts:[{mimeType:'message/delivery-status',body:{data:Buffer.from('Final-Recipient: rfc822; '+conversation.recipient).toString('base64url')}}]}};
 const reply=mail('New subject response',[{name:'To',value:gmail.FROM}]);reply.id='new-subject';reply.payload.headers[0].value=conversation.recipient;
 try{
  global.fetch=async url=>{
   if(url.includes('/threads/'))return response({id:'thread',messages:[sent]});
   if(url.includes('/messages/bounce'))return response(bounced);
   if(url.includes('/messages/new-subject'))return response(reply);
   return response({messages:[{id:decodeURIComponent(url).includes('mailer-daemon')?'bounce':'new-subject'}]});
  };
  const result=await gmail.readThread('fixture',{...conversation,thread_id:'thread',created_at:'2026-10-01T00:00:00Z'},'ops@retodo-ops.com');
  assert.ok(result.messages.some(m=>m.gmail_id==='bounce'&&m.classification==='bounce'));
  assert.ok(result.messages.some(m=>m.gmail_id==='new-subject'&&m.classification==='reply'));
  assert.equal(result.reference,message.rfc_id);
  global.fetch=async url=>url.includes('/threads/')?response({id:'thread',messages:[sent]}):response({messages:[],nextPageToken:'more'});
  await assert.rejects(gmail.readThread('fixture',{...conversation,thread_id:'thread',created_at:'2026-10-01'},'ops@retodo-ops.com'),/need review/);
 }finally{global.fetch=original;}
});
