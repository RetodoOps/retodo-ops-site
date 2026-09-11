-- RetodoOps TMS — Update 046 / R2 server-role compatibility audit
-- Run after 045_r2_server_role_claim_compatibility.sql.
-- Read-only. Every result row must be PASS.

-- 1. All five server-only functions use Supabase's verified auth.role()
-- accessor and retain the hardened function/execution boundary.
WITH required(signature) AS (
    VALUES
      ('public.r2_file_dispatch_044(text,uuid,uuid,uuid,jsonb)'),
      ('public.system_enqueue_due_file_lifecycle_044()'),
      ('public.system_claim_file_lifecycle_044()'),
      ('public.system_complete_file_lifecycle_044(uuid,jsonb)'),
      ('public.system_fail_file_lifecycle_044(uuid,text)')
), definitions AS (
    SELECT required.signature,
           to_regprocedure(required.signature) AS oid
    FROM required
)
SELECT signature,
       CASE
           WHEN definitions.oid IS NULL THEN 'FAIL: function missing'
           WHEN NOT procedure.prosecdef THEN 'FAIL: not SECURITY DEFINER'
           WHEN NOT EXISTS (
               SELECT 1
               FROM unnest(COALESCE(procedure.proconfig, ARRAY[]::TEXT[])) setting
               WHERE setting LIKE 'search_path=%'
           ) THEN 'FAIL: search_path not fixed'
           WHEN pg_get_functiondef(definitions.oid)
                    NOT ILIKE '%auth.role() IS DISTINCT FROM ''service_role''%'
               THEN 'FAIL: auth.role() guard missing'
           WHEN pg_get_functiondef(definitions.oid)
                    ILIKE '%current_setting(''request.jwt.claim.role''%'
               THEN 'FAIL: legacy per-claim role read remains'
           WHEN NOT has_function_privilege('service_role', definitions.oid, 'EXECUTE')
               THEN 'FAIL: service_role cannot execute'
           WHEN has_function_privilege('authenticated', definitions.oid, 'EXECUTE')
               THEN 'FAIL: authenticated can execute'
           WHEN has_function_privilege('anon', definitions.oid, 'EXECUTE')
               THEN 'FAIL: anon can execute'
           ELSE 'PASS'
       END AS result
FROM definitions
LEFT JOIN pg_proc procedure ON procedure.oid = definitions.oid
ORDER BY signature;

-- 2. The dispatcher keeps the existing own-Job, Ready-only and operational
-- role checks. The migration changes authentication compatibility only.
WITH definition AS (
    SELECT pg_get_functiondef(
        'public.r2_file_dispatch_044(text,uuid,uuid,uuid,jsonb)'::regprocedure
    ) AS body
)
SELECT 'R2 dispatcher authorization semantics' AS check_name,
       CASE
           WHEN body NOT ILIKE '%v_role NOT IN (''admin'', ''pm'', ''client_relations'')%'
               THEN 'FAIL: staff role boundary missing'
           WHEN body NOT ILIKE '%job.resource_id = v_resource_id%'
               THEN 'FAIL: own-Job Resource boundary missing'
           WHEN body NOT ILIKE '%file.upload_status = ''Ready''%'
               THEN 'FAIL: Ready-only download boundary missing'
           WHEN body NOT ILIKE '%file.storage_provider = ''Cloudflare R2''%'
               THEN 'FAIL: R2 provider boundary missing'
           ELSE 'PASS'
       END AS result
FROM definition;

-- 3. No Resource-facing direct write policy is introduced by Update 046.
SELECT 'no direct Resource file-table write policy' AS check_name,
       CASE WHEN EXISTS (
           SELECT 1
           FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename IN (
                 'file_records', 'file_access_logs', 'job_file_archives',
                 'file_lifecycle_tasks', 'project_file_retention'
             )
             AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
             AND (
                 COALESCE(qual, '') ILIKE '%resource%'
                 OR COALESCE(with_check, '') ILIKE '%resource%'
             )
       ) THEN 'FAIL: direct Resource write policy exists' ELSE 'PASS' END AS result;
