-- RetodoOps TMS — Update 048 Compliance/ISO audit.
-- Run after 047_compliance_evidence_iso_eligibility.sql.
-- Read-only. Every result row must be PASS.

WITH target AS (
  SELECT
    to_regprocedure('public.resource_compliance_summary_047(uuid)') AS iso_function,
    to_regprocedure('public.professional_experience_duration_047(date,date)') AS duration_function,
    to_regprocedure('public.save_resource_education_047(uuid,uuid,jsonb)') AS education_function,
    to_regprocedure('public.save_resource_professional_since_047(uuid,date,date,date)') AS dates_function,
    to_regprocedure('public.resource_compliance_file_dispatch_047(text,uuid,uuid,uuid,jsonb)') AS file_function,
    to_regprocedure('public.get_blind_cv_data(uuid)') AS cv_function
), checks(check_name, result) AS (
  SELECT 'three independent date source columns', CASE WHEN (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resources'
      AND column_name IN (
        'translation_professional_since','revision_professional_since',
        'mtpe_professional_since'
      )
  )=3 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'education evidence fields', CASE WHEN (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resource_education'
      AND column_name IN (
        'degree_type','country','graduation_date','is_highest_relevant'
      )
  )=4 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'diploma linked to education record', CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resource_documents'
      AND column_name='education_id'
  ) AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.resource_documents'::regclass
      AND conname='resource_documents_education_id_fkey'
  ) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'no editable ISO or experience duration columns', CASE WHEN NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name IN ('resources','resource_education','resource_documents')
      AND (column_name LIKE 'iso_%'
           OR column_name IN (
             'translation_experience_years','revision_experience_years',
             'mtpe_experience_years','translation_experience_months',
             'revision_experience_months','mtpe_experience_months'
           ))
  ) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'Compliance metadata retains company RLS', CASE WHEN (
    SELECT count(*) FROM pg_class
    WHERE oid IN (
      'public.resource_education'::regclass,
      'public.resource_documents'::regclass,
      'public.file_records'::regclass
    ) AND relrowsecurity
  )=3 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'Compliance file and review writes require server', CASE WHEN (
    SELECT count(*) FROM pg_trigger
    WHERE NOT tgisinternal AND tgname IN (
      'file_records_guard_resource_compliance_047',
      'resource_documents_guard_compliance_047'
    )
  )=2 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'ISO RPC is company-only and read-only', CASE
    WHEN iso_function IS NULL THEN 'FAIL'
    WHEN NOT EXISTS (
      SELECT 1 FROM pg_proc WHERE oid=iso_function AND prosecdef
    ) THEN 'FAIL'
    WHEN position('public.is_company_user()' IN
        pg_get_functiondef(iso_function))=0 THEN 'FAIL'
    WHEN position('ISO 17100 Translator' IN
        pg_get_functiondef(iso_function))=0 THEN 'FAIL'
    WHEN position('ISO 18587 Post-editor' IN
        pg_get_functiondef(iso_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'current month duration helper exists', CASE
    WHEN duration_function IS NULL THEN 'FAIL'
    WHEN position('total_months' IN
        pg_get_functiondef(duration_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'experience edits restricted to operations', CASE
    WHEN dates_function IS NULL OR education_function IS NULL THEN 'FAIL'
    WHEN position('public.can_manage_operations()' IN
        pg_get_functiondef(dates_function))=0 THEN 'FAIL'
    WHEN position('public.can_manage_operations()' IN
        pg_get_functiondef(education_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'private evidence dispatcher is server-only', CASE
    WHEN file_function IS NULL THEN 'FAIL'
    WHEN has_function_privilege('anon',file_function,'EXECUTE')
      OR has_function_privilege('authenticated',file_function,'EXECUTE')
      OR NOT has_function_privilege('service_role',file_function,'EXECUTE') THEN 'FAIL'
    WHEN position('auth.role() IS DISTINCT FROM ''service_role''' IN
        pg_get_functiondef(file_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Compliance download excludes resource actors', CASE
    WHEN file_function IS NULL THEN 'FAIL'
    WHEN position('v_role NOT IN (''admin'', ''pm'', ''qa'', ''client_relations'')' IN
        pg_get_functiondef(file_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'evidence review remains operational and audited', CASE
    WHEN file_function IS NULL THEN 'FAIL'
    WHEN position('review_evidence' IN pg_get_functiondef(file_function))=0 THEN 'FAIL'
    WHEN position('Compliance evidence reviewed' IN
        pg_get_functiondef(file_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Blind CV uses current durations without ISO', CASE
    WHEN cv_function IS NULL THEN 'FAIL'
    WHEN position('public.professional_experience_duration_047' IN
        pg_get_functiondef(cv_function))=0 THEN 'FAIL'
    WHEN position('iso_eligibility' IN pg_get_functiondef(cv_function))>0
        THEN 'FAIL'
    ELSE 'PASS' END FROM target
)
SELECT check_name,result FROM checks ORDER BY check_name;
