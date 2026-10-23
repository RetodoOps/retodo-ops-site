# Update 068 — Manual upload

Baseline: installed Update 067 prospect learning set.

The ZIP contains complete replacement files at repository-root paths. Upload every file without deleting unrelated main content. Preserve Update 066 invoice files and the installed Update 067 migration/audit.

## Complete files

1. `netlify/functions/_shared/sales-ai.js`
2. `netlify/functions/sales.js`
3. `tms/sales.js`
4. `tms/sales.html`
5. `tms/migrations/064_sales_cold_prospect_guard.sql`
6. `tms/audits/021_update_067_sales_research_audit.sql`
7. `tms/audits/022_update_068_sales_cold_prospect_audit.sql`
8. `tms/build.json`
9. `tests/update-063-sales-services.test.cjs`
10. `tests/update-063-sales-db.mjs`
11. `tests/update-068-sales-cold-db.mjs`
12. `docs/sales/UPDATE_068_COLD_PROSPECT_GUARD.md`
13. `docs/context/CURRENT_WORK.md`
14. `UPDATE_068_MANUAL_UPLOAD.md`

## Database and deployment

1. Run `tms/migrations/064_sales_cold_prospect_guard.sql`.
2. Run `tms/audits/022_update_068_sales_cold_prospect_audit.sql`; expect 10 `PASS` rows.
3. Deploy after the SQL succeeds.
4. Hard-refresh Sales and confirm build 068 and Research `On demand`.

The migration is forward-only and safe to reapply. It does not change prospect stages, remove contacts, create conversations, send outreach or run paid research.
