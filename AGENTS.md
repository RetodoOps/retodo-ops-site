# Retodo Ops TMS — Agent Instructions

**Context Pack version:** 1.3  
**Continuity protocol introduced:** 2026-09-20  
**Repository:** `RetodoOps/retodo-ops-site`  
**Default branch:** `main`  
**Production TMS origin:** `https://tms.retodo-ops.com/`

## 1. Mandatory startup sequence

Do not restart the project from chat memory and do not require an end-of-session handoff.

Before changing code, schema, UI, workflows, permissions, emails, PDFs, pricing, statuses, business logic, or context documentation:

1. Read this `AGENTS.md`.
2. Read `docs/context/CURRENT_WORK.md`. This is the mandatory operational continuation point.
3. Inspect the current repository state: repository/remote, branch, HEAD, working tree, and `tms/build.json`.
4. Read the relevant latest file under `docs/updates/` if `CURRENT_WORK.md` references one.
5. Read only the repository context files directly relevant to the current task.
6. Read the private `Retodo_Ops_Master_Context_and_Decisions.md` only when:
   - `CURRENT_WORK.md` or the relevant update file identifies a conflict;
   - a business/legal decision is unclear;
   - two sources disagree;
   - the task requires decision provenance that is not adequately recorded in repository context;
   - or the user explicitly asks for a Master-level reconciliation.
7. For UI work, also read `docs/context/04_UI_UX_RULES.md`.
8. For implementation work, also read `docs/context/05_DEVELOPMENT_RULES.md`.

Do not spend a session re-reading the full private Master by default. `CURRENT_WORK.md` + the relevant update record + relevant repository context are the normal continuation path.

If `CURRENT_WORK.md` says `IN_PROGRESS`, `PARTIAL`, `FAILED`, `BLOCKED`, or `NOT_TESTED`, do not assume the previous task is complete.

## 2. Authority and conflict resolution

Use this precedence when sources conflict:

1. The user's newest explicit instruction.
2. The exact wording of the currently approved legal/source document when working on that document.
3. The newest applicable decision/evidence in the private daily `Retodo_Ops_Master_Context_and_Decisions.md`, when available and needed.
4. Current repository/schema/application behavior as implementation evidence only. A bug is not automatically an approved business rule.
5. Newer `LOCKED` entries in this repository context pack.
6. `docs/context/06_CURRENT_STATE.md`.
7. The relevant current update record / latest handover.
8. Older implementation reports/history.

`CURRENT_WORK.md` and `DEV_WORKLOG.md` are operational continuity records, not independent business-policy authority.

Never silently reinterpret a `LOCKED` decision. Record unresolved conflicts.

## 3. Evidence and work-state labels

Use these decision/evidence labels consistently:

- `LOCKED` — explicitly decided/approved by the user.
- `SUPERSEDED` — replaced by a later decision.
- `PROPOSED` — suggested but not approved.
- `IMPLEMENTED-REPORTED` — reported implemented/deployed but not independently verified.
- `VERIFIED` — directly verified by code, migration, test, repository, or application evidence.
- `UNRESOLVED` — discussed but not completed/decided/verified.

Operational work-state labels are separate:

- `IN_PROGRESS`
- `PARTIAL`
- `BLOCKED`
- `FAILED`
- `NOT_TESTED`
- `IMPLEMENTED`
- `TESTED`
- `USER_ACCEPTED`
- `ROLLED_BACK`

A code change, migration file, ZIP, commit, completion claim, or `IMPLEMENTED` work-state label alone does not convert a proposal into a user decision or prove production acceptance.

## 4. Repository facts

The actual TMS codebase is in `RetodoOps/retodo-ops-site`. It contains the public site plus the TMS under `/tms` and Netlify Functions under `/netlify/functions`.

Do not use `RetodoOps/Retodo-App` for TMS work; that is a separate HR/Luma People application.

Continuity baseline at protocol introduction:
- `main` HEAD: `21e9ff676f5a1815368b9537859dc62430becaa9`.
- `tms/build.json` reports build `056`, release `Update 056 - Global visual system refresh`, source baseline `Update 055`.
- Update 053, 054, 055 and 056 source presence has been independently confirmed in repository history.
- Agreement two-party signing and both Admin/Resource final signed-PDF download paths are USER-CONFIRMED WORKING as of 2026-09-20.
- Resource access invitation delivery is USER-CONFIRMED WORKING as of 2026-09-20.

Repository presence is not proof that a Supabase migration/audit was executed or that Netlify/live acceptance passed for unrelated functionality.

Always prefer the live repository state over this baseline if HEAD/build moved later.

## 5. Change authority

- You may implement an existing `LOCKED` decision.
- You may repair bugs without changing intended business behavior.
- You may propose alternatives, clearly marked `PROPOSED`.
- Do not implement a workflow/business-policy change without explicit approval.
- If code contradicts a newer locked decision, treat the code as an implementation defect unless a newer user decision says otherwise.

## 6. Crash-safe continuity protocol

The project must remain recoverable even if usage credits expire mid-task. Do not rely on a final session handoff.

### Before material work

1. Determine or create the task/update identifier.
2. Ensure `docs/context/CURRENT_WORK.md` names:
   - current task;
   - status;
   - task branch;
   - starting HEAD;
   - latest durable checkpoint commit;
   - build;
   - changed files;
   - completed checks;
   - incomplete checks;
   - next exact action.
3. For a numbered TMS update, create/update `docs/updates/UPDATE_NNN.md` from `docs/updates/UPDATE_TEMPLATE.md`.

### During work

After every material logical step — not every keystroke:

1. Update `docs/context/CURRENT_WORK.md`.
2. Append the action/result to `docs/context/DEV_WORKLOG.md`.
3. Update the relevant `docs/updates/UPDATE_NNN.md`.
4. Commit the code and continuity records together.
5. Push the checkpoint to the current non-main development branch.

A material logical step includes, for example:
- completing source inspection and identifying root cause;
- implementing one coherent fix;
- creating a migration;
- completing a test group;
- discovering a blocking failure;
- changing the agreed implementation plan because of evidence.

### If work is interrupted

The last pushed checkpoint commit on the task branch is the durable continuation point.

The next agent must:
1. inspect that branch/commit and working state;
2. read `CURRENT_WORK.md`;
3. read the relevant update file;
4. continue from `Next exact action`;
5. not restart the investigation unless the recorded evidence is inconsistent.

### When switching tasks

Before replacing `CURRENT_WORK.md` with another task:
- append the previous task's final/interrupted state to `DEV_WORKLOG.md`;
- ensure its update file contains the latest durable status;
- preserve unresolved items explicitly.

## 7. Git and deployment safety

The user authorizes crash-safe checkpoint commits and pushes **only to a non-main development/task branch**.

Allowed without additional approval:
- inspect/edit/test local working tree;
- create/use a task branch or worktree;
- commit material checkpoints;
- push those checkpoints to the same non-main task branch;
- update continuity documentation on that branch.

Not authorized without explicit user approval:
- push directly to `main`;
- merge into `main`;
- open/merge a pull request that changes `main`;
- deploy Netlify/production;
- run production migrations;
- change production environment variables;
- modify production data or authentication configuration.

If the current workflow is manual GitHub upload rather than direct branch push:
- deliver one upload-only ZIP containing only complete add/replace files with paths preserved;
- include the updated continuity files in that package;
- state deletions separately;
- deliver each new SQL migration as a separate forward-only `.sql` file and state execution order.

Never ask the user to reconstruct source from snippets.

Never include live secrets, passwords, OAuth tokens, service-role keys, bank details, private personal data, or the private Master in the public repository.

## 8. Database and security

- Migrations are forward-only; never edit an already executed production migration.
- Inspect migration/schema state before running or proposing a retry.
- Preserve RLS and least privilege.
- Test both allowed and denied paths for security-sensitive changes.
- External Resources may see only their own operational data and the minimal Project/Scoop context required to work; Client/Account identity and company financials remain hidden unless explicitly authorized.

## 9. High-risk business rules not to improvise

- Registration, portal access, Compliance, agreement signing, and work eligibility are distinct.
- The exact public self-registration activation rule remains unresolved; do not invent one.
- PO issue/send implies assignment; there is no mandatory Resource PO-acceptance step.
- Only active/current PO versions belong in operational lists. Historical label wording (`Superseded`/`Overridden` or another label) is not a locked business enum unless a user decision establishes it.
- Do not rebuild a broad PO adjustment workflow. The current locked scope is the approved contractual reduction sentence only; financial adjustment mechanics are not authorized by that sentence.
- Agreement wording must come from the approved versioned source; do not make unsolicited legal edits.
- Compliance unlock/request is Retodo's electronic signature; the Service Provider's authenticated `Accept and sign` is the second/final signature.
- R2 lifecycle timings found in package source are implementation behavior, not automatically a locked retention policy.
- Current freelancer invoicing rule is the 15th and the last working day of the month, with undisputed amounts payable within 60 calendar days from the applicable invoicing date. Preserve `15th and 30th` only as explicitly historical/superseded or as a legacy UI/data discrepancy.

## 10. UI quality gate

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

## 11. Update records

Every material numbered update should have one file:

`docs/updates/UPDATE_NNN.md`

Use `docs/updates/UPDATE_TEMPLATE.md`.

The update record must distinguish:
- proposed scope;
- implementation;
- local test results;
- repository checkpoint;
- Netlify deployment;
- production migration execution;
- live acceptance;
- user acceptance.

Never collapse these into one status.

Do not delete failed or interrupted history. Mark it accurately.

## 12. Required implementation reporting

Do not depend on being able to produce a final chat handoff.

The durable report is the repository continuity state:
- `docs/context/CURRENT_WORK.md`;
- `docs/context/DEV_WORKLOG.md`;
- relevant `docs/updates/UPDATE_NNN.md`;
- checkpoint commits on the task branch.

If a final chat response is possible, keep it concise and report:
- current branch and checkpoint commit;
- status;
- tests completed;
- next action;
- whether anything requires user approval.

## 13. Context maintenance

After a material approved decision or implementation:
- update `docs/context/01_DECISION_REGISTER.md` when business-decision evidence changed;
- update `docs/context/06_CURRENT_STATE.md` when durable current state changed;
- update `docs/context/07_OPEN_ISSUES.md` when an issue was opened/resolved/reclassified;
- update the relevant numbered update record;
- update `CURRENT_WORK.md` and append `DEV_WORKLOG.md`.

The private Master remains the cross-business canonical decision/evidence register and is maintained separately by the primary OPS process. Do not create or commit a competing private Master.

See `docs/context/11_MASTER_SYNC_POLICY.md`.

## 14. Continuity quality rule

A continuation record is useful only if another agent can resume without guessing.

Before each checkpoint, ask:
- What exactly is working now?
- What exactly changed?
- What has actually been tested?
- What is still untested or broken?
- What branch/commit contains the durable state?
- What is the single next action?

If any answer is missing, update `CURRENT_WORK.md` before checkpointing.
