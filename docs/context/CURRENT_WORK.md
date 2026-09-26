# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: dev/update-059-zip (local only)
Starting HEAD: adb01a2991d22684289bd943a879470b161099f0
Latest durable checkpoint: Update 059 ZIP handover; user commit pending
Build: 058 production baseline; 059 in delivered package
Last updated: 2026-09-25

## CURRENT TASK
Functional Reports Update 059 — ZIP delivery for user upload and direct commit to main.

## STATUS
READY FOR USER INSTALLATION — implemented and locally tested; not deployed.

## TASK-SPECIFIC LOCKED RULES
- USER OVERRIDE: ZIP updates with complete changed files only. The user uploads and commits directly to main. Do not push, merge, create PRs or deploy for this task.
- Include CURRENT_WORK.md in every update ZIP, recording actual code changes, tests, deployment state and outstanding work. Carry these ZIP workflow rules forward unless the user changes them.
- A documentation/review merge does not update the application. Main adb01a2 contained the Reports review/proposal but still ran build 058; this package contains actual code.
- Preserve RLS/least privilege, currency separation, one client value per Scoop and no invented Job revenue allocation. Unknown costs are not zero; no exchange rates or accounting recognition are invented.
- Migrations are forward-only. The user runs production SQL. Local commits are allowed; do not publish them.

## COMPLETED
- Rebuilt Reports UI and advanced filters; linked client/account/PM/resource IDs; multiple statuses; date basis/presets, languages/service/currency, cost/data-quality and margin bounds.
- Repaired search for project numbers with display names, languages, resources and PO references.
- Added numeric financial sorting, full-dataset grouping, per-currency summaries, separate blocker/estimate counts and URL persistence.
- Added source links, reset/retry/error states and dirty-filter protection against stale export.
- Fixed CSV negative numeric values, added per-currency numeric columns, Margin languages and grouped summaries; retained complete-snapshot export limit of 10,000.
- Added standalone migration 053 (052 optional), versioned filter-options RPC, schema preflight, grants/RLS preservation and read-only audit 014.
- Updated build marker and asset cache versions to 059. No production changes made.

## CHANGED FILES IN ZIP
- tms/reports.html — workspace layout and filters.
- tms/reports.css — scoped responsive styling.
- tms/reports.js — functional controls, tables, grouping, state and CSV.
- tms/build.json — build 059.
- tms/migrations/053_reports_functional_upgrade.sql — reporting/query/options functions.
- tms/audits/014_update_059_reports_audit.sql — read-only installation checks.
- tests/reports-ui.test.js — updated CSV/escaping checks.
- tests/reports-browser.cjs — Update 059 browser fixture checks.
- tests/update-059-reports-db.mjs — 23 reporting database regressions.
- tests/update-059-schema-compatibility.mjs — reporting-schema compatibility and audit checks.
- UPDATE_059_MANUAL_UPLOAD.md — full installation, test and acceptance instructions.
- docs/context/CURRENT_WORK.md — this continuity record.

## TEST RESULTS
- PASS: 23 isolated PostgreSQL reporting checks, including access/RLS and 1,103-row totals/pagination/export.
- PASS: 6 JavaScript CSV/escaping/warning checks.
- PASS: Chromium fixtures for three report views, linked filters, multi-status, sorting/grouping, URL reload, reset, paging, CSV/cap, errors, QA controls, sidebar and mobile overflow. Desktop/mobile screenshots inspected.
- PASS: 053 against repository reporting schema through 038, without 052, replacing 052, and reapplied; audit returns PASS.
- LIMITATION: historical migrations 037 and 040 are absent in the baseline repository. Compatibility test explicitly stubs the unrelated 037 audit writer and omits later unrelated migrations. It is not a complete historical replay or production acceptance test.
- PASS: JavaScript syntax and diff whitespace checks.

## UNRESOLVED / INCOMPLETE
- User installation: migration 053 → audit 014 → upload extracted ZIP contents at main root → commit → Reports acceptance.
- Authenticated production data/permissions remain unverified. Do not claim the update is live until the user confirms installation.
- Historical migration archive gaps 037/040 remain outside this package; do not reconstruct or change unrelated migrations for Reports.
- Invoice reporting, dashboard currency arithmetic and bulk-write changes remain outside this update.

## REQUIRED CONTEXT
NONE

## NEXT EXACT ACTION
Hand over RetodoOps_Update_059_Functional_Reports.zip and installation order. After the user's installation confirmation, record the new main commit/build and acceptance result here. Diagnose any reported issue against the installed 059 code.

## DO NOT REDO
- Do not resume the shell-push/approval workflow; ZIP delivery supersedes earlier branch-push instructions for this task.
- Do not reopen signing, invitations, Compliance or unrelated context reconciliation.
- Do not confuse the earlier proposal document with this implementation.
- Do not run old migrations or mark production accepted based solely on fixture tests.

## PRODUCTION STATE
Last checked main/live baseline: build 058, main adb01a2. Update 059 is prepared for user installation; migration, audit, upload and production acceptance are pending user confirmation. No assistant push, merge, deployment or production SQL execution occurred.
