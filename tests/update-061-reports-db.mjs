process.on('uncaughtException',e=>{console.error(e.message,e.detail||'',e.hint||'');process.exit(1)});
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath) throw new Error('Set PGLITE_MODULE to an installed @electric-sql/pglite module');
const {PGlite}=await import(pathToFileURL(modulePath));
const db=new PGlite();
await db.exec(`
CREATE ROLE authenticated; CREATE ROLE anon; CREATE ROLE service_role; CREATE SCHEMA auth; CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT current_user::text $$;
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
await db.exec("RESET ROLE");
await db.exec(fs.readFileSync(new URL('../tms/migrations/054_reports_eur_scoop_detail.sql',import.meta.url),'utf8'));
await db.exec("SET ROLE authenticated");
let passed=0;
async function check(name,fn){try{await fn();console.log('PASS',name);passed++;}catch(e){console.error('FAIL',name);throw e;}}
async function report(type='projects',filters={},offset=0,limit=50,sort='name',desc=false){return (await db.query('SELECT tms_report_061($1,$2::jsonb,$3,$4,$5,$6) result',[type,JSON.stringify(filters),offset,limit,sort,desc])).rows[0].result;}
async function owner(sql){await db.exec('RESET ROLE;'+sql+';SET ROLE authenticated;');}

await check('Projects list each Scoop once',async()=>{const d=await report();assert.equal(d.api_version,'061');assert.equal(d.total_count,2);assert.equal(d.project_count,1);assert.equal(d.rows[0].client_value,100);assert.equal(d.rows[0].costs.EUR,32.34);assert.equal(d.rows[0].profit,67.66);assert.equal(d.summary_by_currency[0].client_value,300);});
await check('Unknown cost identifies exact Job and does not masquerade as final margin',async()=>{await owner(`UPDATE project_jobs SET supplier_rate=NULL WHERE id='${id(31)}'`);const d=await report();assert.equal(d.rows[0].profit,null);assert.equal(d.rows[0].unknown_cost_count,1);assert.equal(d.rows[0].provisional_profit,87.66);assert.equal(d.rows[0].cost_details.find(r=>r.id===id(31)).native_cost,null);await owner(`UPDATE project_jobs SET supplier_rate=.2 WHERE id='${id(31)}'`);});
await check('EUR conversions use a single dated snapshot and preserve original amounts',async()=>{await owner(`INSERT INTO report_fx_rates(rate_date,currency,units_per_eur) VALUES(CURRENT_DATE,'USD',2);UPDATE project_jobs SET supplier_currency='USD' WHERE id='${id(31)}'`);const d=await report();assert.equal(d.rows[0].costs.EUR,22.34);assert.equal(d.rows[0].profit,77.66);assert.equal(d.rows[0].currency_warning_count,0);assert.equal(d.rows[0].cost_details.find(r=>r.id===id(31)).native_cost,20);assert.ok(d.fx_date);const sorted=await report('projects',{},0,50,'profit',true);assert.equal(sorted.rows[0].profit,170);});
await check('Missing FX remains explicit, not silently treated as EUR',async()=>{await owner(`UPDATE project_jobs SET supplier_currency='XXX' WHERE id='${id(31)}'`);const d=await report();assert.equal(d.rows[0].profit,null);assert.equal(d.rows[0].currency_warning_count,1);await owner(`UPDATE project_jobs SET supplier_currency='EUR' WHERE id='${id(31)}'`);});
await check('Foreign client values also convert to EUR and groups reconcile',async()=>{await owner("UPDATE projects SET currency='USD'");const d=await report('projects',{group_by:'client'});assert.equal(d.summary_by_currency[0].client_value,150);assert.equal(d.summary_by_currency[0].supplier_cost,62.34);assert.equal(d.groups[0].currency,'EUR');assert.equal(d.groups[0].profit,87.66);await owner("UPDATE projects SET currency='EUR'");});
await check('Authenticated users cannot forge the saved FX feed',async()=>{await assert.rejects(db.exec("INSERT INTO report_fx_rates(rate_date,currency,units_per_eur) VALUES(CURRENT_DATE,'GBP',1)"),/permission denied/);});
await check('Pagination uses requested count with full matching totals',async()=>{const d=await report('jobs',{},0,1);assert.equal(d.rows.length,1);assert.equal(d.next_offset,1);assert.equal(d.total_count,3);});
await check('Original-currency filter and language grouping work for the new Scoop grain',async()=>{await owner(`UPDATE project_jobs SET supplier_currency='USD' WHERE id='${id(31)}'`);const j=await report('jobs',{currency:'USD'});assert.equal(j.total_count,1);assert.equal(j.rows[0].costs.EUR,10);assert.equal(j.rows[0].native_currency,'USD');const g=await report('projects',{group_by:'language'});assert.equal(g.groups.length,2);await owner(`UPDATE project_jobs SET supplier_currency='EUR' WHERE id='${id(31)}'`);});
await check('Explicit zero cost is known; unavailable client FX cannot yield a partial revenue total',async()=>{await owner(`UPDATE project_jobs SET supplier_rate=0,supplier_amount=0 WHERE id='${id(31)}'`);const d=await report();assert.equal(d.rows[0].unknown_cost_count,0);assert.equal(d.rows[0].profit,87.66);await owner("UPDATE projects SET currency='XXX'");const missing=await report();assert.equal(missing.summary_by_currency[0].client_value,null);assert.equal(missing.summary_by_currency[0].profit,null);});
await db.close();console.log(`${passed} Update 061 reporting checks passed`);
