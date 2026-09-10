# RetodoOps Update 045 — Cloudflare R2 deployment

This release keeps Supabase for Auth, metadata, RLS and immutable audit records.
Job-file binaries are stored in one private Cloudflare R2 bucket in the EU
jurisdiction. Neither the browser nor an External Resource receives an R2 API
credential.

## Required order

1. Run `tms/migrations/044_cloudflare_r2_file_lifecycle.sql` once in the
   Supabase SQL Editor. Migrations 036–043 remain unchanged.
2. Create a private EU-jurisdiction R2 bucket and an R2 S3 API token limited to
   object read/write for that bucket.
3. Apply `R2_CORS_POLICY.json` to the bucket. Keep public access and the R2.dev
   subdomain disabled.
4. Apply `R2_LIFECYCLE_POLICY.json`. Do not add native automatic object archive
   or delete rules: the TMS worker owns those decisions so that Restore and
   Retention Hold remain authoritative.
5. Add the variables below to the production Netlify site, then upload all
   release files with their preserved paths.
6. Run `tms/audits/006_update_045_r2_file_lifecycle_audit.sql` in Supabase. Every
   result row must report `PASS`.

## Netlify environment variables

No values belong in GitHub or this ZIP.

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | Existing Supabase project URL, server-side use |
| `SUPABASE_SERVICE_ROLE_KEY` | Existing service-role key, Netlify Functions only |
| `R2_ENDPOINT` | EU S3 endpoint: `https://ACCOUNT_ID.eu.r2.cloudflarestorage.com` |
| `R2_ACCESS_KEY_ID` | Bucket-limited R2 S3 access-key ID |
| `R2_SECRET_ACCESS_KEY` | Bucket-limited R2 S3 secret |
| `R2_BUCKET_NAME` | Private Job-file bucket name |
| `FILE_LIFECYCLE_WORKER_SECRET` | New random value of at least 32 bytes |
| `TMS_SITE_URL` | `https://tms.retodo-ops.com` |

Optional controls:

| Variable | Default | Allowed behavior |
|---|---:|---|
| `R2_SIGNED_URL_TTL_SECONDS` | `1800` | GET link: 60 seconds through 604800 seconds (7 days) |
| `R2_UPLOAD_URL_TTL_SECONDS` | `1800` | PUT link: 60 seconds through 604800 seconds (7 days) |
| `R2_ARCHIVE_ZIP_MAX_BYTES` | `536870912` | ZIP strategy ceiling; 16 MiB through 4 GiB |

Changing a signed-link TTL affects newly created links only. Resource access
itself does not expire with the URL: while the assignment and file are active,
each click asks the TMS for a fresh short-lived URL.

## Locked lifecycle behavior

- Default archive clock: three months after the Project's latest transition to
  `Approved`.
- Leaving `Approved` before archive cancels the pending automatic archive. A
  later transition back to `Approved` starts a new clock.
- Archives are per Job. Compressible groups become a verified ZIP with a
  manifest and SHA-256 checksums; already-compressed or oversized groups move
  to R2 Infrequent Access without wasteful recompression.
- The worker verifies the archive, commits the archive metadata, then uses a
  separate idempotent cleanup task to re-verify the surviving copy before any
  redundant object is removed. An interrupted worker is therefore recoverable
  without a missing-file window.
- Archived files disappear from the Resource portal until staff restores them.
- Restore returns objects to Standard storage, restores Resource access,
  cancels permanent deletion and resets the archive clock.
- Permanent binary deletion occurs only after 24 continuous months in
  `Archived`, unless a Client, Account or Project Retention Hold applies.
- PO, finance, issue, file metadata and immutable audit rows are not deleted
  with the binaries.
