-- RetodoOps TMS — P1.1 read-only permission and snapshot audit
-- Run after migration 036_p1_permission_snapshot_hardening.sql.
-- This file contains SELECT/inspection statements only. It does not change
-- data, policies or functions.

-- 1. Required P1.1 objects exist.
SELECT object_name,
       object_type,
       CASE
           WHEN object_type = 'table' AND to_regclass(object_name) IS NOT NULL
               THEN 'PASS'
           WHEN object_type = 'function'
                AND to_regprocedure(object_name) IS NOT NULL
               THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM (VALUES
    ('public.supplier_po_versions', 'table'),
    ('public.audit_events', 'table'),
    ('public.file_access_logs', 'table'),
    ('public.protect_append_only_tms_record()', 'function'),
    ('public.audit_tms_status_change()', 'function')
) AS required(object_name, object_type)
ORDER BY object_type, object_name;

-- 2. RLS must be enabled on the append-only tables.
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls,
       CASE WHEN c.relrowsecurity THEN 'PASS' ELSE 'FAIL' END AS result
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('supplier_po_versions', 'audit_events', 'file_access_logs')
ORDER BY c.relname;

-- 3. Policy review. Expected: SELECT + INSERT only on each table; no generic
-- operations-write policy should remain for these append-only records.
SELECT tablename,
       policyname,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('supplier_po_versions', 'audit_events', 'file_access_logs')
ORDER BY tablename, policyname;

-- 4. Trigger review. Expected: append-only trigger on all three tables and
-- status-audit triggers on Project/Scoop/Job/Resource/PO/Invoice tables.
SELECT event_object_table AS table_name,
       trigger_name,
       event_manipulation,
       action_timing,
       action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND (
      event_object_table IN ('supplier_po_versions', 'audit_events', 'file_access_logs')
      OR trigger_name LIKE '%audit_status_change%'
  )
ORDER BY event_object_table, trigger_name, event_manipulation;

-- 5. SECURITY DEFINER functions must pin search_path to public. This is a
-- review report; any returned row requires inspection before release.
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       p.proconfig AS configuration,
       CASE
           WHEN p.prosecdef
                AND EXISTS (
                    SELECT 1
                    FROM unnest(COALESCE(p.proconfig, ARRAY[]::TEXT[])) setting
                    WHERE setting = 'search_path=public'
                ) THEN 'PASS'
           WHEN p.prosecdef THEN 'REVIEW'
           ELSE 'NOT SECURITY DEFINER'
       END AS result
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND p.proname IN (
      'create_project', 'create_project_scoop', 'update_project_scoop',
      'create_project_job', 'save_scoop_financial_lines',
      'assign_job_and_issue_po', 'assign_job_and_issue_po_inherit_rate_unit',
      'assign_job_and_issue_po_flat_fee', 'cancel_job_supplier_po',
      'issue_supplier_po', 'revise_supplier_po', 'supplier_po_snapshot',
      'protect_append_only_tms_record', 'audit_tms_status_change'
  )
ORDER BY p.proname, arguments;

-- 6. Structural orphans that should normally return no rows.
SELECT 'Job without Scoop' AS check_name, job.id, job.job_number
FROM public.project_jobs job
WHERE job.project_scoop_id IS NULL
UNION ALL
SELECT 'Job/Scoop Project mismatch', job.id, job.job_number
FROM public.project_jobs job
JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
WHERE job.project_id IS DISTINCT FROM scoop.project_id
UNION ALL
SELECT 'Financial line without Scoop', line.id, line.description
FROM public.scope_items line
WHERE line.project_scoop_id IS NULL
UNION ALL
SELECT 'PO version without PO', version.id, version.version_number::TEXT
FROM public.supplier_po_versions version
LEFT JOIN public.supplier_purchase_orders po ON po.id = version.purchase_order_id
WHERE po.id IS NULL
ORDER BY check_name, id;

-- 7. Duplicate PO version numbers should return no rows.
SELECT purchase_order_id,
       version_number,
       count(*) AS duplicate_count
FROM public.supplier_po_versions
GROUP BY purchase_order_id, version_number
HAVING count(*) > 1
ORDER BY purchase_order_id, version_number;

-- 8. Every Issued/Acknowledged PO must have a current immutable version with
-- matching PO number, version and total. Any row returned is a repair review.
SELECT po.id,
       po.po_number,
       po.status,
       po.current_version,
       po.total AS current_po_total,
       version.snapshot->>'po_number' AS snapshot_po_number,
       version.snapshot->>'version' AS snapshot_version,
       version.snapshot->>'total' AS snapshot_total,
       CASE
           WHEN version.id IS NULL THEN 'FAIL: missing current version'
           WHEN version.snapshot->>'po_number' IS DISTINCT FROM po.po_number
               THEN 'FAIL: PO number mismatch'
           WHEN (version.snapshot->>'version')::INTEGER IS DISTINCT FROM po.current_version
               THEN 'FAIL: version mismatch'
           WHEN round((version.snapshot->>'total')::NUMERIC, 2)
                IS DISTINCT FROM round(po.total, 2)
               THEN 'FAIL: total mismatch'
           ELSE 'PASS'
       END AS result
FROM public.supplier_purchase_orders po
LEFT JOIN public.supplier_po_versions version
    ON version.purchase_order_id = po.id
   AND version.version_number = po.current_version
WHERE po.status IN ('Issued', 'Acknowledged', 'Superseded')
ORDER BY result DESC, po.created_at, po.po_number;

-- 9. The latest issued PO snapshot must contain the Job facts printed on the
-- PO. This detects an unversioned mutation of a commercial Job field.
SELECT po.po_number,
       po.current_version,
       job.job_number,
       version.snapshot->'job'->>'job_number' AS snapshot_job_number,
       job.source_language,
       version.snapshot->'job'->>'source_language' AS snapshot_source_language,
       job.target_language,
       version.snapshot->'job'->>'target_language' AS snapshot_target_language,
       job.deadline,
       version.snapshot->'job'->>'deadline' AS snapshot_deadline,
       CASE
           WHEN version.id IS NULL THEN 'FAIL: missing version'
           WHEN version.snapshot->'job'->>'job_number' IS DISTINCT FROM job.job_number
               THEN 'FAIL: Job number mismatch'
           WHEN version.snapshot->'job'->>'source_language' IS DISTINCT FROM job.source_language
               THEN 'FAIL: Source language mismatch'
           WHEN version.snapshot->'job'->>'target_language' IS DISTINCT FROM job.target_language
               THEN 'FAIL: Target language mismatch'
           WHEN (version.snapshot->'job'->>'deadline')::TIMESTAMPTZ
                IS DISTINCT FROM job.deadline
               THEN 'FAIL: deadline mismatch'
           ELSE 'PASS'
       END AS result
FROM public.supplier_purchase_orders po
JOIN public.project_jobs job ON job.id = po.job_id
LEFT JOIN public.supplier_po_versions version
    ON version.purchase_order_id = po.id
   AND version.version_number = po.current_version
WHERE po.status IN ('Issued', 'Acknowledged')
ORDER BY result DESC, po.po_number;

-- 10. Financial rollup checks. Returned rows require investigation; rounding
-- is applied only at the comparison boundary so the stored four-decimal rate
-- precision is not discarded.
WITH scoop_totals AS (
    SELECT scoop.id,
           scoop.project_id,
           round(COALESCE(scoop.price, 0), 2) AS stored_price,
           round(COALESCE(sum(line.price), 0), 2) AS line_total
    FROM public.project_scoops scoop
    LEFT JOIN public.scope_items line ON line.project_scoop_id = scoop.id
    WHERE scoop.active
    GROUP BY scoop.id, scoop.project_id, scoop.price
), project_totals AS (
    SELECT project.id,
           round(COALESCE(project.price, 0), 2) AS stored_price,
           round(COALESCE(sum(scoop.price), 0), 2) AS scoop_total
    FROM public.projects project
    LEFT JOIN public.project_scoops scoop
        ON scoop.project_id = project.id AND scoop.active
    GROUP BY project.id, project.price
)
SELECT 'Scoop total mismatch' AS check_name,
       id,
       stored_price,
       line_total AS calculated_total
FROM scoop_totals
WHERE stored_price IS DISTINCT FROM line_total
UNION ALL
SELECT 'Project total mismatch',
       id,
       stored_price,
       scoop_total
FROM project_totals
WHERE stored_price IS DISTINCT FROM scoop_total
ORDER BY check_name, id;

-- 11. Assignment integrity: an active production Job must not point to an
-- inactive Resource. Expected result is no rows.
SELECT job.id,
       job.job_number,
       job.status,
       resource.id AS resource_id,
       resource.lifecycle_status,
       resource.resource_status
FROM public.project_jobs job
JOIN public.resources resource ON resource.id = job.resource_id
WHERE job.status IN ('Assigned', 'In Progress', 'Delivered', 'Revision Required', 'Approved')
  AND (
      resource.lifecycle_status IS DISTINCT FROM 'Active'
      OR resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred')
  )
ORDER BY job.job_number;

-- 12. Recent status audit coverage. This is informational and should show
-- events after the migration is applied and users exercise the transitions.
SELECT entity_type,
       action,
       count(*) AS event_count,
       max(occurred_at) AS last_event_at
FROM public.audit_events
WHERE occurred_at >= NOW() - INTERVAL '30 days'
GROUP BY entity_type, action
ORDER BY entity_type, action;
