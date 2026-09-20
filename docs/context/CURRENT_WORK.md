# CURRENT WORK

**Purpose:** crash-safe operational continuation point for Retodo Ops TMS work.  
**Repository:** `RetodoOps/retodo-ops-site`  
**Default branch:** `main`  
**Last repository baseline checked:** `21e9ff676f5a1815368b9537859dc62430becaa9`  
**Build at baseline:** `056`  
**Last updated:** 2026-09-20

> This file records operational work state only. It does not override LOCKED business decisions or the private Master.

## Current task

Introduce the crash-safe repository continuity protocol so future GPT/Work/Codex sessions can resume from durable repository checkpoints without relying on an end-of-session handoff.

## Status

`IN_PROGRESS` until this patch is uploaded and verified in the repository.

## Starting repository state

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

## Next exact action

1. Upload this continuity-protocol patch to the repository.
2. Verify the resulting repository HEAD and these four files.
3. Recover/review the interrupted context-reconciliation diff if available.
4. Create a non-main task branch for further material work and begin checkpointing there.

## Do not do

- Do not increment the TMS application build solely for this documentation protocol.
- Do not deploy Netlify for this documentation-only patch.
- Do not run a migration.
- Do not mark the interrupted 20-file reconciliation as complete without evidence.
- Do not commit the private Master.
