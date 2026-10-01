-- Read-only installation audit after migration 056. All rows should PASS.
WITH f(signature) AS (VALUES('public.report_bulk_status_062(text,uuid[],text)'),('public.invoice_revise_062(uuid,integer,jsonb,text)'),('public.tms_search_062(text,integer)')),
checks AS (
 SELECT signature||' exists' check_name,to_regprocedure(signature) IS NOT NULL ok FROM f
 UNION ALL SELECT signature||' authenticated execute',COALESCE(has_function_privilege('authenticated',to_regprocedure(signature),'EXECUTE'),false) FROM f
 UNION ALL SELECT signature||' no anonymous execute',to_regprocedure(signature) IS NOT NULL AND NOT has_function_privilege('anon',to_regprocedure(signature),'EXECUTE') FROM f
 UNION ALL SELECT signature||' checks access',COALESCE(position('invoice_assert_access_061' IN p.prosrc)>0,false) FROM f LEFT JOIN pg_proc p ON p.oid=to_regprocedure(signature)
 UNION ALL SELECT 'Search respects invoker RLS',NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.tms_search_062(text,integer)')
 UNION ALL SELECT 'Revision archive RLS',relrowsecurity FROM pg_class WHERE oid=to_regclass('public.invoice_revisions_062')
 UNION ALL SELECT 'Invoice numbers RLS',relrowsecurity FROM pg_class WHERE oid=to_regclass('public.invoice_numbers_062')
 UNION ALL SELECT 'No direct archive mutations',NOT has_table_privilege('authenticated','public.invoice_revisions_062','INSERT,UPDATE,DELETE,TRUNCATE')
 UNION ALL SELECT 'No direct number mutations',NOT has_table_privilege('authenticated','public.invoice_numbers_062','INSERT,UPDATE,DELETE,TRUNCATE')
 UNION ALL SELECT 'No direct invoice mutations',NOT has_table_privilege('authenticated','public.client_invoices','INSERT,UPDATE,DELETE,TRUNCATE')
 UNION ALL SELECT name||' enabled',EXISTS(SELECT 1 FROM pg_trigger WHERE tgname=name AND tgenabled<>'D') FROM (VALUES('invoice_scoop_state_062'),('scoop_financial_state_guard_062'),('invoice_number_reserve_062'))t(name)
 UNION ALL SELECT 'Reports expose Scoop financial status',position('s.financial_status' IN prosrc)>0 FROM pg_proc WHERE oid=to_regprocedure('public.tms_report_061(text,jsonb,integer,integer,text,boolean)')
)
SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
