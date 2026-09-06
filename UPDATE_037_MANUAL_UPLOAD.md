# RetodoOps TMS — Update 037 manual upload

This package contains the current UI/source files for the pending update and
the database migration. Copy the files into the existing repository while
preserving the `tms/` paths.

## Required order

1. Run `tms/migrations/034_internal_resources_scoop_deadlines_and_context_numbers.sql`
   in Supabase SQL Editor after migration 033.
2. Copy the files in this package to the repository.
3. Deploy the site and hard-refresh the browser with `Ctrl + Shift + R`.

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
- CAT payment rows with quantity `0` are hidden initially and can be revealed.
- Scoop status remains automatic from Jobs unless Manual status override is
  selected; `Delivered` Jobs produce `Ready for QA` automatically.
- A new manual Scoop financial line does not require a reason.
- The stale rate-card mismatch message is cleared after a successful rate-card
  load.

## Deliberately excluded

`config.js` is not included. Keep the existing Supabase URL and anon key in
the repository's current `tms/config.js`.

The migration is included both in this package and as a separate downloadable
file outside the ZIP.
