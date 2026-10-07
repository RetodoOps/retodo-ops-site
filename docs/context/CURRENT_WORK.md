# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: ZIP workflow; user uploads/commits directly to main
Starting HEAD: a39c10809b967e8b4f4ea6935734125e3d3dcc9d
Latest durable checkpoint commit: main a39c108 contains the anti-spam change, but its package incorrectly reset build/context metadata to an older baseline
Build: restore 063 (063B did not advance the build); enquiry correction package 063C does not change the TMS build number
Last updated: 2026-10-07

## CURRENT TASK
Update 063C — keep the working Project Enquiry Turnstile protection, show a specific short-project-details validation message on the website, and repair the baseline metadata overwritten by the older anti-spam package.

## STATUS
READY FOR USER INSTALLATION — correction ZIP prepared from current main a39c108; no SQL, migration, environment-variable or production-data change.

## TASK-SPECIFIC LOCKED RULES
- ZIP updates with complete changed files only. User uploads and commits directly to main. Do not push, merge, create PRs or deploy.
- TURNSTILE_SECRET_KEY remains only in Netlify environment variables; never commit or expose it.
- Preserve the working Turnstile, existing honeypot, origin checks and Gmail enquiry delivery.
- Preserve Update 063/063A/063B Sales work. Update 063B intentionally did not change tms/build.json.
- Do not rerun migration 057. Migration 058/audit 018 remain the Sales worker SQL correction path where applicable.

## COMPLETED WORK
- User confirmed live Turnstile shows successful verification.
- Netlify Function log identified the failed test as `Project details are too short`.
- User then submitted a valid enquiry and confirmed it was sent and received successfully.
- Root cause of the repository-baseline problem confirmed: anti-spam commit a39c108 was uploaded after Updates 062/063/063A/063B but its package had been prepared from Update 060.
- The anti-spam commit changed only UPDATE_061_MANUAL_UPLOAD.md, contact.html, script.js, netlify/functions/submit-project-enquiry.js, tms/build.json and docs/context/CURRENT_WORK.md. It did not overwrite Sales implementation files or migration 058.
- The stale package incorrectly changed tms/build.json from build 063 back to 061 and replaced CURRENT_WORK with obsolete Update 060/061 continuity.
- This correction restores tms/build.json to the verified pre-upload build 063 metadata.
- Website validation now checks trimmed Project Details length before Turnstile/network submission and displays `Project details are too short.` while focusing the field.
- contact.html also declares minlength=10 and cache-busts script.js as v=063c.
- Working server-side Turnstile and Gmail delivery remain unchanged.

## CHANGED FILES
- contact.html
- script.js
- tms/build.json
- docs/context/CURRENT_WORK.md
- UPDATE_063C_MANUAL_UPLOAD.md

## TEST RESULTS
- USER-VERIFIED: valid live enquiry passed Turnstile, sent successfully and was received.
- USER/LOG-VERIFIED: short project details were rejected server-side with `Project details are too short`.
- STATIC PASS: contact textarea has minlength=10; script contains the matching trimmed-length check and exact website error message; script cache reference advances to v=063c.
- STATIC PASS: tms/build.json restored to build 063 / Update 063 Sales metadata from commit 8b1f6d8, the parent immediately before the anti-spam upload.
- No production deployment, email send, SQL execution or environment change was performed while preparing this correction.

## UNRESOLVED / INCOMPLETE
- User must upload/commit this 063C ZIP to main and wait for Netlify deploy.
- After deploy, hard-refresh the contact page and confirm a Project Details value shorter than 10 characters shows `Project details are too short.` without sending.
- Confirm a normal enquiry still succeeds.
- Sales 063B operational acceptance remains governed by its existing migration 058/audit 018 workflow; do not infer completion from this website correction.

## REQUIRED CONTEXT
NONE

## NEXT EXACT ACTION
Upload the extracted Update 063C files to repository root on main, preserving paths, and commit. After Netlify deploy, hard-refresh the contact page, test a <10-character Project Details value, then one valid enquiry.

## DO NOT REDO
- Do not recreate Turnstile, OAuth, Sales worker secrets or queued Sales messages.
- Do not replace the anti-spam solution with Gmail filtering.
- Do not revert or reconstruct Updates 062/063/063A/063B.
- Do not run Supabase SQL for this 063C correction.
- Do not set the TMS build to 061; build 063 is the correct pre-anti-spam baseline.

## PRODUCTION STATE
Current main a39c108 includes the working anti-spam implementation and live enquiry delivery is user-confirmed, but its build/context metadata is stale because the package was based on Update 060. This 063C package repairs that metadata and adds client-side short-details feedback. No assistant push, merge, deploy, migration or production configuration change was performed.
