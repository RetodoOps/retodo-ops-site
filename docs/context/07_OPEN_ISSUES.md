# Retodo Ops TMS — Open Issues and Backlog

**Snapshot:** 2026-09-19

Priority labels:
- `P0` blocking/security/data-integrity
- `P1` important workflow/reliability
- `P2` product completion/quality

---

## P0 — Agreement PDF correctness

**Status:** UNRESOLVED

Reported:
- Agreement PDFs blank/identical.
- Real two-sided signing/PDF validation not complete.

Acceptance:
- filled vendor/resource data visible;
- Retodo signature visible in correct state;
- Resource `Accept and sign` final signature visible;
- final PDF downloadable;
- admin can download/view filled signed PDF;
- no accidental blank/duplicate version;
- authorization correct.

---

## P0 — Production-state reconciliation for Updates 053–055

**Status:** UNRESOLVED

Latest state says prepared/not implemented or deploy unconfirmed.

Need:
- determine exact files already in production;
- determine latest executed migration;
- run schema/audit checks;
- run production build;
- document deployment and browser verification.

Do not execute old migrations blindly; inspect migration history first.

---

## P1 — Real invitation email delivery

**Status:** UNRESOLVED

Reported recipient:
`[redacted Resource address at beconnected.no]`

Issue:
- invitation not received;
- test email alone is insufficient evidence.

Need:
- verify active email provider;
- provider logs;
- sender/domain;
- recipient;
- bounce/rejection;
- invitation URL validity;
- retry idempotence.

---

## P1 — Resource profile visual consistency

**Status:** UNRESOLVED

Apply all rules in `04_UI_UX_RULES.md`.

Specific current problems:
- small test heading text;
- misaligned section headings/actions;
- question icons below headings;
- overflow text outside bubbles;
- inconsistent buttons;
- inconsistent evidence card sizes;
- insufficient field-background contrast.

Acceptance:
- full page passes holistic visual QA at desktop and narrower width.

---

## P1 — PO/Dashboard regression retest

**Status:** UNRESOLVED

Regression history:
- deadline/V3 problems;
- missing Resource in Dashboard after Update 050;
- Update 051 prepared.

Retest:
- Resource display;
- active PO only;
- V1/V2/V3 history;
- supplier cost propagation;
- deadline sync;
- cancelled flow;
- reassignment.

---

## P1 — File lifecycle/R2 end-to-end verification

**Status:** UNRESOLVED

Verify:
- admin upload;
- Resource authorized download;
- unauthorized Resource denial;
- Completed Job access;
- delivery file path;
- issue attachments;
- duplicate Compliance file deletion;
- metadata/history;
- presigned URL expiry;
- no unintended age deletion.

---

## P1 — Compliance end-to-end state machine

**Status:** UNRESOLVED

Verify actual production path:
- draft/save;
- submit;
- admin review;
- request changes;
- Resource edit/resubmit;
- Retodo signature stage;
- Resource final signature;
- final PDF;
- email notifications;
- calculated experience;
- ISO eligibility rationale.

---

## P2 — Reports module

**Status:** UNRESOLVED

Reports menu exists but submodules are not complete.

Before implementation:
- define reports/KPIs;
- confirm data source and filters;
- avoid duplicating Financials source of truth.

---

## P2 — Blind CV completion

**Status:** UNRESOLVED

Verify/build:
- Retodo branding/header;
- stacked language pairs;
- education evidence;
- calculated experience;
- qualifications;
- no client-confidential data;
- PDF/export formatting if required.

---

## P2 — Context synchronization discipline

**Status:** ACTIVE PROCESS

Prior rolling handover became stale around earlier updates.

This pack replaces that weakness with:
- canonical decision register;
- current-state file;
- latest handover;
- required end-of-update context maintenance.

Every future material update must maintain these files.
