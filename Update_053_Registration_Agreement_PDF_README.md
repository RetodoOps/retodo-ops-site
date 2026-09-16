# Retodo Ops TMS — Update 053 Registration and Agreement PDF Recovery

## Scope

This frontend-only correction addresses the two acceptance failures reported after Update 052:

1. An email that already has a Supabase Auth account no longer leaves the Resource with only a generic `Invalid login credentials` message. The registration page identifies the existing account, provides a direct password-setup link, preserves the entered Resource name, and returns to registration after the new password is saved so the existing account can be linked without creating a duplicate.
2. Signed Agreement PDF generation no longer renders an off-screen blank canvas. The shared renderer stages the complete Agreement on-screen for capture, waits for the logo/layout, includes all terms, provider details, acceptance timestamp, version and SHA-256, and is used by both the Resource Portal and the internal Resource page.
3. The internal Resource page now shows the accepted Agreement terms and audit details and changes its action to `Download signed PDF` after acceptance. The original DOCX remains available before acceptance.

The previously reported Reports module gap remains intentionally outside this correction: the Job sidebar entry is visible, but the Reports page/submenus are not yet implemented. It remains the next separate feature update.

## Deployment order

1. Upload all files from `RetodoOps_Update_053_Registration_Agreement_PDF.zip` to the repository root, preserving their paths, and publish through the existing GitHub/Netlify flow.
2. Confirm `https://tms.retodo-ops.com/build.json` reports build `053`.
3. Run the acceptance block below.

No database migration, audit SQL or new environment variable is required. Do not rerun migrations 049/050 or audits 011/012.

## Acceptance block

### Registration recovery

1. Open `register.html` in a fresh/private browser session.
2. Submit an email that already has an Auth account.
3. Confirm the page says the email already has an account and shows `Forgot password / send setup link`.
4. Request the setup link, open the newest email, save a password, and confirm the link returns to registration.
5. Click `Sign in to finish registration` with the new password.
6. Confirm the existing Resource is linked and the account remains pending Administrator approval; no duplicate profile is created.

### Signed Agreement PDF

1. As a Resource, open the accepted Agreement and click `Download signed PDF`.
2. Confirm the PDF contains the Retodo header, all 15 clauses, provider details, signatory, registration email, effective/acceptance data, Agreement version and document SHA-256.
3. As Admin, open the same Resource → Compliance & Qualifications.
4. Confirm the accepted Agreement summary, hash and `Download signed PDF` action are visible, and the downloaded PDF contains the same complete terms and accepted details.

## Verification

- UI/API regression tests: **all PASS**
- Reset-password session tests: **all PASS**, including the registration recovery handoff
- Database regression: inherited Update 040–050 suite **PASS** (all database checks); this update adds no SQL
- JavaScript syntax: **PASS**
- The reported uploaded PDF was confirmed as a one-page 3,058-byte file with no extractable text; the blank-canvas staging fix targets that failure directly.
