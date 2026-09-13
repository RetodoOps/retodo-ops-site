// Isolated PostgreSQL regression for Update 048. Never touches live Supabase/R2.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db=new PGlite();
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');

await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.role',true),'')
$$;
CREATE TABLE profiles(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),role text NOT NULL);
CREATE TABLE audit_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),actor_id uuid,
 entity_type text,entity_id uuid,action text,before_values jsonb,
 after_values jsonb,reason text
);
CREATE FUNCTION public.is_company_user() RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT current_setting('app.test_role',true) IN ('admin','pm','qa','client_relations')
$$;
CREATE FUNCTION public.can_manage_operations() RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT current_setting('app.test_role',true) IN ('admin','pm','client_relations')
$$;
CREATE FUNCTION public.append_trusted_tms_audit_event(
 p_entity_type text,p_entity_id uuid,p_action text,
 p_before_values jsonb,p_after_values jsonb,p_reason text
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO audit_events(entity_type,entity_id,action,before_values,after_values,reason)
 VALUES(p_entity_type,p_entity_id,p_action,p_before_values,p_after_values,p_reason);
END
$$;
CREATE TABLE resources(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 internal_number text NOT NULL UNIQUE,resource_type text NOT NULL DEFAULT 'Freelancer',
 initials text,nationality text,country_of_residence text,native_language text,
 updated_at timestamptz DEFAULT now()
);
CREATE TABLE resource_education(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 resource_id uuid NOT NULL REFERENCES resources(id),institution text,
 degree text,field_of_study text,start_year integer,end_year integer,
 verified boolean NOT NULL DEFAULT false,sort_order integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz DEFAULT now()
);
CREATE TABLE file_records(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 project_id uuid,job_id uuid,resource_id uuid REFERENCES resources(id),
 storage_provider text,bucket_name text,object_key text,original_filename text,
 mime_type text,size_bytes bigint,file_role text,checksum_sha256 text,
 retention_until date DEFAULT CURRENT_DATE + 90,archived_at timestamptz,
 uploaded_by uuid,upload_status text NOT NULL DEFAULT 'Ready',storage_class text,
 verified_at timestamptz,storage_error text,r2_etag text,r2_version_id text,
 deleted_at timestamptz,created_at timestamptz DEFAULT now()
);
CREATE TABLE resource_documents(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),resource_id uuid NOT NULL REFERENCES resources(id),
 document_type text NOT NULL,file_record_id uuid REFERENCES file_records(id),
 issued_on date,expires_on date,status text NOT NULL DEFAULT 'Pending',
 reviewed_by uuid,reviewed_at timestamptz,notes text,
 created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now()
);
CREATE TABLE file_access_logs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),file_record_id uuid REFERENCES file_records(id),
 profile_id uuid,resource_id uuid,action text,occurred_at timestamptz DEFAULT now()
);
CREATE TABLE resource_language_pairs(resource_id uuid,source_language text,target_language text,native_target boolean);
CREATE TABLE resource_services(resource_id uuid,service_type text);
CREATE TABLE specializations(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text);
CREATE TABLE resource_specializations(resource_id uuid,specialization_id uuid,experience_years numeric,
 evidence text,qualification_status text);
CREATE TABLE resource_project_history(resource_id uuid,project_year integer,period_start date,
 period_end date,account_display_label text,source_language text,target_language text,
 service_type text,specialization_id uuid,project_summary text,include_in_blind_cv boolean);
CREATE FUNCTION public.get_blind_cv_data(uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
ALTER TABLE resource_education ENABLE ROW LEVEL SECURITY;
ALTER TABLE resource_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE file_records ENABLE ROW LEVEL SECURITY;
`);

// A pre-existing CV document can point to non-Compliance legacy storage.
// Migration 047 must not silently promote that metadata into ISO evidence.
const {rows:[legacyResource]}=await db.query(
 "INSERT INTO resources(internal_number) VALUES('legacy-cv-file') RETURNING id"
);
const {rows:[legacyFile]}=await db.query(`
 INSERT INTO file_records(resource_id,storage_provider,object_key,original_filename,file_role)
 VALUES($1,'Supabase','legacy/cv','old.pdf','Reference') RETURNING id
`,[legacyResource.id]);
await db.query(`
 INSERT INTO resource_documents(resource_id,document_type,file_record_id,status)
 VALUES($1,'CV',$2,'Valid')
`,[legacyResource.id,legacyFile.id]);

await db.exec(read('tms/migrations/047_compliance_evidence_iso_eligibility.sql'));
await db.exec("SET app.test_role='admin'");

const statuses=async id=>{
 const {rows:[row]}=await db.query('SELECT public.resource_compliance_summary_047($1) AS value',[id]);
 return row.value;
};
const addResource=async number=>{
 const {rows:[row]}=await db.query('INSERT INTO resources(internal_number) VALUES($1) RETURNING id',[number]);
 return row.id;
};
const addActor=async role=>{
 const {rows:[row]}=await db.query('INSERT INTO profiles(role) VALUES($1) RETURNING id',[role]);
 return row.id;
};
const setDates=async (id,translation,revision,mtpe)=>{
 const {rows:[row]}=await db.query(
  'SELECT public.save_resource_professional_since_047($1,$2,$3,$4) AS dates',
  [id,translation,revision,mtpe]
 );return row.dates;
};
const addEducation=async (id,actor,type,overrides={})=>{
 const payload={degree:'Relevant Bachelor',degree_type:type,field_of_study:'Translation',
  institution:'Test University',country:'Norway',graduation_date:'2018-06-01',
  verified:true,is_highest_relevant:true,...overrides};
 const {rows:[row]}=await db.query(
  'SELECT public.save_resource_education_047($1,$2,$3) AS id',
  [id,null,JSON.stringify(payload)]
 );return row.id;
};
const roleClaim=async role=>db.query('SELECT set_config($1,$2,false)',[
 'request.jwt.claim.role',role
]);
const dispatch=async (action,actor,fileId=null,resourceId=null,payload={})=>{
 const {rows:[row]}=await db.query(
  'SELECT public.resource_compliance_file_dispatch_047($1,$2,$3,$4,$5) AS value',
  [action,actor,fileId,resourceId,JSON.stringify(payload)]
 );return row.value;
};
const evidence=async (id,actor,type,educationId=null,reviewed=true)=>{
 const prepared=await dispatch('prepare_upload',actor,null,id,{
  original_filename:type==='CV'?'reviewed-cv.pdf':'diploma.pdf',
  mime_type:'application/pdf',size_bytes:88,
  checksum_sha256:'a'.repeat(64),bucket_name:'private-r2',
  evidence_type:type,education_id:educationId,
 });
 await dispatch('publish_upload',actor,prepared.file_id,null,{
  verified_size_bytes:88,verified_checksum_sha256:'a'.repeat(64),
  storage_class:'STANDARD',
 });
 if(reviewed)await dispatch('review_evidence',actor,prepared.file_id);
 return prepared.file_id;
};
const eligible=(summary,key)=>summary.iso_eligibility[key].eligible;

let passed=0;
async function check(name,fn){await fn();passed++;console.log('PASS '+name)}

const admin=await addActor('admin');
const qa=await addActor('qa');
const freelancer=await addActor('resource');
await roleClaim('service_role');

await check('1. Translation degree and valid dates require linked diploma and CV, then qualify',async()=>{
 const id=await addResource('degree');
 const degree=await addEducation(id,admin,'Translation / language degree');
 await setDates(id,'2018-05-20','2020-07-04','2022-01-01');
 assert.equal(eligible(await statuses(id),'translator'),false);
 await evidence(id,admin,'Diploma / certificate',degree);
 assert.equal(eligible(await statuses(id),'translator'),false);
 const cv=await evidence(id,admin,'CV',null,false);
 assert.equal(eligible(await statuses(id),'translator'),false);
 await dispatch('review_evidence',admin,cv);
 const current=await statuses(id);
 assert.equal(eligible(current,'translator'),true);
 assert.equal(eligible(current,'reviser'),true);
 assert.equal(eligible(current,'post_editor'),true);
 assert.match(current.iso_eligibility.translator.explanation,/Translation \/ language degree/);
});

await check('2. Other university degree and at least 24 months qualify',async()=>{
 const id=await addResource('other-degree');
 const degree=await addEducation(id,admin,'Other university degree');
 await setDates(id,'2018-05-01','2020-06-01','2020-06-01');
 await evidence(id,admin,'Diploma / certificate',degree);
 await evidence(id,admin,'CV');
 assert.equal(eligible(await statuses(id),'translator'),true);
});

await check('3. Other university degree and 16 documented months do not qualify',async()=>{
 const id=await addResource('insufficient');
 const degree=await addEducation(id,admin,'Other university degree');
 const now=new Date();const year=now.getUTCFullYear(),month=now.getUTCMonth();
 const since=new Date(Date.UTC(year,month-16,1)).toISOString().slice(0,10);
 await setDates(id,since,since,since);
 await evidence(id,admin,'Diploma / certificate',degree);
 await evidence(id,admin,'CV');
 const summary=await statuses(id);
 assert.equal(eligible(summary,'translator'),false);
 assert.match(summary.iso_eligibility.translator.explanation,/only 1 year 4 months/);
});

await check('4. Explicitly reviewed no-degree route and 60 months qualify',async()=>{
 const id=await addResource('no-degree');
 await addEducation(id,admin,'No university degree',{
  degree:null,field_of_study:null,institution:null,country:null,
  graduation_date:null,
 });
 await setDates(id,'2016-01-01','2017-01-01','2018-01-01');
 await evidence(id,admin,'CV');
 assert.equal(eligible(await statuses(id),'translator'),true);
});

await check('5. Missing records or unreviewed education never assume eligibility',async()=>{
 const id=await addResource('legacy');
 let summary=await statuses(id);
 assert.equal(eligible(summary,'translator'),false);
 assert.equal(eligible(summary,'reviser'),false);
 assert.equal(eligible(summary,'post_editor'),false);
 assert.equal(summary.professional_experience.translation,null);
 const degree=await addEducation(id,admin,'Translation / language degree',{verified:false});
 await setDates(id,'2018-05-01',null,null);
 await evidence(id,admin,'Diploma / certificate',degree);
 await evidence(id,admin,'CV');
 summary=await statuses(id);
 assert.equal(eligible(summary,'translator'),false);
 assert.match(summary.iso_eligibility.translator.explanation,/incomplete/);
});

await check('Post-editor without an MTPE start date is not assumed qualified',async()=>{
 const id=await addResource('no-mtpe');
 const degree=await addEducation(id,admin,'Translation / language degree');
 await setDates(id,'2016-01-01','2018-01-01',null);
 await evidence(id,admin,'Diploma / certificate',degree);
 await evidence(id,admin,'CV');
 const result=await statuses(id);
 assert.equal(eligible(result,'translator'),true);
 assert.equal(eligible(result,'reviser'),true);
 assert.equal(eligible(result,'post_editor'),false);
 assert.match(result.iso_eligibility.post_editor.explanation,/MTPE/);
});

await check('6. Separate service dates yield three independent durations',async()=>{
 const summary=await statuses((await db.query("SELECT id FROM resources WHERE internal_number='degree'")).rows[0].id);
 assert.notEqual(summary.professional_experience.translation.total_months,
  summary.professional_experience.revision.total_months);
 assert.notEqual(summary.professional_experience.revision.total_months,
  summary.professional_experience.mtpe.total_months);
});

await check('7. Month-boundary duration is dynamic, including leap year and future null',async()=>{
 const duration=async (start,end)=>
  (await db.query('SELECT public.professional_experience_duration_047($1,$2) AS value',[
   start,end
  ])).rows[0].value;
 assert.equal((await duration('2018-05-01','2026-09-01')).display,'8 years 4 months');
 assert.equal((await duration('2018-05-31','2026-09-30')).display,'8 years 4 months');
 assert.equal((await duration('2024-02-01','2024-03-01')).display,'0 years 1 month');
 assert.equal((await duration('2026-01-31','2026-02-01')).display,'0 years 1 month');
 assert.equal(await duration('2026-04-01','2026-03-31'),null);
 assert.equal(await duration(null,'2026-03-31'),null);
});

await check('8. Blind CV receives recalculated durations but never ISO decisions or file identity',async()=>{
 const id=(await db.query("SELECT id FROM resources WHERE internal_number='degree'")).rows[0].id;
 const data=(await db.query('SELECT public.get_blind_cv_data($1) AS value',[id])).rows[0].value;
 const summary=await statuses(id);
 assert.deepEqual(data.professional_experience,summary.professional_experience);
 assert.equal('iso_eligibility' in data,false);
 assert.equal('file_records' in data,false);
 assert.equal('email' in data.resource,false);
});

await check('9–10. Company internal users can read ISO; resource login cannot',async()=>{
 const id=(await db.query("SELECT id FROM resources WHERE internal_number='degree'")).rows[0].id;
 await db.exec("SET app.test_role='qa'");
 assert.equal(eligible(await statuses(id),'translator'),true);
 await db.exec("SET app.test_role='resource'");
 await assert.rejects(()=>statuses(id),/Company access required/);
 await assert.rejects(()=>db.query('SELECT public.get_blind_cv_data($1)',[id]),/Company access required/);
 await db.exec("SET app.test_role='admin'");
});

await check('11. No editable ISO column or override; caller privilege remains role-bound',async()=>{
 const {rows:columns}=await db.query(`
  SELECT table_name,column_name FROM information_schema.columns
  WHERE table_schema='public' AND column_name LIKE 'iso%'
 `);
 assert.equal(columns.length,0);
 await db.exec("SET app.test_role='resource'");
 const id=(await db.query("SELECT id FROM resources WHERE internal_number='degree'")).rows[0].id;
 await assert.rejects(()=>setDates(id,'2020-01-01',null,null),/Operational access required/);
 await db.exec("SET app.test_role='admin'");
});

await check('12. Editing start month immediately flips live eligibility and CV',async()=>{
 const id=(await db.query("SELECT id FROM resources WHERE internal_number='other-degree'")).rows[0].id;
 const now=new Date();
 const shortDate=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()-6,1)).toISOString().slice(0,10);
 await setDates(id,shortDate,null,'2018-01-01');
 const after=await statuses(id);
 assert.equal(after.professional_experience.translation.total_months,6);
 assert.equal(eligible(after,'translator'),false);
 assert.equal(eligible(after,'reviser'),false);
 assert.equal(eligible(after,'post_editor'),true);
 const cv=(await db.query('SELECT public.get_blind_cv_data($1) AS value',[id])).rows[0].value;
 assert.equal(cv.professional_experience.translation.total_months,6);
});

await check('13. Legacy records lacking new fields load without qualification fabrication',async()=>{
 const id=await addResource('old-record');
 const result=await statuses(id);
 assert.equal(result.evidence.education_complete,false);
 assert.equal(result.professional_experience.revision,null);
 assert.equal(result.iso_eligibility.reviser.status,'Not eligible');
});

await check('Education record and ready diploma must match the same Resource',async()=>{
 const first=await addResource('linked-a'),second=await addResource('linked-b');
 const edu=await addEducation(first,admin,'Other university degree');
 await assert.rejects(()=>dispatch('prepare_upload',admin,null,second,{
  original_filename:'bad.pdf',mime_type:'application/pdf',size_bytes:10,
  checksum_sha256:'a'.repeat(64),bucket_name:'private-r2',
  evidence_type:'Diploma / certificate',education_id:edu,
 }),/matching education record/);
});

await check('File dispatcher limits upload to operations, download to company, verifies bytes',async()=>{
 const id=(await db.query("SELECT id FROM resources WHERE internal_number='degree'")).rows[0].id;
 await assert.rejects(()=>dispatch('prepare_upload',qa,null,id,{
  original_filename:'qa.pdf',size_bytes:10,checksum_sha256:'a'.repeat(64),
  bucket_name:'private-r2',evidence_type:'CV',
 }),/Operational access required/);
 const file=await evidence(id,admin,'CV');
 const ticket=await dispatch('authorize_download',qa,file);
 assert.equal(ticket.file_id,file);
 await assert.rejects(()=>dispatch('authorize_download',freelancer,file),/Compliance file not found/);
 await roleClaim('authenticated');
 await assert.rejects(()=>dispatch('authorize_download',admin,file),/Service role required/);
 await roleClaim('service_role');
 const {rows:[privileges]}=await db.query(`
  SELECT has_function_privilege('authenticated',
   'public.resource_compliance_file_dispatch_047(text,uuid,uuid,uuid,jsonb)',
   'EXECUTE') AS browser,
   has_function_privilege('service_role',
   'public.resource_compliance_file_dispatch_047(text,uuid,uuid,uuid,jsonb)',
   'EXECUTE') AS server
 `);
 assert.equal(privileges.browser,false);
 assert.equal(privileges.server,true);
});

await check('Unreviewed CV cannot qualify and browser cannot forge file or review state',async()=>{
 const id=await addResource('review-boundary');
 const degree=await addEducation(id,admin,'Translation / language degree');
 await setDates(id,'2017-01-01',null,null);
 await evidence(id,admin,'Diploma / certificate',degree);
 const file=await evidence(id,admin,'CV',null,false);
 assert.equal(eligible(await statuses(id),'translator'),false);
 await roleClaim('authenticated');
 await assert.rejects(()=>db.query('UPDATE resource_documents SET status=$1 WHERE file_record_id=$2',[
  'Valid',file
 ]),/Compliance evidence changes require the server/);
 await assert.rejects(()=>db.query(`
  INSERT INTO resource_documents(resource_id,document_type,file_record_id,status)
  VALUES($1,'CV',$2,'Valid')
 `,[id,file]),/Compliance evidence changes require the server/);
 await assert.rejects(()=>db.query('UPDATE file_records SET upload_status=$1 WHERE id=$2',[
  'Failed',file
 ]),/Compliance file changes require the server/);
 await assert.rejects(()=>db.query(`
  INSERT INTO file_records(resource_id,storage_provider,object_key,original_filename,file_role)
  VALUES($1,'Cloudflare R2','forged/file','fake.pdf','Compliance - CV')
 `,[id]),/Compliance file changes require the server/);
 await roleClaim('service_role');
 await assert.rejects(()=>dispatch('review_evidence',qa,file),/Operational access required/);
 await dispatch('review_evidence',admin,file);
 assert.equal(eligible(await statuses(id),'translator'),true);
});

await check('Legacy CV metadata without dedicated private R2 evidence never qualifies',async()=>{
 const degree=await addEducation(legacyResource.id,admin,'Translation / language degree');
 await setDates(legacyResource.id,'2017-01-01',null,null);
 await evidence(legacyResource.id,admin,'Diploma / certificate',degree);
 assert.equal(eligible(await statuses(legacyResource.id),'translator'),false);
 await roleClaim('authenticated');
 await db.query("UPDATE resource_documents SET status='Waived' WHERE file_record_id=$1",[
  legacyFile.id
 ]);
 await roleClaim('service_role');
});

await check('Forward migration is idempotent and a read-only audit passes',async()=>{
 await db.exec(read('tms/migrations/047_compliance_evidence_iso_eligibility.sql'));
 const results=await db.query(read('tms/audits/009_update_048_compliance_iso_audit.sql'));
 for(const result of results.rows)assert.equal(result.result,'PASS',result.check_name);
});

console.log(`${passed} Update 048 Compliance database checks passed`);
await db.close();
