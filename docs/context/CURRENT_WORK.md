# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: dev/reports-implementation-20260924
Starting HEAD: d7c3cb5b8dcc948a7820774c7448ae01df2baa49
Latest durable implementation checkpoint: 1f9675e27d478a6d587ec519e94d352fb736c12d
Latest continuity checkpoint: this commit; resolve task branch HEAD
Draft PR: https://github.com/RetodoOps/retodo-ops-site/pull/24
Build: 058 on task branch; main/live baseline remains 057
Last updated: 2026-09-24

## CURRENT TASK
Build Reports: Projects, Jobs and Margin.

## STATUS
IMPLEMENTED — local fixture checks pass; pending PR review and explicit release approval.

## TASK-SPECIFIC LOCKED RULES
- User selected Projects, Jobs, Margin: read-only filters, CSV export, separate currency totals and unreliable-margin warnings.
- No merge/main push, production deployment, production migration, production data/auth/environment changes.
- Preserve existing permissions; no exchange-rate assumptions or accounting recognition.
- No unrelated context reconciliation or signing-flow changes.
- Checkpoint code and this record together on the active non-main branch.

## COMPLETED
- Verified current main and build 057.
- User explicitly requested Reports implementation and selected the three-report scope.
- Created task branch from current main.
- Inspected prior Reports assessment from existing local assessment branch because current main records proposal as partial and contains no detailed requirements.
- Current main application source matches local assessment checkout; only continuity documents differ.
- Implemented Projects, Jobs and Margin reporting plus migration 052.
- Completed 17 DB checks, 5 unit tests and Chromium browser fixture.
- Pushed code and continuity checkpoints; opened draft PR #24.

## CHANGED FILES
- docs/context/CURRENT_WORK.md
- tms/reports.html
- tms/reports.js
- tms/reports.css
- tms/build.json
- tms/migrations/052_read_only_reports.sql
- tests/reports-db.mjs
- tests/reports-ui.test.js
- tests/reports-browser.cjs

## TEST RESULTS
- Reports JavaScript syntax PASS.
- Isolated PGlite fixture: 17 checks PASS (cardinality, currencies, estimates, incomplete records, PO versions, dates, roles/RLS and 1,103-row paging/export).
- UI/export unit tests: 5 PASS (CSV injection, metadata, escaping and warnings).
- Chromium/Playwright browser fixture PASS: report tabs, filters, pagination, empty/error states, CSV download, export limit, QA controls, sidebar, hostile-name escaping, and narrow-screen overflow.
- Desktop and mobile screenshots inspected. Fixed results-table flex collapse and hidden-form styling.
- Standard Chromium download failed; npm-packaged Chromium used successfully.
- Fixture tests are not production or full migration-chain acceptance.

## UNRESOLVED / INCOMPLETE
- Reports page/API implemented with Projects/Jobs/Margin, filters, pagination and bounded CSV export; awaiting review/release.
- Existing company-role read permissions preserved via invoker RPC and table RLS; inactive/external users denied.
- Database and browser fixture tests pass; production/current full migration-chain acceptance not run.
- Migration 052 is prepared only, not executed on production.
- Export is a fresh consistent snapshot, capped at 10,000 rows; larger datasets require narrower filters.
- Invoice reporting remains explicitly unavailable.
- Production merge/deployment/migration need explicit user approval.
- Empty Scoops and unallocated Jobs suppress margins.
- Prior mixed-currency arithmetic and bulk partial-write findings remain unresolved outside new report scope.
- Prior assessment is evidence/proposal, not proof of production correctness.

## REQUIRED CONTEXT
NONE — inspect relevant application source and schema as needed.

## NEXT EXACT ACTION
Review draft PR #24 with the user. Before release, run staging/current migration-chain acceptance. Merge and production migration/deployment require explicit user approval; do not execute automatically.

## DO NOT REDO
- Do not restart context reconciliation.
- Do not claim existing Dashboard/Project arithmetic or bulk writes are fixed.
- Do not reopen user-confirmed signing/PDF/invitation behavior without regression evidence.

## VALIDATION COMMANDS

- `node --check tms/reports.js`
- `node --test tests/reports-ui.test.js`
- `PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tests/reports-db.mjs` (tested with 0.5.8)
- Serve repository locally, then `PLAYWRIGHT_MODULE=/absolute/path/to/playwright REPORT_BASE_URL=http://127.0.0.1:8765/tms/ node tests/reports-browser.cjs`; installed Chromium required. Optional `CHROMIUM_MODULE` points to @sparticuz/chromium/build/index.js.

## REVIEW BOUNDARIES

- No production data, configuration, authentication or deployment changes.
- Company-role read access follows existing RLS; no new permission grants to underlying tables.
- Project date filters for Projects/Margin; UTC deadline dates for Jobs.
- Active scope excludes cancelled Projects, inactive/cancelled Scoops and cancelled/declined Jobs. All scope explicitly includes them.
- Margin uses full Scoop costs, never job-allocated client revenue. Estimates are labelled; incomplete/incompatible/conflicting costs suppress profit and margin.
