-- RetodoOps TMS — Update 039 / P1.2 External Resource portal audit
-- Run after 038_external_resource_portal_and_role_boundaries.sql.
-- Every statement is read-only. Unexpected rows require review; do not repair
-- historical data directly.

-- 1. Required portal functions must exist, be SECURITY DEFINER, have a fixed
-- search_path, be callable by authenticated users and not callable by anon.
WITH required(signature) AS (
    VALUES
        ('public.current_external_resource_id()'),
        ('public.current_external_financial_resource_id()'),
        ('public.external_resource_portal_link_status(uuid)'),
        ('public.activate_external_resource_portal(uuid)'),
        ('public.resource_portal_context()'),
        ('public.resource_portal_jobs()'),
        ('public.resource_portal_job(uuid)'),
        ('public.resource_portal_purchase_orders()'),
        ('public.resource_portal_purchase_order(uuid)'),
        ('public.resource_can_access_file(uuid)'),
        ('public.resource_can_access_storage_object(text,text)'),
        ('public.record_resource_file_access(uuid,text)')
), resolved AS (
    SELECT signature, to_regprocedure(signature) AS function_oid
    FROM required
)
SELECT resolved.signature,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS configuration,
       CASE
           WHEN resolved.function_oid IS NULL THEN 'FAIL: missing function'
           WHEN NOT function_row.prosecdef THEN 'FAIL: not SECURITY DEFINER'
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

-- 2. The five Resource read projections must be stable and must not reference
-- Client, Account, Client-price or Project financial tables/fields.
WITH required(function_name) AS (
    VALUES
        ('resource_portal_context'),
        ('resource_portal_jobs'),
        ('resource_portal_job'),
        ('resource_portal_purchase_orders'),
        ('resource_portal_purchase_order')
), installed AS (
    SELECT function_row.proname AS function_name,
           function_row.prosecdef,
           function_row.provolatile,
           pg_get_functiondef(function_row.oid) AS definition
    FROM pg_proc function_row
    JOIN pg_namespace namespace ON namespace.oid = function_row.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_row.proname LIKE 'resource_portal_%'
)
SELECT required.function_name,
       CASE
           WHEN installed.function_name IS NULL THEN 'FAIL: missing function'
           WHEN NOT installed.prosecdef THEN 'FAIL: not SECURITY DEFINER'
           WHEN installed.provolatile <> 's' THEN 'FAIL: reader is not STABLE'
           WHEN installed.definition ~* 'public\.(clients|client_accounts|client_contacts|scope_items)'
               THEN 'FAIL: forbidden table reference'
           WHEN installed.definition ~* '''(client|account)(_id|_name|_price)?'''
               THEN 'FAIL: forbidden output key'
           WHEN installed.definition ~* '''(profit|margin|client_price)'''
               THEN 'FAIL: forbidden financial output key'
           ELSE 'PASS'
       END AS result
FROM required
LEFT JOIN installed USING (function_name)
ORDER BY required.function_name;

-- 3. Company tables remain RLS protected. Expected: every row PASS.
-- A Resource receives projections through RPCs; no direct Resource SELECT
-- policy may be added to these tables.
WITH protected(table_name) AS (
    VALUES
        ('profiles'), ('clients'), ('client_accounts'), ('projects'),
        ('project_scoops'), ('scope_items'), ('project_jobs'), ('resources'),
        ('resource_rates'), ('supplier_purchase_orders'),
        ('supplier_po_versions'), ('audit_events'), ('file_access_logs')
), policy_summary AS (
    SELECT protected.table_name,
           table_row.relrowsecurity AS rls_enabled,
           count(policy.policyname) FILTER (
               WHERE policy.cmd IN ('SELECT', 'ALL')
           ) AS read_policy_count,
           count(policy.policyname) FILTER (
               WHERE policy.cmd IN ('SELECT', 'ALL')
                 AND (
                     policy.qual IS NULL
                     OR lower(trim(both '()' FROM policy.qual)) = 'true'
                     OR policy.qual ILIKE '%current_external_resource_id%'
                     OR policy.qual ILIKE '%current_external_financial_resource_id%'
                     OR policy.qual ~* 'current_app_role\(\).*resource'
                 )
           ) AS unsafe_resource_read_policies
    FROM protected
    LEFT JOIN pg_namespace namespace ON namespace.nspname = 'public'
    LEFT JOIN pg_class table_row
        ON table_row.relnamespace = namespace.oid
       AND table_row.relname = protected.table_name
    LEFT JOIN pg_policies policy
        ON policy.schemaname = 'public'
       AND policy.tablename = protected.table_name
    GROUP BY protected.table_name, table_row.relrowsecurity
)
SELECT table_name,
       rls_enabled,
       read_policy_count,
       unsafe_resource_read_policies,
       CASE
           WHEN NOT COALESCE(rls_enabled, FALSE) THEN 'FAIL: RLS disabled'
           WHEN read_policy_count = 0 THEN 'FAIL: no company read policy'
           WHEN unsafe_resource_read_policies <> 0 THEN 'FAIL: Resource direct-read policy found'
           ELSE 'PASS'
       END AS result
FROM policy_summary
ORDER BY table_name;

-- 4. Catalogue policy contract: company read, Admin/PM active insert, Admin-only
-- update/delete. Expected: 12 rows, all PASS.
WITH expected(table_name, policy_name, command, required_fragment) AS (
    VALUES
        ('service_catalog', 'service_catalog_company_select', 'SELECT', 'is_company_user'),
        ('service_catalog', 'service_catalog_admin_pm_insert', 'INSERT', '''pm'''),
        ('service_catalog', 'service_catalog_admin_update', 'UPDATE', 'is_admin'),
        ('service_catalog', 'service_catalog_admin_delete', 'DELETE', 'is_admin'),
        ('language_catalog', 'language_catalog_company_select', 'SELECT', 'is_company_user'),
        ('language_catalog', 'language_catalog_admin_pm_insert', 'INSERT', '''pm'''),
        ('language_catalog', 'language_catalog_admin_update', 'UPDATE', 'is_admin'),
        ('language_catalog', 'language_catalog_admin_delete', 'DELETE', 'is_admin'),
        ('specializations', 'specializations_company_select', 'SELECT', 'is_company_user'),
        ('specializations', 'specializations_admin_pm_insert', 'INSERT', '''pm'''),
        ('specializations', 'specializations_admin_update', 'UPDATE', 'is_admin'),
        ('specializations', 'specializations_admin_delete', 'DELETE', 'is_admin')
)
SELECT expected.table_name,
       expected.policy_name,
       expected.command,
       CASE
           WHEN policy.policyname IS NULL THEN 'FAIL: missing policy'
           WHEN COALESCE(policy.qual, '') || ' ' || COALESCE(policy.with_check, '')
                    NOT ILIKE '%' || expected.required_fragment || '%'
               THEN 'FAIL: policy expression mismatch'
           WHEN expected.command = 'INSERT'
                AND COALESCE(policy.with_check, '') NOT ILIKE '%active%'
               THEN 'FAIL: PM insert is not constrained to active rows'
           ELSE 'PASS'
       END AS result
FROM expected
LEFT JOIN pg_policies policy
    ON policy.schemaname = 'public'
   AND policy.tablename = expected.table_name
   AND policy.policyname = expected.policy_name
   AND policy.cmd = expected.command
ORDER BY expected.table_name, expected.command;

-- 5. No additional catalogue policies should survive. Expected: one row per
-- table, policy_count = 4 and result PASS.
SELECT catalog.table_name,
       count(policy.policyname) AS policy_count,
       CASE WHEN count(policy.policyname) = 4 THEN 'PASS'
            ELSE 'FAIL: unexpected catalogue policy count' END AS result
FROM (VALUES
    ('service_catalog'), ('language_catalog'), ('specializations')
) AS catalog(table_name)
LEFT JOIN pg_policies policy
    ON policy.schemaname = 'public'
   AND policy.tablename = catalog.table_name
GROUP BY catalog.table_name
ORDER BY catalog.table_name;

-- 6. The private Storage policy must be SELECT-only and use the exact own-Job
-- object check. Expected: one PASS row.
SELECT policy.schemaname,
       policy.tablename,
       policy.policyname,
       policy.cmd,
       CASE
           WHEN policy.policyname IS NULL THEN 'FAIL: missing Storage policy'
           WHEN policy.cmd <> 'SELECT' THEN 'FAIL: Storage mutation policy'
           WHEN policy.qual NOT ILIKE '%resource_can_access_storage_object%'
               THEN 'FAIL: own-Job object check missing'
           ELSE 'PASS'
       END AS result
FROM (VALUES ('resource_portal_own_job_file_select')) AS expected(policyname)
LEFT JOIN pg_policies policy
    ON policy.schemaname = 'storage'
   AND policy.tablename = 'objects'
   AND policy.policyname = expected.policyname;

-- 7. Other Storage policies granted to authenticated users can also affect a
-- Resource because it uses the authenticated database role. Expected: 0 rows,
-- unless every returned policy has been separately reviewed as company-only.
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname <> 'resource_portal_own_job_file_select'
  AND 'authenticated' = ANY(roles)
  AND NOT (
      COALESCE(qual, '') ILIKE '%is_company_user%'
      OR COALESCE(qual, '') ILIKE '%is_admin%'
      OR COALESCE(qual, '') ILIKE '%can_manage_operations%'
  )
ORDER BY policyname;

-- 8. Trusted file logging must validate own-Job access and allow only View or
-- Download before inserting. Expected: one PASS row.
WITH installed AS (
    SELECT pg_get_functiondef(
        'public.record_resource_file_access(uuid,text)'::regprocedure
    ) AS definition
)
SELECT CASE
           WHEN definition NOT ILIKE '%resource_can_access_file%'
               THEN 'FAIL: own-file check missing'
           WHEN definition NOT ILIKE '%p_action NOT IN (%'
               THEN 'FAIL: action allowlist missing'
           WHEN definition NOT ILIKE '%INSERT INTO public.file_access_logs%'
               THEN 'FAIL: trusted log write missing'
           ELSE 'PASS'
       END AS result
FROM installed;

-- 9. PM may create a Supplier PO revision, but initial manual issue remains
-- Administrator-only. Revision numbering must advance from the largest stored
-- immutable version. Expected: one PASS row.
WITH definitions AS (
    SELECT
        pg_get_functiondef(
            'public.revise_supplier_po(uuid,jsonb,text)'::regprocedure
        ) AS revise_definition,
        pg_get_functiondef(
            'public.issue_supplier_po(uuid)'::regprocedure
        ) AS issue_definition
)
SELECT CASE
           WHEN revise_definition NOT ILIKE '%current_app_role() NOT IN (''admin'', ''pm'')%'
               THEN 'FAIL: PM revision permission missing'
           WHEN revise_definition NOT ILIKE '%max(version.version_number)%'
               THEN 'FAIL: revision does not use largest immutable version'
           WHEN issue_definition NOT ILIKE '%is_admin()%'
               THEN 'FAIL: initial manual issue is not Admin-only'
           ELSE 'PASS'
       END AS result
FROM definitions;

-- 10. Existing External Resource links must map the exact Resource email to an
-- Auth user whose profile role is resource. Expected: 0 rows before/after a
-- correct activation. Unlinked Resources (profile_id IS NULL) are intentionally
-- omitted.
SELECT resource.id AS resource_id,
       resource.internal_number,
       resource.email AS resource_email,
       profile.role AS profile_role,
       auth_user.email AS authentication_email,
       resource.portal_status
FROM public.resources resource
LEFT JOIN public.profiles profile ON profile.id = resource.profile_id
LEFT JOIN auth.users auth_user ON auth_user.id = resource.profile_id
WHERE resource.resource_type IN ('Freelancer', 'Company')
  AND resource.profile_id IS NOT NULL
  AND (
      profile.id IS NULL
      OR profile.role <> 'resource'
      OR auth_user.id IS NULL
      OR lower(COALESCE(resource.email, ''))
            IS DISTINCT FROM lower(COALESCE(auth_user.email, ''))
  )
ORDER BY resource.internal_number;

-- 11. Informational linked-portal inventory. Review that each linked account
-- belongs to the intended person/company and that Financial-only expiry is
-- appropriate. Returned rows are not failures.
SELECT resource.internal_number,
       resource.resource_type,
       resource.lifecycle_status,
       resource.portal_status,
       resource.financial_access_until,
       profile.role,
       count(DISTINCT job.id) AS assigned_job_count,
       count(DISTINCT po.id) FILTER (WHERE po.status <> 'Draft') AS issued_po_count
FROM public.resources resource
JOIN public.profiles profile ON profile.id = resource.profile_id
LEFT JOIN public.project_jobs job ON job.resource_id = resource.id
LEFT JOIN public.supplier_purchase_orders po ON po.resource_id = resource.id
WHERE resource.resource_type IN ('Freelancer', 'Company')
GROUP BY resource.id, profile.role
ORDER BY resource.internal_number;

-- 12. Direct Resource writes cannot bypass the Administrator-only exact-email
-- portal link boundary. Expected: one PASS row.
WITH installed AS (
    SELECT function_row.oid,
           function_row.prosecdef,
           function_row.proconfig,
           pg_get_functiondef(function_row.oid) AS definition
    FROM pg_proc function_row
    JOIN pg_namespace namespace ON namespace.oid = function_row.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_row.proname = 'protect_external_resource_portal_security'
      AND pg_get_function_identity_arguments(function_row.oid) = ''
), trigger_definition AS (
    SELECT pg_get_triggerdef(trigger_row.oid) AS definition
    FROM pg_trigger trigger_row
    JOIN pg_class table_row ON table_row.oid = trigger_row.tgrelid
    JOIN pg_namespace namespace ON namespace.oid = table_row.relnamespace
    WHERE namespace.nspname = 'public'
      AND table_row.relname = 'resources'
      AND trigger_row.tgname = 'resources_protect_external_portal_security'
      AND NOT trigger_row.tgisinternal
), summary AS (
    SELECT
        (SELECT oid FROM installed LIMIT 1) AS function_oid,
        (SELECT prosecdef FROM installed LIMIT 1) AS security_definer,
        (SELECT proconfig FROM installed LIMIT 1) AS configuration,
        (SELECT definition FROM installed LIMIT 1) AS function_definition,
        (SELECT definition FROM trigger_definition LIMIT 1) AS trigger_definition
)
SELECT CASE
           WHEN summary.function_oid IS NULL THEN 'FAIL: missing protection function'
           WHEN NOT summary.security_definer THEN 'FAIL: protection function is not SECURITY DEFINER'
           WHEN NOT EXISTS (
               SELECT 1
               FROM unnest(COALESCE(summary.configuration, ARRAY[]::TEXT[])) setting
               WHERE setting LIKE 'search_path=%'
           ) THEN 'FAIL: protection search_path not fixed'
           WHEN has_function_privilege('authenticated', summary.function_oid, 'EXECUTE')
               THEN 'FAIL: authenticated can call trigger function'
           WHEN has_function_privilege('anon', summary.function_oid, 'EXECUTE')
               THEN 'FAIL: anon can call trigger function'
           WHEN summary.function_definition NOT ILIKE '%NOT public.is_admin()%'
               THEN 'FAIL: Administrator boundary missing'
           WHEN summary.function_definition NOT ILIKE '%auth.users%'
               OR summary.function_definition NOT ILIKE '%profile.role%'
               OR summary.function_definition NOT ILIKE '%btrim(NEW.email)%'
               THEN 'FAIL: exact Auth identity validation missing'
           WHEN summary.trigger_definition IS NULL
               THEN 'FAIL: protection trigger missing'
           WHEN summary.trigger_definition NOT ILIKE '%BEFORE INSERT OR UPDATE OF%'
               OR summary.trigger_definition NOT ILIKE '%profile_id%'
               OR summary.trigger_definition NOT ILIKE '%portal_status%'
               OR summary.trigger_definition NOT ILIKE '%financial_access_until%'
               OR summary.trigger_definition NOT ILIKE '%email%'
               THEN 'FAIL: protection trigger fields mismatch'
           ELSE 'PASS'
       END AS result
FROM summary;

-- 13a. Browser-facing company wrappers must reject Resource/generic accounts
-- before looking up company data. Expected: three PASS rows.
WITH required(signature) AS (
    VALUES
        ('public.save_job_overview_inherit_rate_unit(uuid,jsonb)'),
        ('public.assign_job_and_issue_po_inherit_rate_unit(uuid,uuid,uuid,jsonb,text)'),
        ('public.create_project_with_specializations(jsonb)')
), resolved AS (
    SELECT signature, to_regprocedure(signature) AS function_oid
    FROM required
)
SELECT resolved.signature,
       CASE
           WHEN resolved.function_oid IS NULL THEN 'FAIL: missing company wrapper'
           WHEN NOT has_function_privilege(
               'authenticated', resolved.function_oid, 'EXECUTE'
           ) THEN 'FAIL: authenticated company users cannot execute'
           WHEN pg_get_functiondef(resolved.function_oid)
                    NOT ILIKE '%NOT public.can_manage_operations()%'
               THEN 'FAIL: early operational-role guard missing'
           ELSE 'PASS'
       END AS result
FROM resolved
ORDER BY resolved.signature;

-- 13b. Internal SECURITY DEFINER helpers must not be callable as browser RPCs.
-- is_supported_tms_service is excluded because an invoker trigger requires it;
-- its definition now returns false outside company/service roles. Expected:
-- every returned row PASS.
WITH required(signature) AS (
    VALUES
        ('public.create_job_offer_from_rate(uuid,uuid,uuid,timestamp with time zone,numeric,text,boolean,boolean,text,jsonb)'),
        ('public.normalize_supplier_cat_analysis(uuid,jsonb)'),
        ('public.contextual_supplier_po_number(uuid)'),
        ('public.profile_id_for_internal_email(text)'),
        ('public.project_job_specialization(uuid,text)'),
        ('public.job_service_code(text)'),
        ('public.tms_compact_language_code(text)'),
        ('public.tms_compact_rate_line_label(text[],text,text[],text,text,uuid,text,numeric,text,text)'),
        ('public.refresh_client_rate_card_name(uuid)'),
        ('public.refresh_project_financials(uuid)'),
        ('public.refresh_project_price_from_scoops(uuid)'),
        ('public.refresh_project_scoop_status(uuid)'),
        ('public.refresh_supplier_po_display_name(uuid)')
), resolved AS (
    SELECT signature, to_regprocedure(signature) AS function_oid
    FROM required
)
SELECT resolved.signature,
       CASE
           WHEN resolved.function_oid IS NULL THEN 'FAIL: missing internal helper'
           WHEN has_function_privilege(
               'authenticated', resolved.function_oid, 'EXECUTE'
           ) THEN 'FAIL: authenticated can execute internal helper'
           WHEN has_function_privilege('anon', resolved.function_oid, 'EXECUTE')
               THEN 'FAIL: anon can execute internal helper'
           ELSE 'PASS'
       END AS result
FROM resolved
ORDER BY resolved.signature;

-- 13c. Shared service validation remains usable by company insert triggers but
-- discloses no catalogue result to Resource/generic users. Expected: one PASS.
WITH installed AS (
    SELECT to_regprocedure(
        'public.is_supported_tms_service(text)'
    ) AS function_oid
)
SELECT CASE
           WHEN function_oid IS NULL THEN 'FAIL: service validator missing'
           WHEN NOT has_function_privilege(
               'authenticated', function_oid, 'EXECUTE'
           ) THEN 'FAIL: authenticated trigger caller cannot execute validator'
           WHEN pg_get_functiondef(function_oid) NOT ILIKE '%is_company_user()%'
               OR pg_get_functiondef(function_oid) NOT ILIKE '%is_admin()%'
               THEN 'FAIL: company/service guard missing'
           ELSE 'PASS'
       END AS result
FROM installed;
