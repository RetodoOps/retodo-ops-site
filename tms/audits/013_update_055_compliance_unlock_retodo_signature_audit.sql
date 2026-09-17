-- Retodo Ops TMS - Update 055 audit
WITH checks AS (
    SELECT 'issuance table' AS check_name,
           to_regclass('public.resource_framework_agreement_issuances') IS NOT NULL AS passed
    UNION ALL
    SELECT 'Retodo signature columns', COUNT(*) = 5
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'resource_framework_agreements'
      AND column_name IN ('retodo_signatory_name','retodo_signatory_title',
                          'retodo_registration_email','retodo_signed_by','retodo_signed_at')
    UNION ALL
    SELECT 'atomic unlock dispatcher', to_regprocedure(
        'public.resource_compliance_workflow_dispatch_055(text,uuid,uuid,text)'
    ) IS NOT NULL
    UNION ALL
    SELECT 'portal Agreement projection', to_regprocedure(
        'public.resource_portal_framework_agreement_050()'
    ) IS NOT NULL
    UNION ALL
    SELECT 'portal two-party acceptance', to_regprocedure(
        'public.resource_portal_accept_framework_agreement_050(jsonb)'
    ) IS NOT NULL
    UNION ALL
    SELECT 'submission gate', to_regprocedure(
        'public.resource_portal_submit_compliance_048()'
    ) IS NOT NULL
)
SELECT check_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
