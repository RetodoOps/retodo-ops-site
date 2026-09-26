-- Update 059 read-only installation audit. Run AFTER migration 053.
-- Expected: every row PASS. Does not replace authenticated UI acceptance.
WITH expected(signature) AS (VALUES
 ('public.tms_report(text,jsonb,integer,integer,text,boolean)'),
 ('public.tms_report_options_059()')
), functions AS (
 SELECT e.signature,p.* FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
), checks AS (
 SELECT signature||' exists' check_name,oid IS NOT NULL ok FROM functions
 UNION ALL SELECT signature||' uses invoker rights',oid IS NOT NULL AND NOT prosecdef FROM functions
 UNION ALL SELECT signature||' authenticated can execute',COALESCE(has_function_privilege('authenticated',oid,'EXECUTE'),false) FROM functions
 UNION ALL SELECT signature||' anonymous cannot execute',oid IS NOT NULL AND NOT has_function_privilege('anon',oid,'EXECUTE') FROM functions
 UNION ALL SELECT signature||' fixed search path',COALESCE(proconfig @> ARRAY['search_path=public'],false) FROM functions
 UNION ALL SELECT signature||' API version 059',COALESCE(position('''059''' IN prosrc)>0,false) FROM functions
 UNION ALL SELECT signature||' company and active-access checks',COALESCE(position('is_company_user()' IN prosrc)>0 AND position('current_user_access_enabled()' IN prosrc)>0,false) FROM functions
 UNION ALL SELECT name||' RLS enabled',COALESCE(c.relrowsecurity,false)
 FROM (VALUES('projects'),('project_scoops'),('project_jobs'),('supplier_purchase_orders'),('supplier_po_versions'),('clients'),('client_accounts'),('resources')) t(name)
 LEFT JOIN pg_class c ON c.oid=to_regclass('public.'||name)
)
SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
