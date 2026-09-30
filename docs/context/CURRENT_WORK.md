# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: dev/update-061-invoicing-zip (local only)
Starting HEAD: 0c704f05e762f588cafcb3cd7e53ac44534cba95
Latest delivery checkpoint: Update 061 complete-file ZIP; production still main 0c704f0/build 060
Build: 061 prepared and tested locally; 060 last verified on main
Last updated: 2026-09-27

## CURRENT TASK
Deliver Update 061: Reports corrections and selected-Scoop client invoicing.

## STATUS
UPDATE 061 READY FOR USER INSTALLATION — functional code and complete-file ZIP. No production changes made.

## TASK-SPECIFIC LOCKED RULES
- USER OVERRIDE: ZIP updates with complete changed files only. The user uploads and commits directly to main. Do not push, merge, create PRs or deploy for this task.
- Include CURRENT_WORK.md in every update ZIP, recording actual code changes, tests, deployment state and outstanding work. Carry these ZIP workflow rules forward unless the user changes them.
- A documentation/review merge does not update the application. Main adb01a2 contained the Reports review/proposal but still ran build 058; this package contains actual code.
- Preserve RLS/least privilege, traceable dated EUR conversion, one client value per Scoop and no invented Job revenue allocation. Unknown costs are not zero; no exchange rates or accounting recognition are invented.
- Migrations are forward-only. The user runs production SQL. Local commits are allowed; do not publish them.

## COMPLETED
- Rebuilt Reports UI and advanced filters; linked client/account/PM/resource IDs; multiple statuses; date basis/presets, languages/service/currency, cost/data-quality and margin bounds.
- Repaired search for project numbers with display names, languages, resources and PO references.
- Added numeric financial sorting, full-dataset grouping, per-currency summaries, separate blocker/estimate counts and URL persistence.
- Added source links, reset/retry/error states and dirty-filter protection against stale export.
- Fixed CSV negative numeric values, added per-currency numeric columns, Margin languages and grouped summaries; retained complete-snapshot export limit of 10,000.
- Added standalone migration 053 (052 optional), versioned filter-options RPC, schema preflight, grants/RLS preservation and read-only audit 014.
- Updated build marker and asset cache versions to 059. No production changes made.

## UPDATE 060 CHANGES AND CONFIRMATION
- 2026-09-26: user confirmed Update 059 was committed; Reports seem functional at first glance. Supplied screenshot shows the Jobs export containing 17 rows, opened as comma-separated text in Excel column A.
- Read-only fetch verified main fef44a3 (Add files via upload). Affected files match the delivered 059 files. No independent production SQL/audit acceptance is claimed.
- CSV now begins with UTF-8 BOM plus Excel's `sep=,` directive. This addresses delimiter detection on direct open without changing Windows regional settings.
- Existing report data, quoting, formula-text protection, signed numbers, summaries, filters and database API 059 are retained. No SQL changes.
- Updated frontend build marker and JavaScript cache version to 060.

## UPDATE 060 ACCEPTANCE / INVOICING START
- 2026-09-26 user: “Done; Confirmed”; various search filters also appear functional. Treat this as user-reported 060 installation/CSV acceptance, not an independent financial audit.
- Read-only fetch verifies main 0c704f0 contains build 060 and the Excel separator fix.
- Invoicing menu exists, but invoice.html / invoice.js are absent. Existing client/supplier invoice and payment tables will be reused.
- Recovered earlier decisions through targeted Personal Context retrieval: official client invoices generated in TMS; editable numbering/next follows last; Project approval gates billing; values sourced once from Scoops; supplier cycle is 15th/last working day with 60 calendar days from cycle date. Legacy 15th/30th defaults are superseded.
- Prior multi-Project grouping was only an assistant proposal. Ask the user whether compatible approved Projects may share an invoice or each Project requires its own.
- Inspected financial schema/guards and wrote concrete implementation scope; no application/database changes yet.

## APPROVED UPDATE 061 REQUIREMENTS (2026-09-27)
- User explicitly authorizes a client invoice containing selected approved Scoops across multiple Projects. Approval gate is each active Scoop; a cancelled Project is excluded. This supersedes the earlier pending grouping question and Project-only gate.
- Queue approved Scoops, select which to invoice, search by the client PO inherited from the Project, and add further Scoops to a saved draft.
- Drafts allow manual rows, row removal and amount corrections. Client profile default_payment_days determines due date. Issued facts remain frozen.
- Reports Projects view must have one row per Scoop. EUR is the default reporting currency; convert supported foreign currencies using dated ECB reference rates. Missing costs/rates remain explicit, never silently zero or 1:1.
- Screenshot has an unassigned TEST Job with no stored rate/PO. Dashboard treats that as zero; Reports must identify it and show provisional profit from known costs separately.
- Default typed Excel workbook export fixes Excel date/encoding interpretation; raw CSV remains optional. Page sizes 25/50/100/250, default 50.

## COMPLETED UPDATE 061 CHANGES
- tms/migrations/054_reports_eur_scoop_detail.sql: versioned EUR/Scoop report RPC, protected dated ECB rates, source-currency filtering, exact Job cost diagnostics, provisional profit, numeric sorting and full totals. Legacy report API retained.
- netlify/functions/report-exchange-rates.js: authenticated company refresh from fixed ECB endpoint; server-only storage, validation and short cache. Uses existing server Supabase configuration.
- tms/reports.html / reports.js / reports.css: one Scoop per Projects row, languages, cost detail expansion, EUR basis, original-currency filter, 25/50/100/250 paging with URL persistence and XLSX/raw-CSV format choice.
- tms/report-workbook.js and tms/vendor/exceljs-4.4.0.min.js / EXCELJS_LICENSE.txt: local ExcelJS runtime, typed numeric/Unicode XLSX, readable headers, widths, frozen rows, filters, summaries, groups, source amounts and FX metadata.
- tms/migrations/055_client_scoop_invoicing.sql: existing finance tables extended with Scoop source identity, unique reservations, revision protection, draft save/edit/cancel, source and billing snapshots, issuer/number settings, issue/payment authorization, immutable issued facts, event history and whole-Project financial-state updates. Direct ordinary-user client finance writes replaced with guarded RPCs; no source business records are backfilled.
- tms/invoice.html / invoice.js / invoice.css: approved-Scoop queue, client/PO search and selection across Projects; draft row edits/manual rows/deletion/additional Scoops; client payment days; billing/tax/number fields; settings, issue, saved print/PDF, received payments and invoice history. Supplier menu explicitly describes follow-up scope.
- tms/audits/015_update_061_reports_invoices_audit.sql: read-only installation/permissions audit.
- tms/build.json: local build 061.
- tests/reports-browser.cjs and reports-ui.test.js: adapted for current report API/export and warnings; page-size persistence coverage.
- tests/update-061-reports-db.mjs, update-061-invoices-db.mjs, update-061-export-fx.test.cjs and update-061-invoices-browser.cjs: actual SQL finance checks and browser/export/FX fixtures.
- docs/reports/INVOICING_061_IMPLEMENTATION_SCOPE.md: approved implemented scope replaces pending grouping proposal.
- docs/reports/UPDATE_061_INSTALL_AND_TEST.md: ordered SQL/audit/full-file installation, configuration, acceptance and limitations.
- docs/context/CURRENT_WORK.md: complete task state and ZIP workflow.

## VERIFIED LOCAL RESULTS
- PASS: 9 Reports PostgreSQL checks: Scoop rows, known/unknown/explicit-zero costs, final/provisional margins, source-currency filter, EUR conversion, missing-rate behavior, language grouping, full totals, sorting/paging and FX write denial.
- PASS: 16 client invoice database checks on repository schema: multi-Project selection/PO search, due dates/client terms, reservations/rollback, wrong-client rejection, corrections/manual/removal/later additions, revisions, source changes, role restrictions, numbering, snapshots, immutable issued facts, cancellation, payment guards and Project financial status.
- PASS: 055 reapplication and 58 read-only installation-audit checks.
- PASS: 9 JavaScript/export/FX tests, including numeric XLSX cells, Unicode, inert formula-like text, unknown margin, CSV escaping, ECB parsing and authenticated endpoint behavior.
- PASS: Chromium Reports and Invoice workflows, including page-size persistence, export/cap, selection across Projects, save/reopen, edit/remove/manual rows, add by PO, issue, print contents, payments, QA permissions and mobile overflow. Screenshots inspected.
- PASS: JavaScript syntax and diff whitespace checks.
- LIMITS: browser RPCs use fixtures; database tests execute actual SQL separately. Microsoft Excel desktop and production are not tested. The generated XLSX is reopened with ExcelJS and checked for numeric cell types and text preservation.
- Historical migrations 037/040 are absent. Compatibility tests replay available schema through 038, explicitly stub the unrelated missing 037 audit writer, then apply 053/054/055. This is not a complete historical replay.

## PRODUCTION STATE
Read-only fetch on 2026-09-27 confirms main 0c704f05e762f588cafcb3cd7e53ac44534cba95, build 060, unchanged. No assistant push, merge, PR, deployment, production SQL, invoice issuance or payment recording. Update 061 is delivered for the user's installation and commit.

## NEXT EXACT ACTION
User applies 054 then 055, runs audit 015, uploads complete ZIP contents preserving repository paths, and commits. Await installation/acceptance results; address any failures before starting another module. Do not request grouping approval again.

## OPEN / FOLLOW-UP
- Before official issue the user supplies issuer/legal/bank details, next number, active billing entity, client payment days and tax treatment. These are not guessed.
- The unassigned TEST Job in the Reports screenshot has no saved rate/PO. Reports now names it and shows provisional profit. Dashboard's missing-as-zero calculation is unchanged. Legitimate zero cost must be explicitly saved; do not invent a cost.
- EUR conversion uses a dated ECB snapshot up to seven days old, not historical transaction-day or bank settlement FX. Unsupported/missing rates remain unavailable; server refresh must be configured/deployed. No 1:1 fallback.
- Official invoice edits/credits/annulment/replacement, supplier invoicing, automated email/reminders, bank FX differences and separate Invoice Reports are future work. Draft editing, official client issue and received-payment tracking are implemented.
- Invoice list is latest 250 for selected client. A partly billed Project is not falsely marked fully Invoiced; whole-Project financial status updates only once every active Scoop is covered.
- Legacy Project-only invoice allocations block new Scoop billing conservatively until reviewed.

## REQUIRED CONTEXT
Only docs/reports/UPDATE_061_INSTALL_AND_TEST.md and docs/reports/INVOICING_061_IMPLEMENTATION_SCOPE.md if installation/scope details are needed.

## DO NOT REDO
- Do not reopen the grouping question or resume branch-push approvals. User upload/commit ZIP workflow controls.
- Do not reopen signing, invitations, Compliance or broad context reconciliation.
- Do not run production SQL or reconstruct missing legacy migrations.
