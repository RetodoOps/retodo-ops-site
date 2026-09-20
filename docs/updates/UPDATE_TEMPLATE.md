# UPDATE NNN — <Short title>

**Update:** `NNN`  
**Status:** `IN_PROGRESS`  
**Owner/workstream:** `<GPT / Work / Codex / user>`  
**Created:** `YYYY-MM-DD`  
**Last updated:** `YYYY-MM-DD`

> Valid work-state examples: `IN_PROGRESS`, `PARTIAL`, `BLOCKED`, `FAILED`, `NOT_TESTED`, `IMPLEMENTED`, `TESTED`, `USER_ACCEPTED`, `ROLLED_BACK`, `SUPERSEDED`.

## 1. Objective

<One concise statement of the problem/change.>

## 2. Scope

### Included

- ...

### Explicitly not included

- ...

## 3. Decision basis

### LOCKED decisions implemented

- ...

### Unresolved decisions that must not be invented

- ...

### Relevant source/context

- `AGENTS.md`
- `docs/context/CURRENT_WORK.md`
- `<other relevant file(s)>`

## 4. Starting state

- Repository: `RetodoOps/retodo-ops-site`
- Base branch: `<branch>`
- Starting HEAD: `<sha>`
- Starting build: `<build>`
- Production correlation known: `<yes/no/partial>`

## 5. Task branch

- Branch: `<dev/update-NNN-short-name>`
- Latest durable checkpoint commit: `<sha or NONE>`
- Remote pushed: `<yes/no>`

## 6. Files changed

### Added

- ...

### Replaced/modified

- ...

### Deleted

- ...

## 7. Database / migration / audit

- Migration required: `<yes/no>`
- Migration file: `<path or NONE>`
- Production execution: `<NOT RUN / REPORTED / VERIFIED>`
- Audit file/result: `<...>`

Never edit a production-executed migration.

## 8. Environment / manual configuration

- Environment-variable changes: `<none / details>`
- Netlify configuration: `<none / details>`
- Supabase configuration: `<none / details>`
- R2 configuration: `<none / details>`
- Manual steps required: `<none / details>`

## 9. Implementation checkpoints

Append material logical steps.

### Checkpoint 1 — YYYY-MM-DD HH:MM

- Action:
- Result:
- Files:
- Commit:
- Next action:

## 10. Tests

| Test | Scope | Result | Evidence / note |
|---|---|---|---|
| Example | Local | `NOT RUN` | |

Use explicit results: `PASS`, `FAIL`, `NOT RUN`, `BLOCKED`.

For security-sensitive work, include both allowed and denied paths.

## 11. Deployment state

Keep these independent:

- Local implementation: `<state>`
- Repository checkpoint: `<state>`
- Merged to `main`: `<state>`
- Netlify deployed: `<state>`
- Production migration executed: `<state>`
- Live functional acceptance: `<state>`
- User acceptance: `<state>`

Do not infer one state from another.

## 12. Known failures / incomplete work

- ...

## 13. User-confirmed working items

Only record explicit user confirmation.

- ...

## 14. Superseded / rolled-back work

- ...

## 15. Current next exact action

<Single next action another agent can execute without re-investigating the whole task.>

## 16. Do not redo

- <Already completed investigation/test that remains valid.>

## 17. Context synchronization

Update only what the task materially changes:

- [ ] `docs/context/CURRENT_WORK.md`
- [ ] `docs/context/DEV_WORKLOG.md`
- [ ] `docs/context/01_DECISION_REGISTER.md` if business-decision evidence changed
- [ ] `docs/context/06_CURRENT_STATE.md` if durable state changed
- [ ] `docs/context/07_OPEN_ISSUES.md` if issue state changed
- [ ] relevant repository handover/history if still maintained
- [ ] private Master delta needed for primary OPS process

## 18. Final status

`<IN_PROGRESS / PARTIAL / BLOCKED / IMPLEMENTED / TESTED / USER_ACCEPTED / etc.>`

Final checkpoint commit: `<sha or NONE>`

Production acceptance must not be claimed unless separately evidenced.
