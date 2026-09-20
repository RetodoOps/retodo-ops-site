# DEV WORKLOG

**Purpose:** append-only technical continuity history for Retodo Ops TMS development and QA.

This file records material development actions, test results, interruptions and durable checkpoints. It is not the canonical business-policy register.

## Rules

- Append new entries; do not rewrite prior factual history merely because later work supersedes it.
- Use timestamps/dates when known.
- State branch and checkpoint commit when available.
- Distinguish implementation from testing, deployment and user acceptance.
- Record failures and interruptions, not only successes.
- Never include secrets, passwords, service-role keys, bank details, private personal data, or the private Master.

---

## 2026-09-20 — Continuity protocol bootstrap

### TASK_START

Create a crash-safe repository continuity mechanism because GPT/Work/Codex usage may expire mid-task before a final session handoff can be produced.

### BASELINE

- Repository: `RetodoOps/retodo-ops-site`
- Branch checked: `main`
- HEAD checked: `21e9ff676f5a1815368b9537859dc62430becaa9`
- Build: `056`

### DECISION

Operational development state will be persisted in the repository during work:

- `docs/context/CURRENT_WORK.md` — latest continuation point;
- `docs/context/DEV_WORKLOG.md` — append-only technical history;
- `docs/updates/UPDATE_NNN.md` — per-update durable lifecycle/evidence record;
- checkpoint commits pushed to non-main task branches after material logical steps.

Checkpoint pushes to non-main task branches are authorized. Merge to `main`, production deployment, production migrations, production configuration changes and production-data changes still require explicit user approval.

### CURRENT USER-CONFIRMED WORKING EVIDENCE

As of 2026-09-20:
- Agreement two-party signing works.
- Retodo Compliance unlock/signature works.
- Resource `Accept and sign` works.
- Final signed Agreement PDF is downloadable from Resource side.
- Final signed Agreement PDF is downloadable from Admin side.
- Resource access invitation delivery works.

### INTERRUPTED PRIOR WORK

A Codex context-reconciliation attempt displayed edits to 20 files in a Codex/ChatGPT project workspace, but usage expired before completion/review.

Status: `UNRESOLVED / NOT ACCEPTED`.

The edits must not be treated as repository truth unless recovered and verified against an actual Git branch/commit.

### CHECKPOINT

This protocol patch is documentation-only.

No TMS application code, migration, Netlify deployment or production configuration change is part of this bootstrap.
