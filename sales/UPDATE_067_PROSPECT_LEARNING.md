# Update 067 — Prospect learning set and buyer-profile research

## Outcome

This update turns the two supplied prospect lists into one auditable Sales learning set.

- 7,674 historic client/contact rows were used as purchase-history evidence.
- 255 named accounts were reconciled; 228 matched exactly after normalization and 234 had a high-similarity match.
- 26 current canonical buyer organizations are seeded into Sales at `qualified` stage.
- 67 historic rows merge into those canonical prospects instead of creating duplicates.
- 12 rows are explicit negative examples and 8 are merge/re-verify examples.
- 163 rows remain on hold until current official buyer evidence is verified.
- Four public role-based application contacts are included as unverified. Historical personal contact emails are not copied into the learning profile or web-research context.
- Automatic research remains off. The migration creates no conversations, messages, approvals or outreach.

## Buyer profile

The research target is a current multi-language LSP or localization company that demonstrably buys external language capacity and can need Nordic target languages. Strong evidence includes a current official supplier/vendor/agency/freelancer/linguist route, recent demonstrated purchasing in the supplied history, and current Nordic-language demand.

The AI must exclude Retodo itself, direct end clients in this search stream, individuals, directories/marketplaces, unsupported competitors, inactive entities and acquired/rebranded names as separate prospects. Current canonical names and domains are required.

## Research corrections

- Research receives the saved buyer profile, current Sales company names/domains and suppressed domains before the paid request is queued.
- Citation matching removes tracking parameters such as `utm_*`, `gclid` and `fbclid`, while preserving the URL scheme, host, path and non-tracking query.
- Result records now distinguish AI-returned candidates, evidence-validation rejections, existing prospects, suppressions, insert conflicts and actual imports.
- The Today card and result dialog show those real counts. They no longer always claim that existing companies were skipped.
- The previous service dispatcher remains installed for compatibility. The worker uses service-only `sales_system_067` for the new research context and outcomes.

## Installation

1. Upload the complete files listed in `UPDATE_067_MANUAL_UPLOAD.md` to current main. Do not delete or replace Update 066 invoice files.
2. Run `tms/migrations/063_sales_prospect_learning.sql` once in the Supabase SQL editor.
3. Run `tms/audits/021_update_067_sales_research_audit.sql`. All 15 rows must report `PASS`.
4. Deploy the updated site/functions and hard-refresh Sales. The build must show 067.
5. Confirm Sales → Prospects contains the 26 canonical companies at `qualified` stage. Confirm automatic research is off.
6. Review the four public role contacts on their linked official pages before marking any contact verified.

## Controlled acceptance test

After installation, run one on-demand research task with a narrow brief. Do not enable automatic research. The completed card must show separate counts for returned, evidence checks, validation rejections, existing companies, suppressions, conflicts and added prospects. A zero-import result is acceptable only when those counts explain why.

No outreach is authorized by installing or testing this update.
