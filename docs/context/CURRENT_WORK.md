# CURRENT WORK

Repository: `RetodoOps/retodo-ops-site`
Current branch: `dev/continuity-lightweight`
Starting HEAD: `bc545fc4bcd2476de21242ac23fcfb6955957454` (local checkout)
Latest durable checkpoint: the commit containing this configuration on `dev/continuity-lightweight`; resolve its SHA from the remote branch tip. Previous durable checkpoint: `315d2408fea770d5d17af5f4da4de8fb29abc444`.
Build: `057` — unchanged
Last updated: 2026-09-22

## CURRENT TASK

READY FOR NEXT FUNCTIONAL TMS TASK

## STATUS

READY

## OBJECTIVE

Continue from the next explicit functional TMS instruction using this file
as the self-contained operational continuation source.

## TASK-SPECIFIC LOCKED RULES

- This configuration changes only AGENTS.md and docs/context/CURRENT_WORK.md.
- Do not change application code, database files or tms/build.json.
- Do not deploy, execute migrations or change production configuration/data.
- No context reconciliation or unrelated tests are part of this configuration.
- Update this record at material checkpoints together with related work.

## USER-CONFIRMED WORKING

- Agreement two-party signing works.
- Retodo Compliance unlock/signature works.
- Resource Accept and sign works.
- Final signed Agreement PDF works for Resource.
- Final signed Agreement PDF works for Admin.
- Resource access invitation delivery works.

## COMPLETED

- Reduced AGENTS.md to permanent guardrails.
- Replaced this record with a self-contained lightweight continuation format.
- Preserved the six user-confirmed working behaviors.
- Closed the configuration scope; no functional task is automatically resumed.

## FILES CHANGED

- AGENTS.md
- docs/context/CURRENT_WORK.md

## TEST RESULTS

Documentation-only checks: required sections, READY state, NONE required context,
guardrail line count and two-file change scope checked before checkpointing.
No application or database tests run.

## UNRESOLVED / NOT TESTED

- No new functional task has been assigned.
- Prior Reports assessment remains proposed/partial, not approved implementation.
  Previously recorded currency-mixing and bulk partial-write findings are not
  resolved by this configuration; full-flow acceptance remains untested.
- The historical interrupted reconciliation attempt remains unaccepted.
  It is not the current task, a prerequisite or a blocker.
- Production deployment/migration state has not been reverified here.

## REQUIRED CONTEXT

NONE

## NEXT EXACT ACTION

Wait for the user's next functional TMS task, then record its objective and
task-specific constraints here before material implementation.

## DO NOT REDO

- Do not restart the historical context-reconciliation attempt.
- Do not read broad context packs or old update history at normal startup.
- Do not reopen confirmed signing, PDF or invitation behavior without new evidence.
- Do not automatically resume Reports work or claim its known findings are fixed.
- Do not increment the build for this documentation configuration.

## PRODUCTION STATE

- GitHub implementation: documentation-only checkpoint on the non-main
  configuration branch; no application implementation or main merge in this task.
  Remote parent is 315d2408fea770d5d17af5f4da4de8fb29abc444, whose tree matches
  the starting local HEAD; connector publication preserves that durable ancestry.
- Netlify deployment: none performed; current live deployment not inspected.
- Migrations: no database files changed and no migrations executed.
- Live/user acceptance: the six behaviors above are user-confirmed working;
  this does not establish unrelated functionality or production release acceptance.
