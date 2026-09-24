# Update 059 — Reliable and usable Reports

Baseline: main `5f8435615f4b9fa63ce1b986bfd063380f04bad5`, build 058.
Review branch: `dev/reports-upgrade-059-20260924` (publication explicitly approved; resolve remote branch HEAD).
Status: implemented and fixture-tested; **not deployed or accepted on production**.

## Ordered installation and acceptance

1. Restore the authoritative missing prerequisite migration 037, or provide an approved staging database/schema export representing the actual installed schema and policies. The repository chain runs through 036 but 038 rejects startup without 037's trusted audit function. Do not invent or bypass this prerequisite. Later missing numbered migrations may require verification too.
2. On isolated/staging data, verify the installed migrations and signatures of `public.tms_report(text,jsonb,integer,integer,text,boolean)` and `public.tms_report_options()`. Apply the original 052 if genuinely absent, then apply the new `tms/migrations/053_reports_functional_upgrade.sql`. Do not edit or rerun old migrations blindly. 053 only replaces/adds invoker-rights reporting functions and their execution grants; it does not modify business tables or data.
3. Verify an authenticated Admin, PM and permitted QA can call both RPCs; external, disabled and anonymous users must be denied. Check PostgREST schema visibility/cache separately from database function existence. A public anonymous 404 alone does not establish migration state. Both RPCs must return `api_version: 59` before using the new UI.
4. Copy the full replacement application files from this ZIP, preserving paths: `tms/reports.html`, `tms/reports.js`, `tms/reports.css`, `tms/job.html`, `tms/job.js`, `tms/build.json`. The Job change only opens a requested, already-loaded PO version via `?id=JOB&po=PO&version=N`; existing authorization remains in place. No manual code insertion is needed. The ZIP omits unchanged repository files and dependencies.
5. Run the tests below and perform staging acceptance with actual schema/policies and representative data: stable Project number/name search; duplicate-name selectors; Project/Scoop whole-total semantics; multiple services per Scoop; mixed currencies; missing/estimated costs; PO conflicts/snapshots; null-last financial sorting; currency summaries; grouping; page/export reconciliation; refresh/back/tab filters; original record links and exact PO version. Check failed API states separately from zero rows.
6. Open an exported CSV in the intended spreadsheet application's import dialog. Confirm negative profit/margin and precise quantities are numeric, and malicious text beginning with `=`, `+`, `-`, `@` remains text. Use UTF-8, comma delimiter and dot decimal separator; metadata, rows, currency totals and optional grouped summaries are separate labelled sections. This native Excel/Calc import gate was not executed in this environment. Automated tests verify the emitted numeric/text serialization, not native application import behavior.
7. Obtain separate authorization before any production migration/deployment. After release, authenticate and smoke-test the three reports plus their CSVs; verify build 059 and both RPC versions. Fixture PASS is not production acceptance. If the API is unavailable the page displays a clear error and Retry, with administrator-only diagnostics; an absent client script has a visible reload fallback.

## Implemented behavior

- Project number search independently of display name; language/resource/service relationship search without slicing Project/Scoop totals.
- Searchable Client, dependent Account, PM and Resource selectors use stable IDs. Legacy Projects without PM IDs expose explicitly labelled exact-name choices; identical historical names cannot be disambiguated without correcting source data.
- Entity status choices come from the existing database CHECK constraints. Multiple statuses, languages, service, currency, cost basis, issue/information filters and margin ranges are available.
- Project date or the actual Project/Scoop/Job deadline (UTC), with month/year/last-month/30-day presets. No invented approval or delivery dates.
- Financial sorting requires one currency; costs rank the selected currency's known-cost bucket. Nulls sort last and IDs break ties. Jobs never receive allocated client revenue.
- Applied filters survive URL refresh/back and compatible tab changes. Entity-specific status, date basis, grouping, quality and margin controls reset on tab changes to avoid applying incompatible meanings.
- Distinct Project/Job/Margin layouts, sticky headers, record links and PO-version links. Responsive layout and read-only QA controls retained.
- Currency-separated commercial value, known costs, profit and weighted margin; quality counters drill into matching rows. Estimates/exclusions are informational, separate from blocking issues.
- Summaries group by Client, Account, PM or selected-date month. Resource grouping is Jobs-only. Project/Scoop revenue is never duplicated across resource/service groups. PM IDs remain one group even when historical display labels differ.
- Explicit per-report CSV schemas include Margin language pairs, stable IDs, source references, cost basis where applicable and warning codes. Each cost currency has its own numeric column; costs are not packed into JSON. Numeric values retain signs and precision; untrusted strings retain formula-injection protection. Full-query summaries and the 10,000-row export cap remain.
- Invoice reporting, FX policy, accounting recognition, other Dashboard calculations and signing changes remain outside this package.

## Verification performed

- 28 isolated PGlite database checks passed, including financial invariants, new filters/search/grouping, stable ordering, selector identity, real status-constraint extraction, disabled/external/anonymous denial, invoker RLS and 1,103-row paging/export.
- 7 Node export/UI unit tests passed.
- Chromium browser fixture passed selectors, status contract, URL refresh/back/tab state, pagination, CSV/cap, source-link construction, QA controls, XSS escaping, responsive overflow, distinct backend error states, retry and missing-script fallback. Desktop filters/results and narrow results inspected visually. Existing Job PO rendering still requires authenticated staging acceptance for the new deep link.
- JavaScript syntax and `git diff --check` passed.
- Actual repository setup and migrations 001–036 applied in isolated PGlite. Migration 038 failed because required migration 037 is absent. Only Supabase platform auth objects are shimmed; PGlite's unavailable `CREATE EXTENSION pgcrypto` statement is omitted because the chain only needs PostgreSQL's built-in `gen_random_uuid`. No business migration, policy or trusted audit function was fabricated to continue past the failure.

## Reproduce locally

Use installed test dependencies without adding them to the application package:

```sh
node --check tms/reports.js
node --check tms/job.js
node --test tests/reports-ui.test.js
PGLITE_MODULE=/path/to/@electric-sql/pglite/dist/index.js node tests/reports-db.mjs
PGLITE_MODULE=/path/to/@electric-sql/pglite/dist/index.js node tests/reports-chain.mjs
# Serve the repository locally in another terminal:
python -m http.server 8765 --bind 127.0.0.1
PLAYWRIGHT_MODULE=/path/to/playwright REPORT_BASE_URL=http://127.0.0.1:8765/tms/ node tests/reports-browser.cjs
```

The chain runner intentionally exits nonzero at an unresolved migration prerequisite. The browser suite uses synthetic records and RPC fixtures, not production accounts. Optional `CHROMIUM_MODULE` points to `@sparticuz/chromium/build/index.js`; `CHROMIUM_EXECUTABLE` can point to an already-extracted executable. Browser fixture screenshots are temporary test outputs, not deployment files.
