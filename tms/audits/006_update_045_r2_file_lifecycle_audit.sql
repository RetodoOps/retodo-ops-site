-- RetodoOps TMS — Update 045 / Cloudflare R2 lifecycle audit
-- Run after 044_cloudflare_r2_file_lifecycle.sql.
-- Every statement is read-only. Expected: every result row is PASS and every
-- query explicitly marked "0 rows" returns no rows.

-- 1. Required metadata tables exist, have RLS and expose company SELECT only.
WITH required(table_name) AS (
    VALUES ('file_retention_policies'), ('project_file_retention'),
           ('job_file_archives'), ('file_lifecycle_tasks')
)
SELECT required.table_name,
       CASE
           WHEN table_row.oid IS NULL THEN 'FAIL: table missing'
           WHEN NOT table_row.relrowsecurity THEN 'FAIL: RLS disabled'
           WHEN NOT EXISTS (
               SELECT 1 FROM pg_policies policy
               WHERE policy.schemaname = 'public'
                 AND policy.tablename = required.table_name
                 AND policy.cmd = 'SELECT'
                 AND COALESCE(policy.qual, '') ILIKE '%is_company_user%'
           ) THEN 'FAIL: company SELECT policy missing'
           WHEN EXISTS (
               SELECT 1 FROM pg_policies policy
               WHERE policy.schemaname = 'public'
                 AND policy.tablename = required.table_name
                 AND policy.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
           ) THEN 'FAIL: direct write policy exists'
           ELSE 'PASS'
       END AS result
FROM required
LEFT JOIN pg_namespace namespace ON namespace.nspname = 'public'
LEFT JOIN pg_class table_row
  ON table_row.relnamespace = namespace.oid
 AND table_row.relname = required.table_name
ORDER BY required.table_name;

-- 2. Server-only functions must be SECURITY DEFINER, fixed-search-path and
-- executable by service_role but not browser roles.
WITH required(signature) AS (
    VALUES
      ('public.r2_file_dispatch_044(text,uuid,uuid,uuid,jsonb)'),
      ('public.system_enqueue_due_file_lifecycle_044()'),
      ('public.system_claim_file_lifecycle_044()'),
      ('public.system_complete_file_lifecycle_044(uuid,jsonb)'),
      ('public.system_fail_file_lifecycle_044(uuid,text)')
), resolved AS (
    SELECT signature, to_regprocedure(signature) AS oid FROM required
)
SELECT signature,
       CASE
           WHEN resolved.oid IS NULL THEN 'FAIL: function missing'
           WHEN NOT procedure.prosecdef THEN 'FAIL: not SECURITY DEFINER'
           WHEN NOT EXISTS (
               SELECT 1 FROM unnest(COALESCE(procedure.proconfig, ARRAY[]::TEXT[])) setting
               WHERE setting LIKE 'search_path=%'
           ) THEN 'FAIL: search_path not fixed'
           WHEN NOT has_function_privilege('service_role', resolved.oid, 'EXECUTE')
               THEN 'FAIL: service_role cannot execute'
           WHEN has_function_privilege('authenticated', resolved.oid, 'EXECUTE')
               THEN 'FAIL: browser role can execute'
           WHEN has_function_privilege('anon', resolved.oid, 'EXECUTE')
               THEN 'FAIL: anon can execute'
           ELSE 'PASS'
       END AS result
FROM resolved
LEFT JOIN pg_proc procedure ON procedure.oid = resolved.oid
ORDER BY signature;

-- 3. Browser-facing settings/summary RPCs retain explicit role guards.
WITH required(signature, guard) AS (
    VALUES
      ('public.file_retention_settings_044()', 'is_company_user'),
      ('public.staff_job_file_lifecycle_044(uuid)', 'is_company_user'),
      ('public.admin_save_file_retention_policy_044(text,uuid,integer,integer,boolean,text)', 'is_admin'),
      ('public.admin_delete_file_retention_policy_044(uuid)', 'is_admin'),
      ('public.admin_set_project_file_hold_044(uuid,boolean,text)', 'is_admin')
), definitions AS (
    SELECT required.signature, required.guard,
           to_regprocedure(required.signature) AS oid
    FROM required
)
SELECT signature,
       CASE
           WHEN oid IS NULL THEN 'FAIL: function missing'
           WHEN pg_get_functiondef(oid) NOT ILIKE '%' || guard || '%'
               THEN 'FAIL: role guard missing'
           WHEN NOT has_function_privilege('authenticated', oid, 'EXECUTE')
               THEN 'FAIL: authenticated cannot execute guarded RPC'
           WHEN has_function_privilege('anon', oid, 'EXECUTE')
               THEN 'FAIL: anon can execute'
           ELSE 'PASS'
       END AS result
FROM definitions
ORDER BY signature;

-- 4. R2 and lifecycle allowlists are installed.
WITH constraints AS (
    SELECT constraint_row.conname, pg_get_constraintdef(constraint_row.oid) AS definition
    FROM pg_constraint constraint_row
    WHERE constraint_row.conrelid IN (
        'public.file_records'::regclass, 'public.file_access_logs'::regclass
    )
)
SELECT 'Cloudflare R2 provider' AS check_name,
       CASE WHEN EXISTS (
           SELECT 1 FROM constraints
           WHERE conname = 'file_records_storage_provider_check'
             AND definition ILIKE '%Cloudflare R2%'
       ) THEN 'PASS' ELSE 'FAIL: R2 provider allowlist missing' END AS result
UNION ALL
SELECT 'complete file lifecycle states',
       CASE WHEN EXISTS (
           SELECT 1 FROM constraints
           WHERE conname = 'file_records_upload_status_check'
             AND definition ILIKE '%Archiving%'
             AND definition ILIKE '%Restoring%'
             AND definition ILIKE '%Deleted%'
       ) THEN 'PASS' ELSE 'FAIL: lifecycle state allowlist incomplete' END
UNION ALL
SELECT 'immutable restore audit action',
       CASE WHEN EXISTS (
           SELECT 1 FROM constraints
           WHERE conname = 'file_access_logs_action_check'
             AND definition ILIKE '%Restore%'
       ) THEN 'PASS' ELSE 'FAIL: Restore audit action missing' END;

-- 5. Locked default must be exactly 3 months to archive and 24 months of
-- continuous Archived state before binary deletion.
SELECT 'default 3/24 retention policy' AS check_name,
       CASE
           WHEN count(*) <> 1 THEN 'FAIL: expected exactly one default policy'
           WHEN min(archive_after_months) <> 3 THEN 'FAIL: archive default is not 3 months'
           WHEN min(delete_after_months) <> 24 THEN 'FAIL: delete default is not 24 months'
           ELSE 'PASS'
       END AS result
FROM public.file_retention_policies
WHERE scope_type = 'Default';

-- 6. Project approval trigger and reversible/cancellable semantics are present.
WITH definition AS (
    SELECT pg_get_functiondef(
        'public.track_project_file_retention_044()'::regprocedure
    ) AS body
)
SELECT CASE
    WHEN NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.projects'::regclass
          AND tgname = 'projects_track_file_retention_044'
          AND NOT tgisinternal
    ) THEN 'FAIL: Project status trigger missing'
    WHEN body NOT ILIKE '%NEW.status = ''Approved''%NOW()%'
        THEN 'FAIL: latest Approved clock missing'
    WHEN body NOT ILIKE '%Automatic archive cancelled because Project left Approved%'
        THEN 'FAIL: leaving Approved does not cancel pending archive'
    ELSE 'PASS'
END AS result
FROM definition;

-- 7. Resource projections remain own-Job, Ready-only and Client-blind. The R2
-- branch must not return bucket/object coordinates.
WITH definitions AS (
    SELECT
      pg_get_functiondef('public.resource_portal_job(uuid)'::regprocedure) AS job_body,
      pg_get_functiondef('public.resource_portal_jobs()'::regprocedure) AS jobs_body,
      pg_get_functiondef('public.r2_file_dispatch_044(text,uuid,uuid,uuid,jsonb)'::regprocedure) AS dispatch_body
)
SELECT CASE
    WHEN job_body NOT ILIKE '%job.resource_id = v_resource_id%'
        THEN 'FAIL: own-Job guard missing'
    WHEN job_body NOT ILIKE '%file.upload_status = ''Ready''%'
        OR jobs_body NOT ILIKE '%file.upload_status = ''Ready''%'
        THEN 'FAIL: Ready-only Resource projection missing'
    WHEN job_body ILIKE '%''client_name''%'
        OR job_body ILIKE '%''client_price''%'
        OR job_body ILIKE '%''profit''%'
        OR job_body ILIKE '%''margin''%'
        THEN 'FAIL: forbidden Client/economic field exposed'
    WHEN job_body NOT ILIKE '%CASE WHEN file.storage_provider = ''Supabase''%'
        THEN 'FAIL: R2 coordinates are not suppressed'
    WHEN dispatch_body NOT ILIKE '%job.resource_id = v_resource_id%'
        OR dispatch_body NOT ILIKE '%file.upload_status = ''Ready''%'
        THEN 'FAIL: signed-download own-Job/state guard missing'
    ELSE 'PASS'
END AS result
FROM definitions;

-- 8. Supabase direct uploads are disabled; legacy exact-object SELECT may stay.
SELECT 'no authenticated Supabase Storage upload policy' AS check_name,
       CASE WHEN EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects'
             AND policyname = 'tms_job_files_operations_insert'
       ) THEN 'FAIL: old direct upload policy still exists' ELSE 'PASS' END AS result;

-- 9. No new direct Resource policy may exist on company/file metadata tables.
-- Expected: 0 rows.
SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'projects', 'project_scoops', 'project_jobs', 'clients', 'client_accounts',
      'file_records', 'file_access_logs', 'file_retention_policies',
      'project_file_retention', 'job_file_archives', 'file_lifecycle_tasks'
  )
  AND (
      COALESCE(qual, '') ILIKE '%current_external_resource_id%'
      OR COALESCE(qual, '') ILIKE '%role = ''resource''%'
      OR COALESCE(with_check, '') ILIKE '%current_external_resource_id%'
      OR COALESCE(with_check, '') ILIKE '%role = ''resource''%'
  );

-- 10. State/data consistency. Expected: 0 rows.
SELECT id, original_filename, upload_status, archived_at, archive_id, deleted_at
FROM public.file_records
WHERE (upload_status = 'Ready' AND archived_at IS NOT NULL)
   OR (upload_status IN ('Pending', 'Failed', 'Archived', 'Deleted') AND archived_at IS NULL)
   OR (upload_status IN ('Archiving', 'Archived', 'Restoring', 'Deleted') AND archive_id IS NULL)
   OR (upload_status = 'Deleted' AND deleted_at IS NULL)
   OR (storage_provider = 'Cloudflare R2' AND upload_status <> 'Deleted'
       AND (bucket_name IS NULL OR object_key IS NULL OR checksum_sha256 IS NULL))
ORDER BY created_at;

-- 11. No archive may be deleted/restored inconsistently. Expected: 0 rows.
SELECT id, job_id, state, strategy, archived_at, delete_due_at, restored_at, deleted_at
FROM public.job_file_archives
WHERE (state = 'Archived' AND (strategy IS NULL OR archived_at IS NULL OR delete_due_at IS NULL))
   OR (state = 'Restored' AND (restored_at IS NULL OR delete_due_at IS NOT NULL))
   OR (state = 'Deleted' AND deleted_at IS NULL)
   OR (strategy = 'zip' AND state IN ('Archived', 'Restoring')
       AND (archive_object_key IS NULL OR archive_checksum_sha256 IS NULL))
ORDER BY created_at;

-- 12. Retention Hold must suppress a due timestamp. Expected: 0 rows.
SELECT retention.project_id, retention.archive_due_at, retention.hold_reason
FROM public.project_file_retention retention
WHERE retention.retention_hold AND retention.archive_due_at IS NOT NULL;

-- 13. Crash-safe ZIP cleanup must be complete or durably queued. Expected: 0 rows.
SELECT archive.id, archive.job_id, archive.state,
       file.id AS file_id, file.source_removed_at,
       archive.archive_object_removed_at
FROM public.job_file_archives archive
LEFT JOIN public.file_records file ON file.archive_id = archive.id
WHERE archive.strategy = 'zip'
  AND (
      (archive.state = 'Archived'
       AND file.source_removed_at IS NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.file_lifecycle_tasks task
           WHERE task.archive_id = archive.id
             AND task.action = 'CleanupSources'
             AND task.status IN ('Pending', 'Processing')
       ))
      OR
      (archive.state = 'Restored'
       AND archive.archive_object_removed_at IS NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.file_lifecycle_tasks task
           WHERE task.archive_id = archive.id
             AND task.action = 'CleanupArchive'
             AND task.status IN ('Pending', 'Processing')
       ))
  );
