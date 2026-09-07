# P1.2 — External Resource Portal and Role Boundaries Handoff

Status: prepared locally for manual deployment and live verification

Release: Update 039  
Session: TMS3  
No GitHub push, Netlify deployment or Supabase execution has been performed by
Codex.

## Outcome

Update 039 introduces a dedicated, read-only External Resource workspace. It
does not open direct Resource RLS access to company tables. Each portal screen
uses narrowly scoped `SECURITY DEFINER` functions that resolve the signed-in
user to exactly one External Resource.

The agreed Resource boundary is:

| Data or action | External Resource access |
|---|---|
| Currently assigned Jobs | Read only |
| Technical Project and Scoop references required for the Job | Read only; no Client name |
| Own deadline, languages, Service, Specialization, quantity and instructions | Read only |
| Own issued Supplier POs and all immutable versions | Read only |
| Files and issues belonging to an assigned Job | Read/download only; file access is logged |
| Other Jobs in the same Project | No |
| Client and Account identity | No |
| Client price, profit and margin | No |
| Other Resources | No |
| Settings | No |
| Create Project, Job or PO revision | No |

PM may add a new active Service, Language or Specialization and may create an
immutable revision of an issued Supplier PO. Only Administrator may edit,
activate/deactivate or delete existing catalogue entries. QA remains read-only.

## Deployment files

Database first:

1. `tms/migrations/038_external_resource_portal_and_role_boundaries.sql`
2. `tms/audits/004_p1_2_external_resource_portal_audit.sql`

Then upload the Update 039 frontend files from the supplied ZIP. The three new
portal routes are:

- `tms/resource-dashboard.html`
- `tms/resource-job.html`
- `tms/resource-po.html`

Do not upload only the three pages. The role router in `tms/auth.js`, shared
styles, company Resource-link panel and cache-version changes are also required.

## Manual deployment order

1. Keep the completed Supabase backup in a safe location.
2. In Supabase **SQL Editor**, open and run the complete migration
   `038_external_resource_portal_and_role_boundaries.sql` once.
3. Run all statements in
   `004_p1_2_external_resource_portal_audit.sql`.
4. Expected audit results:
   - checks 1–6, 8, 9 and 12–13: every returned row is `PASS`;
   - check 7: `0 rows`, unless an existing Storage policy has been explicitly
     reviewed as company-only;
   - check 10: `0 rows`;
   - check 11: informational inventory only.
5. Upload the Update 039 frontend files to Netlify using the normal manual
   process.
6. Hard refresh the application (`Ctrl+F5`) before role testing.

If migration 038 fails, stop and retain the exact error. Do not rerun earlier
migrations and do not loosen RLS policies to make a screen load.

## Create and link the External Resource login

Use a separate Authentication account. Do not reuse the Administrator, PM, QA,
Client Relations or Internal Resource account because one Auth user can be
linked to only one Resource and a company role must never be converted into an
External Resource role.

1. In the TMS, open **Resources → External Resource** and select the intended
   Resource.
2. Confirm its email is correct and unique, its lifecycle is `Active`, then
   save.
3. In Supabase, open **Authentication → Users → Add user**.
4. Create a user with exactly the same email. Set a temporary password using
   the normal secure process and mark the account confirmed if the dashboard
   offers that option.
5. Return to the TMS Resource record and open **Portal & Access**.
6. The panel must say that a matching Authentication user was found. Click
   **Activate portal login** as Administrator.
7. The panel must change to **Linked and ready · portal Active**.

The activation function rejects an Auth account when it already has a company
role, is linked to another Resource, or when the Resource is already linked to
a different Auth account.

## Assign the test Resource

Portal activation alone does not create work visibility.

1. As Administrator, open a disposable Job.
2. Select the External Resource and an approved matching Supplier rate.
3. Assign the Resource and issue/send its Supplier PO through the normal Job
   workflow.
4. Verify the Job still loads correctly for the company role before switching
   accounts.

## External Resource live test

Use a private/incognito browser session and sign in with the new Resource
account.

1. Sign-in must route to `resource-dashboard.html`, never the company Dashboard.
2. **My Jobs** must contain the assigned test Job and no unassigned Job.
3. The row may show only Job number, Project/Scoop technical references,
   Service/Specialization, language pair, deadline, status and own Supplier PO.
4. Open the Job. Confirm the instructions, own PO, own files and own issues are
   visible. The issue financial-impact field must not appear.
5. Open and download a private Job file. Afterwards, confirm a new attributed
   `file_access_logs` row exists for that Resource.
6. Open the Supplier PO and switch between immutable versions. Client/Account
   identity and Client economics must not appear.
7. Paste the ID of another Resource's Job into `resource-job.html?id=...`.
   Expected: `Assigned Job not found` and no data.
8. Paste another Resource's PO ID into `resource-po.html?id=...`.
   Expected: `Supplier PO not found` and no data.
9. Manually visit `dashboard.html`, `project.html`, `job.html`, `resources.html`
   and `settings.html`. Every route must return to the Resource dashboard.
10. Confirm there are no create, edit, assign, send or revision controls in the
    Resource workspace.
11. Reassign the disposable Job to another Resource. The original Resource must
    lose Job/files/issues visibility, while its own historical issued PO remains
    in **My Purchase Orders**.

## Company-role regression tests

- **Administrator:** full operational access; can link Resource accounts,
  manage existing catalogues, issue and revise POs.
- **PM:** can add new active catalogue values and create a PO revision; cannot
  edit/deactivate an existing catalogue value or activate a Resource login.
- **Client Relations:** agreed operational access remains; cannot revise an
  issued PO or manage catalogue entries.
- **QA:** may read required company records; all operational form and action
  controls are disabled, and backend mutation attempts remain rejected.
- **Generic `user`:** no TMS workspace. It must not be used as a shortcut for a
  Resource portal account.

## Access-state behavior

| Resource state | Portal behavior |
|---|---|
| `Active` | Assigned Jobs, own files/issues and own issued POs |
| `Read-only` | Same read-only portal data; no mutations |
| `Financial only` within expiry | Own issued PO history only |
| `Closed` | Sign-in is rejected |
| Lifecycle `Inactive` with `Active`/`Read-only` portal | Sign-in is rejected |
| Lifecycle `Inactive` with valid `Financial only` access | Own issued PO history only, until expiry |

Changing access state preserves immutable POs, file-access logs and audit
history.
