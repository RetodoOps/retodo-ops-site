# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current branch: dev/lightweight-continuity
Starting HEAD: c5b60306635fb37803ebe145fe8f139bcb580614
Latest durable checkpoint commit: The commit containing this revision on `dev/lightweight-continuity`; resolve its SHA from the pushed branch tip (avoids a self-referential hash).
Build: 057 — Update 057 — Canonical UI layout system (unchanged)
Last updated: 2026-09-22

## CURRENT TASK

READY FOR NEXT FUNCTIONAL TMS TASK

## STATUS

READY

## OBJECTIVE

Continue from this record when the user provides the next functional TMS task.
The lightweight continuity migration is complete; no functional task is selected.

## TASK-SPECIFIC LOCKED RULES

- Normal startup reads only this file and inspects branch, HEAD, working tree and `tms/build.json`; do not manually read AGENTS.md.
- Extra context is read only when listed under REQUIRED CONTEXT or a real blocking contradiction exists. Context reconciliation is not a startup prerequisite.
- For normal development, the mandatory continuity write is this file, updated after every MATERIAL checkpoint: root cause, selected approach, coherent change, migration creation, meaningful test, blocker, user confirmation or material status change.
- Commit code and this record together, and push checkpoints only to the current non-main task branch. Do not rely on an end-of-session handoff.
- DEV_WORKLOG.md and UPDATE_NNN.md are optional historical/detail records, never normal startup reads or mandatory checkpoint writes. Update a numbered record only when a numbered release/update exists; update DEV_WORKLOG only for useful durable historical events.
- Main merge, production deployment, production migrations and production configuration/data/auth changes require explicit user approval.
- This migration changes only AGENTS.md and this file; application code and build remain unchanged. No deployment or migration is authorized by it.

## USER-CONFIRMED WORKING

- Agreement two-party signing works.
- Retodo Compliance unlock/signature works.
- Resource Accept and sign works.
- Final signed Agreement PDF works for Resource.
- Final signed Agreement PDF works for Admin.
- Resource access invitation delivery works.

These user-confirmed facts are carried forward, not independently retested here.
Do not reopen them without new regression evidence.

## COMPLETED

- Checked live main and freshly cloned baseline c5b60306635fb37803ebe145fe8f139bcb580614; initial working tree was clean.
- Read only AGENTS.md and this file; inspected branch, HEAD, working tree and build marker.
- Replaced long AGENTS.md with compact permanent guardrails.
- Rebuilt this file as the complete normal continuation source and reset task/status to READY.
- Previous continuity recovery is complete enough for continuity purposes and is not the current functional task.
- Removed historical 20-file reconciliation recovery as a prerequisite to future development.
- Simplified mandatory checkpoint writing to this file.

## FILES CHANGED

- AGENTS.md
- docs/context/CURRENT_WORK.md

## TEST RESULTS

- Live main baseline and build 057 verified; initial working tree clean.
- Documentation checks: required sections and user-confirmed facts retained; REQUIRED CONTEXT is NONE; AGENTS.md is within the 60-line maximum.
- Changed-file scope and whitespace checked before commit; no application or build changes.
- No application tests required or run for this documentation-only change.

## UNRESOLVED / NOT TESTED

- No next functional task has been specified.
- Historical interrupted 20-file reconciliation remains unrecovered/unaccepted; it is not a development prerequisite or active blocker.
- Application behavior, deployment state and production migration state were not independently verified in this task.

## REQUIRED CONTEXT

NONE

## NEXT EXACT ACTION

Wait for the user's next functional TMS instruction, then set the current task, objective and task-specific rules here and begin that work from the latest pushed non-main checkpoint. Do not initiate historical diff recovery or context reconciliation.

## DO NOT REDO

- Do not restart the completed continuity-recovery task or repeat this migration.
- Do not recover the old 20-file diff as a prerequisite to functional development.
- Do not routinely read private Master, AGENTS.md, DEV_WORKLOG.md, old handovers, old UPDATE files, decision registers or broad context packs.
- Do not reopen the user-confirmed working flows without new regression evidence.
- Do not increment build, deploy, run migrations or alter production for this documentation-only task.

## PRODUCTION STATE

- Repository implementation: documentation-only continuity migration on dev/lightweight-continuity; application baseline remains build 057.
- Main merge: not performed for this migration; live main checked at the starting HEAD above.
- Netlify deployment: not performed; current deployed revision not verified.
- Production migrations: none executed; existing execution state not verified.
- Live test: not performed in this task.
- User acceptance: the six working facts above are user-confirmed; no broader production acceptance is inferred.
