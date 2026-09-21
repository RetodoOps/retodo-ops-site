# CURRENT WORK

**Purpose:** crash-safe operational continuation point for Retodo Ops TMS work.  
**Repository:** `RetodoOps/retodo-ops-site`  
**Default branch:** `main`  
**Last repository baseline checked:** `15b5922473585256f6e8c590b8f3a6d80c8b04b4`
**Build at baseline:** `057`
**Last updated:** 2026-09-21

> This file records operational work state only. It does not override LOCKED business decisions or the private Master.

## Current task

Verify core Dashboard / Project / Scoop / Job flows and prepare read-only Reports architecture. Task ID: REPORTS-DESIGN-20260920. User approved verification and architecture, not production changes. No numbered application release or build increment for this assessment.

## Status

`PARTIAL` — local source/fixture verification completed and Reports architecture proposed. RPT-01 currency mixing reproduced; RPT-02 bulk partial-write window reproduced. Full end-to-end/live verification remains NOT_TESTED. See docs/reports/CORE_FLOW_AND_REPORTS_ARCHITECTURE.md.

- Task branch: `dev/reports-architecture-20260920`.
- Starting HEAD and latest durable checkpoint before this task: `938c28a4c4edc362398ef3a46f79fdd3ad386b4f`. Main remains `15b5922`, build 057. The current branch HEAD is the local checkpoint containing this revision; push is pending.
- Working tree at task start: clean fresh clone; older dirty workspaces preserved.
- Current changed files: CURRENT_WORK.md, DEV_WORKLOG.md, 07_OPEN_ISSUES.md, docs/reports/CORE_FLOW_AND_REPORTS_ARCHITECTURE.md, tests/reports-core-flow-assessment.test.js.
- Completed checks: remote identity, main HEAD, protocol ancestry and four-file patch, build 057, branch inventory.
- Completed this task: 7 new assessment PASS / 1 TODO reproducing defect; 14 Update 044 + 7 Update 050 isolated PostgreSQL checks PASS; 3 core scripts syntax PASS. Full JS suite with dependencies: 100 PASS / 22 FAIL / 1 TODO; not green.
- Revalidated 2026-09-21: `node --test tests/reports-core-flow-assessment.test.js` reports 7 PASS / 1 TODO / 0 unexpected failures; `git diff --check` PASS.
- Incomplete: full-chain/browser/production acceptance, legacy-test triage and report-design approval. Historical exact interrupted 20-file diff remains unresolved.
- No numbered application update is being implemented; no build increment.

## Task-specific LOCKED rules

- This is an unnumbered, read-only assessment; do not implement Reports, invoice logic, application workflow changes or migrations in this task.
- Do not perform production writes, production migration, production deployment, production environment/auth/data changes or merge to `main`.
- Do not infer currency conversion, invoice recognition, report permissions or parent/sibling bulk-status semantics without explicit approval.
- Checkpoint only this assessment and its continuity records on `dev/reports-architecture-20260920`.

## Starting repository state

The following is the historical protocol-bootstrap starting state, not this recovery task's starting HEAD listed above.

- Repository: `RetodoOps/retodo-ops-site`
- Branch: `main`
- Starting HEAD: `21e9ff676f5a1815368b9537859dc62430becaa9`
- Build marker: `056`
- Application-code change required: no
- Migration required: no
- Netlify deployment required: no

## Files in this continuity-protocol patch

- `AGENTS.md` — replace
- `docs/context/CURRENT_WORK.md` — add
- `docs/context/DEV_WORKLOG.md` — add
- `docs/updates/UPDATE_TEMPLATE.md` — add

## Completed

- Defined repository-based crash-safe continuity model.
- Defined `CURRENT_WORK.md` as the mandatory first operational continuation source.
- Defined append-only `DEV_WORKLOG.md`.
- Defined one durable `UPDATE_NNN.md` record per material numbered update.
- Authorized checkpoint commit/push only to non-main task branches.
- Preserved explicit approval requirement for merge to `main`, production deployment, production migration and production configuration/data changes.
- Preserved the private Master as separate cross-business canonical decision/evidence source.

## Important current evidence

User-confirmed working as of 2026-09-20:
- Agreement two-party signing flow.
- Retodo Compliance unlock/signature.
- Resource `Accept and sign`.
- Final signed Agreement PDF download from Resource side.
- Final signed Agreement PDF download from Admin side.
- Resource access invitation delivery.

These are not active blockers unless new regression evidence appears.

## Interrupted work that must not be mistaken for completed repository work

A prior Codex session attempted a context-only reconciliation and displayed edits to 20 files inside a Codex/ChatGPT project workspace. Usage credits expired before a final review/report.

Unless those edits are independently recovered and verified in an actual Git branch/commit:
- do not treat them as accepted;
- do not assume they were pushed;
- do not assume the context reconciliation is complete;
- recover/review the diff if available before redoing the work from zero.

### Recovery review completed 2026-09-20

- Existing durable reconciliation is available at `21e9ff676f5a1815368b9537859dc62430becaa9`, relative to context-pack commit `55759530fe406f796b5ad43c81542b12b655069f`: 19 files, including the reconciliation note. Reviewed its file inventory and reconciliation-note diff; did not redo a full business/legal audit.
- Recovery command: `git diff 55759530fe406f796b5ad43c81542b12b655069f 21e9ff676f5a1815368b9537859dc62430becaa9 -- AGENTS.md CONTEXT_PACK_START_HERE.md MANIFEST.md docs/context`.
- That existing commit predates the bootstrap warning. There is no evidence establishing identity with the interrupted 20-file attempt; do not mark that attempt completed.
- Searched available workspace context/patch filenames and inspected available historical TMS clones' branches, working diffs/status, context history and stashes. No separate context-reconciliation diff or stash was found. Old application/UI edits were preserved, not repurposed.
- Remote inventory before this task: main, update-052-codex and three claude branches. No separate reconciliation checkpoint branch was found. Fresh clone has no prior local reflog or stash from the interrupted session.
- Historical reconciliation-note unresolved entries for agreement signing/PDF and invitations are superseded by the user-confirmed evidence in current AGENTS.md; they are not reopened by this review.
- Update 057 is present in main at the task base. No docs/updates/UPDATE_057.md existed at inspection; this task does not certify that UI release or start functional work.
- No private Master was read. No fresh reconciliation was performed. Recovery is limited to evidence accessible in this environment; missing diff may exist in another Codex workspace.

## REQUIRED CONTEXT

- Read this file first for normal continuation.
- The proposed report contract and evidence are in `docs/reports/CORE_FLOW_AND_REPORTS_ARCHITECTURE.md`.
- The executable source assessment is `tests/reports-core-flow-assessment.test.js`; its TODO is an intentional RPT-01 defect reproduction, not a green functional assertion.
- Main baseline is `15b5922473585256f6e8c590b8f3a6d80c8b04b4`, build `057`; this task branch starts from `938c28a4c4edc362398ef3a46f79fdd3ad386b4f`.

## Next exact action

Push the current branch HEAD containing the assessment, test and continuity records to the current non-main task branch. Then review proposed report grains/currency/date/permissions with the user. A later, separately approved development task should address verified currency mixing and bulk-write consistency, then complete core-flow acceptance before financial Reports implementation.

## DO NOT REDO

- Do not increment the TMS application build solely for this documentation protocol.
- Do not deploy Netlify for this documentation-only patch.
- Do not run a migration.
- Do not mark the interrupted 20-file reconciliation as complete without evidence.
- Do not commit the private Master.
