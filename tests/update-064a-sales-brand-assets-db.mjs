import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const signature=createRequire(import.meta.url)('../tms/sales-signature');
export async function brandAssetChecks({db,read,check,cmd,sys,workspace,privileged,make,detail}){
 const legacy=await make();let messages=(await detail(legacy.c)).messages;
 const initial=messages.find(m=>m.kind==='initial'),follow=messages.find(m=>m.kind==='followup');
 await cmd('approve',{signature_preview_version:1,messages:[{id:initial.id,version:initial.version}]});
 const save=async patch=>cmd('settings',{...(await workspace()).settings,...patch,sending_enabled:false});
 const stored=async()=>({messages:(await db.query('SELECT to_jsonb(m) row FROM sales_messages m ORDER BY id')).rows,approvals:(await db.query('SELECT to_jsonb(a) row FROM sales_approvals a ORDER BY id')).rows});
 await check('064A migration upgrades only the current template; preserves custom text, toggles and all message/approval snapshots',async()=>{
  const custom={...signature.LEGACY_DEFAULTS,position:'Existing custom position',show_logo:false};await save({email_signature:custom,signature_enabled:false});
  const before=await stored();await privileged(read('tms/migrations/060_sales_signature_brand_assets.sql'));
  assert.deepEqual(await stored(),before);const settings=(await workspace()).settings;
  assert.deepEqual(settings.email_signature,{...custom,version:2});assert.equal(settings.signature_enabled,false);
  await save({email_signature:signature.DEFAULTS,signature_enabled:true});
 });
 let fresh;
 await check('064A old tabs cannot approve the new logo; current preview can approve mixed legacy/new signatures',async()=>{
  const fixture=await make();fresh=(await detail(fixture.c)).messages.find(m=>m.kind==='initial');assert.deepEqual(fresh.signature,signature.DEFAULTS);
  const selected=[{id:fresh.id,version:fresh.version},{id:follow.id,version:follow.version}];
  for(const marker of [undefined,1,3])await assert.rejects(cmd('approve',{signature_preview_version:marker,messages:selected}),/Refresh Sales and review/);
  await cmd('approve',{signature_preview_version:2,messages:selected});
  assert.equal((await detail(fixture.c)).messages.find(m=>m.id===fresh.id).state,'approved');
 });
 await check('064A choosing current signature on an older draft captures new branding and requires reapproval',async()=>{
  await cmd('message',{id:follow.id,version:follow.version,subject:follow.subject,body:follow.body,signature_mode:'current'});
  const edited=(await detail(legacy.c)).messages.find(m=>m.id===follow.id);assert.deepEqual(edited.signature,signature.DEFAULTS);
  assert.equal(edited.state,'draft');assert.equal(edited.approval_id,null);assert.equal(edited.version,follow.version+1);
 });
 await check('064A previously approved renderer 1 messages remain valid for the worker',async()=>{
  await db.exec('BEGIN');try{
   await privileged(`UPDATE sales_conversations SET state='closed';UPDATE sales_conversations SET state='active' WHERE id='${legacy.c}';UPDATE sales_settings SET sending_enabled=true,daily_limit=30`);
   await sys('mailbox',{ok:true});const claim=await sys('claim');assert.equal(claim.message.id,initial.id);assert.equal(claim.message.signature.version,1);
   assert.ok(await sys('begin_send',{id:initial.id,lease_id:claim.message.lease_id}));
  }finally{await db.exec('ROLLBACK');}
 });
 await check('064A migration reapplication preserves the corrected defaults and all saved messages',async()=>{
  const before=await stored(),settings=(await workspace()).settings;await privileged(read('tms/migrations/060_sales_signature_brand_assets.sql'));
  assert.deepEqual(await stored(),before);assert.deepEqual((await workspace()).settings,settings);
 });
}
