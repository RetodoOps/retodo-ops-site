process.on('uncaughtException',e=>{console.error(e.message,e.detail||'',e.hint||'');process.exit(1)});
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath) throw new Error('Set PGLITE_MODULE to an installed @electric-sql/pglite module');
const {PGlite}=await import(pathToFileURL(modulePath));
const db=new PGlite();
await db.exec(`
CREATE ROLE authenticated; CREATE ROLE anon;
CREATE FUNCTION public.current_app_role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.role',true),'') $$;
CREATE FUNCTION public.is_company_user() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT current_app_role() IN ('admin','pm','qa','client_relations') $$;
CREATE FUNCTION public.current_user_access_enabled() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT current_app_role() IN ('admin','pm','qa','client_relations','resource') $$;
CREATE TABLE clients(id uuid primary key,name text);
CREATE TABLE client_accounts(id uuid primary key,name text);
CREATE TABLE projects(id uuid primary key,project_number text,display_name text,project_date date,deadline timestamptz,status text,currency text,project_manager text,client_id uuid,account_id uuid);
CREATE TABLE project_scoops(id uuid primary key,project_id uuid,scoop_number text,status text,source_language text,target_language text,price numeric(14,2),deadline timestamptz,active boolean);
CREATE TABLE resources(id uuid primary key,legal_name text,company_name text,internal_number text);
CREATE TABLE project_jobs(id uuid primary key,project_id uuid,project_scoop_id uuid,job_number text,resource_id uuid,status text,deadline timestamptz,service_type text,source_language text,target_language text,quantity numeric,unit text,supplier_rate numeric,supplier_amount numeric(14,2),supplier_currency text);
CREATE TABLE supplier_purchase_orders(id uuid primary key,job_id uuid,status text,created_at timestamptz,total numeric(14,2),currency text,current_version integer,po_number text);
CREATE TABLE supplier_po_versions(id uuid primary key,purchase_order_id uuid,version_number integer,snapshot jsonb,unique(purchase_order_id,version_number));
GRANT USAGE ON SCHEMA public TO authenticated,anon;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
`);
for(const table of ['clients','client_accounts','projects','project_scoops','resources','project_jobs','supplier_purchase_orders','supplier_po_versions']) await db.exec(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY; CREATE POLICY company_read ON ${table} FOR SELECT TO authenticated USING(is_company_user());`);
await db.exec('ALTER TABLE projects ADD COLUMN project_manager_resource_id uuid; ALTER TABLE client_accounts ADD COLUMN client_id uuid;');
await db.exec(fs.readFileSync(new URL('../tms/migrations/053_reports_functional_upgrade.sql',import.meta.url),'utf8'));
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
await db.exec(`
INSERT INTO clients VALUES('${id(1)}','Example client');INSERT INTO client_accounts(id,name) VALUES('${id(2)}','Localization');
INSERT INTO resources VALUES('${id(3)}','Resource one',null,'R1');
INSERT INTO projects(id,project_number,display_name,project_date,deadline,status,currency,project_manager,client_id,account_id) VALUES('${id(10)}','P1','Project one','2026-09-24',null,'Ongoing','EUR','Alex','${id(1)}','${id(2)}');
INSERT INTO project_scoops VALUES
('${id(20)}','${id(10)}','S1','Ongoing','English','Bulgarian',100,null,true),
('${id(21)}','${id(10)}','S2','Ongoing','English','German',200,null,true);
INSERT INTO project_jobs VALUES
('${id(30)}','${id(10)}','${id(20)}','J1','${id(3)}','Assigned','2026-09-24T00:00:00Z','Translation','English','Bulgarian',100,'Source words',0.1,10,'EUR'),
('${id(31)}','${id(10)}','${id(20)}','J2','${id(3)}','Assigned','2026-09-24T23:59:59.999Z','Review','English','Bulgarian',100,'Source words',0.2,20,'EUR'),
('${id(32)}','${id(10)}','${id(21)}','J3','${id(3)}','Assigned','2026-09-25T00:00:00Z','Translation','English','German',100,'Source words',0.3,30,'EUR'),
('${id(33)}','${id(10)}','${id(21)}','J4','${id(3)}','Cancelled',null,'Translation','English','German',100,'Source words',9.99,999,'EUR');
INSERT INTO supplier_purchase_orders VALUES
('${id(40)}','${id(30)}','Superseded','2026-09-20',99,'EUR',1,'PO-old'),
('${id(41)}','${id(30)}','Issued','2026-09-21',12.34,'EUR',2,'PO-current');
INSERT INTO supplier_po_versions VALUES
('${id(50)}','${id(41)}',1,'{"total":11,"currency":"EUR"}'),
('${id(51)}','${id(41)}',2,'{"total":12.34,"currency":"EUR"}');
SET ROLE authenticated;SET test.role='admin';
`);
let passed=0;
async function check(name,fn){try{await fn();console.log('PASS',name);passed++;}catch(e){console.error('FAIL',name);throw e;}}
async function report(type='projects',filters={},offset=0,limit=50,sort='name',desc=false){return (await db.query('SELECT tms_report($1,$2::jsonb,$3,$4,$5,$6) result',[type,JSON.stringify(filters),offset,limit,sort,desc])).rows[0].result;}
async function owner(sql){await db.exec('RESET ROLE;'+sql+';SET ROLE authenticated;');}
await check('Projects and Margin aggregate each Scoop and effective PO once',async()=>{
 const p=await report();assert.equal(p.total_count,1);assert.equal(p.rows[0].client_value,300);assert.equal(p.rows[0].costs.EUR,62.34);assert.equal(p.rows[0].profit,237.66);assert.equal(p.rows[0].margin,79.22);assert.equal(p.rows[0].job_count,3);
 const m=await report('margin');assert.equal(m.total_count,2);assert.equal(m.summary_by_currency[0].client_value,300);assert.equal(m.summary_by_currency[0].profit,237.66);assert.equal(m.summary_by_currency[0].margin,79.22);
});
await check('Jobs omit client allocation and retain quantity/unit/PO provenance',async()=>{const d=await report('jobs');assert.equal(d.total_count,3);assert.equal(d.rows[0].cost_basis,'PO commitment');assert.equal(d.rows[0].po_version,2);assert.equal(d.rows[1].cost_basis,'Estimate');assert.equal(d.rows[0].client_value,undefined);assert.equal(d.rows[0].unit,'Source words');});
await check('UTC date bounds include whole end day only',async()=>{assert.equal((await report('jobs',{from:'2026-09-24',to:'2026-09-24'})).total_count,2);assert.equal((await report('projects',{from:'2026-09-25'})).total_count,0);});
await check('Scope includes cancelled work only when requested',async()=>{assert.equal((await report('jobs',{scope:'all'})).total_count,4);assert.equal((await report('projects',{scope:'all'})).rows[0].costs.EUR,1061.34);});
await check('Mixed currencies separated and profit suppressed',async()=>{
 await owner(`UPDATE project_jobs SET supplier_currency='USD' WHERE id='${id(31)}'`);
 const d=await report();assert.equal(d.rows[0].profit,null);assert.deepEqual(d.rows[0].costs,{EUR:42.34,USD:20});assert.equal(d.summary_by_currency.find(s=>s.currency==='EUR').profit,null);assert.equal(d.warning_rows,1);
 await owner(`UPDATE project_jobs SET supplier_currency='EUR' WHERE id='${id(31)}'`);
});
await check('Unknown cost never treated as zero',async()=>{await owner(`UPDATE project_jobs SET supplier_rate=null,supplier_amount=0 WHERE id='${id(31)}'`);const d=await report();assert.equal(d.rows[0].unknown_cost_count,1);assert.equal(d.rows[0].profit,null);await owner(`UPDATE project_jobs SET supplier_rate=0.2,supplier_amount=20 WHERE id='${id(31)}'`);});
await check('Missing snapshot and conflicting current POs suppress margin',async()=>{
 await owner(`UPDATE supplier_po_versions SET snapshot='{"total":999,"currency":"EUR"}' WHERE id='${id(51)}'`);assert.equal((await report()).rows[0].profit,null);
 await owner(`UPDATE supplier_po_versions SET snapshot='{"total":12.34,"currency":"EUR"}' WHERE id='${id(51)}';UPDATE supplier_purchase_orders SET status='Issued' WHERE id='${id(40)}'`);
 const d=await report('jobs');assert.equal(d.rows[0].active_po_count,2);assert.equal(d.rows[0].po_id,id(41));assert.equal((await report()).rows[0].profit,null);
 await owner(`UPDATE supplier_purchase_orders SET status='Superseded' WHERE id='${id(40)}'`);
});
await check('Zero client value gives N/A margin',async()=>{await owner(`UPDATE project_scoops SET price=0 WHERE id='${id(20)}'`);assert.equal((await report('margin')).rows[0].margin,null);await owner(`UPDATE project_scoops SET price=100 WHERE id='${id(20)}'`);});
await check('No-Scoop Project keeps unavailable value rather than synthetic zero',async()=>{await owner(`INSERT INTO projects(id,project_number,display_name,project_date,deadline,status,currency,project_manager,client_id,account_id) SELECT '${id(11)}','P2','Empty','2026-09-24',null,'Assign','EUR','Alex','${id(1)}','${id(2)}'`);const row=(await report('projects',{search:'Empty'})).rows[0];assert.equal(row.client_value,null);assert.equal(row.profit,null);await owner(`DELETE FROM projects WHERE id='${id(11)}'`);});
await check('Empty Scoop and unallocated Job suppress margins',async()=>{
 await owner(`INSERT INTO project_scoops VALUES('${id(22)}','${id(10)}','Empty Scoop','Assign','English','French',100,null,true)`);
 const empty=await report();assert.equal(empty.rows[0].empty_scoop_count,1);assert.equal(empty.rows[0].profit,null);
 await owner(`DELETE FROM project_scoops WHERE id='${id(22)}';UPDATE project_jobs SET project_scoop_id=null WHERE id='${id(31)}'`);
 assert.equal((await report()).rows[0].profit,null);assert.ok((await report('margin')).rows.every(r=>r.profit===null));
 await owner(`UPDATE project_jobs SET project_scoop_id='${id(20)}' WHERE id='${id(31)}'`);
});
await check('Missing immutable version suppresses margin',async()=>{
 await owner(`UPDATE supplier_purchase_orders SET current_version=3 WHERE id='${id(41)}'`);
 assert.equal((await report()).rows[0].po_warning_count,1);assert.equal((await report()).rows[0].profit,null);
 await owner(`UPDATE supplier_purchase_orders SET current_version=2 WHERE id='${id(41)}'`);
});
await check('Deterministic PO selection breaks timestamp ties by ID',async()=>{
 await owner(`UPDATE supplier_purchase_orders SET status='Issued',created_at='2026-09-21' WHERE id='${id(40)}'`);
 assert.equal((await report('jobs')).rows[0].po_id,id(41));
 await owner(`UPDATE supplier_purchase_orders SET status='Superseded' WHERE id='${id(40)}'`);
});
await check('Filter/sort allowlist and invalid ranges rejected',async()=>{await assert.rejects(report('invoices'));await assert.rejects(report('projects',{resource:'bad'}));await assert.rejects(report('jobs',{from:'2026-09-25',to:'2026-09-24'}));await assert.rejects(report('jobs',{},0,10001));await assert.rejects(report('jobs',{},-1));await assert.rejects(report('jobs',{},0,50,'bad'));});
await check('Existing company role access retained; resource/disabled roles denied',async()=>{for(const role of ['admin','pm','qa','client_relations']){await db.exec(`SET test.role='${role}'`);assert.equal((await report()).total_count,1);}for(const role of ['resource','user','']){await db.exec(`SET test.role='${role}'`);await assert.rejects(report(),/Company report access required/);}await db.exec("SET test.role='admin'");});
await check('Anonymous cannot execute reporting function',async()=>{await db.exec('RESET ROLE;SET ROLE anon;');await assert.rejects(report(),/permission denied/);await db.exec('RESET ROLE;SET ROLE authenticated;');});
await check('Invoker RLS applies to rows, counts and summaries',async()=>{await owner('CREATE POLICY deny_projects ON projects AS RESTRICTIVE FOR SELECT TO authenticated USING(false)');const d=await report();assert.equal(d.total_count,0);assert.deepEqual(d.rows,[]);assert.deepEqual(d.summary_by_currency,[]);await owner('DROP POLICY deny_projects ON projects');});
await check('059 searches numbers, languages, resources and PO references',async()=>{
 for(const search of ['P1','Bulgarian','Resource one','PO-current'])assert.equal((await report('projects',{search})).total_count,1);
 assert.equal((await report('margin',{search:'P1'})).total_count,2);
});
await check('059 relational choices, IDs and multiple statuses',async()=>{
 await owner(`UPDATE projects SET project_manager_resource_id='${id(3)}';UPDATE client_accounts SET client_id='${id(1)}'`);
 const options=(await db.query('SELECT tms_report_options_059() result')).rows[0].result;
 assert.equal(options.api_version,'059');assert.equal(options.accounts[0].client_id,id(1));assert.equal(options.managers[0].id,id(3));assert.ok(!options.job_statuses.includes('Offered'));
 assert.equal((await report('jobs',{client_id:id(1),account_id:id(2),pm_id:id(3),resource_id:id(3),statuses:['Assigned','Approved']})).total_count,3);
 assert.equal((await report('projects',{client_id:id(9)})).total_count,0);
});
await check('059 language pairs match one Scoop and preserve whole Project costs',async()=>{
 assert.equal((await report('projects',{source_language:'English',target_language:'Bulgarian'})).rows[0].costs.EUR,62.34);
 await owner(`UPDATE project_scoops SET source_language='French' WHERE id='${id(21)}'`);
 assert.equal((await report('projects',{source_language:'French',target_language:'Bulgarian'})).total_count,0);
 await owner(`UPDATE project_scoops SET source_language='English' WHERE id='${id(21)}'`);
 assert.equal((await report('projects',{service:'Review'})).rows[0].client_value,300);
});
await check('059 estimates are informational, blockers separate, and cost basis filter works',async()=>{
 const p=await report();assert.equal(p.warning_rows,0);assert.equal(p.estimate_rows,1);
 assert.equal((await report('jobs',{cost_basis:'po'})).total_count,1);
 assert.equal((await report('jobs',{cost_basis:'estimate'})).total_count,2);
 assert.equal((await report('projects',{issue:'blocked'})).total_count,0);
 assert.equal((await report('projects',{issue:'estimates'})).total_count,1);
});
await check('059 numeric sorting, margin range and weighted groups',async()=>{
 const d=await report('margin',{currency:'EUR',group_by:'client'},0,50,'client_value',true);
 assert.equal(d.rows[0].client_value,200);assert.equal(d.groups[0].client_value,300);assert.equal(d.groups[0].supplier_cost,62.34);assert.equal(d.groups[0].margin,79.22);
 assert.equal((await report('margin',{margin_min:80})).total_count,1);
 await assert.rejects(report('projects',{},0,50,'profit'));
 await assert.rejects(report('jobs',{currency:'EUR'},0,50,'profit'));
 assert.equal((await report('jobs',{date_basis:'project',from:'2026-09-24',to:'2026-09-24'})).total_count,3);
});
await check('059 options and groups preserve RLS',async()=>{
 await owner('CREATE POLICY deny_projects ON projects AS RESTRICTIVE FOR SELECT TO authenticated USING(false)');
 assert.deepEqual((await report('projects',{group_by:'client'})).groups,[]);
 const o=(await db.query('SELECT tms_report_options_059() result')).rows[0].result;assert.deepEqual(o.clients,[]);assert.deepEqual(o.resources,[]);
 await owner('DROP POLICY deny_projects ON projects');
});
await check('Beyond 1000 rows: full totals, stable paging, complete export',async()=>{
 await owner(`INSERT INTO project_jobs SELECT ('00000000-0000-0000-0001-'||lpad(n::text,12,'0'))::uuid,'${id(10)}','${id(20)}','Bulk '||lpad(n::text,4,'0'),null,'Assigned','2026-09-24', 'Translation','English','Bulgarian',1,'Source words',0.01,0.01,'EUR' FROM generate_series(1,1100) n`);
 const first=await report('jobs',{},0,50),next=await report('jobs',{},50,50),all=await report('jobs',{},0,10000);
 assert.equal(first.total_count,1103);assert.equal(all.rows.length,1103);assert.equal(first.next_offset,50);assert.deepEqual(first.summary_by_currency,all.summary_by_currency);assert.equal(new Set([...first.rows,...next.rows].map(r=>r.id)).size,100);assert.equal(all.summary_by_currency[0].supplier_cost,73.34);
});
await db.close();console.log(`${passed} database checks passed`);
