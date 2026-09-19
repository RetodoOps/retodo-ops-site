# Retodo Ops TMS — Business Rules

**Version:** 1.0  
**Date:** 2026-09-19

---

## 1. Commercial defaults

### Freelancer payments

- Standard freelancer invoicing dates: **15th and 30th** of each month.
- Standard freelancer payment term: **60 days**.

These are operating defaults, not permission to overwrite a client/resource-specific agreed term.

### Margin

- Target average margin: **50%**.
- Normal lowest threshold: **40%**.
- Below-threshold work is an exception requiring conscious handling.

The TMS should expose margin clearly; do not silently hide low-margin work.

---

## 2. Client/account pricing

- Price cards belong to the client/account context.
- A Project/Scoop must not be forced to select meaningless units before a valid price card is known.
- Specialization is a controlled/catalog value where applicable.
- Pricing can be edited after initial selection as allowed by workflow.
- Flat fee is supported when rate-card pricing does not apply.

---

## 3. Resource rates

Resource rates depend on:

- source language;
- target language;
- service;
- specialization;
- agreed unit/rate.

Assignment must use the exact language pair rather than broad “language” matching when an exact pair is required.

Manual/flat-fee supplier cost remains possible.

---

## 4. Assignment

- Job starts unassigned.
- Sending/issuing active PO implies assignment.
- Separate Resource PO acceptance is not required.
- Resource decline after assignment cancels/replaces the commercial assignment according to PO versioning rules.
- Do not expose Client name to external Resource by default.

---

## 5. Resource lifecycle

Possible business dimensions must remain independent:

- active/inactive profile;
- portal access/no access;
- approved/not approved for work;
- test result;
- Compliance state;
- qualification/ISO eligibility;
- blacklisted status;
- pending payments.

A blacklisted Resource with pending financial obligations must not lose historical/payment data.

---

## 6. Internal resources

Core profile:

- Name
- Position
- Gender
- Email
- Status

Role assignment can include multiple roles.

Deactivation must preserve history on Projects/Jobs/approvals.

PM selectors use active internal Resources with the appropriate role.

---

## 7. Compliance evidence

### Education

Mandatory/available evidence fields:

- Highest relevant degree
- Degree type
- Field of study
- Institution
- Country
- Graduation date/year
- Diploma/certificate upload

### Professional experience

Source fields:

- Translation professional since `MM/YYYY`
- Revision professional since `MM/YYYY`
- MTPE professional since `MM/YYYY`
- Evidence type: CV
- Evidence file(s)

Calculated duration is display/derived data, not an editable source.

---

## 8. ISO-oriented qualification

System supports internal evaluation/rationale for:

- ISO 17100 translator/reviser qualification;
- ISO 18587 post-editor qualification.

Do not state that a Resource is eligible merely because a UI checkbox is checked; qualification is derived from evidence/business rules.

---

## 9. Tests

Tests & Qualifications record must support:

- whether the Resource was tested before the TMS record existed;
- pass/fail result;
- test/job size in words or hours;
- relationship to Compliance prompting/qualification.

---

## 10. Agreement

- Agreement is auto-filled from approved Resource/vendor data.
- No standalone “Send Agreement” step in the locked TMS4 workflow.
- Two-party signature history must be preserved.
- Final signed PDF must be downloadable and visible to admin.
- Original agreement DOCX/template remains source material unless explicitly replaced.

---

## 11. Confidentiality / white-label behavior

Because Retodo operates as a white-label provider for other LSPs:

- Client identity is hidden from freelancers/resources by default.
- Files and messages should expose only operational information needed to perform the Job.
- Blind CV output must not leak client-confidential information.
- Resource-facing project context should be minimal.

---

## 12. Files and retention

- Operational file bytes use R2 direction.
- No automatic deletion solely by object age.
- Completed Jobs may remain accessible to the authorized Resource.
- Project archival and file deletion are separate concepts.
- Duplicate Compliance/evidence files can be deleted by authorized roles.
- Historical commercial/audit records should remain available after normal UI archival.

---

## 13. Brand and claims

Retodo Ops is a new brand.

Do not insert in:
- website;
- proposals;
- TMS;
- CVs;
- emails;
- sales copy

claims implying inherited customers, testimonials, logos, volumes or delivery history that Retodo itself cannot substantiate.

---

## 14. Outreach ordering

The initial sales wave prioritizes probability of engagement, not prestige:

- explicit vendor registration/recruitment;
- clear vendor onboarding paths;
- evidence of Nordic language demand;
- probable end-client needs in Nordic markets.

Use early outreach feedback to refine the pitch before approaching the most strategic prospects.
