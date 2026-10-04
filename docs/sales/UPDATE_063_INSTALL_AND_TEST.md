# Update 063 — Sales pilot

Prepared 2026-10-04 for Retodo Ops TMS, based on main `0a79fe42b30e02c31edc11329da42027a4d2ec8d` / Update 062. This ZIP contains complete changed files with repository paths. Installation, the GitHub commit and production configuration remain with the user. Nothing has been deployed, sent to prospects or charged to an AI account during development.

## Install in this order

1. Confirm Update 062 and migration 056 are installed. The repository contains them, but production database installation and user acceptance have not been verified here. Use the existing `docs/reports/UPDATE_062_INSTALL_AND_TEST.md` if necessary; do not rerun unrelated historical migrations.
2. In Supabase SQL Editor, run `tms/migrations/057_sales_workspace.sql`. It adds the Sales tables, permissions and RPCs. Both sending and scheduled research start **off**. It does not seed prospects or alter operational Gmail configuration.
3. Run `tms/audits/017_update_063_sales_audit.sql`. All **31** results must be **PASS** before continuing.
4. Extract the ZIP and upload its complete files into the matching repository-root paths. Include root `netlify.toml`, `netlify/`, `tms/`, `tests/` and `docs/`; do not nest everything inside another Update 063 folder. Commit through the normal user-controlled workflow.
5. Set the function environment variables below in the production Netlify configuration, then deploy the uploaded files through the existing workflow. Retain existing values unless a documented connection change is needed. Never place secrets in repository files, browser code or chat.
6. Sign in as an enabled administrator and open **Sales → Settings**. Run **Check mailbox connection**. Save approved company facts, the target brief and the budget allowances. Keep sending and scheduled research off until the controlled pilot below passes.

The page is `sales.html`; the shared sidebar adds Sales for administrators. The initial pilot is admin-only. No new server-side npm dependency or build command is required. The local PowerPoint export bundle and its MIT license are included.

## Function environment

| Variable | Required value / purpose |
| --- | --- |
| `SUPABASE_URL` | Existing TMS Supabase HTTPS URL. |
| `SUPABASE_SERVICE_ROLE_KEY` | Existing server-only database key. Never expose it in the frontend. |
| `TMS_SITE_URL` | Exact production HTTPS site URL, normally `https://tms.retodo-ops.com`. Also used for origin checks and background worker calls. |
| `GOOGLE_CLIENT_ID` | Existing Gmail OAuth client ID. |
| `GOOGLE_CLIENT_SECRET` | Existing Gmail OAuth client secret. |
| `GOOGLE_REFRESH_TOKEN` | Token for the intended mailbox, with send and read access described below. |
| `SALES_GMAIL_ACCOUNT_EMAIL` | Actual primary Gmail account returned by the Gmail profile API. This can differ from the default From address and the Sales alias. Omission assumes `ops@retodo-ops.com`; set it explicitly when the primary account differs. |
| `SALES_WORKER_SECRET` | New random secret of at least 32 characters, used only by the scheduler and Sales background endpoint. |
| `OPENAI_API_KEY` | Optional for manual Sales use; required for AI research, drafting and materials. Prefer a dedicated project key whose usage can be reviewed separately. |
| `SALES_AI_PRICING_REVIEWED_ON` | Date the installer checks model/search prices and the allowance, in `YYYY-MM-DD` form. Valid for 30 days; cannot be in the future. AI pauses when this expires. |
| `SALES_AI_EUR_PER_USD` | Required for AI: conservative EUR allowance per USD of provider usage, including applicable conversion, taxes and fees. Supported range 1–5. Choose it from actual billing conditions; it is not a fetched exchange rate. |
| `SALES_AI_INPUT_USD_PER_MILLION` | Optional override. Current code default/minimum: `0.40`. Raise if the verified provider price is higher. |
| `SALES_AI_OUTPUT_USD_PER_MILLION` | Optional override. Current code default/minimum: `1.60`. Raise if the verified provider price is higher. |
| `SALES_AI_SEARCH_USD_PER_CALL` | Optional override. Current code default/minimum: `0.01`. Raise if the verified tool price is higher. Search input tokens are allowed for separately. |

The AI adapter uses `gpt-4.1-mini` and the Responses API with structured output; research permits up to two hosted web-search calls. If the model, API or billing model changes, review the adapter before enabling it. Set the pricing review date only after checking the linked official sources, not merely to dismiss a hold.

### Gmail connection and sender isolation

The Sales alias `eli.s@retodo-ops.com` has already been created and configured by the user. Keep the general Gmail default **Retodo Ops `<ops@retodo-ops.com>`** and the existing reply-from-received-address preference. Do not change `GMAIL_FROM_EMAIL` for Sales.

Sales uses its own mail helper. Every Sales email has **From: Eli Stoyanova `<eli.s@retodo-ops.com>`** and **Reply-To: `eli.s@retodo-ops.com`**. These addresses are pinned in the database and the MIME headers; the worker does not fall back to the operational sender. The existing operational Gmail helper and supplier PO function are unchanged.

The OAuth token must have both:

- `https://www.googleapis.com/auth/gmail.send`
- `https://www.googleapis.com/auth/gmail.readonly`

An existing token with sufficient broader scopes can also work. A send-only token is insufficient because Sales must inspect replies and delivery failures. If reauthorization is needed, preserve scopes required by other existing workflows and update the server-side refresh token through the established secure process. The `sendAs.list` check accepts Gmail read scope; this implementation does not require `gmail.settings.basic` solely to list the configured alias.

**Check mailbox connection** verifies the authenticated primary account, accepted send-as alias and mailbox read access. A failure keeps sending blocked. It does not send a test email or modify Gmail settings.

## Budget and automation

The initial monthly ceiling is **€30**, with **€5 safety reserve** and **€5 Other Sales costs** as starting placeholders. Enter actual incremental hosting, mail or other service costs in Other Sales costs before enabling AI. Do not treat those placeholders as a price quotation. The database prevents a ceiling above €30 in this pilot.

Before each paid job, the system reserves a conservative upper estimate. It releases unused allowance only after usage is known. Jobs with unknown usage retain their reservation. The calculation includes settled usage, outstanding reservations, Other Sales costs and the safety reserve. Accounting months use UTC; follow-up dates use Europe/Sofia weekdays.

This is an application spending allowance, not a guaranteed provider or hosting invoice cap. It cannot see unrelated provider use, future pricing changes or unrecorded platform charges. Review provider billing alongside the Sales budget. No paid third-party prospect database or LinkedIn subscription is installed.

`netlify.toml` schedules `sales-scheduler` every five minutes on the production site. It wakes the secret-protected `sales-worker-background` function. One database lease prevents ordinary overlapping runs. Each run can process one queued AI job, poll up to five conversations and attempt up to three approved emails; the default daily email limit is ten, configurable from one to thirty.

Scheduled research defaults to every seven days once enabled, returning up to five suggested companies per job. Manual research works with scheduled research off. **Today → Check now** can wake the same worker. Refresh the page to retrieve completed results; jobs remain queued if a wake-up fails and can be picked up by the schedule.

## Daily workflow

1. **Today:** review tasks, attention items, AI jobs and budget. Research suggestions link to public sources; an empty research result is valid when evidence is insufficient.
2. **Prospects:** add or review a company, its fit and the source evidence. Review contact names and LinkedIn links. An AI-suggested email is always unverified. Before sending, check the address, record the evidence and why the contact is appropriate, then mark it verified. Verification expires after 90 days.
3. **Prepare outreach:** write or generate the initial email and optional follow-ups. Default follow-ups are five and twelve business days after the actual first send. Review every claim against the approved company facts. Attach up to three files, at most 1 MB combined.
4. **Batch review:** select at most fifty messages. The final review shows exact recipients, From/Reply-To, text, attachments and timing. Confirm the reviewed batch. An edited draft or contact invalidates its approval; a stale selection rejects the whole approval transaction.
5. **Conversations:** approved messages send only when sending is enabled and connection/reply checks pass. Read replies, pause or close an approach, and prepare a reviewed reply when appropriate. Follow-ups use the original Gmail thread and subject. One company may have only one open Sales conversation.
6. **Materials:** create or generate editable content, preview slides, export editable PowerPoint, download Markdown or print/save PDF. Check the exported document before attaching it. LinkedIn outreach remains a manual task with suggested contacts and draft copy.
7. **Convert / link Client:** link the existing matching Client or create the intended new Client. Sales history is retained; repeated conversion does not create another Client.

Ordinary human replies cancel queued outreach and mark the conversation replied. Out-of-office messages and manual mailbox replies pause the sequence. Recognized opt-outs and bounces suppress further sending. Unknown received messages also pause outreach. Automated classification is conservative English-based matching; review attention items and add an explicit email/domain suppression whenever needed.

The worker checks the tracked thread before every threaded send and also looks for matching separate delivery reports or new-subject replies to the Sales alias. A reply can still arrive between the final check and Gmail accepting a send. Mail synchronization is polling, not instantaneous push delivery.

## Controlled pilot after installation

Use an address you control and an explicitly labelled test company. These steps have not been run against production.

- Confirm audit 017 is all PASS and Sales is accessible only to enabled administrators. Check the existing Invoice links and operational screens still work.
- Check the mailbox connection and confirm the actual primary account plus the Eli alias. Leave general Gmail sender settings as they are.
- Create one test contact with evidence; first leave it unverified and confirm approval is rejected. Verify it and prepare a short initial email with two follow-ups.
- Review and approve only the intended test batch. Confirm the exact email address, content and attachment in the review dialog. Enable sending in Settings after a fresh mailbox check. The scheduler can now send approved due messages, so use only this controlled test in the queue.
- Receive the first email and inspect From/Reply-To. Reply from the controlled address, run/await a background check, refresh and confirm the reply appears and follow-ups are cancelled. Prepare and approve a response; verify it stays in the same thread and uses Eli's Sales address.
- Test a manual reply from Gmail and an out-of-office response using separate controlled conversations; each should pause pending outreach. Test a simple opt-out and confirm suppression. Do not send to an invalid third-party address solely to test a bounce.
- In a test draft, edit the body after approval and confirm fresh review is required. Try an outdated selection from another tab and confirm rejection.
- Confirm an ordinary operational email still uses its established operational identity when an actual operational send is intended. No operational test email was sent during development.
- With AI configured, start one small research job and inspect cited sources, unverified contacts and the settled/reserved budget. Review a generated pitch and PowerPoint before use.
- Turn sending off after the pilot until the first real prospect batch is intentionally ready. Enable scheduled research when the target brief and budget are settled.

## Attention and recovery

- **Mailbox or thread check fails:** sending waits. Correct the account/scopes/configuration, run Check mailbox connection and run a background check. Do not approve duplicate drafts as a workaround.
- **Send outcome unknown:** a message marked `uncertain` is not automatically retried. The worker searches Gmail Sent using its stable RFC message ID; a positive match confirms the existing send. Search absence alone never proves non-delivery. After at least ten minutes, an administrator who has independently confirmed that it was not sent can use the conversation's confirmed-not-sent action and record the evidence. This returns the message to a state requiring a new edit/review/approval. An incorrect resolution can cause a duplicate email.
- **Too many separate-thread candidates:** the mailbox check holds for manual review instead of assuming no reply. Review the conversation and mailbox evidence before investigating the candidate limit; do not increase it blindly.
- **Paused / replied conversation:** resuming does not revive cancelled approvals. Prepare or edit the intended messages and approve them again. Suppressed recipients remain blocked.
- **AI result uncertain:** inspect provider usage before retrying. The reservation stays in place; no automatic paid retry occurs. This pilot has no UI for adjudicating unknown AI charges. Leave the reservation intact unless a database administrator reconciles the exact job against provider evidence.
- **AI budget hold:** if recorded usage exceeds its reservation, both manual and automatic AI work stop. Review pricing, conversion/tax allowance and provider usage first. An administrator may then clear only the hold with `UPDATE public.sales_settings SET budget_hold=false, updated_at=now() WHERE id=true;` in the authorized database workflow. This does not erase charges/reservations or restart scheduled research. Do not run it merely to bypass the €30 ceiling.
- **Stop automation:** disable sending and scheduled research in Settings. An already accepted Gmail send cannot be recalled. Keep migration 057 and its history; do not drop tables as a rollback procedure.

## Executed verification and limits

- **28 database workflow cases** passed using actual migration SQL in PGlite: roles/RLS, duplicates, exact approval snapshots, version checks, edit invalidation, sender isolation, claim leases, uncertain-send handling, follow-up timing, replies, suppression, conversion, AI reservations/settlement/holds, tasks and materials.
- **31 installation audit checks** passed. Migration 057 also passed reapplication.
- **14 service checks** passed: Gmail MIME/thread headers, Unicode subject folding, alias/account/read access, separate-thread replies and delivery failures, AI configuration, evidence validation and cost handling.
- **5 worker/API checks** passed: worker authentication, JWT/admin boundary, durable queuing, synchronization before sending and unknown-send failure handling.
- Chromium fixtures passed navigation, three-message sequence/attachments, exact and stale batch approval, conversations, material preview and PowerPoint download, Settings edits preserved during connection checks, search, escaped untrusted content, mobile layout and QA access denial. Desktop/mobile screenshots were inspected. The downloaded PPTX passed XML/content/embedded-logo inspection; desktop PowerPoint rendering was not tested.
- Browser requests used fixtures; database behavior was tested separately. No live Google OAuth, real delivery, paid AI request, production migration or production acceptance is claimed.
- Database tests use available historical schema through 038 and relevant 050/053/054/055/056/057 migrations. The absent 037 audit writer is explicitly stubbed for the unrelated baseline setup; historical 037/040 remain absent. This is not a complete historical replay.

Pilot limits: exact normalized company-name/domain and email deduplication, no fuzzy corporate matching; one open conversation per company; prospect pages of fifty; review/conversation lists of up to one hundred; full selected-company conversation history in details. The shared operational search does not yet include Sales entities; use the Sales prospect search. Inbox attachments are not imported, OOO dates are not parsed for automatic resumption, and there are no tracking pixels or automatic LinkedIn actions. Resource matching, rate-based proposals, quote creation, broader team permissions and native Google Slides integration remain later work.

## Official integration references

- [Gmail send-as listing and accepted OAuth scopes](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/list)
- [Gmail authorization scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Gmail thread requirements](https://developers.google.com/workspace/gmail/api/guides/threads)
- [Netlify scheduled functions](https://docs.netlify.com/build/functions/scheduled-functions/)
- [GPT-4.1 mini model](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search)
- [OpenAI pricing](https://developers.openai.com/api/docs/pricing)
