-- Update 068: all Sales prospects are cold; confidential history is ranking-only.
-- Requires Update 067. Forward-only and safe to reapply.
BEGIN;

DO $$ BEGIN
 IF to_regprocedure('public.sales_system_067(text,jsonb)') IS NULL
  OR NOT EXISTS(
   SELECT 1 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='sales_settings' AND column_name='research_profile'
  ) THEN
  RAISE EXCEPTION 'Install Update 067 before Update 068';
 END IF;
END $$;

UPDATE public.sales_settings SET
 research_enabled=false,
 research_profile=$profile$
{
  "version": 2,
  "generated_on": "2026-10-23",
  "cold_outreach_only": true,
  "confidential_history_rule": "Supplied historical records describe activity with another business. They may be used only as confidential internal ranking and canonicalization input. Never expose, cite, paraphrase or imply them in Sales notes, research results, materials or outreach. Every prospect must be treated as a first-time cold approach to Retodo Ops.",
  "ideal_buyer": "A current multi-language LSP or localization company with current public evidence that it sources outside language capacity and currently needs Nordic target languages.",
  "source_languages": ["English", "German", "French"],
  "target_languages": ["Norwegian Bokmal", "Norwegian Nynorsk", "Swedish", "Danish", "Finnish", "Icelandic"],
  "required_signals": [
    "Current operating company and canonical domain",
    "Current official supplier, vendor, agency, freelancer or linguist sourcing route",
    "Current official Nordic-language demand, recruitment or delivery need"
  ],
  "insufficient_signals": [
    "General European-language coverage without explicit Nordic evidence",
    "ISO certification, company age, size or broad service capability",
    "Nordic service coverage without evidence that the company buys outside capacity",
    "Confidential historical activity without current public qualification evidence"
  ],
  "exclude": [
    "Retodo Ops and retodo-ops.com",
    "Direct end clients in this agency-buyer search",
    "Individuals",
    "Directories and marketplaces",
    "Inactive, acquired or rebranded aliases as separate prospects",
    "Pure Nordic competitors or suppliers without evidence that they buy outside capacity"
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
  "negative_examples": [
    {"name": "Retodo Ops", "reason": "Seller self-match"},
    {"name": "e2f", "reason": "Changed scope; current business is TrustScale AI verification"},
    {"name": "The Walt Disney Company Nordic", "reason": "Direct end client outside this agency-buyer search"},
    {"name": "Translators.com", "reason": "Directory or marketplace, not a confirmed buyer"},
    {"name": "Business Team Translations for Nordic research", "reason": "Current external translator network is public, but the cited careers evidence does not establish current Nordic demand"}
  ],
  "confidence_threshold": 90,
  "automatic_research_enabled": false
}
$profile$::jsonb,
 updated_at=now()
WHERE id;

-- Replace confidential ranking language in the Update 067 seed with public-only
-- fit statements. Workflow stages and all contacts/conversations remain intact.
WITH safe(domain,fit_note) AS (VALUES
 ('acclaro.com','Current localization company with a public careers route and official Finnish-language service coverage; verify the appropriate supplier route before outreach.'),
 ('acolad.com','Global multilingual LSP with an active freelance community and broad language coverage compatible with Nordic delivery.'),
 ('argosmultilingual.com','Global localization provider with linguist-facing careers content and multilingual delivery across international markets.'),
 ('aspena.com','Current language-services company with an explicit official supplier application route and multilingual delivery.'),
 ('cetra.com','Current LSP with an official freelance-contractor application route and specialist multilingual services.'),
 ('cpsl.com','Current LSP with an official external-partner route that accepts agencies and other language specialists.'),
 ('ecinnovations.com','Current localization company with an explicit official company-provider registration route.'),
 ('global-lingo.com','Current LSP that invites linguist registration and publishes Danish, Finnish, Icelandic, Norwegian and Swedish services.'),
 ('globaltextware.nl','Current LSP with an official freelance-translator registration route.'),
 ('iolar.com','Current language-technology and localization company that publicly references collaboration with freelancers.'),
 ('languageline.com','Current language-services group with an official freelance-translator route and global multilingual delivery.'),
 ('languagewire.com','Current LSP that recruits freelancers and publishes Nordic-language capabilities.'),
 ('lionbridge.com','Current global localization buyer with a translation community and public English-to-Danish opportunity evidence.'),
 ('parentyreitmeier.com','Current translation and localization company with a public language-professional careers route; confirm current Nordic requirements before outreach.'),
 ('questel.com','Current global localization and intellectual-property language-services group; confirm the current supplier route before outreach.'),
 ('rws.com','Current global LSP that publicly works with freelance agencies and language specialists.'),
 ('seprotec.com','Current LSP with an official route for external translator applications.'),
 ('side.inc','Current global games-services and localization company; confirm a current external Nordic capacity requirement before outreach.'),
 ('talkfinance.biz','Current specialist financial-translation company; confirm a current external Nordic capacity requirement before outreach.'),
 ('thebigword.com','Current global language-services buyer with public linguist opportunities.'),
 ('transperfect.com','Current global LSP with an external talent community and public Norwegian, Swedish, Danish and Finnish project evidence.'),
 ('translate.one','Current multilingual LSP group; confirm the current external supplier route and Nordic requirement before outreach.'),
 ('vistatec.com','Current global localization company with an explicit official agency application route.'),
 ('welocalize.com','Current global localization brand with an active external talent route.'),
 ('zelenka-translations.com','Current LSP with a public vendor portal and vendor-management application contact.'),
 ('t-works.eu','Current language-services group with an explicit official freelancer route.')
)
UPDATE public.sales_prospects p SET
 fit_note=s.fit_note,
 updated_at=now()
FROM safe s
WHERE p.domain=s.domain
 AND p.fit_note ~* '(supplied|histor|purchas|predecessor|records demonstrate|entities show)';

UPDATE public.sales_prospects SET
 notes='Cold prospect qualified from current public buyer evidence. Treat as a first-time approach to Retodo Ops. Human review is required; no outreach was sent.',
 updated_at=now()
WHERE domain IN(
 'acclaro.com','acolad.com','argosmultilingual.com','aspena.com','cetra.com','cpsl.com',
 'ecinnovations.com','global-lingo.com','globaltextware.nl','iolar.com','languageline.com',
 'languagewire.com','lionbridge.com','parentyreitmeier.com','questel.com','rws.com',
 'seprotec.com','side.inc','talkfinance.biz','thebigword.com','transperfect.com','translate.one',
 'vistatec.com','welocalize.com','zelenka-translations.com','t-works.eu'
)
AND notes LIKE 'Curated from the supplied prospect learning set on 2026-10-22.%';

-- Remove only the specific confidential relationship note that may have been
-- added during the first acceptance review. Other Jensen notes are preserved.
UPDATE public.sales_prospects SET
 notes='Cold prospect. Treat as a first-time approach to Retodo Ops; do not mention or imply any prior relationship.',
 updated_at=now()
WHERE domain='jensen-localization.com'
 AND notes ~* '(former retodo|former client|jensen localization bv|jensen localization sl|supplied plunet|latest supplied|prior relationship)';

INSERT INTO public.sales_events(event,detail)
SELECT 'cold_prospect_guard_installed',
 jsonb_build_object('profile_version',2,'cold_outreach_only',true,'automatic_research',false)
WHERE NOT EXISTS(SELECT 1 FROM public.sales_events WHERE event='cold_prospect_guard_installed');

NOTIFY pgrst,'reload schema';
COMMIT;
