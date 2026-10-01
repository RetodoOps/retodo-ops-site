# Update 062 — Reports selection, shared search and invoice revisions

Baseline: main 4e7a7dc, build 061. This package contains complete changed files. Upload/commit remains with the user; no assistant push, deployment or production migration.

## Install

1. Run `tms/migrations/056_reports_selection_invoice_revisions_search.sql` in Supabase SQL Editor. It requires installed Update 061 migrations 054/055 and existing operational schema, including Update 052 cancellation support. Do not rerun older migrations.
2. Run `tms/audits/016_update_062_workflow_audit.sql`; every result should be PASS.
3. Upload the package's `tms/`, `tests/` and `docs/` contents to matching repository-root folders and commit. Preserve the folder structure and include CURRENT_WORK.md. These are complete files, not fragments to paste into existing files.
4. Refresh the application; Reports and Client Invoice show Update 062. No new environment variables or Netlify functions are needed.

Migration 056 derives Invoiced/Paid for Scoops already on existing issued/paid invoices, so previous 061 invoices are covered. This is an intentional reconciliation of financial status; source prices, operational approval, amounts and payments are preserved. Existing official numbers are registered to prevent their reuse after a revision.

## What changed

### Reports

Projects and Margin have checkboxes per Scoop; Jobs has a checkbox per Job. A toolbar above the table provides Select page, Clear selection, status choice and Change selected status. Selection persists across pages and clears when filters/sort/group change. Only selected IDs are changed, atomically, with a maximum of 500 per operation. A missing record fails the whole batch. Admin, PM and client-relations can perform operations; QA remains read-only.

Invoiced/Paid are derived financial states, not manual bulk choices. An already invoiced/paid Scoop retains operational approval; changing invoice contents is done through its invoice. Existing Job-level validation and status triggers still run for bulk Job updates.

### Search and navigation

The shared search appears on existing company modules: Dashboard, Clients/Client, Accounts, Resources/Resource, Projects, Jobs, Quotes/Quote, Settings, Reports and Invoices. Search covers Scoops, Projects, Jobs, Clients, Resources and client Invoices. It queries matching records server-side; the old latest-250-only index is removed. Results are capped at 30 matches; narrow the query if needed. Exact matches are ranked first, with Scoops ahead of connected Jobs. At least two characters are required.

Searching `260905_TEST_NB_NOREF-S02` returns the Scoop itself, with its financial status, and links directly to that Scoop inside the Project. Dashboard table search also switches to All so the active deadline/status tab does not hide a matching Scoop. Search fields in individual modules remain available for filtering that module's list.

The Invoice sidebar group is added wherever a company module was missing it, including Clients, Client details and Project details. External resource pages retain their separate access/navigation.

### Invoices

Create invoice now prompts for a number immediately, suggesting the configured next number. The existing ten-digit format is preserved. Cancelling the prompt leaves the selection intact. A draft does not consume the official number; uniqueness is checked at issue. A changed number remains reserved to its original invoice in the number registry, so another invoice cannot reuse it.

Admin can edit issued, partially paid, paid, overdue or disputed invoices using the existing rows and header fields, then Save revision. A reason is required. Every revision keeps a full previous header/line/payment snapshot plus actor/time/reason. History shows the reason and previous/new total. Ordinary users still cannot write directly to finance tables; PM prepares drafts but does not revise official invoices.

Editing keeps the Client and issued currency fixed, preserves recorded payments and the original issuer/issue metadata, prevents a total below receipts already recorded, checks source eligibility, prevents double billing and checks revision conflicts. Rows can be corrected, removed or added, including further eligible Scoops found by client PO. Removing a Scoop releases it; payment status is recalculated against the revised total. Unsaved edits must be saved/discarded before recording a payment. Original snapshots remain in the revision archive; this update does not add credit-note/annulment workflows.

Invoice print/PDF now explicitly labels **Bank:** before the saved bank name. It does not invent a bank name if none was configured.

### Scoop status

On official issue, every linked Scoop displays **Invoiced** in Dashboard, the Project's Scoop cards, shared search and Reports/exports. On full payment it displays **Paid**. Partial payment keeps **Invoiced**. These labels are derived from the invoice and protected from manual financial-status edits. Operational status remains stored separately, preserving approval and Job workflow. Dashboard includes Invoiced and Paid tabs; Reports can filter both statuses.

## Acceptance checks

- Reports Projects: select two uninvoiced Scoops, change an operational status, reload and verify only those Scoops changed. Repeat for two Jobs. Check QA sees no bulk toolbar.
- Select on one page and another page; check selection count. Change filters and confirm selection clears.
- In Clients and inside a Project, expand Invoice and follow Client Invoice.
- Search the exact Scoop number in Clients, Project and Dashboard shared search. Confirm a Scoop result, its financial label, and a link opening its Scoop card.
- Select approved Scoops → Create invoice. Check the number prompt; cancel once and confirm selection remains. Then enter a number, save the draft and reopen it.
- For a real invoice intended for issue, check its Scoops show Invoiced after issue. Refresh another open module to retrieve the changed state. After a real full receipt is recorded, check Paid. Do not create fake production payments for testing.
- Open an existing official invoice as admin, edit an intended correction, Save revision with a reason, reopen and check the corrected document, history and unchanged receipts. PM/QA should not be able to make official revisions.
- Print/PDF must show the Bank label and current saved invoice values.

## Executed verification

- Actual PostgreSQL-compatible tests on repository schema: 23 invoice/workflow checks, including bulk Scoop/Job updates, exact Scoop search, derived statuses, official revisions, retained snapshots/receipts, allocation release/duplicate prevention, total-vs-payment guards, stale revisions, number retention and role restrictions.
- Migration 056 installation/reapplication, prior invoice regressions, and installation audit 016.
- Chromium fixtures: Reports selection and bulk RPC payload, filters/paging/export/QA/mobile; invoice-number prompt, issued editing/reason, print Bank label, receipts and read-only roles; shared search and missing Invoice navigation in Clients, Client and Project.
- JavaScript syntax and diff whitespace checks; search/navigation screenshot inspected.

Database tests use the available schema through 038 (the missing 037 audit writer is explicitly stubbed), then relevant 050/053/054/055/056 migrations. Historical 037/040 remain missing from the repository; no full historical replay or production acceptance is claimed. Browser RPCs use fixtures; database behavior is tested separately with actual SQL. Supplier invoicing remains follow-up scope.
