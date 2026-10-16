-- Read-only installation checks. Expect 9 PASS rows after migration 062.
WITH checks AS (
 SELECT 'document column' check_name, EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='client_invoices' AND column_name='document_details_066' AND data_type='jsonb' AND is_nullable='NO') ok
 UNION ALL SELECT 'draft wrapper',to_regprocedure('public.invoice_save_066(jsonb,uuid,integer)') IS NOT NULL
 UNION ALL SELECT 'revision wrapper',to_regprocedure('public.invoice_revise_066(uuid,integer,jsonb,text,boolean)') IS NOT NULL
 UNION ALL SELECT 'validator internal',NOT has_function_privilege('authenticated','public.invoice_document_validate_066(jsonb)','EXECUTE')
 UNION ALL SELECT 'draft authenticated',has_function_privilege('authenticated','public.invoice_save_066(jsonb,uuid,integer)','EXECUTE')
 UNION ALL SELECT 'revision authenticated',has_function_privilege('authenticated','public.invoice_revise_066(uuid,integer,jsonb,text,boolean)','EXECUTE')
 UNION ALL SELECT 'anonymous denied',NOT has_function_privilege('anon','public.invoice_save_066(jsonb,uuid,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.invoice_revise_066(uuid,integer,jsonb,text,boolean)','EXECUTE')
 UNION ALL SELECT 'invoice RLS',relrowsecurity FROM pg_class WHERE oid='public.client_invoices'::regclass
 UNION ALL SELECT 'immutable guard',EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.client_invoices'::regclass AND tgname='invoices_immutable_061' AND tgenabled='O')
) SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
