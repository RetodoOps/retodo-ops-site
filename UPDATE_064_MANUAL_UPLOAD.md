# Update 064 — Eli’s Sales email signature

This package adds a compact automatic signature to Sales emails, follow-ups and replies. Configure it at **Sales → Settings → Eli’s email signature**. The signature is shown in each complete email preview and in Batch review before approval.

## Signature supplied

- Closing: Best Regards,
- Name: Eli Stoyanova
- Position: Business Development & Client Relations Coordinator
- Existing Retodo Ops logo, displayed at 110 × 35 px
- Website: https://retodo-ops.com/
- LinkedIn: https://www.linkedin.com/in/eli-stoyanova-667831410/
- Note: This email and any attachments are confidential. If received in error, please notify the sender and delete them.

No postal address or location appears. The position comes from the earlier signature draft and is editable; it is not a newly verified job designation. The LinkedIn link uses Eli’s previously supplied profile and is editable. A standalone, self-contained preview is in `docs/sales/Eli_Stoyanova_Sales_Signature.html`.

## Install through the agreed complete-file workflow

The baseline is main `75b4b54e2f30fc010cd09dadb4f183c460e62255`, including the latest 063C enquiry correction. The existing Sales delivery/reply test has passed. Migration 057 and the 058 polling correction should already be installed.

1. In **Sales → Settings → Outreach**, clear **Allow approved messages to send**, then select **Save Sales settings**.
2. In the **Supabase SQL Editor**, create a new query, paste the entire contents of `tms/migrations/059_sales_email_signatures.sql` and run it. Uploading the SQL file to GitHub does not apply it. Run this new migration only; do not rerun 057 or 058 afterward.
3. Run the complete read-only `tms/audits/019_update_064_sales_signature_audit.sql`. All **12 rows** should say **PASS**.
4. Upload/replace every file in this ZIP at its matching repository-root path and commit using your usual workflow. These are complete files, not patches. Keep the folder structure.
5. After your usual Netlify deployment finishes, hard-refresh **Sales**. Open **Settings → Eli’s email signature**, review the position and links, and select **Save signature**. This button saves the Sales settings form, including its current Outreach choice.

There are no new environment variables, OAuth steps, paid services or Gmail-default changes for this update. The source package retains the separate project-enquiry anti-spam changes already committed on main.

## How to use it

**New outreach:** Open a prospect, select **Prepare outreach** and write only the message body. **Include Eli’s signature** is selected by default for the initial email and each follow-up. Expand **Preview complete email** to see the result. You can clear the checkbox for an individual message, for example when it already contains a typed signature.

**Replies:** Open a sent conversation and select **Draft reply**. The same signature checkbox and complete-email preview are available. Save the reply for batch review as usual.

**Existing messages:** Open **Batch review → Edit draft**, or **Conversations → Open → Edit / review**. Under **Signature**, choose **Use current Sales signature**, then **Save draft**. The other choices keep that message’s saved signature or remove it. Saving an approved message returns it to review and requires fresh approval.

**Default changes:** Edit the closing, position, website, LinkedIn link or short note in Settings. You can hide the logo or disable automatic inclusion for new messages. Existing draft, approved and sent messages retain their own saved signature. Messages created before this update remain without an automatic signature until explicitly edited.

## One controlled delivery check

1. Keep sending paused and open your existing test conversation with an address you control. Select **Draft reply**, enter a short test body and expand **Preview complete email**.
2. Confirm the compact logo, Eli’s name/position, both links and the short note. Save for batch review and approve only the intended test reply. Ensure the approved queue contains only messages you intend to release.
3. Enable **Allow approved messages to send**, save, then select **Today → Check now**.
4. Check the received email: one signature, readable logo, working website/LinkedIn links, no address, and From/Reply-To `eli.s@retodo-ops.com`. Then return sending to the desired pilot state.

The earlier live send/reply/follow-up cancellation test does not need to be repeated for setup. Actual signature rendering in the recipient’s mail app is the remaining live check; Gmail/Outlook may use different fonts or image-display preferences.

## Approval and compatibility details

- Each saved message captures a structured signature with a renderer version. The exact snapshot is included in the batch approval. Template edits never silently change a queued message.
- The worker verifies the stored signature against its approval immediately before sending. An old open Sales tab cannot approve a signature it has not displayed; it will ask for a refresh and review.
- HTML and plain-text email alternatives use the same saved content. The original logo bytes are embedded inline in MIME; no external tracking image or remote logo fetch is added.
- Existing attachment limits and Gmail threading remain in place. The inline logo does not replace a user attachment. General TMS Gmail and supplier PO helpers are untouched.
- Migration 059 is forward-only and can be reapplied without changing saved settings, messages or approvals. It retains the corrected 058 worker polling query. Future renderers must keep the version 1 layout and logo stable for already reviewed signatures.

## Verification performed

- 44 actual SQL workflow checks, including 9 signature checks: legacy migration preservation, validation, per-message choices, immutable approvals, edit/reapproval, replies, old-tab approval rejection, pre-send snapshot checks and migration reapplication.
- All installation audits pass: 31 Sales checks, 11 worker checks and 12 signature checks.
- 38 service/worker/diagnostic tests, including independent MIME parsing of HTML/plain text, nested inline logo, attachments, Unicode and thread headers; unsafe links/HTML are rejected or escaped.
- Chromium fixture workflow: settings/live preview/save, each sequence choice, batch signatures, signature edits, captured vs current defaults, replies, mobile layout and prior Sales flows. Desktop and mobile screenshots inspected.
- The actual worker plus actual SQL sends once through intercepted Gmail, imports a reply and cancels follow-ups. No real mail, paid AI, production SQL or production deployment was performed by the assistant. A recovery checkpoint is saved only on the non-main signature task branch.

SQL tests use an isolated PGlite database with Supabase platform stubs and the existing explicit stub for the repository’s absent historical 037 audit writer. Browser mail/database/AI responses are fixtures. These checks do not claim live Gmail or Outlook rendering.

For repeatable local checks, run `tests/update-063-sales-db.mjs` with `PGLITE_MODULE` pointing to the installed PGlite entry, `node --test tests/update-063-sales-services.test.cjs tests/update-063-sales-worker.test.cjs tests/update-063-sales-diagnostics.test.cjs tests/update-064-sales-signature.test.cjs`, and `tests/update-063-sales-browser.cjs` with `PLAYWRIGHT_MODULE`, `CHROMIUM_MODULE` and `SALES_TEST_OUTPUT` pointing to the local test runtime/output. The new MIME tests also require Python 3’s standard library.

## Complete package contents — 17 files

```text
UPDATE_064_MANUAL_UPLOAD.md
docs/context/CURRENT_WORK.md
docs/sales/Eli_Stoyanova_Sales_Signature.html
netlify/functions/_shared/sales-ai.js
netlify/functions/_shared/sales-gmail.js
tests/update-063-sales-browser.cjs
tests/update-063-sales-db.mjs
tests/update-064-sales-signature-db.mjs
tests/update-064-sales-signature.test.cjs
tms/audits/019_update_064_sales_signature_audit.sql
tms/build.json
tms/migrations/059_sales_email_signatures.sql
tms/sales-signature-ui.js
tms/sales-signature.js
tms/sales.css
tms/sales.html
tms/sales.js
```
