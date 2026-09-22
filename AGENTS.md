# Retodo Ops TMS — Permanent Guardrails

Repository: `RetodoOps/retodo-ops-site`
Default branch: `main`

## Operational continuity

`docs/context/CURRENT_WORK.md` is the normal operational continuation source.
Keep current task state in that file, not in this guardrail file.

Read extra context only when CURRENT_WORK.md explicitly requires it
or a real conflict requires narrowly scoped additional evidence.
Do not routinely load broad context packs or historical records.

## Business-policy authority

Implementation is evidence of behavior, not automatic business policy.
Do not treat a bug, historical behavior or proposal as an approved rule.
Resolve blocking policy conflicts with the user before changing policy.

## Private information

Never commit secrets, credentials, tokens or the private Master.
Keep private material out of repository files and commit messages.

## Database safety

Migrations are forward-only.
Never rewrite an already executed production migration.
Preserve row-level security (RLS) and least privilege.
Do not bypass authorization boundaries to complete a task.

## Checkpoints and production authority

Checkpoint commits and pushes may go only to non-main task branches.
Record material checkpoints in CURRENT_WORK.md with the related work.
The last pushed task-branch checkpoint is the durable continuation point.

Explicit user approval is required for:
- merging to main;
- deployment;
- production migrations;
- production configuration changes, including environment/auth settings;
- production data changes.

## Context reconciliation

Do not perform context reconciliation unless explicitly requested
or necessary to resolve a blocking contradiction.
Keep any necessary conflict investigation narrowly scoped.
