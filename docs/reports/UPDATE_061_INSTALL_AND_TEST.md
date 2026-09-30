# Update 061 — install and test

Baseline: build 060, main 0c704f0. Package: complete changed files, not a patch or a proposal.
The ZIP workflow is unchanged: you upload files to main and make the commit yourself.

## Installation order

1. Extract the ZIP. Read the two new SQL files locally. In Supabase SQL Editor, run `tms/migrations/054_reports_eur_scoop_detail.sql`, then `tms/migrations/055_client_scoop_invoicing.sql`. Migration 053 from Update 059 must already be installed. Do not rerun historical setup/migrations.
2. Run `tms/audits/015_update_061_reports_invoices_audit.sql`. Every result should be PASS. This checks installation and permissions; it does not issue invoices or modify business data.
3. Upload the ZIP's complete `tms/`, `netlify/`, `docs/` and `tests/` contents to the matching repository-root paths, preserving folders, and commit on main. Include `docs/context/CURRENT_WORK.md`. Do not upload only the ZIP file or nest everything under another directory.
4. Let the existing Netlify deployment finish. Confirm `/build.json` reports 061 and hard-refresh Reports/Client Invoice. Do not use the 061 frontend before its SQL is installed.
5. The new `report-exchange-rates` function uses the existing server-only `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. `TMS_SITE_URL`, if configured, must match the live site origin (default is https://tms.retodo-ops.com). Never place the service key in config.js or Git. Opening Reports or refreshing Invoices requests ECB rates. Check the displayed reference date for foreign-currency tests. If refresh fails, the latest valid saved snapshot is used; otherwise non-EUR conversions remain unavailable.
6. As administrator, open Client Invoice → Invoice settings and enter the correct issuer details and next invoice number. Verify each Client's payment days and active Billing entity. Enter the applicable tax rate/basis on each draft before issuing.

Existing Reports API 059 is retained, so applying SQL before uploading frontend files is supported. The migrations do not backfill business invoices or edit source prices. New invoice triggers protect issued records, and ordinary-user writes to client finance tables go through guarded RPCs.

## Reports acceptance

- Open Projects: confirm each Scoop is on a separate row, with its languages and Project link.
- On the EUR 40 / EUR 22 example, expand **View Job costs**. The unassigned TEST Job with no saved rate/PO is unknown even if the dashboard displayed zero. The complete Scoop has a margin; the incomplete Scoop shows provisional profit from known costs and names the missing Job. If TEST legitimately has no cost, explicitly save a zero rate on that Job or cancel it if it should be excluded, then rerun. Do not mark a real unpaid/unknown cost zero just to make margin appear.
- Compare a foreign-currency Job and/or Scoop: original amount divided by the displayed units-per-EUR rate equals its EUR amount. Supported mixed currencies no longer block the margin solely because their codes differ. Missing/stale/unsupported rates remain an explicit blocker.
- Change rows per page to 25/100/250, move between pages, reload, and compare full-result totals.
- Export **Excel workbook** from Projects and open it. Values such as 24.2 and 9.6 must be numeric amounts, names must retain accents, and the Details/Summary/Report information sheets must be readable. Grouped exports include a Groups sheet. Export covers all matching rows up to 10,000, not just the visible page. Raw CSV is optional; it cannot guarantee Excel's automatic cell typing.

## Client invoicing acceptance

Use designated test work for draft tests. Official issue consumes a real number; only issue an intended official invoice after verifying settings and tax/billing details.

1. Select two approved Scoops from different Projects of the same Client → Create draft. Confirm individual rows, source values, selected billing entity, currency and due date from the Client profile.
2. Change a row amount with a correction reason, add a manual row, remove another row, save, close and reopen. Confirm persisted amounts and total.
3. Use **Add Scoops by PO**, search the Project's client PO, select another Scoop, add it and save. Verify earlier notes/rows survive. Currency is fixed while rows exist; remove rows before changing it to avoid relabelling amounts.
4. Confirm reserved Scoops are absent from another new draft's queue. Cancel the test draft and confirm its reservations are released.
5. For an intended official invoice, verify the proposed/next number, tax basis, client terms, billing entity and issuer details, then Issue. Print/PDF must match the saved totals, recipient and issuer, with source POs. Issued rows are locked.
6. Record an actual received payment using its date/reference and invoice currency; check the balance. Recording a payment does not send money. Full payment sets Paid; duplicate or excess receipts are rejected. Do not record fake production receipts for testing.
7. QA can inspect and print; PM/client-relations can prepare drafts; official issue, settings and payment recording require admin.

## Executed local checks

- 061 Reports database: Scoop grain, exact unknown-Job diagnostics, provisional vs final profit, dated EUR conversion, missing rates, grouped/full totals, monetary sorting, pagination and FX write denial.
- Client invoice database on repository schema: cross-Project selection, PO queue search, terms/due date, duplicate reservations/rollback, wrong-client rejection, corrected/manual/deleted/re-added rows, revision conflicts, settings/source changes, role restrictions, numbering, issue snapshots, immutable facts, draft cancellation, payment guards and Project financial status.
- Migration reapplication and installation audit.
- Nine JavaScript/export/FX tests: typed numeric XLSX cells, Unicode, inert formula-like text, incomplete-margin blanks, CSV escaping, ECB parsing and authenticated feed storage.
- Chromium fixtures: Reports filters/grouping/paging/page-size persistence/XLSX/export cap/QA/error/mobile; Invoice selection/edit/save/add-by-PO/issue/print/payments/QA/mobile. Desktop/mobile screenshots inspected. Browser network calls use fixture RPCs; the database tests execute actual SQL separately.
- JavaScript syntax and whitespace checks.

Limitations: Microsoft Excel desktop and the deployed site are not exercised here. The actual exported workbook is reopened and checked with ExcelJS. Historical migrations 037/040 are missing from the repository; schema tests explicitly stub the unrelated 037 audit writer and replay through 038 plus the relevant feature migrations, not the entire historical database.

## Follow-up scope

Supplier invoicing, credit/annulment/replacement documents, automated invoice email, bank FX differences and separate Invoice Reports are not implemented in 061. Client invoice drafts and issued invoice/payment tracking are functional. Latest 250 invoices are listed per selected client. A Project is marked fully invoiced only when every active Scoop is covered; partial Scoop billing remains visible in the invoice workspace.
