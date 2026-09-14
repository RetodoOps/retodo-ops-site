-- Run after migration 050. Every row must report PASS.

WITH checks AS (
    SELECT 'Project status allows Cancelled' AS check_name,
           CASE WHEN EXISTS (
               SELECT 1 FROM pg_constraint
               WHERE conrelid = 'public.projects'::regclass
                 AND conname = 'projects_new_status_check'
                 AND pg_get_constraintdef(oid) LIKE '%Cancelled%'
           ) THEN 'PASS' ELSE 'FAIL' END AS result

    UNION ALL

    SELECT 'Scoop status allows Cancelled',
           CASE WHEN EXISTS (
               SELECT 1 FROM pg_constraint
               WHERE conrelid = 'public.project_scoops'::regclass
                 AND conname = 'project_scoops_status_check'
                 AND pg_get_constraintdef(oid) LIKE '%Cancelled%'
           ) THEN 'PASS' ELSE 'FAIL' END

    UNION ALL

    SELECT 'Agreement acceptance remains available',
           CASE WHEN to_regprocedure('public.resource_portal_accept_framework_agreement_050(jsonb)') IS NOT NULL
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL

    SELECT 'Agreement snapshot retains both compatibility columns',
           CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'resource_framework_agreements'
                 AND column_name = 'registration_or_id_number'
           ) AND EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'resource_framework_agreements'
                 AND column_name = 'tax_vat_number'
           ) THEN 'PASS' ELSE 'FAIL' END
)
SELECT check_name, result FROM checks ORDER BY check_name;
