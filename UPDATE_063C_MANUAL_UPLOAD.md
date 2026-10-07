# Update 063C — Enquiry UX + baseline repair

Baseline: current main `a39c10809b967e8b4f4ea6935734125e3d3dcc9d`.

This corrects the anti-spam package that was prepared from Update 060 and later uploaded after Updates 062/063/063A/063B.

## What is corrected

- Project Details now has a 10-character browser minimum.
- The website explicitly shows `Project details are too short.` before Turnstile/network submission.
- The working Turnstile/server/Gmail flow is otherwise unchanged.
- `tms/build.json` is restored to build 063, the verified value immediately before the anti-spam upload.
- `docs/context/CURRENT_WORK.md` is repaired so continuation no longer points back to Update 060/061.

The anti-spam commit did not overwrite the Sales implementation or migration 058; its changed files were limited to the enquiry files plus build/context metadata and its guide.

## Install

1. Extract this ZIP.
2. Upload all extracted files/folders to the repository root on `main`, preserving paths.
3. Replace the existing files with these complete versions.
4. Commit, for example: `Update 063C: enquiry validation and baseline repair`.
5. Wait for the normal Netlify deployment.
6. Hard-refresh the contact page (`Ctrl+F5`).

No Supabase SQL is required for this correction.

## Acceptance

- Enter fewer than 10 characters in Project Details and click Send.
- Expected website message: `Project details are too short.`
- No enquiry should be sent.
- Then enter a normal message (10+ characters), complete Turnstile and submit.
- Expected: enquiry sends and arrives as before.

## Complete changed files

- `contact.html`
- `script.js`
- `tms/build.json`
- `docs/context/CURRENT_WORK.md`
- `UPDATE_063C_MANUAL_UPLOAD.md`
