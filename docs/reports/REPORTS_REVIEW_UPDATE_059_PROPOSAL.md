# Reports review and proposed Update 059

Date: 2026-09-24
Repository: RetodoOps/retodo-ops-site
Reviewed main: 5f8435615f4b9fa63ce1b986bfd063380f04bad5
Reviewed build: 058 (PR 24 implementation; PR 25 continuity)
Task branch: dev/reports-review-20260924
Status: REVIEW COMPLETE / PACKAGE PROPOSED — no application changes or release performed.

## Assessment

The module is an implemented first version, not merely a mockup: Projects, Jobs and Scoop-level Margin call a database reporting function and support paging and CSV. Its foundations are worth retaining. It is not yet a complete reporting workspace, and live authenticated functionality is unverified.

The immediate release dependency and the functional improvements should be handled separately. A new UI cannot repair an unavailable database function.

## Live observations and limits

- GET https://tms.retodo-ops.com/build.json returned HTTP 200 and build 058.
- A read-only GET to the configured Supabase reporting RPC using the application's public anonymous key returned HTTP 404 / PGRST202: public.tms_report could not be found in the schema cache for the supplied parameters.
- This is a release diagnostic, not an authenticated Admin test. It does not alone prove migration 052 was never applied. Verify function existence/signature, API schema exposure and an authenticated company-role call before selecting the remedy.
- CURRENT_WORK.md records migration 052 and full migration-chain/staging acceptance as unverified.
- No authenticated production data, private credentials, production writes or migration execution were used in this review. Live screens behind login were not visually tested.

## Verified findings

| Priority | Finding | Evidence | Required change |
| --- | --- | --- | --- |
| P1 | Exact Project-number search fails when a different display name exists. | Isolated SQL fixture: project_number P1 / display_name Project one; search P1 returns zero. Migration 052 creates `name` from display_name and the search predicate omits project_number. | Search stable record numbers independently of names. Include Project number when searching Jobs and Margin too. |
| P1 | Projects search advertises language/resource search but does not search related Scoops/Jobs. | A Project with a Bulgarian Scoop and Resource one returns zero for either query. These fields are not present on Project report rows, although the shared placeholder advertises them. | Implement relationship-aware search using EXISTS, preserving whole-Project totals, or use accurately scoped search labels. Dedicated filters are recommended. |
| P1 | Negative numeric CSV values are converted to text. | `csvCell(-12.34)` produces an apostrophe-prefixed cell. The serializer treats trusted numeric values as possible formulas. | Preserve finite numeric values as numeric CSV content; keep formula-injection protection for strings. Verify negative profit/margin and positive values in an actual spreadsheet import. |
| P2 | Warning totals and visible warning messages use different definitions. | Three-Job fixture: two estimated costs are shown as warnings while `warning_rows` is zero. | Separate blocking data issues from informational estimates/exclusions, with matching badges, counts and filters. |
| P2 | Status options include values the current Job schema does not accept. | reports.js offers Offered and Declined; migration 014's latest Job status constraint allows Unassigned, Assigned, In Progress, Delivered, Revision Required, Approved and Cancelled. | Derive status options from a shared authoritative contract, specific to each report entity. |
| P2 | Margin exports omit the language pair. | reports.js uses the shared Projects/Margin export field list without source_language or target_language even though SQL returns both for Margin. | Give each report its own explicit columns and export schema. |
| P2 | Sorting cannot answer basic commercial questions. | SQL allowlist and UI support only name, date, status and client. | Add numeric cost/profit/margin sorting, with nulls last and deterministic ID tie-breakers; monetary ranking must be within a chosen currency. |

Five new isolated reproductions confirmed the first four rows (language and resource tested separately). The remaining findings were verified directly against the current source/schema; no production failures are inferred from them.

## Functional limitations verified in the code

- Client, Account and PM are partial-text inputs, not linked selectors. Duplicate/similar names can match multiple entities.
- There are no dedicated resource, language pair, service, currency, cost-basis, missing-cost or margin-range filters.
- No group-by controls, period comparisons, saved views or configurable columns.
- Projects/Margin dates always mean Project date; Jobs dates mean UTC Job deadline. The basis is explained, but cannot be changed to answer other date-based questions.
- Switching report tabs reloads the page and resets the applied filters; URL contains only report type.
- Job and Scoop links exist; PO numbers and resources are plain text without direct record links.
- Detailed supplier costs are exported as JSON in one cell; this is inconvenient for spreadsheet analysis.
- Invoice Report is an explicit unavailable screen. It should remain deferred until the invoicing data/workflow exists.

## Retain from build 058

- One row per Project, one per Job and one per Scoop for Margin.
- Client value counted once at Scoop level; no invented per-Job client allocation.
- Separate currency buckets without assumed exchange rates.
- Unknown/incompatible costs and PO conflicts suppress unreliable margin.
- Labelled saved-cost estimates and immutable PO snapshot checks.
- Invoker-rights RPC, existing RLS, company/access-enabled checks and no anonymous execution grant.
- Deterministic pagination and fresh-snapshot CSV export with explicit 10,000-row cap.
- HTML escaping and CSV formula protection for untrusted text.

## Proposed Update 059 — Reliable and usable Reports

This is a proposed scope, not a locked business-policy change or an already implemented package. Reserve the next available release number at implementation start if another profile has advanced the build.

### A. Release readiness and correctness — mandatory first

1. Validate the current migration chain in an isolated/staging database with the actual schema and policies.
2. Verify authenticated company-role reporting. Distinguish missing migration/schema from permission, network and query errors.
3. If migration 052 is absent, its production application remains a separately authorized release action. If it exists but needs changes, use a new forward-only migration; do not rewrite production migration history.
4. Fix search identity and relationship matching, stale status options, CSV numeric typing and warning consistency.
5. Add a clear service-unavailable state, retry action and administrator diagnostic details. Do not show an unavailable backend as an empty business report.

### B. Practical reporting controls — recommended core package

- Searchable selectors for Client, dependent Account, PM and Resource; stable IDs for relational filters.
- Language pair, service and currency selectors; multi-select statuses based on the appropriate entity.
- Cost-basis and data-quality filters: issued PO, estimate, unknown cost, PO conflict, currency mismatch.
- Date presets and an explicitly labelled date basis. Any additional delivery/approval basis must use actual stored event dates, not invented timestamps.
- Numeric margin range and financial sorting within a currency. No global ranking that treats EUR and USD as equivalent.
- Persist applied filters in the URL and preserve compatible filters when switching tabs. Clearly display active filters and reset.
- Clickable Project, Scoop, Job, PO and Resource references, respecting existing page permissions.

### C. Report-specific layouts — recommended core package

| View | Primary purpose | Proposed visible columns |
| --- | --- | --- |
| Projects | Portfolio status and commercial totals | Project number/name, Client, Account, PM, Project date/deadline, status, Scoop/Job counts, client value, supplier costs by currency, profit/margin, data quality |
| Jobs | Supplier workload and commitments | Job/Project/Scoop, Resource, language pair, service, deadline, status, quantity/unit, cost/currency, cost basis, PO/version, data quality |
| Margin | Identify profitable and problematic Scoops | Project/Scoop, Client/Account, language pair, status, client currency/value, costs, profit, margin, estimate/data-quality indicators |

Use the existing visual system with aligned labels, compact filters, consistent buttons, sticky headers, readable numeric columns and compact information help. Important errors and financial uncertainty must remain visible rather than being hidden in tooltips.

### D. Actionable summaries — recommended after B/C

- Currency-separated commercial value, known cost, profit and weighted margin.
- Counts for missing data, estimates and PO conflicts, each linked to the matching filtered results.
- Grouping by Client, Account, PM, Resource or month where compatible with the report grain.
- Never average row margin percentages; use aggregate profit / aggregate client value where all underlying amounts are valid and comparable.
- Language/service filters on Projects should select matching Projects without silently slicing their totals. Resource filters belong naturally on Jobs; any later Margin resource filter must retain complete Scoop costs and say so explicitly.
- Never duplicate Scoop revenue across multiple Job services/resources in grouped reports.

### E. Spreadsheet-ready exports — mandatory

- Separate numeric amount and currency columns; flat rows instead of cost JSON as the only detailed export.
- Preserve signed numeric values and high-precision quantities; escape untrusted text.
- Include language pair, cost basis, warning codes, stable IDs and source record references where appropriate.
- Include applied filters, date basis and generation timestamp in clearly separated metadata.
- Retain same-query row counts/currency totals and explicit export cap. XLSX may be a later enhancement; correct CSV is sufficient for this package.

## Proposed implementation files

Exact filenames/next migration number must be checked against live main when implementation begins:

- tms/reports.html — view-specific filters, columns and diagnostics.
- tms/reports.js — filter state, links, renderers and typed export.
- tms/reports.css — reporting layouts using existing shared tokens.
- tms/migrations/053_reports_functional_upgrade.sql — proposed next forward-only query/filter migration, only if still unused.
- tms/reference-data.js — only if needed for the shared status contract.
- tests/reports-db.mjs, tests/reports-ui.test.js, tests/reports-browser.cjs — targeted regressions and actual-schema integration coverage.
- tms/build.json and relevant Reports cache keys — advance together when code is ready.
- docs/context/CURRENT_WORK.md and release-specific deployment/acceptance instructions.

The deliverable should be a non-main reviewable branch and a ZIP containing only full changed/replacement files, any new migration and a short ordered README. Do not distribute the full repository or partial code snippets for manual insertion.

## Acceptance gates

1. Real-schema staging RPC loads for Admin, PM and permitted QA; disabled/external/anonymous users remain denied.
2. Project number P1 remains searchable when display_name differs. Language/resource matching behaves as the labels promise.
3. Selector IDs distinguish duplicate names; status lists match actual schema; filter reset/tab/back/refresh behavior is consistent.
4. A Scoop with Translation + Revision contributes client value exactly once. Mixed currencies, missing costs, current PO conflicts, empty Scoops and unallocated Jobs remain honest and traceable.
5. Summary issue counts match row badges and issue filters. Estimates are distinguishable from blocking errors.
6. Sorting/pagination/export use identical filters and stable ordering. Negative profit stays numeric in a spreadsheet; no formula injection regression.
7. Source links open the intended Project/Scoop/Job/PO/Resource. Both wide and narrow browser layouts are inspected.
8. Missing migration, denied access, timeout and zero matching records are distinct states.
9. Authenticated production smoke test only after separately authorized release; fixture PASS is not production acceptance.

## Out of scope

Invoicing/accounting recognition, exchange-rate policy, unrelated Dashboard currency arithmetic, Dashboard atomic bulk-status changes, signing/PDF/invitation changes and context reconciliation. Those items are not fixed by this proposal.

## Coordination and checkpoint status

The review uses a fresh isolated branch, preserving the older worktree and the other profile's implementation. The initial local checkpoint is 07a53bc; the review is b427594. Earlier automatic-review push denials were followed by explicit user authorization naming both documentation files and the exact repository/branch. The next shell push failed because command-line Git had no credentials. Publication uses the authenticated GitHub connector with the same two-file payload and original base; resolve the remote branch HEAD for the durable publication commit. No main merge or production release is part of this authorization.
