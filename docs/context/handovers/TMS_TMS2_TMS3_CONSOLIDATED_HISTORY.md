# Retodo Ops TMS — Consolidated Session History

**Purpose:** Historical continuity from TMS → TMS2 → TMS3 → TMS4.  
**Date compiled:** 2026-09-19

This is not the current-state source of truth. Use the Decision Register and Current State first. This file preserves why the architecture evolved.

---

## 1. TMS — foundational implementation

Early TMS work established:

- Projects / Jobs / Offers / POs as separate operational concepts.
- Jobs start unassigned.
- Exact language-pair matching for Resource assignment.
- Initial PO identifier concept `PO-YYYY-NNNN`.
- Issued POs locked and revisions versioned.
- Client hidden from Resource by default.
- Admin-only commercial issue/revise/disclose behavior.
- Financial fields on Job: Client value, Supplier cost, Profit, Profit margin %.
- Gmail/OAuth-based PO email work was introduced but had delivery/token issues.

### Migration / update landmarks

Known reported sequence includes:

- Migration 019: Resource assignment/PO creation/Job assignment behavior; user reported success.
- Deploy 020: Job Client value / Supplier cost / Profit / Margin fields and calculations.
- Migration 020 / Deploy 021: completed before an email `Bad Request` investigation.
- OAuth issue: `invalid_grant` occurred while obtaining token; diagnosis pointed to OAuth refresh/client mismatch rather than PO logic.

### Historical email configuration

A Gmail send flow used:
- Google OAuth client for Retodo Ops TMS / Netlify;
- account authorized for Gmail send;
- `ops@retodo-ops.com` used as a send-as alias.

Do not store OAuth secrets/tokens in this repository.

---

## 2. TMS2 — financial synchronization and product model expansion

TMS2 work expanded and corrected:

- PO revision supplier-cost synchronization;
- Job → Project expense/profit/margin flow;
- client price kept separate;
- status transitions kept independent from pure financial edits;
- project/PO naming and versioning refinements;
- Client Accounts and price cards;
- Resource pricing/eligibility;
- Files and access;
- resource registration/onboarding;
- migration packaging.

### Update 024

Reported behavior:
- PO V2 supplier cost updates Job supplier cost;
- Project expense/profit/margin update;
- Client price remains unchanged.

Regression fixture:
- Client = 31.00 EUR
- Supplier = 10.68 EUR
- Profit = 20.32 EUR
- Margin = 65.55%

Migration 022 was a prerequisite in the reported sequence.

### Terminology / hierarchy

On 2026-09-03 the user locked the term `Scoop`.

Further locked UI/data behavior:
- Scoop source/target languages editable;
- connected Jobs/dashboard synchronize;
- individual Scoop price/profit/margin;
- Scoop-linked dashboard and Job breadcrumb;
- full language dropdowns.

---

## 3. TMS3 — P0 architecture hardening and onboarding

TMS3 converged on the architectural baseline:

`Client → Account → Project → Scoop → Job → Resource/PO → Financials`

### P0 baseline — reported complete 2026-09-06

Included:
- Scoop-owned pricing/deadlines;
- read-only Project Financials;
- contextual PO naming;
- manual/flat-fee assignments;
- corrected Scoop status transitions;
- full CAT breakdown;
- job languages inherit from Scoop but remain editable;
- zero-quantity selector removed;
- overdue Scoop deadlines red.

### Update 036

Reported:
- commit `1eaeb9f3`;
- migration 033 executed;
- tests around Financials/Scoop, CAT zero rows, PO naming, Accounts, specialization, pricing/status, Job→Scoop transitions and manual financial rows.

The commit hash is historical evidence only; do not assume it is the current repository head.

### Resource onboarding direction

Locked 2026-09-07:
- external admin-created/imported Resource has no Auth initially;
- separate access invitation;
- self-registration is end-to-end;
- internal Resource may auto-create Auth/invitation;
- work approval separate.

Update 040 was reported as onboarding implementation work with migration 040 and local tests.

### Update 042

Locked access semantics:
- invitation → password → automatic activation → Resource dashboard;
- no separate access approval;
- preserve RLS;
- Resource sees only own Jobs/POs/files/issues plus minimal Project/Scoop context without Client name.

Reported after deployment:
- migration 041 succeeded;
- password activation/direct Resource dashboard confirmed.

### Update 044

Prepared scope:
- active-only PO views;
- Superseded history labels;
- private Job-file lifecycle;
- staff issue workflow.

Around this stage the storage strategy moved from the earlier Supabase/Drive concept to Cloudflare R2 EU/object storage with TMS-mediated access.

---

## 4. TMS4 — Compliance, Agreement, PO regression work and UI quality

TMS4 concentrated on:

- locked ISO-oriented Compliance fields;
- dynamic professional experience;
- tests/qualifications;
- Agreement autofill/signing;
- PDF output;
- Resource/Admin Compliance UX;
- PO version/status regressions;
- access invitation delivery;
- UI consistency.

### Locked Compliance decision — 2026-09-10

Education:
- Highest relevant degree
- Degree type
- Field of study
- Institution
- Country
- Graduation date/year
- Upload diploma/certificate

Professional:
- Translation professional since `MM/YYYY`
- Revision professional since `MM/YYYY`
- MTPE professional since `MM/YYYY`
- Evidence type: CV
- Evidence files

Derived experience recalculates automatically.

### Signing-flow decision — 2026-09-14

Locked:
- no separate Send Agreement;
- preserve original DOCX source;
- Retodo first-signature stage in Compliance flow;
- Resource second/final `Accept and sign`;
- ID/Tax/VAT as one field where specified;
- final filled PDF downloadable;
- save progress;
- admin visibility/review;
- request changes and resubmission.

### Update progression known as of 2026-09-18

- 048–049: reported deployed.
- 050: deployed but rejected due deadline/V3 issues and missing Resource on Dashboard.
- 051: prepared, deployment not confirmed.
- 052: deployed; Cancelled path reported PASS.
- 053–055: prepared, latest deployment/implementation not confirmed.

### Latest blockers

- blank/identical Agreement PDFs;
- real two-sided signing/PDF test incomplete;
- real invitation email delivery unverified;
- production migration/audit/build reconciliation missing;
- Reports incomplete;
- Blind CV completion unclear;
- full R2 file lifecycle verification incomplete.

### Latest UI direction

The user explicitly requires canonical, holistic UI quality rather than listing each defect after every update. Current Resource-profile defects are captured in `04_UI_UX_RULES.md` and `07_OPEN_ISSUES.md`.

---

## 5. Supersessions to remember

Historical concept → Current direction:

- generic PO-only numbering → contextual Project/Job PO naming/version display;
- Resource PO acceptance → send/issue implies assignment;
- Supabase operational files + Google Drive archive → Cloudflare R2 operational file direction;
- Resource record automatically implying Auth → Resource record and portal access separated;
- ad hoc chat memory → repository-based canonical context/decision register.

When old code still follows a superseded rule, treat it as technical debt unless a newer decision says otherwise.
