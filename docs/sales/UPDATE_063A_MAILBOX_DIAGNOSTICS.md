# Update 063A — Sales mailbox diagnostics

Prepared 2026-10-05 against Update 063 on main `9e2799c393861e18aef6e8196ff4ff8cb12e916a`. This package contains complete changed files, preserving repository-root paths. The TMS build number remains 063.

## What this fixes

The previous Gmail helper discarded Google's specific OAuth error, then the general error filter hid the remaining authorization message. That left the administrator with “The Sales request could not be completed” and no way to distinguish a rejected refresh token from a mismatched OAuth client.

Sales now displays a reviewed diagnostic code and explanation in the connection error and saved Automation status. It never echoes Google's raw error description, tokens, secrets or response body. General error filtering remains in place for other failures.

This fixes error reporting. It does not establish that the saved refresh token is valid or that the live mailbox is connected.

## Install and check

1. Extract `RetodoOps_Update_063A_Mailbox_Diagnostics.zip`. Upload all six complete files into their matching repository paths, including the new `netlify/functions/_shared/sales-diagnostics.js`. Commit through your normal workflow.
2. Wait for the production Netlify deployment containing that commit to succeed.
3. Open **Sales → Settings → Check mailbox connection**.
4. If it fails, share the new `[CODE]` message. It is also recorded under **Today → Automation**; check that the mailbox-check time belongs to this attempt.

No SQL or migration is required. No new token or environment change is required solely to install this diagnostic update. The connection check sends no email and changes no Gmail settings. Keep sending paused until the controlled pilot in `UPDATE_063_INSTALL_AND_TEST.md` is ready.

On success, the check returns the authenticated primary account, Sales alias and Reply-To. The alias and Reply-To must both be `eli.s@retodo-ops.com`; the primary account can be different.

## Read the result

| Code | Next action |
| --- | --- |
| `GOOGLE_CONFIG_MISSING` / `GOOGLE_CONFIG_FORMAT` | Check that `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` and `GOOGLE_REFRESH_TOKEN` exist for production Functions and contain only their plain values. Paste no JSON, quotation marks or `Bearer` prefix. |
| `GOOGLE_CLIENT_REJECTED` | Google returned `invalid_client`. Compare Netlify's client ID and secret with the same client used in OAuth Playground. |
| `GOOGLE_REFRESH_REJECTED` | Google returned `invalid_grant`. Test the existing refresh token as described below before replacing it again. |
| `GMAIL_API_DISABLED` | Enable Gmail API in the Google Cloud project containing that OAuth client. |
| `GMAIL_PERMISSIONS_MISSING` | Authorize `gmail.send` and `gmail.readonly`, preserving any scopes needed by existing workflows. Save the resulting refresh token through the established configuration process. |
| `GOOGLE_MAILBOX_MISMATCH` | Set `SALES_GMAIL_ACCOUNT_EMAIL` to the actual primary Google account used for OAuth. Do not assume it is the Sales alias or the default From address. |
| `GOOGLE_ALIAS_UNVERIFIED` | Check that `eli.s@retodo-ops.com` is an accepted send-as address in that account. |
| `GOOGLE_POLICY_BLOCKED` / `GOOGLE_CLIENT_NOT_ALLOWED` | Review the OAuth client and Workspace app-access policy with the account administrator. |
| Other diagnostic codes | Share the displayed code and message so the next step can follow the actual failure. Network timeouts alone do not prove a token is invalid. |

Netlify environment changes must apply to the production Functions scope and require a new deployment. Keep the existing general Gmail sender settings. Sales continues to use Eli Stoyanova `<eli.s@retodo-ops.com>` for From and Reply-To.

## Test the existing refresh token in OAuth Playground

This is an optional diagnostic for `GOOGLE_REFRESH_REJECTED`; it does not send mail.

1. Open [OAuth Playground](https://developers.google.com/oauthplayground/). In its settings, select **Use your own OAuth credentials** and use the exact same OAuth client ID and secret configured in Netlify.
2. In Step 2, set the **Refresh token** field to the exact existing refresh-token value being tested.
3. Click **Refresh access token**. A successful refresh returns an access token; the refresh token can remain unchanged.
4. If it succeeds, compare Netlify's deployed production values and scope with that working configuration. If it fails, share only the OAuth error code, such as `invalid_grant` or `invalid_client`.

**Exchange authorization code for tokens** exchanges a newly issued authorization code once. Repeating that exchange with the same code can fail with Bad request; it does not test whether the existing refresh token still works. Do not paste tokens, client secrets or full Playground responses into chat or the repository.

If the original generic Sales error remains, confirm that the new function files were included in the successful production deployment. A failure before the Google check, such as an authentication/database error, can still use the general error message; the mailbox-check timestamp helps distinguish a new attempt from saved status.

## Verification

All **32 focused tests passed**: 13 new diagnostics tests, 14 existing service tests and 5 existing worker/API tests. They cover the real API/worker/Gmail error path with intercepted network calls, secret redaction, role checks, successful read-only connection checks and no automatic retry after a failed send. JavaScript syntax and diff whitespace checks passed.

The operational Gmail helper, supplier PO sender, shared error filter, database and frontend are unchanged. No live Google authentication, deployment, email delivery or paid AI request was performed for this update.

References: [Google OAuth refresh-token flow](https://developers.google.com/identity/protocols/oauth2/web-server#offline), [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), [Netlify function environment variables](https://docs.netlify.com/build/functions/environment-variables/).
