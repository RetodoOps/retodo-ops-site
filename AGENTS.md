# Retodo Ops TMS — Agent Instructions

**Context Pack version:** 1.0  
**Canonical date:** 2026-09-19  
**Scope:** Retodo Ops Translation Management System (TMS)

## 1. Mandatory startup sequence

Before changing code, schema, UI, workflows, permissions, emails, PDFs, pricing, statuses, or business logic:

1. Read `docs/context/00_MASTER_CONTEXT.md`.
2. Read `docs/context/01_DECISION_REGISTER.md`.
3. Read `docs/context/06_CURRENT_STATE.md`.
4. Read `docs/context/07_OPEN_ISSUES.md`.
5. Read the latest file in `docs/context/handovers/`.
6. For UI work, also read `docs/context/04_UI_UX_RULES.md`.
7. For implementation work, also read `docs/context/05_DEVELOPMENT_RULES.md`.

Do not begin from assumptions based only on the current chat/thread.

## 2. Source-of-truth precedence

When sources conflict, use this precedence:

1. The user's newest explicit instruction.
2. A newer `LOCKED` decision in `01_DECISION_REGISTER.md`.
3. `06_CURRENT_STATE.md`.
4. `00_MASTER_CONTEXT.md`.
5. Latest handover.
6. Older handovers / implementation reports.
7. Historical chat summaries.

Never silently reinterpret a `LOCKED` decision.

## 3. Decision statuses

Use only these labels for material decisions:

- `LOCKED` — explicitly decided/approved by the user.
- `SUPERSEDED` — replaced by a later decision.
- `PROPOSED` — suggested but not approved.
- `IMPLEMENTED-REPORTED` — reported as implemented/deployed but not independently verified here.
- `VERIFIED` — directly verified by code, migration, test, or application behavior.
- `UNRESOLVED` — discussed but not completed/decided.

A code change does not convert a `PROPOSED` decision into `LOCKED`.

## 4. Change authority

- You may implement an existing `LOCKED` decision.
- You may repair bugs without changing intended business behavior.
- You may propose an alternative, but mark it `PROPOSED` and do not implement it if it changes a locked workflow without explicit approval.
- If current code contradicts a `LOCKED` decision, treat the code as the implementation defect unless a later explicit user decision supersedes the register.

## 5. Repository and deployment safety

The exact TMS GitHub repository must be established from the active TMS working copy. Do **not** assume that `RetodoOps/Retodo-App` is the TMS repository; the connected repository inspected on 2026-09-19 appears to contain an HR/Luma People application.

Unless the user explicitly changes this rule:

- Codex may edit the local working tree and create a task branch.
- Do **not** push to GitHub, merge, deploy to Netlify, or run production migrations automatically.
- Deliver repository changes as complete files / a complete ZIP, not as scattered snippets.
- SQL migrations are delivered as separate `.sql` files, not mixed into the GitHub ZIP when the user is following the established manual deployment workflow.
- Preserve existing `config.js` behavior/file where present unless the task explicitly requires changing it.
- Never include secrets, tokens, passwords, service-role keys, OAuth client secrets, or live credentials in commits, ZIPs, prompts, logs, screenshots, or documentation.

## 6. Database rules

- Migrations are forward-only.
- Never edit an already executed production migration.
- New schema changes require a new numbered migration.
- Preserve RLS unless a locked decision explicitly requires a policy change.
- State migration dependencies and execution order.
- For security-sensitive RPC/policy changes, test both allowed and denied paths.

## 7. Required implementation report

For every material implementation, report:

- objective;
- branch/workstream;
- changed files;
- new migration(s);
- environment/config changes;
- business rules affected;
- tests run and results;
- manual test steps;
- deployment status;
- unresolved risks;
- context documents that must be updated.

## 8. Parallel work

Never allow two agents to independently modify the same workflow/schema without coordination.

Use one workstream per branch, for example:

- `codex/compliance-pdf-fix`
- `codex/resource-profile-ui`
- `codex/invitation-delivery`
- `codex/reports-module`

Before starting, write the scope and forbidden areas. Before merging, reconcile against the latest `LOCKED` decisions and any merged work from other branches.

## 9. UI quality gate

Do not fix only the specifically mentioned misalignment. Review the whole affected screen for hierarchy, spacing, alignment, containment, contrast, consistency, responsive behavior, and readability. Follow `04_UI_UX_RULES.md`.

## 10. Context maintenance

After any material user-approved decision or completed implementation:

- update `01_DECISION_REGISTER.md`;
- update `06_CURRENT_STATE.md`;
- update `07_OPEN_ISSUES.md`;
- create/update the latest handover if the session materially changes the project state.

The repository context is the durable project memory. Chat history is supporting evidence, not the sole source of truth.
