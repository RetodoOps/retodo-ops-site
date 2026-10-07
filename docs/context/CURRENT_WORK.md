# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Remote baseline / starting HEAD: main `75b4b54e2f30fc010cd09dadb4f183c460e62255`
Remote tree: `84ddb375f3aa4c424cb0b9d7ce6537c7b6199000`
Active local branch: `dev/update-064-sales-signature`
Latest durable checkpoint commit: `dev/update-064-sales-signature` HEAD (this file’s containing checkpoint); implementation commit `bcb34e2f58504d00931304bedff11d942c3cf20b`, parent main `75b4b54`.
Delivery: `RetodoOps_Update_064_Sales_Signature.zip` — complete changed files
Build: 064. Status: READY FOR USER INSTALLATION. Signature implementation, tests and review are complete; production installation and received-email signature check are pending.
Last updated: 2026-10-07

## USER WORKFLOW — LOCKED

- Deliver complete changed files in a ZIP at repository-root paths. The user uploads to main and commits directly. Include this CURRENT_WORK.md in each package.
- Current session instructions authorize code + CURRENT_WORK checkpoints on a non-main task branch. This supersedes the older ZIP-only no-push instruction; ZIP delivery remains required. Do not merge or push application work to main, deploy production, run production SQL or change production configuration/data. Do not send real prospect mail during development.
- Do not read AGENTS.md or reopen old/private context packs. Read current source and task-relevant installation guides only.
- Preserve RLS, least privilege and forward-only migrations. Do not reconstruct missing historical migrations or commit private material.
- Local Git was reconstructed from 244 hash-verified Update 062 blobs; snapshot root `3e8e5ed` is not remote history. Never push that reconstructed history. Save the task branch using the canonical remote parent/tree and only the reviewed signature file overlay.
- Main advanced to `75b4b54` (063C enquiry UX/baseline repair) while signature work was in progress. Restored hash-verified `contact.html`, `script.js` and `UPDATE_063C_MANUAL_UPLOAD.md`; integrated current build/context metadata. Preserve the corrected short-details message and working anti-spam code. Resumed local HEAD was `f69cb1f`.

## CURRENT TASK — UPDATE 064 SALES SIGNATURE

USER REQUEST: create Eli’s signature, then add the Sales option. Include “Best Regards,” name, position, company logo smaller than the attached example, website link, LinkedIn shortcut and a shorter confidentiality note. No address/location. The attachment was recovered and used as a layout reference.

- Supplied closing/name: Best Regards, / Eli Stoyanova.
- Position: Business Development & Client Relations Coordinator. This is from an earlier assistant signature draft, not a newly confirmed official title. The Settings field is editable.
- Website: https://retodo-ops.com/
- LinkedIn: https://www.linkedin.com/in/eli-stoyanova-667831410/ — the user’s previously supplied Eli profile. A proposed custom LinkedIn slug was never confirmed and is not used. No company LinkedIn URL was verified.
- Logo: unchanged existing PNG bytes, displayed at 110 × 35 px. The linked logo and text website link point to the same site. LinkedIn is a readable text shortcut.
- Note: “This email and any attachments are confidential. If received in error, please notify the sender and delete them.”
- No postal address or geographical claim appears.

IMPLEMENTED:
- Sales → Settings → Eli’s email signature: editable closing, position, website, LinkedIn and short note; compact-logo toggle; default inclusion toggle; live preview and Save signature button. This button submits the current Sales settings form.
- New initial messages, follow-ups and replies have individual Include Eli’s signature controls and Preview complete email. AI drafting asks for body-only email text, preserving the opt-out sentence.
- Each saved draft captures a structured, versioned signature. Batch review and conversation history display that captured copy. Settings changes do not alter existing draft/approved/sent messages.
- Edit draft → Signature offers keep saved, use current or no signature. Existing edit/version guards revoke approvals. New-signature approvals require the preview version marker, so a stale older tab must refresh before approving unseen content.
- Forward-only migration `059_sales_email_signatures.sql` adds settings/message columns and strict validators, updates the existing admin command, and retains migration 058’s corrected server worker while adding a signature-versus-approval check immediately before sending.
- `tms/sales-signature.js` is the shared version 1 renderer with the original logo embedded. Both browser preview and Sales MIME use it. Keep version 1 rendering and assets stable in later work; introduce a new renderer version when changing the reviewed layout.
- MIME contains HTML/plain-text alternatives, with the logo embedded inline by Content-ID and user attachments kept separate. Legacy messages without a captured signature keep their original body. No external tracking image or remote logo fetch.
- Signature text is escaped, links are restricted to HTTPS website and LinkedIn profile/company URLs, and raw HTML is not configurable.
- Build 064 and Sales asset cache references updated. Operational Gmail, supplier PO, general sender, finance modules and the public enquiry anti-spam implementation are unchanged.

DELIVERY:
- 17 complete files in the ZIP, enumerated in `UPDATE_064_MANUAL_UPLOAD.md`.
- Standalone self-contained signature preview: `docs/sales/Eli_Stoyanova_Sales_Signature.html`.
- Read-only signature audit: `tms/audits/019_update_064_sales_signature_audit.sql` (12 PASS rows).
- Nothing has been deployed or applied to production by the assistant.

## VERIFIED IN THIS UPDATE

- PASS: 44 actual SQL workflow checks (35 previous + 9 signature cases). Covers migration preservation, strict settings/role boundaries, new/per-message signature capture, immutable approval snapshots, template changes, edits requiring reapproval, replies, stale frontend rejection, legacy approval compatibility, mismatched signature rejection and reapplication.
- PASS: 31 base Sales + 11 worker correction + 12 signature audit checks.
- PASS: 38 service/worker/diagnostic tests (32 existing + 6 signature/MIME tests). Independent Python email parser verifies MIME nesting, decoded text/logo/attachment bytes, Unicode, thread headers, safe content and legacy behavior.
- PASS: Chromium fixture workflow for settings/live preview/save, per-email inclusion, complete batch previews, captured vs current signature, edit choices, reply payload, mobile, XSS and prior navigation/materials/attachment flows. Desktop/mobile screenshots inspected.
- Real worker + actual SQL uses intercepted Gmail: one send, thread polling, reply import and follow-up cancellation without duplicates. This now exercises HTML/signature MIME too.
- SQL replay uses PGlite with Supabase platform stubs, available schema through 038 (explicit unrelated missing-037 audit-writer stub) and relevant 050/053/054/055/056/057/058/059. No full historical replay is claimed.
- No live email, paid AI, production SQL or deployment was performed. The authorized non-main implementation checkpoint is saved at `bcb34e2`. Recipient Gmail/Outlook signature rendering is still a user acceptance check.

RESUME CHECKPOINT (2026-10-07): recovered the completed implementation and reference image; re-ran all 38 service/MIME tests and 44 SQL workflow checks plus 54 audit rows, all PASS. Inspected desktop Settings/batch previews. No feature rewrite was required. The standalone preview was rendered and inspected. The non-main checkpoint is saved; the final ZIP contains the same 17 complete signature files. All 260 unchanged main blobs were hash-verified against current main 75b4b54.

## CHANGED FILES

The 17 complete signature files are enumerated in `UPDATE_064_MANUAL_UPLOAD.md`. The three 063C files restored from main are baseline preservation only and are not part of the signature overlay.

## REQUIRED CONTEXT

NONE for normal continuation. For installation, use `UPDATE_064_MANUAL_UPLOAD.md` only.

## DO NOT REDO

Do not recreate the signature implementation or repeat completed tests without a concrete new risk. Do not rerun OAuth, worker-secret setup or basic delivery/reply acceptance. Do not revert the 063C enquiry correction or push reconstructed Git history.

## NEXT EXACT ACTION

Follow `UPDATE_064_MANUAL_UPLOAD.md`:
1. Sales → Settings → Outreach: clear Allow approved messages to send and save.
2. Run the complete new migration 059 in Supabase SQL Editor, then audit 019 (12 PASS rows). Do not rerun older 057/058 afterward.
3. Upload/commit all 17 complete files through the user-controlled workflow; after the normal deployment, hard-refresh Sales.
4. Open Settings → Eli’s email signature, review the editable title/links and Save signature.
5. Use Draft reply in the existing conversation with the controlled test address, preview and approve that one message, enable sending and Check now. Verify the received signature and links. Return sending to the desired pilot state.

Existing approved messages are not retrofitted. To add a signature to an old unsent draft, use Edit draft → Signature → Use current Sales signature → Save draft, then review/approve again. Do not change Gmail defaults or restart OAuth troubleshooting for this feature.

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
- EUR reporting uses a dated traceable ECB snapshot; missing rates/costs are explicit. Unknown costs are not zero. Provisional profit and final margin differ; do not invent Job revenue allocation.
- Invoiced/Paid Scoop status is derived from invoices/receipts, separate from operational approval. Preserve 062 shared search, exact Scoop priority and restored Invoice navigation.
- Supplier invoice cycle remains the 15th/last working day with 60 calendar days from cycle; implementation is later scope. Credit notes/annulment, bank FX differences and separate Invoice Reports are also later scope.
- No invented issuer/legal/bank/tax configuration or reopening signing, invitations, Compliance and unrelated reconciliation.

## SALES PILOT LIMITS / LATER WORK

- Polling is not instant; replies can arrive after the final check. OOO needs manual review/resumption.
- No automated LinkedIn messages, inbound attachment storage or tracking pixels.
- Sales search remains separate from operational shared search. Current list paging/limits remain.
- No UI to settle uncertain AI charges; use the existing documented evidenced administrator recovery process.
- Broader roles, commercial quoting/proposals, rate/resource matching and native Google Slides integration remain later work.
