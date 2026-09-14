# Retodo Ops TMS — Update 052 Interface Completion

## Scope

This release completes the six items recorded after Update 051 acceptance:

1. Dashboard bulk Change Status includes `Cancelled` and applies the selected status to the selected Scoop rows and their Projects.
2. The Job sidebar keeps the Reports menu and all four report links.
3. Blind CV preview, DOCX and PDF load the Retodo Ops PNG from the published `tms/` directory.
4. Self-registration uses build 052 assets, gives immediate progress/error feedback, handles existing TMS sessions safely and distinguishes an already registered email.
5. Agreement `ID / Tax / VAT` is one combined portal field. The existing two database columns are populated with the same combined value for backward compatibility.
6. After electronic acceptance, the portal download changes from the original DOCX to a filled signed PDF containing the agreement terms, Service Provider details, signatory, authenticated registration email, acceptance timestamp, version and immutable document hash.

## Deployment order

1. Run `tms/migrations/050_update_052_dashboard_cancelled_status.sql` once in Supabase SQL Editor.
2. Run `tms/audits/012_update_052_interface_completion_audit.sql`; all four rows must be `PASS`.
3. Upload all files from `RetodoOps_Update_052_Interface_Completion.zip` to the repository root, preserving their paths, and publish through the existing GitHub/Netlify flow.
4. Confirm `https://tms.retodo-ops.com/build.json` reports build `052`.
5. Run the acceptance block below.

No environment-variable change is required. Do not rerun migration 049 or Audit 011.

## Acceptance block

1. Dashboard: select one or more Scoop rows, choose `Cancelled`, apply, refresh, and confirm the selected rows remain `Cancelled` and appear in the Cancelled tab.
2. Job: open any Job and confirm Reports remains visible in the left menu and each report link opens.
3. Blind CV: open preview, download DOCX and PDF, and confirm the Retodo Ops logo appears in all three.
4. Registration: open the public registration link in a browser that currently has a company TMS session, submit a new unique email, and confirm the button shows progress followed by the confirmation-email message. Complete the email link and confirm the Resource is created pending approval.
5. Agreement: before acceptance confirm original DOCX download; confirm there is one `ID / Tax / VAT` field; accept; then click `Download signed PDF` and confirm the full terms, entered details and electronic signature/acceptance block are present.

## Database impact

Migration 050 only widens the existing Project and Scoop status constraints to include `Cancelled`. It does not alter existing rows, PO history, Compliance evidence or accepted agreement snapshots.
