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
12. Commit/push the updated repository files so Netlify deploys them.

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
   Entity and price-card item. Refresh each tab and confirm that the data
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
13. Create a Draft Job Offer to an approved Resource, mark it sent and record
    acceptance. Confirm the Resource is assigned, the Job moves to In Progress,
    the supplier amount rolls into Project expense/margin and a Draft Supplier
    PO with a `PO-YYYY-NNNN` number is created.
14. Confirm a second active offer is blocked. Decline or withdraw the first
    offer and confirm a new candidate may then be selected. Confirm an
    ineligible Resource cannot receive an offer without an Administrator
    override and mandatory reason.
15. Edit the Draft PO, including a discount or surcharge, and confirm totals
    recalculate. Issue it as Administrator, confirm version 1 is locked, then
    create a revision with a mandatory reason and confirm version 2 is retained.
16. Confirm Client/Account identity is absent from the PO and offer by default.
    Confirm only the Administrator may enable disclosure.
17. Open **External Resources**, combine source, target and specialization
    filters, and confirm pagination reports the full result count.
18. Open a Resource, add an approved language pair, service, specialization,
    rate, education and availability period. Confirm a non-approved Resource
    still cannot be assigned.
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
    without a specialization or moved to In Progress before a Resource accepts
    an Offer.
23. In Job Overview, select an eligible matching Resource. Confirm Supplier
    rate is a dropdown containing only current approved matching rows from the
    Resource profile. Create the Draft Offer, mark it Sent and Accepted, and
    confirm the exact rate row is linked while its amount/currency snapshot is
    retained on the Job and Supplier PO.
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
28. Select the approved base rate in Job Overview, accept the Offer and open
    the Supplier PO. Confirm its production line shows `Resource base rate` as
    the rate source, while additional manual or adjustment lines are labelled
    separately.

The `client_relations` role may be assigned to Eli after the Client and Account
screens are deployed and tested. It permits operational work and financial
visibility, while Administrator-only triggers retain invoice issue/annulment,
payment, rate approval, assignment approval and blacklist controls.
