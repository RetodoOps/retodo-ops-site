# Update 068 — Cold-prospect confidentiality guard

## Reason

The supplied historical lists describe work performed through another business, not engagement with Retodo Ops. They remain useful for confidential ranking, canonical-name reconciliation and identifying likely buyers, but they must never be exposed or paraphrased in Retodo Sales notes, materials or outreach. Every prospect is a first-time cold prospect to Retodo Ops.

The first controlled Update 067 research test also showed that a broad European-language careers page could pass through on an inferred Nordic fit. Update 068 requires public evidence of both outside-capacity sourcing and current Nordic-language demand.

## Changes

- The saved buyer profile is upgraded to version 2 with `cold_outreach_only=true` and an explicit confidential-history rule.
- Automatic research remains off.
- Update 067 seed text is replaced with public-only fit statements. Prospect stages, contacts, conversations and user workflow history are preserved.
- The specific Jensen relationship note suggested during acceptance is removed if present. Jensen remains a cold qualified prospect.
- Research instructions require two current public signals: an external supplier/vendor/freelancer route and Nordic-language demand, recruitment or delivery need.
- General European coverage, ISO certification, company age, size or broad service capability are explicitly insufficient.
- Research validation rejects results whose fit statement does not contain both signals or contains confidential relationship wording.
- Writing requests exclude free-form prospect fit notes and notes. They receive only public identity fields and a fixed cold-outreach mode.
- Draft and material validation fails closed if generated copy implies a previous client, project, order, collaboration or relationship.
- The Sales dialogs explain the cold-only rule before research or writing is queued.

## Installation

1. Upload all complete files listed in `UPDATE_068_MANUAL_UPLOAD.md` over installed Update 067.
2. Run `tms/migrations/064_sales_cold_prospect_guard.sql`.
3. Run `tms/audits/022_update_068_sales_cold_prospect_audit.sql`; all 10 rows must report `PASS`.
4. Deploy and hard-refresh Sales. Confirm build 068 and Research remains `On demand`.
5. Do not enable automatic research. A later controlled test should use the same narrow brief and confirm weak inferred Nordic matches are counted under validation rejection.

No outreach or paid AI request is performed by this update.
