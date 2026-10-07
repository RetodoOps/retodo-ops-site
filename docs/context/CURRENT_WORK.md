# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Remote baseline: main `1233887f2093934b17c7260cc21d0c550301f2bc` / Update 063A
Remote tree: `b27bf4baf93bf1ba4f6ab41f9426b9e2d5af7799`
Active local branch: `dev/update-063b-worker-sql`
Delivery: Update 063B worker SQL correction complete-file ZIP
Local build: 063. Mailbox check passed; worker reached a SQL ambiguity before sending.
Last updated: 2026-10-06

## USER WORKFLOW — LOCKED

- Deliver complete changed files in a ZIP, preserving repository-root paths. The user uploads to main and commits directly.
- Do not push, merge, create PRs, deploy, run production SQL or change production configuration/data. Local task-branch commits are allowed.
- Include CURRENT_WORK.md with each package. Preserve RLS and least privilege. Migrations are forward-only; do not reconstruct absent historical migrations or commit private material.
- Git transport was unavailable. All 244 original Update 062 baseline files were fetched at the pinned commit and verified against their Git blob hashes. Local snapshot root `3e8e5ed` is not remote Git history. Never push this reconstructed branch.
- Main was rechecked read-only on 2026-10-06 at the Update 063A commit above. The affected Sales files and CURRENT_WORK match the delivered local Update 063A checkpoint `10366ab`; migration numbering currently ends at 057. No remote writes were performed.

## CURRENT TASK — UPDATE 063B WORKER SQL CORRECTION

- USER-REPORTED: mailbox connection passed for primary account `aleksandra.a@retodo-ops.com`, Sales sender `eli.s@retodo-ops.com`. The earlier token diagnosis is no longer the active blocker.
- The user confirmed `SALES_WORKER_SECRET` was shorter than the required 32 characters and was instructed to replace it. Their next screenshot showed mailbox and worker times at 2026-10-06 19:48 Sofia, sending enabled, one approved queued message, one draft awaiting review, zero sent messages and `column reference "c.*" is ambiguous` under Automation.
- VERIFIED: migration 057 declares local conversation record `c` and reuses `c` as a table alias in the worker RPC's `threads` query. The original SQL reproduces the screenshot's exact SQLSTATE 42702 error. Earlier SQL tests did not call that action; worker JavaScript tests mocked the RPC, leaving this integration gap.
- Migration `058_sales_worker_thread_polling.sql` replaces the complete `sales_system_063` function with only the thread query alias/qualification corrected. No Sales rows or settings are changed. Migration 057 remains unchanged; no frontend, Netlify function, environment variable or build-number change is needed.
- PASS: 35 actual database/workflow checks, including original failure reproduction, corrected polling with empty and populated queues, state filters/order/limit, role boundaries, all existing 28 cases and row preservation on reapplication. The real worker/helper + actual SQL with intercepted Gmail sends once, imports a reply, cancels follow-ups and does not duplicate sends or replies. All 31 existing and 11 new audit checks pass.
- Package five complete files in `RetodoOps_Update_063B_Worker_SQL_Fix.zip`: migration 058, audit 018, the updated SQL test, `docs/sales/UPDATE_063B_WORKER_SQL_FIX.md` and this context. No production SQL, deployment, email or paid AI call was performed by the assistant. Live delivery remains unverified.

## COMPLETED UPDATE 063A — MAILBOX DIAGNOSTICS

- The user saved Sales setup, company facts and the target brief, but originally Check mailbox connection returned the generic Sales error. Today → Automation showed “Google mail authorization failed. Reconnect the mailbox with the required scopes”, placing that failure at the access-token exchange before account/alias checks.
- The user used the existing OAuth web client and OAuth Playground redirect, authorized send/read scopes, exchanged an authorization code and saved a refresh token in Netlify. The exact deployed values and authenticated primary mailbox have not been independently verified. Repeating Exchange returned Bad request; authorization codes are single-use, so that repeat is not a refresh-token test.
- The Gmail helper previously discarded Google's specific OAuth code; the general redactor then hid its authorization message. New Sales-only, allowlisted diagnostics identify token/client/configuration/API/scope/account/alias failures without returning raw provider descriptions, response bodies or secret values. Surrounding configuration whitespace is trimmed; quoted/JSON/internal-whitespace values are rejected before contacting Google.
- Changed code: `netlify/functions/_shared/sales-gmail.js`, `netlify/functions/sales.js`; new helper: `netlify/functions/_shared/sales-diagnostics.js`. Existing frontend displays the returned message; no frontend/cache/build change or migration is needed. General Gmail, supplier PO, shared redaction and sender settings are unchanged.
- PASS: 13 new end-to-end mocked diagnostic cases, 14 service cases and 5 worker/API cases (32 total); JavaScript syntax, whitespace and unchanged operational-helper checks. No live OAuth, mail, paid AI, production configuration or deployment was performed for this fix.
- Delivered six complete changed files in `RetodoOps_Update_063A_Mailbox_Diagnostics.zip`; the user uploaded them to main and subsequently reported a passing mailbox check. The diagnostic helper remains installed.

## UPDATE 063 — AGREED SCOPE

The user approved the Sales v1 specification and implementation. The pilot is admin-only, with batch review before sending and a €30 monthly starting incremental Sales ceiling.

Every Sales From and Reply-To is Eli Stoyanova `<eli.s@retodo-ops.com>`. The user created/configured that alias and confirmed completion. Preserve the general Gmail default Retodo Ops `<ops@retodo-ops.com>`, reply-from-received-address preference and existing operational helpers. No real prospect sending was authorized during development.

## IMPLEMENTED

- Additive migration 057: 12 Sales tables; admin RLS and guarded RPCs; immutable approvals/activity; company/contact evidence and deduplication; one open approach per company; exact draft-version batch approval; edits revoke approvals; suppression; Client conversion; tasks/materials; durable AI jobs and cost reservations.
- Isolated Sales Gmail helper: accepted alias/primary-account/read-scope checks, fixed Eli headers, thread replies, pre-send sync, separate-thread delivery failure/new-subject reply matching, RFC message-ID reconciliation. Ambiguous sends are never automatically retried. Existing `_shared/gmail.js` and supplier PO sending are unchanged.
- Admin API, secret-protected background worker and five-minute scheduler. Global worker lease, per-message claims, database validation immediately before send and default ten/day sending limit. Replies stop follow-ups; OOO/manual replies pause; opt-outs/bounces suppress. Follow-up dates use actual initial send time and Sofia weekdays.
- AI adapter: `gpt-4.1-mini`, structured results, public source evidence, unverified suggested emails, no automated LinkedIn contact action, durable conservative reservations, 30-day pricing review and hold on underestimated usage. €30 ceiling includes entered other costs and reserve; it is not a guaranteed external invoice cap.
- Sales tabs: Today, Prospects, Batch review, Conversations, Materials, Settings. Existing TMS styling and admin navigation. Exact batch confirmation, attachments, contact verification, LinkedIn tasks, editable replies, Client linking, mobile layout and escaped untrusted content.
- Materials: manual/AI content, slide preview, editable PowerPoint via local PptxGenJS 4.0.1 with included MIT license, Markdown export and browser print/PDF.
- Build 063, audit 017, complete installation/acceptance guide, focused regression tests. Operational HTML changes only refresh the shared navigation script reference.

## VERIFICATION

- PASS: 28 actual SQL workflow cases, covering role restrictions, sender/approval immutability, edit/stale guards, duplicate prevention, leases, uncertain sends, timing, synchronization, suppression, conversion, budgets, tasks and materials.
- PASS: migration 057 reapplication and all 31 read-only audit 017 checks.
- PASS: 14 service tests, including MIME/Unicode headers, exact sender, Gmail account/read checks, separate-thread replies/bounces, source validation and AI pricing/cost failures.
- PASS: 5 worker/API tests, including JWT/admin and worker-secret boundaries, durable queueing, fresh sync and unknown-send behavior.
- PASS: Chromium fixture workflow for navigation, sequence/attachment payloads, exact/stale batch approval, conversation UI, material preview/PPTX export, settings-edit preservation, search, XSS escaping, mobile and QA denial. Desktop/mobile screenshots inspected. Exported PPTX XML, content and embedded logo inspected; desktop PowerPoint rendering unverified.
- JavaScript syntax, package completeness and diff whitespace checked during final packaging.
- Browser service responses are mocked; SQL is exercised separately with PGlite. Historical tests replay available schema through 038, explicitly stub the unrelated missing 037 audit writer, then apply relevant 050/053/054/055/056/057. Missing 037/040 are not reconstructed. This is not a full historical replay.
- Those developer checks were isolated; the user has since installed the release and reported a successful live mailbox check. No email or paid AI call was made by the assistant. The controlled delivery/reply pilot remains incomplete.

## NEXT EXACT ACTION

Follow `docs/sales/UPDATE_063B_WORKER_SQL_FIX.md`: pause sending while installing; run the complete migration 058 and read-only audit 018 in Supabase (all 11 rows PASS), then upload/commit all five complete files through the user-controlled workflow. Re-enable sending for the existing controlled test, select Today → Check now and refresh. Check the new Worker time/error and actual test delivery, From/Reply-To, reply detection and follow-up cancellation. Do not recreate queued messages or rerun migration 057. Uploading files alone does not apply this SQL correction.

The successful mailbox check identifies the actual primary account as `aleksandra.a@retodo-ops.com`; Sales From/Reply-To remain the Eli alias. The worker now starts, so do not restart OAuth/worker-secret troubleshooting for the SQL error. Optional AI credentials/pricing remain a separate acceptance step. Refresh connection status currently has no completion notice when status is unchanged; that usability issue is not part of the SQL correction. No secrets belong in chat or source.

If the user reports installation failures, fix the concrete failure first. Do not restart implementation, reopen approved batch/budget/sender decisions or request push permission. Keep the complete-file ZIP workflow.

## PILOT LIMITS / LATER WORK

- One open conversation per company; exact normalized name/domain/email checks rather than fuzzy corporate identity resolution. Administrators review renamed companies and aliases.
- Polling is not instant; a reply can arrive after the final check and before Gmail accepts the send. OOO requires manual review/resumption. No inbound attachment storage, tracking pixels or automated LinkedIn actions.
- Sales uses its own prospect search; operational shared search does not index Sales yet. Prospects page by 50, review/conversation lists by 100; full selected-company history remains available.
- Unknown AI usage keeps its reservation. A budget hold requires evidenced administrator reconciliation; the guide describes the recovery workflow. No UI for settling uncertain AI charges is included.
- Rate/resource matching, commercial proposals/quote creation, broader roles and native Google Slides integration remain later scope. No production rendering claim for PowerPoint.

## RETAINED 061/062 BUSINESS DECISIONS

- Client invoices can include selected approved Scoops across Projects; eligible Scoops may be selected by client PO, with row corrections/deletion and manual rows. Client payment days determine due date.
- Update 062 permits admin-only, reasoned official invoice revisions with previous snapshots and financial safeguards. This supersedes the prior issued-edit lock. Keep receipts, issuer metadata, number ownership, client/currency and total-at-least-receipts protections.
- Reports Projects view has one row per Scoop and page sizes 25/50/100/250 (default 50). Typed XLSX is default; CSV optional. User accepted 061 Excel export.
- EUR reporting uses a traceable dated ECB snapshot, with missing rates/costs explicit. Unknown costs are not zero; provisional profit differs from final margin. Do not invent Job revenue allocation.
- Invoiced/Paid Scoop display is derived from invoices/receipts, separate from stored operational approval. Preserve 062 shared search, exact Scoop priority and restored Invoice navigation.
- Supplier invoice cycle remains the 15th/last working day with 60 calendar days from cycle date; implementation is follow-up scope. Credit notes/annulment, bank FX differences and separate Invoice Reports also remain later work.
- Use the 062 installation guide only when needed for baseline installation details. Do not reopen broad old/private context packs, signing, invitations, Compliance or unrelated reconciliation. Never invent issuer/legal/bank/tax configuration.
