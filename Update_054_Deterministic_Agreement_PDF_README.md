# Retodo Ops TMS - Update 054

## Scope

This is an upload-only corrective release based on Update 053.

- Replaces the blank `html2canvas` Agreement export with direct vector PDF generation through jsPDF.
- Includes the full 15-clause Agreement, Retodo party details, Resource details, combined ID / Tax / VAT value, authenticated signatory, registration email, acceptance timestamp, Agreement version, document SHA-256 and page numbers.
- Uses the same generator from the Resource Portal and the internal Resource page.
- Preserves Update 053 registration recovery and all Update 052 functionality.

## Deployment

1. Publish all files with their included paths to GitHub / Netlify.
2. Confirm `/build.json` reports build `054`.
3. Download the signed PDF once from the Resource Portal and once from the internal Resource page.
4. Confirm both PDFs contain the full Agreement and acceptance details.

No migration, audit SQL or new environment variable is required. Do not rerun migrations 049/050 or audits 011/012.

The Reports module and submenu design remain outside this corrective release.
