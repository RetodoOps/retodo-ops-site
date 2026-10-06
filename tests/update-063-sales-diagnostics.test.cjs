'use strict';
// Exercise the real API -> worker -> Gmail -> error-rendering path. Every
// external request is intercepted; these tests cannot send mail or use AI.
const {test,beforeEach,afterEach}=require('node:test');
const assert=require('node:assert/strict');
const api=require('../netlify/functions/sales');
const worker=require('../netlify/functions/_shared/sales-worker');
const gmail=require('../netlify/functions/_shared/sales-gmail');
const {diagnostic}=require('../netlify/functions/_shared/sales-diagnostics');
const {publicError}=require('../netlify/functions/_shared/supabase');

const fixture={
 SUPABASE_URL:'https://sales-fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-db-private',
 GOOGLE_CLIENT_ID:'fixture-client.apps.googleusercontent.com',GOOGLE_CLIENT_SECRET:'fixture-google-private',
 GOOGLE_REFRESH_TOKEN:'fixture-refresh-private',SALES_GMAIL_ACCOUNT_EMAIL:'ops@retodo-ops.com',
 TMS_SITE_URL:'https://sales-tms.invalid',GMAIL_FROM_EMAIL:'ops@retodo-ops.com'
};
const sensitive=Object.values(fixture).filter(v=>v.includes('private')).concat('fixture-access-private');
const rawPrivate=sensitive.join(' ');
let savedEnv,savedFetch;
beforeEach(()=>{savedFetch=global.fetch;savedEnv=Object.fromEntries(Object.keys(fixture).map(k=>[k,process.env[k]]));Object.assign(process.env,fixture);});
afterEach(()=>{global.fetch=savedFetch;for(const [k,v]of Object.entries(savedEnv)){if(v===undefined)delete process.env[k];else process.env[k]=v;}});
const response=(data,status=200)=>({status,ok:status>=200&&status<300,json:async()=>data,text:async()=>JSON.stringify(data)});
const malformed=status=>({status,ok:status>=200&&status<300,json:async()=>{throw new SyntaxError(rawPrivate);},text:async()=>rawPrivate});
const event={httpMethod:'POST',headers:{origin:fixture.TMS_SITE_URL,authorization:'Bearer fixture-user'},body:JSON.stringify({action:'check_mailbox'})};

function setup(options={}){
 const calls=[],records=[];
 global.fetch=async(url,request={})=>{
  calls.push({url:String(url),method:request.method||'GET'});
  if(url===fixture.SUPABASE_URL+'/auth/v1/user')return options.auth||response({id:'fixture-admin'});
  if(url===fixture.SUPABASE_URL+'/rest/v1/rpc/sales_is_admin_063')return response(options.admin!==false);
  if(url===fixture.SUPABASE_URL+'/rest/v1/rpc/sales_system_063'){
   const input=JSON.parse(request.body);records.push(input);
   return options.rpc?options.rpc(input):response({ok:true});
  }
  if(url==='https://oauth2.googleapis.com/token'){
   const body=new URLSearchParams(request.body);
   assert.equal(body.get('grant_type'),'refresh_token');
   if(options.tokenRequest)options.tokenRequest(body);
   if(options.networkError)throw options.networkError;
   return options.oauth||response({access_token:'fixture-access-private'});
  }
  if(String(url).startsWith('https://gmail.googleapis.com/gmail/v1/users/me/')){
   assert.equal(request.headers.Authorization,'Bearer fixture-access-private');
   if(options.gmailError)return options.gmailError;
   if(url.endsWith('/profile'))return response({emailAddress:options.account||'ops@retodo-ops.com'});
   if(url.endsWith('/settings/sendAs'))return response({sendAs:options.aliasMissing?[]:[{sendAsEmail:gmail.FROM,verificationStatus:options.aliasStatus||'accepted'}]});
   if(url.includes('/messages?'))return response({messages:[]});
   if(url.endsWith('/messages/send')&&options.sendResponse)return options.sendResponse;
  }
  throw new Error('Unexpected mocked request: '+url);
 };
 return {calls,records};
}
function noPrivate(value){const text=JSON.stringify(value);for(const secret of sensitive)assert.ok(!text.includes(secret),'Private fixture value escaped into a public diagnostic');}
async function check(code,options={}){
 const h=setup(options),result=await api.handler(event),body=JSON.parse(result.body);
 assert.equal(result.statusCode,400);assert.equal(body.code,code);assert.deepEqual(body,diagnostic(code));noPrivate(body);noPrivate(h.records);
 assert.equal(h.records.at(-1).p_action,'mailbox');assert.equal(h.records.at(-1).p_data.ok,false);
 assert.equal(h.records.at(-1).p_data.error,body.error);
 assert.ok(!h.calls.some(c=>c.url.endsWith('/messages/send')));
 return h;
}

test('Rejected refresh token reaches the admin UI and saved status without provider secrets',async()=>{
 const h=await check('GOOGLE_REFRESH_REJECTED',{oauth:response({error:'invalid_grant',error_description:rawPrivate},400)});
 assert.equal(h.calls.filter(c=>c.url.includes('oauth2.googleapis.com')).length,1);
 assert.ok(!h.calls.some(c=>c.url.includes('gmail.googleapis.com')));
});
test('Rejected client credentials remain actionable despite the shared secret-word redactor',async()=>{
 const h=await check('GOOGLE_CLIENT_REJECTED',{oauth:response({error:'invalid_client',error_description:rawPrivate},401)});
 assert.match(h.records[0].p_data.error,/GOOGLE_CLIENT_SECRET/);
 assert.equal(publicError(new Error(h.records[0].p_data.error),'hidden'),'hidden');
});
test('Known OAuth policy, client-type and request failures stay distinct',async()=>{
 for(const [error,code]of [['unauthorized_client','GOOGLE_CLIENT_NOT_ALLOWED'],['access_denied','GOOGLE_POLICY_BLOCKED'],['admin_policy_enforced','GOOGLE_POLICY_BLOCKED'],['invalid_request','GOOGLE_TOKEN_REQUEST_INVALID']]){
  await check(code,{oauth:response({error,error_description:rawPrivate},400)});
 }
});
test('Unknown or malicious provider error fields cannot become public messages',async()=>{
 for(const error of [rawPrivate,'constructor','__proto__',{message:rawPrivate}])await check('GOOGLE_TOKEN_RESPONSE_INVALID',{oauth:response({error,error_description:rawPrivate},400)});
 assert.equal(diagnostic('constructor'),null);assert.equal(diagnostic(rawPrivate),null);
});
test('Malformed and missing access-token responses are safe; transient failures are not blamed on credentials',async()=>{
 await check('GOOGLE_TOKEN_RESPONSE_INVALID',{oauth:malformed(400)});
 await check('GOOGLE_TOKEN_RESPONSE_INVALID',{oauth:response({access_token:null})});
 await check('GOOGLE_TOKEN_RESPONSE_INVALID',{oauth:response({access_token:{value:rawPrivate}})});
 for(const status of [429,500,503])await check('GOOGLE_TEMPORARILY_UNAVAILABLE',{oauth:malformed(status)});
});
test('Connection and body timeouts do not trigger blind retries or expose thrown values',async()=>{
 for(const name of ['TimeoutError','AbortError']){
  const h=await check('GOOGLE_CONNECTION_TIMEOUT',{networkError:Object.assign(new Error(rawPrivate),{name})});
  assert.equal(h.calls.filter(c=>c.url.includes('oauth2.googleapis.com')).length,1);
 }
 await check('GOOGLE_CONNECTION_FAILED',{networkError:new Error(rawPrivate)});
 await check('GOOGLE_CONNECTION_TIMEOUT',{oauth:{status:200,ok:true,json:async()=>{throw Object.assign(new Error(rawPrivate),{name:'TimeoutError'});}}});
});
test('Missing and malformed settings fail before any Google request',async()=>{
 delete process.env.GOOGLE_REFRESH_TOKEN;
 let h=await check('GOOGLE_CONFIG_MISSING');assert.ok(!h.calls.some(c=>c.url.includes('googleapis.com')));
 for(const token of ['"fixture-refresh-private"','{"refresh_token":"fixture-refresh-private"}','Bearer fixture-refresh-private']){
  process.env.GOOGLE_REFRESH_TOKEN=token;h=await check('GOOGLE_CONFIG_FORMAT');assert.ok(!h.calls.some(c=>c.url.includes('googleapis.com')));
 }
});
test('Surrounding whitespace is trimmed and a successful check never exposes tokens or sends mail',async()=>{
 for(const key of ['GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN'])process.env[key]=' \n'+fixture[key]+'\t ';
 process.env.SALES_GMAIL_ACCOUNT_EMAIL=' OPS@RETODO-OPS.COM ';
 const h=setup({tokenRequest:body=>{assert.equal(body.get('client_id'),fixture.GOOGLE_CLIENT_ID);assert.equal(body.get('client_secret'),fixture.GOOGLE_CLIENT_SECRET);assert.equal(body.get('refresh_token'),fixture.GOOGLE_REFRESH_TOKEN);}});
 const result=await api.handler(event);assert.equal(result.statusCode,200);
 assert.deepEqual(JSON.parse(result.body),{account:'ops@retodo-ops.com',alias:gmail.FROM,reply_to:gmail.FROM});noPrivate(JSON.parse(result.body));noPrivate(h.records);
 assert.equal(h.records.at(-1).p_data.ok,true);
 assert.equal(h.calls.filter(c=>c.url.includes('gmail.googleapis.com')).length,3);
 assert.ok(!h.calls.some(c=>c.url.endsWith('/messages/send')));
 assert.equal(process.env.GMAIL_FROM_EMAIL,'ops@retodo-ops.com');
});
test('Disabled Gmail API, missing permissions and Workspace policy are distinguished',async()=>{
 for(const [reason,code]of [['SERVICE_DISABLED','GMAIL_API_DISABLED'],['ACCESS_TOKEN_SCOPE_INSUFFICIENT','GMAIL_PERMISSIONS_MISSING'],['domainPolicy','GOOGLE_POLICY_BLOCKED']]){
  await check(code,{gmailError:response({error:{message:rawPrivate,details:[{reason}]}},403)});
 }
 for(const [reason,code]of [['accessNotConfigured','GMAIL_API_DISABLED'],['insufficientPermissions','GMAIL_PERMISSIONS_MISSING']]){
  await check(code,{gmailError:response({error:{message:rawPrivate,errors:[{reason}]}},403)});
 }
});
test('Other Gmail failures keep safe diagnostics without echoing response bodies',async()=>{
 for(const [status,code]of [[401,'GMAIL_ACCESS_REJECTED'],[403,'GMAIL_API_FORBIDDEN'],[404,'GMAIL_REQUEST_FAILED'],[429,'GOOGLE_TEMPORARILY_UNAVAILABLE'],[503,'GOOGLE_TEMPORARILY_UNAVAILABLE']])await check(code,{gmailError:response({error:{message:rawPrivate}},status)});
});
test('Expected mailbox and accepted Eli alias checks remain mandatory',async()=>{
 await check('GOOGLE_MAILBOX_MISMATCH',{account:'another@example.invalid'});
 await check('GOOGLE_ALIAS_UNVERIFIED',{aliasMissing:true});
 await check('GOOGLE_ALIAS_UNVERIFIED',{aliasStatus:'pending'});
});
test('Session and administrator checks still run before Gmail, and ordinary errors stay redacted',async()=>{
 let h=setup({admin:false}),result=await api.handler(event);assert.equal(result.statusCode,403);assert.equal(h.calls.length,2);
 h=setup({auth:response({message:'Authorization failed: '+rawPrivate},401)});result=await api.handler(event);assert.equal(result.statusCode,401);assert.equal(h.calls.length,1);
 assert.equal(JSON.parse(result.body).error,'The Sales request could not be completed. Check configuration and try again');noPrivate(JSON.parse(result.body));
});
test('A Gmail send rejection still becomes uncertain through the existing worker path with no automatic retry',async()=>{
 let claimed=false;
 const message={id:'00000000-0000-0000-0000-000000000123',lease_id:'fixture-lease',kind:'initial',rfc_id:'<sales.00000000-0000-0000-0000-000000000123@retodo-ops.com>',subject:'Fixture',body:'No live message',attachments:[]};
 const conversation={id:'fixture-conversation',recipient:'test@example.invalid',sender:gmail.FROM,reply_to:gmail.FROM};
 const h=setup({sendResponse:response({error:{errors:[{reason:'insufficientPermissions'}],message:rawPrivate}},403),rpc:({p_action:action})=>{
  if(action==='lock')return response({lease_id:'fixture-worker'});
  if(action==='config')return response({research_enabled:false});
  if(action==='claim_ai')return response(null);
  if(action==='threads'||action==='uncertain')return response([]);
  if(action==='claim'){if(claimed)return response(null);claimed=true;return response({message,conversation});}
  if(action==='begin_send')return response({message,conversation});
  return response({ok:true});
 }});
 const result=await worker.runWorker();assert.equal(result.sent,0);
 assert.equal(h.calls.filter(c=>c.url.endsWith('/messages/send')).length,1);
 const error=h.records.find(r=>r.p_action==='send_error');assert.equal(error.p_data.lease_id,'fixture-lease');assert.match(error.p_data.error,/GMAIL_PERMISSIONS_MISSING/);noPrivate(error);
 assert.equal(h.records.at(-1).p_action,'unlock');
});
