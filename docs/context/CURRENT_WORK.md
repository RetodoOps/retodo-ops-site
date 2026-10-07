# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: ZIP workflow; user uploads/commits directly to main
Starting HEAD: 0c704f05e762f588cafcb3cd7e53ac44534cba95
Latest durable checkpoint: main 0c704f0 contains Update 060
Build: 060 repository baseline; 061 in this package
Last updated: 2026-09-29

## CURRENT TASK
Update 061 — stop automated spam submissions through the public Project Enquiry form.

## STATUS
READY FOR USER INSTALLATION — Turnstile + server-side validation package prepared; production acceptance pending.

## TASK-SPECIFIC LOCKED RULES
- USER OVERRIDE: ZIP updates with complete changed files only. User uploads and commits directly to main. Do not push, merge, create PRs or deploy.
- TURNSTILE_SECRET_KEY stays only in Netlify environment variables; never commit the secret.
- Public Turnstile site key: 0x4AAAAAAFE58tRuuQcvpTkl.
- Preserve the existing honeypot and Gmail delivery flow.
- No production migration, data or authentication change.

## COMPLETED WORK
- Root cause established: spam is submitted through the public website enquiry endpoint; existing honeypot alone is insufficient.
- User created Cloudflare Turnstile and configured TURNSTILE_SECRET_KEY in Netlify.
- Added Cloudflare Turnstile widget to contact form.
- Client requires a Turnstile response before AJAX submission and resets the widget after success/failure.
- Netlify function verifies the Turnstile token server-side before Gmail delivery.
- Existing origin/referrer restriction and honeypot retained.
- Server now allow-lists source language, target language and word-count selections.
- Past deadlines are rejected server-side.
- Build marker advanced to 061.

## CHANGED FILES
- contact.html
- script.js
- netlify/functions/submit-project-enquiry.js
- tms/build.json
- docs/context/CURRENT_WORK.md
- UPDATE_061_MANUAL_UPLOAD.md

## TEST RESULTS
- Static package checks: Turnstile API script, public site key, cf-turnstile-response handling, server siteverify call and TURNSTILE_SECRET_KEY reference are present.
- Server validation path preserves honeypot before Turnstile verification and Gmail send occurs only after validation + Turnstile success.
- No live Turnstile verification or production email was executed from this environment; production acceptance is pending after upload/deploy.

## UNRESOLVED / INCOMPLETE
- User must upload/commit Update 061 files to main.
- Netlify must deploy the resulting main commit.
- Confirm contact page shows the Turnstile security check and a genuine test enquiry arrives.
- Confirm obvious automated/direct submissions without a valid Turnstile token no longer generate email.
- If Turnstile reports hostname/configuration errors, verify retodo-ops.com and www.retodo-ops.com are allowed on the Cloudflare widget.

## REQUIRED CONTEXT
NONE

## NEXT EXACT ACTION
User uploads extracted Update 061 files to repository root, commits to main, waits for Netlify deploy, then submits one genuine test enquiry through retodo-ops.com/contact.html.

## DO NOT REDO
- Do not recreate Turnstile or expose/commit its secret.
- Do not replace the solution with Gmail filtering.
- Do not remove the existing honeypot/origin controls.
- Do not run Supabase SQL; Update 061 has no database migration.

## PRODUCTION STATE
Main 0c704f0 is the inspected Update 060 baseline. Update 061 is packaged only; no assistant push, merge, deployment, migration or production configuration change was performed.
