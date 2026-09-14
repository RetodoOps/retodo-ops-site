# Retodo Ops TMS — Update 051 Static Asset Recovery

## Why this release exists

Update 050 database migration and audit were completed, but the live acceptance
test reproduced the exact behavior of the older Update 048 frontend:

- every Job save revalidated a historical Resource deadline;
- every Job save resent deadline and Supplier PO fields;
- the Dashboard did not contain the new linked Job / External Resource output.

Update 051 republishes the complete Update 050 runtime files with an explicit
build number and strengthens the status-only Job save regression.

## Deployment order

1. Publish every file in this package to the existing GitHub `main` branch,
   preserving the included `tms/` and `netlify/` paths.
2. Wait for the resulting Netlify production deploy to complete.
3. Open `/build.json` on the TMS domain and confirm `"build": "051"`.
4. Run the two acceptance tests below.

There is no migration in Update 051. Migration 049 and Audit 011 were already
completed and must not be rerun for this frontend recovery.

No new environment variables are required.

## Code changes relative to Update 050

### Job status-only save

- `tms/job.js` stores the exact displayed date/time field snapshot after loading.
- Saving compares the current fields to that snapshot, without reparsing the
  database timestamp to decide whether the user changed it.
- An unchanged historical deadline is neither validated nor sent in the RPC
  payload.
- A genuine deadline edit is still validated and remains a PO-facing change.
- Status-only `Delivered → Approved` sends no rate, CAT, quantity, language,
  specialization, or deadline fields and therefore cannot request a PO revision.

### Dashboard Resource

- `tms/dashboard.js` has an independently testable Job→Resource mapper.
- The mapper preserves the actual `project_jobs.resource_id` and adds the
  Resource number/name for the linked Job.
- Dashboard rendering, search, sort, and CSV continue to use the same mapped
  Resource collection.

### Deployment correlation

- Job, Dashboard, internal Resource, and Resource Portal pages carry build 051
  metadata and request their updated scripts/styles with `?v=051`.
- `tms/build.json` provides a public, non-sensitive build marker so the deployed
  frontend version can be verified without inferring it from behavior.
- Existing Netlify no-cache headers are preserved.

## Production data note

The test created `PO-2026-0007 · V3` only after the historical deadline had to be
changed to proceed. Update 051 does not delete, overwrite, or silently repair
that immutable PO history. Any later data correction must be an explicit user
decision after the frontend behavior is verified.

## Acceptance tests

### Test 1 — status-only approval

1. Hard-refresh the Job page.
2. Use a Delivered Job whose unchanged Resource deadline is in the past.
3. Record the current Supplier PO version.
4. Change only Status to `Approved` and save.

Expected:

- no past-deadline message;
- Job becomes `Approved`;
- Supplier PO version does not change.

### Test 2 — Dashboard Resource

1. Hard-refresh Dashboard.
2. Open the relevant Scoop row.

Expected:

- External Resource column lists each linked Job;
- the assigned Resource number/name appears under its Job;
- Job and Resource links open the correct records.

## Files included

- Updated build/cache files:
  - `tms/job.js`
  - `tms/job.html`
  - `tms/dashboard.js`
  - `tms/dashboard.html`
  - `tms/resource.html`
  - `tms/resource-dashboard.html`
  - `tms/build.json`
- Complete Update 050 runtime dependencies:
  - `tms/resource.js`
  - `tms/resource-dashboard.js`
  - `tms/style.css`
  - `tms/agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx`
  - `Logo-440x140.png`
  - `netlify/functions/resource-compliance.js`
  - `netlify/functions/resource-compliance-files.js`
  - `netlify/functions/_shared/gmail.js`
- Repository/audit continuity:
  - migration 049 and audit 011 (included for source completeness; do not rerun)
  - Update 050 and 051 regression tests
  - Update 050 README and this README

## Short handoff

- Order: GitHub/Netlify publish → verify `/build.json` = 051 → acceptance tests
- New environment variables: no
- Database migration/audit: none for Update 051
- Unresolved issues: production verification of the two failed tests
- Next acceptance test: status-only `Delivered → Approved`
