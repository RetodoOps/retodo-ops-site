# Retodo Ops TMS — Permanent Guardrails

Repository: `RetodoOps/retodo-ops-site`

## Normal startup

- Read ONLY `docs/context/CURRENT_WORK.md`.
- Inspect the current branch, HEAD, working tree and `tms/build.json`.
- Do not manually read `AGENTS.md` at normal Work startup.
- `CURRENT_WORK.md` is the complete normal operational continuation source.
- Read extra context only when `CURRENT_WORK.md` explicitly lists it under
  REQUIRED CONTEXT or a real blocking contradiction exists.
- Context reconciliation is NOT a startup prerequisite.
- Do not perform reconciliation unless explicitly requested or needed to
  resolve a real blocking contradiction.

## Policy and security

- Implementation behavior does not automatically define business policy.
- Migrations are forward-only; never edit an executed production migration.
- Preserve RLS and least privilege.
- Never commit secrets or the private Master.

## Checkpoints and continuity

- Update `docs/context/CURRENT_WORK.md` after every MATERIAL checkpoint.
- Material checkpoints include root cause established, approach selected,
  coherent code change completed, migration created, meaningful test completed,
  blocker discovered, user confirmation, or material task-status change.
- Record the task, status, branch, starting HEAD, latest durable checkpoint,
  build, task-specific locked rules, completed work, changed files, tests,
  unresolved work, REQUIRED CONTEXT, NEXT EXACT ACTION and DO NOT REDO.
- Commit code and `CURRENT_WORK.md` together at material checkpoints.
- Checkpoint commits and pushes are allowed only on non-main task branches.
- The last pushed task-branch checkpoint is the durable continuation point.
- Do not rely on an end-of-session handoff.

## Explicit approval boundaries

Without explicit user approval:
- Do not merge to main or push application work directly to main.
- Do not deploy production or execute production migrations.
- Do not change production configuration, data or authentication.
