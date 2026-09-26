# Update 059 — Functional Reports

Delivery: complete replacement files in a ZIP. Upload and commit by the user.
Baseline: main adb01a2991d22684289bd943a879470b161099f0 / build 058.
Prepared: 25 September 2026. Not deployed by the assistant.

## Install

1. Extract `RetodoOps_Update_059_Functional_Reports.zip` on your computer.
2. In Supabase → SQL Editor, open a new query, paste the entire contents of `tms/migrations/053_reports_functional_upgrade.sql`, and Run. This is the only new migration. It works whether migration 052 was previously run or missed; your earlier operational TMS migrations must already be installed.
3. Run the entire `tms/audits/014_update_059_reports_audit.sql`. Every result must be PASS. If any fail, retain the result and resolve it before the frontend upload.
4. Open **RetodoOps/retodo-ops-site**, select **main**, then **Add file → Upload files** at the repository root. Drag the extracted `tms`, `tests`, and `docs` folders plus `UPDATE_059_MANUAL_UPLOAD.md`. Preserve the folder structure. Upload the contents, not the ZIP or its enclosing folder. These are full files; no manual code editing is required.
5. Commit directly to main, for example: `Update 059: functional Reports and ZIP workflow`.
6. Open Reports and refresh with Ctrl+F5. The page should display **Update 059** with Projects, Jobs and Margin tabs. Test using your signed-in company account.

Do not rerun old migrations. No new environment variables, hosting configuration, or production data edits are required. Applying SQL first leaves the build 058 client usable during the upload. Reverting the frontend to 058 is compatible with the 053 RPC; do not delete SQL functions to roll back.

## Visible and functional changes

- Rebuilt Reports workspace with report-specific details, currency cards and data-quality counts.
- Search by record number even when a display name exists, language, resource, Job and PO reference.
- Client/account selection uses linked IDs. PM and Job resource choices come from existing records.
- Multiple statuses; language, service, currency, cost basis, data-quality and margin-range filters.
- Project-date/deadline basis, inclusive date bounds and month/quarter/year shortcuts.
- Numeric financial sorting within a selected currency; percent-margin sorting across currencies.
- Summaries grouped by client, account, PM or month; language pairs for Jobs/Margin; resource/service for Jobs.
- Saved URL filter state and compatible filter transfer between tabs.
- Projects/Scoops/Jobs and resource links; PO references lead to the parent Job (use its Supplier PO tab).
- Complete CSV up to 10,000 matching rows, separate numeric currency columns, negative amounts retained as numbers, Margin languages and grouped summaries. Larger exports ask you to narrow filters; they never silently truncate.
- Missing/outdated migration, access failure, no-results and retry states.

Financial meaning stays unchanged: commercial client value is counted once per Scoop; Jobs have no allocated client revenue. Known costs use the selected effective PO, otherwise a labelled saved estimate. Unknown costs stay unknown. Incomplete data suppresses profit/margin. Currency totals stay separate, without conversion. Estimates are shown separately from blockers. Filtering a Project/Scoop by language/service/cost basis selects the whole entity and preserves its full costs.

Invoice reporting remains outside this release. No payment/invoicing recognition, forecasts, charts, accounting export or exchange rates were added.

## Checks completed locally

- 23 isolated database regression checks: aggregation, PO versions, mixed currencies, missing costs, date boundaries, scopes, search, IDs, options, grouping, sorting, margin bounds, role denial/RLS, and 1,103-row pagination/export.
- 6 JavaScript checks: CSV formula protection, signed numbers, escaping, language/currency fields and warnings.
- Chromium fixture checks: all tabs, linked account filters, multi-status, grouping/sort, URL reload, dirty-filter export protection, reset, pagination, complete CSV, 10,000-row cap, missing migration, QA read controls, sidebar and mobile overflow. Desktop/mobile screenshots inspected.
- Schema compatibility: repository reporting tables and access helpers through migration 038; 053 without 052, replacement of 052, reapplication and read-only audit. The repository lacks historical migrations 037 and 040. The test explicitly substitutes the unrelated 037 audit writer and does not replay later unrelated migrations. This is not a complete historical migration-chain or production acceptance test.
- No authenticated production test or SQL execution was performed.

### Reproduce checks

From the repository root, with Node and isolated dependencies installed outside the repository:

```sh
node --test tests/reports-ui.test.js
PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tests/update-059-reports-db.mjs
PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tests/update-059-schema-compatibility.mjs
```

For browser fixtures, serve the repository on localhost:8765, then run `tests/reports-browser.cjs` with `PLAYWRIGHT_MODULE` pointing to Playwright. Optionally set `CHROMIUM_MODULE` to an installed Chromium provider module. Auth/RPC are mocked; no live credentials are used.

## After upload: acceptance

Search for a known Project number with a display name. Select a client/account; compare its results to the source Project. Check Jobs and Margin, including languages and source links. Select one currency, sort by profit/cost and inspect a grouped summary. Export CSV and verify a negative amount remains numeric. Check an estimate and an incomplete-cost row: these must have different indicators. If a migration message appears, retain its diagnostic details.

Once the user confirms migration, audit and upload are complete, update `docs/context/CURRENT_WORK.md` with that confirmation and any acceptance results. Do not mark production verified based only on these local tests.
