# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current task: Update 065 — standalone client invoices and Bulgarian/PDF/Word downloads
Status: READY FOR USER INSTALLATION — complete-file ZIP built; production acceptance pending
Task branch: dev/update-065-invoice-downloads (local)
Starting HEAD: b21fa1bbf1be66eb0769c672759e147268711f23 (main, build 064A)
Latest durable checkpoint: packaging commit containing this record; prior verified checkpoint 2476c54
Build: 065 locally; main baseline 064A
Last updated: 2026-10-15

## LOCKED RULES
- Deliver complete changed files in a ZIP. User uploads/commits to main. No assistant push/merge/deployment/production SQL/configuration/data changes for this task.
- Update this record at material checkpoints and commit locally. Preserve current Sales signature and public enquiry changes.
- Standalone invoices select an existing Client, keep client payment terms and billing entity, accept manual rows with no Scoop or Project. Existing number prompt, roles, revision/payment protections remain.
- Download language selector English/Bulgarian for PDF and real editable .docx. Translate document labels, dates and number formatting; preserve entered descriptions, notes, names, tax basis and bank details. No invented translations or legal/tax facts.

## FINDINGS / APPROACH
- Main b21fa1b has Sales 064A but invoice files are still 062; invoice/report Update 064 ZIP was not uploaded to this main. Do not confuse Sales migration 058 with invoice-fix migration 058 from that ZIP.
- Existing invoice_save_061 already supports manual-only invoices. Frontend create action is blocked by required Scoop selection. Add separate New invoice without Scoops dialog with Client/currency/number.
- Recover only invoice frontend/revision/payment/deletion prerequisites from local completed Update 064; publish invoice-only forward migration 061 with unique filename. Preserve existing Reports SQL and UI from main.
- Use a shared localized document model for PDF and Word so both reflect saved invoice data. Vendor DOCX browser library locally with license; no invoice data sent to an external converter.

## COMPLETED / CHANGED FILES
- Baseline inspected; local worktree created from current origin/main.
- Standalone client/currency/number dialog, localized PDF and DOCX download controls implemented.
- New invoice-document.js shares saved facts across formats; DOCX 9.6.1 vendored with license.
- Invoice-only 064 recovery delivered under migration 061 and audit 021; no Reports/Sales overwrite.
- Changed: invoice.js/html/css, invoice-document.js, vendor/docx*, migrations/061*, audits/021*, build.json, tests/update-065-*, this record and UPDATE_065_MANUAL_UPLOAD.md.
- All 14 package files are complete additions/replacements. Main rechecked unchanged at b21fa1b on 2026-10-15.
- Desktop/mobile UI and final English/Bulgarian document pages inspected; DOCX ZIP/XML checks pass including actual browser downloads.

## TEST RESULTS
- PASS 32 isolated SQL workflow checks: manual-only save/issue/revise/pay/delete, tax totals, client due date, no Scoop mutations, later Scoop addition, duplicate/permission/revision guards, existing payment/deletion regression. Migration 061 reapplication passes.
- PASS audit 021: 15 checks.
- PASS Chromium fixture suite: standalone dialog, saved manual row, English/Bulgarian native Word downloads, localized PDF, unsaved-download guard, existing selection/revisions/full-partial payment/deletion, QA read-only and mobile.
- PASS native DOCX generation and rendering: English and Bulgarian single-page samples; Bulgarian 65-row / five-page document. Fixed split invoice rows; repeated table headers and all pages inspected.
- Test infrastructure only: corrupt cached Chromium restored from packaged compressed bytes; SQL allocation assertion uses owner role without changing production privileges. No functional failures remain.
- JS syntax passes. SQL uses PGlite with explicit missing-037 audit stub; browser uses fixture RPCs, production acceptance and desktop Microsoft Word checks remain user steps.

## UNRESOLVED / INCOMPLETE
Production installation and desktop Microsoft Word acceptance pending.
Older Reports 064 fixes are absent on main; do not silently claim installed. Not part of this invoice-only package.

## REQUIRED CONTEXT
UPDATE_065_MANUAL_UPLOAD.md for installation/acceptance only.

## NEXT EXACT ACTION
User runs migration 061, audit 021 (15 PASS), uploads the 14 complete ZIP files, commits and refreshes Client invoices to Update 065. Test standalone creation and both download languages/formats as described in UPDATE_065_MANUAL_UPLOAD.md.

## DO NOT REDO
Do not redo Sales, OAuth, signatures, public enquiry protection, full context reconciliation or previously accepted Reports exports. No production actions.

## USER-REPORTED LIVE SALES ACCEPTANCE — PASSED 2026-10-07

- Mailbox check passed: primary account `aleksandra.a@retodo-ops.com`; Sales sender `eli.s@retodo-ops.com`.
- The worker secret was corrected after being too short; background processing now starts.
- Migration 058 corrected the original SQLSTATE 42702 `c.*` polling ambiguity.
- The test email was successfully sent and received. From and Reply-To were correct.
- Reply detection and follow-up cancellation were checked; the user confirmed “Yes, correct.”
- Do not treat basic delivery/reply testing or OAuth as an unresolved blocker.
- Optional AI configuration and live research acceptance remain unconfirmed and separate from the signature task.

## INSTALLED SALES BASELINE — 063 / 063A / 063B

The pilot is admin-only with exact batch review before sending and a €30 starting monthly incremental Sales ceiling. Every Sales From/Reply-To is Eli Stoyanova <eli.s@retodo-ops.com>. General Gmail remains Retodo Ops <ops@retodo-ops.com> with its existing reply preference and operational helpers.

- Migration 057: 12 Sales tables, admin RLS/guarded RPCs, immutable approvals/events, evidence and deduplication, one open company approach, suppression, Client conversion, tasks/materials, durable AI jobs and conservative cost reservations.
- Isolated Sales Gmail helper: accepted alias/primary mailbox checks, fresh reply checks, same-thread and separate-thread reply/bounce handling, stable Message-ID reconciliation. Ambiguous sends are not automatically retried.
- Admin API, secret-protected worker and five-minute scheduler; global/message leases, pre-send database checks and default 10/day limit. Replies cancel follow-ups; manual Gmail replies/OOO pause; opt-outs/bounces suppress. Business days use Sofia weekdays from actual initial send.
- AI uses structured research/drafts/materials, approved company facts, public source evidence and unverified suggested emails. LinkedIn contact actions remain manual. Budget includes entered other costs/reserve; unknown usage keeps reservations and may hold spending.
- Sales tabs: Today, Prospects, Batch review, Conversations, Materials, Settings. Materials provide editable pitches/decks, local PowerPoint export, Markdown and print/PDF.
- 063A mailbox diagnostics expose allowlisted actionable Google error codes while keeping secrets/raw provider errors hidden.
- 063B migration 058 fixes only the server polling query alias. Current 059 retains this correction.

## RETAINED PUBLIC ENQUIRY ANTI-SPAM WORK

Main’s 2026-10-07 06:35:50Z commit uploaded the older named Update 061 anti-spam package after Sales 063B. It retained Sales files/migration 058 but replaced CURRENT_WORK/build metadata with stale 061 text. This document reconciles the two workstreams; build 064 now describes the latest change.

Preserve `contact.html`, root `script.js`, `netlify/functions/submit-project-enquiry.js` and `UPDATE_061_MANUAL_UPLOAD.md` from that main upload, with the later 063C corrections at `75b4b54`. 063C adds the browser minimum of 10 characters and `Project details are too short.` feedback, restores build 063 and repairs continuity. Public project enquiries use Turnstile, plus existing honeypot/origin checks and Gmail delivery; required language/wordcount/deadline validations remain. The user reported a valid enquiry was sent and received. Live 063C browser feedback was not independently rechecked during this signature task.

## RETAINED 061/062 BUSINESS DECISIONS

- Client invoices can include selected approved Scoops across Projects, with PO-based selection, row correction/deletion and manual rows. Client payment days determine due date.
- Update 062 permits admin-only, reasoned official invoice revisions with previous snapshots and financial safeguards; preserve receipts, issuer metadata, number ownership, client/currency and total-at-least-receipts protections.
- Reports Projects view is one row per Scoop, with page sizes 25/50/100/250 (50 default). Typed XLSX is default and CSV optional.
- EUR reporting uses a dated traceable ECB snapshot; missing rates/costs are explicit. Latest user rule is that empty supplier prices count as EUR 0; the separately delivered Reports 064 implementation remains absent from main and is not included in this invoice-only update. Provisional profit and final margin differ; do not invent Job revenue allocation.
- Invoiced/Paid Scoop status is derived from invoices/receipts, separate from operational approval. Preserve 062 shared search, exact Scoop priority and restored Invoice navigation.
- Supplier invoice cycle remains the 15th/last working day with 60 calendar days from cycle; implementation is later scope. Credit notes/annulment, bank FX differences and separate Invoice Reports are also later scope.
- No invented issuer/legal/bank/tax configuration or reopening signing, invitations, Compliance and unrelated reconciliation.

## SALES PILOT LIMITS / LATER WORK

- Polling is not instant; replies can arrive after the final check. OOO needs manual review/resumption.
- No automated LinkedIn messages, inbound attachment storage or tracking pixels.
- Sales search remains separate from operational shared search. Current list paging/limits remain.
- No UI to settle uncertain AI charges; use the existing documented evidenced administrator recovery process.
- Broader roles, commercial quoting/proposals, rate/resource matching and native Google Slides integration remain later work.
