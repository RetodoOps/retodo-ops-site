-- Update 067: curated prospect learning set and auditable AI research outcomes.
-- Requires the installed Sales signature baseline. Forward-only and idempotent.
BEGIN;

DO $$ BEGIN
 IF to_regprocedure('public.sales_system_063(text,jsonb)') IS NULL
  OR to_regprocedure('public.sales_signature_valid_064(jsonb,boolean)') IS NULL THEN
  RAISE EXCEPTION 'Install the Sales 064A baseline before Update 067';
 END IF;
END $$;

ALTER TABLE public.sales_settings
 ADD COLUMN IF NOT EXISTS research_profile jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$ BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM pg_constraint
  WHERE conrelid='public.sales_settings'::regclass
   AND conname='sales_settings_research_profile_067'
 ) THEN
  ALTER TABLE public.sales_settings ADD CONSTRAINT sales_settings_research_profile_067
   CHECK(jsonb_typeof(research_profile)='object' AND octet_length(research_profile::text)<=50000);
 END IF;
END $$;

UPDATE public.sales_settings SET
 research_enabled=false,
 research_profile=$profile$
{
  "version": 1,
  "generated_on": "2026-10-22",
  "ideal_buyer": "A current multi-language LSP or localization company that demonstrably buys external language capacity and can need Nordic target languages.",
  "source_languages": ["English", "German", "French"],
  "target_languages": ["Norwegian Bokmal", "Norwegian Nynorsk", "Swedish", "Danish", "Finnish", "Icelandic"],
  "required_signals": [
    "Current operating company and canonical domain",
    "Current official supplier, vendor, agency, freelancer or linguist sourcing route, or demonstrated recent purchasing in the supplied client history",
    "Multilingual or global delivery compatible with specialist Nordic capacity"
  ],
  "strong_signals": [
    "Official supplier or agency application page",
    "Official freelancer or linguist recruitment page",
    "Recent historical order from the supplied buyer data",
    "Current official evidence of Nordic language demand"
  ],
  "exclude": [
    "Retodo Ops and retodo-ops.com",
    "Direct end clients in this agency-buyer search",
    "Individuals",
    "Directories and marketplaces",
    "Inactive, acquired or rebranded aliases as separate prospects",
    "Pure Nordic competitors or suppliers without evidence that they buy outside capacity"
  ],
  "positive_examples": [
    "Acclaro", "Acolad", "Argos Multilingual", "ASPENA", "CETRA", "CPSL",
    "EC Innovations", "Global Lingo", "Global Textware", "IOLAR",
    "LanguageLine Solutions", "LanguageWire", "Lionbridge", "Parenty Reitmeier",
    "Questel", "RWS", "Seprotec", "Side", "talk finance", "thebigword",
    "TransPerfect", "Translate.One", "Vistatec", "Welocalize", "ZELENKA", "t'works"
  ],
  "canonical_aliases": {
    "Acclaro": ["Jonckers"],
    "Acolad": ["Technicis", "Amplexor", "Telelingua", "AranchoDoc", "Sajan"],
    "Argos Multilingual": ["Venga Global"],
    "LanguageLine Solutions": ["Capita Translation and Interpreting"],
    "LanguageWire": ["Delingua", "WHP", "Xplanation"],
    "Questel": ["Morningside"],
    "RWS": ["SDL", "Moravia"],
    "Side": ["PTW"],
    "TransPerfect": ["Apostroph", "Semantix", "Unbabel"],
    "Translate.One": ["Commit Global", "Intertext", "Trustpoint.One"],
    "t'works": ["ASI", "Wohanka"]
  },
  "merge_reverify_examples": {
    "Akorbi": "Propio Language Services",
    "United Language Group": "Propio Language Services",
    "Language Connect": "THG Fluently",
    "Straker Translations": "Straker",
    "Summa Linguae": "DATAmundi.ai"
  },
  "negative_examples": [
    {"name": "Retodo Ops", "reason": "Seller self-match"},
    {"name": "e2f", "reason": "Changed scope; current business is TrustScale AI verification"},
    {"name": "The Walt Disney Company Nordic", "reason": "Direct end client outside this agency-buyer search"},
    {"name": "Translators.com", "reason": "Directory or marketplace, not a confirmed buyer"},
    {"name": "Generic Nordic translation agency", "reason": "Nordic service coverage alone does not prove outside-capacity buying"}
  ],
  "confidence_threshold": 80,
  "automatic_research_enabled": false
}
$profile$::jsonb,
 updated_at=now()
WHERE id;

-- Seed only current canonical companies. Existing non-research workflow stages,
-- user notes and existing contacts are preserved.
WITH seed(name,domain,country,score,fit_note,source_url) AS (VALUES
 ('Acclaro','acclaro.com','United States',91,'Demonstrated localization buyer with recent supplied purchase history and a current public careers route; public Finnish coverage supports Nordic fit.','https://www.acclaro.com/company/careers'),
 ('Acolad','acolad.com','France',96,'Global LSP with an active freelance community and repeated recent purchase history across current and predecessor group entities.','https://www.acolad.com/en/about/community'),
 ('Argos Multilingual','argosmultilingual.com','United States',88,'Current global localization provider with linguist-facing careers content and demonstrated purchase history under Argos and Venga.','https://careers.argosmultilingual.com/blog/'),
 ('ASPENA','aspena.com','Czech Republic',94,'Current language-services buyer with an explicit supplier application route and recent supplied purchase history.','https://www.aspena.com/i-want-to-be-a-supplier'),
 ('CETRA','cetra.com','United States',95,'Current LSP with a public freelance-contractor application and repeated recent purchase history.','https://www.cetra.com/careers/freelance-contractors/'),
 ('CPSL','cpsl.com','Spain',96,'Current LSP explicitly recruits external partners and accepts agencies; the supplied data shows recent purchasing.','https://www.cpsl.com/external-partners/'),
 ('EC Innovations','ecinnovations.com','Singapore',98,'Current localization company with an explicit company-provider registration route and recent supplied purchase history.','https://partner.ecinnovations.com/register/'),
 ('Global Lingo','global-lingo.com','United Kingdom',100,'Current LSP states it is always seeking linguists; official pages cover Danish, Finnish, Icelandic, Norwegian and Swedish.','https://global-lingo.com/linguist-registration/'),
 ('Global Textware','globaltextware.nl','Netherlands',94,'Current LSP has a public freelance-translator registration route and recent supplied purchase history.','https://www.globaltextware.nl/about-us/vacancies/register-as-freelance-translator/'),
 ('IOLAR','iolar.com','Slovenia',90,'Current language-technology and localization company publicly references freelancers and has recent supplied purchase history.','https://www.iolar.com/'),
 ('LanguageLine Solutions','languageline.com','United States',94,'Current language-services group has a public freelance-translator route and recent supplied purchase history.','https://www.languageline.com/en-gb/careers/freelance-translator-jobs'),
 ('LanguageWire','languagewire.com','Denmark',100,'Current LSP actively recruits freelancers; official content identifies Nordic-language demand and predecessor records show recent purchasing.','https://www.languagewire.com/en-gb/become-a-freelancer/'),
 ('Lionbridge','lionbridge.com','United States',98,'Current global localization buyer maintains a translation community; current career evidence includes English-to-Danish work.','https://careers.lionbridge.com/translation'),
 ('Parenty Reitmeier','parentyreitmeier.com','Canada',86,'Current translation and localization company has a public careers route and demonstrated purchase history.','https://www.parentyreitmeier.com/pages/careers.html'),
 ('Questel','questel.com','France',94,'Current localization group presents vendor opportunities; recent purchase history exists under Morningside.','https://www.questel.com/about-questel/careers/'),
 ('RWS','rws.com','United Kingdom',99,'Current global LSP explicitly works with freelance agencies; current and SDL/Moravia entities show recent purchasing.','https://www.rws.com/about/careers/freelance/intellectual-property/'),
 ('Seprotec','seprotec.com','Spain',96,'Current LSP explicitly invites external translators and the supplied data shows recent purchasing.','https://seprotec.com/en/get-in-touch/work-with-us'),
 ('Side','side.inc','United Kingdom',85,'Current games-services company with a supplied 2025 purchase under Side; global game localization creates Nordic-language demand.','https://side.inc/news/ptw-rebrands-as-side'),
 ('talk finance','talkfinance.biz','Luxembourg',84,'Current specialist financial-translation company with recent demonstrated purchase history.','https://www.talkfinance.biz/'),
 ('thebigword','thebigword.com','United Kingdom',97,'Current global language-services buyer publishes linguist opportunities and has recent supplied purchase history.','https://thebigword.com/linguist-opportunities/'),
 ('TransPerfect','transperfect.com','United States',100,'Current global LSP runs an external talent community; a current project explicitly includes Norwegian, Swedish, Danish and Finnish.','https://community.transperfect.com/'),
 ('Translate.One','translate.one','United States',88,'Current consolidated LSP; supplied Translate.One, Intertext and Trustpoint.One records demonstrate purchasing under the group.','https://www.translate.one/translate-one-announces-rebranding-of-commit-global-inwhatlanguage-and-balthasar-ltd/'),
 ('Vistatec','vistatec.com','Ireland',99,'Current global localization company has an explicit agency application route and recent supplied purchase history.','https://www.vistatec.com/agency-application-form/'),
 ('Welocalize','welocalize.com','United States',94,'Current global localization brand maintains an active talent route; multiple entities show recent supplied purchasing.','https://careers.welocalize.com/welocalize-wednesdays/'),
 ('ZELENKA','zelenka-translations.com','Czech Republic',99,'Current LSP publishes a vendor portal and vendor-management contact; recent supplied purchase history is present.','https://www.zelenka-translations.com/translator-jobs'),
 ('t''works','t-works.eu','Germany',92,'Current language-services group has an explicit freelancer route; group and predecessor records demonstrate demand.','https://www.t-works.eu/join-as-a-freelancer')
)
INSERT INTO public.sales_prospects(name,domain,country,sector,fit_note,source_url,researched_at,notes,stage)
SELECT name,domain,country,'Language services',fit_note,source_url,now(),
 'Curated from the supplied prospect learning set on 2026-10-22. Confidence '||score||'/100. Human review required; no outreach was sent.',
 'qualified'
FROM seed s
WHERE NOT EXISTS(
 SELECT 1 FROM public.sales_prospects p
 WHERE regexp_replace(lower(p.name),'[^a-z0-9]','','g')=regexp_replace(lower(s.name),'[^a-z0-9]','','g')
)
ON CONFLICT(domain) DO UPDATE SET
 name=CASE WHEN sales_prospects.stage='research' THEN excluded.name ELSE sales_prospects.name END,
 country=CASE WHEN sales_prospects.stage='research' AND sales_prospects.country='' THEN excluded.country ELSE sales_prospects.country END,
 sector=CASE WHEN sales_prospects.stage='research' AND sales_prospects.sector='' THEN excluded.sector ELSE sales_prospects.sector END,
 fit_note=CASE WHEN sales_prospects.stage='research' AND sales_prospects.fit_note='' THEN excluded.fit_note ELSE sales_prospects.fit_note END,
 source_url=CASE WHEN sales_prospects.stage='research' AND sales_prospects.source_url='' THEN excluded.source_url ELSE sales_prospects.source_url END,
 researched_at=coalesce(sales_prospects.researched_at,excluded.researched_at),
 stage=CASE WHEN sales_prospects.stage='research' THEN 'qualified' ELSE sales_prospects.stage END,
 updated_at=CASE WHEN sales_prospects.stage='research' THEN now() ELSE sales_prospects.updated_at END;

WITH contacts(domain,name,role_title,email,source_url) AS (VALUES
 ('ecinnovations.com','Resource Management','Supplier onboarding','resourcemanagement@ecinnovations.com','https://partner.ecinnovations.com/register/'),
 ('seprotec.com','Vendor applications','External translator applications','cv@seprotec.com','https://seprotec.com/en/get-in-touch/work-with-us'),
 ('transperfect.com','DataForce Sourcing','Community sourcing','dataforce.sourcing@transperfect.com','https://dataforcecommunity.transperfect.com/project/mirabelle-project'),
 ('zelenka-translations.com','Vendor Management','Vendor applications','vendors@zelenka.cz','https://www.zelenka-translations.com/translator-jobs')
)
INSERT INTO public.sales_contacts(prospect_id,name,role_title,email,source_url,outreach_basis)
SELECT p.id,c.name,c.role_title,c.email,c.source_url,
 'Public role-based application address. Verify the current official source and outreach basis before use.'
FROM contacts c JOIN public.sales_prospects p ON p.domain=c.domain
ON CONFLICT(email) DO NOTHING;

INSERT INTO public.sales_events(event,detail)
SELECT 'prospect_learning_set_installed',
 jsonb_build_object('profile_version',1,'qualified_seed_count',26,'public_role_contacts',4,'automatic_research',false)
WHERE NOT EXISTS(SELECT 1 FROM public.sales_events WHERE event='prospect_learning_set_installed');

CREATE OR REPLACE FUNCTION public.sales_system_067(p_action text,p_data jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 j sales_ai_jobs%ROWTYPE; item jsonb; contact jsonb; v_prospect_id uuid; v_cost numeric;
 imported integer:=0; duplicates integer:=0; suppressions integer:=0; conflicts integer:=0;
 returned integer:=0; accepted integer:=0; validation_rejected integer:=0; v_result jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Server access required' USING ERRCODE='42501'; END IF;
 IF p_action='research_context' THEN
  RETURN jsonb_build_object(
   'research_profile',(SELECT research_profile FROM sales_settings WHERE id),
   'existing_prospects',coalesce((SELECT jsonb_agg(jsonb_build_object('name',name,'domain',domain)) FROM (
    SELECT name,domain FROM sales_prospects ORDER BY updated_at DESC,id LIMIT 200
   ) existing),'[]'::jsonb),
   'suppressed_domains',coalesce((SELECT jsonb_agg(target) FROM (
    SELECT target FROM sales_suppressions WHERE target NOT LIKE '%@%' ORDER BY target LIMIT 200
   ) suppressed),'[]'::jsonb)
  );
 ELSIF p_action<>'finish_ai' THEN
  RETURN public.sales_system_063(p_action,p_data);
 END IF;

 SELECT * INTO j FROM sales_ai_jobs WHERE id=(p_data->>'id')::uuid FOR UPDATE;
 IF j.id IS NULL OR j.state NOT IN('running','queued') THEN RAISE EXCEPTION 'AI task already finalized'; END IF;
 IF p_data->>'state' NOT IN('completed','failed','uncertain') THEN RAISE EXCEPTION 'Invalid AI completion state'; END IF;
 IF p_data->>'state'<>'completed' OR j.kind<>'research' THEN
  RETURN public.sales_system_063(p_action,p_data);
 END IF;

 accepted:=jsonb_array_length(coalesce(p_data->'result'->'prospects','[]'::jsonb));
 returned:=coalesce((p_data->'result'->'diagnostics'->>'returned')::integer,accepted);
 validation_rejected:=coalesce((p_data->'result'->'diagnostics'->>'validation_rejected')::integer,greatest(returned-accepted,0));
 FOR item IN SELECT value FROM jsonb_array_elements(coalesce(p_data->'result'->'prospects','[]'::jsonb)) LOOP
  IF EXISTS(SELECT 1 FROM sales_prospects WHERE domain=lower(item->>'domain') OR regexp_replace(lower(name),'[^a-z0-9]','','g')=regexp_replace(lower(item->>'name'),'[^a-z0-9]','','g')) THEN
   duplicates:=duplicates+1; CONTINUE;
  END IF;
  IF EXISTS(SELECT 1 FROM sales_suppressions WHERE target=lower(item->>'domain')) THEN
   suppressions:=suppressions+1; CONTINUE;
  END IF;
  v_prospect_id:=NULL;
  INSERT INTO sales_prospects(name,domain,country,sector,fit_note,source_url,researched_at)
  VALUES(item->>'name',lower(item->>'domain'),coalesce(item->>'country',''),coalesce(item->>'sector',''),coalesce(item->>'fit_note',''),coalesce(item->>'source_url',''),now())
  ON CONFLICT(domain) DO NOTHING RETURNING id INTO v_prospect_id;
  IF v_prospect_id IS NULL THEN conflicts:=conflicts+1; CONTINUE; END IF;
  imported:=imported+1;
  FOR contact IN SELECT value FROM jsonb_array_elements(coalesce(item->'contacts','[]'::jsonb)) LOOP
   INSERT INTO sales_contacts(prospect_id,name,role_title,email,linkedin_url,source_url)
   VALUES(v_prospect_id,coalesce(contact->>'name',''),coalesce(contact->>'role_title',''),nullif(lower(contact->>'email'),''),coalesce(contact->>'linkedin_url',''),coalesce(contact->>'source_url',''))
   ON CONFLICT(email) DO NOTHING;
  END LOOP;
 END LOOP;

 v_cost=(p_data->>'cost_eur')::numeric;
 IF v_cost IS NOT NULL AND v_cost<0 THEN RAISE EXCEPTION 'Invalid usage cost'; END IF;
 v_result=coalesce(p_data->'result','{}'::jsonb)||jsonb_build_object(
  'imported',imported,
  'outcomes',jsonb_build_object(
   'returned',returned,'accepted',accepted,'validation_rejected',validation_rejected,
   'duplicates',duplicates,'suppressions',suppressions,'conflicts',conflicts,'imported',imported
  )
 );
 UPDATE sales_ai_jobs SET state='completed',cost_eur=v_cost,result=v_result,error=NULL,
  provider_id=p_data->>'provider_id',finished_at=now() WHERE id=j.id;
 INSERT INTO sales_events(event,detail) VALUES('research_completed',
  jsonb_build_object('job_id',j.id,'returned',returned,'accepted',accepted,'validation_rejected',validation_rejected,
   'duplicates',duplicates,'suppressions',suppressions,'conflicts',conflicts,'imported',imported));
 IF v_cost>j.reserved_eur THEN
  UPDATE sales_settings SET research_enabled=false,budget_hold=true WHERE id;
  INSERT INTO sales_events(event,detail) VALUES('budget_estimate_exceeded',jsonb_build_object('job_id',j.id));
 END IF;
 RETURN jsonb_build_object('ok',true);
END $$;

REVOKE ALL ON FUNCTION public.sales_system_067(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sales_system_067(text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
