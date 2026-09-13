// Isolated PostgreSQL regression for Update 049. Never touches live Supabase/R2.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

// Reuse the already-tested Update 048 base schema fixture, then add the
// operational tables/columns exercised by Update 049.
const baseSource = read('tests/update-048-compliance-iso-db.mjs');
const baseFixture = baseSource.match(/await db\.exec\(`([\s\S]*?)`\);/);
assert.ok(baseFixture, 'Update 048 database fixture is available');
await db.exec(baseFixture[1]);

await db.exec(`
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('app.actor_id',true),'')::uuid
$$;

ALTER TABLE resources
 ADD COLUMN profile_id uuid UNIQUE REFERENCES profiles(id),
 ADD COLUMN portal_status text NOT NULL DEFAULT 'Not invited',
 ADD COLUMN lifecycle_status text NOT NULL DEFAULT 'Active',
 ADD COLUMN resource_status text NOT NULL DEFAULT 'New contact',
 ADD COLUMN email text,
 ADD COLUMN legal_name text,
 ADD COLUMN company_name text,
 ADD COLUMN compliance_status text NOT NULL DEFAULT 'Unknown';

ALTER TABLE resource_specializations
 ADD CONSTRAINT resource_specializations_pkey PRIMARY KEY(resource_id,specialization_id);

CREATE TABLE client_accounts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL
);
CREATE TABLE projects(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid REFERENCES client_accounts(id)
);
CREATE TABLE project_jobs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 project_id uuid NOT NULL REFERENCES projects(id),
 job_number text NOT NULL,
 resource_id uuid REFERENCES resources(id),
 service_type text NOT NULL,
 source_language text,
 target_language text,
 specialization_id uuid REFERENCES specializations(id),
 status text NOT NULL DEFAULT 'Unassigned',
 approved_at timestamptz,
 quantity numeric(14,3),
 unit text,
 supplier_rate numeric(14,4),
 supplier_currency text DEFAULT 'EUR',
 supplier_amount numeric(14,2) DEFAULT 0
);
CREATE TABLE resource_account_qualifications(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 resource_id uuid NOT NULL REFERENCES resources(id),
 account_id uuid NOT NULL REFERENCES client_accounts(id),
 specialization_id uuid REFERENCES specializations(id),
 qualification_status text NOT NULL DEFAULT 'Not tested',
 evidence text,
 updated_by uuid REFERENCES profiles(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE NULLS NOT DISTINCT(resource_id,account_id,specialization_id)
);
CREATE TABLE resource_tests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 resource_id uuid NOT NULL REFERENCES resources(id),
 test_type text NOT NULL CHECK(test_type IN ('General','Domain','Account')),
 status text NOT NULL DEFAULT 'Assigned',
 source_language text,
 target_language text,
 service_type text,
 specialization_id uuid REFERENCES specializations(id),
 account_id uuid REFERENCES client_accounts(id),
 assigned_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 memoq_project_ref text,
 reviewer_name text,
 evidence text,
 created_by uuid REFERENCES profiles(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT resource_tests_status_check CHECK(
   status IN ('Assigned','In review','Passed','Failed','Cancelled')
 ),
 CHECK(
   (test_type='General' AND specialization_id IS NULL AND account_id IS NULL)
   OR (test_type='Domain' AND specialization_id IS NOT NULL AND account_id IS NULL)
   OR (test_type='Account' AND account_id IS NOT NULL)
 )
);
ALTER TABLE resource_tests ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.current_external_resource_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT nullif(current_setting('app.resource_id',true),'')::uuid
$$;
`);

const insertProfile = async role => (await db.query(
  'INSERT INTO profiles(role) VALUES($1) RETURNING id', [role],
)).rows[0].id;
const insertResource = async (number, profileId = null) => (await db.query(`
  INSERT INTO resources(
    internal_number,profile_id,portal_status,lifecycle_status,
    resource_status,email,legal_name
  ) VALUES($1,$2,'Active','Active','New contact',$3,$4) RETURNING id
`, [number, profileId, `${number.toLowerCase()}@example.com`, number])).rows[0].id;
const claim = async role => db.query('SELECT set_config($1,$2,false)', [
  'request.jwt.claim.role', role,
]);
const actor = async id => db.query('SELECT set_config($1,$2,false)', [
  'app.actor_id', id || '',
]);
const ownResource = async id => db.query('SELECT set_config($1,$2,false)', [
  'app.resource_id', id || '',
]);
const companyRole = async role => db.query('SELECT set_config($1,$2,false)', [
  'app.test_role', role,
]);

const adminId = await insertProfile('admin');
const externalProfileId = await insertProfile('resource');
const otherProfileId = await insertProfile('resource');
const missingProfileId = await insertProfile('resource');
const legacyId = await insertResource('LEGACY');
const resourceId = await insertResource('PORTAL', externalProfileId);
const otherResourceId = await insertResource('OTHER', otherProfileId);
const missingResourceId = await insertResource('MISSING', missingProfileId);

// This is a real legacy row: Update 049 must split its status/result without
// fabricating a different timestamp.
await db.query(`
 INSERT INTO resource_tests(resource_id,test_type,status,assigned_at,completed_at)
 VALUES($1,'General','Passed','2024-01-10T10:00:00Z','2024-01-11T10:00:00Z')
`, [legacyId]);

await db.exec(read('tms/migrations/047_compliance_evidence_iso_eligibility.sql'));
await db.exec(read('tms/migrations/048_compliance_phase_tests_and_job_qualifications.sql'));

const workflow = async (action, target, reason = null) => (await db.query(`
 SELECT public.resource_compliance_workflow_dispatch_048($1,$2,$3,$4) AS value
`, [action, adminId, target, reason])).rows[0].value;
const portalRead = async () => (await db.query(
  'SELECT public.resource_portal_compliance_048() AS value',
)).rows[0].value;
const portalSave = async payload => (await db.query(
  'SELECT public.resource_portal_save_compliance_048($1) AS value',
  [JSON.stringify(payload)],
)).rows[0].value;
const fileDispatch = async (action, actorId, fileId = null, target = null, payload = {}) => (
  await db.query(`
   SELECT public.resource_compliance_file_dispatch_048($1,$2,$3,$4,$5) AS value
  `, [action, actorId, fileId, target, JSON.stringify(payload)])
).rows[0].value;
const publishEvidence = async (actorId, target, type, educationId = null) => {
  const prepared = await fileDispatch('prepare_upload', actorId, null, target, {
    original_filename: type === 'CV' ? 'evidence-cv.pdf' : 'diploma.pdf',
    mime_type: 'application/pdf', size_bytes: 128,
    checksum_sha256: 'a'.repeat(64), bucket_name: 'private-r2',
    evidence_type: type, education_id: educationId,
  });
  await fileDispatch('publish_upload', actorId, prepared.file_id, null, {
    verified_size_bytes: 128, verified_checksum_sha256: 'a'.repeat(64),
    storage_class: 'STANDARD',
  });
  return prepared.file_id;
};

let passed = 0;
async function check(name, fn) {
  await fn();
  passed++;
  console.log('PASS ' + name);
}

await check('legacy Passed status becomes Completed/Pass without changing its recorded date', async () => {
  const {rows: [row]} = await db.query(`
    SELECT status,test_result,tested_before_tms,assigned_at,completed_at
    FROM resource_tests WHERE resource_id=$1
  `, [legacyId]);
  assert.equal(row.status, 'Completed');
  assert.equal(row.test_result, 'Pass');
  assert.equal(row.tested_before_tms, false);
  assert.equal(new Date(row.assigned_at).toISOString(), '2024-01-10T10:00:00.000Z');
  assert.equal(new Date(row.completed_at).toISOString(), '2024-01-11T10:00:00.000Z');
});

await check('pre-TMS checkbox is always Completed/Pass and stores no test date', async () => {
  const {rows: [row]} = await db.query(`
    INSERT INTO resource_tests(
      resource_id,test_type,status,test_result,tested_before_tms,
      assigned_at,completed_at,evidence
    ) VALUES($1,'General','Assigned','Fail',true,now(),now(),'Legacy test')
    RETURNING status,test_result,assigned_at,completed_at
  `, [resourceId]);
  assert.equal(row.status, 'Completed');
  assert.equal(row.test_result, 'Pass');
  assert.equal(row.assigned_at, null);
  assert.equal(row.completed_at, null);
  const status = (await db.query('SELECT resource_status FROM resources WHERE id=$1', [resourceId])).rows[0];
  assert.equal(status.resource_status, 'Assignable');
});

await check('ordinary completed tests require an explicit result and retain dates', async () => {
  await assert.rejects(() => db.query(`
    INSERT INTO resource_tests(resource_id,test_type,status,test_result)
    VALUES($1,'General','Completed',NULL)
  `, [otherResourceId]), /requires a Pass or Fail/);
  const {rows: [row]} = await db.query(`
    INSERT INTO resource_tests(resource_id,test_type,status,test_result)
    VALUES($1,'General','Completed','Pass')
    RETURNING assigned_at,completed_at
  `, [otherResourceId]);
  assert.ok(row.assigned_at);
  assert.ok(row.completed_at);
});

await check('Compliance remains hidden until explicitly prompted after a successful General test', async () => {
  await claim('authenticated');
  await ownResource(resourceId);
  assert.equal((await portalRead()).visible, false);
  await claim('service_role');
  const opened = await workflow('request', resourceId);
  assert.equal(opened.status, 'Requested');
  assert.equal(opened.notification_kind, 'compliance_requested');
  await claim('authenticated');
  const visible = await portalRead();
  assert.equal(visible.visible, true);
  assert.equal(visible.editable, true);
  assert.equal('iso_eligibility' in visible, false);
});

await check('prompting before a successful General test is rejected', async () => {
  await claim('service_role');
  await assert.rejects(() => workflow('request', missingResourceId), /passed General test/);
});

await check('Resource saves controlled education, graduation year and three independent dates', async () => {
  await claim('authenticated');
  await ownResource(resourceId);
  const saved = await portalSave({
    education: {
      degree_level: "Master's degree",
      degree_type: 'Translation / language degree',
      field_of_study_category: 'Translation and Interpreting',
      field_of_study_other: null,
      institution: 'Test University', country: 'Norway', end_year: 2018,
    },
    translation_professional_since: '2018-05-01',
    revision_professional_since: '2020-07-01',
    mtpe_professional_since: '2022-01-01',
  });
  assert.equal(saved.status, 'In progress');
  assert.equal(saved.education.graduation_year, 2018);
  assert.equal(saved.education.review_status, 'Pending review');
  assert.notEqual(saved.professional_experience.translation.total_months,
    saved.professional_experience.revision.total_months);
  assert.notEqual(saved.professional_experience.revision.total_months,
    saved.professional_experience.mtpe.total_months);
});

let diplomaId;
let cvId;
await check('exact linked Resource can upload own diploma/CV but another Resource cannot', async () => {
  const educationId = (await portalRead()).education.id;
  await claim('service_role');
  diplomaId = await publishEvidence(externalProfileId, resourceId,
    'Diploma / certificate', educationId);
  cvId = await publishEvidence(externalProfileId, resourceId, 'CV');
  await assert.rejects(() => fileDispatch(
    'authorize_download', otherProfileId, cvId, null, {file_action: 'View'},
  ), /Compliance file not found/);
  const own = await fileDispatch(
    'authorize_download', externalProfileId, cvId, null, {file_action: 'View'},
  );
  assert.equal(own.file_id, cvId);
});

await check('Resource can submit complete upload evidence but cannot mark it reviewed', async () => {
  await claim('authenticated');
  await ownResource(resourceId);
  const submitted = (await db.query(
    'SELECT public.resource_portal_submit_compliance_048() AS value',
  )).rows[0].value;
  assert.equal(submitted.status, 'Submitted');
  assert.equal(submitted.editable, false);
  await claim('service_role');
  await assert.rejects(() => fileDispatch('review_evidence', externalProfileId, cvId),
    /Operational access required/);
});

await check('internal review and completion are required before Compliance becomes Valid', async () => {
  await claim('service_role');
  await fileDispatch('review_evidence', adminId, diplomaId);
  await fileDispatch('review_evidence', adminId, cvId);
  await companyRole('admin');
  const currentEducation = (await db.query(`
    SELECT id,degree_level,degree_type,field_of_study_category,
      field_of_study_other,institution,country,end_year
    FROM resource_education WHERE resource_id=$1 AND is_highest_relevant
  `, [resourceId])).rows[0];
  await db.query(`SELECT public.save_resource_education_048($1,$2,$3)`, [
    resourceId, currentEducation.id,
    JSON.stringify({...currentEducation, verified: true, is_highest_relevant: true}),
  ]);
  const completed = await workflow('complete', resourceId);
  assert.equal(completed.status, 'Complete');
  const {rows: [row]} = await db.query(
    'SELECT compliance_phase_status,compliance_status FROM resources WHERE id=$1',
    [resourceId],
  );
  assert.deepEqual(row, {compliance_phase_status: 'Complete', compliance_status: 'Valid'});
});

await check('changes reopen only the Resource form and do not expose ISO', async () => {
  await claim('service_role');
  const changed = await workflow('request_changes', resourceId, 'Correct the graduation year.');
  assert.equal(changed.status, 'Changes required');
  await claim('authenticated');
  await ownResource(resourceId);
  const portal = await portalRead();
  assert.equal(portal.editable, true);
  assert.equal(portal.change_reason, 'Correct the graduation year.');
  assert.equal('iso_eligibility' in portal, false);
});

await check('missing upload evidence cannot be submitted', async () => {
  await claim('service_role');
  // A passed normal test already exists for this Resource.
  await workflow('request', otherResourceId);
  await claim('authenticated');
  await ownResource(otherResourceId);
  await portalSave({
    education: {
      degree_level: 'No university degree', degree_type: 'No university degree',
    },
    translation_professional_since: '2016-01-01',
  });
  await assert.rejects(() => db.query(
    'SELECT public.resource_portal_submit_compliance_048()',
  ), /Upload at least one CV/);
});

await check('Approved Jobs provide quantities by unit, including flat-rate quantity, never money', async () => {
  const accountId = (await db.query(
    "INSERT INTO client_accounts(name) VALUES('Test Account') RETURNING id",
  )).rows[0].id;
  const projectId = (await db.query(
    'INSERT INTO projects(account_id) VALUES($1) RETURNING id', [accountId],
  )).rows[0].id;
  for (const [number, quantity, unit, amount] of [
    ['J-WORDS', 1200, 'Source words', 300],
    ['J-HOURS', 4.5, 'Hours', 500],
    ['J-FLAT', 2, 'Fixed fee', 900],
  ]) await db.query(`
    INSERT INTO project_jobs(
      project_id,job_number,resource_id,service_type,source_language,
      target_language,status,approved_at,quantity,unit,supplier_rate,
      supplier_currency,supplier_amount
    ) VALUES($1,$2,$3,'Translation','English','Norwegian','Approved',now(),$4,$5,999,'EUR',$6)
  `, [projectId, number, resourceId, quantity, unit, amount]);
  await companyRole('admin');
  const {rows} = await db.query(
    'SELECT * FROM public.resource_account_job_qualifications_048($1)', [resourceId],
  );
  assert.equal(rows.length, 1);
  const jobs = rows[0].approved_jobs;
  assert.deepEqual(jobs.map(job => job.unit).sort(), ['Flat rate', 'Hours', 'Source words']);
  assert.equal(jobs.find(job => job.unit === 'Flat rate').quantity, 2);
  for (const job of jobs) {
    assert.equal('supplier_amount' in job, false);
    assert.equal('supplier_rate' in job, false);
    assert.equal('currency' in job, false);
  }
});

await check('Compliance phase does not gate work before submission/completion', async () => {
  await db.query(`
    INSERT INTO project_jobs(
      project_id,job_number,resource_id,service_type,status,quantity,unit
    ) SELECT project_id,'J-WORKS-EARLY',$1,'Revision','In Progress',250,'Source words'
      FROM project_jobs LIMIT 1
  `, [otherResourceId]);
  const {rows: [row]} = await db.query(
    "SELECT count(*)::int AS count FROM project_jobs WHERE resource_id=$1 AND status='In Progress'",
    [otherResourceId],
  );
  assert.equal(row.count, 1);
  const state = (await db.query(
    'SELECT compliance_phase_status FROM resources WHERE id=$1', [otherResourceId],
  )).rows[0].compliance_phase_status;
  assert.equal(state, 'In progress');
});

await check('existing Resource records still load with default workflow and no fabricated qualification', async () => {
  const id = await insertResource('EXISTING');
  await companyRole('admin');
  const summary = (await db.query(
    'SELECT public.resource_compliance_workflow_summary_048($1) AS value', [id],
  )).rows[0].value;
  assert.equal(summary.status, 'Not requested');
  assert.equal(summary.successful_general_test, false);
  assert.equal(summary.completion_check.complete, false);
});

await check('forward migration is idempotent and the read-only audit passes', async () => {
  await claim('service_role');
  await db.exec(read('tms/migrations/048_compliance_phase_tests_and_job_qualifications.sql'));
  const audit = await db.query(read('tms/audits/010_update_049_compliance_workflow_audit.sql'));
  for (const row of audit.rows) assert.equal(row.result, 'PASS', row.check_name);
});

console.log(`${passed} Update 049 Compliance workflow database checks passed`);
await db.close();
