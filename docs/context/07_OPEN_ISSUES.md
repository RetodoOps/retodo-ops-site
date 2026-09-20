# Retodo Ops TMS — Open Issues and Backlog

**Snapshot:** 2026-09-19 after repository reconciliation to build 056

Priority:
- `P0` blocking/security/data-integrity
- `P1` important workflow/reliability
- `P2` product completion/quality
- `PROCESS` context/release discipline

## P0 — Production state of Update 055 Agreement flow
**Status:** UNRESOLVED

Update 055 source is verified on GitHub `main`, and Update 056 builds on it. Still verify separately:
- migration 051 production history;
- audit 013 output;
- Retodo unlock/request signature record;
- Resource second/final signature;
- exact version/hash binding;
- complete Resource signed PDF;
- complete internal signed PDF;
- matching signature/audit metadata.

Do not rerun migrations blindly.

## P0 — Signed Agreement PDF correctness
**Status:** UNRESOLVED

Two historical downloaded PDFs were blank/identical. Deterministic PDF source (054) and two-signature source (055) are in `main`, but real live output must still be accepted.

Acceptance:
- correct agreement terms;
- provider details;
- Retodo signature;
- Service Provider signature;
- version/hash/audit metadata;
- pagination/readability;
- Resource and internal downloads match expected final document.

## P1 — Netlify/live correlation for build 056
**Status:** UNRESOLVED

GitHub `main` verifies `tms/build.json = 056`, but record:
- Netlify deployment status/commit;
- live `/tms/build.json`;
- hard-refresh application behavior;
- no stale static assets.

## P1 — Global visual system acceptance
**Status:** SOURCE-VERIFIED / LIVE ACCEPTANCE OPEN

Update 056 source defines darker fields, hierarchy/card consistency, compact pills, prominent actions, purple Upload, accessible `?` help, responsive behavior and a role-drift guard.

Acceptance-test Dashboard, Project, Job, Resource and Resource Portal on desktop and narrower width.

## P1 — Real invitation email delivery
**Status:** UNRESOLVED

The external test Resource did not receive the access invitation even though a separate test email arrived.

Need:
- invocation/function log;
- provider/API message identifier;
- delivery/suppression/bounce result;
- actual received invitation;
- single-use link/password setup;
- Resource portal landing.

## P1 — Public existing-account registration recovery
**Status:** UNRESOLVED

Verified historical failure: `User already registered` → `Invalid login credentials`.

Update 053 source is now on `main`, but live recovery must prove:
- no duplicate Auth/Resource;
- password setup/recovery works;
- entered profile data is retained/linked;
- final activation follows the explicitly approved policy.

Exact public self-registration activation/pending-approval rule remains unresolved.

## P1 — PO/Dashboard regression retest
**Status:** UNRESOLVED

Retest on current build:
- assigned Resource display;
- status-only Delivered → Approved with historical deadline unchanged;
- no unintended new PO revision;
- active PO only in operational view;
- immutable V1/V2/V3 history;
- supplier cost propagation;
- cancelled/reassignment path.

Do not invent a historical label enum.

## P1 — File lifecycle/R2 end-to-end verification
**Status:** UNRESOLVED

Verify:
- admin upload;
- Resource authorized download;
- other-Resource denial;
- PDF/CSV/XLS and other relevant formats;
- delivery/issue files;
- duplicate Compliance evidence deletion;
- metadata/audit;
- presigned URL expiry;
- archive/restore/hold/deletion worker behavior.

Policy question: package 3-month/24-month lifecycle timings are not yet established here as a locked business policy.

## P1 — Compliance state-machine regression
**Status:** UNRESOLVED

Verify:
- unlock/request after passed General test;
- draft/save;
- submit;
- admin review;
- Request changes;
- Resource edit/resubmit;
- calculated experience;
- internal ISO rationale;
- Retodo signature;
- Resource final signature;
- final PDF;
- submission/review emails;
- least-privilege permissions.

## P2 — Reports module
**Status:** UNRESOLVED / NOT IMPLEMENTED

Define requirements/data/filters/permissions before implementation. Do not invent report stages or duplicate Financials source of truth.

## P2 — Blind CV final outputs
**Status:** UNRESOLVED

Explicitly accept preview/DOCX/PDF logo, language pairs, qualification/experience fields and no financial/client-confidential data.

## P2 — Invoice-cycle UI reconciliation
**Status:** UNRESOLVED

One legacy Resource screen showed `15th and 30th`, while the current Agreement says `15th and last working day`. Inspect actual profile/config/calculation before changing global payment logic.

## PROCESS — Private Master vs repository context
**Status:** ACTIVE

- private daily Master = cross-business decision/evidence authority;
- repository context = Codex/development mirror;
- private Master must never be copied into the public repo;
- primary OPS/daily process is the default single writer of the Master;
- secondary profile produces `MASTER_DELTA_FOR_RECONCILIATION`;
- rolling TMS handoff remains supplementary.
