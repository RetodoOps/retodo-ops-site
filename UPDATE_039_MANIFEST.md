# RetodoOps Update 039 — File Manifest

Purpose: P1.2 least-privilege External Resource portal and agreed role
corrections.

## Database

- `tms/migrations/038_external_resource_portal_and_role_boundaries.sql`
- `tms/audits/004_p1_2_external_resource_portal_audit.sql`

Run the migration before uploading the frontend. Run the audit immediately
after the migration.

## Shared frontend

- `tms/auth.js`
- `tms/style.css`
- `tms/index.html`
- `tms/reset-password.html`
- `tms/accounts.html`
- `tms/client.html`
- `tms/clients.html`
- `tms/dashboard.html`
- `tms/job.html`
- `tms/project.html`
- `tms/quote.html`
- `tms/quotes.html`
- `tms/resource.html`
- `tms/resources.html`
- `tms/settings.html`
- `tms/job.js`
- `tms/resource.js`
- `tms/settings.js`

The HTML files carry cache version `039` for the shared role router and styles.

## External Resource portal

- `tms/resource-dashboard.html`
- `tms/resource-dashboard.js`
- `tms/resource-job.html`
- `tms/resource-job.js`
- `tms/resource-po.html`
- `tms/resource-po.js`
- `tms/resource-portal.js`

## Documentation

- `P1_2_EXTERNAL_RESOURCE_PORTAL_HANDOFF.md`
- `P1_2_ROLE_TEST_MATRIX.md`
- `TMS_ARCHITECTURE.md`
- `TMS_ENTITY_FIELD_STATUS_PERMISSION_MATRIX.md`
- `TMS_FOUNDATION_DEPLOYMENT.md`
- `UPDATE_039_MANIFEST.md`

## Explicitly not included

- Supabase credentials, passwords, access tokens or service-role keys.
- A database dump.
- A Netlify environment-variable change.
- A Git commit, push or deployment action.
