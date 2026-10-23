# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current task: Update 068 — cold-prospect confidentiality guard
Status: READY FOR USER INSTALLATION — verified complete-file package; no production actions performed by Codex
Baseline: Update 067 installed and its first controlled research test completed
Local branch: `dev/update-064-sales-signature` on reconstructed history; never push this history
Build: 068 locally; installed build 067
Last updated: 2026-10-23

## LOCKED WORKFLOW

- Deliver complete changed files in a repository-root ZIP. The user uploads/commits to main.
- Do not push, merge, deploy, run production SQL, change production configuration/data or send prospect outreach.
- Preserve Update 066 invoice work and all Update 067 prospect data, Sales signature, Gmail, Reports and public-enquiry behavior.
- Database migrations are forward-only. Preserve RLS, least privilege, approvals, suppressions and immutable history.

## USER CLARIFICATION

The supplied historical lists record engagement through another company owned by the user, not through Retodo Ops. This relationship cannot be disclosed. All Sales prospects must be treated as first-time cold prospects to Retodo Ops.

Historical rows may remain confidential internal training/ranking and canonicalization material. They must never appear or be implied in prospect notes, generated drafts, LinkedIn text, capability materials or outreach.

## ACCEPTANCE FINDING

The first controlled Update 067 research result returned Baltic Media, Business Team Translations and Jensen Localization.

- Baltic Media: qualified on current public external-capacity and Nordic evidence.
- Jensen Localization: qualified, but the historical relationship must not be recorded or referenced; treat as cold.
- Business Team Translations: remains at research. Its cited careers page proves an external translator network but not current Nordic demand; its original Nordic rationale was inferential.
- Automatic research remains off.

## IMPLEMENTED — UPDATE 068

- Forward-only migration `064_sales_cold_prospect_guard.sql` upgrades the buyer profile to version 2, enforces cold-only handling, leaves automatic research off and scrubs confidential relationship language from the Update 067 seed plus the known Jensen note.
- Update 067 seed fit text is replaced with public-only reasons without changing stages, contacts, conversations or user workflow history.
- Research now requires current official evidence of both external-capacity sourcing and Nordic-language demand. Certifications, age, size and broad European coverage alone are explicitly insufficient.
- Result validation requires both signals in each fit statement and rejects confidential relationship wording.
- Writing requests exclude free-form prospect fit notes/notes and pass only public identity fields with fixed `outreach_mode: cold`.
- Draft and material validation fails closed if generated content implies prior work, orders, projects, clients, collaboration or another relationship.
- Sales research/writing dialogs state the cold-only rule.

## VERIFIED

- 44 service, worker, diagnostic, signature and brand tests pass, including new cold-context stripping and weak-evidence rejection tests.
- 57 database workflow checks pass. Read-only audits pass, including the 10-row Update 068 audit, migration reapplication, profile v2, seeded-text cleanup, Jensen cleanup, retained workflow rows and automatic research off.
- Browser fixture passes with build 068 assets and prior Sales behavior retained.
- ZIP contents are complete repository-root files and hash-checked against the verified working tree.

## DELIVERY

- `RetodoOps_Update_068_Cold_Prospect_Guard.zip` — 14 complete files listed in `UPDATE_068_MANUAL_UPLOAD.md`.
- Installation: upload files, run migration 064, run audit 022 (10 PASS), deploy and hard-refresh.

## RETAINED UPDATE 066 / 067 WORK

Do not overwrite or remove Update 066 invoice migration, audit, PDF/Word layout, Bulgarian issuer settings or invoice revision safeguards. Preserve Update 067 migration 063, the 26 canonical seed records, four unverified public role contacts, truthful research counters and service-only `sales_system_067`.

## NEXT EXACT ACTION

The user uploads Update 068, runs migration 064 and audit 022, deploys and confirms build 068 with Research still On demand. Then inspect the already-completed Update 067 result counters via Sales → Today → Research & writing → Prospect research → View result. Do not run another paid research task or generate outreach until Update 068 is installed.

## DO NOT REDO

Do not re-run migration 063 as a substitute for 064, re-enable automatic research, import historical personal emails, describe any prospect as a previous Retodo client, generate outreach before Update 068, or change/remove Update 066 invoice files.
