# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Current task: Update 066 — reference invoice layout and Bulgarian issuer details
Status: READY FOR USER INSTALLATION — verified complete-file package; production acceptance pending
Task branch: dev/update-066-invoice-layout (local)
Starting HEAD: 3e90411b25bb3cf868a8754aae1fdaa483f70374 (main, Update 065)
Build: 066 locally; main 065
Latest checkpoint: verification/package commit containing this record; scope checkpoint 34af9d4
Last updated: 2026-10-16

## LOCKED RULES
- Deliver complete changed files in a ZIP. User uploads/commits to main. No assistant push/merge/deployment/production SQL/configuration/data changes.
- Keep local checkpoints and this record. Preserve Sales, Reports and public enquiry changes.
- Match supplied invoice layout in PDF and editable Word. Bulgarian output uses separate Bulgarian issuer fields. Preserve entered recipient, descriptions, tax basis and bank account; no guessed translations or tax facts.
- Existing issued snapshots remain frozen. Adding Bulgarian issuer text to an old invoice requires an explicit admin revision with reason/history.

## FINDINGS / APPROACH
- Main includes Update 065 standalone/BG/Word at 3e90411. No need to replay or overwrite earlier fixes.
- Previous transient 066 workspace disappeared; rebuild from main and saved scope, rerun verification.
- Reference supplier: Ретодо ЕООД, ул. Светла 48А, ап. 23 / София / България; ЕИК 208524462; Обединена българска банка АД; Демир Атанасов. Optional fill button affects text only, requires matching configured registration and explicit save.
- Never copy screenshot recipient, invoice number, dates, line items, tax basis or bank account into live data.

## COMPLETED / TEST RESULTS
- Shared reference layout implemented in PDF and native Word; separate Bulgarian issuer fields and reference-text fill with matching-registration gate.
- Migration 062 adds optional document metadata and guarded save/revision wrappers. Old snapshots change only through explicit admin revision; previous full snapshot and payments retained.
- 34 SQL workflow checks PASS; audit021 15 PASS, audit022 9 PASS; migration reapplication PASS.
- Browser fixture suite PASS: settings fill/save, standalone manual metadata, English/Bulgarian Word, BG print, explicit issuer revision, payments/deletion, QA and mobile.
- Native DOCX rendered: EN/BG single pages and all five pages of a 65-row document inspected. Browser PDF inspected. No clipping or row/header problems.
- JS syntax and diff checks PASS. No production operations. PGlite test uses documented missing-037 audit stub; browser uses fixture RPCs.
- Main rechecked at 3e90411 before packaging. Complete files only; no vendor duplication or Sales/Reports changes.

## UNRESOLVED / REQUIRED CONTEXT
User production installation and desktop Microsoft Word acceptance remain pending. Use UPDATE_066_MANUAL_UPLOAD.md for installation steps.

## NEXT EXACT ACTION
User runs migration062, audit022 (9 PASS), uploads/commits ZIP files, refreshes to066, fills and saves BG settings. For existing issued invoices, select explicit BG issuer copy and Save revision with a reason.

## DO NOT REDO
No Sales, OAuth, signatures, public enquiry, Reports changes or broad context reconciliation. No production actions.

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
