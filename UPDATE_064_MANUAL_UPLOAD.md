# Update 064A — Eli’s Sales signature with supplied brand assets

This corrected package replaces the earlier Update 064 download and includes the full signature feature. It uses the assets supplied by the user on 2026-10-07.

This package adds a compact automatic signature to Sales emails, follow-ups and replies. Configure it at **Sales → Settings → Eli’s email signature**. The signature is shown in each complete email preview and in Batch review before approval.

## Signature supplied

- Closing: Best Regards,
- Name: Eli Stoyanova
- Position: Business Development & Client Relations Coordinator
- Supplied multicolour Retodo Ops logo, displayed at 48 × 48 px beside the company name; navy/blue text matching the brand cover
- Website: https://retodo-ops.com/
- LinkedIn: https://www.linkedin.com/in/eli-stoyanova-667831410/
- Note: This email and any attachments are confidential. If received in error, please notify the sender and delete them.

No postal address or location appears. The position comes from the earlier signature draft and is editable; it is not a newly verified job designation. The LinkedIn link uses Eli’s previously supplied profile and is editable. A standalone, self-contained preview is in `docs/sales/Eli_Stoyanova_Sales_Signature.html`.

## Install through the agreed complete-file workflow

The baseline is main `75b4b54e2f30fc010cd09dadb4f183c460e62255`, including the latest 063C enquiry correction. The existing Sales delivery/reply test has passed. Migration 057 and the 058 polling correction should already be installed.

1. In **Sales → Settings → Outreach**, clear **Allow approved messages to send**, then select **Save Sales settings**.
2. In **Supabase SQL Editor**, run `tms/migrations/059_sales_email_signatures.sql` **only if you have not already installed it**. Then run the complete new `tms/migrations/060_sales_signature_brand_assets.sql`. Uploading these files to GitHub does not execute SQL. Do not rerun 057, 058 or 059 after 060.
3. Run audit `019_update_064_sales_signature_audit.sql` (**12 PASS rows**), then `020_update_064a_sales_brand_assets_audit.sql` (**9 PASS rows**).
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
- Migrations 059 and 060 are forward-only and can be reapplied without changing saved settings, messages or approvals. Migration 060 retains the corrected 058 worker polling query. Renderer 1 remains byte-for-byte stable for previously reviewed messages. Renderer 2 uses the supplied assets for new messages. Updating an existing message to the current signature requires fresh review.

## Supplied brand source

Source folder: https://drive.google.com/drive/folders/1mclWAmQ8SckGcPpJmmVevWXQaPxyOUG_ → 01 Brand assets. Logo: `Retodo_Ops_LinkedIn_Logo_600x600.png`, Drive file `1DRLqtJZ4tSKqBIDd98LSECaSY3C9XU8v`. The PNG is embedded unchanged; only its display size is reduced. SHA-256: `747a6f6ef984b726bb5efa86737e513dc76b16296453099d28b090fc47cc4890`. The supplied 4200×700 company cover establishes the navy/blue/orange branding. No replacement logo was generated.

## Verification performed

- 49 actual SQL workflow checks, including 9 signature and 5 supplied-brand-asset checks: legacy migration preservation, validation, per-message choices, immutable approvals, renderer-version approval, edit/reapproval, replies, old-tab approval rejection, pre-send snapshot checks and migration reapplication.
- All installation audits pass: 31 Sales checks, 11 worker checks, 12 signature checks and 9 supplied-brand-asset checks.
- 41 service/worker/diagnostic tests, including independent MIME parsing of HTML/plain text, nested inline logo, exact supplied logo bytes, attachments, Unicode and thread headers; unsafe links/HTML are rejected or escaped.
- Chromium fixture workflow: settings/live preview/save with supplied logo, each sequence choice, batch signatures, signature edits, captured vs current defaults, replies, mobile layout and prior Sales flows. Desktop and mobile screenshots inspected.
- The actual worker plus actual SQL sends once through intercepted Gmail, imports a reply and cancels follow-ups. No real mail, paid AI, production SQL or production deployment was performed by the assistant. A recovery checkpoint is saved only on the non-main signature task branch.

SQL tests use an isolated PGlite database with Supabase platform stubs and the existing explicit stub for the repository’s absent historical 037 audit writer. Browser mail/database/AI responses are fixtures. These checks do not claim live Gmail or Outlook rendering.

For repeatable local checks, run `tests/update-063-sales-db.mjs` with `PGLITE_MODULE` pointing to the installed PGlite entry, `node --test tests/update-063-sales-services.test.cjs tests/update-063-sales-worker.test.cjs tests/update-063-sales-diagnostics.test.cjs tests/update-064-sales-signature.test.cjs tests/update-064a-sales-brand-assets.test.cjs`, and `tests/update-063-sales-browser.cjs` with `PLAYWRIGHT_MODULE`, `CHROMIUM_MODULE` and `SALES_TEST_OUTPUT` pointing to the local test runtime/output. The MIME tests also require Python 3’s standard library.

## Complete package contents — 21 files

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
tests/update-064a-sales-brand-assets.test.cjs
tests/update-064a-sales-brand-assets-db.mjs
tms/audits/019_update_064_sales_signature_audit.sql
tms/audits/020_update_064a_sales_brand_assets_audit.sql
tms/build.json
tms/migrations/059_sales_email_signatures.sql
tms/migrations/060_sales_signature_brand_assets.sql
tms/sales-signature-ui.js
tms/sales-signature.js
tms/sales.css
tms/sales.html
tms/sales.js
```
