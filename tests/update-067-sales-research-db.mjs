import assert from 'node:assert/strict';

export async function researchLearningChecks({db,read,check,rpc,privileged}){
 const sys=async(action,data={})=>{
  await db.exec("RESET ROLE;SET ROLE service_role;SET request.jwt.claim.role='service_role'");
  try{return await rpc('sales_system_067',[action,data]);}
  finally{await db.exec("RESET ROLE;SET ROLE authenticated;SET request.jwt.claim.role='authenticated'");}
 };
 const beforeConversations=Number((await db.query('SELECT count(*) n FROM sales_conversations')).rows[0].n);
 await privileged(read('tms/migrations/063_sales_prospect_learning.sql'));
 await check('067 migration installs the curated profile, keeps automation off and seeds 26 canonical pipeline companies',async()=>{
  const settings=(await db.query('SELECT research_enabled,research_profile FROM sales_settings WHERE id')).rows[0];
  assert.equal(settings.research_enabled,false);assert.equal(settings.research_profile.version,1);
  assert.match(settings.research_profile.ideal_buyer,/multi-language LSP/);assert.ok(settings.research_profile.exclude.includes('Retodo Ops and retodo-ops.com'));
  const expected=['acclaro.com','acolad.com','argosmultilingual.com','aspena.com','cetra.com','cpsl.com','ecinnovations.com','global-lingo.com','globaltextware.nl','iolar.com','languageline.com','languagewire.com','lionbridge.com','parentyreitmeier.com','questel.com','rws.com','seprotec.com','side.inc','talkfinance.biz','thebigword.com','transperfect.com','translate.one','vistatec.com','welocalize.com','zelenka-translations.com','t-works.eu'];
  const rows=(await db.query('SELECT domain,stage FROM sales_prospects WHERE domain=ANY($1) ORDER BY domain',[expected])).rows;
  assert.equal(rows.length,26);assert.ok(rows.every(x=>x.stage==='qualified'));
  assert.equal(Number((await db.query('SELECT count(*) n FROM sales_conversations')).rows[0].n),beforeConversations);
 });
 await check('067 retains only public role contacts and requires human verification',async()=>{
  const rows=(await db.query("SELECT email,verified_at,outreach_basis FROM sales_contacts WHERE email IN('resourcemanagement@ecinnovations.com','cv@seprotec.com','dataforce.sourcing@transperfect.com','vendors@zelenka.cz') ORDER BY email")).rows;
  assert.equal(rows.length,4);assert.ok(rows.every(x=>x.verified_at===null&&/Verify/.test(x.outreach_basis)));
 });
 await check('067 research context contains the profile and known-company exclusions but no historical personal emails',async()=>{
  const context=await sys('research_context');assert.equal(context.research_profile.version,1);
  assert.ok(context.existing_prospects.some(x=>x.domain==='acclaro.com'));
  assert.doesNotMatch(JSON.stringify(context),/@(?!invalid)/);
 });
 await check('067 records returned, validation, duplicate, suppression, conflict and import outcomes truthfully',async()=>{
  const job='00000000-0000-0000-0000-000000000367';
  await privileged("INSERT INTO sales_suppressions(target,reason) VALUES('suppressed.invalid','Test suppression') ON CONFLICT DO NOTHING");
  await privileged(`INSERT INTO sales_ai_jobs(id,kind,payload,state,reserved_eur,cost_config) VALUES('${job}','research','{}','running',0.5,'{}')`);
  const prospects=[
   {name:'Acclaro',domain:'acclaro.com',country:'US',sector:'LSP',fit_note:'Existing',source_url:'https://www.acclaro.com/company/careers',contacts:[]},
   {name:'Suppressed Buyer',domain:'suppressed.invalid',country:'SE',sector:'LSP',fit_note:'Suppressed',source_url:'https://suppressed.invalid/vendors',contacts:[]},
   {name:'Fresh Buyer',domain:'fresh-buyer.invalid',country:'SE',sector:'LSP',fit_note:'Official vendor route',source_url:'https://fresh-buyer.invalid/vendors',contacts:[]},
  ];
  await sys('finish_ai',{id:job,state:'completed',cost_eur:0.02,provider_id:'fixture',result:{prospects,notes:'Fixture',diagnostics:{returned:4,accepted:3,validation_rejected:1}}});
  const result=(await db.query('SELECT result FROM sales_ai_jobs WHERE id=$1',[job])).rows[0].result;
  assert.deepEqual(result.outcomes,{returned:4,accepted:3,validation_rejected:1,duplicates:1,suppressions:1,conflicts:0,imported:1});
  assert.equal(result.imported,1);assert.equal(Number((await db.query("SELECT count(*) n FROM sales_prospects WHERE domain='fresh-buyer.invalid'")).rows[0].n),1);
 });
 await check('067 server dispatcher is service-only and migration reapplication does not duplicate candidates or contacts',async()=>{
  await assert.rejects(rpc('sales_system_067',['research_context',{}]),/permission denied/);
  const before={prospects:Number((await db.query('SELECT count(*) n FROM sales_prospects')).rows[0].n),contacts:Number((await db.query('SELECT count(*) n FROM sales_contacts')).rows[0].n),events:Number((await db.query("SELECT count(*) n FROM sales_events WHERE event='prospect_learning_set_installed'")).rows[0].n)};
  await privileged(read('tms/migrations/063_sales_prospect_learning.sql'));
  const after={prospects:Number((await db.query('SELECT count(*) n FROM sales_prospects')).rows[0].n),contacts:Number((await db.query('SELECT count(*) n FROM sales_contacts')).rows[0].n),events:Number((await db.query("SELECT count(*) n FROM sales_events WHERE event='prospect_learning_set_installed'")).rows[0].n)};
  assert.deepEqual(after,before);
 });
}
