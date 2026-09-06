# RetodoOps TMS — Update 038 manual upload

This package contains the complete pending UI/source set for Update 037 plus
the Update 038 corrections and database migration. Copy the files into the
existing repository while preserving the `tms/` paths.

## Required order

1. If Update 037 has not yet been applied, run
   `tms/migrations/034_internal_resources_scoop_deadlines_and_context_numbers.sql`
   in Supabase SQL Editor after migration 033.
2. Run
   `tms/migrations/035_job_language_flat_fee_po_label_and_deadline.sql`
   after migration 034.
3. Copy the package files to the repository.
4. Deploy the site and hard-refresh the browser with `Ctrl + Shift + R`.

## Included behavior

- Internal Resources are simplified employee records with Name, Position,
  Gender, ResourceNumber, Email and lifecycle Status.
- Internal positions are multi-select values: `Project Manager`, `QA` and
  `Project`.
- Inactive Internal Resources lose access and cannot receive new assignments;
  historical references remain unchanged.
- Project creation has no Project deadline or price. Scoop deadline date and
  time are mandatory, and Scoop financials own the price.
- Project Manager, QA and Project dropdowns use active Internal Resources.
- Project numbering uses the daily sequence format `YYMMDD-N_...`.
- New Supplier PO numbering uses the Project/Scoop/Service/Job context, for
  example `PO-260906-1_S01-TRA_J01`.
- Project Financials remains read-only and groups each Scoop once across its
  detailed CAT rows.
- The CAT payment grid has no zero-row visibility selector and displays the
  full rate-card breakdown as it did previously.
- Scoop status remains automatic from Jobs unless Manual status override is
  selected; `Delivered` Jobs produce `Ready for QA` automatically.
- A new manual Scoop financial line does not require a reason.
- The stale rate-card mismatch message is cleared after a successful rate-card
  load.
- Job Source and Target language fields are prefilled from the owning Scoop
  while remaining editable.
- When no approved matching Supplier rate card is available, a Resource can be
  assigned with a manually entered flat fee and currency. The assignment still
  uses the normal PO, version and email-audit workflow.
- PO display labels use only the PO number; the project/job name is not
  prepended to the PO title or version history label.
- Dashboard Scoop deadlines that have passed, including a deadline earlier on
  the current day, are shown in red.

## Deliberately excluded

`config.js` is not included. Keep the existing Supabase URL and anon key in
the repository's current `tms/config.js`.

## Manual smoke test

1. Open a Job under a Scoop and confirm Source and Target are prefilled from
   the Scoop; change either value and confirm it remains editable.
2. Select an eligible Resource with no matching approved rate card. Choose
   `Manual flat fee`, enter an amount and currency, and assign it. Confirm the
   Job receives a Fixed fee PO and the PO label is only its PO number plus
   version.
3. Open a CAT-based Job and confirm there is no `CAT rows` selector; all CAT
   bands are visible, including zero-quantity rows.
4. Open the Dashboard and confirm a past Scoop deadline is red.

