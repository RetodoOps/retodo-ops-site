// Isolated PostgreSQL regression for Update 050. Never touches live Supabase/R2.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');

await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.role',true),'')
$$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('app.actor_id',true),'')::uuid
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
 profile_id uuid UNIQUE REFERENCES profiles(id),portal_status text NOT NULL DEFAULT 'Not invited',
 lifecycle_status text NOT NULL DEFAULT 'Active',resource_status text NOT NULL DEFAULT 'New contact',
 email text,legal_name text,company_name text,city text,tax_id text,
 compliance_status text NOT NULL DEFAULT 'Unknown',updated_at timestamptz DEFAULT now()
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
 evidence text,qualification_status text,PRIMARY KEY(resource_id,specialization_id));
CREATE TABLE client_accounts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL,
 allow_name_in_blind_cv boolean NOT NULL DEFAULT false,blind_cv_label text
);
CREATE TABLE projects(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),account_id uuid REFERENCES client_accounts(id),
 project_date date
);
CREATE TABLE project_jobs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_id uuid NOT NULL REFERENCES projects(id),
 job_number text NOT NULL,resource_id uuid REFERENCES resources(id),service_type text NOT NULL,
 source_language text,target_language text,specialization_id uuid REFERENCES specializations(id),
 status text NOT NULL DEFAULT 'Unassigned',approved_at timestamptz,deadline timestamptz,
 delivered_at timestamptz,quantity numeric(14,3),unit text,supplier_rate numeric(14,4),
 supplier_currency text DEFAULT 'EUR',supplier_amount numeric(14,2) DEFAULT 0
);
CREATE TABLE resource_project_history(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),resource_id uuid NOT NULL REFERENCES resources(id),
 project_id uuid REFERENCES projects(id),job_id uuid UNIQUE REFERENCES project_jobs(id),
 account_id uuid REFERENCES client_accounts(id),account_display_label text,
 project_year integer,period_start date,period_end date,source_language text,
 target_language text,service_type text,specialization_id uuid,
 project_summary text,include_in_blind_cv boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE resource_account_qualifications(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),resource_id uuid NOT NULL REFERENCES resources(id),
 account_id uuid NOT NULL REFERENCES client_accounts(id),specialization_id uuid REFERENCES specializations(id),
 qualification_status text NOT NULL DEFAULT 'Not tested',evidence text,updated_by uuid REFERENCES profiles(id),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE NULLS NOT DISTINCT(resource_id,account_id,specialization_id)
);
CREATE TABLE resource_tests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),resource_id uuid NOT NULL REFERENCES resources(id),
 test_type text NOT NULL CHECK(test_type IN ('General','Domain','Account')),
 status text NOT NULL DEFAULT 'Assigned',source_language text,target_language text,
 service_type text,specialization_id uuid REFERENCES specializations(id),
 account_id uuid REFERENCES client_accounts(id),assigned_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,memoq_project_ref text,reviewer_name text,evidence text,
 created_by uuid REFERENCES profiles(id),created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT resource_tests_status_check CHECK(status IN ('Assigned','In review','Passed','Failed','Cancelled')),
 CHECK(
   (test_type='General' AND specialization_id IS NULL AND account_id IS NULL)
   OR (test_type='Domain' AND specialization_id IS NOT NULL AND account_id IS NULL)
   OR (test_type='Account' AND account_id IS NOT NULL)
 )
);
ALTER TABLE resource_education ENABLE ROW LEVEL SECURITY;
ALTER TABLE resource_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE file_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE resource_tests ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.current_external_resource_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT nullif(current_setting('app.resource_id',true),'')::uuid
$$;
CREATE FUNCTION public.get_blind_cv_data(uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.save_job_overview(uuid,jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_terms_changed boolean := false; v_po_changed boolean;
BEGIN
 v_po_changed := v_terms_changed OR false;
 RETURN CASE WHEN v_po_changed THEN 1 ELSE 0 END;
END
$$;
`);

await db.exec(read('tms/migrations/047_compliance_evidence_iso_eligibility.sql'));
await db.exec(read('tms/migrations/048_compliance_phase_tests_and_job_qualifications.sql'));
await db.exec(read('tms/migrations/049_job_approval_history_compliance_agreement.sql'));

const insertProfile = async role => (await db.query(
  'INSERT INTO profiles(role) VALUES($1) RETURNING id', [role],
)).rows[0].id;
const insertResource = async (number, profileId, overrides = {}) => (await db.query(`
  INSERT INTO resources(
    internal_number,profile_id,portal_status,lifecycle_status,resource_status,
    email,legal_name,company_name,city,country_of_residence,tax_id,
    compliance_phase_status
  ) VALUES($1,$2,'Active','Active','Assignable',$3,$4,$5,$6,$7,$8,$9)
  RETURNING id
`, [
  number, profileId, overrides.email || `${number.toLowerCase()}@example.com`,
  overrides.legalName || number, overrides.companyName || null,
  overrides.city || 'Sofia', overrides.country || 'Bulgaria',
  overrides.taxId || 'BG123456789', overrides.phase || 'Requested',
])).rows[0].id;
const claim = role => db.query('SELECT set_config($1,$2,false)', ['request.jwt.claim.role', role]);
const actor = id => db.query('SELECT set_config($1,$2,false)', ['app.actor_id', id || '']);
const ownResource = id => db.query('SELECT set_config($1,$2,false)', ['app.resource_id', id || '']);
const companyRole = role => db.query('SELECT set_config($1,$2,false)', ['app.test_role', role || '']);
const fileDispatch = async (action, actorId, fileId = null, resourceId = null, payload = {}) => (
  await db.query(`SELECT public.resource_compliance_file_dispatch_048($1,$2,$3,$4,$5) AS value`,
    [action, actorId, fileId, resourceId, JSON.stringify(payload)])
).rows[0].value;
const addCv = async (actorId, resourceId, filename) => {
  const prepared = await fileDispatch('prepare_upload', actorId, null, resourceId, {
    original_filename: filename, mime_type: 'application/pdf', size_bytes: 123,
    checksum_sha256: 'a'.repeat(64), bucket_name: 'private-r2', evidence_type: 'CV',
  });
  await fileDispatch('publish_upload', actorId, prepared.file_id, null, {
    verified_size_bytes: 123, verified_checksum_sha256: 'a'.repeat(64), storage_class: 'STANDARD',
  });
  return prepared.file_id;
};

let passed = 0;
async function check(name, action) {
  await action();
  passed += 1;
  console.log('PASS ' + name);
}

const adminId = await insertProfile('admin');
const resourceProfileId = await insertProfile('resource');
const otherProfileId = await insertProfile('resource');
const resourceId = await insertResource('RO-LNG-00500', resourceProfileId, {
  legalName: 'Example Vendor', email: 'vendor@example.com', taxId: 'BG987654321',
});
const otherResourceId = await insertResource('RO-LNG-00501', otherProfileId, {
  legalName: 'Other Vendor', phase: 'In progress',
});

await db.query(`
 INSERT INTO resource_education(
   resource_id,degree_level,degree_type,is_highest_relevant,verified
 ) VALUES($1,'No university degree','No university degree',true,false)
`, [resourceId]);
await claim('service_role');
const keptCvId = await addCv(resourceProfileId, resourceId, 'current-cv.pdf');
const duplicateCvId = await addCv(resourceProfileId, resourceId, 'current-cv-copy.pdf');

await check('exact Resource can delete an accidental duplicate but another Resource cannot', async () => {
  await assert.rejects(() => db.query(`
    SELECT public.resource_compliance_file_delete_050('inspect',$1,$2,NULL)
  `, [otherProfileId, duplicateCvId]), /Compliance file not found/);
  const inspected = (await db.query(`
    SELECT public.resource_compliance_file_delete_050('inspect',$1,$2,NULL) AS value
  `, [resourceProfileId, duplicateCvId])).rows[0].value;
  assert.equal(inspected.resource_id, resourceId);
  await db.query(`
    SELECT public.resource_compliance_file_delete_050('commit',$1,$2,$3)
  `, [resourceProfileId, duplicateCvId, 'Duplicate evidence']);
  const {rows: [row]} = await db.query(`
    SELECT file.upload_status,file.deleted_at,document.status
    FROM file_records file JOIN resource_documents document ON document.file_record_id=file.id
    WHERE file.id=$1
  `, [duplicateCvId]);
  assert.equal(row.upload_status, 'Deleted');
  assert.ok(row.deleted_at);
  assert.equal(row.status, 'Rejected');
  const log = (await db.query(
    `SELECT action FROM file_access_logs WHERE file_record_id=$1 ORDER BY occurred_at DESC LIMIT 1`,
    [duplicateCvId],
  )).rows[0];
  assert.equal(log.action, 'Delete');
});

await check('portal Agreement pre-fills known vendor details without exposing another Resource', async () => {
  await claim('authenticated'); await actor(resourceProfileId); await ownResource(resourceId);
  const agreement = (await db.query(
    'SELECT public.resource_portal_framework_agreement_050() AS value',
  )).rows[0].value;
  assert.equal(agreement.status, 'Not accepted');
  assert.equal(agreement.provider.service_provider_name, 'Example Vendor');
  assert.equal(agreement.provider.service_provider_address, 'Sofia, Bulgaria');
  assert.equal(agreement.provider.tax_vat_number, 'BG987654321');
  assert.equal(agreement.provider.registration_email, 'vendor@example.com');
  assert.equal(agreement.provider.registration_or_id_number, '');
  assert.equal('iso_eligibility' in agreement, false);

  await actor(otherProfileId); await ownResource(otherResourceId);
  const other = (await db.query(
    'SELECT public.resource_portal_framework_agreement_050() AS value',
  )).rows[0].value;
  assert.equal(other.resource_id, otherResourceId);
  assert.notEqual(other.provider.registration_email, 'vendor@example.com');
});

await check('Compliance cannot be submitted until the exact Agreement version is accepted', async () => {
  await claim('authenticated'); await actor(resourceProfileId); await ownResource(resourceId);
  await assert.rejects(() => db.query(
    'SELECT public.resource_portal_submit_compliance_048()',
  ), /Read and accept the Freelancer Framework Agreement/);

  const accepted = (await db.query(`
    SELECT public.resource_portal_accept_framework_agreement_050($1) AS value
  `, [JSON.stringify({
    service_provider_name: 'Example Vendor', registration_or_id_number: 'ID-500',
    service_provider_address: '1 Vendor Street, Sofia, Bulgaria',
    tax_vat_number: 'BG987654321', signatory_name: 'Example Vendor', accepted: true,
  })])).rows[0].value;
  assert.equal(accepted.status, 'Accepted');
  assert.equal(accepted.agreement_version, '1.0');
  assert.equal(accepted.agreement_sha256,
    '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a');
  assert.ok(accepted.accepted_at);

  const stored = (await db.query(`
    SELECT agreement_version,agreement_sha256,registration_email,accepted_by,accepted_at
    FROM resource_framework_agreements WHERE resource_id=$1
  `, [resourceId])).rows[0];
  assert.equal(stored.registration_email, 'vendor@example.com');
  assert.equal(stored.accepted_by, resourceProfileId);
  assert.ok(stored.accepted_at);
  const auditRow = (await db.query(`
    SELECT action FROM audit_events WHERE entity_id=$1 AND action='Framework agreement accepted'
  `, [resourceId])).rows[0];
  assert.equal(auditRow.action, 'Framework agreement accepted');

  const submitted = (await db.query(
    'SELECT public.resource_portal_submit_compliance_048() AS value',
  )).rows[0].value;
  assert.equal(submitted.status, 'Submitted');
  assert.equal(submitted.editable, false);
  assert.equal('iso_eligibility' in submitted, false);
  assert.equal(keptCvId !== duplicateCvId, true);
});

await check('submission notification state is exact-resource bound and deduplicated', async () => {
  await claim('service_role');
  const prepared = (await db.query(`
    SELECT public.resource_compliance_submission_notification_050('prepare',$1,$2,NULL) AS value
  `, [resourceProfileId, resourceId])).rows[0].value;
  assert.equal(prepared.notification_kind, 'compliance_submitted');
  assert.equal(prepared.already_sent, false);
  await assert.rejects(() => db.query(`
    SELECT public.resource_compliance_submission_notification_050('prepare',$1,$2,NULL)
  `, [otherProfileId, resourceId]), /access denied/);
  await db.query(`
    SELECT public.resource_compliance_submission_notification_050('sent',$1,$2,NULL)
  `, [resourceProfileId, resourceId]);
  const repeated = (await db.query(`
    SELECT public.resource_compliance_submission_notification_050('prepare',$1,$2,NULL) AS value
  `, [resourceProfileId, resourceId])).rows[0].value;
  assert.equal(repeated.notification_kind, null);
  assert.equal(repeated.already_sent, true);
});

await check('Approved Job history captures and updates operational size without money', async () => {
  const accountId = (await db.query(`
    INSERT INTO client_accounts(name,allow_name_in_blind_cv,blind_cv_label)
    VALUES('Private Client',false,'Confidential finance account') RETURNING id
  `)).rows[0].id;
  const projectId = (await db.query(`
    INSERT INTO projects(account_id,project_date) VALUES($1,'2026-09-01') RETURNING id
  `, [accountId])).rows[0].id;
  const jobId = (await db.query(`
    INSERT INTO project_jobs(
      project_id,job_number,resource_id,service_type,source_language,target_language,
      status,approved_at,delivered_at,quantity,unit,supplier_rate,supplier_amount
    ) VALUES($1,'J-APPROVED-050',$2,'Translation','English (US)','Norwegian (Bokmål)',
      'Approved',now(),'2026-09-12T10:00:00Z',1200,'Source words',0.25,300)
    RETURNING id
  `, [projectId, resourceId])).rows[0].id;
  let history = (await db.query(`
    SELECT quantity,unit,account_display_label FROM resource_project_history WHERE job_id=$1
  `, [jobId])).rows[0];
  assert.equal(Number(history.quantity), 1200);
  assert.equal(history.unit, 'Source words');
  assert.equal(history.account_display_label, 'Confidential finance account');

  await db.query(`UPDATE project_jobs SET quantity=7.5,unit='Hours' WHERE id=$1`, [jobId]);
  history = (await db.query(`
    SELECT quantity,unit FROM resource_project_history WHERE job_id=$1
  `, [jobId])).rows[0];
  assert.equal(Number(history.quantity), 7.5);
  assert.equal(history.unit, 'Hours');

  await companyRole('admin');
  const cv = (await db.query('SELECT public.get_blind_cv_data($1) AS value', [resourceId])).rows[0].value;
  assert.equal(Number(cv.project_history[0].quantity), 7.5);
  assert.equal(cv.project_history[0].unit, 'Hours');
  assert.equal('supplier_amount' in cv.project_history[0], false);
  assert.equal('legal_name' in cv.resource, false);
  assert.equal('email' in cv.resource, false);
  assert.equal('iso_eligibility' in cv, false);
});

await check('internal workflow sees accepted Agreement and sent notification status', async () => {
  await companyRole('admin');
  const summary = (await db.query(`
    SELECT public.resource_compliance_workflow_summary_048($1) AS value
  `, [resourceId])).rows[0].value;
  assert.equal(summary.status, 'Submitted');
  assert.equal(summary.framework_agreement.status, 'Accepted');
  assert.ok(summary.submission_notification_sent_at);
  assert.equal(summary.submission_notification_error, null);
});

await check('forward migration can be retried and audit 011 reports PASS for every boundary', async () => {
  await db.exec(read('tms/migrations/049_job_approval_history_compliance_agreement.sql'));
  const result = await db.query(read('tms/audits/011_update_050_job_approval_history_compliance_agreement_audit.sql'));
  assert.ok(result.rows.length >= 9);
  for (const row of result.rows) assert.equal(row.result, 'PASS', row.check_name);
});

console.log(`${passed} Update 050 database checks passed`);
await db.close();
