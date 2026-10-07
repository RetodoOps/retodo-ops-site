-- Update 064 read-only installation audit. Expected: all 12 rows PASS.
WITH checks(check_name,ok) AS (VALUES
 ('Signature validator installed',to_regprocedure('public.sales_signature_valid_064(jsonb,boolean)') IS NOT NULL),
 ('Signature default setting installed',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sales_settings' AND column_name='signature_enabled' AND is_nullable='NO')),
 ('Signature settings validated',EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_settings'::regclass AND conname='sales_settings_signature_valid_064' AND convalidated)),
 ('Message signatures validated',EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_messages'::regclass AND conname='sales_messages_signature_valid_064' AND convalidated)),
 ('Configured signature valid',NOT EXISTS(SELECT 1 FROM public.sales_settings WHERE NOT public.sales_signature_valid_064(email_signature))),
 ('Stored message signatures valid',NOT EXISTS(SELECT 1 FROM public.sales_messages WHERE NOT public.sales_signature_valid_064(signature,true))),
 ('Signature edit control installed',position('signature_mode' IN pg_get_functiondef('public.sales_command_063(text,jsonb)'::regprocedure))>0),
 ('Signature checked immediately before sending',position('Approved signature does not match' IN pg_get_functiondef('public.sales_system_063(text,jsonb)'::regprocedure))>0),
 ('Worker polling correction retained',position('thread_conversation.thread_id' IN pg_get_functiondef('public.sales_system_063(text,jsonb)'::regprocedure))>0),
 ('Sales settings and messages retain RLS',(SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN('public.sales_settings'::regclass,'public.sales_messages'::regclass))),
 ('Browser cannot write tables or call worker directly',NOT has_table_privilege('authenticated','public.sales_settings','UPDATE') AND NOT has_table_privilege('authenticated','public.sales_messages','UPDATE') AND NOT has_function_privilege('authenticated','public.sales_system_063(text,jsonb)','EXECUTE')),
 ('Admin command grant and server worker grant retained',has_function_privilege('authenticated','public.sales_command_063(text,jsonb)','EXECUTE') AND has_function_privilege('service_role','public.sales_system_063(text,jsonb)','EXECUTE') AND NOT has_function_privilege('anon','public.sales_command_063(text,jsonb)','EXECUTE'))
)
SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result FROM checks ORDER BY check_name;
