# Retodo Ops TMS — TMS4 Current Handover

**Handover date:** 2026-09-19  
**Purpose:** Start a new GPT/Codex workstream without reconstructing TMS4 from chat. Reconciled against private Master v0.15 and GitHub `main` on 2026-09-19.

---

## 1. Canonical decisions to preserve

### Compliance evidence

Education:
- Highest relevant degree
- Degree type
- Field of study
- Institution
- Country
- Graduation date/year
- Diploma/certificate upload

Professional:
- Translation professional since `MM/YYYY`
- Revision professional since `MM/YYYY`
- MTPE professional since `MM/YYYY`
- Evidence type: CV
- Evidence files upload

Derived:
- X years Y months dynamically from current month
- ISO 17100 Translator/Reviser eligibility + rationale
- ISO 18587 Post-editor eligibility + rationale

### Agreement/signing

- No separate `Send Agreement`.
- Preserve original DOCX template.
- Retodo first-signature stage is part of the locked Compliance/signing flow.
- Resource performs second/final signature with `Accept and sign`.
- Final filled/signed PDF must be downloadable.
- Admin sees filled/signed agreement.
- Resource can save Compliance progress.
- Admin can request changes.
- Resource may edit and resubmit requested Compliance changes.
- ID/Tax/VAT uses one combined field where specified.

### PO

- one Job PO series;
- V1/V2/V3 immutable history;
- one active version;
- old versions remain immutable in PO history; exact historical label/status is unresolved;
- no separate Resource acceptance;
- PO send/issue implies assignment;
- decline → cancellation/reassignment path.

### Resource access

- admin-created/imported Resource can exist without Auth;
- separate access invitation;
- invitation → password → automatic portal activation → Resource dashboard;
- work approval remains separate;
- Resource access remains RLS-restricted to own operational data;
- Client hidden by default.

### Storage

- Cloudflare R2 direction;
- Supabase-storage/Drive archival concept is superseded for main TMS file storage;
- authorized completed-job access remains possible;
- Update 045 package contains archive/delete lifecycle timings, but the exact timing policy is not locked and still requires reconciliation/live acceptance.

---

## 2. Known implementation progression

Latest consolidated prior-session status:

- Update 044 — substantial PO/file/issues scope prepared/tested historically; exact production state should be reconciled.
- Update 045 — partial.
- 048–049 — reported deployed.
- 050 — deployed but rejected because:
  - deadline/V3 behavior incorrect;
  - Resource missing in Dashboard.
- 051 — later source advances it to implemented-reported/narrowly supported.
- 052 — reported deployed; Project/Scoop Cancelled flow PASS.
- 053–055 — source is now present on GitHub `main`; this advances repository source state, not live acceptance.
- 056 — Global Visual System source is present on `main`; `tms/build.json` reports build `056`, source baseline Update 055.
- Production migration 051/audit 013, Netlify live build, and live two-signature/PDF acceptance remain unconfirmed.

Do not equate GitHub source presence with production migration or live acceptance.

---

## 3. Blocking defects / missing verification

### Agreement PDF
Reported blank/identical PDFs.

Need real production test:
1. populate Resource/vendor data;
2. generate correct first-signature artifact;
3. Resource final signature;
4. download final PDF as Resource;
5. download/view as Admin;
6. confirm data/signatures/version differences.

### Invitation email
Real invitation to `[redacted external Resource address]` was not received.

Need:
- provider logs;
- sender/domain verification;
- actual invitation send;
- link validity;
- retry.

### Database/deployment
Need exact latest:
- migration applied;
- code deployed;
- build result;
- production browser test.

### PO/Dashboard
Retest after recent regressions:
- dashboard Resource;
- deadline;
- V3/active PO;
- cancelled assignment;
- financial propagation.

---

## 4. Current UI task — highest-confidence immediate requirement

The Resource profile remains visually inconsistent.

User feedback to treat as class-level requirements, not a one-off checklist:

- background behind fields should be darker/clearer;
- text above `Test Test` is too small;
- `Tests & Qualifications` is not aligned correctly;
- `Save changes` is not aligned properly relative to `+ Assign Test`;
- `Compliance phase` uses different alignment from fields below;
- `Account Qualifications from approved jobs` heading is not aligned;
- question marks/help icons must sit next to the relevant heading, not below;
- explanatory text must remain inside its bubble/card;
- buttons are inconsistent in size/color/type;
- Master's degree and Diploma upload blocks differ unnecessarily in size;
- apply canonical visual design/alignment/readability rules proactively.

Before handing back an update, inspect the entire page at desktop and narrower width.

---

## 5. Known incomplete modules

- Reports: menu/planning exists; submodules not complete.
- Blind CV: requirements exist; current production completion not established.
- R2 complete lifecycle verification: not established.
- Full Compliance state-machine regression: not established.

---

## 6. Established delivery constraints

- User performs GitHub/deployment steps unless explicitly changed.
- Provide full changed files in ZIP.
- Provide SQL migrations separately.
- Do not make user manually reconstruct snippets.
- Do not unnecessarily include every repository file; include all changed/addition files with complete contents and paths.
- Preserve existing config behavior.
- No secrets.
- Test before delivery.

---

## 7. Recommended next work sequence

Parallel-safe sequence:

### Branch A — Resource profile UI
Scope: frontend layout/styles only.  
Do not touch Compliance schema/state/signing logic.

### Branch B — Production state audit
Scope: inspect code/migration history; no destructive changes.

After audit:

### Branch C — Agreement PDF/signing fix
Depends on production-state reconciliation.

### Branch D — Invitation delivery
Can run in parallel if it does not touch the same Auth files as the signing work.

Then:
- PO/Dashboard regression;
- R2 lifecycle;
- Blind CV;
- Reports.

---

## 8. Definition of a complete next handover

Next handover must state:

- exact update/branch;
- decision IDs;
- changed files;
- migration number;
- env changes;
- tests;
- migration executed? yes/no;
- deployed? yes/no;
- production browser verified? yes/no;
- current screenshot/UI result;
- unresolved defects;
- next task.


---

## 8. Reconciled current base — 2026-09-19

Use repo `RetodoOps/retodo-ops-site`, branch `main`, TMS `/tms`, current repository build marker `056`.

Before the next task:
1. verify HEAD/build marker;
2. confirm whether Netlify serves 056;
3. do not rerun migration 051 or older migrations without checking production history;
4. test Admin and Resource in separate browser profiles.
