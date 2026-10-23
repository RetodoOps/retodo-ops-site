# Update 067 — Manual upload

Baseline: current main `ebb6f20d061fc284399973997627d8a2bdec6b3a` (Update 066).

The ZIP contains complete replacement files at repository-root paths. Upload all files without deleting unrelated main content. In particular, preserve the installed Update 066 invoice migration, audit, layout and Bulgarian issuer files.

## Complete files

1. `netlify/functions/_shared/sales-ai.js`
2. `netlify/functions/_shared/sales-worker.js`
3. `netlify/functions/sales.js`
4. `tms/sales.js`
5. `tms/sales.html`
6. `tms/migrations/063_sales_prospect_learning.sql`
7. `tms/audits/021_update_067_sales_research_audit.sql`
8. `tms/build.json`
9. `tests/update-063-sales-services.test.cjs`
10. `tests/update-063-sales-worker.test.cjs`
11. `tests/update-063-sales-diagnostics.test.cjs`
12. `tests/update-063-sales-browser.cjs`
13. `tests/update-063-sales-db.mjs`
14. `tests/update-067-sales-research-db.mjs`
15. `docs/sales/UPDATE_067_PROSPECT_LEARNING.md`
16. `docs/context/CURRENT_WORK.md`
17. `UPDATE_067_MANUAL_UPLOAD.md`

## Database and deployment

1. Run `tms/migrations/063_sales_prospect_learning.sql`.
2. Run `tms/audits/021_update_067_sales_research_audit.sql`; expect 15 `PASS` rows.
3. Deploy after the SQL succeeds.
4. Hard-refresh Sales and confirm build 067, 26 qualified canonical prospects and automatic research off.

The migration is forward-only and safe to reapply. It preserves non-research stages, existing contacts, notes, conversations, approvals and messages. It does not send email or run paid research.
