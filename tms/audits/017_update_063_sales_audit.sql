-- Update 063 installation audit. Read-only. Every row should report PASS.
WITH sales_tables(name) AS (VALUES
 ('sales_settings'),('sales_prospects'),('sales_contacts'),('sales_suppressions'),
 ('sales_conversations'),('sales_messages'),('sales_approvals'),('sales_events'),
 ('sales_materials'),('sales_ai_jobs'),('sales_runtime'),('sales_tasks')
), checks AS (
 SELECT 'Table protected: '||t.name AS check_name,
  EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname=t.name AND c.relrowsecurity
   AND NOT has_table_privilege('anon',c.oid,'SELECT')
   AND NOT has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE')
   AND has_table_privilege('authenticated',c.oid,'SELECT')) AS ok
 FROM sales_tables t
 UNION ALL SELECT 'Administrator RLS on all Sales tables',
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename IN(SELECT name FROM sales_tables)
   AND policyname='sales_admin_read' AND cmd='SELECT' AND qual LIKE '%sales_is_admin_063%')=12
 UNION ALL SELECT 'Administrator workspace RPC',
  has_function_privilege('authenticated','public.sales_workspace_063(text,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('anon','public.sales_workspace_063(text,integer,integer)','EXECUTE')
 UNION ALL SELECT 'Browser command RPC restricted',
  has_function_privilege('authenticated','public.sales_command_063(text,jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.sales_command_063(text,jsonb)','EXECUTE')
 UNION ALL SELECT 'Worker RPC service-only',
  has_function_privilege('service_role','public.sales_system_063(text,jsonb)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.sales_system_063(text,jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.sales_system_063(text,jsonb)','EXECUTE')
 UNION ALL SELECT 'Worker has service claim guard',
  position('auth.role() IS DISTINCT FROM ''service_role''' in pg_get_functiondef('public.sales_system_063(text,jsonb)'::regprocedure))>0
 UNION ALL SELECT 'Administrator access checks enabled status',
  position('current_user_access_enabled()' in pg_get_functiondef('public.sales_is_admin_063()'::regprocedure))>0
 UNION ALL SELECT 'Approval history immutable',
  EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.sales_approvals'::regclass AND tgname='sales_approvals_immutable' AND tgenabled='O')
 UNION ALL SELECT 'Activity history immutable',
  EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.sales_events'::regclass AND tgname='sales_events_immutable' AND tgenabled='O')
 UNION ALL SELECT 'One open conversation per company',to_regclass('public.sales_one_open_company_idx') IS NOT NULL
 UNION ALL SELECT 'Outbox due index installed',to_regclass('public.sales_due_idx') IS NOT NULL
 UNION ALL SELECT 'Sales From constrained to Eli alias',
  EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_conversations'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%sender%eli.s@retodo-ops.com%')
 UNION ALL SELECT 'Sales Reply-To constrained to Eli alias',
  EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_conversations'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%reply_to%eli.s@retodo-ops.com%')
 UNION ALL SELECT 'Sending defaults to off',
  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sales_settings' AND column_name='sending_enabled' AND column_default='false')
 UNION ALL SELECT 'Research defaults to off',
  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sales_settings' AND column_name='research_enabled' AND column_default='false')
 UNION ALL SELECT 'Monthly ceiling cannot exceed EUR 30',
  EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_settings'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%monthly_cap%30%')
 UNION ALL SELECT 'Settings singleton exists',(SELECT count(*) FROM public.sales_settings)=1
 UNION ALL SELECT 'Runtime singleton exists',(SELECT count(*) FROM public.sales_runtime)=1
 UNION ALL SELECT 'Uncertain send state supported',
  EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_messages'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%uncertain%')
 UNION ALL SELECT 'Unrelated Update 062 search retained',to_regprocedure('public.tms_search_062(text,integer)') IS NOT NULL
)
SELECT check_name,CASE WHEN coalesce(ok,false) THEN 'PASS' ELSE 'FAIL' END AS result FROM checks ORDER BY check_name;
