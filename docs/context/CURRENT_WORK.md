# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current task: Update 069 — repair manual draft saving and include undelivered invoice Update 067
Status: READY FOR USER INSTALLATION — combined complete-file ZIP; no production actions performed
Task branch: dev/update-069-invoice-draft-fix (local only)
Starting HEAD: 0ff1c19 (main, Sales Update 068)
Build: 069
Last updated: 2026-10-26

## LOCKED WORKFLOW
- Complete replacement files in repository-root ZIP; user uploads/commits.
- No assistant push, merge, deployment, production SQL/configuration/data changes or prospect outreach.
- Forward-only migrations; preserve RLS, roles, payment protections, immutable snapshots and all Sales Update 067/068 files.
- User has NOT uploaded the separately delivered Invoice Update 067 ZIP. That older ZIP is superseded by this combined Update 069, because main now uses 067/068 for Sales.

## CURRENT FINDING AND REPAIR
- User's invoice UI is Update 066. Saving a manual-only draft fails with `record "sc" is not assigned yet`.
- Reproduced exact error on the first manual save in a fresh SQL session. Earlier tests warmed the function by saving Scoops first, masking the unassigned-record planning error.
- New migration 066 replaces only invoice_save_061. Each row resets a typed project UUID to NULL; only the Scoop branch assigns it. The INSERT never references unassigned sc. Existing validations, locks, events and roles remain intact.
- Combined package imports undelivered optional BG/defaults/Invoice Reports work, rebased onto current main without overwriting Sales.
- Invoice Reports migration renamed from undelivered 063_invoice_reports.sql to 065_invoice_reports.sql. RPC identifiers remain unchanged for compatibility. Sales migrations 063/064 are untouched.
- New audit024 checks Reports (7 PASS); audit025 checks draft repair (7 PASS).

## VERIFICATION
- 42 isolated SQL workflow checks PASS, including exact pre-fix reproduction, cold manual-only save/update, three rows totalling EUR 2230, manual rows before/after a Scoop, issued revisions, payment idempotency and role protections.
- Invoice audits021/022/024/025 PASS; repair reapplication leaves invoice data unchanged.
- All three invoice/report/operational Reports browser suites PASS; JavaScript syntax, diff and ZIP verification PASS.
- SQL uses PGlite and the documented missing-037 audit writer stub; browser checks use fixture RPCs. Production acceptance remains the user's step.

## NEXT EXACT ACTION
Deliver RetodoOps_Update_069_Invoice_Draft_Fix_Reports.zip with UPDATE_069_MANUAL_UPLOAD.md.
Immediate unblock: user may run migration066 then audit025 on installed invoice066, without installing Reports first. Retry Save draft without refreshing the unsaved editor.
Full install: migrations065 then066, audits024 then025, upload all ZIP files and refresh to069. Do not upload the superseded Invoice Update067 package.

## INVOICE BEHAVIOR RETAINED
New BG version optional/off; Recipient English defaults to Client name, preparer defaults Demir Atanasov / Демир Атанасов unless an explicit setting exists. Existing documents stay frozen. Reports lists invoice links, currency-separated balances and guarded admin payment entry. Unknown payment retries retain request only in the current page; after reload check history before recording again. Client invoices only.

## SALES CONTEXT RETAINED FROM MAIN 0ff1c19
Main contains Sales Update 068; production SQL acceptance is not inferred from source commit. The following Sales decisions/findings remain authoritative; do not rerun paid research or change automatic research in this invoice task.

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

## RETAINED SALES NEXT ACTION (CONFIRM INSTALLATION SEPARATELY)

The user uploads Update 068, runs migration 064 and audit 022, deploys and confirms build 068 with Research still On demand. Then inspect the already-completed Update 067 result counters via Sales → Today → Research & writing → Prospect research → View result. Do not run another paid research task or generate outreach until Update 068 is installed.

## DO NOT REDO

Do not re-run migration 063 as a substitute for 064, re-enable automatic research, import historical personal emails, describe any prospect as a previous Retodo client, generate outreach before Update 068, or change/remove Update 066 invoice files.
