-- Read-only installation checks. Run after 061; every row should PASS.
WITH f(signature) AS (VALUES
 ('public.invoice_receive_payment_064(uuid,integer,text,numeric,date,text,uuid)'),
 ('public.invoice_delete_064(uuid,integer,text,boolean)')),
checks AS (
 SELECT 'Manual rows allow no Project or Scoop' check_name, NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='client_invoice_lines' AND column_name IN ('project_id','scoop_id') AND is_nullable='NO') ok
 UNION ALL
 SELECT signature||' exists' check_name,to_regprocedure(signature) IS NOT NULL ok FROM f
 UNION ALL SELECT signature||' authenticated execute',COALESCE(has_function_privilege('authenticated',to_regprocedure(signature),'EXECUTE'),false) FROM f
 UNION ALL SELECT signature||' no anonymous execute',to_regprocedure(signature) IS NOT NULL AND NOT has_function_privilege('anon',to_regprocedure(signature),'EXECUTE') FROM f
 UNION ALL SELECT signature||' admin check',COALESCE(position('invoice_assert_access_061(true,true)' IN p.prosrc)>0,false) FROM f LEFT JOIN pg_proc p ON p.oid=to_regprocedure(signature)
 UNION ALL SELECT 'Explicit revision exception',COALESCE(position('repair 056' IN prosrc)>0 AND position('retodo.invoice_revision_062' IN prosrc)>0,false) FROM pg_proc WHERE oid=to_regprocedure('public.invoice_immutable_061()')
 UNION ALL SELECT 'Scoped deletion exception',COALESCE(position('retodo.invoice_delete_064' IN prosrc)>0,false) FROM pg_proc WHERE oid=to_regprocedure('public.invoice_immutable_061()')
 UNION ALL SELECT 'Invoice protection trigger enabled',EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='invoices_immutable_061' AND tgenabled<>'D' AND tgfoid=to_regprocedure('public.invoice_immutable_061()'))
 UNION ALL SELECT 'Invoice row protection trigger enabled',EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='invoice_lines_immutable_061' AND tgenabled<>'D' AND tgfoid=to_regprocedure('public.invoice_immutable_061()'))
 UNION ALL SELECT 'No direct invoice or receipt mutations',NOT has_table_privilege('authenticated','public.client_invoices','INSERT,UPDATE,DELETE,TRUNCATE') AND NOT has_table_privilege('authenticated','public.payments','INSERT,UPDATE,DELETE,TRUNCATE')
 UNION ALL SELECT 'Idempotent payment key index',EXISTS(SELECT 1 FROM pg_index WHERE indexrelid=to_regclass('public.payments_receipt_key_064') AND indisunique AND indisvalid)
)
SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result FROM checks ORDER BY check_name;
