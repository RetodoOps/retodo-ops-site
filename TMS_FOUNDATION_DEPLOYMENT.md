# RetodoOps TMS — Operational Foundation Deployment

This checkpoint fixes the existing project editor schema, adds commercial
scope lines, introduces restrictive role-based database access, adds a
password-recovery flow, and installs the normalized operational core approved
during the module review.

## Before deployment

1. Confirm that `aleksandra.atanasoff@gmail.com` is the current Supabase TMS
   login. If it is not, replace that address in
   `tms/migrations/001_operational_foundation.sql` before running the migration.
2. Back up the Supabase database.
3. In Supabase Authentication URL Configuration, add this allowed redirect URL:
   `https://stately-pudding-c59ebb.netlify.app/reset-password.html`
4. Do not configure memoQ credentials yet. Migration 002 creates only the safe
   integration mapping layer; a later server-side connector will hold secrets.

## Apply in this order

1. Open Supabase SQL Editor.
2. Run `tms/migrations/001_operational_foundation.sql` once.
3. Confirm that it finishes successfully. A missing administrator account makes
   the transaction fail and roll back without changing access policies.
4. Run `tms/migrations/002_operational_core.sql` once.
5. Confirm that existing projects remain present. Legacy statuses are migrated:
   `QA Ready` → `Ready for QA`, `QA Issues` → `Waiting`, `PM Ready`/`Delivery`
   → `Ready to Deliver`, and `Completed` → `Delivered to Client`.
6. Run `tms/migrations/003_resources_module.sql` once.
7. Run `tms/migrations/004_jobs_and_supplier_pos.sql` once.
8. Run `tms/migrations/005_project_financial_backfill.sql` once.
9. Run `tms/migrations/006_internal_staff_assignments.sql` once.
10. Run `tms/migrations/007_specializations_and_resource_rates.sql` once.
11. Run `tms/migrations/008_resource_reference_data_and_cat_rates.sql` once.
12. Run `tms/migrations/009_project_financials_and_cat_grid.sql` once.
13. Run `tms/migrations/010_unified_resource_status_and_tests.sql` once.
14. Run `tms/migrations/011_client_rate_cards_and_simplified_project_grid.sql` once.
15. Run `tms/migrations/012_resource_selection_and_editable_capabilities.sql` once.
16. Run `tms/migrations/013_multilanguage_rates_editable_work_and_po_versions.sql` once.
17. Run `tms/migrations/014_cat_quantities_assignment_and_quick_navigation.sql` once.
18. Run `tms/migrations/015_direct_po_assignment_and_financial_grid_fix.sql` once.
19. Commit/push the updated repository files so Netlify deploys them.

## Verification

1. Sign in with the administrator account.
2. Open an existing project, add a scope line, save, refresh, and confirm it is
   still present.
3. Sign out and use **Forgot password?**. Confirm that the email arrives and the
   link opens the new-password page.
4. Sign in with the new password and confirm the dashboard loads.
5. In the SQL Editor, confirm that `integration_connections`,
   `integration_links`, and `integration_events` exist. Do not insert API keys
   or passwords into any of these tables.
6. Open **Clients**, create a test Client, then add an Account, Contact, Billing
   Entity and Client rate-card item. Refresh each tab and confirm that the data
   persists. Confirm only one Billing Entity can be marked as default.
7. Confirm the Dashboard uses the new production statuses and that an existing
   Project can still be opened and saved.
8. Create a test Quote with two target languages and accept it. Confirm exactly
   two linked Projects are created and repeating the action creates no
   duplicates.
9. Create one direct Project without a Client reference and confirm its name
   contains `NOREF`. Create another with the same date/Client/target/reference
   and confirm the `_02` suffix is added.
10. Add a Client reference to the `NOREF` Project and confirm that it becomes
    searchable and visible while the Project name stays unchanged. Confirm the
    change appears in the audit history.
11. Put a Project into `Waiting` without a reason/follow-up and confirm it is
    rejected. Add both values and confirm it saves.
12. Create an unassigned Job. Confirm it opens in the separate Job workspace
    and does not require a Resource at creation.
13. Select an Assignable Resource, an Approved matching Supplier rate card and
    CAT quantities, then choose **Assign Resource & Issue PO**. Confirm the Job
    moves to Assigned, the Project moves from Assign to Ongoing, the supplier
    amount rolls into Project expense/margin and Supplier PO version 1 is
    immediately Issued with a `PO-YYYY-NNNN` number. Confirm an outbound email
    queue record is created; no Resource acceptance step should appear.
14. Select another Resource and confirm a reassignment reason is required. On
    confirmation, verify the old PO becomes Cancelled with its history intact,
    the new Resource is assigned and receives a newly numbered Issued PO.
15. Open the issued PO, create an Administrator revision with a mandatory
    reason, including a discount or surcharge, and confirm version 1 remains
    locked while version 2 and its recalculated totals are retained.
16. Confirm Client/Account identity is absent from the PO and assignment snapshot by default.
    Confirm only the Administrator may enable disclosure.
17. Open **External Resources**, combine source, target and specialization
    filters, and confirm pagination reports the full result count.
18. Open a Resource and add a language pair, service, specialization, rate,
    education and availability period. Assign and pass a General test; confirm
    the Resource becomes Assignable. Record a failed Domain test and confirm
    only that specialization becomes Not approved. Record a failed General test
    and confirm the Resource becomes Do not use.
19. Confirm Aleksandra appears as an Internal Resource in the Project Manager,
    QA Specialist and Project Coordinator selectors. Change an Internal
    Resource to `Inactive`; confirm existing Project links remain visible and
    the Resource disappears from selectors for new Projects.
20. In Project creation, focus a language selector and press `S`; confirm
    Swedish is selected. Enter deadline date and time directly from the
    keyboard and confirm the saved deadline is correct.
21. Create or edit an Account and confirm at least one specialization is
    required. Create a Project for that Account and confirm those
    specializations are inherited and locked. Create a Project with Account
    `Non-defined` and confirm its specializations can be selected freely.
22. Create a Job and confirm its specialization list contains only the
    specializations selected on the Project. Confirm the Job cannot be saved
    without a specialization or moved to In Progress before a Resource and PO
    are assigned.
23. In Job Overview, select an Active Assignable, Proven or Preferred Resource.
    Confirm capability and qualification warnings do not disable selection. Confirm Supplier
    rate is a dropdown containing only current approved matching rows from the
    Resource profile. Assign the Resource and issue its PO, then confirm the
    exact rate row is linked while its amount/currency snapshot is retained on
    the Job and Supplier PO.
24. Add an Administrator-only private note and confirm it cannot be read by a
    non-Administrator. Generate the blind CV and confirm that both DOCX and PDF
    exclude the Resource's name, email, phone, LinkedIn URL and rates.
25. Create a Resource and enter its Legal / personal name. Confirm Initials are
    filled automatically. Confirm Nationality and Country of residence provide
    searchable shared lists.
26. Add a Resource language pair and confirm both Source and Target use the
    same canonical language list as Projects and Quotes. Create a Job with that
    pair and confirm the Resource can be found by Suggest appropriate Resource.
27. Add a Resource rate card. Confirm Source and Target are restricted to that
    Resource's recorded language pairs, enter one base price and CAT discount
    percentages, and confirm the calculated CAT-band rates are shown beneath
    the base row after saving. Confirm Valid from / Valid to are not requested.
28. Select the approved base rate in Job Overview and confirm all Supplier CAT
    bands appear underneath. Enter a separate quantity in each used band and
    confirm its amount and the bold Supplier total recalculate. Assign and issue
    the PO and confirm these bands become its lines with rate provenance retained.
29. In a Client profile, add one base rate and CAT discount percentages. Confirm
    the calculated CAT rates appear beneath the base row and no validity dates
    are requested. Open a Project and confirm the former Commercial tab is named
    Financials. Confirm Service and Specialization are inherited rather than
    repeated in the CAT grid. Load a Client rate card and confirm all seven
    standard CAT rows appear with
    quantity 0. Enter quantities and confirm line amounts, Client price and
    margin recalculate. Delete one unused CAT row and confirm the total remains
    correct.
30. Load a blank CAT grid and confirm the same seven rows appear with quantity
    0 and unit price 0. Confirm a linked rate-card row keeps its rate source and
    cannot have its snapshot price silently edited.
31. Create a Project and confirm Client contact is filtered to Client-wide or
    selected-Account contacts. Enter Place of delivery during creation and
    confirm it is present in Project General after saving.
32. Set an External Resource to Active + Assignable, Proven or Preferred and
    confirm it becomes selectable in Job Overview regardless of its capability,
    qualification or compliance warnings. Confirm an approved matching Supplier
    rate card is still required to assign the Resource and issue the PO.
33. Edit a Resource Specialization qualification and a Supplier rate card, then
    refresh and confirm both changes persist. Remove a language pair and a
    Service and confirm their affected current rate cards disappear while old
    Job, assignment and Supplier PO snapshots remain unchanged.
34. Add English (UK) → Swedish and English (US) → Swedish to one Resource.
    Create one Approved Supplier rate card with both Source languages and
    Swedish as Target. Confirm both corresponding Jobs find the same card.
    Edit Project and Job operational fields directly and save them. With a
    PO-facing Job field, save, and confirm the next PO version appears with the
    earlier version retained.
35. In Project Financials, type quantities directly into several CAT rows
    without opening the financial-line modal. Confirm line amounts update while
    typing, the bold Project CAT total remains at the bottom, and Save persists
    every changed quantity.
36. Use the top quick search to open a Project and a Job. Focus it again and
    confirm both appear under Recently visited; search by number/name and test
    `/`. Confirm labels, fields, focus outlines, tables and
    totals remain clearly readable on desktop and narrow screens.
37. Edit a Project CAT quantity and Save. Confirm no `record "new" has no field
    "updated_at"` error appears, the line Amount, bottom CAT total and top Client
    price update, and the value persists after refresh. Select a non-matching
    Client rate card and confirm the mismatch is reported instead of silently
    creating zero-price rows.

The `client_relations` role may be assigned to Eli after the Client and Account
screens are deployed and tested. It permits operational work and financial
visibility, while Administrator-only triggers retain invoice issue/annulment,
payment, rate approval, assignment approval and blacklist controls.
