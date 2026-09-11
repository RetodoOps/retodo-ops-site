-- RetodoOps TMS — Update 047 / Resource invitation email correction audit
-- Run after 046_resource_invitation_email_correction.sql.
-- Read-only. Every result row must be PASS.

WITH objects AS (
    SELECT
        to_regclass('public.resource_email_correction_requests') AS request_table,
        to_regprocedure(
            'public.resource_email_correction_046(text,uuid,uuid,text,uuid)'
        ) AS correction_function
), checks(check_name, result) AS (
    SELECT 'correction request table exists',
           CASE WHEN request_table IS NULL
                THEN 'FAIL: relation missing' ELSE 'PASS' END
    FROM objects

    UNION ALL

    SELECT 'correction request table uses RLS',
           CASE
               WHEN request_table IS NULL THEN 'FAIL: relation missing'
               WHEN NOT COALESCE((
                   SELECT relrowsecurity FROM pg_class WHERE oid = request_table
               ), false) THEN 'FAIL: RLS disabled'
               ELSE 'PASS'
           END
    FROM objects

    UNION ALL

    SELECT 'browser roles cannot read correction requests',
           CASE
               WHEN request_table IS NULL THEN 'FAIL: relation missing'
               WHEN has_table_privilege('authenticated', request_table, 'SELECT')
                 OR has_table_privilege('anon', request_table, 'SELECT')
                   THEN 'FAIL: browser table privilege exists'
               ELSE 'PASS'
           END
    FROM objects

    UNION ALL

    SELECT 'service role owns the correction execution path',
           CASE
               WHEN request_table IS NULL THEN 'FAIL: relation missing'
               WHEN NOT has_table_privilege('service_role', request_table, 'SELECT,INSERT,UPDATE')
                   THEN 'FAIL: service role table privilege missing'
               ELSE 'PASS'
           END
    FROM objects

    UNION ALL

    SELECT 'correction function is hardened',
           CASE
               WHEN correction_function IS NULL THEN 'FAIL: function missing'
               WHEN NOT (SELECT prosecdef FROM pg_proc WHERE oid = correction_function)
                   THEN 'FAIL: not SECURITY DEFINER'
               WHEN NOT EXISTS (
                   SELECT 1
                   FROM pg_proc procedure,
                        unnest(COALESCE(procedure.proconfig, ARRAY[]::text[])) setting
                   WHERE procedure.oid = correction_function
                     AND setting LIKE 'search_path=%'
               ) THEN 'FAIL: search_path not fixed'
               WHEN has_function_privilege('authenticated', correction_function, 'EXECUTE')
                 OR has_function_privilege('anon', correction_function, 'EXECUTE')
                   THEN 'FAIL: browser role can execute'
               WHEN NOT has_function_privilege('service_role', correction_function, 'EXECUTE')
                   THEN 'FAIL: service role cannot execute'
               ELSE 'PASS'
           END
    FROM objects

    UNION ALL

    SELECT 'correction keeps the locked identity rules',
           CASE
               WHEN correction_function IS NULL THEN 'FAIL: function missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%auth.role() IS DISTINCT FROM ''service_role''%'
                   THEN 'FAIL: service-role guard missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%v_actor_role IS DISTINCT FROM ''admin''%'
                   THEN 'FAIL: Administrator actor guard missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%last_sign_in_at IS NOT NULL%'
                   THEN 'FAIL: never-signed-in guard missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%resource_type = ''Internal''%'
                   THEN 'FAIL: External Resource boundary missing'
               ELSE 'PASS'
           END
    FROM objects

    UNION ALL

    SELECT 'correction invalidates old access before reinvitation',
           CASE
               WHEN correction_function IS NULL THEN 'FAIL: function missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%portal_status = ''Invited''%'
                   THEN 'FAIL: portal reset missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%status = ''failed''%'
                   THEN 'FAIL: old invitation invalidation missing'
               WHEN pg_get_functiondef(correction_function)
                    NOT ILIKE '%append_trusted_tms_audit_event%'
                   THEN 'FAIL: trusted audit event missing'
               ELSE 'PASS'
           END
    FROM objects

    UNION ALL

    SELECT 'linked Resource email protections remain installed',
           CASE WHEN NOT EXISTS (
               SELECT 1
               FROM pg_trigger trigger
               JOIN pg_class relation ON relation.oid = trigger.tgrelid
               JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
               WHERE namespace.nspname = 'public'
                 AND relation.relname = 'resources'
                 AND trigger.tgname IN (
                     'resources_check_auth_email_040',
                     'resources_protect_external_portal_security'
                 )
                 AND NOT trigger.tgisinternal
               GROUP BY relation.oid
               HAVING count(DISTINCT trigger.tgname) = 2
           ) THEN 'FAIL: linked-email trigger missing' ELSE 'PASS' END
)
SELECT check_name, result
FROM checks
ORDER BY check_name;
