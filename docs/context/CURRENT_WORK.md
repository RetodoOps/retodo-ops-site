# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current task: Update 071 — release corrected invoice numbers
Status: READY FOR USER INSTALLATION; production acceptance pending
Task branch: dev/update-071-invoice-number-release (local only)
Starting HEAD: 8222949 (main; Update 070 upload)
Build: 071
Last updated: 2026-10-26

## USER REQUEST AND SCOPE
- User could not issue invoice 20 after correcting the earlier invoice to 21. Screenshot error: Invoice number already belongs to another invoice or its revision.
- Root cause: invoice_numbers_062 retained every previous number, even after correction.
- User STOPPED removal of Client code. No client code changes are included. The abandoned local client-code worktree is not a continuation source.
- Continue complete-file ZIP/manual upload workflow. No assistant push, merge, deployment or production SQL/config/data changes.

## IMPLEMENTED
- Forward migration 068_invoice_number_release.sql removes only reservations that no longer match their invoice's current number. Current numbers stay reserved for every lifecycle status.
- The existing reservation trigger now claims the replacement before releasing the old number in the same transaction. Failure rolls everything back.
- Historical snapshots, invoice facts, receipts and events remain unchanged. Existing access and duplicate-current-number protections remain.
- Issuing a freed earlier number or renumbering now chooses the next unused number above the chosen number, skipping current numbers. This prevents issuing 20 from suggesting occupied 21 again.
- The migration changes only the next-number expression inside the existing issue/revise functions, with prerequisite guards. It is safe to reapply.

## VERIFIED
- 49 isolated PostgreSQL/PGlite workflow tests pass, including exact reproduction before repair, issuing 20 after 20-to-21 correction, next number 22, duplicate 21 rejection, future release, rollback after late trigger failure, preserved receipts/history/events and migration reapplication.
- Read-only audit027 returns 8 PASS. Prior invoice/report audits pass.
- Tests use the existing minimal Supabase platform fixtures and documented missing-037 audit-writer stub. No live database was changed. No frontend logic changed.

## DELIVERY / NEXT ACTION
- RetodoOps_Update_071_Invoice_Number_Release.zip contains six complete files listed in UPDATE_071_MANUAL_UPLOAD.md.
- User runs migration068, then audit027 (8 PASS), uploads files and commits. Refresh, reopen the saved draft and retry number 0000000020.
- Source main 8222949 contains Update070; production SQL acceptance is not inferred from source commit.

# PRIOR UPDATE 070 CONTEXT

Repository: RetodoOps/retodo-ops-site
Current task: Update 070 — Invoice Reports, PDF/ZIP, tax choices, editor cleanup and client creation
Status: READY FOR USER INSTALLATION — verification/package commit includes this checkpoint; production acceptance pending
Task branch: dev/update-070-invoice-report-downloads (local only)
Starting HEAD: 121731e (main; exact tree matches delivered Update 069)
Build: 070
Last updated: 2026-10-26

## LOCKED WORKFLOW
- User uploads/commits complete replacement files from ZIP. No assistant push, merge, deployment, production SQL/config/data changes or outreach.
- Forward-only SQL; preserve RLS, admin-only receipt entry, existing revisions, snapshots and numbering.
- Preserve all Sales Update 067/068 files and Update 069 draft-saving fix. Source commit does not confirm production migrations.

## IMPLEMENTED
- Compact invoice list based on user reference: checkbox, linked number, Type, linked Client, date, payment status, amount/currency, PDF download and existing payment action.
- Paid green, Unpaid red, Partially paid yellow; computed from receipts/balance. Draft/Cancelled/Annulled are neutral and excluded from payment filters. Lifecycle status remains unchanged.
- Search/filter and currency-summary panels collapse to emphasize the list. Existing sorting/paging, Excel/CSV and payment protections retained. New read-only invoice_report_070 adds payment-status filters/sorting and explicit Invoice document type. Old RPC remains intact.
- Current data model has invoices only. Type is Invoice; drafts are not proformas. User has been told that proforma creation requires a separate workflow; no proforma numbering/accounting policy invented.
- Direct, selectable-text PDFs in EN/BG, using current saved invoice details and issued snapshots; draft PDFs use current configured parties and a draft warning. Fonts and libraries are local vendor assets. No print dialog or external PDF service.
- Selection persists across pages/sorts. Applying different filters clears it. Select-page checkbox is explicit; maximum 100 invoices per ZIP. All selected documents must succeed before download; errors preserve selection and produce no partial archive. Missing BG data fails clearly, without silently switching language.
- Tax treatment dropdown has the five exact Bulgarian options from the screenshot, blank choice and Other / existing custom basis. Existing text is preserved. Selection does not change the VAT percentage or default a legal basis.

## USER ADDITIONS INCORPORATED BEFORE DELIVERY
- Browser-generated print headers/footers removed by using direct Download PDF in the invoice editor too. New native PDF has no running title/date/URL/page-number margin text.
- Tax event date removed from form, model metadata and PDF/Word, including legacy invoice downloads; immutable historical snapshots remain.
- Highlighted explanatory, duplicate status and language captions removed. Main actions use bold filled purple buttons; scoped styles override the existing automatic action-prominent styling.
- Invoice number is first and visually emphasized in the editor; issued-number changes use the existing guarded revision path. No permission/duplicate-number safeguards bypassed.
- Country code removed from Add client. Screenshot actually showed duplicate Client code MIRO; user informed, unique client codes retained, feedback now identifies the conflicting code/client.

## VERIFIED
- 43 isolated SQL workflows PASS, including payment filter/sort/role checks and prior invoice-save/revision/payment safeguards. Read-only audit026: 6 PASS. Prior invoice audits pass; new migration reapplication passes.
- Browser invoice suite PASS: tax options/custom text, native EN/BG PDF and Word without tax-event date, no noisy editor captions, filled bold buttons, number correction, edit/issue/revise/pay, QA/mobile. Client-create browser test PASS without country code and with duplicate-code handling.
- Browser report suite PASS: links, colours, payment filters, XLSX/CSV, selection across pages, real EN/BG PDF and ZIP bytes, draft PDF, missing/deleted/BG-disabled error handling, existing payment retries/stale revisions and QA/mobile.
- Operational Projects/Jobs/Margin report regression PASS. No operational report logic changed.
- Generated English/Bulgarian PDFs rendered and inspected; four-page long-row test retains all 40 rows, repeats headings and stays within page bounds. Cyrillic text extraction passes. JavaScript syntax, git diff and package checks pass.
- Database tests use PGlite and the documented missing-037 audit writer stub; browser RPCs are fixtures. No live production changes.

## DELIVERY / NEXT EXACT ACTION
Deliver RetodoOps_Update_070_Invoice_Report_PDF_Tax.zip and UPDATE_070_MANUAL_UPLOAD.md.
User runs migration067_invoice_report_downloads.sql and audit026 (6 PASS), uploads package files, deploys and refreshes Invoice/Reports to070. Prerequisite Update069 includes migrations065/066; do not replay old migrations unless they were never installed.

## RETAINED INVOICE DETAILS
Update069 fixed the unassigned sc RECORD on a first manual draft save. Existing optional BG/default preparer behavior and frozen document revisions stay unchanged. Reports cover client invoices; supplier invoices and proforma creation remain separate. Unknown payment request retries are retained only in the current page; after navigation/reload check receipt history before recording another payment.

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

## USER ADDITIONS INCORPORATED BEFORE DELIVERY
- Browser-generated print headers/footers removed by using direct Download PDF in the invoice editor too. New native PDF has no running title/date/URL/page-number margin text.
- Tax event date removed from form, model metadata and PDF/Word, including legacy invoice downloads; immutable historical snapshots remain.
- Highlighted explanatory, duplicate status and language captions removed. Main actions use bold filled purple buttons; scoped styles override the existing automatic action-prominent styling.
- Invoice number is first and visually emphasized in the editor; issued-number changes use the existing guarded revision path. No permission/duplicate-number safeguards bypassed.
- Country code removed from Add client. Screenshot actually showed duplicate Client code MIRO; user informed, unique client codes retained, feedback now identifies the conflicting code/client.

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
