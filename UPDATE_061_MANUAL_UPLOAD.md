# Update 061 — Project enquiry anti-spam

Baseline: main `0c704f05e762f588cafcb3cd7e53ac44534cba95` / Update 060.

## Before installation
The user has already configured the private Netlify environment variable:
`TURNSTILE_SECRET_KEY`

Do not put its value in GitHub.

Cloudflare public Site Key used by the form:
`0x4AAAAAAFE58tRuuQcvpTkl`

## Install
1. Extract this ZIP.
2. Upload all extracted files/folders to the root of `RetodoOps/retodo-ops-site` on branch `main`, preserving paths.
3. Replace the existing files with these complete versions.
4. Commit, e.g. `Update 061: protect project enquiry with Turnstile`.
5. Wait for the normal Netlify deployment. No Supabase SQL is required.
6. Hard-refresh `https://retodo-ops.com/contact.html`.
7. Submit one genuine test enquiry.

## Expected result
- Cloudflare Turnstile appears/operates on the enquiry form.
- A genuine verified enquiry is delivered to ops@retodo-ops.com.
- Requests without a valid Turnstile token are rejected before Gmail delivery.
- Existing honeypot and origin checks remain active.
- Invalid select values and past deadlines are rejected server-side.

## Files
- `contact.html`
- `script.js`
- `netlify/functions/submit-project-enquiry.js`
- `tms/build.json`
- `docs/context/CURRENT_WORK.md`
- `UPDATE_061_MANUAL_UPLOAD.md`

## Production acceptance
After deployment, send one normal enquiry. Then test a past deadline in the browser by temporarily changing the date input value through devtools only if desired; it should not send. Do not expose the Turnstile secret during testing.
