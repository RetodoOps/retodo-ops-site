# Retodo Ops — Full Project Handoff

**Handoff date:** 2026-09-19  
**Scope:** Entire Retodo Ops project: company model, brand, website, sales/outreach, freelancer operations, documents/Drive, TMS, Compliance, infrastructure, AI/Codex working rules and current priorities.  
**Purpose:** Give a new ChatGPT profile enough context to continue the Retodo Ops project without reconstructing months of chats.

> This is a comprehensive orientation document, not a replacement for the canonical Decision Register. When this handoff conflicts with a newer explicit user instruction or a newer `LOCKED` entry in `01_DECISION_REGISTER.md`, the newer source wins.

---

## 1. What Retodo Ops is

Retodo Ops is a Nordic-focused language-services operation invoiced through **Retodo EOOD**, owned/managed by **Demir Atanasov**.

Core commercial direction:

- white-label language support for other multilingual/global LSPs first;
- direct clients may be developed later;
- small specialist team, not a mass marketplace;
- primary services: Translation, MTPE, proofreading/revision and related language services;
- primary source languages: English, German, French;
- primary Nordic target focus: Swedish, Norwegian/NB, Finnish and Danish; broader Nordic support may be added where genuinely covered;
- suitable positioning for specialized/sensitive content such as medical, IFU, patents and legal, without making unsupported certification/history claims.

Established positioning language includes the concept **“Your Nordic Language Desk”** / Nordic white-label desk.

### Brand integrity rules

Do not claim or imply:

- client relationships inherited from earlier personal/freelancer work unless Retodo itself has the relationship;
- client logos without permission;
- testimonials/case studies Retodo has not earned;
- unsupported scale;
- unsupported ISO certification;
- unsupported AI/automation capability;
- delivery history belonging to another entity/person as Retodo corporate history.

The preferred brand impression is specialist, controlled, responsive and credible rather than “large global LSP”.

---

## 2. Business entity and operating identities

### Legal/invoicing entity

- **Retodo EOOD** is the company used for invoicing.
- Owner/manager: **Demir Atanasov**.
- Company documentation has been updated to the relevant Sofia address/postal context used in the project; do not guess legal fields from memory when generating formal documents—use the canonical company record/documents.

### Sales-facing identity

- Retodo Ops has a LinkedIn company page.
- **Eli Stoyanova** is used as the initial personal LinkedIn sales/outreach profile.
- The company owner/user remains the controlling admin authority for the project/system.

### Email

- `ops@retodo-ops.com` is the company operational identity used for external operations.
- Historically it has functioned as an alias/forwarding identity into the main mailbox.
- Sending-provider implementation has evolved during TMS development; verify active production provider and environment before changing email logic.

### Domains

Known operating domains include:

- `retodo-ops.com` — public website;
- `tms.retodo-ops.com` — TMS portal direction/current TMS domain.

---

## 3. Company knowledge base / source-of-truth principle

The user explicitly wants the project to act as a **knowledge base and source of truth** for:

- decisions;
- business rules;
- system architecture;
- platforms used;
- operating procedures;
- implementation state;
- profiles/references to credentials (but **not live passwords/secrets in Git**).

Historical requirement: maintain one portable Retodo Ops master context covering the entire company, target clients, pricing, freelancer/outreach stages, workflow logic and TMS structure, kept current as decisions change.

Current evolution of that rule:

- the **private daily `Retodo_Ops_Master_Context_and_Decisions.md`** is the cross-business decision/evidence authority and is reconciled daily;
- chats are working sessions/evidence;
- repository context files are the repo-safe AI/Codex development mirror;
- material decisions must be synchronized to the Master and relevant repository context;
- the private Master contains internal data and must not be committed to the public repository;
- secrets remain in appropriate secret/password stores/environment variables and are referenced only by location/name.

---

## 4. Google Drive and company-document architecture

The connected company Drive account used in the project is:

- company Google Workspace account (kept in the private Master; do not duplicate private account details in the public repo)

The Drive was structured as a company architecture/source-of-truth with top-level folders numbered approximately `00`–`09`, covering areas such as:

- governance/company;
- legal;
- finance;
- clients;
- operations;
- freelancers/resources;
- quality/security;
- marketing/sales;
- systems;
- archive.

A document pack/templates was prepared historically. Do not discard existing Drive material or recreate a competing architecture without checking what already exists.

Legal/business-document rule:

- client agreements usually come from the client;
- freelancer/resource agreement is intended to be integrated into the TMS Compliance flow with auto-fill and e-signing;
- legal drafts that materially affect Bulgarian legal obligations should receive appropriate Bulgarian legal review before being treated as definitive legal advice.

---

## 5. Commercial rules

### Margin policy

- target average margin: **50%**;
- lowest normal threshold: **40%**;
- below 40% is exception-based and should not become an unnoticed default.

### Freelancer invoicing/payment baseline

Established default:

- freelancer invoice dates: **15th and 30th of each month**;
- in February/use cases without a 30th, use the month’s final day as applicable;
- accepted/approved POs enter the applicable invoicing cycle;
- default freelancer payment term: **60 calendar days** from the applicable/correct invoice basis.

When the TMS automates these processes, preserve the commercial rule but verify the exact implemented labels/state transitions.

### Pricing model

Client and supplier economics are deliberately separate:

- client pricing may come from Account-specific price cards;
- resource rates may be keyed by language pair, service and specialization;
- CAT-grid pricing is supported;
- manual/flat-fee fallback is allowed where no applicable rate exists;
- supplier-cost PO changes must not silently alter client price;
- profit and margin are derived from client value vs supplier cost.

---

## 6. Website — positioning and current known state

Public website repository known from the connected GitHub account:

- `RetodoOps/retodo-ops-site`

The website direction was revised to emphasize:

- Nordic white-label specialization;
- small specialist team;
- controlled delivery/security rather than scale claims.

A **Security & Trust** section was intentionally restored/retained, covering themes such as:

- confidentiality/NDA;
- controlled access;
- responsible AI/MT use;
- documented QA;
- security contact/policies.

Important website trust rules:

- no unsupported client logos/testimonials/case studies;
- no unsupported ISO claims;
- no vague claim that implies scale or certifications not yet obtained.

Latest known website gate work included:

- real Privacy page;
- real Terms page;
- validated enquiry submission route to `ops@retodo-ops.com`;
- TMS freelancer registration replacing an older mailto-style registration path.

User deployment preference applies here as well: provide only the complete files that actually need replacing/adding, not an unnecessarily huge ZIP or instructions to reconstruct code snippets manually.

---

## 7. LinkedIn and launch/outreach state

### Established LinkedIn assets

- Retodo Ops company page exists.
- Eli Stoyanova personal sales profile was prepared/updated.
- Company/profile banner work and initial posting were completed.
- Historical state around 2026-08-24: approximately 30 freelancer invitations had been sent and 14 had accepted at that point; treat this as dated progress, not a live count.

Recent social-content preference:

- Retodo posts should be spaced more deliberately;
- the next post should differ in substance/meaning, not merely repeat the previous message with different wording.

### Sales strategy evolution

Initial instinct was to target the strongest/most desirable clients first. The user later changed the sequence deliberately:

**Current sales sequencing principle:** start with the prospects where Retodo has the **highest probability of getting a response/opportunity**, use them as a training/learning wave, analyze their questions/vendor-recruitment process, refine the pitch, then approach the strongest desired clients with a better-tested sales process.

Priority indicators for early prospects:

- a visible vendor/freelancer registration route;
- explicit indication they recruit new vendors/resources;
- evidence of multilingual/global delivery where Nordic support is plausible;
- evidence/end clients that may need Nordic languages;
- clear supplier/vendor-management contact path;
- good fit for Retodo’s white-label specialist positioning.

A previously identified learning-wave sequence included:

1. CQ fluency
2. Crestec Europe
3. Argos
4. ZELENKA
5. SeproTec

Milengo was noted as a contingency/interesting route because of explicit EN/DE→Swedish relevance found during research.

These names are **prospect research status**, not existing Retodo clients.

### Outreach gate

The latest strategy did **not** say “send to everyone immediately”. Before approaching each first-wave prospect, ensure adequate delivery readiness, especially:

- primary/backup freelancer/resource coverage;
- relevant language pair/service mapping;
- current availability/consent where needed;
- rates and expected margin;
- current vendor contact and legal-entity verification;
- TMS/operational path sufficiently stable to onboard/quote/assign/deliver.

The first-prospect interaction should be treated as feedback to refine the pitch and process before continuing sequentially.

---

## 8. Operational-readiness philosophy

Before serious outreach, the user wanted real operating capability, not only branding. Important readiness areas include:

- working company email/signatures;
- project numbering/register;
- quotes and freelancer POs;
- project/file storage;
- CAT-tool workflow;
- secure file transfer;
- realistic end-to-end project simulation;
- enough resource coverage to avoid selling work that cannot be delivered.

memoQ integration is planned for later and must not become a blocking dependency unless the user changes priority.

---

## 9. TMS — purpose and canonical hierarchy

The TMS is the operational core for Retodo Ops.

Canonical hierarchy:

**Client → Account → Project → Scoop → Job → Resource / PO → Financials**

`Scoop` is the locked Retodo term for the work-package/item level inside a Project. Do not rename it casually.

Supporting modules include:

- external Resources;
- Internal resources;
- Clients & Accounts;
- Projects/Scoops/Jobs;
- client price cards;
- resource rate cards;
- POs and PO versions;
- Files;
- Delivery / files / issues;
- Compliance;
- Tests & Qualifications;
- Blind CV;
- Settings catalogs;
- Dashboard;
- Reports.

For full entity ownership/workflow rules read `02_TMS_ARCHITECTURE.md`, `03_BUSINESS_RULES.md` and `01_DECISION_REGISTER.md`.

---

## 10. TMS naming and workflow rules

### Naming

Project names are date-first and contextual. Known example:

`260828_TEST_SV_TMSQA001`

Scoops:

- `S01`, `S02`, ...

Jobs:

- service/step + index, e.g. `TRA J01`, `PROOF J02`.

PO naming/version display must remain contextual to the relevant project/job; an older generic-only PO numbering concept is historical and should not be reintroduced over newer behavior.

### Project status concept

Conceptual lifecycle:

`Offered → Ongoing/In progress → Ready to deliver → Delivered → Approved → Invoiced → Paid`

with alternate terminal paths such as `Declined` / `Cancelled`.

Use the exact labels/enums implemented in the current TMS; do not rewrite enum values merely for wording uniformity without approval.

### Job/PO assignment concept

- Jobs begin unassigned.
- PO sending/issue implies assignment.
- Separate Resource PO acceptance was removed.
- If a Resource later declines, the active PO/assignment follows the cancellation/reassignment path.

---

## 11. PO/versioning — locked model

The intended model is one Job-linked PO series with version history:

- V1, V2, V3 ...;
- one active version operationally;
- older versions remain immutable history rather than being destroyed; active-only operational display is locked, but the exact historical label/status is unresolved;
- dashboards/lists normally show active PO only;
- detailed PO/history view retains older versions;
- supplier-cost revisions propagate to Job/Scoop/Project financials;
- client price remains independent;
- issued/versioned commercial history should not be destructively overwritten.

The current approved PO change scope is the contractual reduction/correction-cost sentence only. Do not infer or build a new adjustment workflow, financial recalculation mechanism or status from that clause.

---

## 12. Resource and access model

Important separation of concepts:

1. Resource record exists.
2. Portal/Auth access exists.
3. Work/quality approval exists.
4. Compliance status exists.

These are related but are **not the same state**.

Locked direction for admin-created/imported external Resources:

- Resource record may exist without Auth;
- access invitation is separate;
- invitation flow sets password and activates portal access;
- after successful activation the Resource is directed into the Resource portal/dashboard;
- separate work approval/eligibility remains distinct;
- RLS protects Resource data;
- Resource sees only own relevant Jobs/POs/files/issues/minimal project/scoop context;
- Client identity is hidden from Resource by default unless a specific rule authorizes disclosure.

Self-registration and admin-created-resource flows are separate flows and should not be conflated.

---

## 13. Internal resources

Simplified internal-resource baseline:

- Name
- Position
- Gender
- Email
- Status

Multiple roles may be assigned, e.g. PM / QA / Project.

Deactivation preserves history.

PM selectors should use internal resources rather than unrelated external Resource records.

---

## 14. Compliance and ISO-oriented qualification — locked 2026-09-10

### Education evidence

- Highest relevant degree
- Degree type
- Field of study
- Institution
- Country
- Graduation date/year
- Upload diploma/certificate

### Professional experience

- Translation professional since: `MM/YYYY`
- Revision professional since: `MM/YYYY`
- MTPE professional since: `MM/YYYY`
- Evidence type: CV
- Evidence file(s) upload

### Derived experience

The system dynamically calculates experience as `X years Y months` against the current month.

### Internal eligibility calculation

The TMS should internally derive/display eligibility + rationale for:

- ISO 17100 Translator/Reviser criteria;
- ISO 18587 Post-editor criteria.

Do not claim Retodo corporate ISO certification simply because the TMS evaluates resource qualification against standard-related criteria.

### Test/qualification workflow

The design also includes:

- flag/record for pre-TMS tested status;
- pass/fail result;
- job/test size recorded in words/hours;
- Compliance is prompted/unlocked after the relevant test path;
- a Resource may work before full Compliance according to the established workflow;
- admin is notified on Compliance submission.

---

## 15. Agreement and e-signing — locked direction

Agreement is part of Compliance, not a detached “Send Agreement” process.

Locked principles:

- no separate `Send Agreement` action;
- preserve the original DOCX agreement/template source;
- agreement auto-fills with vendor/resource details;
- Retodo first-signature stage occurs in the Compliance signing flow;
- Resource applies the second/final signature using `Accept and sign`;
- final populated/signed PDF is downloadable;
- Admin can see the populated/signed agreement;
- Resource can save Compliance progress;
- Admin can request changes;
- Resource can edit/resubmit requested Compliance changes;
- combined `ID / Tax / VAT` field is used where the locked form requires it;
- agreements/signatures should preserve version/audit history rather than silently overwriting executed evidence.

A major current defect is that Agreement PDFs have been reported blank/identical; real end-to-end signing/PDF verification is still required.

---

## 16. Storage and files

Current TMS operational file-storage direction:

- **Cloudflare R2**.

This supersedes earlier ideas around using Supabase Storage as the primary operational store and/or Google Drive archival logic for live TMS files.

Access principles:

- TMS-mediated authorization;
- Resource access limited by assignment/RLS/authorization;
- completed-job access should remain available where business rules require it;
- do not treat an age/deletion statement as locked policy without reconciliation: Update 045 source contains 3-month archive and 24-month archived-binary deletion mechanics with holds, but those exact timings remain implementation/policy-unverified;
- duplicate Compliance evidence should be deletable under the established lifecycle rules;
- use secure/expiring access patterns where applicable.

R2 lifecycle has not yet been fully end-to-end verified in production.

---

## 17. Technology and infrastructure baseline

Known TMS direction:

- web app/front end: static HTML/JavaScript/CSS under `/tms`, with Netlify Functions for server-side actions;
- Auth/database: Supabase;
- hosting/deployment: Netlify;
- object/file storage: Cloudflare R2;
- email: provider implementation changed across development; verify current production code/environment before modifying;
- memoQ: planned later.

Historically Gmail/OAuth PO email work encountered `invalid_grant`/OAuth configuration issues. Do not infer that the current production mail path is still identical without checking code/environment.

### GitHub repository — reconciled

The actual TMS repository is `RetodoOps/retodo-ops-site`, branch `main`. The public website and TMS coexist in this repository; TMS files are under `/tms` and server functions under `/netlify/functions`.

`RetodoOps/Retodo-App` is a separate HR/Luma People application and must not be used for TMS work.

---

## 18. TMS historical implementation landmarks

Historical session progression is documented in `handovers/TMS_TMS2_TMS3_CONSOLIDATED_HISTORY.md` and `handovers/TMS4_CURRENT_HANDOVER.md`.

High-level landmarks:

- TMS: foundational Projects/Jobs/Offers/PO/financial concepts; early Gmail/OAuth work;
- TMS2: PO revisions and financial synchronization, Accounts/price cards, Scoop expansion;
- TMS3: P0 architecture hardening, onboarding/access/RLS, contextual hierarchy;
- TMS4: Compliance, tests/qualifications, Agreement/e-sign/PDF, PO regressions, invitation delivery and UI-quality work.

Known recent update state, reconciled 2026-09-19:

- 048–049: reported deployed;
- 050: deployment reported but frontend acceptance failed;
- 051: later source advances it to implemented-reported/narrowly supported;
- 052: deployment reported; Project/Scoop Cancelled path PASS;
- 053–055: source is now present on GitHub `main`, but live acceptance remains incomplete;
- 056: Global Visual System source is present on `main` and `tms/build.json` reports build `056` with baseline Update 055; Netlify/live visual acceptance remains to be recorded;
- production migration 051/audit 013 and live two-party Agreement/PDF acceptance remain unresolved.

Never treat “prepared” as “live”.

---

## 19. Current TMS unresolved priorities

### High priority

1. **Resource profile UI consistency**
   - field/card backgrounds need clearer contrast;
   - heading hierarchy/alignment needs correction;
   - actions/buttons need consistent size/style/alignment;
   - help icons belong beside headings;
   - explanatory text must stay within cards/bubbles;
   - related evidence cards should use consistent dimensions;
   - review the whole page, not only individual defects named by the user.

2. **Production-state reconciliation**
   - determine exact current deployed code;
   - determine latest executed migration;
   - build/audit/test before applying old prepared updates blindly.

3. **Agreement PDF/signing**
   - prove real populated first-signature artifact;
   - Resource final signature;
   - final PDF from Resource and Admin views;
   - verify data/signature/version differences.

4. **Invitation email delivery**
   - a real invitation was reported not received;
   - inspect provider logs, sender/domain, link validity, bounce/rejection and retry behavior.

5. **PO/Dashboard regression**
   - Resource display;
   - deadline synchronization;
   - V3/active-version behavior;
   - Cancelled/reassignment;
   - supplier-cost propagation.

6. **R2 file lifecycle end-to-end verification**.

7. **Full Compliance state-machine regression**.

### Later/incomplete

- Reports module/submodules;
- Blind CV completion/verification.

---

## 20. UI/UX working rule

The user explicitly does **not** want to act as a pixel-by-pixel QA list after every update.

When a UI issue is raised, the implementer must apply general interface-quality rules proactively across the affected screen:

- visual hierarchy;
- consistent alignment/grid;
- spacing rhythm;
- containment;
- text readability;
- adequate contrast;
- consistent controls;
- consistent card/field sizing;
- responsive/narrow-width behavior;
- no orphaned labels/help icons/overflow text.

Use `04_UI_UX_RULES.md` as the canonical implementation standard.

---

## 21. GitHub / deployment / delivery preferences

This is a hard user workflow preference unless explicitly changed for a specific task:

- user performs GitHub upload/push/deploy steps manually;
- do not automatically upload/push/deploy merely because a connector is available;
- when delivering code changes, provide **complete changed files**, not snippets the user must manually splice;
- package the complete set of changed/new repository files in a ZIP;
- do **not** include unrelated repository files just to make the ZIP large;
- SQL migrations are provided separately as `.sql` files in the established manual workflow;
- do not repeatedly tell the user to confirm a standard published Netlify deploy when they already understand that step;
- preserve existing functionality unless the requested change explicitly replaces it.

For Codex parallel work, task branches/worktrees are preferred to avoid overlapping edits.

---

## 22. AI / Codex parallel-work operating model

### Primary ChatGPT profile

Acts as the main Product/Architecture/Decision authority because it contains the richest accumulated Retodo Ops history.

Use it for:

- product/business decisions;
- workflow architecture;
- conflict resolution;
- priority and acceptance criteria;
- promotion of proposals into locked decisions.

### Secondary ChatGPT profile

Acts as Development/QA coordinator.

It must:

- read this full handoff and the canonical context files;
- not build a separate source of truth;
- coordinate Codex tasks;
- preserve locked decisions;
- return implementation/QA handovers.

### Codex Desktop

Acts as execution layer for:

- code inspection;
- edits;
- migrations;
- tests/builds;
- diffs;
- branch/worktree tasks.

Codex does **not** have authority to redefine business rules because a different implementation is technically easier.

### Source precedence

Use:

1. newest explicit user instruction;
2. newer `LOCKED` Decision Register entry;
3. Current State;
4. Master Context;
5. latest relevant handover;
6. older history.

### Decision taxonomy

- LOCKED
- SUPERSEDED
- PROPOSED
- IMPLEMENTED-REPORTED
- VERIFIED
- UNRESOLVED

---

## 23. Secret/password handling

The Retodo Ops project is intended to know **where** systems/profiles/secrets belong, but live secrets must not be placed into Git/context files.

Never commit or paste into project docs:

- passwords;
- Supabase service-role keys;
- OAuth client secrets;
- refresh tokens;
- Resend/API keys;
- R2 secret keys;
- private signing keys;
- recovery codes.

Use references such as:

`Production Supabase service-role key → production environment / approved secret store`

rather than the value itself.

See `10_SECRET_REFERENCES.md`.

---

## 24. Immediate overall project priorities

The whole Retodo Ops project currently has two parallel tracks:

### Track A — Operational/TMS readiness

Priority order:

1. verify the local working copy remote is `RetodoOps/retodo-ops-site` and branch/base are current;
2. install/maintain this canonical context pack there;
3. reconcile production code + migrations;
4. finish Resource UI quality pass;
5. verify Agreement signing/PDF;
6. verify invitation delivery;
7. retest PO/Dashboard;
8. verify R2 and Compliance end-to-end;
9. complete Blind CV/Reports later.

### Track B — Sales launch

Continue only with sufficient operational/resource readiness:

1. maintain primary/backup freelancer/resource map by needed Nordic language/service;
2. verify rates, availability and expected margin;
3. verify first-wave vendor contacts/routes;
4. approach highest-probability learning-wave prospects sequentially;
5. record questions/objections/recruitment requirements;
6. refine Retodo sales pitch/process;
7. then approach the strongest desired clients with the improved process.

Do not sacrifice operational reliability merely to accelerate outreach.

---

## 25. What the secondary profile must do on first use

The secondary profile must **not** treat `09_SECOND_PROFILE_BOOTSTRAP_PROMPT.md` as the project knowledge itself. That prompt is only the startup instruction.

Mandatory orientation order:

1. Read this file: `handovers/RETODO_OPS_FULL_PROJECT_HANDOFF_2026-09-19.md`.
2. Read `00_MASTER_CONTEXT.md`.
3. Read `01_DECISION_REGISTER.md`.
4. Read `06_CURRENT_STATE.md` and `07_OPEN_ISSUES.md`.
5. Read `08_PARALLEL_WORKFLOW.md`.
6. Read the current TMS handover and consolidated TMS history.
7. Read the specialized architecture/business/UI/development files relevant to the next task.
8. Only then coordinate Codex or propose implementation changes.

At startup it should summarize its understanding in four categories:

- company/business model and launch state;
- TMS architecture and locked rules;
- current unresolved implementation items;
- exact next workstream and its non-goals.

If it cannot distinguish an explicit locked decision from an old proposal, it must check the Decision Register rather than guess.

---

## 26. Handoff maintenance

This file is a broad project snapshot. It should be refreshed when there is a material cross-project change such as:

- business positioning change;
- new sales-stage strategy;
- company/document architecture change;
- major TMS architecture change;
- new deployment/storage/provider decision;
- major launch milestone.

Fine-grained TMS implementation changes belong first in:

- `01_DECISION_REGISTER.md`;
- `06_CURRENT_STATE.md`;
- `07_OPEN_ISSUES.md`;
- the latest TMS implementation handover.

Do not rewrite history silently: use `SUPERSEDED` for replaced decisions and preserve the reason where known.


---

## 24. 2026-09-19 reconciliation delta

- actual TMS repository confirmed as `RetodoOps/retodo-ops-site`;
- TMS stack corrected from Next.js to static `/tms` + Netlify Functions;
- current repo build advanced to 056;
- Update 055/056 source presence verified, while DB/live acceptance remains separate;
- freelancer invoice cycle corrected to 15th + last working day;
- public self-registration activation remains unresolved;
- PO historical label remains unresolved;
- broad PO adjustment workflow is not authorized;
- R2 lifecycle package timings are not promoted to locked policy;
- private Master must remain out of the public repo.
