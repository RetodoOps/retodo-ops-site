// Invoked by the actual Sales SQL replay, with the same database and role fixtures.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const signature=createRequire(import.meta.url)('../tms/sales-signature');
export async function signatureChecks({db,read,check,cmd,sys,rpc,workspace,privileged,make,detail}){
 const snapshot=async()=>{
  const result={};
  for(const table of ['sales_settings','sales_messages','sales_approvals','sales_conversations','sales_events'])result[table]=(await db.query(`SELECT to_jsonb(row_data) AS row FROM public.${table} row_data ORDER BY to_jsonb(row_data)::text`)).rows;
  return result;
 };
 const legacy=await make(),legacyInitial=(await detail(legacy.c)).messages.find(m=>m.kind==='initial');
 await cmd('approve',{signature_preview_version:1,messages:[{id:legacyInitial.id,version:legacyInitial.version}]});
 await check('064 migration preserves existing content, approval snapshots and sender/settings; legacy messages have no signature',async()=>{
  const before=await snapshot();await privileged(read('tms/migrations/059_sales_email_signatures.sql'));const after=await snapshot();
  const clean=structuredClone(after);for(const {row}of clean.sales_messages){assert.deepEqual(row.signature,{});delete row.signature;}
  for(const {row}of clean.sales_settings){assert.equal(row.signature_enabled,true);assert.deepEqual(row.email_signature,signature.DEFAULTS);delete row.signature_enabled;delete row.email_signature;}
  assert.deepEqual(clean,before);
 });
 const saveSettings=async patch=>cmd('settings',{...(await workspace()).settings,...patch,sending_enabled:false});
 const defaults={...signature.DEFAULTS};
 await check('064 signature settings validate URLs, shape and text, retain fixed identity and deny direct browser writes',async()=>{
  for(const change of [{website_url:'javascript:alert(1)'},{website_url:'https://retodo-ops.com@evil.invalid/'},{linkedin_url:'https://linkedin.com.evil.invalid/in/eli/'},{name:null},{version:2},{closing:'Hi\nBcc: evil'},{confidentiality:null},{position:'x'.repeat(161)},{show_logo:'yes'},{html:'<script>x</script>'}])await assert.rejects(saveSettings({email_signature:{...defaults,...change}}),/Invalid Sales signature/);
  await assert.rejects(saveSettings({email_signature:{}}),/Invalid Sales signature/);
  await assert.rejects(saveSettings({email_signature:null}),/Invalid Sales signature/);
  await assert.rejects(db.query("UPDATE sales_settings SET email_signature='{}'"),/permission denied/);
  await assert.rejects(db.query("UPDATE sales_messages SET signature='{}'"),/permission denied/);
  await saveSettings({email_signature:defaults,signature_enabled:true});
 });
 let fixture,initial,savedApproval;
 await check('064 new initial and follow-up drafts capture the configured signature in exact approval snapshots',async()=>{
  fixture=await make();const d=await detail(fixture.c);
  assert.equal(d.messages.length,3);assert.ok(d.messages.every(m=>JSON.stringify(m.signature)===JSON.stringify(d.messages[0].signature)));
  for(const m of d.messages)assert.deepEqual(m.signature,defaults);
  initial=d.messages.find(m=>m.kind==='initial');
  await assert.rejects(cmd('approve',{messages:d.messages.map(m=>({id:m.id,version:m.version}))}),/Refresh Sales and review the signature/);
  const approval=await cmd('approve',{signature_preview_version:1,messages:d.messages.map(m=>({id:m.id,version:m.version}))});
  savedApproval=(await db.query('SELECT snapshot FROM sales_approvals WHERE id=$1',[approval.id])).rows[0].snapshot;
  assert.ok(savedApproval.every(s=>s.message.signature.position===defaults.position));
 });
 const changed={...defaults,position:'Client Partnerships',show_logo:false};
 await check('064 saving or disabling the default does not alter existing messages or approvals',async()=>{
  const before=(await detail(fixture.c)).messages;await saveSettings({email_signature:changed,signature_enabled:false});
  assert.deepEqual((await detail(fixture.c)).messages,before);
  const approval=(await db.query('SELECT snapshot FROM sales_approvals WHERE id=$1',[before[0].approval_id])).rows[0].snapshot;
  assert.deepEqual(approval,savedApproval);
  const off=await make();assert.ok((await detail(off.c)).messages.every(m=>Object.keys(m.signature).length===0));
 });
 await check('064 draft edits keep snapshots by default; explicit replace/remove revokes approval and increases the version',async()=>{
  await cmd('message',{id:initial.id,version:initial.version,subject:initial.subject,body:initial.body});
  let m=(await detail(fixture.c)).messages.find(m=>m.id===initial.id);assert.deepEqual(m.signature,defaults);assert.equal(m.state,'draft');assert.equal(m.approval_id,null);assert.equal(m.version,initial.version+1);
  await cmd('approve',{signature_preview_version:1,messages:[{id:m.id,version:m.version}]});
  await cmd('message',{id:m.id,version:m.version,subject:m.subject,body:m.body,signature_mode:'current'});
  m=(await detail(fixture.c)).messages.find(m=>m.id===initial.id);assert.deepEqual(m.signature,changed);assert.equal(m.state,'draft');assert.equal(m.approval_id,null);
  await assert.rejects(cmd('approve',{signature_preview_version:1,messages:[{id:m.id,version:initial.version}]}),/changed/);
  await assert.rejects(cmd('message',{id:m.id,version:m.version,subject:m.subject,body:m.body,signature_mode:'anything'}),/Choose whether/);
  await cmd('message',{id:m.id,version:m.version,subject:m.subject,body:m.body,signature_mode:'none'});
  assert.deepEqual((await detail(fixture.c)).messages.find(m=>m.id===initial.id).signature,{});
 });
 await check('064 per-message choices override the default and replies capture their own editable signature',async()=>{
  const p=await cmd('prospect',{name:'Signature Choices',domain:'signature-choices.invalid'});
  const k=await cmd('contact',{prospect_id:p.id,name:'Recipient',email:'choices@example.invalid',source_url:'https://source.invalid',outreach_basis:'Controlled signature test',verified:true});
  const c=await cmd('sequence',{contact_id:k.id,messages:[{subject:'Signature choices',body:'Body only',include_signature:true},{subject:'Signature choices',body:'Manually signed\nEli',delay_days:5,include_signature:false}]});
  let d=await detail(c.id);assert.deepEqual(d.messages.find(m=>m.kind==='initial').signature,changed);assert.deepEqual(d.messages.find(m=>m.kind==='followup').signature,{});
  await privileged(`UPDATE sales_conversations SET thread_id='signature-reply-thread',state='replied' WHERE id='${c.id}'`);
  const noSig=await cmd('reply',{conversation_id:c.id,subject:'Signature choices',body:'Reply without automatic signature'});
  const withSig=await cmd('reply',{conversation_id:c.id,subject:'Signature choices',body:'Reply with signature',include_signature:true});
  d=await detail(c.id);assert.deepEqual(d.messages.find(m=>m.id===noSig.id).signature,{});assert.deepEqual(d.messages.find(m=>m.id===withSig.id).signature,changed);
 });
 await check('064 pre-send verification accepts unchanged legacy approvals without a signature key',async()=>{
  await db.exec('BEGIN');try{
   await privileged(`UPDATE sales_conversations SET state='closed';UPDATE sales_conversations SET state='active' WHERE id='${legacy.c}';UPDATE sales_settings SET sending_enabled=true,daily_limit=30`);
   await sys('mailbox',{ok:true});const claim=await sys('claim');assert.equal(claim.message.id,legacyInitial.id);assert.deepEqual(claim.message.signature,{});
   assert.ok(await sys('begin_send',{id:claim.message.id,lease_id:claim.message.lease_id}));
  }finally{await db.exec('ROLLBACK');}
 });
 await saveSettings({email_signature:defaults,signature_enabled:true});
 await check('064 pre-send verification rejects a signature different from the approval snapshot, even at the same version',async()=>{
  await db.exec('BEGIN');try{
   await privileged("UPDATE sales_conversations SET state='closed'");
   const f=await make(),m=(await detail(f.c)).messages.find(m=>m.kind==='initial');await cmd('approve',{signature_preview_version:1,messages:[{id:m.id,version:m.version}]});
   await sys('mailbox',{ok:true});await cmd('settings',{...(await workspace()).settings,sending_enabled:true,daily_limit:30});
   const claim=await sys('claim');assert.equal(claim.message.id,m.id);
   await db.exec('SAVEPOINT signature_edit');
   await assert.rejects(cmd('message',{id:m.id,version:m.version,subject:m.subject,body:m.body,signature_mode:'none'}),/cannot be edited/);
   await db.exec('ROLLBACK TO SAVEPOINT signature_edit');
   await privileged(`UPDATE sales_messages SET signature=jsonb_set(signature,'{position}','"Unreviewed change"') WHERE id='${m.id}'`);
   await db.exec("SAVEPOINT signature_send;RESET ROLE;SET ROLE service_role;SET request.jwt.claim.role='service_role'");
   await assert.rejects(rpc('sales_system_063',['begin_send',{id:m.id,lease_id:claim.message.lease_id}]),/Approved signature does not match/);
   await db.exec('ROLLBACK TO SAVEPOINT signature_send');
  }finally{await db.exec('ROLLBACK');}
 });
 await check('064 migration can be reapplied without changing saved defaults, messages or approvals',async()=>{
  const before=await snapshot();await privileged(read('tms/migrations/059_sales_email_signatures.sql'));assert.deepEqual(await snapshot(),before);
  assert.deepEqual((await workspace()).settings.email_signature,defaults);
 });
}
