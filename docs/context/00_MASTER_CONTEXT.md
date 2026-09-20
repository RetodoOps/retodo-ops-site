# Retodo Ops — Master Context

**Version:** 1.2  
**Canonical date:** 2026-09-19  
**Purpose:** Repo-safe operational context for Retodo Ops TMS. The private daily `Retodo_Ops_Master_Context_and_Decisions.md` remains the cross-business canonical decision/evidence register when available.

---

## 1. Company and business model

Retodo Ops is a Nordic-focused white-label language-service operation invoiced through **Retodo EOOD**, owned/managed by **Demir Atanasov**.

Primary service scope:

- Translation
- MTPE
- Proofreading / revision
- Other language services

Primary source languages: **English, German, French**.  
Primary target focus: **Nordic languages**, especially Swedish, Norwegian/NB, Finnish and Danish.

Commercial positioning:

- small specialist team rather than a broad commodity marketplace;
- white-label support for multilingual global LSPs;
- direct clients may be developed later;
- readiness for sensitive/specialized content such as medical, IFU, patents and legal;
- the new Retodo brand must not imply inherited client relationships, logos, testimonials or delivery history that Retodo itself has not earned.

The private daily Master is the cross-business source of truth. This repository context pack is the Codex/development mirror and must be reconciled against the Master and current code.

---

## 2. Core TMS purpose

The TMS manages the operational chain:

**Client → Account → Project → Scoop → Job → Resource / PO → Financials**

Supporting modules include:

- external Resources;
- Internal resources;
- Clients & Accounts;
- Project / Scoop / Job workflow;
- Client price cards;
- Resource rate cards;
- POs and PO versions;
- Files;
- Delivery / files / issues;
- Compliance;
- Tests & Qualifications;
- Blind CV;
- Settings catalogs;
- Dashboard;
- Reports.

`Scoop` is Retodo's chosen term for an item/work package inside a project. Do not rename it to “item” in the product unless explicitly instructed.

---

## 3. Technology baseline

Known architectural baseline from prior TMS sessions:

- frontend/application: static HTML/JavaScript/CSS under `/tms`, with Netlify Functions for server-side actions;
- authentication/database: Supabase;
- hosting/deployment: Netlify;
- file/object storage: **Cloudflare R2** for the TMS file-storage direction;
- email: implementation has evolved (Gmail OAuth / provider-backed sending in prior work); the currently active provider and production delivery path must be verified in code/environment before changing it;
- memoQ integration: planned later, not a current dependency.

Repository: `RetodoOps/retodo-ops-site`, branch `main`; the same repository contains the public site and the TMS. `RetodoOps/Retodo-App` is a separate HR/Luma People application.\n\nImportant: an older Supabase-storage / Google-Drive archival concept was superseded for new TMS operational file bytes by the Cloudflare R2 direction.

---

## 4. Canonical entity model

### Client

Represents the legal/commercial client organization.

A Client may have multiple Accounts.

### Account

Commercial/operational subdivision under a Client.

Account owns or selects client-specific commercial settings such as price cards.

### Project

Top-level operational container.

Project aggregates Scoops and Financials. Project Financials should be calculated/read-only rather than independently edited when values already originate from Scoops/Jobs/POs.

### Scoop

Primary ownership boundary for:

- project item/work-package scope;
- source and target language;
- client-side price;
- client deadline;
- linked Jobs;
- scoop-level profit/margin.

Scoop language and deadline changes synchronize to connected views/jobs according to locked workflow rules.

### Job

Execution task inside a Scoop.

A Job carries a service/step (e.g. Translation, Proofreading, MTPE), resource assignment, supplier cost and PO relationship.

Job languages inherit from the Scoop but remain editable where already locked.

### Resource

External freelance/vendor linguist/resource.

Resource commercial rates, eligibility, access, tests, qualifications and Compliance are separate concerns.

### Internal resource

Internal staff record. Core fields were simplified to:

- Name
- Position
- Gender
- Email
- Status

Multiple roles can be assigned (e.g. PM, QA, Project). Deactivation preserves history.

### PO

Supplier purchase order tied to a Job. One active commercial PO version per Job; prior versions remain as history.

### Financials

Derived from the underlying commercial data:

- Client value
- Supplier cost
- Profit
- Margin %

The client price and supplier cost are separate sources and must never be conflated.

---

## 5. Naming conventions

Project naming is date-first and includes client/account context, target language and a reference.

Known example:

`260828_TEST_SV_TMSQA001`

Scoops use sequential identifiers:

- `S01`
- `S02`
- etc.

Jobs use service/step plus sequential job index, e.g.:

- `TRA J01`
- `PROOF J02`

PO naming/versioning must remain tied to the relevant project/job context and clearly expose the active version.

A historical generic `PO-YYYY-NNNN` concept existed earlier; later P0 work moved toward contextual PO naming. Do not reintroduce an older naming rule if current schema/UI uses the contextual naming standard.

---

## 6. Workflow principles

### Projects

Conceptual lifecycle:

`Offered → Ongoing/In progress → Ready to deliver → Delivered → Approved → Invoiced → Paid`

Alternate terminal paths include `Declined` / `Cancelled`.

Use the exact enum labels implemented in the current schema/UI; do not change them merely for wording consistency without approval.

### Jobs

Jobs begin unassigned.

Operational states include the established flow around:

- Unassigned
- Assigned
- Ongoing
- Waiting
- Delivery
- Completed
- Approved
- Cancelled

PO sending/assignment drives assignment behavior according to the locked PO rules.

### Scoops

Scoop state reflects the state/assignment of its jobs. Do not create an independent scoop state machine that can contradict the jobs without a locked rule.

---

## 7. Pricing and margin model

Client price:

- preferably comes from an Account-specific price card;
- supports CAT-grid quantities;
- can support flat-fee/manual pricing when no applicable rate exists.

Resource cost:

- comes from resource rate cards by language pair, service and specialization where available;
- may use manual/flat-fee assignment when needed.

CAT pricing must preserve row-level quantities and calculations.

The system must display:

- Client value
- Supplier cost
- Profit
- Profit margin %

Target commercial policy:

- target average margin: **50%**;
- lowest normal margin threshold: **40%**;
- work below threshold is exception-based, not a silent default.

---

## 8. PO model

Locked direction:

- one PO relationship per Job with immutable/versioned revisions;
- active version is the operational one;
- older versions remain visible in PO history; the exact historical display/status label is not locked and must not be invented from `Overridden`/`Superseded` examples;
- normal dashboards/lists show only active POs;
- resource PO acceptance was removed;
- sending/issuing the PO implies assignment;
- if the Resource later declines, the PO is cancelled rather than waiting for a separate acceptance step;
- supplier-cost changes must flow to Job → Scoop/Project Financials and margin;
- client price remains independent from supplier PO changes.

Post-delivery commercial corrections are handled as explicit adjustments/versioned commercial history rather than destructive overwrite.

---

## 9. Resource onboarding and access

There are three distinct concepts:

1. Resource record exists.
2. Resource has portal Auth/access.
3. Resource is approved/eligible for work.

These must not be collapsed.

### Admin-created/imported Resource

- may exist without Auth;
- receives portal access only through a separate invitation;
- invitation flow: invitation → password creation → automatic portal activation → Resource dashboard;
- no redundant second “approve access” step.

### Self-registration

Self-registration is allowed and is distinct from staff-created invitation flow. The exact activation/pending-approval behavior is currently unresolved because earlier decisions and the observed existing-account recovery path conflict. Do not invent or generalize a stage until the exact policy is recovered/approved.

### Permissions

External Resource sees only its own:

- Jobs
- active/historical POs as allowed
- files
- issues
- minimal Project/Scoop context needed to work

Client identity/name is hidden by default from external Resources unless explicitly disclosed.

Preserve RLS.

---

## 10. Files and storage

Current strategic storage decision:

- Cloudflare R2 for TMS operational file storage;
- TMS-mediated authorization;
- short-lived presigned links where appropriate;
- external Resource access remains available for relevant completed Jobs, subject to permissions;
- Update 045 package source contains a 3-month archive / 24-month archived-binary deletion mechanism with holds, but those timings are implementation-package behavior and were not recovered as a locked business retention policy. Do not promote them to policy or remove them without reconciliation.

Project/application archival may exist separately from physical file deletion.

Earlier concepts involving private Supabase storage plus Google Drive archival are historical/superseded for the main TMS storage direction.

File lifecycle must support:

- admin upload/access;
- external resource access to allowed files;
- delivery files;
- issue-related files;
- duplicate-file deletion where authorized;
- counters/visibility for Delivery, files & issues;
- download/access logging where implemented/required.

---

## 11. Compliance and qualification model

Compliance is separate from normal resource profile data and must support the ISO-oriented qualification evidence model.

### Education evidence — locked

- Highest relevant degree
- Degree type
- Field of study
- Institution
- Country
- Graduation date/year
- Upload diploma/certificate

### Professional experience — locked

- Translation professional since: `MM/YYYY`
- Revision professional since: `MM/YYYY`
- MTPE professional since: `MM/YYYY`
- Evidence type: CV
- Evidence file(s): upload

The `MM/YYYY` start values are the source of truth.

Durations are calculated dynamically against the current month, e.g.:

- Translation experience: X years Y months
- Revision experience: X years Y months
- MTPE experience: X years Y months

### Internal eligibility

The system determines and records eligibility/rationale for:

- ISO 17100 Translator/Reviser
- ISO 18587 Post-editor

### Test record

Post-TMS test record includes:

- pre-TMS tested checkbox/indicator;
- result pass/fail;
- job/test size in words/hours.

Resource may work before full Compliance when the business workflow allows it; Compliance is prompted after test pass according to the locked flow.

---

## 12. Agreement and signature model

Latest locked direction from TMS4:

- no separate “Send Agreement” action;
- agreement is auto-filled from vendor/resource details;
- Retodo performs the first signature in the established Compliance flow;
- the Resource uses **“Accept and sign”** for the second/final signature;
- ID/Tax/VAT is treated as one field where specified in the agreement/profile workflow;
- after signing, the completed/final PDF must be downloadable;
- admin must be able to see the filled/signed version;
- Resource can save progress in Compliance;
- admin can review and request Compliance changes;
- Resource can edit and resubmit requested Compliance changes;
- notifications accompany relevant submission/review steps;
- the original DOCX agreement remains the canonical template/source document unless explicitly replaced.

Do not alter the signing sequence based on assumptions; consult `01_DECISION_REGISTER.md` and the latest handover.

---

## 13. Blind CV

Blind CV generator is intended to use approved Resource profile data, including dynamically calculated experience.

Known presentation requirements:

- Retodo logo/header;
- language pairs stacked vertically;
- no client-confidential information;
- qualification/experience data derived from source fields rather than manually duplicated text.

Implementation/completion status is tracked in `06_CURRENT_STATE.md` and `07_OPEN_ISSUES.md`.

---

## 14. Dashboard and reports

Dashboard requirements accumulated across sessions include:

- Job linguist/resource visible;
- sorting controls/arrows;
- overdue Scoop deadlines shown in red;
- only active POs in operational views;
- connected Project/Scoop/Job context;
- relevant counters for delivery/files/issues.

Reports menu exists/was planned, but report submodules remain incomplete as of the current handover.

---

## 15. Operating policies outside the TMS

Freelancer/vendor commercial defaults:

- invoicing dates: **15th and 30th** of each month;
- payment term: **60 days**.

Sales/outreach sequence:

- initial outreach should prioritize clients with highest probability of onboarding/need;
- indicators include public vendor registration links, explicit recruitment, and likely Nordic end-client demand;
- first waves are also used as training/feedback before targeting the strongest strategic prospects.

---

## 16. Current repository snapshot — 2026-09-19

Verified in `RetodoOps/retodo-ops-site` `main`:

- Update 055 source was committed to `main`.
- Update 056 Global Visual System was committed to `main`.
- `tms/build.json` reports build `056`, release `Update 056 - Global visual system refresh`, source baseline `Update 055`.
- Context Pack v1.0 was subsequently added to `main`; v1.2 supersedes those context files.

Update 056 changes UI/auth-session behavior only and declares no new migration, database audit, or environment variable.

Repository presence does **not** prove:
- migration 051 was executed in production;
- audit 013 passed in production;
- Netlify currently serves build 056;
- the two-signature Agreement flow passed live acceptance;
- invitation delivery is fixed.

Separate Admin and Resource browser profiles/incognito remain the recommended simultaneous-session test setup.


---

## 17. Durable-memory rule

No material product decision should live only in a ChatGPT conversation.

After approval:

- add it to `01_DECISION_REGISTER.md`;
- update `06_CURRENT_STATE.md`;
- remove/reclassify related entries in `07_OPEN_ISSUES.md`;
- add an implementation report/handover when code or production state changes.
