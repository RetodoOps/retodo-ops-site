# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Remote baseline / starting HEAD: main `75b4b54e2f30fc010cd09dadb4f183c460e62255`
Starting remote tree: `84ddb375f3aa4c424cb0b9d7ce6537c7b6199000`
Verified current main: `b21fa1bbf1be66eb0769c672759e147268711f23`; tree `8737cbad2398a74bbc028842ed2c4e4b342aeae2`, identical to the corrected 064A implementation checkpoint.
Active local branch: `dev/update-064-sales-signature`
Latest durable checkpoint commit: `dev/update-064-sales-signature` HEAD (this AI-setup diagnostic checkpoint); corrected 064A implementation checkpoint `eb417d30135278f2bcdfe14b3ec0840197948db0`, starting main `75b4b54`.
Delivery: `RetodoOps_Update_064A_Sales_Signature_Correct_Assets.zip` — complete changed files
Build: 064A. Status: COMPLETE — USER-REPORTED LIVE ACCEPTANCE PASSED. On 2026-10-08 the user confirmed “Looking good! :) Sent and received.” after the controlled signature test instructions. Installation and received signature appearance are accepted; no signature issue is reported. Main source upload is independently verified: its entire tree matches the corrected 064A implementation. Production migration/audit execution, deployment and received-email rendering are user-reported, not independently inspected. Starting remote task HEAD for this status update: d15b65c50d0f0e104b0fd973462639e293b4979a; local starting HEAD: fadf72442412e417509c6f3dc8e7b2077d67d41f.
Last updated: 2026-10-08
Follow-on task: AI setup. The user reports “AI research is not configured. Manual Sales tools are available / Background worker configured. / Mailbox check passed.” Source confirms the first message is raised when OPENAI_API_KEY is absent or empty in the running functions. Other AI settings have not yet been evaluated because this guard runs first. Starting remote task HEAD for this diagnostic checkpoint: 17521afdf4bebee2d935d7a945766af523d879fb; local HEAD: c85f65da51f8512d8791623a21177c6e112d732e.

## USER WORKFLOW — LOCKED

- Deliver complete changed files in a ZIP at repository-root paths. The user uploads to main and commits directly. Include this CURRENT_WORK.md in each package.
- Current session instructions authorize code + CURRENT_WORK checkpoints on a non-main task branch. This supersedes the older ZIP-only no-push instruction; ZIP delivery remains required. Do not merge or push application work to main, deploy production, run production SQL or change production configuration/data. Do not send real prospect mail during development.
- Do not read AGENTS.md or reopen old/private context packs. Read current source and task-relevant installation guides only.
- Preserve RLS, least privilege and forward-only migrations. Do not reconstruct missing historical migrations or commit private material.
- Local Git was reconstructed from 244 hash-verified Update 062 blobs; snapshot root `3e8e5ed` is not remote history. Never push that reconstructed history. Save the task branch using the canonical remote parent/tree and only the reviewed signature file overlay.
- Main advanced to `75b4b54` (063C enquiry UX/baseline repair) while signature work was in progress. Restored hash-verified `contact.html`, `script.js` and `UPDATE_063C_MANUAL_UPLOAD.md`; integrated current build/context metadata. Preserve the corrected short-details message and working anti-spam code. Resumed local HEAD was `f69cb1f`.

## CURRENT TASK — UPDATE 064A SALES SIGNATURE BRAND CORRECTION

LATEST USER CORRECTION: the previously supplied teal repository logo is not the correct asset. Use https://drive.google.com/drive/folders/1mclWAmQ8SckGcPpJmmVevWXQaPxyOUG_ instead. Retrieved and inspected the multicolour 600×600 network logo and company cover in 01 Brand assets. Logo file id: 1DRLqtJZ4tSKqBIDd98LSECaSY3C9XU8v; SHA-256 747a6f6ef984b726bb5efa86737e513dc76b16296453099d28b090fc47cc4890. The supplied bytes are unchanged and displayed at 48×48 beside the company name. Matching navy/blue styling replaces teal for renderer 2.

APPROACH SELECTED / IMPLEMENTED: preserve renderer 1 exactly for existing saved/approved/sent messages, add renderer 2 with supplied assets, and create forward-only migration 060. The migration upgrades the current template version while retaining custom text and inclusion/logo toggles. It does not rewrite message/approval snapshots. New tabs can review both versions; old tabs cannot approve an unseen renderer 2 signature. Source assets in Drive are unchanged. The earlier Update 064 download is superseded by the complete 064A package (21 files); do not install the old package as the final version.

USER REQUEST: create Eli’s signature, then add the Sales option. Include “Best Regards,” name, position, company logo smaller than the attached example, website link, LinkedIn shortcut and a shorter confidentiality note. No address/location. The attachment was recovered and used as a layout reference.

- Supplied closing/name: Best Regards, / Eli Stoyanova.
- Position: Business Development & Client Relations Coordinator. This is from an earlier assistant signature draft, not a newly confirmed official title. The Settings field is editable.
- Website: https://retodo-ops.com/
- LinkedIn: https://www.linkedin.com/in/eli-stoyanova-667831410/ — the user’s previously supplied Eli profile. A proposed custom LinkedIn slug was never confirmed and is not used. No company LinkedIn URL was verified.
- Current logo: supplied multicolour PNG, unchanged bytes, displayed at 48 × 48 px. The earlier teal 110 × 35 logo is retained ONLY inside the frozen renderer 1 for saved message history. All new templates use renderer 2.
- Note: “This email and any attachments are confidential. If received in error, please notify the sender and delete them.”
- No postal address or geographical claim appears.

IMPLEMENTED:
- Sales → Settings → Eli’s email signature: editable closing, position, website, LinkedIn and short note; compact-logo toggle; default inclusion toggle; live preview and Save signature button. This button submits the current Sales settings form.
- New initial messages, follow-ups and replies have individual Include Eli’s signature controls and Preview complete email. AI drafting asks for body-only email text, preserving the opt-out sentence.
- Each saved draft captures a structured, versioned signature. Batch review and conversation history display that captured copy. Settings changes do not alter existing draft/approved/sent messages.
- Edit draft → Signature offers keep saved, use current or no signature. Existing edit/version guards revoke approvals. New-signature approvals require the preview version marker, so a stale older tab must refresh before approving unseen content.
- Forward-only migration `059_sales_email_signatures.sql` adds settings/message columns and strict validators, updates the existing admin command, and retains migration 058’s corrected server worker while adding a signature-versus-approval check immediately before sending.
- `tms/sales-signature.js` is the shared versioned renderer. Renderer 1 with the earlier logo remains frozen for already saved/approved/sent messages; renderer 2 embeds the supplied Drive logo and is the current template. Both browser preview and Sales MIME use the same renderer. Keep both versions stable in later work; introduce a new renderer version when changing a reviewed layout.
- MIME contains HTML/plain-text alternatives, with the logo embedded inline by Content-ID and user attachments kept separate. Legacy messages without a captured signature keep their original body. No external tracking image or remote logo fetch.
- Signature text is escaped, links are restricted to HTTPS website and LinkedIn profile/company URLs, and raw HTML is not configurable.
- Build 064A and Sales asset cache references updated. Operational Gmail, supplier PO, general sender, finance modules and the public enquiry anti-spam implementation are unchanged.

DELIVERY:
- 21 complete files in the ZIP, enumerated in `UPDATE_064_MANUAL_UPLOAD.md`.
- Standalone self-contained signature preview: `docs/sales/Eli_Stoyanova_Sales_Signature.html`.
- Read-only audits: `tms/audits/019_update_064_sales_signature_audit.sql` (12 PASS rows) and `tms/audits/020_update_064a_sales_brand_assets_audit.sql` (9 PASS rows).
- Nothing has been deployed or applied to production by the assistant.

## VERIFIED IN THIS UPDATE

- PASS: 49 actual SQL workflow checks (35 previous + 9 signature + 5 supplied-brand-asset cases). Covers migration preservation, strict settings/role boundaries, new/per-message signature capture, immutable approval snapshots, renderer-version approval, edits requiring reapproval, replies, stale frontend rejection, legacy compatibility, mismatched signature rejection and reapplication.
- PASS: 31 base Sales + 11 worker correction + 12 signature + 9 supplied-brand-asset audit checks.
- PASS: 41 service/worker/diagnostic tests (32 existing + 6 signature/MIME + 3 supplied-brand-asset tests). Independent Python email parser verifies MIME nesting, decoded text/logo/attachment bytes, Unicode, thread headers, safe content, exact supplied-logo bytes and legacy behavior.
- PASS: Chromium fixture workflow for settings/live preview/save with supplied logo, per-email inclusion, complete batch previews, captured vs current signature, edit choices, reply payload, mobile, XSS and prior navigation/materials/attachment flows. Desktop/mobile screenshots inspected.
- Real worker + actual SQL uses intercepted Gmail: one send, thread polling, reply import and follow-up cancellation without duplicates. This now exercises HTML/signature MIME too.
- SQL replay uses PGlite with Supabase platform stubs, available schema through 038 (explicit unrelated missing-037 audit-writer stub) and relevant 050/053/054/055/056/057/058/059/060. No full historical replay is claimed.
- No live email, paid AI, production SQL or deployment was performed by the assistant. The corrected non-main implementation checkpoint is saved at `eb417d3`. The user accepted the received signature on 2026-10-08; no cross-client rendering matrix is claimed.

RESUME CHECKPOINT (2026-10-07): retrieved and inspected the supplied Drive brand assets; integrated the exact 600×600 logo into renderer 2; re-ran all 41 service/MIME tests, 49 SQL workflow checks and 63 audit rows, all PASS. Browser fixture workflow passed with the corrected compact logo and current approval marker. The standalone preview was rendered and inspected. The non-main checkpoint is saved; the final ZIP contains 21 complete files. All 260 unchanged main blobs were hash-verified against current main 75b4b54.

INSTALLATION CHECKPOINT (2026-10-07): user confirmed “done.” GitHub main advanced to `b21fa1b` with message “Add files via upload / RetodoOps_Update_064A_Sales_Signature_Correct_Assets”; its tree `8737cba` exactly matches the corrected implementation checkpoint `eb417d3`. Record installation as user-reported complete, with source upload verified. Do not ask the user to repeat migrations, audits, upload or deployment confirmation.

LIVE ACCEPTANCE CHECKPOINT (2026-10-08): user confirmed “Looking good! :) Sent and received. What's next?” The corrected signature is accepted following the received-email test. Main remains `b21fa1b`; no further signature implementation or testing is pending. User now requests the next Sales step. AI connection readiness, live prospect research and generated draft acceptance remain unconfirmed; the next recommendation is to check Connections before a small research/drafting pilot. No paid AI task, live outreach or production configuration change was initiated by the assistant.

## CHANGED FILES

The 21 complete 064A files are enumerated in `UPDATE_064_MANUAL_UPLOAD.md`. The three 063C files restored from main are baseline preservation only and are included where required to preserve the current main tree.

This AI-setup diagnostic checkpoint changes only `docs/context/CURRENT_WORK.md`; no new installation package is needed.

## REQUIRED CONTEXT

NONE for normal continuation. For installation, use `UPDATE_064_MANUAL_UPLOAD.md` only.

## DO NOT REDO

Do not recreate the signature implementation or repeat completed tests without a concrete new risk. Do not repeat the user-confirmed 064A migration/audit/upload/deployment steps or ask for another deployment confirmation. Do not rerun OAuth, worker-secret setup, basic delivery/reply acceptance or the accepted live signature test. Do not revert the 063C enquiry correction or push reconstructed Git history.

## NEXT EXACT ACTION

AI SETUP DIAGNOSIS (2026-10-08): the code is installed; no application change is indicated by the reported message. A server-side OpenAI project API key is required, with API billing available. Do not request or place the secret in chat or repository files. In Netlify, use the TMS project's Project configuration → Environment variables, with a Production value available to Functions (or All scopes when scope selection is unavailable). A new deploy is required for function environment changes to take effect.

Reviewed official documentation on 2026-10-08: GPT-4.1 mini input $0.40 and output $1.60 per million tokens; non-preview web search $0.01 per call plus search-content tokens (8,000 input tokens per call for this model). Existing adapter/defaults match these prices. Sources: https://developers.openai.com/api/docs/models/gpt-4.1-mini ; https://developers.openai.com/api/docs/pricing ; https://developers.openai.com/api/docs/quickstart ; https://docs.netlify.com/build/environment-variables/get-started/ ; https://docs.netlify.com/build/functions/environment-variables/ .

Proposed next steps:
1. Keep automatic research off while configuring. Create/use a dedicated OpenAI project API key and add OPENAI_API_KEY to the function environment. Ensure API billing is available. Do not change the accepted mailbox settings.
2. Set SALES_AI_PRICING_REVIEWED_ON=2026-10-08, SALES_AI_INPUT_USD_PER_MILLION=0.40, SALES_AI_OUTPUT_USD_PER_MILLION=1.60 and SALES_AI_SEARCH_USD_PER_CALL=0.01. Proposed initial SALES_AI_EUR_PER_USD=1.25 is a conservative internal budget allowance, not a verified currency conversion or invoice total; compare it against actual billing conditions and increase it if necessary. These are instructions/recommendations, not settings already applied or approved by the user. The review date expires after 30 days.
3. After the user's normal deployment, refresh Sales → Settings → Connections. “AI is configured.” checks local configuration only; it does not test whether the key, permissions, credits or provider request work. The first controlled research run is still needed for live API acceptance.
4. Review Target clients → Research brief and Approved company facts → Facts the writing assistant may use. Retain the €30 monthly ceiling and review the allowance before paid research.
5. Once configured, use Find prospects for one on-demand research batch of up to five companies. Review evidence, company duplicates and suggested contacts; suggested emails remain unverified until checked.
6. Prepare one personalized outreach draft and follow-ups for review before expanding the first batch. Sending remains subject to the existing explicit batch-approval workflow. Keep automatic research off until the first result has been reviewed.

These are recommended next steps, not a record that AI configuration, paid research or prospect outreach has been executed or separately authorized by “What's next?”.

Existing approved messages are not retrofitted. To add a signature to an old unsent draft, use Edit draft → Signature → Use current Sales signature → Save draft, then review/approve again. Do not change Gmail defaults or restart OAuth troubleshooting for this feature.

## USER-REPORTED LIVE SALES ACCEPTANCE — PASSED 2026-10-07 / 2026-10-08

- Mailbox check passed: primary account `aleksandra.a@retodo-ops.com`; Sales sender `eli.s@retodo-ops.com`.
- The worker secret was corrected after being too short; background processing now starts.
- Migration 058 corrected the original SQLSTATE 42702 `c.*` polling ambiguity.
- The test email was successfully sent and received. From and Reply-To were correct.
- Reply detection and follow-up cancellation were checked; the user confirmed “Yes, correct.”
- Corrected 064A signature sent and received successfully, with appearance accepted: “Looking good! :) Sent and received.” (2026-10-08).
- Do not treat basic delivery/reply testing or OAuth as an unresolved blocker.
- AI status checked 2026-10-08: OPENAI_API_KEY is unavailable to the deployed functions; worker configured and mailbox passed. AI setup instructions are the next action. Live research and generated draft acceptance remain pending. The signature task is complete.

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
