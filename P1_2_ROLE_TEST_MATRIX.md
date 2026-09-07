# P1.2 — Trusted Writes, Roles and External Resource Portal Test Matrix

Status: prepared locally for manual deployment and live verification

Session: TMS3
Do not place test passwords, access tokens or Supabase service-role keys in
screenshots or chat messages.

## Purpose

Migration 037 closes direct browser writes to:

- `audit_events`;
- `supplier_po_versions`;
- `file_access_logs`.

Authenticated company users retain read access through company RLS. New audit
events and immutable PO versions must continue to be created through trusted
database functions and triggers.

Migration 038 adds the least-privilege External Resource portal, closes generic
`user` workspace access, makes the QA interface read-only, permits PM to add
new active catalogue values, and permits Administrator/PM PO revisions.

## Intended role boundary

| Capability | `admin` | `pm` | `client_relations` | `qa` | `resource` | `user` |
|---|---:|---:|---:|---:|---:|---:|
| Read company audit events and PO versions | Yes | Yes | Yes | Yes | No | No |
| Directly mutate protected-history rows | No | No | No | No | No | No |
| Create operational audit through an allowed business action | Yes | Yes | Yes | No | No | No |
| Assign Resource and create initial immutable PO | Yes | Yes | Yes | No | No | No |
| Manually issue an existing Draft PO | Yes | No | No | No | No | No |
| Create revision of an issued PO | Yes | Yes | No | No | No | No |
| Add a new active Service/Language/Specialization | Yes | Yes | No | No | No | No |
| Edit/deactivate existing catalogue value | Yes | No | No | No | No | No |
| Link External Resource Auth account | Yes | No | No | No | No | No |
| Read own assigned Jobs/files/issues | — | — | — | — | Yes | No |
| Read own immutable Supplier POs | — | — | — | — | Yes | No |
| Read Client/Account identity or Client economics | Yes | Yes | Yes | Yes | No | No |
| Read or manage integration connection configuration | Yes | No | No | No | No | No |

`resource` receives only dedicated own-record RPC projections. `user` receives
no TMS workspace and is not a fallback portal role.

## Required live tests

Use disposable test records and separate authenticated accounts. Do not
deactivate the only Administrator account.

### A. Trusted audit writer

1. Sign in as Administrator.
2. Open a test Scoop, enable Manual status override, change the status and
   save.
3. Return it to the original status and save again.
4. Change the Client reference on a disposable test Project.
5. Run check 10 in `tms/audits/003_p1_2_trusted_write_audit.sql`.
6. Confirm the result contains:
   - `Scoop` / `Manual Scoop status override changed` or `Status changed`;
   - `Project` / `Client reference changed`;
   - a non-null actor for actions performed by the signed-in user.

### B. Trusted PO-version writer

1. On a disposable Job, assign an eligible Resource and issue a Supplier PO.
2. Confirm version 1 is created even though authenticated direct INSERT has
   been revoked from `supplier_po_versions`.
3. As Administrator or PM, create version 2 with a mandatory revision reason.
4. Confirm version 1 remains unchanged and version 2 appears.
5. Run the existing P1.1 PO snapshot checks 7–9 and confirm there is no new
   duplicate, missing version or commercial snapshot failure.

### C. PM / Operations

1. Sign in with a `pm` test account.
2. Confirm Projects, Scoops, Jobs, Financials, PO versions and audit events can
   be read.
3. Change an allowed test Scoop/Job status and confirm it creates an attributed
   audit event.
4. Confirm normal Resource assignment can still create PO version 1.
5. Confirm creating an issued-PO revision is available and produces the next
   immutable version with the mandatory reason.
6. In Settings, add one disposable active catalogue value and confirm existing
   values cannot be edited/deactivated by PM.

### D. Client Relations

1. Sign in with a `client_relations` test account.
2. Confirm Client, Account, Project and operational records can be read and
   allowed operational edits still save.
3. Change a disposable Project Client reference and confirm an attributed
   `Client reference changed` event is created.
4. Confirm Administrator/PM-only PO revision remains unavailable/rejected.

### E. QA read-only boundary

1. Sign in with a `qa` test account.
2. Confirm required Project, Scoop, Job, Financials, audit and PO-version rows
   can be read.
3. Confirm creating/editing a Project, Scoop or Job is unavailable or rejected.
4. Confirm Resource assignment and PO issue/revision are unavailable or
   rejected.

### F. External Resource portal

Use a separate Auth account linked to an External Resource by exact email. Do
not reuse a company or Internal Resource login.

| Data | Expected access |
|---|---|
| Own currently assigned Jobs | Yes, read only |
| Minimal Project/Scoop technical data required for Job | Yes; no Client name |
| Own deadline, languages, Service and instructions | Yes, read only |
| Own Supplier PO and immutable versions | Yes, read only |
| Own assigned-Job files and issues | Yes, read/download only |
| Other Jobs in the same Project | No |
| Client and Account | No |
| Client price, profit and margin | No |
| Other Resources | No |
| Settings | No |
| Create Project/Job/PO revision | No |

1. Assign the linked External Resource to one disposable Job and issue its PO.
2. Sign in as that Resource in a private browser session. Confirm routing to
   `resource-dashboard.html`.
3. Confirm only the assigned Job and own issued POs appear.
4. Open the Job and verify own instructions, files and issues. Confirm issue
   financial impact is absent.
5. Open/download a file and confirm an attributed immutable access-log row.
6. Open every PO version and confirm no Client/Account name or Client economics.
7. Try another Resource's Job and PO IDs directly; both must return not found.
8. Try company routes including Settings; all must redirect to the Resource
   dashboard.
9. Confirm no create, edit, assignment, send or revision controls exist.

### G. Generic user boundary

1. Sign in with an unlinked `user` test account.
2. Confirm access is rejected and the session returns to sign-in.
3. Confirm company Projects, histories, Settings and portal RPC data cannot be
   read.

### H. Internal Resource deactivation

1. Use a secondary Internal Resource test login, never the only Administrator.
2. Confirm the active account can sign in and has its assigned application
   role.
3. As Administrator, change that Internal Resource to `Inactive`.
4. Refresh the secondary session and confirm current TMS access stops.
5. As Administrator, confirm historical Project staff references, Jobs, POs
   and audit events remain unchanged and readable.

## Acceptance

P1.2 is complete only when:

- migration 037 audit checks and migration 038 portal audit checks pass;
- the controlled Scoop and Client-reference changes create attributed events;
- PO issue and revision still create immutable versions;
- QA cannot mutate operational records;
- External Resource sees only the approved own-record projection;
- generic `user` cannot enter a TMS workspace;
- Internal Resource deactivation stops current access without deleting history.

If a test fails, capture the role, exact action, error text and corresponding
audit check. Do not restore broad table grants or generic write policies as a
quick fix.
