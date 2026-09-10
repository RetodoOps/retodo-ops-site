-- RetodoOps TMS — Update 044 / Job files, issues and active PO audit
-- Run after 042_job_files_issues_staff_workflow.sql.
-- Every statement is read-only. Expected: every result row is PASS and every
-- explicitly marked exception query returns 0 rows.

-- 1. Browser-facing functions must be SECURITY DEFINER, use a fixed
-- search_path, allow authenticated callers and deny anon.
WITH required(signature, expected_volatility) AS (
    VALUES
        ('public.resource_portal_context()', 's'),
        ('public.resource_portal_jobs()', 's'),
        ('public.resource_portal_purchase_orders()', 's'),
        ('public.staff_prepare_job_file_upload(uuid,text,text,bigint,text,text)', 'v'),
        ('public.staff_publish_job_file_upload(uuid)', 'v'),
        ('public.staff_archive_job_file(uuid)', 'v'),
        ('public.staff_create_job_issue(uuid,text,text)', 'v'),
        ('public.staff_update_job_issue(uuid,text,text,text,text)', 'v')
), resolved AS (
    SELECT signature, expected_volatility,
           to_regprocedure(signature) AS function_oid
    FROM required
)
SELECT resolved.signature,
       CASE
           WHEN resolved.function_oid IS NULL THEN 'FAIL: missing function'
           WHEN NOT function_row.prosecdef THEN 'FAIL: not SECURITY DEFINER'
           WHEN function_row.provolatile <> resolved.expected_volatility::"char"
               THEN 'FAIL: unexpected volatility'
           WHEN NOT EXISTS (
               SELECT 1
               FROM unnest(COALESCE(function_row.proconfig, ARRAY[]::TEXT[])) setting
               WHERE setting LIKE 'search_path=%'
           ) THEN 'FAIL: search_path not fixed'
           WHEN NOT has_function_privilege(
               'authenticated', resolved.function_oid, 'EXECUTE'
           ) THEN 'FAIL: authenticated cannot execute'
           WHEN has_function_privilege('anon', resolved.function_oid, 'EXECUTE')
               THEN 'FAIL: anon can execute'
           ELSE 'PASS'
       END AS result
FROM resolved
LEFT JOIN pg_proc function_row ON function_row.oid = resolved.function_oid
ORDER BY resolved.signature;

-- 2. Every staff mutation must perform the operational-role check inside the
-- trusted function. Expected: 5 PASS rows.
WITH required(function_name) AS (
    VALUES
        ('staff_prepare_job_file_upload'),
        ('staff_publish_job_file_upload'),
        ('staff_archive_job_file'),
        ('staff_create_job_issue'),
        ('staff_update_job_issue')
), installed AS (
    SELECT function_row.proname AS function_name,
           pg_get_functiondef(function_row.oid) AS definition
    FROM pg_proc function_row
    JOIN pg_namespace namespace ON namespace.oid = function_row.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_row.proname LIKE 'staff_%job_%'
)
SELECT required.function_name,
       CASE
           WHEN installed.function_name IS NULL THEN 'FAIL: missing function'
           WHEN installed.definition NOT ILIKE
                '%IF NOT public.can_manage_operations() THEN%'
               THEN 'FAIL: operational-role guard missing'
           ELSE 'PASS'
       END AS result
FROM required
LEFT JOIN installed USING (function_name)
ORDER BY required.function_name;

-- 3. The managed bucket must exist and remain private; the file lifecycle
-- column and allowlist constraint must be installed. Expected: 2 PASS rows.
SELECT 'private tms-job-files bucket' AS check_name,
       CASE
           WHEN bucket.id IS NULL THEN 'FAIL: bucket missing'
           WHEN bucket.public THEN 'FAIL: bucket is public'
           ELSE 'PASS'
       END AS result
FROM (VALUES ('tms-job-files')) expected(id)
LEFT JOIN storage.buckets bucket ON bucket.id = expected.id
UNION ALL
SELECT 'file_records upload_status constraint',
       CASE
           WHEN attribute.attname IS NULL THEN 'FAIL: column missing'
           WHEN constraint_row.oid IS NULL THEN 'FAIL: allowlist constraint missing'
           ELSE 'PASS'
       END
FROM (VALUES (1)) singleton(value)
LEFT JOIN pg_attribute attribute
  ON attribute.attrelid = 'public.file_records'::regclass
 AND attribute.attname = 'upload_status'
 AND NOT attribute.attisdropped
LEFT JOIN pg_constraint constraint_row
  ON constraint_row.conrelid = 'public.file_records'::regclass
 AND constraint_row.conname = 'file_records_upload_status_check';

-- 4. Expected Storage contract: own-Job Resource SELECT, company SELECT and
-- operations INSERT only. No UPDATE or DELETE policy is introduced.
WITH expected(policy_name, command, required_fragment) AS (
    VALUES
        ('resource_portal_own_job_file_select', 'SELECT',
         'resource_can_access_storage_object'),
        ('tms_job_files_company_select', 'SELECT', 'is_company_user'),
        ('tms_job_files_operations_insert', 'INSERT', 'can_manage_operations')
)
SELECT expected.policy_name,
       CASE
           WHEN policy.policyname IS NULL THEN 'FAIL: missing policy'
           WHEN policy.cmd <> expected.command THEN 'FAIL: wrong command'
           WHEN COALESCE(policy.qual, '') || ' ' ||
                COALESCE(policy.with_check, '') NOT ILIKE
                '%' || expected.required_fragment || '%'
               THEN 'FAIL: required guard missing'
           WHEN expected.policy_name LIKE 'tms_job_files_%'
                AND COALESCE(policy.qual, '') || ' ' ||
                    COALESCE(policy.with_check, '') NOT ILIKE '%tms-job-files%'
               THEN 'FAIL: private-bucket scope missing'
           ELSE 'PASS'
       END AS result
FROM expected
LEFT JOIN pg_policies policy
  ON policy.schemaname = 'storage'
 AND policy.tablename = 'objects'
 AND policy.policyname = expected.policy_name
ORDER BY expected.policy_name;

-- Expected: 0 rows.
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND 'authenticated' = ANY(roles)
  AND cmd IN ('UPDATE', 'DELETE')
  AND (
      COALESCE(qual, '') ILIKE '%tms-job-files%'
      OR COALESCE(with_check, '') ILIKE '%tms-job-files%'
  );

-- 5. Resource access to operational company tables must still be RPC-only.
-- Expected: 3 PASS rows followed by 0 exception rows. Company-only policies
-- are allowed.
SELECT table_name,
       CASE WHEN table_row.relrowsecurity THEN 'PASS'
            ELSE 'FAIL: RLS disabled' END AS result
FROM (VALUES
    ('file_records'), ('file_access_logs'), ('job_issues')
) protected(table_name)
LEFT JOIN pg_namespace namespace ON namespace.nspname = 'public'
LEFT JOIN pg_class table_row
  ON table_row.relnamespace = namespace.oid
 AND table_row.relname = protected.table_name
ORDER BY table_name;

SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('file_records', 'file_access_logs', 'job_issues')
  AND cmd IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'ALL')
  AND (
      COALESCE(qual, '') ILIKE '%current_external_resource_id%'
      OR COALESCE(qual, '') ILIKE '%current_external_financial_resource_id%'
      OR COALESCE(with_check, '') ILIKE '%current_external_resource_id%'
      OR COALESCE(with_check, '') ILIKE '%current_external_financial_resource_id%'
  );

-- 6. All three dashboard projections must use only active POs. The list and
-- My Jobs projection must select only the newest immutable version.
WITH installed AS (
    SELECT function_row.proname AS function_name,
           pg_get_functiondef(function_row.oid) AS definition
    FROM pg_proc function_row
    JOIN pg_namespace namespace ON namespace.oid = function_row.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_row.proname IN (
          'resource_portal_context', 'resource_portal_jobs',
          'resource_portal_purchase_orders'
      )
)
SELECT function_name,
       CASE
           WHEN definition NOT ILIKE
                '%status IN (''Issued'', ''Acknowledged'')%'
               THEN 'FAIL: active-PO filter missing'
           WHEN function_name <> 'resource_portal_context'
                AND definition NOT ILIKE '%ORDER BY%version_number DESC%LIMIT 1%'
               THEN 'FAIL: latest immutable version selection missing'
           WHEN definition ~* 'public\.(clients|client_accounts|scope_items)'
               THEN 'FAIL: forbidden company table reference'
           ELSE 'PASS'
       END AS result
FROM installed
ORDER BY function_name;

-- 7. Resource file logging remains own-file only and View/Download only.
WITH installed AS (
    SELECT pg_get_functiondef(
        'public.record_resource_file_access(uuid,text)'::regprocedure
    ) AS definition
)
SELECT CASE
           WHEN definition NOT ILIKE '%resource_can_access_file%'
               THEN 'FAIL: own-file check missing'
           WHEN definition NOT ILIKE '%p_action NOT IN (%'
               THEN 'FAIL: View/Download allowlist missing'
           WHEN definition NOT ILIKE '%INSERT INTO public.file_access_logs%'
               THEN 'FAIL: immutable access log missing'
           ELSE 'PASS'
       END AS result
FROM installed;

-- 8. Staff file lifecycle must use a Resource-bound object key, Pending before
-- upload, storage existence before publication and immutable audit events.
WITH definitions AS (
    SELECT
        pg_get_functiondef(
            'public.staff_prepare_job_file_upload(uuid,text,text,bigint,text,text)'::regprocedure
        ) AS prepare_definition,
        pg_get_functiondef(
            'public.staff_publish_job_file_upload(uuid)'::regprocedure
        ) AS publish_definition,
        pg_get_functiondef(
            'public.staff_archive_job_file(uuid)'::regprocedure
        ) AS archive_definition
)
SELECT CASE
           WHEN prepare_definition NOT ILIKE '%v_resource_id%v_file_id%v_safe_filename%'
               THEN 'FAIL: Resource-bound object key missing'
           WHEN prepare_definition NOT ILIKE '%''Pending''%'
               THEN 'FAIL: pending upload state missing'
           WHEN publish_definition NOT ILIKE '%FROM storage.objects%'
               THEN 'FAIL: storage existence check missing'
           WHEN publish_definition NOT ILIKE '%''Upload''%'
               THEN 'FAIL: upload audit event missing'
           WHEN archive_definition NOT ILIKE '%''Archive''%'
               THEN 'FAIL: archive audit event missing'
           ELSE 'PASS'
       END AS result
FROM definitions;

-- 9. Issue functions expose no financial-impact write and enforce the locked
-- status/severity vocabulary. Expected: one PASS row.
WITH definitions AS (
    SELECT
        pg_get_functiondef(
            'public.staff_create_job_issue(uuid,text,text)'::regprocedure
        ) AS create_definition,
        pg_get_functiondef(
            'public.staff_update_job_issue(uuid,text,text,text,text)'::regprocedure
        ) AS update_definition
)
SELECT CASE
           WHEN create_definition ILIKE '%financial_impact%'
                OR update_definition ILIKE '%financial_impact%'
               THEN 'FAIL: financial impact is browser-writable'
           WHEN create_definition NOT ILIKE '%Critical%'
               THEN 'FAIL: severity allowlist missing'
           WHEN update_definition NOT ILIKE '%Correction Requested%'
                OR update_definition NOT ILIKE '%Resolved%'
               THEN 'FAIL: issue status allowlist missing'
           WHEN update_definition NOT ILIKE
                '%A resolution is required when resolving an issue%'
               THEN 'FAIL: resolved-state guard missing'
           ELSE 'PASS'
       END AS result
FROM definitions;

-- 10. Lifecycle state/data consistency. Expected: 0 rows.
SELECT id, upload_status, archived_at, original_filename
FROM public.file_records
WHERE upload_status NOT IN ('Pending', 'Ready', 'Archived')
   OR upload_status IS NULL
   OR (upload_status = 'Pending' AND archived_at IS NULL)
   OR (upload_status = 'Ready' AND archived_at IS NOT NULL)
   OR (upload_status = 'Archived' AND archived_at IS NULL)
ORDER BY created_at;
