-- RetodoOps TMS — Update 050 audit.
-- Run after 049_job_approval_history_compliance_agreement.sql.
-- Read-only. Every result row must be PASS.

WITH target AS (
  SELECT
    to_regprocedure('public.save_job_overview(uuid,jsonb)') AS job_save,
    to_regprocedure('public.feed_approved_job_to_resource_history()') AS history_feed,
    to_regprocedure('public.get_blind_cv_data(uuid)') AS blind_cv,
    to_regprocedure('public.resource_portal_framework_agreement_050()') AS portal_agreement,
    to_regprocedure('public.resource_portal_accept_framework_agreement_050(jsonb)') AS accept_agreement,
    to_regprocedure('public.resource_framework_agreement_summary_050(uuid)') AS agreement_summary,
    to_regprocedure('public.resource_portal_submit_compliance_048()') AS portal_submit,
    to_regprocedure('public.resource_compliance_file_delete_050(text,uuid,uuid,text)') AS file_delete,
    to_regprocedure('public.resource_compliance_submission_notification_050(text,uuid,uuid,text)') AS submission_notice
), checks(check_name, result) AS (
  SELECT 'status-only Job save does not define a PO change', CASE
    WHEN job_save IS NULL THEN 'FAIL'
    WHEN position('v_old.status IS DISTINCT FROM v_new.status'
                  IN pg_get_functiondef(job_save)) > 0 THEN 'FAIL'
    WHEN position('v_po_changed := v_terms_changed'
                  IN pg_get_functiondef(job_save)) = 0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Project History has approximate quantity and unit', CASE WHEN (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='resource_project_history'
      AND column_name IN ('quantity','unit')
  )=2 THEN 'PASS' ELSE 'FAIL' END

  UNION ALL SELECT 'approved Job history feed updates size without money', CASE
    WHEN history_feed IS NULL THEN 'FAIL'
    WHEN position('NEW.quantity' IN pg_get_functiondef(history_feed))=0
      OR position('NEW.unit' IN pg_get_functiondef(history_feed))=0 THEN 'FAIL'
    WHEN position('supplier_amount' IN pg_get_functiondef(history_feed))>0
      OR position('supplier_rate' IN pg_get_functiondef(history_feed))>0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Blind CV contains current history size and preserves privacy', CASE
    WHEN blind_cv IS NULL THEN 'FAIL'
    WHEN position('''quantity'', history.quantity' IN pg_get_functiondef(blind_cv))=0
      OR position('''unit'', history.unit' IN pg_get_functiondef(blind_cv))=0 THEN 'FAIL'
    WHEN position('resource.legal_name' IN pg_get_functiondef(blind_cv))>0
      OR position('resource.email' IN pg_get_functiondef(blind_cv))>0
      OR position('iso_eligibility' IN pg_get_functiondef(blind_cv))>0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'framework Agreement table is private and RLS-enabled', CASE
    WHEN to_regclass('public.resource_framework_agreements') IS NULL THEN 'FAIL'
    WHEN NOT (SELECT relrowsecurity FROM pg_class
              WHERE oid='public.resource_framework_agreements'::regclass) THEN 'FAIL'
    WHEN has_table_privilege('anon','public.resource_framework_agreements','SELECT')
      OR has_table_privilege('anon','public.resource_framework_agreements','INSERT')
      OR has_table_privilege('anon','public.resource_framework_agreements','UPDATE')
      OR has_table_privilege('anon','public.resource_framework_agreements','DELETE')
      OR has_table_privilege('authenticated','public.resource_framework_agreements','SELECT')
      OR has_table_privilege('authenticated','public.resource_framework_agreements','INSERT')
      OR has_table_privilege('authenticated','public.resource_framework_agreements','UPDATE')
      OR has_table_privilege('authenticated','public.resource_framework_agreements','DELETE') THEN 'FAIL'
    ELSE 'PASS' END

  UNION ALL SELECT 'Agreement acceptance stores exact version hash and audit trail', CASE
    WHEN portal_agreement IS NULL OR accept_agreement IS NULL
      OR agreement_summary IS NULL THEN 'FAIL'
    WHEN position('current_external_resource_id()'
                  IN pg_get_functiondef(accept_agreement))=0 THEN 'FAIL'
    WHEN position('0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a'
                  IN pg_get_functiondef(accept_agreement))=0 THEN 'FAIL'
    WHEN position('Framework agreement accepted'
                  IN pg_get_functiondef(accept_agreement))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Compliance submit requires accepted current Agreement', CASE
    WHEN portal_submit IS NULL THEN 'FAIL'
    WHEN position('resource_framework_agreements'
                  IN pg_get_functiondef(portal_submit))=0 THEN 'FAIL'
    WHEN position('Read and accept the Freelancer Framework Agreement'
                  IN pg_get_functiondef(portal_submit))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'Compliance file deletion is server-only and soft-deletes metadata', CASE
    WHEN file_delete IS NULL THEN 'FAIL'
    WHEN has_function_privilege('anon',file_delete,'EXECUTE')
      OR has_function_privilege('authenticated',file_delete,'EXECUTE')
      OR NOT has_function_privilege('service_role',file_delete,'EXECUTE') THEN 'FAIL'
    WHEN position('v_actor_resource_id = v_file.resource_id'
                  IN pg_get_functiondef(file_delete))=0 THEN 'FAIL'
    WHEN position('upload_status = ''Deleted'''
                  IN pg_get_functiondef(file_delete))=0 THEN 'FAIL'
    WHEN position('''Delete''' IN pg_get_functiondef(file_delete))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'submission notification is durable and exact-resource bound', CASE
    WHEN submission_notice IS NULL THEN 'FAIL'
    WHEN (SELECT count(*) FROM information_schema.columns
          WHERE table_schema='public' AND table_name='resources'
            AND column_name IN (
              'compliance_submission_notification_sent_at',
              'compliance_submission_notification_error'))<>2 THEN 'FAIL'
    WHEN has_function_privilege('anon',submission_notice,'EXECUTE')
      OR has_function_privilege('authenticated',submission_notice,'EXECUTE')
      OR NOT has_function_privilege('service_role',submission_notice,'EXECUTE') THEN 'FAIL'
    WHEN position('v_resource.profile_id = p_actor_id'
                  IN pg_get_functiondef(submission_notice))=0 THEN 'FAIL'
    ELSE 'PASS' END FROM target

  UNION ALL SELECT 'external portal Agreement projection excludes internal ISO', CASE
    WHEN portal_agreement IS NULL THEN 'FAIL'
    WHEN position('current_external_resource_id()'
                  IN pg_get_functiondef(portal_agreement))=0 THEN 'FAIL'
    WHEN position('iso_eligibility'
                  IN pg_get_functiondef(portal_agreement))>0 THEN 'FAIL'
    ELSE 'PASS' END FROM target
)
SELECT check_name, result FROM checks ORDER BY check_name;
