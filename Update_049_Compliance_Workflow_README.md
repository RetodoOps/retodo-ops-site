# Retodo Ops TMS — Update 049: prompted Compliance workflow

This release extends the existing Compliance architecture; it does not create a
parallel qualification module. It contains complete replacement files at their
repository paths, one forward-only migration, one read-only audit and regression
tests. It contains no credentials and does not modify migration 047 or any other
previously applied migration.

## Deployment order

1. Apply `tms/migrations/048_compliance_phase_tests_and_job_qualifications.sql`
   as a whole after successful Update 048 / migration 047.
2. Run `tms/audits/010_update_049_compliance_workflow_audit.sql`; every returned
   row must be `PASS`.
3. Commit the complete files from this release at their included repository
   paths and publish through the existing Netlify workflow.
4. Hard-refresh the TMS and Resource Portal before acceptance testing.

The existing Supabase, private Cloudflare R2 and Gmail environment variables are
reused. Update 049 adds no environment variable.

## Locked workflow implemented

- Test workflow status and result are separate. A completed current TMS test has
  an explicit `Pass` or `Fail` result.
- **Tested before TMS launch** always represents `Completed / Pass`. Both
  `assigned_at` and `completed_at` are `NULL`; no false legacy test date is
  requested, displayed or generated.
- The Compliance phase can be requested internally only after a passed General
  test, including a pre-TMS General pass. It is not automatic.
- The external Resource receives the existing Gmail notification and then sees
  **My Compliance** in the Resource Portal. They can save progress, upload their
  diploma/certificate and CV to private R2, and submit for internal review.
- The prompted phase does not gate Job offers or assignment. A Resource may work
  before Compliance is submitted or completed.
- Submitted records are read-only in the Resource Portal. Internal operations
  can confirm evidence, request data-derived changes, or complete the review.
- Education uses controlled dropdowns for highest relevant degree, degree type
  and field of study (including `Other`), a country dropdown, free-text
  institution and graduation **year only**. Existing unclassified legacy text
  remains visible and is never reclassified automatically.
- Translation, Revision and MTPE start months remain the source of truth. Live
  durations and Blind CV values continue to be calculated from those dates.
- ISO 17100/18587 eligibility remains internal-only, system-generated and
  non-editable. It is absent from Resource Portal SQL projections and UI files.
- Account qualifications are derived from Approved TMS Jobs and link to the
  supporting Job records. They show Job quantities grouped by unit (for example
  words or hours); fixed-fee work is labelled `Flat rate` and shows only its
  quantity. Supplier rates, amounts, currencies and EUR values are not selected
  or returned.

## Schema changes

### `public.resource_tests`

- `test_result TEXT` — `Pass` / `Fail`, separate from workflow status.
- `tested_before_tms BOOLEAN NOT NULL DEFAULT FALSE`.
- `assigned_at` becomes nullable solely so a pre-TMS pass can have no fabricated
  date.
- Workflow constraints and the existing result trigger are replaced in this
  forward migration. Existing `Passed` / `Failed` rows migrate to
  `Completed` + `Pass` / `Fail` while retaining their recorded timestamps.

### `public.resource_education`

- `degree_level TEXT`.
- `field_of_study_category TEXT`.
- `field_of_study_other TEXT`.
- Controlled vocabulary constraints are added. Existing rows remain nullable in
  these fields and continue to load without fabricated classifications.

### `public.resources`

- `compliance_phase_status` and requested/submitted/change/completed timestamps.
- Internal actor references for request/change/completion.
- Change reason, last Resource edit timestamp, notification timestamp and safe
  notification error state.

No calculated experience or editable ISO column is added.

## Access-control boundary

- Workflow mutations and private R2 authorization dispatchers remain
  service-role-only and re-resolve the verified actor's stored TMS role.
- Only Administrator, Project Manager and Client Relations can request or
  complete the phase or confirm evidence. QA retains internal read-only
  visibility, including the system-generated ISO results and explanations.
- External Resources use narrow own-resource RPCs. They cannot select another
  Resource's Compliance data, verify evidence, change ISO outcomes, or access a
  different Resource's file.
- Private R2 object identity is still stored in protected `file_records`; every
  Resource view/download remains logged.

## Verification completed

- `node --test tests/*.test.js`: **75/75 PASS**.
- `node tests/update-049-compliance-workflow-db.mjs`: **15/15 PASS**.
- Existing Update 044–048 isolated database suites: **all PASS** (51 checks).
- Migration 048 was applied twice to the isolated PostgreSQL fixture to verify
  idempotency; audit 010 returned only `PASS` rows.
- JavaScript syntax checks passed for all changed browser and Netlify files.

The source snapshot's older standalone `resource-onboarding-db.mjs` references
`tms/migrations/040_resource_onboarding.sql`, which is not present in the source
archive supplied for this work. That unrelated legacy test cannot start from
this snapshot; Update 049 does not modify it. No live Supabase, R2, Gmail or
production deployment was used during isolated verification.

## Acceptance test sequence

1. Record a pre-TMS General pass and confirm the table shows `Pre-TMS launch` and
   `No test date recorded` with result `Pass`.
2. Open **Compliance & Qualifications** internally and select **Request
   Compliance**.
3. Sign in as that External Resource; confirm **My Compliance** is visible, ISO
   is absent, and assigned Jobs still open.
4. Save education/year and different Translation/Revision/MTPE start months;
   upload diploma/certificate and CV; submit.
5. Internally open and confirm both evidence types, verify the read-only ISO
   explanations, then complete the phase.
6. Approve Jobs with word, hour and flat-rate units. Confirm Account
   qualifications show only those quantities and supporting Job links—never a
   supplier price, currency or EUR value.
