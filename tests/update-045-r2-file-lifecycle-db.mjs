// Isolated PostgreSQL (PGlite) fixture. No live Supabase or Cloudflare calls.
// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite module.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const file = relativePath => readFileSync(new URL(`../${relativePath}`, import.meta.url), 'utf8');
const migration = file('tms/migrations/044_cloudflare_r2_file_lifecycle.sql');
const audit = file('tms/audits/006_update_045_r2_file_lifecycle_audit.sql');

await db.exec(`
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE SCHEMA storage;

CREATE TABLE auth.users(id UUID PRIMARY KEY, email TEXT NOT NULL);
CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', TRUE), '')::UUID
$$;

CREATE TABLE public.profiles(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), full_name TEXT, role TEXT NOT NULL
);
CREATE TABLE public.clients(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT NOT NULL
);
CREATE TABLE public.client_accounts(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  name TEXT NOT NULL
);
CREATE TABLE public.projects(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_number TEXT NOT NULL, client_id UUID REFERENCES public.clients(id),
  account_id UUID REFERENCES public.client_accounts(id), status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE public.resources(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  internal_number TEXT NOT NULL, profile_id UUID REFERENCES public.profiles(id),
  resource_type TEXT NOT NULL, legal_name TEXT, company_name TEXT, email TEXT,
  portal_status TEXT NOT NULL, lifecycle_status TEXT NOT NULL
);
CREATE TABLE public.project_scoops(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES public.projects(id), scoop_number TEXT NOT NULL
);
CREATE TABLE public.specializations(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT NOT NULL
);
CREATE TABLE public.project_jobs(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES public.projects(id),
  project_scoop_id UUID NOT NULL REFERENCES public.project_scoops(id),
  resource_id UUID REFERENCES public.resources(id),
  specialization_id UUID REFERENCES public.specializations(id),
  job_number TEXT NOT NULL, status TEXT NOT NULL, service_type TEXT,
  source_language TEXT, target_language TEXT, deadline TIMESTAMPTZ,
  quantity NUMERIC, unit TEXT, assignment_notes TEXT, notes TEXT
);
CREATE TABLE public.supplier_purchase_orders(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), po_number TEXT NOT NULL,
  job_id UUID REFERENCES public.project_jobs(id), project_id UUID REFERENCES public.projects(id),
  resource_id UUID REFERENCES public.resources(id), status TEXT NOT NULL,
  current_version INTEGER DEFAULT 0, total NUMERIC DEFAULT 0, currency TEXT DEFAULT 'EUR',
  issued_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE public.supplier_po_versions(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id UUID REFERENCES public.supplier_purchase_orders(id),
  version_number INTEGER NOT NULL, snapshot JSONB NOT NULL DEFAULT '{}'::JSONB
);
CREATE TABLE public.job_issues(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), job_id UUID REFERENCES public.project_jobs(id),
  status TEXT, severity TEXT, description TEXT, resolution TEXT,
  reported_at TIMESTAMPTZ DEFAULT NOW(), resolved_at TIMESTAMPTZ
);
CREATE TABLE public.file_records(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES public.projects(id), job_id UUID REFERENCES public.project_jobs(id),
  resource_id UUID REFERENCES public.resources(id),
  storage_provider TEXT NOT NULL CONSTRAINT file_records_storage_provider_check CHECK (
    storage_provider IN ('Supabase','Google Drive','Client server','memoQ','External link')
  ),
  bucket_name TEXT, object_key TEXT, external_url TEXT, original_filename TEXT NOT NULL,
  mime_type TEXT, size_bytes BIGINT, file_role TEXT NOT NULL, checksum_sha256 TEXT,
  retention_until DATE, archived_at TIMESTAMPTZ, uploaded_by UUID REFERENCES public.profiles(id),
  upload_status TEXT NOT NULL DEFAULT 'Ready' CONSTRAINT file_records_upload_status_check
    CHECK (upload_status IN ('Pending','Ready','Archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (object_key IS NOT NULL OR external_url IS NOT NULL)
);
CREATE TABLE public.file_access_logs(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  file_record_id UUID NOT NULL REFERENCES public.file_records(id),
  profile_id UUID REFERENCES public.profiles(id), resource_id UUID REFERENCES public.resources(id),
  action TEXT NOT NULL CONSTRAINT file_access_logs_action_check
    CHECK (action IN ('View','Download','Upload','Archive','Delete')),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE public.audit_events(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), actor_id UUID REFERENCES public.profiles(id),
  entity_type TEXT NOT NULL, entity_id UUID, action TEXT NOT NULL,
  before_values JSONB, after_values JSONB, reason TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE storage.objects(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id TEXT, name TEXT);

CREATE FUNCTION public.current_app_role() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT role FROM public.profiles WHERE id=auth.uid()
$$;
CREATE FUNCTION public.is_admin() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT COALESCE(public.current_app_role()='admin',FALSE)
$$;
CREATE FUNCTION public.is_company_user() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT COALESCE(public.current_app_role() IN ('admin','pm','qa','client_relations'),FALSE)
$$;
CREATE FUNCTION public.current_external_resource_id() RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT resource.id FROM public.resources resource
  JOIN public.profiles profile ON profile.id=resource.profile_id
  JOIN auth.users app_user ON app_user.id=profile.id
  WHERE profile.id=auth.uid() AND profile.role='resource'
    AND lower(app_user.email)=lower(resource.email)
    AND resource.portal_status IN ('Active','Read-only')
    AND resource.lifecycle_status IN ('Active','On leave') LIMIT 1
$$;
CREATE FUNCTION public.set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at=NOW(); RETURN NEW; END
$$;
CREATE FUNCTION public.append_trusted_tms_audit_event(
  p_entity_type TEXT,p_entity_id UUID,p_action TEXT,p_before JSONB,p_after JSONB,p_reason TEXT
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO public.audit_events(actor_id,entity_type,entity_id,action,before_values,after_values,reason)
  VALUES(auth.uid(),p_entity_type,p_entity_id,p_action,p_before,p_after,p_reason)
  RETURNING id INTO v_id; RETURN v_id;
END
$$;

GRANT USAGE ON SCHEMA public,auth,storage TO authenticated,service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO authenticated,service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA auth TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public,auth TO authenticated,service_role;
`);

const {rows: [admin]} = await db.query(
  "INSERT INTO public.profiles(full_name,role) VALUES('Admin','admin') RETURNING id",
);
const {rows: [resourceProfile]} = await db.query(
  "INSERT INTO public.profiles(full_name,role) VALUES('Resource','resource') RETURNING id",
);
await db.query("INSERT INTO auth.users(id,email) VALUES($1,'resource@example.com')", [resourceProfile.id]);
const {rows: [client]} = await db.query(
  "INSERT INTO public.clients(name) VALUES('Hidden Client') RETURNING id",
);
const {rows: [account]} = await db.query(
  "INSERT INTO public.client_accounts(client_id,name) VALUES($1,'Hidden Account') RETURNING id",
  [client.id],
);
const {rows: [project]} = await db.query(`
  INSERT INTO public.projects(project_number,client_id,account_id,status)
  VALUES('260910_TEST',$1,$2,'Ongoing') RETURNING id
`, [client.id, account.id]);
const {rows: [resource]} = await db.query(`
  INSERT INTO public.resources(
    internal_number,profile_id,resource_type,legal_name,email,portal_status,lifecycle_status
  ) VALUES('RO-EXT-001',$1,'Freelancer','Resource','resource@example.com','Active','Active')
  RETURNING id
`, [resourceProfile.id]);
const {rows: [scoop]} = await db.query(
  "INSERT INTO public.project_scoops(project_id,scoop_number) VALUES($1,'260910_TEST-S01') RETURNING id",
  [project.id],
);
const {rows: [job]} = await db.query(`
  INSERT INTO public.project_jobs(project_id,project_scoop_id,resource_id,job_number,status)
  VALUES($1,$2,$3,'260910_TEST-S01-TRA_J01','Assigned') RETURNING id
`, [project.id, scoop.id, resource.id]);

await db.exec(migration);

let passed = 0;
async function check(name, callback) {
  await callback(); passed += 1; console.log(`PASS ${name}`);
}
async function setActor(id, databaseRole, jwtRole = databaseRole) {
  await db.exec('RESET ROLE');
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,FALSE)", [id || '']);
  await db.query("SELECT set_config('request.jwt.claim.role',$1,FALSE)", [jwtRole || '']);
  await db.exec(`SET ROLE ${databaseRole}`);
}
async function resetActor() {
  await db.exec('RESET ROLE');
  await db.query("SELECT set_config('request.jwt.claim.sub','',FALSE)");
  await db.query("SELECT set_config('request.jwt.claim.role','',FALSE)");
}

await check('default retention is 3/24 and new tables have RLS', async () => {
  const {rows: [policy]} = await db.query(
    "SELECT archive_after_months,delete_after_months FROM public.file_retention_policies WHERE scope_type='Default'",
  );
  assert.equal(policy.archive_after_months, 3);
  assert.equal(policy.delete_after_months, 24);
  const {rows} = await db.query(`
    SELECT relname,relrowsecurity FROM pg_class
    WHERE relnamespace='public'::regnamespace
      AND relname IN ('file_retention_policies','project_file_retention','job_file_archives','file_lifecycle_tasks')
  `);
  assert.equal(rows.length, 4); assert.ok(rows.every(row => row.relrowsecurity));
});

await check('Project approval starts and leaving Approved cancels the archive clock', async () => {
  await setActor(admin.id, 'authenticated');
  await db.query("UPDATE public.projects SET status='Approved' WHERE id=$1", [project.id]);
  let result = await db.query(
    'SELECT last_approved_at,archive_due_at FROM public.project_file_retention WHERE project_id=$1',
    [project.id],
  );
  assert.ok(result.rows[0].last_approved_at); assert.ok(result.rows[0].archive_due_at);
  await db.query("UPDATE public.projects SET status='Ongoing' WHERE id=$1", [project.id]);
  result = await db.query(
    'SELECT archive_due_at FROM public.project_file_retention WHERE project_id=$1', [project.id],
  );
  assert.equal(result.rows[0].archive_due_at, null);
});

await check('only Admin can save a Client/Account policy or Retention Hold', async () => {
  await setActor(admin.id, 'authenticated');
  await db.query(`SELECT public.admin_save_file_retention_policy_044(
    'Account',$1,4,30,TRUE,'Contractual evidence hold'
  )`, [account.id]);
  const {rows: [effective]} = await db.query(
    'SELECT public.staff_job_file_lifecycle_044($1) AS policy', [job.id],
  );
  assert.equal(effective.policy.archive_after_months, 4);
  assert.equal(effective.policy.delete_after_months, 30);
  assert.equal(effective.policy.retention_hold, true);
  await db.query(`SELECT public.admin_save_file_retention_policy_044(
    'Account',$1,3,24,FALSE,NULL
  )`, [account.id]);
});

let fileId;
let task;
await check('server dispatcher creates a verified R2 record without exposing Client identity', async () => {
  await setActor('', 'service_role', 'service_role');
  const checksum = 'ab'.repeat(32);
  const {rows: [prepared]} = await db.query(`
    SELECT public.r2_file_dispatch_044(
      'prepare_upload',$1,NULL,$2,$3::JSONB
    ) AS ticket
  `, [admin.id, job.id, JSON.stringify({
    original_filename: 'Client source.txt', mime_type: 'text/plain', size_bytes: 4096,
    file_role: 'Source', checksum_sha256: checksum, bucket_name: 'retodo-private-files',
  })]);
  fileId = prepared.ticket.file_id;
  assert.match(prepared.ticket.object_key, new RegExp(`^active/projects/${project.id}/jobs/${job.id}/${fileId}/`));
  assert.doesNotMatch(prepared.ticket.object_key, /Hidden Client|Hidden Account/);
  await db.query(`SELECT public.r2_file_dispatch_044(
    'publish_upload',$1,$2,NULL,$3::JSONB
  )`, [admin.id, fileId, JSON.stringify({
    verified_size_bytes: 4096, verified_checksum_sha256: checksum,
    r2_etag: 'etag', storage_class: 'STANDARD',
  })]);
  const {rows: [record]} = await db.query(
    'SELECT storage_provider,upload_status,archived_at,verified_at FROM public.file_records WHERE id=$1',
    [fileId],
  );
  assert.equal(record.storage_provider, 'Cloudflare R2');
  assert.equal(record.upload_status, 'Ready'); assert.equal(record.archived_at, null); assert.ok(record.verified_at);
});

await check('signed-download authorization is own-Job and immutable-log backed', async () => {
  await setActor('', 'service_role', 'service_role');
  const {rows: [authorized]} = await db.query(`SELECT public.r2_file_dispatch_044(
    'authorize_download',$1,$2,NULL,'{"file_action":"Download"}'::JSONB
  ) AS ticket`, [resourceProfile.id, fileId]);
  assert.equal(authorized.ticket.file_id, fileId);
  const {rows: [log]} = await db.query(
    "SELECT count(*)::INTEGER AS count FROM public.file_access_logs WHERE file_record_id=$1 AND action='Download'",
    [fileId],
  );
  assert.equal(log.count, 1);
});

await check('archive then restore preserves metadata and resets active access', async () => {
  await setActor('', 'service_role', 'service_role');
  await db.query("SELECT public.r2_file_dispatch_044('queue_archive',$1,NULL,$2,'{}'::JSONB)", [admin.id, job.id]);
  ({rows: [task]} = await db.query('SELECT public.system_claim_file_lifecycle_044() AS task'));
  assert.equal(task.task.action, 'Archive');
  const manifest = {
    format: 'retodo-job-archive-v1', project_id: project.id, job_id: job.id,
    archive_id: task.task.archive_id, files: task.task.files,
  };
  await db.query(`SELECT public.system_complete_file_lifecycle_044($1,$2::JSONB)`, [
    task.task.task_id, JSON.stringify({
      strategy: 'infrequent', manifest, manifest_sha256: 'cd'.repeat(32),
      archive_object_key: null, archive_checksum_sha256: null,
      original_size_bytes: 4096, archive_size_bytes: 4096,
      file_count: 1, storage_class: 'STANDARD_IA',
    }),
  ]);
  let result = await db.query(
    'SELECT upload_status,archived_at,storage_class FROM public.file_records WHERE id=$1', [fileId],
  );
  assert.equal(result.rows[0].upload_status, 'Archived'); assert.ok(result.rows[0].archived_at);
  assert.equal(result.rows[0].storage_class, 'STANDARD_IA');
  await assert.rejects(() => db.query(`SELECT public.r2_file_dispatch_044(
    'authorize_download',$1,$2,NULL,'{}'::JSONB
  )`, [resourceProfile.id, fileId]), /Job file not found/);

  await db.query("SELECT public.r2_file_dispatch_044('queue_restore',$1,NULL,$2,'{}'::JSONB)", [admin.id, job.id]);
  ({rows: [task]} = await db.query('SELECT public.system_claim_file_lifecycle_044() AS task'));
  assert.equal(task.task.action, 'Restore');
  await db.query(`SELECT public.system_complete_file_lifecycle_044($1,$2::JSONB)`, [
    task.task.task_id, JSON.stringify({strategy:'infrequent',restored_file_count:1,storage_class:'STANDARD'}),
  ]);
  result = await db.query(
    'SELECT upload_status,archived_at,archive_id,storage_class FROM public.file_records WHERE id=$1', [fileId],
  );
  assert.equal(result.rows[0].upload_status, 'Ready'); assert.equal(result.rows[0].archived_at, null);
  assert.equal(result.rows[0].archive_id, null); assert.equal(result.rows[0].storage_class, 'STANDARD');
});

await check('ZIP archive and restore use crash-safe verified cleanup phases', async () => {
  await setActor('', 'service_role', 'service_role');
  await db.query("SELECT public.r2_file_dispatch_044('queue_archive',$1,NULL,$2,'{}'::JSONB)", [admin.id, job.id]);
  ({rows: [task]} = await db.query('SELECT public.system_claim_file_lifecycle_044() AS task'));
  assert.equal(task.task.action, 'Archive');
  const archiveId = task.task.archive_id;
  const manifest = {
    format: 'retodo-job-archive-v1', project_id: project.id, job_id: job.id,
    archive_id: archiveId, files: task.task.files,
  };
  await db.query(`SELECT public.system_complete_file_lifecycle_044($1,$2::JSONB)`, [
    task.task.task_id, JSON.stringify({
      strategy: 'zip', manifest, manifest_sha256: 'cd'.repeat(32),
      archive_object_key: task.task.archive_object_key,
      archive_checksum_sha256: 'ef'.repeat(32), original_size_bytes: 4096,
      archive_size_bytes: 2048, file_count: 1, storage_class: 'STANDARD_IA',
    }),
  ]);
  let result = await db.query(
    'SELECT upload_status,source_removed_at FROM public.file_records WHERE id=$1', [fileId],
  );
  assert.equal(result.rows[0].upload_status, 'Archived');
  assert.equal(result.rows[0].source_removed_at, null);

  ({rows: [task]} = await db.query('SELECT public.system_claim_file_lifecycle_044() AS task'));
  assert.equal(task.task.action, 'CleanupSources');
  assert.equal(task.task.manifest.files.length, 1);
  await db.query(`SELECT public.system_complete_file_lifecycle_044($1,$2::JSONB)`, [
    task.task.task_id, JSON.stringify({strategy: 'zip', cleaned_file_count: 1}),
  ]);
  result = await db.query('SELECT source_removed_at FROM public.file_records WHERE id=$1', [fileId]);
  assert.ok(result.rows[0].source_removed_at);

  await db.query("SELECT public.r2_file_dispatch_044('queue_restore',$1,NULL,$2,'{}'::JSONB)", [admin.id, job.id]);
  ({rows: [task]} = await db.query('SELECT public.system_claim_file_lifecycle_044() AS task'));
  assert.equal(task.task.action, 'Restore');
  await db.query(`SELECT public.system_complete_file_lifecycle_044($1,$2::JSONB)`, [
    task.task.task_id, JSON.stringify({strategy: 'zip', restored_file_count: 1, storage_class: 'STANDARD'}),
  ]);
  await resetActor();
  result = await db.query(
    'SELECT state,archive_object_removed_at FROM public.job_file_archives WHERE id=$1', [archiveId],
  );
  assert.equal(result.rows[0].state, 'Restored');
  assert.equal(result.rows[0].archive_object_removed_at, null);

  await setActor('', 'service_role', 'service_role');
  ({rows: [task]} = await db.query('SELECT public.system_claim_file_lifecycle_044() AS task'));
  assert.equal(task.task.action, 'CleanupArchive');
  assert.equal(task.task.files.length, 1);
  await db.query(`SELECT public.system_complete_file_lifecycle_044($1,$2::JSONB)`, [
    task.task.task_id, JSON.stringify({strategy: 'zip', cleaned_archive_count: 1}),
  ]);
  await resetActor();
  result = await db.query(
    'SELECT archive_object_removed_at FROM public.job_file_archives WHERE id=$1', [archiveId],
  );
  assert.ok(result.rows[0].archive_object_removed_at);
});

await check('read-only database audit reports only PASS or empty exception sets', async () => {
  await resetActor();
  const results = await db.exec(audit);
  assert.ok(results.length >= 12);
  for (const result of results) {
    const rows = result.rows || [];
    if (rows.some(row => Object.hasOwn(row, 'result'))) {
      for (const row of rows) assert.equal(row.result, 'PASS');
    } else {
      assert.equal(rows.length, 0);
    }
  }
});

await resetActor();
await db.close();
assert.equal(passed, 8);
console.log(`Update 045 isolated database tests passed: ${passed}`);
