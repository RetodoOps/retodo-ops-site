# P1.1 — Permission and Snapshot Hardening Handoff

Status: prepared locally for manual deployment  
Session: TMS3  
No GitHub/Netlify upload has been performed.

## Files

1. `tms/migrations/036_p1_permission_snapshot_hardening.sql`
2. `tms/audits/001_p1_permission_snapshot_audit.sql`

## What migration 036 changes

- Makes `supplier_po_versions` append-only. Issued PO versions cannot be
  updated or deleted; a correction must create a new version.
- Makes `audit_events` append-only.
- Makes `file_access_logs` append-only.
- Replaces the generic RLS `operations_write` policy on those three tables with
  `SELECT` for company users and `INSERT` for operational users. Authenticated
  users no longer receive direct `UPDATE`/`DELETE` grants for them.
- Adds database audit events for changes to:
  - Project production/financial/issue status;
  - Scoop status and manual override;
  - Job status;
  - Resource lifecycle/readiness/compliance;
  - Supplier PO status/version;
  - Client and Supplier invoice status.

It does not change Project/Scoop/Job pricing, CAT formulas, rate matching,
status labels or UI behavior.

## Manual execution order

1. Confirm that migrations `001`–`035` and the current local Update 038 files
   are already deployed to the intended environment.
2. Run the complete `036_p1_permission_snapshot_hardening.sql` in Supabase SQL
   Editor.
3. Run the read-only `001_p1_permission_snapshot_audit.sql`.
4. Save the result sets, especially checks 6–11, before making further changes.
5. Exercise one controlled status transition in the UI and rerun check 12 to
   confirm that an audit event was created.

## Expected results

- Check 1: all required objects show `PASS`.
- Check 2: all three append-only tables show `rls_enabled = true`.
- Check 3: each append-only table has a company `SELECT` policy and an
  operations `INSERT` policy only.
- Check 4: append-only triggers exist on all three log/version tables and
  status-audit triggers exist on the listed operational entities.
- Check 5: all listed `SECURITY DEFINER` functions show a fixed
  `search_path=public` configuration. Any `REVIEW` row must be investigated.
- Checks 6, 7, 8, 9, 10 and 11: normally no unexpected failure rows. A returned
  row is a data-repair or security-review item, not something to ignore.
- Check 12: after status changes, events appear with actor, entity, before and
  after values.

## Role tests after migration

Run these with separate authenticated accounts:

| Test | Expected result |
|---|---|
| `admin` reads PO versions, audit events and file-access logs | Allowed. |
| `pm` or `client_relations` reads the same records | Allowed for company rows. |
| `qa` reads the records | Allowed for company rows. |
| `pm` updates/deletes a PO version | Rejected by RLS/trigger. |
| `pm` updates/deletes an audit event | Rejected by RLS/trigger. |
| `pm` updates/deletes a file-access log | Rejected by RLS/trigger. |
| `resource` or `user` reads company-wide audit/PO-version rows | Rejected by company-user RLS. |
| Existing PO revision RPC creates a new version | Allowed through the approved RPC; old version remains unchanged. |
| Existing Project/Scoop/Job status change | Allowed where the role already has operational permission and creates an audit row. |

## Important limitation

This first hardening step makes records append-only and records status changes,
but it does not yet solve every audit-authenticity question. Operational users
retain `INSERT` permission on `audit_events` for compatibility with the current
architecture. P1.2 should replace direct audit insertion with a controlled
append RPC or trusted trigger-only path after all existing audit writers have
been inventoried.

## Rollback/repair note

Do not manually delete the new triggers or policies from the live database.
If a compatibility issue is found, record the failing query/result and prepare
an explicit follow-up migration. Existing PO versions, audit events and file
access logs must not be removed as a rollback method.
