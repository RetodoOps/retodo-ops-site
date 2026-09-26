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
const check=async()=>{
 await db.exec('SET ROLE authenticated');
 for(const type of ['projects','margin','jobs']){const d=(await db.query('SELECT tms_report($1) result',[type])).rows[0].result;assert.equal(d.api_version,'059');assert.equal(d.total_count,0);}
 const d=(await db.query('SELECT tms_report_options_059() result')).rows[0].result;assert.equal(d.api_version,'059');assert.ok(d.job_statuses.includes('Assigned'));await db.exec('RESET ROLE');
};
await db.exec(read('tms/migrations/053_reports_functional_upgrade.sql'));await check();console.log('PASS 053 without 052, repository reporting schema and access functions');
await db.exec(read('tms/migrations/052_read_only_reports.sql'));await db.exec(read('tms/migrations/053_reports_functional_upgrade.sql'));await check();console.log('PASS 053 replaces 052');
await db.exec(read('tms/migrations/053_reports_functional_upgrade.sql'));await check();console.log('PASS 053 reapplication');
const audit=await db.query(read('tms/audits/014_update_059_reports_audit.sql'));assert.ok(audit.rows.length>0);assert.ok(audit.rows.every(r=>r.result==='PASS'),JSON.stringify(audit.rows));console.log('PASS installation audit: '+audit.rows.length+' checks');
}catch(e){console.error(e.message);process.exitCode=1;}finally{await db.close();}
