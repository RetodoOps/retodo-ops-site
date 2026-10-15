# Update 065 — Standalone invoices and Bulgarian and Word downloads

This package adds invoice creation without a Project or Scoop and English/Bulgarian downloads in PDF and editable Word (.docx). It is based on main b21fa1bbf1be66eb0769c672759e147268711f23, build 064A, preserving the Sales signature and public enquiry work.

## Install

1. In Supabase SQL Editor, run the complete `tms/migrations/061_standalone_invoice_prerequisites.sql`.
2. Run `tms/audits/021_update_065_invoice_audit.sql`. All **15 results must say PASS**.
3. Upload all complete files from this ZIP to their matching repository-root paths and commit using your usual workflow. Keep the directory structure; do not replace the repository with only this package.
4. After your normal deployment, hard-refresh Client invoices. The badge should show **Update 065**.

No new environment variables, external converters or server functions are required. Installation changes no invoice amounts, statuses or payments. Migration 061 restores the previously prepared invoice revision/payment/deletion fixes if absent, and is safe to reapply. It assumes the existing invoice schema from 054/055/056. Do not rerun older migrations.

**Migration numbering:** Sales already uses migration 058 and migrations 059/060. The older, separately delivered Reports/Invoice Update 064 also had an invoice migration numbered 058; it is not on this main baseline. This package gives its invoice-only prerequisites the unique number **061** and leaves Sales and Reports implementations unchanged. Do not replace the Sales 058 file with the old invoice 058 file.

## Create an invoice without Scoops

Open **Client invoices → New invoice without Scoops**. Choose an existing client, currency (EUR by default), and invoice number. Select **Create invoice**, enter a description and amount, and add further manual rows as needed. Choose the client's billing entity, check the tax fields and save. The due date uses the payment terms saved in the Client profile.

You can issue this invoice without any Scoop. You can also add approved Scoops later through **Add Scoops by PO**. Existing role permissions apply: authorized staff prepare drafts and administrators issue, revise, record payments and delete invoices. Manual-only invoices do not change Project, Scoop or Job statuses.

## Download

Open a saved invoice and choose **Download language → English / Български**, then:

- **Print / PDF** opens the print dialog. Choose Save as PDF. Disable browser headers/footers if your browser adds the page URL.
- **Download Word** creates a genuine editable `.docx` file locally in your browser.

The choice translates invoice labels and formats dates and numbers. Names, addresses, service descriptions, notes and tax-basis text remain exactly as entered. Enter these in Bulgarian where a fully Bulgarian document is needed. Amounts, currency, invoice number and saved issuer/billing details are preserved. Drafts retain a clear draft notice in both languages. Unsaved changes must be saved before downloading.

Changes made in the downloaded Word file do not update the TMS invoice. Use the invoice editor to change the stored record and regenerate the document.

## Focused acceptance

1. Create a test invoice without selecting any Scoops. Save two manual rows, reopen it, and confirm the client, number, billing entity, amounts and due date.
2. Download Word in both languages and open it in Microsoft Word. Confirm the Bulgarian characters, decimal values, table, total and bank details. Compare the Bulgarian PDF with the same saved invoice.
3. If desired, add an approved Scoop to a separate manual draft and confirm the original manual rows remain.
4. On test records, check issue, official revision and full/partial payment. A manual-only invoice must leave all Scoops unchanged.

## Verification

- 32 isolated SQL workflow tests pass, including standalone create/issue/revise/pay/delete, later Scoop addition, existing billing/payment/revision safeguards and access control.
- Migration reapplication and all 15 audit checks pass.
- Chromium fixture tests pass: standalone dialog and rows, number/terms, English/Bulgarian Word downloads, Bulgarian print content, unsaved-download guard, established Scoop workflows, revisions, full/partial payments, deletion, QA and mobile.
- Real DOCX files rendered and visually inspected: English/Bulgarian one-page invoices and a 65-row Bulgarian invoice across five pages with repeated table headers. XML text and decimal preservation checked independently.
- JavaScript syntax and package integrity checked.

SQL tests use isolated PGlite and the existing explicit stub for the repository's missing historical 037 audit writer. Browser RPCs are fixtures. No production SQL, deployment, real invoice creation/payment/deletion, or desktop Microsoft Word acceptance is claimed. Nothing was pushed or merged by the assistant.

## Files

All files are complete replacements/additions, not patches. The package contains this guide, CURRENT_WORK.md, invoice HTML/JS/CSS, the shared invoice-document.js exporter, vendored DOCX 9.6.1 plus MIT license, build.json, migration 061, audit 021 and three task-specific tests. Sales, public website and Reports files are not included.
