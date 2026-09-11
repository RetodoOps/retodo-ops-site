-- RetodoOps TMS — Update 046 / R2 server-role claim compatibility
-- Forward-only migration. Run once after 044_cloudflare_r2_file_lifecycle.sql.
--
-- Supabase exposes the verified JWT claims through auth.role(). Update 044
-- read only the legacy per-claim GUC, which may be empty even when PostgREST
-- has authenticated a service_role request. This migration changes only the
-- five server-only function guards; their operational bodies and privileges
-- remain otherwise unchanged.

BEGIN;

DO $migration$
DECLARE
    v_signature TEXT;
    v_function REGPROCEDURE;
    v_definition TEXT;
    v_old_guard CONSTANT TEXT :=
        'IF COALESCE(current_setting(''request.jwt.claim.role'', TRUE), '''') <> ''service_role'' THEN';
    v_new_guard CONSTANT TEXT :=
        'IF auth.role() IS DISTINCT FROM ''service_role'' THEN';
    v_old_count INTEGER;
BEGIN
    IF to_regprocedure('auth.role()') IS NULL THEN
        RAISE EXCEPTION 'Migration 045 requires Supabase auth.role()';
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.r2_file_dispatch_044(text,uuid,uuid,uuid,jsonb)',
        'public.system_enqueue_due_file_lifecycle_044()',
        'public.system_claim_file_lifecycle_044()',
        'public.system_complete_file_lifecycle_044(uuid,jsonb)',
        'public.system_fail_file_lifecycle_044(uuid,text)'
    ]
    LOOP
        v_function := to_regprocedure(v_signature);
        IF v_function IS NULL THEN
            RAISE EXCEPTION 'Migration 045 prerequisite missing: %', v_signature;
        END IF;

        v_definition := pg_get_functiondef(v_function);
        v_old_count := (
            length(v_definition) - length(replace(v_definition, v_old_guard, ''))
        ) / length(v_old_guard);

        IF position(v_new_guard IN v_definition) > 0 AND v_old_count = 0 THEN
            CONTINUE;
        END IF;
        IF v_old_count <> 1 OR position(v_new_guard IN v_definition) > 0 THEN
            RAISE EXCEPTION
                'Migration 045 refused an unexpected definition for %',
                v_signature;
        END IF;

        EXECUTE replace(v_definition, v_old_guard, v_new_guard);

        v_definition := pg_get_functiondef(to_regprocedure(v_signature));
        IF position(v_new_guard IN v_definition) = 0
           OR position(v_old_guard IN v_definition) > 0 THEN
            RAISE EXCEPTION
                'Migration 045 could not verify the updated guard for %',
                v_signature;
        END IF;
    END LOOP;
END;
$migration$;

-- Reassert the locked server-only execution boundary explicitly. CREATE OR
-- REPLACE preserves existing privileges, but these statements make the
-- intended boundary independently auditable.
REVOKE ALL ON FUNCTION public.r2_file_dispatch_044(
    TEXT, UUID, UUID, UUID, JSONB
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_enqueue_due_file_lifecycle_044()
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_claim_file_lifecycle_044()
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_complete_file_lifecycle_044(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_fail_file_lifecycle_044(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.r2_file_dispatch_044(
    TEXT, UUID, UUID, UUID, JSONB
) TO service_role;
GRANT EXECUTE ON FUNCTION public.system_enqueue_due_file_lifecycle_044()
    TO service_role;
GRANT EXECUTE ON FUNCTION public.system_claim_file_lifecycle_044()
    TO service_role;
GRANT EXECUTE ON FUNCTION public.system_complete_file_lifecycle_044(UUID, JSONB)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.system_fail_file_lifecycle_044(UUID, TEXT)
    TO service_role;

COMMIT;
