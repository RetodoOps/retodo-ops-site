-- Update 061 read-only installation audit, after 054 then 055. All rows should PASS.
WITH expected(signature,definer) AS (VALUES
 ('public.tms_report_061(text,jsonb,integer,integer,text,boolean)',false),
 ('public.invoice_workspace_061(uuid,text,integer,integer,uuid)',true),
 ('public.invoice_get_061(uuid)',true),('public.invoice_save_061(jsonb,uuid,integer)',true),
 ('public.invoice_issue_061(uuid,integer)',true),('public.invoice_cancel_draft_061(uuid,integer)',true),
 ('public.invoice_settings_save_061(jsonb,bigint)',true),('public.invoice_record_payment_061(uuid,numeric,date,text,text)',true)
), functions AS (SELECT e.*,p.* FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)),
 checks AS (
 SELECT signature||' exists with intended rights' check_name,oid IS NOT NULL AND prosecdef=definer ok FROM functions
 UNION ALL SELECT signature||' authenticated execute',COALESCE(has_function_privilege('authenticated',oid,'EXECUTE'),false) FROM functions
 UNION ALL SELECT signature||' no anonymous execute',oid IS NOT NULL AND NOT has_function_privilege('anon',oid,'EXECUTE') FROM functions
 UNION ALL SELECT signature||' fixed search path',COALESCE(proconfig @> ARRAY['search_path=public'],false) FROM functions
 UNION ALL SELECT signature||' checks caller access',COALESCE(position('invoice_assert_access_061' IN prosrc)>0 OR position('is_company_user' IN prosrc)>0,false) FROM functions
 UNION ALL SELECT name||' RLS enabled',COALESCE(c.relrowsecurity,false) FROM (VALUES('report_fx_rates'),('client_invoices'),('client_invoice_lines'),('payments'),('invoice_scoop_allocations_061'),('invoice_settings_061'),('invoice_events_061'))t(name) LEFT JOIN pg_class c ON c.oid=to_regclass('public.'||name)
 UNION ALL SELECT name||' no direct authenticated mutation',to_regclass('public.'||name) IS NOT NULL AND NOT has_table_privilege('authenticated','public.'||name,'INSERT,UPDATE,DELETE,TRUNCATE') FROM (VALUES('report_fx_rates'),('client_invoices'),('client_invoice_lines'),('payments'),('invoice_scoop_allocations_061'),('invoice_settings_061'),('invoice_events_061'))t(name)
 UNION ALL SELECT 'FX importer limited to service role',has_function_privilege('service_role','public.store_report_fx_061(date,jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','public.store_report_fx_061(date,jsonb)','EXECUTE') AND NOT has_function_privilege('anon','public.store_report_fx_061(date,jsonb)','EXECUTE')
 UNION ALL SELECT 'Scoop reservations unique',EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=to_regclass('public.invoice_scoop_allocations_061') AND contype='p')
 UNION ALL SELECT name||' guard enabled',EXISTS(SELECT 1 FROM pg_trigger WHERE tgname=name AND tgenabled<>'D') FROM (VALUES('invoice_lines_immutable_061'),('invoices_immutable_061'))t(name)
)
SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
