-- Read-only; run after migration 066. Expect 7 PASS, including on invoice UI 066.
WITH fn AS (
 SELECT p.prosrc,p.prosecdef,p.proconfig
 FROM pg_proc p WHERE p.oid=to_regprocedure('public.invoice_save_061(jsonb,uuid,integer)')
), checks AS (
 SELECT 'manual row uses typed project id' check_name,
  EXISTS(SELECT 1 FROM fn WHERE position('VALUES(v_id,v_project_id,v_scoop' IN prosrc)>0
   AND position('CASE WHEN v_scoop IS NOT NULL THEN sc.project_id END' IN prosrc)=0) ok
 UNION ALL SELECT 'project id reset per row',EXISTS(SELECT 1 FROM fn WHERE position('v_project_id:=NULL;v_n:=v_n+1' IN prosrc)>0)
 UNION ALL SELECT 'source project assigned inside Scoop branch',EXISTS(SELECT 1 FROM fn WHERE position('v_project_id:=sc.project_id;' IN prosrc)>0)
 UNION ALL SELECT 'security definer and fixed search path',EXISTS(SELECT 1 FROM fn WHERE prosecdef AND 'search_path=public'=ANY(proconfig))
 UNION ALL SELECT 'authenticated save available',has_function_privilege('authenticated','public.invoice_save_061(jsonb,uuid,integer)','EXECUTE')
 UNION ALL SELECT 'anonymous save denied',NOT has_function_privilege('anon','public.invoice_save_061(jsonb,uuid,integer)','EXECUTE')
 UNION ALL SELECT 'no direct invoice writes',NOT has_table_privilege('authenticated','public.client_invoices','INSERT') AND NOT has_table_privilege('authenticated','public.client_invoice_lines','INSERT')
) SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
