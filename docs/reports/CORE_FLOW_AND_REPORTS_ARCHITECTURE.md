# Core-flow verification and Reports architecture

Task: REPORTS-DESIGN-20260920. Date: 2026-09-20.
Status: PARTIAL verification; PROPOSED architecture, not an implemented Reports release.
Branch: dev/reports-architecture-20260920.
Base: 938c28a4c4edc362398ef3a46f79fdd3ad386b4f; application main 15b5922, build 057.

## Scope and authority

User approved core-flow verification followed by Reports architecture. No production writes, application workflow changes, invoice implementation, legal changes or exchange-rate policy are included. AGENTS.md overrides older startup/push instructions in 05_DEVELOPMENT_RULES.md. Private Master not needed/read. This is an unnumbered assessment, not Update 058.

## 1. Verification results

We cannot certify that all Dashboard/Project/Job flows work. Tests below are local fixtures/source checks, not live acceptance or an all-migrations replay.

| Check | Result | Limit |
|---|---|---|
| New actual-function assessment | 7 PASS, 1 TODO (reproduced financial defect) | VM executes selected real functions; no browser or DB |
| Update 044 isolated PostgreSQL fixture | 14 PASS | Includes active PO RPC, file visibility, Resource isolation, staff/QA denied paths; fixture schema, not current production |
| Update 050 isolated PostgreSQL fixture | 7 PASS | Approved Job history, duplicate file deletion and agreement boundaries; historical fixture |
| Dashboard/Project/Job JS syntax | PASS | Syntax only |
| Existing JS suite, first run | 87 PASS / 28 FAIL | Missing dependencies plus historical expectations |
| Full JS suite with locally available dependencies and new assessment | 100 PASS / 22 FAIL / 1 TODO | Not a green regression suite; remaining failures need individual triage |
| Full browser workflow / production RLS / current migration chain | NOT RUN | Requires a safe staging fixture and separate Admin/Resource sessions |

Commands:

```
node --test tests/reports-core-flow-assessment.test.js
node --test tests/*.test.js
PGLITE_MODULE=<installed-pglite-module> node tests/update-044-job-files-issues-db.mjs
PGLITE_MODULE=<installed-pglite-module> node tests/update-050-job-history-compliance-agreement-db.mjs
node --check tms/dashboard.js
node --check tms/project.js
node --check tms/job.js
```

Dependencies for the second suite run were reused from an existing local node_modules via NODE_PATH; no dependency/source files were changed. Remaining legacy failures include fixed old cache/build expectations, legal-document hash/snapshot expectations and a ZIP round-trip failure. Do not simply replace expected values to make the suite green. Agreement failures do not override separately user-confirmed live signing evidence, but still require test review.

### Verified or reproduced source behavior

- `project.js::jobSupplierCost/scoopMetrics`: active Issued/Acknowledged PO takes precedence over supplier estimate; cancelled/declined Jobs excluded. Fixture 31.00 EUR revenue minus 10.68 EUR cost = 20.32 EUR / 65.55%.
- `reference-data.js::scoopStatus`: active Job states derive Assign/Ongoing/Ready for QA/Approved; stored Scoop status wins. Manual/derived provenance matters.
- `dashboard.js::filterByTab`: status and missing-PO filters checked. Search/sorting/date-boundary browser tests remain pending.
- `job.js::assignResourceAndIssuePO`: assignment/PO RPC occurs before email; send failure displays an explicit retry message. Source inspection only, not provider-delivery test.
- Reports links exist in `job.html`; `tms/reports.html` does not exist. Navigation presence is not module implementation.

### Findings and gates

**RPT-01 — mixed-currency arithmetic (blocking financial trust).** `dashboard.js::reloadProjects`, `project.js::scoopMetrics` and migration 022 `refresh_project_financials` sum numeric PO/Job costs without converting or validating currencies. Job screen `renderJobFinancials` detects mismatch, so screens are inconsistent. Reproduced: 31 EUR minus 10.68 USD is displayed as numeric profit 20.32 by Scoop calculation. TODO test intentionally demonstrates the defect; it is not a functional PASS. No fix or exchange-rate assumption applied.

**RPT-02 — partial bulk state update (workflow reliability).** Dashboard `applyBulkStatus` independently updates Scoops and Projects using Promise.all. Mocked second-write failure leaves first write successful; error is shown but no atomic rollback occurs. Selecting a Scoop also updates its parent Project; sibling business semantics must be confirmed before changing that behavior. Design a transactional operation retaining approved semantics, not a silent new status policy.

**RPT-03 — query completeness (source risk, not demonstrated data loss).** Dashboard loads unpaginated collections across Projects/Scoops/Jobs/POs. Large datasets may hit server row limits; separate requests can observe different states. Reports must not reuse a browser-loaded Dashboard array as complete data.

**RPT-04 — no-Scoop fallback (source behavior needing validation).** Dashboard fallback overwrites Project totals/status with zero/Assign when no active Scoop is returned. Distinguish genuinely empty Projects from missing/filtered child data; do not use that synthetic row as financial truth.

**RPT-05 — regression and end-to-end coverage.** Current tests are not all green. Historical fixtures do not prove current full-chain assignment, revision, reassign, delivery and approval. Production mutations remain forbidden.

## 2. Proposed report contract

Phase 1 is read-only operational/commercial reporting, not accounting recognition. Call revenue 'Client value', and show whether cost is current PO commitment or a saved estimate. No paid/invoiced amounts inferred from Job status.

| Report | Row grain | Main data | Drill-down |
|---|---|---|---|
| Projects | One Project | Client/Account, PM, raw Project status, Scoop/Job counts, dates, client value, supplier costs by currency, valid profit/margin, warning count | Project then Scoops/Jobs |
| Jobs | One Job | Parent Project/Scoop IDs, service/languages, Resource, status/deadline, quantity/unit, effective PO ID/version/cost/currency, estimate flag | Job and current PO/history |
| Margin | One Scoop; grouped summaries by Project, Client, Account, PM or language pair | Client value counted once per Scoop, eligible Job costs, currency coverage and exceptions | Exact contributing Scoops/Jobs/POs |

Do not allocate an entire Scoop's client value to every Job. Job-level client allocation is not approved; omit additive Job profit/revenue from phase 1. When filtering Margin by Resource/service, avoid assigning full Scoop revenue to a subset of Jobs: either disable those dimensions or show whole-Scoop context explicitly as non-additive. Project counts are distinct Project IDs, not Dashboard Scoop row counts.

### Calculation and data-quality rules — proposed

1. Pre-aggregate active Scoop value once per Project. Pre-select one effective active PO per Job, then aggregate Jobs; never join raw PO versions and raw client lines into financial sums.
2. Match effective PO selection to existing contract: Issued/Acknowledged, newest created_at then ID as deterministic tie-break. Flag multiple active candidates, missing immutable versions and header/snapshot disagreement instead of silently concealing them.
3. Cancelled/declined Jobs are excluded from active operating cost, with excluded counts shown. Inclusion of cancelled Projects/Scoops in revenue requires explicit scope; propose default active-only with clearly separate historical/cancelled views.
4. Saved supplier_amount fallback must be labelled estimate. Unknown/missing rate is not free work. Show cost completeness and suppress claims of final margin when incomplete.
5. No currency conversion in phase 1. Display separate currency totals. Suppress profit/margin on incompatible currencies and show 'Currency conversion required'; do not add unlike currencies or assume parity.
6. Profit = eligible client value minus comparable cost. Aggregate margin = total profit / total client value, not mean of row percentages. Zero revenue => proposed N/A margin (current UI uses zero; changing it is a separately reviewed display decision).
7. Use database NUMERIC and existing line-rounding semantics; format money only at display/export boundary. Test fractional CAT quantities and rounding drift.
8. Apply 40% normal floor / 50% target from existing decision register as visible advisory markers, not new automatic assignment blocks.
9. Dates need an explicit basis (Project date, deadline, or available approval timestamp), chosen timezone and inclusive-date UI converted to half-open timestamp bounds. Phase 1 proposes Project date for Project/Margin, deadline for Jobs. These are not interchangeable invoice periods.
10. Quantities aggregate only within the same unit; words, hours, pages and fixed fees must not be combined into one volume.

## 3. Technical shape — proposed, not implemented

- Keep the static HTML/JS/CSS + Supabase architecture. New `tms/reports.html` / `reports.js` would supply tabs, filters, a results table, warning summary and drill-down links.
- Shared read-only PostgreSQL reporting functions/views should own effective-PO selection, grouping and totals. Prefer invoker rights and existing RLS; verify actual policy helpers before implementation. Do not copy Dashboard arithmetic into a second browser calculator.
- Query returns rows, filtered total count, currency-separated summary, coverage/warnings, applied filters and generated-at timestamp from one consistent request/snapshot. Proposed shape: `{rows,total_count,summary_by_currency,warnings,filters,generated_at,next_cursor}`.
- Allowlisted filters/sorts only; deterministic ID tie-break and bounded server pagination. Summary covers the full filtered dataset, not merely the visible page. Drill-down and export use identical scope and permission checks.
- Proposed CSV export: server-authorized, bounded/chunked, sanitized against spreadsheet formula injection, filter/timezone/currency metadata included. Preserve exact IDs and visible warning fields. Exports are not invoices.
- Existing roles include admin, pm, qa, client_relations and resource. No new Finance role assumed. Reports permissions must be mapped to existing authorized operational/financial reads and explicitly reviewed; do not grant company-wide margin access merely because a sidebar link is visible. External Resource and anonymous access to company reports denied server-side, including counts, summaries and exports.
- No caches/materialized views initially. Add only after measured need with explicit freshness rules. No service-role secret in browser and no security-definer bypass without scoped authorization tests.
- Invoice report deferred/clearly unavailable until invoice entities, approval rules and accounting scope exist. Do not derive invoices from Projects marked Approved.

## 4. Remaining acceptance matrix

Use isolated staging or mocked browser fixtures; never production writes without permission.

| Scenario | Required evidence |
|---|---|
| Create Project with multiple Scoops and Jobs | Stable IDs, language/rate inheritance, Project totals equal unique Scoops |
| Assign, email failure and retry | One current PO, correct Resource, explicit provider state, no duplicate business effect |
| Revise PO and reassign Resource | Old version retained; current cost changes once; client value unchanged |
| Deliver, request revision, approve, cancel | Status transitions and permissions consistent across screens; audit preserved |
| File upload/download/delete | Own Resource allowed; other Resource/anonymous denied; binary/metadata completion checked |
| Pricing edge cases | Same/mixed currency, missing rates, zero value, flat fee, CAT rounding and excluded work |
| Dashboard interactions | Search, sort, date boundaries, bulk partial failures and parent/sibling behavior |
| Reporting cardinality | 2 Scoops × multiple Jobs × multiple PO versions: no duplication; page totals equal export totals |
| Scale / concurrency | Dataset beyond API cap, stable pagination and coherent summary/rows |
| Role matrix | Admin/PM/QA/client_relations scopes and external denial at DB/API/export, not only UI |

## 5. Next action

Review proposed report grains, currency handling, date defaults and internal-role visibility with the user. Before implementing financial reports, repair/verify RPT-01 and address RPT-02 under a separately recorded development task. Triage legacy tests without weakening assertions; run current full-chain staging checks. No production-ready claim is justified yet.

Durable evidence: tests/reports-core-flow-assessment.test.js plus CURRENT_WORK and DEV_WORKLOG on this task branch. No application code/schema/build/environment changes in this assessment.
