'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../netlify/functions/_shared/sales-worker.js'),'utf8');
const apiSource=fs.readFileSync(path.join(__dirname,'../netlify/functions/sales.js'),'utf8');
function harness({reply=false,timeout=false,settleFail=false,mailboxFail=false}={}){
 const calls=[];let claimed=false;
 const message={id:'message',lease_id:'lease',kind:'followup'},conversation={id:'conversation',thread_id:'thread'};
 const serviceRpc=async(_,{p_action:action,p_data:data})=>{
  calls.push({action,data});
  if(action==='lock')return {lease_id:'worker'};if(action==='config')return {research_enabled:false};if(action==='claim_ai')return null;
  if(action==='threads'||action==='uncertain')return [];
  if(action==='claim'){if(claimed)return null;claimed=true;return {message,conversation};}
  if(action==='begin_send')return reply?null:{message,conversation};
  if(action==='finish_send'&&settleFail)throw new Error('Database unavailable after Gmail accepted');
  return {};
 };
 const gmail={accessToken:async()=>{calls.push({action:'token'});return 'fixture';},verifyMailbox:async()=>{if(mailboxFail)throw new Error('Alias missing');return {account:'ops@retodo-ops.com'};},readThread:async()=>{calls.push({action:'read_thread'});return {messages:reply?[{classification:'reply'}]:[],reference:'<ref@example.invalid>'};},buildMime:()=>{calls.push({action:'mime'});return 'approved-raw';},send:async()=>{calls.push({action:'gmail_post'});if(timeout)throw new Error('Timeout');return {gmail_id:'sent',thread_id:'thread'};}};
 const module={exports:{}};
 vm.runInNewContext(source,{module,exports:module.exports,require:name=>name==='node:crypto'?require(name):name==='./supabase'?{serviceRpc}:name==='./sales-gmail'?gmail:{},process:{env:{GOOGLE_REFRESH_TOKEN:'fixture'}},Date,Buffer,URL,AbortSignal,fetch:()=>{throw new Error('Unexpected network');}});
 return {worker:module.exports,calls};
}
test('Fresh inbox sync precedes begin_send and Gmail POST; worker unlocks on success',async()=>{
 const {worker,calls}=harness();const result=await worker.runWorker();assert.equal(result.sent,1);
 const actions=calls.map(c=>c.action);assert.ok(actions.indexOf('read_thread')<actions.indexOf('begin_send'));assert.ok(actions.indexOf('begin_send')<actions.indexOf('gmail_post'));assert.equal(actions.at(-1),'unlock');
});
test('A reply racing the claim invalidates it before any Gmail POST',async()=>{const {worker,calls}=harness({reply:true});assert.equal((await worker.runWorker()).sent,0);assert.ok(calls.some(c=>c.action==='sync'));assert.ok(!calls.some(c=>c.action==='gmail_post'));});
test('Ambiguous Gmail timeout and completion-database failure never retry POST',async()=>{
 for(const options of [{timeout:true},{settleFail:true}]){
  const {worker,calls}=harness(options);await worker.runWorker();assert.equal(calls.filter(c=>c.action==='gmail_post').length,1);assert.ok(calls.some(c=>c.action==='send_error'));assert.equal(calls.at(-1).action,'unlock');
 }
});
test('Missing Sales alias blocks claims and records connection failure',async()=>{
 const {worker,calls}=harness({mailboxFail:true});await assert.rejects(worker.runWorker(),/Alias missing/);assert.ok(calls.some(c=>c.action==='mailbox'&&!c.data.ok));assert.ok(!calls.some(c=>c.action==='claim'));assert.equal(calls.at(-1).action,'unlock');
});
test('Sales API checks authenticated role before exposing connections or creating jobs',async()=>{
 let role=false,work=0;
 const sb={requireSameOrigin:()=>({headers:{authorization:'Bearer fixture'}}),verifyUser:async()=>({id:'user'}),request:async()=>role,jsonResponse:(status,body)=>({statusCode:status,body}),publicError:e=>e.message};
 const module={exports:{}};vm.runInNewContext(apiSource,{module,exports:module.exports,require:name=>name==='./_shared/supabase'?sb:name==='./_shared/sales-worker'?{invokeWorker:async()=>work++}:{},Buffer,process:{env:{}}});
 let res=await module.exports.handler({httpMethod:'POST',body:JSON.stringify({action:'run'})});assert.equal(res.statusCode,403);assert.equal(work,0);
 role=true;res=await module.exports.handler({httpMethod:'POST',body:JSON.stringify({action:'run'})});assert.equal(res.statusCode,202);assert.equal(work,1);
 res=await module.exports.handler({httpMethod:'GET',body:'{}'});assert.equal(res.statusCode,405);
});
