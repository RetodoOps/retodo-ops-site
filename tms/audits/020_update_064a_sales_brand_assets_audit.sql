-- Update 064A read-only installation audit. Expected: all 9 rows PASS.
WITH checks(check_name,ok) AS (VALUES
 ('Current signature uses corrected brand renderer',EXISTS(SELECT 1 FROM sales_settings WHERE email_signature->>'version'='2')),
 ('New settings default uses corrected renderer',EXISTS(SELECT 1 FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum WHERE d.adrelid='public.sales_settings'::regclass AND a.attname='email_signature' AND position('"version": 2' IN pg_get_expr(d.adbin,d.adrelid))>0)),
 ('Legacy signatures remain valid',EXISTS(SELECT 1 FROM sales_settings WHERE public.sales_signature_valid_064(jsonb_set(email_signature,'{version}','1'::jsonb)))),
 ('Corrected signatures are valid',EXISTS(SELECT 1 FROM sales_settings WHERE public.sales_signature_valid_064(email_signature))),
 ('Unknown signature renderer rejected',EXISTS(SELECT 1 FROM sales_settings WHERE NOT public.sales_signature_valid_064(jsonb_set(email_signature,'{version}','3'::jsonb)))),
 ('Approval requires a compatible signature preview',position('NOT IN (''2'',m.signature->>''version'')' IN pg_get_functiondef('public.sales_command_063(text,jsonb)'::regprocedure))>0),
 ('Approved signature checked immediately before sending',position('Approved signature does not match' IN pg_get_functiondef('public.sales_system_063(text,jsonb)'::regprocedure))>0),
 ('Direct browser writes and worker calls remain blocked',NOT has_table_privilege('authenticated','public.sales_settings','UPDATE') AND NOT has_table_privilege('authenticated','public.sales_messages','UPDATE') AND NOT has_function_privilege('authenticated','public.sales_system_063(text,jsonb)','EXECUTE')),
 ('Worker polling correction retained',position('thread_conversation.thread_id' IN pg_get_functiondef('public.sales_system_063(text,jsonb)'::regprocedure))>0)
)
SELECT check_name,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result FROM checks ORDER BY check_name;
