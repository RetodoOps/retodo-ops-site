# Retodo Ops TMS Context Directory

This directory is the canonical, AI-readable project memory for parallel work across ChatGPT profiles, Codex Desktop, and future development sessions.

## Files

- `00_MASTER_CONTEXT.md` — stable company/TMS context and overall product model.
- `01_DECISION_REGISTER.md` — material decisions with status and precedence.
- `02_TMS_ARCHITECTURE.md` — entities, ownership, workflows, security boundaries, integrations.
- `03_BUSINESS_RULES.md` — operational and commercial rules.
- `04_UI_UX_RULES.md` — canonical visual and interaction rules.
- `05_DEVELOPMENT_RULES.md` — coding, migration, testing, packaging and deployment rules.
- `06_CURRENT_STATE.md` — current known implementation state.
- `07_OPEN_ISSUES.md` — unresolved bugs, missing tests and backlog.
- `08_PARALLEL_WORKFLOW.md` — coordination protocol for multiple GPT/Codex workstreams.
- `09_SECOND_PROFILE_BOOTSTRAP_PROMPT.md` — first prompt for a new ChatGPT profile.
- `10_SECRET_REFERENCES.md` — secret-handling policy and reference registry (never actual values).
- `handovers/TMS4_CURRENT_HANDOVER.md` — current TMS4 handover.
- `handovers/TMS_TMS2_TMS3_CONSOLIDATED_HISTORY.md` — historical continuity and supersessions.

## Maintenance rule

Material decisions must not remain only in chat. Once approved, add them to `01_DECISION_REGISTER.md` and update the current-state/open-issues files.

## Conflict rule

Newest explicit user instruction wins. After that, newer `LOCKED` decisions take precedence over older documentation and implementation.
