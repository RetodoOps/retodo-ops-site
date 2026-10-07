# Update 063B — Sales worker polling correction

Prepared 2026-10-06 against main `1233887f2093934b17c7260cc21d0c550301f2bc` (Update 063A). The ZIP contains five complete changed files with repository-root paths. The TMS build remains 063.

## Problem and correction

The mailbox check passed for primary account `aleksandra.a@retodo-ops.com`, with Sales sender `eli.s@retodo-ops.com`. After the short worker secret was replaced, the screenshot showed a worker run at 19:48 on 6 October and the database error `column reference "c.*" is ambiguous`. It also showed one approved queued message, one draft to review and zero sent messages.

Inside `sales_system_063`, `c` named both a local conversation record and the table alias used by the `threads` action. PostgreSQL rejects that ambiguity when the action executes. The worker calls it before claiming approved emails, including when there are no existing Gmail threads.

Migration 058 replaces the worker function with the same implementation except for that query: the table alias is now `thread_conversation`, and its selected fields, filters and sorting use that name explicitly. The filters, oldest-first order and 20-thread limit remain the same. Existing settings, drafts, approvals, leases, spending records and email history are retained. Browser roles still cannot execute the worker RPC.

The original migration 057 is retained unchanged. Updating GitHub/Netlify alone does not apply this database correction: run the new SQL in Supabase.

## Install

1. In **Sales → Settings → Outreach**, untick **Allow approved messages to send** and click **Save Sales settings**. This keeps the approved test queued while you apply and audit the correction.
2. Extract `RetodoOps_Update_063B_Worker_SQL_Fix.zip`.
3. Open `tms/migrations/058_sales_worker_thread_polling.sql`. Copy its entire contents into a new query in the TMS project's **Supabase SQL Editor**, and run it.
4. Run the entire `tms/audits/018_update_063b_sales_worker_audit.sql` file. All **11** rows must report **PASS**. The audit only reads the installed function and its permissions; it does not start the worker or send email.
5. Upload all five complete files into their matching GitHub repository paths and commit through the usual workflow. This records the migration and updated tests/context. No Netlify function, environment variable, Gmail setting or frontend change is required for this correction.

Do not rerun migration 057 as part of this installation: it contains the original query. Migration 058 can be reapplied to this version without changing Sales rows. If the audit reports FAIL, keep sending paused and share the failing row.

## Resume the controlled test

1. Open the existing TEST prospect/conversation. Keep its existing messages; no duplicate prospect or sequence is needed. The screenshot showed one message still in **Batch review**: if that is the test follow-up, review and approve it too. Approval remains required for each message.
2. Enable **Allow approved messages to send**, save, then select **Today → Check now**.
3. Refresh the Sales page after the background run. The Worker time should advance and the `c.*` error should clear. A due, approved initial message should appear as sent if the remaining delivery checks pass.
4. In the receiving test mailbox, inspect From and Reply-To: both must use `eli.s@retodo-ops.com`, with From name Eli Stoyanova. Reply from that receiving account, select **Today → Check now**, then refresh and confirm the reply appears and pending follow-ups are cancelled.
5. Turn sending off after the controlled test.

If a new error appears, share its exact text and the updated Worker time. Local tests do not establish live delivery; that remains the next acceptance step.

## Verification

- Reproduced the original `c.*` error under PostgreSQL's strict variable-conflict setting before applying the correction.
- **35 database/workflow checks passed**, including all 28 existing cases plus empty/nonempty thread polling, eligibility/order/limit checks, service-only access and migration reapplication with every Sales row preserved, including approved and draft messages.
- The full worker test uses the actual JavaScript worker, Gmail helper and corrected SQL, with all external requests intercepted. It sends the simulated initial email once, polls the returned thread, imports the simulated reply, cancels pending follow-ups, rejects duplicate sending and records a successful worker run.
- **42 audit checks passed**: the existing 31 Update 063 checks plus the 11 new correction checks.
- JavaScript syntax and diff whitespace checks passed. The full worker function was compared against 057; only the thread query changes. Existing Gmail helpers, sender settings, frontend, approval logic and uncertain-send handling are unchanged.

Database tests use PGlite with minimal Supabase stubs and the existing historical compatibility fixture; they are not a complete historical migration replay. No production SQL, deployment, live email or paid AI request was performed by the assistant.

Developer test command: set `PGLITE_MODULE` to `@electric-sql/pglite/dist/index.js`, then run `node tests/update-063-sales-db.mjs`.

Reference: [PostgreSQL PL/pgSQL variable substitution and deferred query analysis](https://www.postgresql.org/docs/current/plpgsql-implementation.html).
