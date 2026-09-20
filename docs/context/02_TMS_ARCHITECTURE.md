# Retodo Ops TMS — Architecture

**Version:** 1.2  
**Date:** 2026-09-19

---

## 1. Logical architecture

```text
Users / Roles
   |
   +-- Admin / Internal Resource
   |      |
   |      +-- Clients & Accounts
   |      +-- Projects
   |      |    +-- Scoops
   |      |          +-- Jobs
   |      |                +-- Resource assignment
   |      |                +-- PO versions
   |      |                +-- Files / delivery / issues
   |      |
   |      +-- Resources
   |      |    +-- Tests & Qualifications
   |      |    +-- Compliance
   |      |    +-- Agreement
   |      |    +-- Rate cards
   |      |
   |      +-- Financials / Reports
   |
   +-- External Resource
          |
          +-- Own Jobs
          +-- Own POs
          +-- Allowed files/delivery/issues
          +-- Own profile / tests / compliance
```

Core infrastructure:

```text
Static TMS HTML / JavaScript / CSS (`/tms`)
   |
   +-- Netlify Functions (`/netlify/functions`) for server-side actions
   +-- Supabase Auth
   +-- Supabase PostgreSQL + RLS
   +-- Cloudflare R2 file objects
   +-- Email provider integration (verify current production path)
   +-- Netlify deployment
```

---

## 2. Entity relationships

### Client → Account

A Client can have one or more Accounts.

Account is the natural boundary for:

- client-specific price cards;
- commercial settings;
- operational subdivision.

### Account → Project

Project belongs to the selected client/account context.

After selection, project fields remain editable where previously locked; the system must not make initial selection irreversible by default.

### Project → Scoop

A Project contains one or more Scoops.

Scoop owns:

- source language;
- target language;
- client deadline;
- client-side pricing/CAT quantities;
- specialization where applicable;
- Job collection;
- scoop-level financial view.

### Scoop → Job

A Job executes a service step.

Job owns:

- service/step;
- resource assignment;
- supplier rate/cost;
- active PO reference;
- operational status;
- job-specific files/issues;
- inherited-but-editable language pair as locked.

### Job → PO

PO revisions are historical commercial records.

Model conceptually:

```text
Job
  └─ PO series
       ├─ V1  Historical
       ├─ V2  Historical
       └─ V3  Active

The UI may render historical versions with a label such as `Superseded`; the exact label is not a locked business enum unless confirmed by current code and an explicit decision.
```

Only active version drives current supplier cost.

### Resource

Resource references:

- identity/contact profile;
- language pairs/services/specializations;
- rate cards;
- tests/qualifications;
- Compliance evidence;
- agreement/signatures;
- Auth link if access is enabled.

---

## 3. Financial ownership and calculation

### Source values

Client price:
- owned primarily by Scoop/Account pricing context.

Supplier cost:
- owned by Job/active PO commercial assignment.

### Derived values

For each relevant level:

`Profit = Client value - Supplier cost`

`Margin % = Profit / Client value × 100`

Handle zero client value safely; never divide by zero.

Project Financials aggregate underlying Scoop/Job values and should not allow a conflicting second source of truth.

---

## 4. CAT-grid behavior

CAT pricing may contain row-level categories/quantities.

Rules:

- preserve per-row quantities;
- do not display irrelevant zero-quantity selectors/rows where the locked UI removes them;
- recalculate totals immediately after quantity/rate changes;
- flat fee is permitted when no price/rate card is suitable;
- switching pricing modes must not silently preserve incompatible stale values.

---

## 5. Status synchronization

Avoid multiple independent state machines that contradict each other.

Examples:

- PO send/issue can trigger Job assignment state.
- Job assignment/progress influences Scoop state.
- Scoop/job progress influences Project lifecycle.
- Cancelled Job/PO paths must not leave the Project/Scoop falsely “complete”.
- Completed/Approved states should retain historical files and commercial versions.

Any automation must be idempotent and safe on retry.

---

## 6. Auth and RLS

### Admin/internal

Internal users receive permissions by role.

Known role concepts include PM, QA and Project responsibilities.

### External Resource

RLS/queries must enforce:

- own Resource identity;
- own Jobs;
- own PO records;
- allowed Job/Delivery files;
- own issues;
- minimum Project/Scoop context;
- no default exposure of Client name/identity;
- no access to other Resources.

Do not enforce security only in React/UI. Server/database authorization remains mandatory.

---

## 7. Resource onboarding architecture

### Admin-created/imported

```text
Resource record created
        |
        v
No Auth account yet
        |
Admin sends access invitation
        |
Resource opens invitation
        |
Sets password
        |
Auth/profile linked
        |
Automatic portal activation
        |
Resource dashboard
```

Work approval remains separate.

### Self-registration

```text
Public registration
       |
Existing/new Auth handling
       |
Resource profile created/linked
       |
Activation/access behavior = CURRENTLY UNRESOLVED
       |
Business approval/qualification remains separate

Do not infer that public registration follows the staff-invitation activation rule. The observed existing-account path has produced `User already registered` → `Invalid login credentials`, and Update 053 prepared a recovery route that still requires live acceptance.
```

Flows must be duplicate-safe and retryable.

---

## 8. Compliance state concept

A robust model must preserve:

- draft/progress state;
- resource submission;
- admin review;
- requested changes;
- resubmission;
- agreement signature state;
- final signed state;
- evidence/document versions;
- eligibility calculation and rationale.

The exact current state machine must follow migrations/code and the locked signing decision.

---

## 9. Agreement/PDF architecture

The agreement is generated from a canonical DOCX/template source and Resource data.

Required outputs:

- filled agreement data;
- first (Retodo) signature state;
- second/final Resource signature state;
- final downloadable PDF;
- admin-visible filled/signed artifact.

PDF rendering must be tested against real populated data; a blank PDF is a blocking defect, not a cosmetic issue.

---

## 10. File architecture — R2

Recommended locked direction:

```text
Browser
   |
   | authenticated request
   v
TMS API / authorization
   |
   | validate role + Job/Resource relationship
   v
Short-lived signed R2 URL / mediated transfer
   |
   v
Cloudflare R2 object
```

Never expose reusable storage credentials client-side.

Metadata should remain in the database even though bytes live in R2.

Useful metadata:

- object key;
- original filename;
- MIME type;
- size;
- uploader;
- relation type/id;
- created_at;
- status/deleted state;
- access/audit data where implemented.

---

## 11. Email architecture

Historical TMS work used Gmail/OAuth for PO sending and later branded invitation work referenced Gmail/custom-provider paths.

Because this integration evolved, agents must verify:

- active provider;
- sender address/domain;
- API route;
- environment variables;
- delivery logs/errors;
- retry semantics.

Do not mark Job/PO/email-dependent state as successful before the send operation succeeds when the workflow requires successful delivery.

---

## 12. Environments

At minimum distinguish:

- local/dev;
- production Supabase;
- production Netlify;
- production R2;
- production email provider.

Never infer that a local test means a production migration/deploy succeeded.

Every handover must explicitly label:
- prepared;
- locally tested;
- migration executed;
- deployed;
- browser-tested in production.


---

## 12. Repository implementation boundary — reconciled 2026-09-19

- Code repository: `RetodoOps/retodo-ops-site`, branch `main`.
- TMS frontend: `/tms`.
- Server functions: `/netlify/functions`.
- Build marker: `/tms/build.json`.
- Update 056 is the current verified repository build marker at reconciliation.
- Repository source state is not equivalent to Netlify live state or Supabase migration state.
