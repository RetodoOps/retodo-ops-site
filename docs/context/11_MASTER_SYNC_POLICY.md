# Retodo Ops — Master / Repository Context Sync Policy

**Version:** 1.0  
**Date:** 2026-09-19

## 1. Two sources with different purposes

### Private daily Master
`Retodo_Ops_Master_Context_and_Decisions.md`

Purpose: cross-business decisions, legal/commercial context, launch/sales history, TMS history/evidence and source register.

Security: private. It may contain banking/internal contact/commercial data and must **never** be committed to the public GitHub repository.

### Repository context
`AGENTS.md` + `docs/context/`

Purpose: repo-safe instructions for Codex, stable product/business rules needed for code work, current implementation snapshot, open technical issues and parallel-work coordination.

It is an operational extraction, not a replacement for the private Master.

## 2. Start-of-session rule

For a secondary-profile Work session:
1. read the latest private Master;
2. read repository reconciliation/current-state files;
3. verify current GitHub `main` and `tms/build.json`;
4. record any mismatch before changing code.

For Codex:
- Codex reads repository instructions via `AGENTS.md`;
- give it task-specific locked decisions/non-goals;
- do not assume Codex has the private ChatGPT Project attachment.

## 3. Single-writer rule for the private Master

Default ownership of the private daily Master remains with the primary OPS Project/daily reconciliation process. This avoids two GPT profiles overwriting each other.

The secondary profile must read the current Master but should not independently create a second Master or replace it by default.

After material secondary-profile work:
1. update/prep repo-safe Decision Register/Current State/Open Issues/Handover;
2. produce the implementation evidence record;
3. produce a `MASTER_DELTA_FOR_RECONCILIATION` containing only new approved decisions, implementation evidence, supersessions, unresolved issues and source references;
4. send that delta back to the primary profile/daily reconciliation process;
5. primary reconciliation updates the same canonical Master identity/version.

Only let the secondary profile directly replace the Master when the user explicitly assigns Master ownership for that session and the latest version has been re-read immediately before writing.

## 4. Evidence discipline

Track separately:
- prepared package;
- local tests;
- GitHub commit;
- Netlify deployment;
- migration execution;
- audit output;
- live browser acceptance;
- user approval.

Never collapse these into one “done” status.

## 5. Daily drift check

Compare:
- private Master last-reviewed date;
- latest GitHub commit;
- `tms/build.json`;
- latest applied migration/audit known;
- latest accepted live test;
- latest rolling TMS handoff.

If repository implementation is newer than the Master, record the delta and update the Master. If the Master contains a newer business decision than code, treat the code as pending/defective rather than silently changing the decision.
