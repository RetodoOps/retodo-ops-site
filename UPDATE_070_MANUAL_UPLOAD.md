# Update 070 — Invoice report, PDF downloads and tax-treatment dropdown

Baseline: main `121731e`, containing the complete Update 069 source. This ZIP contains complete changed files. It preserves Sales and the manual-invoice draft repair.

## Install

1. Prerequisite: Update 069, including invoice migrations `065_invoice_reports.sql` and `066_invoice_manual_draft_fix.sql`. If those SQL steps were skipped, finish them using the Update 069 instructions first.
2. In Supabase SQL Editor, run `tms/migrations/067_invoice_report_downloads.sql` from this ZIP.
3. Run `tms/audits/026_update_070_invoice_download_audit.sql`: expect **6 PASS** rows. If a check fails, stop and share the result.
4. Upload all ZIP files at the repository root, preserving folders, and commit. Do not delete unrelated files.
5. After deployment, refresh Invoice and Reports with Ctrl+F5. Both show **Update 070**.

Migration 067 is read-only report functionality; it does not modify invoices, payments, tax rates or numbering. It can safely be reapplied. Do not replay previously installed migrations.

## Invoice list

Columns: selection, Number (opens invoice), Type, Client (opens client profile), Date, Payment status, Amount/currency and Download/payment actions.

- Paid: green. Unpaid: red. Partially paid: yellow. Payment labels derive from recorded receipts and outstanding balance.
- Draft, Cancelled and Annulled remain neutral; they do not appear as unpaid invoices.
- Search & filters and Totals by currency are expandable. Payment-status filtering is available alongside existing filters and sorting.
- Admins can still record full or partial receipts from the list. Existing access and duplicate-payment protections remain unchanged.
- Excel/CSV retains the earlier finance columns and adds Type, Payment status and a Client link.

**Type currently shows Invoice.** The existing application has no proforma creation or numbering workflow; a draft is not labelled as a proforma. This update does not add proforma issuance or conversion.

## PDF downloads

Choose English or Български in the toolbar. Each row's **Download PDF** saves an actual PDF without a print dialog. The same direct download is now available inside the invoice editor. PDF pages have no browser date/time, URL, running title or page-number header/footer. Issued documents use saved issuer/billing snapshots and invoice data. Drafts are visibly marked and use current configured party details. PDFs contain selectable text and embedded Cyrillic fonts; long item lists continue across pages.

Select invoices using their checkboxes, then choose **Download selected PDFs (ZIP)**. The ZIP contains one PDF per invoice, up to **100 selected invoices** per download. The header checkbox selects only the displayed page. Selection carries across pages and sorting; changing applied filters clears it. Clear selection removes all selected invoices.

Bulgarian download requires the invoice's optional BG version to be enabled and its required Bulgarian issuer data present. For issued invoices, correct saved data through the existing reasoned revision workflow. Download never silently changes language. If any selected invoice was deleted, is inaccessible or cannot produce the requested language, no partial ZIP is downloaded; the error identifies the invoice and selection is retained for correction/retry.

Files are generated in the browser using bundled fonts/libraries. No invoice data is sent to an external PDF service. Downloading does not issue or revise an invoice.

## Tax treatment / basis

The creation/editor field is now a dropdown with these supplied options:

- чл.113 ал.9 от ЗДДС - лицето не е регистрирано по ЗДДС
- чл.86, ал.3 и чл.21 от ЗДДС
- чл.82, ал. 2 от ЗДДС - обратно начисляване
- чл.21 от ЗДДС - услугата е извън територията на България
- чл.21 ал.2 от ЗДДС

There is also an empty choice and **Other / existing custom basis**. Old custom text remains editable and is preserved on save. Choose the applicable basis explicitly; selecting an option does not change the VAT rate. The selected text is saved in the existing tax-note field and appears in downloads. Existing issued records are not changed automatically.

## Verification

43 SQL workflow checks and invoice audits pass, including the new 6-check installation audit and migration reapplication. Browser checks cover tax options/custom text, links, status colours, payment filtering, PDF/ZIP, selection across pages, download failures, existing payment safeguards and operational report regressions. Real EN/BG PDFs were rendered and checked; a four-page test retains all 40 rows and Cyrillic text.

Tests use isolated PGlite with the documented missing-037 audit-writer stub and browser fixture RPCs. Production installation remains your step.

## Invoice editor cleanup and numbering

- Tax event date is removed from creation/editing, PDF and Word output, including downloads of existing invoices. Historical snapshots are preserved for audit; no production data is erased.
- The highlighted explanatory captions and duplicate status/language captions are removed. Action results are concise.
- New invoice, Save, Issue, PDF and Word buttons have bold text and a solid purple fill. Add-row actions are visibly accented.
- **Invoice number** is the first field in the editor. Change it and save the draft, or use **Save revision** for an issued invoice. Existing administrator/reason, duplicate-number and revision-history protections remain. The changed number appears in downloads.

## Client creation

Country code is removed from the Add client form and is not sent on creation. Existing country data and billing-entity records are preserved. No database migration is needed for this change.

The supplied screenshot's message was caused by the already-used **Client code MIRO**, not the country code. Client codes remain unique because they identify clients and form part of project naming. Duplicate-code feedback now names the conflicting code/client; choose a different available code to create the new client.

Additional checks passed: direct PDF from the invoice editor; no tax-event date in EN/BG Word/PDF; corrected issued number saved through the real revision RPC with receipts/history retained and duplicate numbers rejected; bold filled button styles; client creation without country code and clearer duplicate-code handling.

## Complete files in this ZIP

- `UPDATE_070_MANUAL_UPLOAD.md`
- `docs/context/CURRENT_WORK.md`
- `tests/update-070-clients-browser.cjs`
- `tests/update-070-invoices-browser.cjs`
- `tests/update-070-invoices-db.mjs`
- `tests/update-070-report-browser.cjs`
- `tms/audits/026_update_070_invoice_download_audit.sql`
- `tms/build.json`
- `tms/clients.html`
- `tms/clients.js`
- `tms/invoice-document.js`
- `tms/invoice-pdf.js`
- `tms/invoice-report-export.js`
- `tms/invoice-report.css`
- `tms/invoice-report.js`
- `tms/invoice.css`
- `tms/invoice.html`
- `tms/invoice.js`
- `tms/migrations/067_invoice_report_downloads.sql`
- `tms/reports.html`
- `tms/vendor/INVOICE_PDF_LICENSES.md`
- `tms/vendor/JSZip-LICENSE.txt`
- `tms/vendor/fonts/DejaVu-LICENSE.txt`
- `tms/vendor/fonts/DejaVuSans-Bold.ttf`
- `tms/vendor/fonts/DejaVuSans.ttf`
- `tms/vendor/jspdf-3.0.2.umd.min.js`
- `tms/vendor/jszip-3.10.1.min.js`
