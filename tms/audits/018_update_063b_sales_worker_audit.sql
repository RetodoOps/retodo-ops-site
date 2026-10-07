-- Update 063B installation audit. Read-only; does not invoke the worker or send mail.
-- Every row should report PASS after migration 058.
WITH worker AS (
 SELECT p.oid,p.prosrc,p.prosecdef,p.proconfig,p.proacl,p.proowner
 FROM (SELECT to_regprocedure('public.sales_system_063(text,jsonb)') AS oid) target
 LEFT JOIN pg_proc p ON p.oid=target.oid
), checks AS (
 SELECT 'Sales worker RPC exists' AS check_name,oid IS NOT NULL AS ok FROM worker
 UNION ALL SELECT 'Worker remains SECURITY DEFINER',prosecdef FROM worker
 UNION ALL SELECT 'Worker search path remains public','search_path=public'=ANY(proconfig) FROM worker
 UNION ALL SELECT 'Service role retains worker access',has_function_privilege('service_role',oid,'EXECUTE') FROM worker
 UNION ALL SELECT 'Browser roles cannot execute worker',
  NOT has_function_privilege('anon',oid,'EXECUTE') AND NOT has_function_privilege('authenticated',oid,'EXECUTE') FROM worker
 UNION ALL SELECT 'PUBLIC cannot execute worker',oid IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) acl
  WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') FROM worker
 UNION ALL SELECT 'Service claim check retained',position('auth.role() IS DISTINCT FROM ''service_role''' in prosrc)>0 FROM worker
 UNION ALL SELECT 'Thread query uses an unambiguous conversation alias',
  position('SELECT thread_conversation.*' in prosrc)>0
  AND position('FROM public.sales_conversations AS thread_conversation' in prosrc)>0
  AND position('SELECT c.*' in prosrc)=0 FROM worker
 UNION ALL SELECT 'Thread eligibility filters retained',
  position('thread_conversation.thread_id IS NOT NULL' in prosrc)>0
  AND position('thread_conversation.state NOT IN(''closed'',''suppressed'')' in prosrc)>0 FROM worker
 UNION ALL SELECT 'Oldest unchecked threads first; maximum 20',
  position('ORDER BY thread_conversation.synced_at NULLS FIRST LIMIT 20' in prosrc)>0 FROM worker
 UNION ALL SELECT 'Thread result still returns a JSON array',
  position('jsonb_agg(thread_row)' in prosrc)>0 AND position(') AS thread_row),''[]''::jsonb)' in prosrc)>0 FROM worker
)
SELECT check_name,CASE WHEN coalesce(ok,false) THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks ORDER BY check_name;
