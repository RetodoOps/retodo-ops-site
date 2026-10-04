# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Remote baseline: main `0a79fe42b30e02c31edc11329da42027a4d2ec8d` / Update 062
Remote tree: `b592a056f927913f1acdf9b26110a7ec6730290f`
Active local branch: `dev/update-063-sales`
Delivery: Update 063 complete-file ZIP; ready for user installation
Local build: 063. Production installation/acceptance: not yet verified.
Last updated: 2026-10-04

## USER WORKFLOW — LOCKED

- Deliver complete changed files in a ZIP, preserving repository-root paths. The user uploads to main and commits directly.
- Do not push, merge, create PRs, deploy, run production SQL or change production configuration/data. Local task-branch commits are allowed.
- Include CURRENT_WORK.md with each package. Preserve RLS and least privilege. Migrations are forward-only; do not reconstruct absent historical migrations or commit private material.
- Git transport was unavailable. All 244 baseline files were fetched at the pinned remote commit and verified against their Git blob hashes. Local snapshot root `3e8e5ed` is not remote Git history. Never push this reconstructed branch.
- Main was rechecked read-only on 2026-10-04 and remained at the baseline above. Update 062 code is present; its production migration/acceptance has not been verified and no failure was reported.

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
- No production migration, deployment, live Google OAuth check, actual email, paid AI call or production acceptance occurred.

## NEXT EXACT ACTION

The user installs the complete Update 063 ZIP using `docs/sales/UPDATE_063_INSTALL_AND_TEST.md`: confirm installed 062/056, run migration 057, require all audit 017 checks PASS, upload/commit the complete files and configure server-side connections. Run the controlled-address acceptance pilot before real outreach. Both sending and scheduled research install disabled.

Gmail requires send plus read access; the actual primary account may differ from both From aliases. Set `SALES_GMAIL_ACCOUNT_EMAIL` to that account. Do not redo the alias or change the general sender. Configure a random worker secret; configure optional AI credentials, reviewed prices and a conservative currency/tax allowance. No secrets belong in chat or source.

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
