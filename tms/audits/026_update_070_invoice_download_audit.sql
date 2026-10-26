-- Read-only installation audit; expect 6 PASS.
WITH checks AS (
 SELECT 'new report RPC' check_name,to_regprocedure('public.invoice_report_070(jsonb,integer,integer,text,boolean)') IS NOT NULL ok
 UNION ALL SELECT 'authenticated report access',has_function_privilege('authenticated','public.invoice_report_070(jsonb,integer,integer,text,boolean)','EXECUTE')
 UNION ALL SELECT 'anonymous report denied',NOT has_function_privilege('anon','public.invoice_report_070(jsonb,integer,integer,text,boolean)','EXECUTE')
 UNION ALL SELECT 'payment status filters',position('Invalid payment status' IN pg_get_functiondef('public.invoice_report_070(jsonb,integer,integer,text,boolean)'::regprocedure))>0
 UNION ALL SELECT 'guarded saved invoice retrieval',to_regprocedure('public.invoice_get_061(uuid)') IS NOT NULL AND NOT has_function_privilege('anon','public.invoice_get_061(uuid)','EXECUTE')
 UNION ALL SELECT 'no direct finance writes',NOT has_table_privilege('authenticated','public.payments','INSERT') AND NOT has_table_privilege('authenticated','public.client_invoices','UPDATE')
) SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
