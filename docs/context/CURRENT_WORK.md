# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main 4e7a7dc914b0d0c6034f39e3d7d78a1e22ac06a2 (build 061)
Active task branch: dev/update-062-reports-invoice-workflow (local only)
Delivery: Update 062 complete-file ZIP, prepared and tested; awaiting user installation
Build: 062 locally; 061 verified on main
Last updated: 2026-09-30

## WORKFLOW — USER DECISION
- Deliver ZIP updates containing complete changed files, preserving repository paths. The user uploads to main and commits directly.
- Do not push, merge, create PRs, deploy, run production SQL or change production configuration/data. Local task-branch commits are allowed.
- Include this CURRENT_WORK.md with actual changes, verification, installation state and remaining work in every package.
- Preserve RLS and least privilege. Migrations are forward-only. Do not reconstruct missing historical migrations or commit private material.

## CURRENT TASK / STATUS
Update 062 is implemented and locally verified. The user confirmed Update 061 Excel exports work. Read-only fetch on 2026-09-30 confirms main 4e7a7dc contains build 061 and is unchanged during this task. No production installation or acceptance of 062 is claimed.

User requirements: select Reports Scoops/Jobs and bulk-change status; restore Invoice navigation in Clients/Project; shared search including exact Scoop identifiers across company modules; Bank label in invoice output; prompt for invoice number at creation; automatic Invoiced/Paid Scoop display; editable official invoices.

The explicit request for official invoice editing supersedes Update 061's issued-edit lock. Implemented as admin-only, reasoned revisions with prior snapshots and financial safeguards. No further workflow/grouping approval is needed.

## UPDATE 062 CHANGES
- tms/migrations/056_reports_selection_invoice_revisions_search.sql: guarded atomic bulk status RPC (maximum 500 records); protected derived Scoop financial_status; synchronization on invoice issue/payment/revision and backfill for existing issued/paid invoices; revision archive with RLS; permanent invoice-number ownership registry; admin-only official revision RPC with mandatory reason, optimistic revision checks, allocation/source validation, preserved receipts and issuer metadata, fixed client/currency, and total-at-least-receipts guard; server-side shared search; financial status integration into Reports API 061. Existing direct finance-write restrictions remain.
- tms/reports.html / reports.js / reports.css: per-Scoop and per-Job selection, select page/clear, operational status toolbar and confirmation. Selection spans pages and clears on changed report criteria. QA is read-only. Invoiced/Paid are filterable derived states, not manual bulk choices.
- tms/quick-nav.js and company HTML entry points (Accounts, Client/Clients, Dashboard, Invoice, Job, Project, Quote/Quotes, Reports, Resource/Resources, Settings): shared search queries Scoops, Projects, Jobs, Clients, Resources and client Invoices; exact Scoop matches rank before related Jobs and link to the Scoop card. Removes latest-250 search indexing; returns up to 30 matches per query. Restores missing Invoice sidebar groups, including Clients and Project. External resource pages remain separate.
- tms/dashboard.js / dashboard.html and tms/reference-data.js: display Invoiced/Paid separately from stored operational approval; Dashboard financial tabs and local table search across the All tab; Project Scoop cards use derived financial labels.
- tms/invoice.html / invoice.js: immediate ten-digit invoice-number prompt, admin official revision editor/reason/history, locked issued currency/client, unsaved-edit protection before recording receipts, explicit Bank label in print/PDF. PM prepares drafts; QA remains read-only. Revision snapshots are retained in the database.
- tms/build.json and affected asset references: Update 062 cache/build markers.
- tms/audits/016_update_062_workflow_audit.sql: 22 read-only installation/permission checks.
- tests/update-062-workflow-db.mjs, update-062-reports-browser.cjs, update-062-invoices-browser.cjs, update-062-search-browser.cjs, update-062-ui.test.cjs: focused SQL and browser regressions.
- docs/reports/UPDATE_062_INSTALL_AND_TEST.md: installation, acceptance, implemented scope and limits.

## VERIFICATION
- PASS: 23 actual PostgreSQL-compatible invoice/workflow checks, including existing 061 invoice regressions, 056 backfill for pre-existing invoices and reapplication, exact Scoop search, bulk Scoop/Job updates and atomic rejection, issued/paid revisions, complete prior snapshots, retained receipts, total/payment and stale-revision guards, removal/addition of Scoops, duplicate billing, protected financial state, historical number retention and role restrictions.
- PASS: installation audit 016, all 22 checks.
- PASS: Chromium Reports selection/bulk payload, filters, paging, export, QA and mobile checks.
- PASS: Chromium invoice-number prompt, official revision and reason, Bank label, payments, read-only permissions and mobile checks.
- PASS: Chromium shared search and restored Invoice navigation on Clients, Client details and Project details; screenshot inspected.
- PASS: focused Scoop display unit test; JavaScript syntax and diff whitespace checks.
- LIMITS: browser RPCs use fixtures; actual SQL is tested separately with PGlite. No production acceptance or desktop PDF/Excel acceptance of 062 is claimed. User already accepted 061 Excel export.
- Historical migrations 037/040 are absent. Tests replay available schema through 038, explicitly stub the unrelated missing 037 audit writer, then apply relevant 050/053/054/055/056 migrations. This is not a complete historical replay.

## RETAINED BUSINESS DECISIONS / 061 BASELINE
- One client invoice may include selected approved Scoops across several Projects. Users can add eligible Scoops by client PO; correct/delete rows and add manual rows. Client profile payment days determine due date.
- Reports Projects view has one row per Scoop; page sizes 25/50/100/250 (default 50); typed XLSX is default and raw CSV optional.
- EUR is the reporting default. Dated ECB conversion is traceable; unsupported/missing rates remain explicit, never 1:1. Unknown costs are not zero; provisional profit is separate from final margin. No invented Job revenue allocation.
- Supplier invoice cycle decision remains 15th/last working day, with 60 calendar days from cycle date; implementation remains follow-up scope.

## NEXT EXACT ACTION
User runs migration 056 on the installed 061 schema (054/055 and existing operational cancellation support from migration 050), runs audit 016 and checks all PASS, uploads the complete package files into matching repository paths, commits and refreshes. Follow the included Update 062 installation/acceptance guide. No new environment variables or Netlify functions are required.

After user installation, verify their actual Reports bulk-selection, exact Scoop search, invoice-number prompt, intended official revision and financial-status results. Fix any reported failures before beginning another module. Do not request permission to push: the ZIP workflow controls.

## OPEN / LIMITATIONS
- Supplier invoicing, credit notes/annulment/replacement, automated email/reminders, bank FX differences and separate Invoice Reports remain follow-up scope. Official client revisions are implemented in 062.
- Official revisions preserve old snapshots but no archived-document download UI is added. The current invoice prints corrected values and history shows reason/old/new total.
- Invoice list remains latest 250 for the selected client; shared search is server-side and is not restricted to that list.
- Operational approval and derived Scoop financial state remain separate. A partly billed Project is not falsely marked fully invoiced; legacy Project-only allocations conservatively block new Scoop billing until reviewed.
- Issuer/legal/bank details, billing entity, payment days and tax treatment come from configuration; do not invent them.
- Dashboard missing-cost calculations were not redesigned. Reports retains explicit unknown-cost diagnostics/provisional profit.
- EUR reporting uses a dated ECB snapshot up to seven days old, not historical transaction-day or bank settlement FX. Existing authenticated exchange-rate refresh configuration is still required.

## REQUIRED CONTEXT / DO NOT REDO
Use docs/reports/UPDATE_062_INSTALL_AND_TEST.md for current installation/scope details. Consult the 061 installation/scope documents only for baseline specifics; their immutable-issued-invoice rule is superseded above.
Do not reopen invoice grouping, branch-push approvals, signing, invitations, Compliance or broad context reconciliation. Do not run production SQL or reconstruct missing legacy migrations.
