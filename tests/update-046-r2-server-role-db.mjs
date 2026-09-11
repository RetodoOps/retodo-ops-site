// Isolated PostgreSQL regression for Update 046. No live Supabase or R2 calls.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const file = relativePath => readFileSync(new URL(`../${relativePath}`, import.meta.url), 'utf8');
const migration = file('tms/migrations/045_r2_server_role_claim_compatibility.sql');
const audit = file('tms/audits/007_update_046_r2_server_role_audit.sql');

await db.exec(`
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;

CREATE FUNCTION auth.role() RETURNS TEXT
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', TRUE), ''),
    NULLIF(current_setting('request.jwt.claims', TRUE), '')::JSONB ->> 'role'
  )
$$;

CREATE FUNCTION public.r2_file_dispatch_044(
  p_action TEXT, p_actor_id UUID, p_file_id UUID DEFAULT NULL,
  p_job_id UUID DEFAULT NULL, p_payload JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,auth,pg_temp AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  -- Preserved production authorization markers checked by the audit fixture:
  -- v_role NOT IN ('admin', 'pm', 'client_relations')
  -- job.resource_id = v_resource_id
  -- file.upload_status = 'Ready'
  -- file.storage_provider = 'Cloudflare R2'
  RETURN jsonb_build_object('action', p_action, 'authorized', TRUE);
END
$$;

CREATE FUNCTION public.system_enqueue_due_file_lifecycle_044()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  RETURN '{"authorized":true}'::JSONB;
END
$$;

CREATE FUNCTION public.system_claim_file_lifecycle_044()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  RETURN '{"authorized":true}'::JSONB;
END
$$;

CREATE FUNCTION public.system_complete_file_lifecycle_044(p_task_id UUID, p_result JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  RETURN jsonb_build_object('task_id', p_task_id, 'authorized', TRUE);
END
$$;

CREATE FUNCTION public.system_fail_file_lifecycle_044(p_task_id UUID, p_error TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  RETURN jsonb_build_object('task_id', p_task_id, 'authorized', TRUE);
END
$$;

REVOKE ALL ON FUNCTION public.r2_file_dispatch_044(TEXT,UUID,UUID,UUID,JSONB)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.system_enqueue_due_file_lifecycle_044()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.system_claim_file_lifecycle_044()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.system_complete_file_lifecycle_044(UUID,JSONB)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.system_fail_file_lifecycle_044(UUID,TEXT)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;
`);

await db.query("SELECT set_config('request.jwt.claim.role','',FALSE)");
await db.query("SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)");

await assert.rejects(
  () => db.query("SELECT public.r2_file_dispatch_044('prepare_upload',gen_random_uuid())"),
  /Service role required/,
);

await db.exec(migration);

const calls = [
  "SELECT public.r2_file_dispatch_044('prepare_upload',gen_random_uuid()) AS value",
  'SELECT public.system_enqueue_due_file_lifecycle_044() AS value',
  'SELECT public.system_claim_file_lifecycle_044() AS value',
  "SELECT public.system_complete_file_lifecycle_044(gen_random_uuid(),'{}') AS value",
  "SELECT public.system_fail_file_lifecycle_044(gen_random_uuid(),'test') AS value",
];
for (const sql of calls) {
  const {rows: [row]} = await db.query(sql);
  assert.equal(row.value.authorized, true);
}

// The forward migration is deliberately safe to re-run.
await db.exec(migration);

await db.query("SELECT set_config('request.jwt.claims','{\"role\":\"authenticated\"}',FALSE)");
await assert.rejects(
  () => db.query("SELECT public.r2_file_dispatch_044('download',gen_random_uuid())"),
  /Service role required/,
);

await db.query("SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)");
const results = await db.exec(audit);
for (const result of results) {
  for (const row of result.rows || []) assert.equal(row.result, 'PASS');
}

await db.close();
console.log('Update 046 JSON-claims server-role database regression passed');
