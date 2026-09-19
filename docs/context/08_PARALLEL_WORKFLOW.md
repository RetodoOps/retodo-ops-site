# Retodo Ops — Parallel GPT + Codex Workflow

**Version:** 1.0  
**Date:** 2026-09-19

---

## 1. Roles

### Primary ChatGPT profile — Product / Architecture authority

Use for:
- product decisions;
- business rules;
- workflow design;
- conflict resolution;
- acceptance criteria;
- prioritization;
- final approval of proposed changes.

This profile currently has the richest historical Retodo Ops/TMS context.

### Secondary ChatGPT profile — Development / QA coordinator

Use for:
- scoped implementation planning;
- code review;
- QA/test design;
- defect isolation;
- coordinating one or more Codex tasks;
- producing handover reports.

It must use the repository context pack rather than building a separate private source of truth.

### Codex Desktop — Execution agent

Use for:
- inspecting the current codebase;
- editing files;
- writing migrations;
- running tests/builds;
- producing diffs;
- working in task branches/worktrees.

Codex must not independently redefine locked business rules.

---

## 2. Task ownership ledger

Before starting parallel work, record something like:

| Workstream | Owner | Branch | Allowed scope | Forbidden overlap |
|---|---|---|---|---|
| Resource UI | Codex A | `codex/resource-profile-ui` | profile/components/css | no Compliance DB/state |
| Agreement PDF | Codex B | `codex/compliance-pdf-fix` | PDF/signing server code | no Resource UI redesign |
| Invitation email | GPT2/Codex C | `codex/invitation-delivery` | email/invite route | no Auth schema redesign |

Do not start two tasks that both alter the same state machine/migration without sequencing.

---

## 3. Start-of-task protocol

The coordinator gives Codex:

1. Objective.
2. Relevant locked decision IDs.
3. Exact allowed files/modules if known.
4. Explicit non-goals.
5. Required tests.
6. Packaging/deployment restrictions.
7. Required report format.

Example:

```text
Objective: Fix Resource profile layout only.
Locked decisions: DR-080, DR-081.
Do not change Compliance business logic, DB schema, agreement sequence or field meaning.
Run lint/build and visual inspection at desktop/narrow width.
Return changed files, tests, screenshots/description, and remaining issues.
Do not push or deploy.
```

---

## 4. Merge gate

Before accepting a workstream:

- compare against newest `main`/accepted base;
- re-read any decisions made while the branch was in progress;
- confirm no locked behavior changed;
- run targeted regression tests;
- reconcile migration numbering;
- inspect RLS changes;
- update context docs.

---

## 5. Decision handoff between profiles

When one profile obtains a new user decision, write it immediately in:

`01_DECISION_REGISTER.md`

Minimum entry:
- decision ID;
- date/source;
- status;
- exact decision;
- affected modules;
- superseded decision if any.

The other profile must not rely on “you probably saw it in the other chat”.

---

## 6. Implementation handoff

Every code task returns:

```text
Update ID:
Date:
Branch/base:
Objective:

Decision IDs implemented:
Changed files:
SQL migrations:
Env/config:
Tests:
Results:
Production steps NOT performed:
Known issues:
Recommended next task:
```

Save important handovers in `docs/context/handovers/`.

---

## 7. Production control

Default established rule:
- user performs upload/push/deploy/migrations manually.

Therefore parallel agents should stop at:
- locally tested branch/files;
- complete ZIP;
- separate SQL migration;
- exact deployment/test instructions.

Only change this behavior when the user explicitly instructs that a specific connected agent may push/deploy.

---

## 8. Conflict resolution

If two agents produce conflicting implementations:

1. Do not pick by code quality alone.
2. Identify which `LOCKED` decisions each implementation follows.
3. Prefer the implementation matching the latest locked behavior.
4. If both are compatible, choose the simpler/safer one.
5. If the decision itself is ambiguous, mark `UNRESOLVED` and surface the exact conflict for product authority.

---

## 9. Recommended workstream order from current state

To minimize cross-branch conflicts:

1. Resource profile UI cleanup (UI-only branch).
2. Production-state reconciliation / migration inventory.
3. Agreement PDF/signing correctness.
4. Invitation email delivery.
5. PO/Dashboard regression verification.
6. R2 file-lifecycle verification.
7. Blind CV.
8. Reports.

UI-only work can run in parallel with server-side PDF/email investigation if the branches avoid shared files.
