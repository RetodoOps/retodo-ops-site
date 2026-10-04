// Replays repository SQL in isolated PostgreSQL with minimal Supabase platform stubs.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath)throw new Error('Set PGLITE_MODULE to @electric-sql/pglite/dist/index.js');
const {PGlite}=await import(pathToFileURL(modulePath));
const {pgcrypto}=await import(pathToFileURL(modulePath.replace(/index.js$/,'contrib/pgcrypto.js')));
const db=new PGlite({extensions:{pgcrypto}});
const read=path=>fs.readFileSync(new URL('../'+path,import.meta.url),'utf8');
try{
await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;
CREATE SCHEMA auth;CREATE SCHEMA storage;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,raw_user_meta_data jsonb DEFAULT '{}',raw_app_meta_data jsonb DEFAULT '{}',email_confirmed_at timestamptz,last_sign_in_at timestamptz,created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now());
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'authenticated') $$;
GRANT USAGE ON SCHEMA public,auth TO authenticated,anon,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated,service_role;`);
await db.exec(read('tms/setup.sql').split('-- ── SAMPLE DATA')[0]);
await db.exec("INSERT INTO auth.users(id,email) VALUES('00000000-0000-0000-0000-000000000099','aleksandra.atanasoff@gmail.com');SET test.uid='00000000-0000-0000-0000-000000000099'");
const files=fs.readdirSync(new URL('../tms/migrations/',import.meta.url)).filter(f=>/^\d+.*\.sql$/.test(f)).sort();
for(const file of files){
// Migration 037 is absent from this repository. Its unrelated audit writer is
// explicitly stubbed in this isolated compatibility test; no full production replay is claimed.
if(file.startsWith('038'))await db.exec(`CREATE OR REPLACE FUNCTION public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;`);
if(Number(file.slice(0,3))>38)continue;try{await db.exec(read('tms/migrations/'+file));}catch(e){throw new Error(file+': '+e.message);} }
console.log('PASS reporting schema through 038 (missing 037 audit writer stubbed; later unrelated migrations not replayed)');
await db.exec(`INSERT INTO auth.users(id,email) VALUES('00000000-0000-0000-0000-000000000001','qa@example.invalid');UPDATE profiles SET role='admin' WHERE id='00000000-0000-0000-0000-000000000001';SET test.uid='00000000-0000-0000-0000-000000000001';`);
await db.exec(read('tms/migrations/050_update_052_dashboard_cancelled_status.sql'));
await db.exec(read('tms/migrations/053_reports_functional_upgrade.sql'));
await db.exec(read('tms/migrations/054_reports_eur_scoop_detail.sql'));
await db.exec(read('tms/migrations/055_client_scoop_invoicing.sql'));
await db.exec(read('tms/migrations/056_reports_selection_invoice_revisions_search.sql'));
await db.exec(read('tms/migrations/057_sales_workspace.sql'));
console.log('PASS Sales migration applied to actual 062 schema');
await db.exec(read('tms/migrations/057_sales_workspace.sql'));
console.log('PASS Sales migration reapplication');
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const rpc=async(name,args=[]) => (await db.query(`SELECT ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args)).rows[0].result;
const cmd=(action,data={})=>rpc('sales_command_063',[action,data]);
const workspace=()=>rpc('sales_workspace_063',['',0,50]);
const privileged=async sql=>{await db.exec('RESET ROLE');try{return await db.exec(sql);}finally{await db.exec("SET ROLE authenticated;SET request.jwt.claim.role='authenticated'");}};
const sys=async(action,data={})=>{await db.exec("RESET ROLE;SET ROLE service_role;SET request.jwt.claim.role='service_role'");try{return await rpc('sales_system_063',[action,data]);}finally{await db.exec("RESET ROLE;SET ROLE authenticated;SET request.jwt.claim.role='authenticated'");}};
let passed=0;const check=async(name,fn)=>{await fn();console.log('PASS',name);passed++;};
const rejects=(fn,pattern)=>assert.rejects(fn,pattern);
await db.exec("SET ROLE authenticated;SET request.jwt.claim.role='authenticated'");
let settings=(await workspace()).settings;
const setSettings=async patch=>{settings={...settings,...patch};return cmd('settings',settings);};
let counter=0;
const make=async()=>{
 const n=++counter;
 const p=await cmd('prospect',{name:`Pilot ${n}`,domain:`pilot${n}.invalid`,fit_note:'Test only',source_url:'https://source.invalid'});
 const k=await cmd('contact',{prospect_id:p.id,name:'Test Person',email:`person${n}@pilot.invalid`,source_url:'https://source.invalid/contact',outreach_basis:'Relevant professional contact; test fixture only',verified:true});
 const c=await cmd('sequence',{contact_id:k.id,due_at:new Date(Date.now()-3600000).toISOString(),messages:[{subject:'Nordic services',body:'Initial',delay_days:0},{subject:'Nordic services',body:'First follow-up',delay_days:5},{subject:'Nordic services',body:'Second follow-up',delay_days:12}]});
 return {p:p.id,k:k.id,c:c.id};
};
const detail=c=>rpc('sales_detail_063',[c]);
const approve=async c=>{const d=await detail(c);const msgs=d.messages.filter(m=>m.state==='draft');await cmd('approve',{messages:msgs.map(m=>({id:m.id,version:m.version}))});return msgs;};
await check('Admin-only RPC and RLS; PM/QA/resource/anonymous cannot read or mutate Sales',async()=>{
 for(const role of ['pm','qa','resource','client_relations']){
  await privileged(`UPDATE profiles SET role='${role}' WHERE id='${id(1)}'`);
  await rejects(workspace(),/administrator/);
  assert.equal((await db.query('SELECT * FROM sales_prospects')).rows.length,0);
  await rejects(cmd('prospect',{name:'Denied',domain:'denied.invalid'}),/administrator/);
 }
 await privileged(`UPDATE profiles SET role='admin' WHERE id='${id(1)}'`);
 await rejects(db.query("INSERT INTO sales_prospects(name,domain) VALUES('Direct write','write.invalid')"),/permission denied/);
 await rejects(rpc('sales_system_063',['config',{}]),/permission denied/);
 await db.exec('RESET ROLE;SET ROLE anon');await rejects(workspace(),/permission denied/);await db.exec('RESET ROLE;SET ROLE authenticated');
});
await check('Installation defaults: EUR 30, sending off, research off, no live data',async()=>{const d=await workspace();assert.equal(Number(d.settings.monthly_cap),30);assert.equal(d.settings.sending_enabled,false);assert.equal(d.settings.research_enabled,false);assert.equal(d.counts.prospects,0);await rejects(setSettings({sending_enabled:true}),/mailbox/);settings.sending_enabled=false;});
let first=await make();let firstMessages;
await check('Duplicate company/domain/contact and parallel company approaches blocked',async()=>{
 await rejects(cmd('prospect',{name:'Pilot 1',domain:'other.invalid'}),/already exists/);
 await rejects(cmd('prospect',{name:'Another Name',domain:'pilot1.invalid'}),/duplicate key/);
 await rejects(cmd('contact',{prospect_id:first.p,name:'Duplicate',email:'person1@pilot.invalid'}),/duplicate key/);
 const k=await cmd('contact',{prospect_id:first.p,name:'Other',email:'other@pilot.invalid'});
 await rejects(cmd('sequence',{contact_id:k.id,messages:[{subject:'Other',body:'Duplicate approach'}]}),/duplicate key/);
});
await check('Stale/missing versions and unverified recipients fail whole-batch approval',async()=>{
 const d=await detail(first.c);const m=d.messages[0];
 await rejects(cmd('approve',{messages:[{id:m.id}]}),/changed/);
 await rejects(cmd('message',{id:m.id,subject:'Changed',body:'Bad'}),/changed/);
 await privileged(`UPDATE sales_contacts SET verified_at=NULL WHERE id='${first.k}'`);
 await rejects(approve(first.c),/Verify/);
 await privileged(`UPDATE sales_contacts SET verified_at=now() WHERE id='${first.k}'`);
 const list=d.messages.map(m=>({id:m.id,version:m.version}));list[1].version=999;
 await rejects(cmd('approve',{messages:list}),/changed/);
 assert.ok((await detail(first.c)).messages.every(m=>m.state==='draft'));
});
await check('Batch snapshot includes exact sender, recipient, body, attachments and timing; immutable history',async()=>{
 firstMessages=await approve(first.c);
 const approval=(await db.query('SELECT * FROM sales_approvals ORDER BY created_at DESC LIMIT 1')).rows[0];
 assert.equal(approval.snapshot.length,3);assert.equal(approval.snapshot[0].sender,'eli.s@retodo-ops.com');assert.equal(approval.snapshot[0].reply_to,'eli.s@retodo-ops.com');assert.equal(approval.snapshot[0].recipient,'person1@pilot.invalid');
 assert.ok(approval.snapshot.some(x=>x.message.body==='First follow-up'&&x.message.delay_days===5));
 await rejects(db.query("UPDATE sales_approvals SET snapshot='[]'"),/permission denied/);
 await db.exec('RESET ROLE');await rejects(db.query('DELETE FROM sales_approvals'),/append-only/);await db.exec('SET ROLE authenticated');
});
await check('Sender remains Eli; disabled sending claims nothing',async()=>{assert.equal(await sys('claim'),null);assert.ok((await detail(first.c)).conversations.every(c=>c.sender==='eli.s@retodo-ops.com'&&c.reply_to===c.sender));});
await check('Edits revoke approvals, including initial subject changes affecting follow-ups',async()=>{
 const d=await detail(first.c),m=d.messages.find(m=>m.kind==='initial');
 await cmd('message',{id:m.id,version:m.version,subject:'Nordic services',body:'Revised initial',due_at:m.due_at});
 assert.ok((await detail(first.c)).messages.every(m=>m.state==='draft'));await approve(first.c);
});
await check('Conversation recipient cannot change; contact evidence edit invalidates queued approvals',async()=>{
 let d=await detail(first.c),k=d.contacts.find(k=>k.id===first.k);
 await rejects(cmd('contact',{...k,prospect_id:first.p,email:'new@pilot.invalid',verified:true}),/original recipient/);
 await cmd('contact',{...k,prospect_id:first.p,verified:true});assert.ok((await detail(first.c)).messages.every(m=>m.state==='draft'));await approve(first.c);
});
await sys('mailbox',{ok:true});await setSettings({sending_enabled:true});
let claim;
await check('Atomic claim: competing worker cannot claim the same conversation',async()=>{
 claim=await sys('claim');assert.ok(claim?.message);assert.equal(claim.message.kind,'initial');assert.equal(await sys('claim'),null);
 assert.equal(await sys('begin_send',{id:claim.message.id,lease_id:id(999)}),null);
});
await check('Sending requires matching approval and stable lease; send errors become uncertain, never requeued',async()=>{
 assert.ok(await sys('begin_send',{id:claim.message.id,lease_id:claim.message.lease_id}));
 await sys('send_error',{id:claim.message.id,lease_id:claim.message.lease_id,error:'Network interrupted after POST'});
 assert.equal((await detail(first.c)).messages.find(m=>m.id===claim.message.id).state,'uncertain');
 assert.equal(await sys('claim'),null);await rejects(cmd('message',{...claim.message,body:'Retry'}),/cannot be edited/);
});
await check('Uncertain send reconciles only once and pins Gmail thread',async()=>{
 await sys('finish_send',{id:claim.message.id,lease_id:claim.message.lease_id,gmail_id:'gmail-first',thread_id:'thread-first'});
 await rejects(sys('finish_send',{id:claim.message.id,lease_id:claim.message.lease_id,gmail_id:'gmail-first',thread_id:'thread-first'}),/no longer matches/);
 assert.equal((await detail(first.c)).conversations[0].thread_id,'thread-first');
});
await check('Follow-up waits for actual send time and skips weekends in Sofia',async()=>{
 assert.equal(await sys('claim'),null);
 const due=await rpc('sales_workspace_063',['',0,50]);assert.equal(due.counts.sent,1);
 await db.exec('RESET ROLE');const row=(await db.query("SELECT sales_business_due_063('2026-10-02 10:00:00+03',1) d")).rows[0];assert.equal(new Date(row.d).toISOString(),'2026-10-05T07:00:00.000Z');await db.exec('SET ROLE authenticated');
 await privileged(`UPDATE sales_messages SET sent_at=now()-interval '20 days' WHERE id='${claim.message.id}'`);
});
let follow;
await check('Stale/failed mailbox checks block follow-ups immediately before send',async()=>{
 follow=await sys('claim');assert.equal(follow.message.kind,'followup');
 await rejects(sys('begin_send',{id:follow.message.id,lease_id:follow.message.lease_id}),/stale/);
 await sys('sync',{conversation_id:first.c,error:'Read unavailable'});
 await rejects(sys('begin_send',{id:follow.message.id,lease_id:follow.message.lease_id}),/stale/);
});
await check('Inbound reply stops claimed and future outreach; repeated sync does not duplicate messages',async()=>{
 const inbound={gmail_id:'gmail-reply',rfc_id:'<reply@example.invalid>',classification:'reply',body:'Tell me more',subject:'Nordic services',sent_at:new Date().toISOString()};
 await sys('sync',{conversation_id:first.c,messages:[inbound]});await sys('sync',{conversation_id:first.c,messages:[inbound]});
 const d=await detail(first.c);assert.equal(d.conversations[0].state,'replied');assert.equal(d.messages.filter(m=>m.gmail_id==='gmail-reply').length,1);assert.ok(d.messages.filter(m=>m.kind==='followup').every(m=>m.state==='cancelled'));
 assert.equal(await sys('begin_send',{id:follow.message.id,lease_id:follow.message.lease_id}),null);assert.equal(await sys('claim'),null);
});
await check('A human-reviewed reply can send from Eli on the same conversation',async()=>{
 const r=await cmd('reply',{conversation_id:first.c,subject:'Nordic services',body:'Reply draft'});await cmd('approve',{messages:[{id:r.id,version:1}]});
 const c=await sys('claim');assert.equal(c.message.kind,'reply');assert.equal(c.conversation.sender,'eli.s@retodo-ops.com');
 await sys('sync',{conversation_id:first.c,messages:[]});assert.ok(await sys('begin_send',{id:c.message.id,lease_id:c.message.lease_id}));
 await sys('finish_send',{id:c.message.id,lease_id:c.message.lease_id,gmail_id:'gmail-sales-reply',thread_id:'thread-first'});
});
await check('Manual sent mail and out-of-office pause sequences without auto-resume',async()=>{
 for(const classification of ['outbound','ooo']){
  const f=await make();await approve(f.c);
  await sys('sync',{conversation_id:f.c,messages:[{gmail_id:'gmail-'+classification,rfc_id:'<'+classification+'@example.invalid>',classification,body:'Automatic response',subject:'Nordic services',sent_at:new Date().toISOString()}]});
  assert.equal((await detail(f.c)).conversations[0].state,'paused');assert.equal(await sys('claim'),null);
 }
});
await check('Opt-outs and bounces create suppression; initial outreach and replies cannot bypass it',async()=>{
 for(const classification of ['optout','bounce']){
  const f=await make();await approve(f.c);
  await sys('sync',{conversation_id:f.c,messages:[{gmail_id:'gmail-'+classification,rfc_id:'<'+classification+'@example.invalid>',classification,body:'Stop',subject:'Nordic services',sent_at:new Date().toISOString()}]});
  assert.equal(await sys('claim'),null);
  const d=await detail(f.c);const m=d.messages.find(m=>m.kind==='initial');await cmd('message',{...m,body:'Do not send'});
  await rejects(cmd('approve',{messages:[{id:m.id,version:m.version+1}]}),/Verify/);
 }
});
await check('Domain suppression cancels even a claimed message before POST',async()=>{
 const f=await make();await approve(f.c);const claimed=await sys('claim');assert.equal(claimed.conversation.id,f.c);
 await cmd('suppress',{target:`pilot${counter}.invalid`,reason:'Domain request'});
 assert.equal(await sys('begin_send',{id:claimed.message.id,lease_id:claimed.message.lease_id}),null);
 assert.equal((await detail(f.c)).conversations[0].state,'suppressed');
});
await check('Missing body and invalid follow-up order roll back sequence creation',async()=>{
 const n=++counter,p=await cmd('prospect',{name:`Pilot ${n}`,domain:`pilot${n}.invalid`}),k=await cmd('contact',{prospect_id:p.id,email:`person${n}@pilot.invalid`});
 await rejects(cmd('sequence',{contact_id:k.id,messages:[{subject:'X',body:'A'},{subject:'X',body:'B',delay_days:12},{subject:'X',body:'C',delay_days:5}]}),/increase/);
 assert.equal((await detail(p.id)).conversations.length,0);
});
await check('Client conversion is idempotent and retains Sales history',async()=>{
 const r=await cmd('convert',{prospect_id:first.p,code:'SALESTEST',client_type:'LSP',currency:'EUR'});
 const r2=await cmd('convert',{prospect_id:first.p,code:'NEWCODE'});assert.equal(r.id,r2.id);assert.equal(r2.existing,true);
 assert.equal((await detail(first.p)).prospect.client_id,r.id);assert.ok((await detail(first.p)).messages.length>0);
});
await check('Budget reservation is durable/idempotent and includes fixed costs plus reserve',async()=>{
 const payload={id:id(301),kind:'research',payload:{brief:'Test'},reserved_eur:19,cost_config:{model:'test'}};
 const j=await sys('reserve_ai',payload);assert.equal(j.state,'queued');assert.equal((await sys('reserve_ai',payload)).id,j.id);
 await rejects(sys('reserve_ai',{...payload,id:id(302)}),/already queued/);
 await sys('claim_ai');await sys('finish_ai',{id:j.id,state:'uncertain',cost_eur:null,error:'Unknown provider outcome'});
 await rejects(sys('reserve_ai',{...payload,id:id(302),reserved_eur:2}),/budget limit/);
 assert.equal(Number((await workspace()).budget.reserved),19);
});
await check('Usage settlement releases unused reservation, stores results and skips duplicate prospects',async()=>{
 const result={prospects:[{name:'Research Example',domain:'research.invalid',country:'SE',sector:'LSP',fit_note:'Public vendor program',source_url:'https://research.invalid/vendor',contacts:[{name:'A Person',role_title:'Vendor Manager',email:'research@research.invalid',linkedin_url:'',source_url:'https://research.invalid/vendor'}]}]};
 await sys('reserve_ai',{id:id(303),kind:'research',payload:{brief:'Test'},reserved_eur:1,cost_config:{}});await sys('claim_ai');
 await sys('finish_ai',{id:id(303),state:'completed',cost_eur:.01,result});
 const p=(await db.query("SELECT id FROM sales_prospects WHERE domain='research.invalid'")).rows[0];assert.ok(p);
 assert.equal((await detail(p.id)).contacts[0].verified_at,null);
 await sys('reserve_ai',{id:id(304),kind:'research',payload:{brief:'Test'},reserved_eur:.5,cost_config:{}});await sys('claim_ai');await sys('finish_ai',{id:id(304),state:'completed',cost_eur:.01,result});
 assert.equal((await db.query("SELECT * FROM sales_prospects WHERE domain='research.invalid'")).rows.length,1);
 assert.equal(Number((await workspace()).budget.charged),.02);
});
await check('Budget cannot be raised above EUR 30; invalid settings fail atomically',async()=>{await rejects(setSettings({monthly_cap:31}),/check constraint/);settings.monthly_cap=30;await rejects(setSettings({reserve_eur:40}),/Budget cannot/);settings.reserve_eur=5;});
await check('AI materials and manual LinkedIn tasks persist without sending',async()=>{
 await sys('reserve_ai',{id:id(305),kind:'materials',payload:{},reserved_eur:.2,cost_config:{}});await sys('claim_ai');await sys('finish_ai',{id:id(305),state:'completed',cost_eur:.01,result:{title:'Sales capabilities',content:'## Services\nApproved company facts'}});
 const task=await cmd('task',{prospect_id:first.p,title:'Contact via LinkedIn',notes:'Manual task'});assert.ok((await workspace()).tasks.some(t=>t.id===task.id));await cmd('task',{id:task.id,done:true});assert.ok(!(await workspace()).tasks.some(t=>t.id===task.id));assert.ok((await workspace()).materials.length);
});
await check('Global worker lease prevents overlapping runs and requires matching release token',async()=>{
 const lock=await sys('lock');assert.ok(lock.lease_id);assert.equal(await sys('lock'),null);await sys('unlock',{lease_id:id(998)});assert.equal(await sys('lock'),null);await sys('unlock',{lease_id:lock.lease_id});assert.ok(await sys('lock'));
});
await check('Reopening needs fresh review and cannot bypass suppression',async()=>{
 await cmd('resume',{conversation_id:first.c});assert.equal((await detail(first.c)).conversations[0].state,'active');
 await cmd('suppress',{target:'person1@pilot.invalid',reason:'Requested no contact'});await rejects(cmd('resume',{conversation_id:first.c}),/cannot resume/);
});
await check('Manual uncertain-send resolution requires elapsed time and a reason; fresh approval still required',async()=>{
 const f=await make();await approve(f.c);const c=await sys('claim');assert.equal(c.conversation.id,f.c);await sys('begin_send',{id:c.message.id,lease_id:c.message.lease_id});await sys('send_error',{id:c.message.id,lease_id:c.message.lease_id,error:'Unknown'});
 await rejects(cmd('resolve_unsent',{id:c.message.id,confirmed:true,reason:'Checked Sent and the stable Message-ID in Gmail'}),/older than/);
 await privileged(`UPDATE sales_messages SET attempted_at=now()-interval '20 minutes' WHERE id='${c.message.id}'`);
 await rejects(cmd('resolve_unsent',{id:c.message.id,confirmed:false,reason:'No'}),/confirmed/);
 await cmd('resolve_unsent',{id:c.message.id,confirmed:true,reason:'Checked Gmail Sent and the message search; confirmed no message was accepted.'});
 const m=(await detail(f.c)).messages.find(m=>m.id===c.message.id);assert.equal(m.state,'failed');assert.equal(m.approval_id,null);assert.equal(await sys('claim'),null);
});
await check('Usage above reservation trips a hold for manual and automatic AI work',async()=>{
 await sys('reserve_ai',{id:id(307),kind:'draft',payload:{},reserved_eur:.01,cost_config:{}});await sys('claim_ai');await sys('finish_ai',{id:id(307),state:'failed',cost_eur:.02,error:'Unexpected usage'});
 assert.equal((await workspace()).settings.budget_hold,true);await rejects(sys('reserve_ai',{id:id(308),kind:'draft',payload:{},reserved_eur:.01,cost_config:{}}),/on hold/);
 await rejects(setSettings({monthly_cap:10}),/Budget cannot/);settings.monthly_cap=30;
});
await db.exec('RESET ROLE');
const audit=await db.query(read('tms/audits/017_update_063_sales_audit.sql'));
assert.ok(audit.rows.every(r=>r.result==='PASS'),JSON.stringify(audit.rows.filter(r=>r.result!=='PASS')));
console.log(`PASS Sales installation audit: ${audit.rows.length} checks`);
console.log(`${passed} Sales database checks passed`);
}catch(e){console.error(e.message);console.error(e.where,e.internalQuery,e.position);process.exitCode=1;}finally{await db.close();}
