# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: dev/update-060-csv-zip (local only)
Starting HEAD: fef44a3852ab82c660cb407aafd1dd8240664ef7
Latest durable checkpoint: main fef44a3 contains Update 059; Update 060 ZIP prepared locally
Build: 059 user-confirmed installed baseline; 060 in this package
Last updated: 2026-09-26

## CURRENT TASK
Update 060 — fix CSV columns when opened directly in regional Excel; ZIP delivery.

## STATUS
READY FOR USER INSTALLATION — Update 060 export fix; Update 059 committed and initially functional per user.

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

## UPDATE 060 CHANGES AND CONFIRMATION
- 2026-09-26: user confirmed Update 059 was committed; Reports seem functional at first glance. Supplied screenshot shows the Jobs export containing 17 rows, opened as comma-separated text in Excel column A.
- Read-only fetch verified main fef44a3 (Add files via upload). Affected files match the delivered 059 files. No independent production SQL/audit acceptance is claimed.
- CSV now begins with UTF-8 BOM plus Excel's `sep=,` directive. This addresses delimiter detection on direct open without changing Windows regional settings.
- Existing report data, quoting, formula-text protection, signed numbers, summaries, filters and database API 059 are retained. No SQL changes.
- Updated frontend build marker and JavaScript cache version to 060.

## CHANGED FILES IN ZIP
- tms/reports.js — explicit Excel comma-separator directive.
- tms/reports.html — build marker and JavaScript cache version 060.
- tms/build.json — release 060.
- docs/context/CURRENT_WORK.md — 059 confirmation, 060 fix and remaining acceptance.
- UPDATE_060_MANUAL_UPLOAD.md — upload instructions and existing-file workaround.

## TEST RESULTS
Update 060: existing 6 CSV/escaping checks pass; CSV round-trip preserves Unicode, commas, quotes, newlines and signed decimal text. JavaScript syntax/diff checks pass. Microsoft Excel desktop is not available in this environment; direct-open acceptance on the user’s Excel is pending.

Prior Update 059 results:
- PASS: 23 isolated PostgreSQL reporting checks, including access/RLS and 1,103-row totals/pagination/export.
- PASS: 6 JavaScript CSV/escaping/warning checks.
- PASS: Chromium fixtures for three report views, linked filters, multi-status, sorting/grouping, URL reload, reset, paging, CSV/cap, errors, QA controls, sidebar and mobile overflow. Desktop/mobile screenshots inspected.
- PASS: 053 against repository reporting schema through 038, without 052, replacing 052, and reapplied; audit returns PASS.
- LIMITATION: historical migrations 037 and 040 are absent in the baseline repository. Compatibility test explicitly stubs the unrelated 037 audit writer and omits later unrelated migrations. It is not a complete historical replay or production acceptance test.
- PASS: JavaScript syntax and diff whitespace checks.

## UNRESOLVED / INCOMPLETE
- Upload Update 060 extracted contents to main, commit, refresh Reports and download a NEW CSV. Old CSV files are unchanged.
- Confirm new CSV opens across columns in the user's Excel. Numeric/date interpretation still depends on Excel locale; for explicit decimal typing, import using comma delimiter and English (United States) numeric locale. No native XLSX export is included.
- User reports initial 059 functionality; full production financial/permissions acceptance and SQL audit output are not independently verified.
- Historical migration archive gaps 037/040 and Invoice reporting remain outside this patch.

## REQUIRED CONTEXT
NONE

## NEXT EXACT ACTION
Hand over RetodoOps_Update_060_Excel_CSV_Fix.zip. User uploads/commits; no SQL. On confirmation, update this record with main/build and Excel column-opening result.

## DO NOT REDO
- Do not resume the shell-push/approval workflow; ZIP delivery supersedes earlier branch-push instructions for this task.
- Do not reopen signing, invitations, Compliance or unrelated context reconciliation.
- Do not confuse the earlier proposal document with this implementation.
- Do not run old migrations or mark production accepted based solely on fixture tests.

## PRODUCTION STATE
Main fef44a3 includes build 059, verified by read-only fetch on 2026-09-26. User reports Reports working at first glance and provided an actual Jobs CSV screenshot. Update 060 is local/packaged, pending user upload and Excel acceptance. No assistant push, merge, deployment or production SQL execution occurred.
