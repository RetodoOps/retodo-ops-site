# Retodo Ops TMS — Update 048: Compliance evidence and ISO eligibility

This release contains complete replacement files at their existing repository paths,
one forward-only migration, an internal read-only audit, and regression tests. It
does not include credentials or change previously applied migrations.

## Deployment order

1. Apply `tms/migrations/047_compliance_evidence_iso_eligibility.sql` as a whole
   to the existing TMS Supabase database, after migrations 036–046.
2. Run `tms/audits/009_update_048_compliance_iso_audit.sql`; all rows must be PASS.
3. Commit the files at the paths included in this archive to the GitHub repository
   and let the existing Netlify deployment publish them. Existing private R2
   configuration is reused; no new secrets are contained in this release.
4. Verify a sample external Resource in the internal Compliance tab: record a
   highest relevant degree, professional start months, upload a diploma and a CV,
   inspect each file and select **Confirm evidence**. ISO decisions and Blind CV
   durations then reflect the recorded evidence without editable ISO fields.

This archive is not a snapshot of a live deployment and has not been applied to
production by its creation. The older standalone onboarding database test refers
to `040_resource_onboarding.sql`, which is absent from the provided source
snapshot; it is not included or modified here.

## Data contract

- Three DATE columns on `resources` retain the first day of each professional
  start month. Experience is calculated at read time against the current month;
  there are no editable duration columns.
- `resource_education` adds degree type, country, graduation date and the
  highest-relevant flag. Existing `degree`, `field_of_study`, `institution`,
  and year-only `end_year` remain in use. A year-only legacy record stays
  year-only when edited; an unknown month is never replaced with January.
- `resource_documents.education_id` binds a diploma/certificate file to its
  education record. Private R2 evidence uses existing `file_records` and
  `file_access_logs`; size and SHA-256 are checked before the file can be reviewed.
  A physically uploaded but unreviewed file never qualifies as ISO evidence.
- ISO decisions are internal-only, read-only SQL projections. A recorded and
  reviewed translation/language degree, another university degree plus at
  least 24 documented months, or an explicitly recorded and reviewed
  no-university-degree route plus at least 60 documented months are the
  translation routes. Each requires a separately documented translation start
  month and reviewed CV. The reviser route also needs documented revision
  experience. The post-editor route can use documented translation or MTPE
  experience and the relevant 24/60-month education alternative, but always
  requires a documented MTPE start month. Incomplete
  evidence stays Not eligible with a data-derived explanation.
- Blind CV receives the three live durations; it never receives ISO status,
  contact data, R2 keys or Compliance files.
- Previous failed/abandoned Job uploads remain in the audit data, but their
  failed rows are hidden from the active attachments table as requested for
  the next update. The active-file badge counts Ready files only.

## Verification

`node --test tests/*.test.js` passes 67/67.

`node tests/update-048-compliance-iso-db.mjs` passes 18 isolated PostgreSQL
checks, including the read-only audit and an idempotent migration application.
The existing Update 044–047 isolated database suites pass as well. No real
Supabase, Cloudflare R2, authenticated browser or production deployment was
used by these isolated tests.
