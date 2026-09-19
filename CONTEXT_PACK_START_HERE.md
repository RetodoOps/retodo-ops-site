# Retodo Ops AI Context Pack — Start Here

This package is designed to let a second ChatGPT profile and Codex Desktop work on Retodo Ops TMS without relying on the memory of one account.

## Install into the TMS repository

Copy:

- `AGENTS.md` to the repository root.
- `docs/context/` into the repository.

Do not place the package into a repository until you have confirmed it is the actual TMS codebase.

The GitHub connection inspected while creating this package exposed `RetodoOps/Retodo-App`, but that repository currently appeared to contain HR/Luma People code. It is therefore intentionally **not** hard-coded as the TMS repo.

## First use

1. Open the TMS repository in Codex Desktop.
2. Let Codex read `AGENTS.md`.
3. In the secondary ChatGPT profile, use `docs/context/09_SECOND_PROFILE_BOOTSTRAP_PROMPT.md` as the first prompt.
4. Start each workstream on a separate branch.
5. Keep material decisions synchronized back to `01_DECISION_REGISTER.md`.

## Canonical precedence

Newest explicit user instruction → newer LOCKED decision → Current State → Master Context → latest handover → older history.

## Security

This pack contains no live secrets and must remain that way.
