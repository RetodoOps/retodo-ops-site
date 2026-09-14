# Retodo Ops TMS — Update 050

## Deployment order

1. Run `tms/migrations/049_job_approval_history_compliance_agreement.sql` in Supabase SQL Editor.
2. Run `tms/audits/011_update_050_job_approval_history_compliance_agreement_audit.sql`; every row must be `PASS`.
3. Publish the updated files from this package through the existing GitHub/Netlify workflow.

No new environment variables are required. The internal Compliance-submission email uses the existing Gmail and `TMS_SITE_URL` configuration.

## Implemented changes

### Job approval and Supplier PO

- Changing only a Job status to `Approved` no longer validates an unchanged historical Resource deadline as a new deadline.
- The Job page sends only fields that actually changed. A status-only approval does not send PO-facing terms and therefore does not create a Supplier PO revision.
- A genuinely changed past Resource deadline remains blocked.

### Dashboard and Resource Project History

- Dashboard Scoops show each linked Job and its assigned External Resource.
- Dashboard search, sort and CSV include the assigned Resource data.
- Approved Job history stores and displays approximate `quantity` and `unit` only.
- Flat-rate work is displayed as a flat-rate quantity. No rate, currency, supplier amount or EUR value is added to Project History.
- Existing Account Qualifications remain derived from Approved Jobs.

### Blind CV

- Preview, DOCX and PDF include Retodo EOOD company details.
- Preview and DOCX include the existing Retodo logo.
- Language combinations are listed one per line.
- Selected Project History includes the approximate Job size.
- Existing anonymisation rules remain unchanged; personal identity, direct contact, Client identity (unless already permitted), ISO results and file metadata are not added.

### Compliance evidence deletion

- External Resources can permanently delete their own Ready Compliance evidence while their Compliance form is editable.
- Internal operations users can delete evidence unless Compliance is `Complete`; completed Compliance must first be reopened through the existing changes workflow.
- The server verifies the exact Resource/file relationship, deletes the private R2 object, soft-deletes its metadata, rejects the linked evidence record and writes file-access and trusted audit entries.
- Another Resource cannot inspect or delete the file.

### Compliance submission notification

- After a Resource submits Compliance, Retodo Ops receives an internal email with the Resource name/number, submission time and a direct link to the internal Compliance tab.
- Delivery state is stored and repeated calls do not send the same submission notification twice.
- A failed email does not undo or hide the submitted Compliance record; the internal page shows the notification failure.
- The message contains no ISO eligibility result.

### Freelancer Framework Agreement

- The exact supplied agreement is included at `tms/agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx`.
- Its verified SHA-256 is `0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a`.
- The Resource portal shows the full agreement and pre-fills known Service Provider details from the linked Resource record.
- Missing legal/registration details remain blank and must be completed by the Resource; no vendor data is fabricated.
- The Resource must confirm the displayed details and accept agreement version `1.0` electronically before submitting Compliance.
- The immutable application snapshot records version, document hash, effective date, provider details, signatory, registration email, authenticated profile and timestamp, plus a trusted audit event.
- Internal users see the acceptance summary; direct browser table access is revoked and RLS is enabled.
- Existing submitted/completed records are not rewritten or assigned fabricated acceptance data.

## Migration changes

### Added columns

`public.resource_project_history`

- `quantity numeric(14,3)`
- `unit text`

`public.resources`

- `compliance_submission_notification_sent_at timestamptz`
- `compliance_submission_notification_error text`

### Added table

`public.resource_framework_agreements`

- Resource relationship
- Agreement title, version, SHA-256 and effective date
- Service Provider name, ID/registration, address and tax/VAT number
- Signatory name and registration email
- Authenticated accepting profile and acceptance timestamp

### Added/replaced functions

- Approved Job → Resource Project History feed, including size
- Blind CV projection, including Project History size
- Portal agreement projection and acceptance
- Internal agreement summary
- Compliance submission gate requiring the current agreement
- Two-phase, service-only Compliance file deletion
- Durable Compliance-submission notification state
- Internal Compliance workflow summary

## Access-control changes

- Agreement acceptance is bound to `current_external_resource_id()` and the authenticated Resource profile.
- Agreement snapshots have RLS and no direct `anon` or `authenticated` table grants.
- Compliance deletion and notification state mutations are service-role-only RPCs with a verified actor.
- Compliance evidence deletion enforces exact-own-Resource access for the portal.
- Internal ISO information remains absent from all Resource portal projections, markup and emails.

## Files included

- `tms/job.js`, `tms/job.html`
- `tms/dashboard.js`, `tms/dashboard.html`
- `tms/resource.js`, `tms/resource.html`
- `tms/resource-dashboard.js`, `tms/resource-dashboard.html`
- `tms/style.css`
- `tms/agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx`
- `Logo-440x140.png`
- `netlify/functions/resource-compliance.js`
- `netlify/functions/resource-compliance-files.js`
- `netlify/functions/_shared/gmail.js`
- migration 049 and audit 011
- Update 050 database/UI regression tests and updated successor cache assertions

## Automated test results

- JavaScript syntax checks: `PASS`
- Full Node UI/server regression suite: `86/86 PASS`
- Update 044–050 isolated PostgreSQL suites: `73/73 PASS`
- Update 050 focused browser/server checks: `11/11 PASS`
- Update 050 focused PostgreSQL checks: `7/7 PASS`
- Migration 049 retry/idempotence: `PASS`
- Audit 011 in isolated PostgreSQL: all rows `PASS`
- Supplied agreement binary/hash comparison: `PASS`

The older `resource-onboarding-db.mjs` fixture is not part of this release package because its historical migration 040 source is absent from the current Update 045 baseline. All available Update 044–050 database regressions were run and passed.

## Recommended smoke test after publish

1. Approve a Delivered Job whose unchanged deadline is in the past; confirm no deadline error and no new PO version.
2. Confirm the Dashboard shows the linked Job and assigned External Resource.
3. Confirm Resource Project History and Blind CV show the Job quantity/unit without money.
4. Upload the same Compliance file twice, delete one copy and confirm the other remains available.
5. Submit Compliance without accepting the agreement and confirm submission is blocked.
6. Accept the agreement with the prefilled vendor details, submit Compliance and confirm the internal email arrives once.
7. Confirm the internal Resource Compliance tab shows the agreement snapshot and the Resource portal contains no ISO eligibility information.

## Unresolved issues

None identified in Update 050.
