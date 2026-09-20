# Retodo Ops AI Context Pack — Start Here

**Version:** 1.2  
**Reconciled:** 2026-09-19

This repository pack is the AI-readable technical/operational context for the Retodo Ops TMS. It is designed for parallel use by a secondary ChatGPT profile and Codex Desktop.

## Important: two context layers

There are two different context layers and they should not be confused:

1. **Private daily Master:** `Retodo_Ops_Master_Context_and_Decisions.md`
   - cross-business source covering Retodo Ops, launch, legal/commercial rules, TMS history and evidence;
   - updated daily;
   - contains internal information and must **not** be copied into the public GitHub repository.

2. **Repository context pack:** `AGENTS.md` + `docs/context/`
   - repo-safe operational extraction for Codex and development sessions;
   - contains no live secrets/bank data;
   - must be reconciled when the private Master or implementation state changes materially.

## Verified repository

The TMS codebase is:

`RetodoOps/retodo-ops-site` → branch `main`

It contains the public website and the TMS under `/tms`.

`RetodoOps/Retodo-App` is a different HR/Luma People application and is not the TMS repository.

## Current repository state at reconciliation

- Update 055 source exists on `main`.
- Update 056 Global Visual System source exists on `main`.
- `tms/build.json` reports build `056` with source baseline Update 055.
- The original Context Pack v1.0 was also added to `main`.
- This v1.2 pack supersedes those context files.

This proves repository source state, not production database migration/audit execution or live Netlify acceptance.

## First use in the secondary profile

Create/open a **Retodo Ops Project** in the secondary ChatGPT account and upload the current private Master plus the secondary-profile handoff bundle. Start a **Work chat inside that Project** for substantial coordination/QA tasks.

Codex remains a separate software-development surface. Open the local clone of `RetodoOps/retodo-ops-site` in Codex; `AGENTS.md` supplies the repository instructions.

Use `docs/context/09_SECOND_PROFILE_BOOTSTRAP_PROMPT.md` as the first Work message.

## Security

Do not put the private daily Master in this public repository. Never place passwords, tokens, bank details, service-role keys, OAuth secrets, or private contact data in repo context.
