-- RetodoOps TMS — Update 049 prompted Compliance workflow audit.
-- Run after 048_compliance_phase_tests_and_job_qualifications.sql.
-- Read-only. Every result row must be PASS.

WITH target AS (
  SELECT
    to_regprocedure('public.apply_resource_test_result()') AS test_trigger_function,
    to_regprocedure('public.resource_compliance_workflow_summary_048(uuid)') AS workflow_summary,
    to_regprocedure('public.resource_compliance_workflow_dispatch_048(text,uuid,uuid,text)') AS workflow_dispatch,
    to_regprocedure('public.resource_portal_compliance_048()') AS portal_read,
    to_regprocedure('public.resource_portal_save_compliance_048(jsonb)') AS portal_save,
    to_regprocedure('public.resource_portal_submit_compliance_048()') AS portal_submit,
    to_regprocedure('public.resource_account_job_qualifications_048(uuid)') AS job_qualifications,
    to_regprocedure('public.resource_compliance_file_dispatch_048(text,uuid,uuid,uuid,jsonb)') AS file_dispatch,
    to_regprocedure('public.get_blind_cv_data(uuid)') AS blind_cv
), checks(check_name, result) AS (
  SELECT 'test result and pre-TMS source columns', CASE WHEN (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resource_tests'
      AND column_name IN ('test_result','tested_before_tms')
  )=2 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'test workflow constraints separate status and result', CASE WHEN (
    SELECT count(*) FROM pg_constraint
    WHERE conrelid='public.resource_tests'::regclass
      AND conname IN (
        'resource_tests_status_048_check',
        'resource_tests_result_048_check',
        'resource_tests_workflow_048_check'
      )
  )=3 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'pre-TMS pass stores no test date', CASE
    WHEN test_trigger_function IS NULL THEN 'FAIL'
    WHEN position('NEW.tested_before_tms' IN pg_get_functiondef(test_trigger_function))=0 THEN 'FAIL'
    WHEN position('NEW.assigned_at := NULL' IN pg_get_functiondef(test_trigger_function))=0 THEN 'FAIL'
    WHEN position('NEW.completed_at := NULL' IN pg_get_functiondef(test_trigger_function))=0 THEN 'FAIL'
    WHEN position('NEW.test_result := ''Pass''' IN pg_get_functiondef(test_trigger_function))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'controlled education vocabulary and graduation year', CASE WHEN (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resource_education'
      AND column_name IN ('degree_level','field_of_study_category','field_of_study_other','end_year')
  )=4 AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.resource_education'::regclass
      AND conname='resource_education_degree_level_048_check'
  ) AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.resource_education'::regclass
      AND conname='resource_education_field_category_048_check'
  ) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'prompted Compliance workflow state fields', CASE WHEN (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resources'
      AND column_name IN (
        'compliance_phase_status','compliance_requested_at',
        'compliance_requested_by','compliance_submitted_at',
        'compliance_changes_requested_at','compliance_changes_requested_by',
        'compliance_change_reason','compliance_completed_at',
        'compliance_completed_by','compliance_last_resource_edit_at',
        'compliance_notification_sent_at','compliance_notification_error'
      )
  )=12 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'workflow dispatch is server-only and role-bound', CASE
    WHEN workflow_dispatch IS NULL THEN 'FAIL'
    WHEN has_function_privilege('anon',workflow_dispatch,'EXECUTE')
      OR has_function_privilege('authenticated',workflow_dispatch,'EXECUTE')
      OR NOT has_function_privilege('service_role',workflow_dispatch,'EXECUTE') THEN 'FAIL'
    WHEN position('auth.role() IS DISTINCT FROM ''service_role''' IN pg_get_functiondef(workflow_dispatch))=0 THEN 'FAIL'
    WHEN position('v_role NOT IN (''admin'', ''pm'', ''client_relations'')' IN pg_get_functiondef(workflow_dispatch))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Compliance requires a successful General test only when prompted', CASE
    WHEN workflow_dispatch IS NULL THEN 'FAIL'
    WHEN position('resource_has_successful_general_test_048' IN pg_get_functiondef(workflow_dispatch))=0 THEN 'FAIL'
    WHEN position('compliance_phase_status <> ''Not requested''' IN pg_get_functiondef(workflow_dispatch))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'portal Compliance projection is own-resource and excludes ISO', CASE
    WHEN portal_read IS NULL OR portal_save IS NULL OR portal_submit IS NULL THEN 'FAIL'
    WHEN position('current_external_resource_id()' IN pg_get_functiondef(portal_read))=0 THEN 'FAIL'
    WHEN position('iso_eligibility' IN pg_get_functiondef(portal_read))>0 THEN 'FAIL'
    WHEN NOT has_function_privilege('authenticated',portal_read,'EXECUTE') THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'portal writes are phase-bound and cannot verify evidence', CASE
    WHEN portal_save IS NULL OR portal_submit IS NULL THEN 'FAIL'
    WHEN position('compliance_phase_status NOT IN' IN pg_get_functiondef(portal_save))=0 THEN 'FAIL'
    WHEN position('FALSE' IN pg_get_functiondef(portal_save))=0 THEN 'FAIL'
    WHEN position('Compliance evidence cannot be submitted now' IN pg_get_functiondef(portal_submit))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Compliance R2 dispatcher permits only exact linked Resource or operations', CASE
    WHEN file_dispatch IS NULL THEN 'FAIL'
    WHEN has_function_privilege('anon',file_dispatch,'EXECUTE')
      OR has_function_privilege('authenticated',file_dispatch,'EXECUTE')
      OR NOT has_function_privilege('service_role',file_dispatch,'EXECUTE') THEN 'FAIL'
    WHEN position('v_actor_resource_id = p_resource_id' IN pg_get_functiondef(file_dispatch))=0 THEN 'FAIL'
    WHEN position('v_actor_resource_id = v_file.resource_id' IN pg_get_functiondef(file_dispatch))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Approved Job qualifications contain volume and no financial value', CASE
    WHEN job_qualifications IS NULL THEN 'FAIL'
    WHEN position('job.status = ''Approved''' IN pg_get_functiondef(job_qualifications))=0 THEN 'FAIL'
    WHEN position('''quantity''' IN pg_get_functiondef(job_qualifications))=0
      OR position('''unit''' IN pg_get_functiondef(job_qualifications))=0 THEN 'FAIL'
    WHEN position('supplier_amount' IN pg_get_functiondef(job_qualifications))>0
      OR position('supplier_rate' IN pg_get_functiondef(job_qualifications))>0
      OR position('supplier_currency' IN pg_get_functiondef(job_qualifications))>0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Compliance phase does not gate Job eligibility', CASE WHEN NOT EXISTS (
    SELECT 1 FROM pg_proc procedure
    WHERE procedure.pronamespace='public'::regnamespace
      AND procedure.proname IN (
        'search_job_candidates','create_job_offer_from_rate',
        'assign_job_and_issue_po','assign_job_and_issue_po_inherit_rate_unit',
        'assign_job_and_issue_po_flat_fee'
      )
      AND position('compliance_phase_status' IN pg_get_functiondef(procedure.oid))>0
  ) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'Blind CV retains dynamic experience and omits ISO', CASE
    WHEN blind_cv IS NULL THEN 'FAIL'
    WHEN position('professional_experience_duration_047' IN pg_get_functiondef(blind_cv))=0 THEN 'FAIL'
    WHEN position('iso_eligibility' IN pg_get_functiondef(blind_cv))>0 THEN 'FAIL'
    ELSE 'PASS' END FROM target
)
SELECT check_name,result FROM checks ORDER BY check_name;
