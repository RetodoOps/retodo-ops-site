import assert from 'node:assert/strict';

export async function coldProspectChecks({db,read,check,privileged}){
 const beforeConversations=Number((await db.query('SELECT count(*) n FROM sales_conversations')).rows[0].n);
 await privileged(`INSERT INTO sales_prospects(name,domain,stage,fit_note,notes)
  VALUES('Jensen Localization','jensen-localization.com','qualified','Seeks freelance translators for Nordic languages','Former Retodo client recorded as Jensen Localization BV and Jensen Localization SL. Latest supplied Plunet activity: December 2020.')
  ON CONFLICT(domain) DO UPDATE SET notes=excluded.notes`);
 await privileged(read('tms/migrations/064_sales_cold_prospect_guard.sql'));
 await check('068 makes confidential history ranking-only and keeps automatic research off',async()=>{
  const settings=(await db.query('SELECT research_enabled,research_profile FROM sales_settings WHERE id')).rows[0];
  assert.equal(settings.research_enabled,false);assert.equal(settings.research_profile.version,2);assert.equal(settings.research_profile.cold_outreach_only,true);
  assert.match(settings.research_profile.confidential_history_rule,/another business/);assert.match(settings.research_profile.confidential_history_rule,/Never expose/);
  assert.ok(settings.research_profile.required_signals.some(x=>/Nordic-language demand/.test(x)));
 });
 await check('068 removes relationship evidence from seeded fit text and Jensen notes',async()=>{
  const seeded=['acclaro.com','acolad.com','argosmultilingual.com','aspena.com','cetra.com','cpsl.com','ecinnovations.com','global-lingo.com','globaltextware.nl','iolar.com','languageline.com','languagewire.com','lionbridge.com','parentyreitmeier.com','questel.com','rws.com','seprotec.com','side.inc','talkfinance.biz','thebigword.com','transperfect.com','translate.one','vistatec.com','welocalize.com','zelenka-translations.com','t-works.eu'];
  const rows=(await db.query('SELECT fit_note,notes FROM sales_prospects WHERE domain=ANY($1)',[seeded])).rows;
  assert.equal(rows.length,26);assert.doesNotMatch(JSON.stringify(rows),/supplied prospect|purchase history|historical order|former retodo|former client|plunet/i);
  const jensen=(await db.query("SELECT notes FROM sales_prospects WHERE domain='jensen-localization.com'")).rows[0];
  assert.match(jensen.notes,/Cold prospect/);assert.doesNotMatch(jensen.notes,/BV|SL|Plunet|former/i);
  assert.equal(Number((await db.query('SELECT count(*) n FROM sales_conversations')).rows[0].n),beforeConversations);
 });
 await check('068 reapplication is idempotent and records one guard event',async()=>{
  await privileged(read('tms/migrations/064_sales_cold_prospect_guard.sql'));
  assert.equal(Number((await db.query("SELECT count(*) n FROM sales_events WHERE event='cold_prospect_guard_installed'")).rows[0].n),1);
  const settings=(await db.query('SELECT research_profile FROM sales_settings WHERE id')).rows[0];assert.equal(settings.research_profile.version,2);
 });
}
