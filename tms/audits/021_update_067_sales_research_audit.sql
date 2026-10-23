-- Update 067 read-only installation audit. Expected: all rows PASS.
WITH expected(name,domain) AS (VALUES
 ('Acclaro','acclaro.com'),('Acolad','acolad.com'),('Argos Multilingual','argosmultilingual.com'),
 ('ASPENA','aspena.com'),('CETRA','cetra.com'),('CPSL','cpsl.com'),
 ('EC Innovations','ecinnovations.com'),('Global Lingo','global-lingo.com'),
 ('Global Textware','globaltextware.nl'),('IOLAR','iolar.com'),
 ('LanguageLine Solutions','languageline.com'),('LanguageWire','languagewire.com'),
 ('Lionbridge','lionbridge.com'),('Parenty Reitmeier','parentyreitmeier.com'),
 ('Questel','questel.com'),('RWS','rws.com'),('Seprotec','seprotec.com'),('Side','side.inc'),
 ('talk finance','talkfinance.biz'),('thebigword','thebigword.com'),
 ('TransPerfect','transperfect.com'),('Translate.One','translate.one'),('Vistatec','vistatec.com'),
 ('Welocalize','welocalize.com'),('ZELENKA','zelenka-translations.com'),('t''works','t-works.eu')
), worker AS (
 SELECT p.oid,p.prosecdef,p.proconfig,p.proacl,p.proowner,p.prosrc
 FROM (SELECT to_regprocedure('public.sales_system_067(text,jsonb)') oid) target
 LEFT JOIN pg_proc p ON p.oid=target.oid
), checks(check_name,ok) AS (
 VALUES
 ('Research profile column installed',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sales_settings' AND column_name='research_profile' AND data_type='jsonb' AND is_nullable='NO')),
 ('Research profile constraint validated',EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_settings'::regclass AND conname='sales_settings_research_profile_067' AND convalidated)),
 ('Curated profile active',EXISTS(SELECT 1 FROM sales_settings WHERE research_profile->>'version'='1' AND research_profile->>'ideal_buyer' LIKE '%multi-language LSP%' AND research_profile->'exclude' ? 'Retodo Ops and retodo-ops.com')),
 ('Automatic research remains off',NOT EXISTS(SELECT 1 FROM sales_settings WHERE research_enabled)),
 ('All 26 canonical candidates present',(SELECT count(*) FROM expected e WHERE EXISTS(SELECT 1 FROM sales_prospects p WHERE p.domain=e.domain OR regexp_replace(lower(p.name),'[^a-z0-9]','','g')=regexp_replace(lower(e.name),'[^a-z0-9]','','g')))=26),
 ('New canonical candidates are qualified or further',(SELECT count(*) FROM expected e WHERE EXISTS(SELECT 1 FROM sales_prospects p WHERE (p.domain=e.domain OR regexp_replace(lower(p.name),'[^a-z0-9]','','g')=regexp_replace(lower(e.name),'[^a-z0-9]','','g')) AND p.stage IN('qualified','contacted','replied','opportunity','won','lost','suppressed')))=26),
 ('Public role contacts remain unverified',NOT EXISTS(SELECT 1 FROM sales_contacts WHERE email IN('resourcemanagement@ecinnovations.com','cv@seprotec.com','dataforce.sourcing@transperfect.com','vendors@zelenka.cz') AND verified_at IS NOT NULL)),
 ('No outreach seeded',NOT EXISTS(SELECT 1 FROM sales_conversations c JOIN sales_prospects p ON p.id=c.prospect_id WHERE p.domain IN(SELECT domain FROM expected))),
 ('Update 067 worker exists',(SELECT oid IS NOT NULL FROM worker)),
 ('Update 067 worker remains SECURITY DEFINER',(SELECT prosecdef FROM worker)),
 ('Update 067 worker search path remains public',(SELECT 'search_path=public'=ANY(proconfig) FROM worker)),
 ('Update 067 worker is service-only',(SELECT has_function_privilege('service_role',oid,'EXECUTE') AND NOT has_function_privilege('authenticated',oid,'EXECUTE') AND NOT has_function_privilege('anon',oid,'EXECUTE') FROM worker)),
 ('Update 067 worker keeps service claim guard',(SELECT position('auth.role() IS DISTINCT FROM ''service_role''' IN prosrc)>0 FROM worker)),
 ('Research context and outcome counters installed',(SELECT position('research_context' IN prosrc)>0 AND position('validation_rejected' IN prosrc)>0 AND position('duplicates' IN prosrc)>0 AND position('suppressions' IN prosrc)>0 AND position('conflicts' IN prosrc)>0 FROM worker)),
 ('Previous worker retained',to_regprocedure('public.sales_system_063(text,jsonb)') IS NOT NULL)
 )
SELECT check_name,CASE WHEN coalesce(ok,false) THEN 'PASS' ELSE 'FAIL' END result
FROM checks ORDER BY check_name;
