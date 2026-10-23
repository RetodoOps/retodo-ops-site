-- Update 068 read-only audit. Expected: all rows PASS.
WITH seeded(domain) AS (VALUES
 ('acclaro.com'),('acolad.com'),('argosmultilingual.com'),('aspena.com'),('cetra.com'),('cpsl.com'),
 ('ecinnovations.com'),('global-lingo.com'),('globaltextware.nl'),('iolar.com'),('languageline.com'),
 ('languagewire.com'),('lionbridge.com'),('parentyreitmeier.com'),('questel.com'),('rws.com'),
 ('seprotec.com'),('side.inc'),('talkfinance.biz'),('thebigword.com'),('transperfect.com'),('translate.one'),
 ('vistatec.com'),('welocalize.com'),('zelenka-translations.com'),('t-works.eu')
), checks(check_name,ok) AS (
 VALUES
 ('Cold-only profile active',EXISTS(
   SELECT 1 FROM sales_settings
   WHERE research_profile->>'version'='2'
    AND research_profile->>'cold_outreach_only'='true'
 )),
 ('Confidential history is labelled as another-business ranking input',EXISTS(
   SELECT 1 FROM sales_settings
   WHERE research_profile->>'confidential_history_rule' LIKE '%another business%'
    AND research_profile->>'confidential_history_rule' LIKE '%Never expose%'
 )),
 ('Current external-capacity evidence is required',EXISTS(
   SELECT 1 FROM sales_settings
   WHERE research_profile->'required_signals' ? 'Current official supplier, vendor, agency, freelancer or linguist sourcing route'
 )),
 ('Current Nordic evidence is required',EXISTS(
   SELECT 1 FROM sales_settings
   WHERE research_profile->'required_signals' ? 'Current official Nordic-language demand, recruitment or delivery need'
 )),
 ('Automatic research remains off',NOT EXISTS(SELECT 1 FROM sales_settings WHERE research_enabled)),
 ('Seeded fit text contains no confidential relationship evidence',NOT EXISTS(
   SELECT 1 FROM sales_prospects p JOIN seeded s USING(domain)
   WHERE p.fit_note ~* '(supplied|purchase history|historical order|predecessor records|prior relationship|former client|plunet)'
 )),
 ('Seeded notes contain no supplied-history wording',NOT EXISTS(
   SELECT 1 FROM sales_prospects p JOIN seeded s USING(domain)
   WHERE p.notes ~* '(supplied prospect|purchase history|historical order|former retodo|former client|plunet)'
 )),
 ('Jensen contains no disclosed former-company relationship',NOT EXISTS(
   SELECT 1 FROM sales_prospects
   WHERE domain='jensen-localization.com'
    AND (fit_note||' '||notes) ~* '(former retodo|former client|jensen localization bv|jensen localization sl|supplied plunet|latest supplied)'
 )),
 ('Cold-prospect guard event recorded',EXISTS(
   SELECT 1 FROM sales_events
   WHERE event='cold_prospect_guard_installed' AND detail->>'cold_outreach_only'='true'
 )),
 ('Update 067 service remains installed',to_regprocedure('public.sales_system_067(text,jsonb)') IS NOT NULL)
)
SELECT check_name,CASE WHEN coalesce(ok,false) THEN 'PASS' ELSE 'FAIL' END result
FROM checks ORDER BY check_name;
