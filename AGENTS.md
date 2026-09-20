# Retodo Ops TMS — Agent Instructions

**Context Pack version:** 1.2  
**Reconciled:** 2026-09-19  
**Repository:** `RetodoOps/retodo-ops-site`  
**Default branch:** `main`  
**Production TMS origin:** `https://tms.retodo-ops.com/`

## 1. Mandatory startup sequence

Before changing code, schema, UI, workflows, permissions, emails, PDFs, pricing, statuses, or business logic:

1. If the current private `Retodo_Ops_Master_Context_and_Decisions.md` is available in the ChatGPT Project/session, read it first. It is the daily cross-business decision/evidence register and may be newer than this repository snapshot.
2. Read this `AGENTS.md`.
3. Read `docs/context/12_CONTEXT_RECONCILIATION_2026-09-19.md`.
4. Read `docs/context/00_MASTER_CONTEXT.md`.
5. Read `docs/context/01_DECISION_REGISTER.md`.
6. Read `docs/context/06_CURRENT_STATE.md`.
7. Read `docs/context/07_OPEN_ISSUES.md`.
8. Read `docs/context/handovers/RETODO_OPS_FULL_PROJECT_HANDOFF_2026-09-19.md`.
9. Read `docs/context/handovers/TMS4_CURRENT_HANDOVER.md`.
10. For UI work, also read `docs/context/04_UI_UX_RULES.md`.
11. For implementation work, also read `docs/context/05_DEVELOPMENT_RULES.md`.
12. Verify the current repository state (`git remote`, branch/HEAD, and `tms/build.json`) before changing anything.

Do not begin from assumptions based only on the current chat/thread.

## 2. Authority and conflict resolution

Use this precedence when sources conflict:

1. The user's newest explicit instruction.
2. The exact wording of the currently approved legal/source document when working on that document.
3. The newest entry in the private daily `Retodo_Ops_Master_Context_and_Decisions.md`, when available.
4. Current repository/schema/application behavior as evidence of implementation state only. A bug is not automatically an approved business rule.
5. Newer `LOCKED` entries in this repository context pack.
6. `06_CURRENT_STATE.md`.
7. Latest handover.
8. Older implementation reports/history.

Never silently reinterpret a `LOCKED` decision. Record unresolved conflicts.

## 3. Evidence labels

Use these labels consistently:

- `LOCKED` — explicitly decided/approved by the user.
- `SUPERSEDED` — replaced by a later decision.
- `PROPOSED` — suggested but not approved.
- `IMPLEMENTED-REPORTED` — reported implemented/deployed but not independently verified.
- `VERIFIED` — directly verified by code, migration, test, repository, or application evidence.
- `UNRESOLVED` — discussed but not completed/decided/verified.

A code change, migration file, ZIP, commit, or completion claim alone does not convert a proposal into a user decision.

## 4. Repository facts

The actual TMS codebase is in `RetodoOps/retodo-ops-site`. It contains the public site plus the TMS under `/tms` and Netlify Functions under `/netlify/functions`.

Do not use `RetodoOps/Retodo-App` for TMS work; that is a separate HR/Luma People application.

At reconciliation time:
- Update 055 source is present on `main`.
- Update 056 source is present on `main`.
- `tms/build.json` in `main` reports build `056`, release `Update 056 - Global visual system refresh`, source baseline `Update 055`.
- Context Pack v1.0 was subsequently added to `main`; v1.2 supersedes those repository context files.

Repository presence is not proof that a Supabase migration/audit was executed or that Netlify/live acceptance passed.

## 5. Change authority

- You may implement an existing `LOCKED` decision.
- You may repair bugs without changing intended business behavior.
- You may propose alternatives, clearly marked `PROPOSED`.
- Do not implement a workflow/business-policy change without explicit approval.
- If code contradicts a newer locked decision, treat the code as an implementation defect unless a newer user decision says otherwise.

## 6. Deployment safety

Unless the user explicitly changes this rule for a specific task:

- Codex may inspect/edit/test the local working tree and use a task branch/worktree.
- Do **not** push, merge, deploy Netlify, or run production migrations automatically.
- Deliver GitHub changes as one upload-only ZIP containing only complete add/replace files with paths preserved.
- State deletions separately.
- Deliver each new SQL migration as a separate forward-only `.sql` file and state execution order.
- Never ask the user to reconstruct source from snippets.
- Never include live secrets, passwords, OAuth tokens, service-role keys, bank details, or private personal data in the public repository.

## 7. Database and security

- Migrations are forward-only; never edit an already executed production migration.
- Inspect migration/schema state before running or proposing a retry.
- Preserve RLS and least privilege.
- Test both allowed and denied paths for security-sensitive changes.
- External Resources may see only their own operational data and the minimal Project/Scoop context required to work; Client/Account identity and company financials remain hidden unless explicitly authorized.

## 8. High-risk business rules not to improvise

- Registration, portal access, Compliance, agreement signing, and work eligibility are distinct.
- The exact public self-registration activation rule remains unresolved; do not invent one.
- PO issue/send implies assignment; there is no mandatory Resource PO-acceptance step.
- Only active/current PO versions belong in operational lists. Historical label wording (`Superseded`/`Overridden` or another label) is not a locked business enum unless current code and a user decision establish it.
- Do not rebuild a broad PO adjustment workflow. The current locked scope is the approved contractual reduction sentence only; financial adjustment mechanics are not authorized by that sentence.
- Agreement wording must come from the approved versioned source; do not make unsolicited legal edits.
- Compliance unlock/request is Retodo's electronic signature; the Service Provider's authenticated `Accept and sign` is the second/final signature.
- R2 lifecycle timings found in package source are implementation behavior, not automatically a locked retention policy.

## 9. UI quality gate

Do not fix only the specifically mentioned defect. Review the whole affected screen for hierarchy, spacing, alignment, containment, contrast, consistency, responsive behavior and readability.

Update 056 establishes a global visual system:
- darker bounded field surfaces;
- consistent hierarchy;
- consistent card geometry/spacing;
- compact status/date pills;
- prominent Open/Download/View/Print/Export actions;
- purple Upload actions;
- accessible `?` help tooltips;
- responsive behavior.

Admin and Resource should be tested in separate browser profiles/incognito when simultaneous sessions are needed. Update 056 also contains a role-drift guard, but separate profiles remain the recommended QA method.

## 10. Required implementation report

For each material task report:

- objective;
- branch/workstream/base commit;
- locked decisions implemented;
- changed files;
- new migration(s)/audit(s);
- environment/manual configuration;
- tests and exact results;
- manual acceptance steps;
- GitHub state;
- Netlify/live state;
- production DB state;
- unresolved risks;
- context files that require synchronization.

Do not collapse local test, GitHub commit, Netlify deployment, migration execution, and user acceptance into one status.

## 11. Context maintenance

After a material approved decision or implementation:
- update `01_DECISION_REGISTER.md`;
- update `06_CURRENT_STATE.md`;
- update `07_OPEN_ISSUES.md`;
- update the latest TMS handover;
- produce a `MASTER_DELTA_FOR_RECONCILIATION` for the primary OPS/daily Master maintainer. The primary process is the default single writer of the private Master; do not create a competing Master.

See `docs/context/11_MASTER_SYNC_POLICY.md`.
