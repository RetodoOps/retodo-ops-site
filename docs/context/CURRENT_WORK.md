# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current task: Update 067 — curated Sales prospects and buyer-profile research
Status: READY FOR USER INSTALLATION — verified complete-file package; no production actions performed
Starting remote HEAD: `ebb6f20d061fc284399973997627d8a2bdec6b3a` (main, Update 066)
Local branch: `dev/update-064-sales-signature` on reconstructed history; never push this history
Build: 067 locally; main 066
Last updated: 2026-10-22

## LOCKED WORKFLOW

- Deliver complete changed files in a repository-root ZIP. The user uploads/commits to main.
- Do not push, merge, deploy, run production SQL, change production configuration/data or send prospect outreach.
- Preserve Update 066 invoice work and all earlier Sales signature, Gmail, Reports and public-enquiry behavior.
- Database migrations are forward-only. Preserve RLS, least privilege, approvals, suppressions and immutable history.

## USER REQUEST

Use the two supplied prospect lists as learning material: clarify the buyer profile, reconcile duplicate/acquired names, remove organizations that no longer fit or operate under that name, add only high-confidence prospects to the Sales pipeline, and improve future AI research.

The earlier live AI task completed for €0.02 but returned zero prospect cards and generic sources, including Retodo itself. Provider access, worker execution and cost accounting passed; research selection, URL validation and result reporting did not.

## SOURCE ANALYSIS

- Historic Plunet export: 7,674 records; 546 websites, 459 email fields and 530 order dates.
- Named account report: 255 entities. 228 normalized-exact matches and 234 high-similarity matches to the historic export.
- Reconciliation result: 26 current canonical pipeline candidates; 67 rows merge into them; 8 additional merge/re-verify examples; 12 explicit exclusions; 163 held for current evidence.
- Current canonical mappings include SDL/Moravia → RWS, Jonckers → Acclaro, Venga → Argos, Morningside → Questel, Delingua/WHP → LanguageWire, PTW → Side and current consolidated groups for Acolad, TransPerfect, Translate.One and t'works.
- e2f is excluded: its current business became TrustScale and no longer matches the target buyer profile.
- Historical personal emails are not sent to web research or seeded. Four current public role-based application contacts are retained as unverified.

## IMPLEMENTED — UPDATE 067

- Forward-only migration `063_sales_prospect_learning.sql` adds a bounded JSON buyer profile, forces automatic research off, seeds 26 current canonical companies at `qualified`, adds four unverified public role contacts, and creates no conversations/messages/outreach.
- New service-only `sales_system_067` supplies the curated profile, known company/domain exclusions and suppressed domains. It records returned, validation-rejected, duplicate, suppression, conflict and imported counts.
- AI prompt now requires a current multi-language LSP/localization buyer, current official evidence, outside-capacity demand and canonical identity. It rejects Retodo, direct clients, individuals, directories, weak competitors and legacy aliases.
- URL validation safely removes tracking parameters while retaining scheme/host/path/non-tracking-query identity.
- Sales Today and result dialog show truthful outcome counts; the unconditional “Existing companies were skipped” claim is removed.
- Existing `sales_system_063`, approval workflow, budget controls, Gmail protections and signature renderers remain intact.
- Automatic research remains off. No paid AI call or outreach was made during development.

## VERIFIED

- 54 database workflow checks PASS, including migration reapplication, 26 canonical seeds, four unverified role contacts, service-only context, truthful outcome counts, prior sending/reply/signature behavior and a real-worker/fixture-Gmail pass.
- Read-only audits PASS: Sales 31, worker 11, signature 12, brand assets 9, Update 067 research 15.
- 43 service, worker, diagnostic, signature and brand tests PASS, including tracking-URL canonicalization, strict path evidence, curated context, exclusions and dispatcher selection.
- Full browser fixture PASS: truthful research counts/result dialog plus prior navigation, review, signatures, conversations, materials, XSS, mobile and role boundaries.
- Analysis workbook rendered and visually inspected on all five tabs; no formula errors. It contains Summary, Pipeline Candidates, Training Examples, Source Reconciliation and Method.

## DELIVERY

- `RetodoOps_Update_067_Prospect_Learning.zip` — 16 complete repository files listed in `UPDATE_067_MANUAL_UPLOAD.md`.
- `Retodo_Ops_Prospect_Learning_Set_2026-10-22.xlsx` — reusable analysis and training workbook, stored separately from the application repository.
- Installation: run migration 063, then audit 021 (15 PASS), deploy, hard-refresh, confirm build 067 and automatic research off. Review public contacts before verification.

## RETAINED UPDATE 066 INVOICE WORK

Main `ebb6f20d` contains Update 066 reference invoice layout and Bulgarian issuer details. Do not overwrite its migration 062, audits, PDF/Word layout, Bulgarian issuer settings or invoice revision safeguards. Existing issued snapshots remain frozen; old invoices gain Bulgarian issuer text only through explicit administrator revision with a reason. Production/desktop Word acceptance remains separate from this Sales update.

## RETAINED LIVE SALES ACCEPTANCE

- Mailbox, Eli alias, sending, reply detection and follow-up cancellation passed in the live pilot.
- Corrected 064A signature was sent, received and accepted by the user.
- AI provider access and cost accounting passed in the €0.02 task; discovery/import quality was not accepted and is the reason for Update 067.

## NEXT EXACT ACTION

The user uploads the Update 067 ZIP to current main, runs migration 063 and audit 021, deploys, and confirms the 26 qualified canonical prospects with automatic research still off. Then run one narrow on-demand research acceptance test and inspect the separated outcome counts before enabling any recurring research.

## DO NOT REDO

Do not recreate the signature, restart OAuth, repeat delivery/reply tests, re-enable automatic research, seed legacy aliases, import historic personal emails, or rerun paid research before Update 067 is installed. Do not change or remove Update 066 invoice files.
