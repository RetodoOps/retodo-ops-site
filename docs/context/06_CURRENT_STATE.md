# Retodo Ops TMS — Current State

**Context snapshot:** 2026-09-19  
**Reconciled against:** private Master v0.15 (last reviewed 2026-09-18), current GitHub `main`, and the latest TMS4 UI work.

## 1. Verified repository identity and baseline

The TMS codebase is:
- repository: `RetodoOps/retodo-ops-site`
- branch: `main`
- TMS path: `/tms`
- server functions: `/netlify/functions`
- production TMS origin: `https://tms.retodo-ops.com/`

`RetodoOps/Retodo-App` is a separate HR/Luma People application.

Current repository evidence:
- Update 055 source commit exists on `main`;
- Update 056 Global Visual System source exists on `main`;
- `tms/build.json` reports build `056`, source baseline `Update 055`;
- Context Pack v1.0 was added to `main` after Update 056.

Repository state is **VERIFIED**. Netlify live state, production Supabase migration state and end-to-end acceptance are separate evidence levels.

## 2. Update progression — reconciled

- 048–049: user-reported deployed; narrow screenshots support Compliance form/submitted state.
- 050: deployment block reported, but frontend acceptance failed (historical deadline/V3 and Dashboard Resource regressions).
- 051: later source advances it to implemented-reported/narrowly supported.
- 052: deployment block reported; Project/Scoop `Cancelled` acceptance PASS; Reports and other items remained incomplete.
- 053: source package was prepared and later uploaded to GitHub `main`; live registration/PDF recovery acceptance is not established.
- 054: deterministic PDF source was prepared and later uploaded to GitHub `main`; live complete PDF acceptance is not established.
- 055: two-signature Agreement 1.1 source is now **VERIFIED PRESENT ON GITHUB MAIN**. Production migration 051/audit 013 execution and live two-party acceptance remain unverified.
- 056: Global Visual System source is **VERIFIED PRESENT ON GITHUB MAIN** and `tms/build.json` = `056`. It changes interface/session-safety behavior and declares no migration, audit or new environment variable.

Do not downgrade repository source to “not uploaded”, but also do not call it production-accepted without live evidence.

## 3. Update 056 — current UI baseline

Update 056 applies a global interface refresh across internal TMS, Resource Portal, sign-in, registration and password setup:
- darker bounded field backgrounds;
- consistent heading/label/supporting-copy hierarchy;
- shared card geometry/spacing;
- compact status/date bubbles;
- prominent Open/Download/View/Print/Export actions;
- purple Upload actions;
- explanatory help collapsed into accessible `?` tooltips;
- responsive behavior;
- role-drift guard when the active Supabase login changes in one browser profile.

For simultaneous Admin/Resource testing, separate browser profiles or Incognito remain recommended.

Acceptance across the entire live application is still to be recorded explicitly; source presence alone is not visual acceptance.

## 4. Resource invitation

Known:
- staff invitation/password/resource-dashboard path has been user-tested historically;
- invitation wording/correction work has been iterated;
- a fresh invitation to an external test Resource produced no visible send error but was **not received**;
- a separate normal test email did arrive.

Status: invitation delivery remains **UNRESOLVED / NOT ACCEPTED**. Inspect function/provider logs and obtain a real delivered invitation + valid link/password/portal test.

## 5. Public self-registration

Self-registration is allowed, but exact activation/pending-admin-approval behavior remains unresolved.

Verified defect:
- existing Auth email → `User already registered`;
- finish-registration route → `Invalid login credentials`.

Update 053 prepared an existing-account recovery path; live no-duplicate recovery acceptance remains unverified.

## 6. Compliance / Agreement

Locked evidence model and workflow remain in force.

Agreement:
- Retodo signature = authorized internal Compliance request/unlock action;
- Service Provider `Accept and sign` = second/final signature;
- no separate Send Agreement action;
- exact Agreement version/hash must be bound immutably;
- final PDF must contain both signature records and be available to Resource and internal user.

Historical failure:
- two signed-PDF downloads were blank/identical.

Current source:
- Update 054 deterministic PDF generator and Update 055 two-signature flow are present on `main`.

Still unverified:
- production migration 051/audit 013;
- live Retodo signature record;
- live Resource final signature;
- matching complete Resource/internal PDFs;
- final version/hash/audit snapshot.

## 7. PO / Dashboard

Preserve:
- versioned immutable PO history;
- active/current PO only in normal lists;
- no separate Resource acceptance;
- PO issue/send implies assignment.

Do not treat `Superseded` or `Overridden` as a locked database/business status merely because packages/UI examples use those words.

Historical regressions requiring explicit retest:
- status-only approval vs historical deadline;
- unintended V3 records after manual deadline edits;
- assigned Resource visibility in Dashboard;
- active-version/cost propagation.

Project/Scoop `Cancelled` path was reported PASS under Update 052.

The earlier broad commercial-adjustment workflow proposal is not current scope. The locked PO change is the approved contractual reduction sentence only unless a later decision expands it.

## 8. Files / R2

Cloudflare R2 remains the storage direction for new TMS operational file bytes.

Narrow live evidence exists for one Ready TXT file and assigned-Resource access. Full format/RLS/lifecycle acceptance is incomplete.

Update 045 package source includes 3-month archive and 24-month archived-binary deletion mechanics with holds. Treat those timings as package implementation, not locked retention policy, until explicitly reconciled.

## 9. Reports

Reports remains **UNRESOLVED / NOT IMPLEMENTED** in the accepted product sense. Job navigation/links existed, but no complete report module/page/specification was accepted.

## 10. Blind CV

Requirements/source corrections exist; definitive live preview/DOCX/PDF logo/output acceptance remains unresolved.

## 11. Commercial/legal correction from the daily Master

Current Freelancer Framework Agreement invoicing cycle:
- 15th; and
- last working day of the month.

Payment:
- 60 calendar days from the applicable invoicing date for undisputed amounts.

Older `15th and 30th` wording is superseded. A legacy Resource UI value still showed it in one test; do not change payment calculations incidentally without inspecting the record/code.

## 12. Context state

The private cross-business Master was last reviewed 2026-09-18 and therefore does not yet contain the GitHub-verified Update 056/context-pack commits from 2026-09-19.

The old rolling `/OPS/Retodo_Ops_TMS_Latest_Changes.md` was stale at Update 051 in the Master review. It should be reconciled, but the daily Master remains the higher-value cross-business handoff.

## 13. Deployment responsibility

Default workflow remains:
- user controls GitHub upload/push, Netlify deployment and production migrations unless explicitly authorizing otherwise;
- agents inspect/edit/test/package;
- deliver complete add/replace files in an upload-only ZIP;
- SQL migrations remain separate forward-only files.
