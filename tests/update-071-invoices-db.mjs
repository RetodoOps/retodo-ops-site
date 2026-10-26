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
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT current_user::text $$;
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
console.log('PASS invoice migration on repository schema');
await db.exec(read('tms/migrations/055_client_scoop_invoicing.sql'));
console.log('PASS invoice migration reapplication');

const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const result=async(sql,args=[]) => (await db.query(sql,args)).rows[0]?.result;
const rpc=async(name,args=[])=>result(`SELECT ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args);
let passed=0;const check=async(name,fn)=>{await fn();passed++;console.log('PASS',name)};
await db.exec(`INSERT INTO clients(id,name,default_currency,default_payment_days) VALUES('${id(10)}','Client A','EUR',30),('${id(11)}','Client B','EUR',60);
INSERT INTO client_billing_entities(id,client_id,name,legal_name,address_line_1,city,country_code,is_default) VALUES('${id(12)}','${id(10)}','Main','Client A Ltd','One Street','Sofia','BG',true);
INSERT INTO projects(id,project_number,display_name,client_id,currency,po_number) VALUES('${id(20)}','P1','Project one','${id(10)}','EUR','CLIENT-PO1'),('${id(21)}','P2','Project two','${id(10)}','EUR','CLIENT-PO2'),('${id(22)}','P3','Project three','${id(11)}','EUR','CLIENT-OTHER');
INSERT INTO project_scoops(id,project_id,scoop_number,source_language,target_language,price,deadline,status,status_manual) VALUES
('${id(30)}','${id(20)}','260905_TEST_NB_NOREF-S02','English','Bulgarian',100,now()+interval '3 days','Approved',true),
('${id(31)}','${id(20)}','P1-S02','English','German',200,now()+interval '3 days','Approved',true),
('${id(32)}','${id(21)}','P2-S01','English','French',300,now()+interval '3 days','Approved',true),
('${id(33)}','${id(22)}','P3-S01','English','Italian',100,now()+interval '3 days','Approved',true),
('${id(34)}','${id(21)}','P2-S02','English','Spanish',400,now()+interval '3 days','Assign',true);
SET ROLE authenticated;`);
const base={client_id:id(10),billing_entity_id:id(12),currency:'EUR',issue_date:'2026-09-27',tax_rate:0,tax_note:'Test tax basis',lines:[{scoop_id:id(30),description:'First Scoop',amount:100},{scoop_id:id(32),description:'Second Project Scoop',amount:300}]};
let invoice,detail;
await check('Reproduces manual-first unassigned sc error before any Scoop save in this session',async()=>{
 const before=await result('SELECT count(*)::int result FROM client_invoices');
 await assert.rejects(rpc('invoice_save_061',[{...base,lines:[{description:'Manual first',amount:330}]},null,null]),/record "sc" is not assigned yet/);
 assert.equal(await result('SELECT count(*)::int result FROM client_invoices'),before);
});
await db.exec('RESET ROLE');
await db.exec(read('tms/migrations/066_invoice_manual_draft_fix.sql'));
await db.exec('SET ROLE authenticated');
await check('Queue gates individual approved Scoops and searches client PO',async()=>{const d=await rpc('invoice_workspace_061',[id(10),'',0,50,null]);assert.equal(d.total_count,3);assert.equal((await rpc('invoice_workspace_061',[id(10),'CLIENT-PO2',0,50,null])).total_count,1);});
await check('Draft combines Scoops across Projects; client terms set due date',async()=>{invoice=await rpc('invoice_save_061',[base,null,null]);detail=await rpc('invoice_get_061',[invoice]);assert.equal(detail.lines.length,2);assert.equal(Number(detail.invoice.total),400);assert.equal(detail.invoice.due_date,'2026-10-27');assert.equal(detail.invoice.payment_terms_days,30);assert.equal((await rpc('invoice_workspace_061',[id(10),'',0,50,null])).total_count,1);});
await check('Reservations block duplicate billing with rollback',async()=>{await assert.rejects(rpc('invoice_save_061',[base,null,null]),/already reserved/);assert.equal((await rpc('invoice_get_061',[invoice])).lines.length,2);});
await check('Different-client Scoop cannot enter invoice',async()=>{await assert.rejects(rpc('invoice_save_061',[{...base,lines:[{scoop_id:id(33),description:'Wrong',amount:100}]},null,null]),/belonging/);});
await check('Corrections need a reason; stale revision rejected',async()=>{await assert.rejects(rpc('invoice_save_061',[{...base,lines:[{...base.lines[0],amount:90}]},invoice,1]),/reason/);await assert.rejects(rpc('invoice_save_061',[base,invoice,0]),/another window/);});
await check('Edit amount, remove Scoop, add manual row and later add by PO',async()=>{await rpc('invoice_save_061',[{...base,lines:[{...base.lines[0],amount:90,adjustment_reason:'Agreed discount'},{description:'Extra service',amount:10}]},invoice,1]);detail=await rpc('invoice_get_061',[invoice]);assert.equal(detail.invoice.revision,2);assert.equal(Number(detail.invoice.total),100);assert.equal((await rpc('invoice_workspace_061',[id(10),'CLIENT-PO2',0,50,null])).total_count,1);await rpc('invoice_save_061',[base,invoice,2]);detail=await rpc('invoice_get_061',[invoice]);assert.equal(detail.invoice.revision,3);});
await check('Ordinary SQL cannot mutate invoices, rows or receipts',async()=>{for(const table of ['client_invoices','client_invoice_lines','payments'])await assert.rejects(db.exec(`DELETE FROM ${table}`),/permission denied/);});
await check('Incomplete issuer settings block official issue',async()=>{await assert.rejects(rpc('invoice_issue_061',[invoice,3]),/Complete issuer/);await rpc('invoice_settings_save_061',[{legal_name:'Test Issuer',registration_number:'TEST',address:'Test Street',iban:'TEST-IBAN'},101]);});
await check('Changed client terms require resave, then due date updates',async()=>{await db.exec(`RESET ROLE; UPDATE clients SET default_payment_days=45 WHERE id='${id(10)}'; SET ROLE authenticated`);await assert.rejects(rpc('invoice_issue_061',[invoice,3]),/terms changed/);await rpc('invoice_save_061',[base,invoice,3]);detail=await rpc('invoice_get_061',[invoice]);assert.equal(detail.invoice.due_date,'2026-11-11');});
await check('Changed source price blocks issue until reviewed',async()=>{await db.exec(`RESET ROLE; UPDATE project_scoops SET price=110 WHERE id='${id(30)}'; SET ROLE authenticated`);await assert.rejects(rpc('invoice_issue_061',[invoice,4]),/Source price/);await db.exec(`RESET ROLE; UPDATE project_scoops SET price=100 WHERE id='${id(30)}'; SET ROLE authenticated`);});
await check('PM can save drafts but cannot issue or change numbering',async()=>{await db.exec(`RESET ROLE;UPDATE profiles SET role='pm' WHERE id='${id(1)}';SET ROLE authenticated`);await assert.rejects(rpc('invoice_issue_061',[invoice,4]),/access denied/);await assert.rejects(rpc('invoice_settings_save_061',[{},102]),/access denied/);await db.exec(`RESET ROLE;UPDATE profiles SET role='admin' WHERE id='${id(1)}';SET ROLE authenticated`);});
await check('Issue freezes source, issuer and number; next sequence advances',async()=>{detail=await rpc('invoice_issue_061',[invoice,4]);assert.equal(detail.invoice.invoice_number,'0000000101');assert.equal(detail.invoice.status,'Issued');assert.equal(detail.invoice.issuer_snapshot.legal_name,'Test Issuer');assert.equal(detail.invoice.billing_snapshot.legal_name,'Client A Ltd');assert.equal((await rpc('invoice_workspace_061')).settings.next_number,102);await assert.rejects(rpc('invoice_save_061',[base,invoice,5]),/Only Draft/);});
await check('Payment partial/full, duplicate, wrong currency and overpayment guards',async()=>{detail=await rpc('invoice_record_payment_061',[invoice,100,'2026-09-27','BANK-1','EUR']);assert.equal(detail.invoice.status,'Partially Paid');await assert.rejects(rpc('invoice_record_payment_061',[invoice,100,'2026-09-27','BANK-1','EUR']),/already recorded/);await assert.rejects(rpc('invoice_record_payment_061',[invoice,1,'2026-09-27','BANK-2','USD']),/matching currency/);await assert.rejects(rpc('invoice_record_payment_061',[invoice,301,'2026-09-27','BANK-2','EUR']),/remaining balance/);detail=await rpc('invoice_record_payment_061',[invoice,300,'2026-09-27','BANK-2','EUR']);assert.equal(detail.invoice.status,'Paid');assert.equal(detail.payments.length,2);});
await check('Cancellation releases reservation; manual numbering advances following number',async()=>{const payload={...base,proposed_number:'150',lines:[{scoop_id:id(31),description:'Last Scoop',amount:200}]};const d=await rpc('invoice_save_061',[payload,null,null]);await rpc('invoice_cancel_draft_061',[d,1]);const other=await rpc('invoice_save_061',[payload,null,null]);const issued=await rpc('invoice_issue_061',[other,1]);assert.equal(issued.invoice.invoice_number,'0000000150');assert.equal((await rpc('invoice_workspace_061')).settings.next_number,151);});
await check('Issued row/header facts remain immutable even through owner SQL',async()=>{await db.exec('RESET ROLE');await assert.rejects(db.exec(`UPDATE client_invoice_lines SET amount=1 WHERE invoice_id='${invoice}'`),/cannot be changed/);await assert.rejects(db.exec(`UPDATE client_invoices SET due_date=CURRENT_DATE WHERE id='${invoice}'`),/frozen/);assert.equal((await db.query(`SELECT financial_status FROM projects WHERE id='${id(20)}'`)).rows[0].financial_status,'Partially Paid');await db.exec('SET ROLE authenticated');});
await db.exec('RESET ROLE');
await db.exec(read('tms/migrations/056_reports_selection_invoice_revisions_search.sql'));
await db.exec(read('tms/migrations/056_reports_selection_invoice_revisions_search.sql'));
console.log('PASS 056 migration and reapplication');
// Simulate SQL-editor CRLF normalization of the original 055 trigger source.
const originalGuard=read('tms/migrations/055_client_scoop_invoicing.sql').split('CREATE OR REPLACE FUNCTION public.invoice_immutable_061()')[1].split('DROP TRIGGER')[0];
await db.exec(('CREATE OR REPLACE FUNCTION public.invoice_immutable_061()'+originalGuard).replace(/\n/g,'\r\n'));
await db.exec(read('tms/migrations/056_reports_selection_invoice_revisions_search.sql'));
await db.exec('SET ROLE authenticated');
await check('Reproduces reported issued-to-Draft error when 056 misses CRLF function body',async()=>{const d=await rpc('invoice_get_061',[invoice]);await assert.rejects(rpc('invoice_revise_062',[invoice,d.invoice.revision,{...base,proposed_number:d.invoice.invoice_number},'Reproduce']),/An issued invoice cannot return to Draft or Cancelled/);});
await db.exec('RESET ROLE');
await db.exec(read('tms/migrations/061_standalone_invoice_prerequisites.sql'));
await db.exec(read('tms/migrations/061_standalone_invoice_prerequisites.sql'));
console.log('PASS 061 migration and reapplication repair missed 056 trigger patch');

// Replacing the function invalidates its cached plans. A manual row must work
// before any Scoop row, not merely after a Scoop has warmed the session cache.
await db.exec(read('tms/migrations/066_invoice_manual_draft_fix.sql'));
await db.exec('SET ROLE authenticated');
await check('Cold function saves three manual rows, updates draft, and leaves all source links empty',async()=>{
 const payload={...base,lines:[{description:'Manual A',amount:330},{description:'Manual B',amount:1100},{description:'Manual C',amount:800}]};
 const n=await rpc('invoice_save_061',[payload,null,null]);
 let d=await rpc('invoice_get_061',[n]);assert.equal(d.invoice.total,2230);assert.equal(d.lines.length,3);
 assert.ok(d.lines.every(l=>l.project_id===null&&l.scoop_id===null&&Object.keys(l.source_snapshot).length===0));
 await rpc('invoice_save_061',[{...payload,lines:[...payload.lines,{description:'Extra',amount:10}]},n,d.invoice.revision]);
 d=await rpc('invoice_get_061',[n]);assert.equal(d.invoice.total,2240);assert.equal(d.invoice.revision,2);
 await assert.rejects(rpc('invoice_save_061',[payload,n,1]),/another window/);
 await rpc('invoice_delete_064',[n,d.invoice.revision,d.invoice.draft_reference,false]);
});
await check('Manual rows before and after a Scoop never inherit its Project or source snapshot',async()=>{
 await db.exec(`RESET ROLE;UPDATE project_scoops SET status='Approved',status_manual=true WHERE id='${id(34)}';SET ROLE authenticated`);
 const payload={...base,lines:[{description:'Before',amount:10},{scoop_id:id(34),description:'Scoop',amount:400},{description:'After',amount:20}]};
 const n=await rpc('invoice_save_061',[payload,null,null]);const d=await rpc('invoice_get_061',[n]);
 assert.equal(d.invoice.total,430);
 for(const l of d.lines){if(l.scoop_id){assert.equal(l.project_id,id(21));assert.equal(l.scoop_id,id(34));}else{assert.equal(l.project_id,null);assert.deepEqual(l.source_snapshot,{});}}
 await db.exec('RESET ROLE');assert.equal(await result('SELECT count(*)::int result FROM invoice_scoop_allocations_061 WHERE invoice_id=$1',[n]),1);await db.exec('SET ROLE authenticated');
 await rpc('invoice_delete_064',[n,d.invoice.revision,d.invoice.draft_reference,false]);
});

await db.exec('SET ROLE authenticated');
await check('Issued and paid Scoops display derived finance status without losing operational approval',async()=>{const rows=await db.query('SELECT status,financial_status FROM project_scoops WHERE id=ANY($1)',[[id(30),id(32)]]);assert.ok(rows.rows.every(s=>s.status==='Approved'&&s.financial_status==='Paid'));const r=await rpc('tms_report_061',['projects',{statuses:['Paid']},0,50,'name',false]);assert.equal(r.total_count,2);});
await check('Exact Scoop search returns the Scoop itself and escapes literal underscores',async()=>{const hits=await rpc('tms_search_062',['260905_TEST_NB_NOREF-S02',30]);assert.equal(hits[0].kind,'Scoop');assert.match(hits[0].href,/&scoop=/);assert.match(hits[0].meta,/Paid/);assert.equal((await rpc('tms_search_062',['not_found_thing',30])).length,0);});
await check('Bulk Scoop update is atomic, bounded and financial statuses are not manual options',async()=>{assert.equal(await rpc('report_bulk_status_062',['projects',[id(34)],'Approved']),1);await assert.rejects(rpc('report_bulk_status_062',['projects',[id(34),id(9999)],'Waiting']),/no longer exist/);assert.equal((await db.query('SELECT status FROM project_scoops WHERE id=$1',[id(34)])).rows[0].status,'Approved');await assert.rejects(rpc('report_bulk_status_062',['projects',[id(34)],'Paid']),/operational status/);await assert.rejects(rpc('report_bulk_status_062',['projects',[id(30)],'Waiting']),/Invoiced/);});
await check('Admin can revise an issued paid invoice; old facts and receipts remain available',async()=>{let d=await rpc('invoice_get_061',[invoice]);const payload={...base,proposed_number:d.invoice.invoice_number,lines:[...base.lines,{description:'Additional review',amount:50}]};d=await rpc('invoice_revise_062',[invoice,d.invoice.revision,payload,'Added agreed review']);assert.equal(Number(d.invoice.total),450);assert.equal(d.invoice.status,'Partially Paid');assert.equal(d.payments.length,2);const versions=await db.query('SELECT snapshot,reason FROM invoice_revisions_062 WHERE invoice_id=$1',[invoice]);assert.equal(versions.rows[0].snapshot.invoice.total,400);assert.equal(versions.rows[0].reason,'Added agreed review');assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(30)])).rows[0].financial_status,'Invoiced');await assert.rejects(rpc('invoice_revise_062',[invoice,d.invoice.revision,{...base,lines:[{description:'Too low',amount:1}]},'Bad total']),/recorded payments/);assert.equal((await rpc('invoice_get_061',[invoice])).invoice.total,450);await assert.rejects(rpc('invoice_revise_062',[invoice,d.invoice.revision-1,payload,'Stale']),/Reopen/);await rpc('invoice_record_payment_061',[invoice,50,'2026-09-27','BANK-3','EUR']);assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(30)])).rows[0].financial_status,'Paid');});
await check('Issued revision can remove or add Scoops and preserves duplicate billing checks',async()=>{const d=await rpc('invoice_get_061',[invoice]);const payload={...base,proposed_number:d.invoice.invoice_number,lines:[base.lines[0],{scoop_id:id(34),description:'New Scoop',amount:400}]};await rpc('invoice_revise_062',[invoice,d.invoice.revision,payload,'Changed scope']);assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(32)])).rows[0].financial_status,'Not Invoiced');assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(34)])).rows[0].financial_status,'Invoiced');const now=await rpc('invoice_get_061',[invoice]);await assert.rejects(rpc('invoice_revise_062',[invoice,now.invoice.revision,{...payload,lines:[...payload.lines,{scoop_id:id(31),description:'Already billed',amount:200}]},'Duplicate']),/already reserved/);});
await check('Derived financial state cannot be forged and revised numbers cannot be reused',async()=>{await assert.rejects(db.exec(`UPDATE project_scoops SET financial_status='Paid' WHERE id='${id(34)}'`),/managed by invoices/);let d=await rpc('invoice_get_061',[invoice]);const payload={...d.invoice,proposed_number:'160',lines:d.lines};d=await rpc('invoice_revise_062',[invoice,d.invoice.revision,payload,'Corrected number']);assert.equal(d.invoice.invoice_number,'0000000160');const n=await rpc('invoice_save_061',[{...base,proposed_number:'101',lines:[{description:'Manual test',amount:10}]},null,null]);await assert.rejects(rpc('invoice_issue_061',[n,1]),/already belongs/);});
await check('Bulk Job statuses and permission checks use guarded RPCs',async()=>{await db.exec(`RESET ROLE;INSERT INTO specializations(id,name) VALUES('${id(91)}','Test Domain');INSERT INTO project_specializations(project_id,specialization_id) VALUES('${id(21)}','${id(91)}');INSERT INTO project_jobs(id,project_id,project_scoop_id,job_number,service_type,source_language,target_language) VALUES('${id(90)}','${id(21)}','${id(32)}','TEST-J1','Translation','English','French');SET ROLE authenticated`);assert.equal(await rpc('report_bulk_status_062',['jobs',[id(90)],'Cancelled']),1);await db.exec(`RESET ROLE;UPDATE profiles SET role='pm' WHERE id='${id(1)}';SET ROLE authenticated`);await assert.rejects(rpc('invoice_revise_062',[invoice,1,base,'Denied']),/access denied/);await db.exec(`RESET ROLE;UPDATE profiles SET role='qa' WHERE id='${id(1)}';SET ROLE authenticated`);await assert.rejects(rpc('report_bulk_status_062',['jobs',[id(90)],'Approved']),/access denied/);await db.exec(`RESET ROLE;UPDATE profiles SET role='admin' WHERE id='${id(1)}';SET ROLE authenticated`);});

await check('Partial payment accepts omitted reference; future, bad amount, stale and overpayment rejected',async()=>{
 let d=await rpc('invoice_get_061',[invoice]);const revision=d.invoice.revision;
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,revision,'partial',1,null,null,id(400)]),/date/);
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,revision,'partial',1,'2099-01-01',null,id(400)]),/future/);
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,revision,'partial',-1,'2026-09-27',null,id(400)]),/positive/);
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,revision,'partial',50.01,'2026-09-27',null,id(400)]),/remaining/);
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,revision-1,'full',null,'2026-09-27',null,id(400)]),/changed/);
 d=await rpc('invoice_receive_payment_064',[invoice,revision,'partial',10.4,'2026-09-27',null,id(400)]);assert.equal(d.invoice.status,'Partially Paid');assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(30)])).rows[0].financial_status,'Invoiced');
 const again=await rpc('invoice_receive_payment_064',[invoice,revision,'partial',10.4,'2026-09-27',null,id(400)]);assert.equal(again.payments.length,d.payments.length);
});
await check('Full payment derives exact remaining 39.60 server-side and retry cannot duplicate receipt',async()=>{
 let d=await rpc('invoice_get_061',[invoice]);const rev=d.invoice.revision,count=d.payments.length;
 d=await rpc('invoice_receive_payment_064',[invoice,rev,'full',999999,'2026-09-27',null,id(401)]);assert.equal(d.invoice.status,'Paid');assert.equal(d.payments.length,count+1);assert.ok(d.payments.some(p=>Number(p.amount)===39.6));assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(34)])).rows[0].financial_status,'Paid');
 assert.equal((await rpc('invoice_receive_payment_064',[invoice,rev,'full',999999,'2026-09-27',null,id(401)])).payments.length,count+1);
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,rev,'full',null,'2026-09-26',null,id(401)]),/different details/);
});
await check('Deletion is admin-only, revision guarded, confirmation guarded and requires receipt acknowledgment',async()=>{
 const d=await rpc('invoice_get_061',[invoice]);await assert.rejects(rpc('invoice_delete_064',[invoice,d.invoice.revision,'wrong',true]),/exact invoice/);
 await assert.rejects(rpc('invoice_delete_064',[invoice,d.invoice.revision-1,d.invoice.invoice_number,true]),/changed/);
 await assert.rejects(rpc('invoice_delete_064',[invoice,d.invoice.revision,d.invoice.invoice_number,false]),/recorded payments/);
 await db.exec(`RESET ROLE;UPDATE profiles SET role='pm' WHERE id='${id(1)}';SET ROLE authenticated`);
 await assert.rejects(rpc('invoice_delete_064',[invoice,d.invoice.revision,d.invoice.invoice_number,true]),/access denied/);
 await assert.rejects(rpc('invoice_receive_payment_064',[invoice,d.invoice.revision,'full',null,'2026-09-27',null,id(402)]),/access denied/);
 await db.exec(`RESET ROLE;UPDATE profiles SET role='admin' WHERE id='${id(1)}';SET ROLE authenticated`);
});
await check('Deleting paid revised invoice removes rows/receipts/numbers, releases only its Scoops and allows number reuse',async()=>{
 const d=await rpc('invoice_get_061',[invoice]);await rpc('invoice_delete_064',[invoice,d.invoice.revision,d.invoice.invoice_number,true]);
 for(const table of ['client_invoices','client_invoice_lines','payments','invoice_numbers_062','invoice_revisions_062','invoice_events_061','invoice_scoop_allocations_061']){await db.exec('RESET ROLE');const key=table==='client_invoices'?'id':table==='payments'?'client_invoice_id':'invoice_id';assert.equal((await db.query(`SELECT count(*)::int n FROM ${table} WHERE ${key}=$1`,[invoice])).rows[0].n,0);await db.exec('SET ROLE authenticated');}
 const released=await db.query('SELECT status,financial_status FROM project_scoops WHERE id=ANY($1)',[[id(30),id(34)]]);assert.ok(released.rows.every(s=>s.status==='Approved'&&s.financial_status==='Not Invoiced'));
 assert.equal((await db.query('SELECT financial_status FROM project_scoops WHERE id=$1',[id(31)])).rows[0].financial_status,'Invoiced');
 assert.equal((await db.query('SELECT status FROM project_jobs WHERE id=$1',[id(90)])).rows[0].status,'Cancelled');
 const other=await rpc('invoice_save_061',[{...base,proposed_number:'160',lines:[base.lines[0]]},null,null]);const issued=await rpc('invoice_issue_061',[other,1]);assert.equal(issued.invoice.invoice_number,'0000000160');
});
await check('Deleting draft releases reservations and proposed number with no operational Job changes',async()=>{
 const n=await rpc('invoice_save_061',[{...base,proposed_number:'190',lines:[{scoop_id:id(34),description:'Test',amount:400}]},null,null]);const d=await rpc('invoice_get_061',[n]);await rpc('invoice_delete_064',[n,d.invoice.revision,d.invoice.draft_reference,false]);const queue=await rpc('invoice_workspace_061',[id(10),'',0,50,null]);assert.ok(queue.rows.some(s=>s.id===id(34)));
});
await check('Outside revision/deletion RPC, direct owner writes remain blocked',async()=>{await db.exec('RESET ROLE');const current=(await db.query("SELECT id FROM client_invoices WHERE status='Issued' LIMIT 1")).rows[0].id;await assert.rejects(db.query('DELETE FROM client_invoices WHERE id=$1',[current]),/cannot be deleted/);await assert.rejects(db.query("UPDATE client_invoices SET status='Draft' WHERE id=$1",[current]),/cannot return/);await db.exec('SET ROLE authenticated');});
await check('Manual-only invoice saves, issues, revises and pays without changing any Scoop',async()=>{
 const before=(await db.query('SELECT id,status,financial_status FROM project_scoops ORDER BY id')).rows;
 const payload={...base,proposed_number:'201',lines:[{description:'Консултация — български текст',amount:39.6},{description:'Additional service',amount:10}],tax_rate:20};
 const n=await rpc('invoice_save_061',[payload,null,null]);let d=await rpc('invoice_get_061',[n]);
 assert.equal(d.invoice.total,59.52);assert.equal(d.invoice.due_date,'2026-11-11');assert.ok(d.lines.every(l=>l.scoop_id==null&&l.project_id==null));
 await db.exec('RESET ROLE');assert.equal((await db.query('SELECT count(*)::int n FROM invoice_scoop_allocations_061 WHERE invoice_id=$1',[n])).rows[0].n,0);await db.exec('SET ROLE authenticated');
 d=await rpc('invoice_issue_061',[n,d.invoice.revision]);assert.equal(d.invoice.invoice_number,'0000000201');
 d=await rpc('invoice_revise_062',[n,d.invoice.revision,{...payload,lines:[{description:'Коригирана услуга',amount:49.6}]},'Correct description']);assert.equal(d.invoice.total,59.52);
 d=await rpc('invoice_receive_payment_064',[n,d.invoice.revision,'full',null,'2026-10-15',null,id(501)]);assert.equal(d.invoice.status,'Paid');
 assert.deepEqual((await db.query('SELECT id,status,financial_status FROM project_scoops ORDER BY id')).rows,before);
 await rpc('invoice_delete_064',[n,d.invoice.revision,d.invoice.invoice_number,true]);assert.deepEqual((await db.query('SELECT id,status,financial_status FROM project_scoops ORDER BY id')).rows,before);
});
await check('Manual invoice may later add a compatible Scoop; description and issue guards remain',async()=>{
 const payload={...base,proposed_number:'202',lines:[{description:'Manual work',amount:10}]};const n=await rpc('invoice_save_061',[payload,null,null]);
 await rpc('invoice_save_061',[{...payload,lines:[...payload.lines,{scoop_id:id(34),description:'Added later',amount:400}]},n,1]);let d=await rpc('invoice_get_061',[n]);assert.equal(d.invoice.total,410);assert.equal(d.lines.length,2);
 await rpc('invoice_delete_064',[n,d.invoice.revision,d.invoice.draft_reference,false]);
 await assert.rejects(rpc('invoice_save_061',[{...payload,lines:[{description:'',amount:10}]},null,null]),/description/i);
 const empty=await rpc('invoice_save_061',[{...payload,lines:[]},null,null]);await assert.rejects(rpc('invoice_issue_061',[empty,1]),/row|positive/i);
});
await check('QA read only; resource and anonymous denied',async()=>{await db.exec(`RESET ROLE;UPDATE profiles SET role='qa' WHERE id='${id(1)}';SET ROLE authenticated`);assert.ok(await rpc('invoice_workspace_061'));await assert.rejects(rpc('invoice_save_061',[base,null,null]),/access denied/);await db.exec(`RESET ROLE;UPDATE profiles SET role='resource' WHERE id='${id(1)}';SET ROLE authenticated`);await assert.rejects(rpc('invoice_workspace_061'),/access denied/);await db.exec('RESET ROLE;SET ROLE anon');await assert.rejects(rpc('invoice_workspace_061'),/permission denied/);await db.exec('RESET ROLE');});

await db.exec(read('tms/migrations/062_invoice_document_layout.sql'));
await db.exec(read('tms/migrations/062_invoice_document_layout.sql'));
await db.exec(read('tms/migrations/066_invoice_manual_draft_fix.sql'));
await db.exec(`UPDATE profiles SET role='admin' WHERE id='${id(1)}';SET ROLE authenticated`);
await check('066 metadata validation, frozen BG issuer and explicit historical revision',async()=>{
 const en={legal_name:'Retodo EOOD',address:'English address',registration_number:'208524462',bank:'English bank',iban:'KEEP-IBAN'};
 await rpc('invoice_settings_save_061',[en,301]);
 const payload={...base,proposed_number:'301',lines:[{description:'Услуга',amount:100}],document_details_066:{tax_event_date:'2026-10-15',payment_method:'bank',recipient_bg:'Тест получател',prepared_by_bg:'Тест съставител'}};
 const n=await rpc('invoice_save_066',[payload,null,null]);let d=await rpc('invoice_get_061',[n]);
 assert.equal(d.invoice.document_details_066.tax_event_date,'2026-10-15');
 for(const bad of [{tax_event_date:'2026-02-31'},{unknown:'x'},{payment_method:'card'},{recipient:42}]){
  await assert.rejects(rpc('invoice_save_066',[{...payload,document_details_066:bad},n,d.invoice.revision]));
  assert.equal((await rpc('invoice_get_061',[n])).invoice.revision,d.invoice.revision);
 }
 d=await rpc('invoice_issue_061',[n,d.invoice.revision]);
 const bg={...en,legal_name_bg:'Ретодо ЕООД',address_bg:'Български адрес',bank_bg:'Българска банка',prepared_by_bg:'Съставител'};
 await rpc('invoice_settings_save_061',[bg,302]);
 assert.equal((await rpc('invoice_get_061',[n])).invoice.issuer_snapshot.legal_name_bg,undefined);
 d=await rpc('invoice_receive_payment_064',[n,d.invoice.revision,'partial',10,'2026-10-15',null,id(601)]);
 const oldRevision=d.invoice.revision;
 d=await rpc('invoice_revise_066',[n,oldRevision,{...payload,document_details_066:{...payload.document_details_066,tax_event_date:'2026-10-16'}},'Bulgarian text',true]);
 assert.equal(d.invoice.issuer_snapshot.legal_name_bg,bg.legal_name_bg);assert.equal(d.invoice.issuer_snapshot.iban,en.iban);assert.equal(d.invoice.issuer_snapshot.address,en.address);assert.equal(d.invoice.document_details_066.tax_event_date,'2026-10-16');assert.equal(d.payments.length,1);
 const previous=(await db.query('SELECT snapshot FROM invoice_revisions_062 WHERE invoice_id=$1 AND revision=$2',[n,oldRevision])).rows[0].snapshot;
 assert.equal(previous.invoice.document_details_066.tax_event_date,'2026-10-15');assert.equal(previous.invoice.issuer_snapshot.legal_name_bg,undefined);
 await assert.rejects(rpc('invoice_revise_066',[n,oldRevision,payload,'Stale',true]),/Reopen/);
 await rpc('invoice_settings_save_061',[{...bg,registration_number:'OTHER',address_bg:'Changed'},303]);
 await assert.rejects(rpc('invoice_revise_066',[n,d.invoice.revision,payload,'Wrong company',true]),/same registration/);
 d=await rpc('invoice_revise_066',[n,d.invoice.revision,payload,'Keep frozen issuer',false]);assert.equal(d.invoice.issuer_snapshot.address_bg,bg.address_bg);
 const occupied=await result('SELECT invoice_number result FROM client_invoices WHERE id<>$1 AND invoice_number IS NOT NULL LIMIT 1',[n]);
 await assert.rejects(rpc('invoice_revise_066',[n,d.invoice.revision,{...payload,proposed_number:occupied},'Duplicate number',false]),/already exists|already belongs/);
 d=await rpc('invoice_revise_066',[n,d.invoice.revision,{...payload,proposed_number:'305',document_details_066:{payment_method:'bank'}},'Correct number',false]);
 assert.equal(d.invoice.invoice_number,'0000000305');assert.equal(d.payments.length,1);assert.equal(d.invoice.document_details_066.tax_event_date,undefined);
 assert.ok((await db.query('SELECT snapshot FROM invoice_revisions_062 WHERE invoice_id=$1',[n])).rows.some(r=>r.snapshot.invoice.invoice_number==='0000000301'));

 await db.exec('RESET ROLE');await assert.rejects(db.query("UPDATE client_invoices SET document_details_066='{}' WHERE id=$1",[n]),/frozen/);await db.exec('SET ROLE authenticated');
});
await check('066 wrappers retain role restrictions',async()=>{
 await db.exec(`RESET ROLE;UPDATE profiles SET role='pm' WHERE id='${id(1)}';SET ROLE authenticated`);
 const payload={...base,proposed_number:'304',lines:[{description:'PM manual',amount:20}],document_details_066:{payment_method:'cash'}};
 const n=await rpc('invoice_save_066',[payload,null,null]);assert.ok(n);await assert.rejects(rpc('invoice_revise_066',[n,1,payload,'Denied',true]),/access denied/);
 await db.exec(`RESET ROLE;UPDATE profiles SET role='qa' WHERE id='${id(1)}';SET ROLE authenticated`);await assert.rejects(rpc('invoice_save_066',[payload,null,null]),/access denied/);
 await db.exec('RESET ROLE;SET ROLE anon');await assert.rejects(rpc('invoice_save_066',[payload,null,null]),/permission denied/);await db.exec('RESET ROLE');
});
const audit066=await db.query(read('tms/audits/022_update_066_invoice_document_audit.sql'));assert.ok(audit066.rows.every(r=>r.result==='PASS'),JSON.stringify(audit066.rows));console.log('PASS Update 066 audit: '+audit066.rows.length+' checks');
const audit=await db.query(read('tms/audits/021_update_065_invoice_audit.sql'));assert.ok(audit.rows.every(r=>r.result==='PASS'),JSON.stringify(audit.rows.filter(r=>r.result!=='PASS')));console.log('PASS installation audit: '+audit.rows.length+' checks');

await db.exec(read('tms/migrations/065_invoice_reports.sql'));
await db.exec(read('tms/migrations/065_invoice_reports.sql'));
await db.exec(read('tms/migrations/067_invoice_report_downloads.sql'));
await db.exec(read('tms/migrations/067_invoice_report_downloads.sql'));
await db.exec(`UPDATE profiles SET role='admin' WHERE id='${id(1)}';
INSERT INTO clients(id,name,default_currency,default_payment_days) VALUES('${id(710)}','Report 067 A','EUR',30),('${id(711)}','Report 067 B','EUR',30);
INSERT INTO client_billing_entities(id,client_id,name,legal_name,address_line_1,city,country_code,is_default) VALUES('${id(712)}','${id(710)}','Main','Report 067 A Legal','Test Street','Sofia','BG',true),('${id(713)}','${id(711)}','Main','Report 067 B Legal','Test Street','Sofia','BG',true);
INSERT INTO report_fx_rates(currency,rate_date,units_per_eur,source) VALUES('USD',CURRENT_DATE,1.1,'ECB') ON CONFLICT(currency,rate_date) DO UPDATE SET units_per_eur=1.1;
SET ROLE authenticated`);
const day=(await db.query("SELECT ((now() AT TIME ZONE 'Europe/Sofia')::date)::text d,((now() AT TIME ZONE 'Europe/Sofia')::date-60)::text old")).rows[0];
const rptPayload={client_id:id(710),billing_entity_id:id(712),currency:'EUR',issue_date:day.old,tax_rate:0,tax_note:'Test basis',lines:[{description:'Report service',amount:100}],document_details_066:{bulgarian_enabled:false,recipient:'Report 067 A',prepared_by:'Demir Atanasov',prepared_by_bg:'Демир Атанасов'}};
let reportInvoice,reportDraft,reportUsd;
await check('067 English-only invoice issues with optional BG disabled and names saved',async()=>{
 await rpc('invoice_settings_save_061',[{legal_name:'English Issuer',registration_number:'208524462',address:'English Street',iban:'TEST-IBAN'},801]);
 reportInvoice=await rpc('invoice_save_066',[{...rptPayload,proposed_number:'801'},null,null]);let d=await rpc('invoice_issue_061',[reportInvoice,1]);assert.equal(d.invoice.document_details_066.bulgarian_enabled,false);assert.equal(d.invoice.document_details_066.prepared_by,'Demir Atanasov');assert.equal(d.invoice.issuer_snapshot.legal_name_bg,undefined);
 await assert.rejects(rpc('invoice_save_066',[{...rptPayload,document_details_066:{bulgarian_enabled:'yes'}},null,null]),/boolean/);
 d=await rpc('invoice_receive_payment_064',[reportInvoice,d.invoice.revision,'partial',20,day.d,null,id(720)]);assert.equal(d.invoice.status,'Partially Paid');
 reportDraft=await rpc('invoice_save_066',[{...rptPayload,proposed_number:'802',lines:[{description:'Draft',amount:900}]},null,null]);
 reportUsd=await rpc('invoice_save_066',[{...rptPayload,proposed_number:'803',currency:'USD',lines:[{description:'USD service',amount:200}]},null,null]);await rpc('invoice_issue_061',[reportUsd,1]);
 const cancelled=await rpc('invoice_save_066',[{...rptPayload,proposed_number:'804',lines:[{description:'Cancelled',amount:500}]},null,null]);await rpc('invoice_cancel_draft_061',[cancelled,1]);
 const other=await rpc('invoice_save_066',[{...rptPayload,client_id:id(711),billing_entity_id:id(713),proposed_number:'805'},null,null]);await rpc('invoice_issue_061',[other,1]);
});
await check('067 one invoice per row; totals cover all pages, currencies and excluded drafts',async()=>{
 const d=await rpc('invoice_report_070',[{client_id:id(710)},0,1,'number',false]);assert.equal(d.total_count,4);assert.equal(d.rows.length,1);assert.equal(d.next_offset,1);assert.equal(d.overdue_count,2);assert.equal(d.draft_count,1);assert.equal(d.can_record_payment,true);
 const eur=d.summary_by_currency.find(s=>s.currency==='EUR'),usd=d.summary_by_currency.find(s=>s.currency==='USD');assert.equal(eur.issued_total,100);assert.equal(eur.received,20);assert.equal(eur.outstanding,80);assert.equal(eur.overdue,80);assert.equal(eur.draft_total,900);assert.equal(usd.issued_total,200);assert.equal(usd.outstanding,200);
 const all=await rpc('invoice_report_070',[{client_id:id(710)},0,50,'number',false]);assert.equal(new Set(all.rows.map(r=>r.id)).size,4);assert.equal(all.rows.find(r=>r.status==='Cancelled').balance,0);assert.equal(all.rows.find(r=>r.status==='Draft').payable,false);
 const ids=[];for(let n=0;n<4;n++)ids.push((await rpc('invoice_report_070',[{client_id:id(710)},n,1,'balance',true])).rows[0].id);assert.equal(new Set(ids).size,4);
});
await check('067 filters, overdue dates, literal search, stable sort and validation',async()=>{
 assert.equal((await rpc('invoice_report_070',[{client_id:id(710),currency:'EUR',balance:'open'}])).total_count,1);
 assert.equal((await rpc('invoice_report_070',[{client_id:id(710),statuses:['Overdue']}])).total_count,2);
 assert.equal((await rpc('invoice_report_070',[{client_id:id(710),statuses:['Draft']}])).total_count,1);
 assert.equal((await rpc('invoice_report_070',[{search:'Report 067 B'}])).total_count,1);
 assert.equal((await rpc('invoice_report_070',[{search:'%'}])).total_count,0);
 assert.equal((await rpc('invoice_report_070',[{client_id:id(710),from:day.old,to:day.old,date_basis:'issue_date'}])).total_count,4);
 assert.equal((await rpc('invoice_report_070',[{client_id:id(710),from:day.d,date_basis:'due_date'}])).total_count,0);
 for(const args of [[{},-1,50,'number',false],[{},0,10001,'number',false],[{},0,50,'BAD',false],[{statuses:'Paid'}],[{statuses:['BAD']}],[{from:'2026-02-31'}],[{date_basis:'unknown'}],[{unknown:'x'}]])await assert.rejects(rpc('invoice_report_070',args));
 const d=await rpc('invoice_report_070',[{client_id:id(710)},0,50,'total',true]);assert.deepEqual(d.rows.map(r=>r.total),[900,500,200,100]);
});
await check('070 payment status filters and sorting use receipts and exclude drafts/cancellations',async()=>{
 const unpaid=await rpc('invoice_report_070',[{client_id:id(710),payment_status:'Unpaid'}]);
 const partial=await rpc('invoice_report_070',[{client_id:id(710),payment_status:'Partially paid'}]);
 assert.equal(unpaid.total_count,1);assert.equal(partial.total_count,1);
 assert.ok(unpaid.rows.every(r=>r.document_type==='Invoice'&&r.payment_status==='Unpaid'&&r.is_official));
 assert.ok(partial.rows.every(r=>r.paid>0&&r.balance>0&&r.payment_status==='Partially paid'));
 const all=await rpc('invoice_report_070',[{client_id:id(710)},0,50,'payment_status',false]);assert.equal(all.total_count,4);
 assert.ok(all.rows.filter(r=>['Draft','Cancelled'].includes(r.status)).every(r=>r.payment_status===null));
 await assert.rejects(rpc('invoice_report_070',[{payment_status:'BAD'}]),/Invalid payment status/);
 await assert.rejects(rpc('invoice_report_070',[{payment_status:123}]),/Invalid report filter/);
});
await check('067 payment updates report balances; stale and duplicate request guards retained',async()=>{
 const inv=(await rpc('invoice_get_061',[reportInvoice])).invoice;const args=[reportInvoice,inv.revision,'full',null,day.d,null,id(721)];await rpc('invoice_receive_payment_064',args);await rpc('invoice_receive_payment_064',args);
 const d=await rpc('invoice_report_070',[{client_id:id(710),currency:'EUR'}]);const row=d.rows.find(r=>r.id===reportInvoice);assert.equal(row.status,'Paid');assert.equal(row.paid,100);assert.equal(row.balance,0);assert.equal(row.payable,false);assert.equal(row.payment_count,2);assert.equal(d.summary_by_currency[0].received,100);assert.equal(d.summary_by_currency[0].overdue,0);
 const usd=(await rpc('invoice_get_061',[reportUsd])).invoice;await assert.rejects(rpc('invoice_receive_payment_064',[reportUsd,usd.revision-1,'partial',10,day.d,null,id(722)]),/changed/);
});
await check('067 report roles: QA and PM read only payments; external and anon denied',async()=>{
 for(const role of ['pm','qa']){await db.exec(`RESET ROLE;UPDATE profiles SET role='${role}' WHERE id='${id(1)}';SET ROLE authenticated`);const d=await rpc('invoice_report_070',[{client_id:id(710)}]);assert.equal(d.can_record_payment,false);assert.equal(d.total_count,4);await assert.rejects(rpc('invoice_receive_payment_064',[reportUsd,1,'full',null,day.d,null,id(723)]),/access denied/);}
 await db.exec(`RESET ROLE;UPDATE profiles SET role='resource' WHERE id='${id(1)}';SET ROLE authenticated`);await assert.rejects(rpc('invoice_report_070'),/access denied/);await db.exec('RESET ROLE;SET ROLE anon');await assert.rejects(rpc('invoice_report_070'),/permission denied/);await db.exec('RESET ROLE');
});
const audit067=await db.query(read('tms/audits/024_update_069_invoice_report_audit.sql'));assert.ok(audit067.rows.every(r=>r.result==='PASS'),JSON.stringify(audit067.rows));console.log('PASS Update 067 audit: '+audit067.rows.length+' checks');
const beforeReapply=(await db.query('SELECT id,total,revision,status FROM client_invoices ORDER BY id')).rows;
await db.exec(read('tms/migrations/066_invoice_manual_draft_fix.sql'));
assert.deepEqual((await db.query('SELECT id,total,revision,status FROM client_invoices ORDER BY id')).rows,beforeReapply);
const audit069=await db.query(read('tms/audits/025_update_069_manual_draft_audit.sql'));assert.ok(audit069.rows.every(r=>r.result==='PASS'),JSON.stringify(audit069.rows));console.log('PASS Update 069 draft audit: '+audit069.rows.length+' checks; repair reapplication leaves invoice data unchanged');
const audit070=await db.query(read('tms/audits/026_update_070_invoice_download_audit.sql'));assert.ok(audit070.rows.every(r=>r.result==='PASS'),JSON.stringify(audit070.rows));console.log('PASS Update 070 report audit: '+audit070.rows.length+' checks');
await db.exec(`UPDATE profiles SET role='admin' WHERE id='${id(1)}';SET ROLE authenticated`);
const renumberPayload={...rptPayload,proposed_number:'20'};
let renumbered,waiting20,originalHistory,originalEvents,originalPayments;
await check('071 reproduces 20 still blocked after official correction to 21',async()=>{
 renumbered=await rpc('invoice_save_066',[renumberPayload,null,null]);
 let d=await rpc('invoice_issue_061',[renumbered,1]);
 d=await rpc('invoice_receive_payment_064',[renumbered,d.invoice.revision,'partial',20,day.d,'KEEP-RECEIPT',id(730)]);
 d=await rpc('invoice_revise_066',[renumbered,d.invoice.revision,{...renumberPayload,proposed_number:'21'},'Correct 20 to 21',false]);
 assert.equal(d.invoice.invoice_number,'0000000021');assert.equal(d.payments.length,1);
 waiting20=await rpc('invoice_save_066',[renumberPayload,null,null]);
 await assert.rejects(rpc('invoice_issue_061',[waiting20,1]),/Invoice number already belongs to another invoice or its revision/);
 assert.equal((await rpc('invoice_get_061',[waiting20])).invoice.status,'Draft');
 await db.exec('RESET ROLE');
 originalHistory=(await db.query('SELECT * FROM invoice_revisions_062 ORDER BY id')).rows;
 originalEvents=(await db.query('SELECT * FROM invoice_events_061 ORDER BY id')).rows;
 originalPayments=(await db.query('SELECT * FROM payments ORDER BY id')).rows;
});
await db.exec('RESET ROLE');
await check('071 migration repairs old reservations and preserves invoice facts, history and payments',async()=>{
 const facts=(await db.query('SELECT * FROM client_invoices ORDER BY id')).rows;
 await db.exec(read('tms/migrations/068_invoice_number_release.sql'));
 assert.deepEqual((await db.query('SELECT * FROM client_invoices ORDER BY id')).rows,facts);
 assert.deepEqual((await db.query('SELECT * FROM invoice_revisions_062 ORDER BY id')).rows,originalHistory);
 assert.deepEqual((await db.query('SELECT * FROM invoice_events_061 ORDER BY id')).rows,originalEvents);
 assert.deepEqual((await db.query('SELECT * FROM payments ORDER BY id')).rows,originalPayments);
 assert.equal((await db.query("SELECT * FROM invoice_numbers_062 WHERE number='0000000020'")).rows.length,0);
});
await db.exec('SET ROLE authenticated');
await check('071 the failed draft now issues as 20; occupied 21 is still blocked',async()=>{
 const d=await rpc('invoice_issue_061',[waiting20,1]);assert.equal(d.invoice.invoice_number,'0000000020');
 assert.equal((await rpc('invoice_workspace_061')).settings.next_number,22);
 const duplicate=await rpc('invoice_save_066',[{...renumberPayload,proposed_number:'21'},null,null]);
 await assert.rejects(rpc('invoice_issue_061',[duplicate,1]),/already exists/);
 const revised=await rpc('invoice_get_061',[renumbered]);assert.equal(revised.invoice.invoice_number,'0000000021');assert.equal(revised.payments.length,1);
 const versions=(await db.query('SELECT snapshot FROM invoice_revisions_062 WHERE invoice_id=$1',[renumbered])).rows;
 assert.ok(versions.some(r=>r.snapshot.invoice.invoice_number==='0000000020'));
});
await check('071 future corrections release old numbers immediately and failed corrections retain them',async()=>{
 let d=await rpc('invoice_get_061',[waiting20]);
 d=await rpc('invoice_revise_066',[waiting20,d.invoice.revision,{...renumberPayload,proposed_number:'22'},'20 to 22',false]);
 assert.equal(d.invoice.invoice_number,'0000000022');
 const revisions=(await db.query('SELECT * FROM invoice_revisions_062 WHERE invoice_id=$1 ORDER BY id',[waiting20])).rows;
 await assert.rejects(rpc('invoice_revise_066',[waiting20,d.invoice.revision,{...renumberPayload,proposed_number:'21'},'Duplicate',false]),/already exists/);
 assert.deepEqual((await db.query('SELECT * FROM invoice_revisions_062 WHERE invoice_id=$1 ORDER BY id',[waiting20])).rows,revisions);
 await db.exec('RESET ROLE');
 assert.equal((await db.query("SELECT invoice_id FROM invoice_numbers_062 WHERE number='0000000022'")).rows[0].invoice_id,waiting20);
 assert.equal((await db.query("SELECT * FROM invoice_numbers_062 WHERE number='0000000020'")).rows.length,0);
 await db.exec('SET ROLE authenticated');
 const reused=await rpc('invoice_save_066',[renumberPayload,null,null]);assert.equal((await rpc('invoice_issue_061',[reused,1])).invoice.invoice_number,'0000000020');
});
await check('071 failure after reservation trigger rolls back release and replacement together',async()=>{
 await db.exec(`RESET ROLE;
 CREATE FUNCTION test_fail_after_reserve() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.invoice_number='0000000023' THEN RAISE EXCEPTION 'Simulated late failure'; END IF;RETURN NEW;END $$;
 CREATE TRIGGER zz_test_late_failure AFTER UPDATE OF invoice_number ON client_invoices FOR EACH ROW EXECUTE FUNCTION test_fail_after_reserve();
 SET ROLE authenticated;`);
 const d=await rpc('invoice_get_061',[waiting20]);
 await assert.rejects(rpc('invoice_revise_066',[waiting20,d.invoice.revision,{...renumberPayload,proposed_number:'23'},'Failed late',false]),/Simulated late failure/);
 assert.equal((await rpc('invoice_get_061',[waiting20])).invoice.invoice_number,'0000000022');
 await db.exec('RESET ROLE');
 assert.equal((await db.query("SELECT invoice_id FROM invoice_numbers_062 WHERE number='0000000022'")).rows[0].invoice_id,waiting20);
 assert.equal((await db.query("SELECT * FROM invoice_numbers_062 WHERE number='0000000023'")).rows.length,0);
 await db.exec('DROP TRIGGER zz_test_late_failure ON client_invoices;DROP FUNCTION test_fail_after_reserve();SET ROLE authenticated');
});
await check('071 no direct finance or reservation writes; migration reapplication and audit pass',async()=>{
 await assert.rejects(db.exec('DELETE FROM invoice_numbers_062'),/permission denied/);
 await assert.rejects(db.exec('DELETE FROM invoice_revisions_062'),/permission denied/);
 await db.exec('RESET ROLE');
 const reservations=(await db.query('SELECT * FROM invoice_numbers_062 ORDER BY number')).rows;
 await db.exec(read('tms/migrations/068_invoice_number_release.sql'));
 assert.deepEqual((await db.query('SELECT * FROM invoice_numbers_062 ORDER BY number')).rows,reservations);
 const audit071=(await db.query(read('tms/audits/027_update_071_invoice_number_audit.sql'))).rows;
 assert.equal(audit071.length,8);assert.ok(audit071.every(r=>r.result==='PASS'),JSON.stringify(audit071));
 console.log('PASS Update 071 installation audit: 8 checks');
});

console.log(`${passed} client invoice database checks passed`);

}catch(e){console.error(e.message);console.error(e.where,e.internalQuery,e.position);process.exitCode=1;}finally{await db.close();}
