# Retodo Ops TMS — Decision Register

**Version:** 1.0  
**Canonical date:** 2026-09-19

This register is intentionally conservative. Where a historical detail is uncertain or implementation-only, it is not upgraded to `LOCKED`.

---

## A. Governance and source of truth

### DR-001 — One canonical project memory
**Status:** LOCKED  
**Source:** TMS3 / 2026-09-08 and current parallel-work decision / 2026-09-19  
**Decision:** Maintain one canonical context/decision register rather than separate incompatible “masters”. Material decisions, migrations, tests, implementations, supersessions and unresolved issues must be committed back into that source of truth.  
**Impact:** All AI agents and sessions must read/update this context pack.

### DR-002 — Decision status taxonomy
**Status:** LOCKED  
**Decision:** Use `LOCKED`, `SUPERSEDED`, `PROPOSED`, `IMPLEMENTED-REPORTED`, `VERIFIED`, `UNRESOLVED`.  
**Impact:** Product and implementation history.

---

## B. Architecture and data ownership

### DR-010 — Core hierarchy
**Status:** LOCKED  
**Source:** P0 architecture baseline / 2026-09-06  
**Decision:** `Client → Account → Project → Scoop → Job → Resource/PO → Financials`.  
**Impact:** Data model, breadcrumbs, calculations, permissions.

### DR-011 — “Scoop” terminology
**Status:** LOCKED  
**Source:** User decision / 2026-09-03  
**Decision:** Work items inside Projects are called `Scoops`.  
**Impact:** UI, schema labels, documentation.

### DR-012 — Scoop ownership
**Status:** LOCKED  
**Decision:** Scoop owns its client-side pricing/deadline context; Project Financials aggregate underlying data and should be read-only where derived.  
**Impact:** Project/Scoop/Job/Financials.

### DR-013 — Job languages
**Status:** LOCKED  
**Source:** 2026-09-06  
**Decision:** Job languages inherit from the Scoop but remain editable.  
**Impact:** Job editing, dashboards, sync behavior.

---

## C. Pricing and financials

### DR-020 — Account-specific client price cards
**Status:** LOCKED  
**Decision:** Client pricing is account-specific where applicable.  
**Impact:** Accounts, Scoop creation/editing, CAT pricing.

### DR-021 — Resource rate cards
**Status:** LOCKED  
**Decision:** Resource rates are keyed by language pair, service and specialization where applicable.  
**Impact:** Assignment and supplier-cost calculation.

### DR-022 — Flat-fee fallback
**Status:** LOCKED  
**Source:** 2026-09-06  
**Decision:** Allow flat-fee/manual cost/price where no rate card applies. Do not force a zero-quantity rate selector.  
**Impact:** Scoop/Job pricing and assignment.

### DR-023 — Financial separation
**Status:** LOCKED  
**Decision:** Client value and supplier cost are independent. PO revisions may change supplier cost but must not silently change client price.  
**Impact:** Profit and margin calculations.

### DR-024 — Margin policy
**Status:** LOCKED  
**Decision:** Target average margin = 50%; normal lowest threshold = 40%, with exceptions handled explicitly.  
**Impact:** Commercial monitoring; not an automatic hard rejection unless separately implemented.

### DR-025 — PO cost propagation
**Status:** IMPLEMENTED-REPORTED  
**Source:** TMS2 update / 2026-09-01  
**Decision/result:** Active PO supplier cost propagates to Job, Project expense/profit/margin while client value remains unchanged.  
**Reported test:** 31.00 EUR client value, 10.68 EUR supplier cost, 20.32 EUR profit, 65.55% margin.  
**Note:** Preserve as expected behavior; re-verify after financial changes.

---

## D. PO and assignment workflow

### DR-030 — Versioned PO per Job
**Status:** LOCKED  
**Decision:** One PO relationship per Job with versioning (`V1`, `V2`, ...). Only one version is active; prior versions remain immutable history.  
**Impact:** PO tables, supplier cost, PDF/email, dashboard.

### DR-031 — Old PO versions hidden from operational lists
**Status:** LOCKED  
**Decision:** Dashboard/normal lists show active PO only; older versions are visible in PO history as `Overridden`/`Superseded`.  
**Impact:** PO UI and queries.

### DR-032 — No Resource PO acceptance step
**Status:** LOCKED  
**Decision:** Sending/issuing the PO implies assignment. Resource acceptance as a separate mandatory workflow was removed. If Resource later declines, cancel the PO/assignment.  
**Impact:** Job status, Resource portal, PO status.

### DR-033 — Contextual PO naming
**Status:** LOCKED  
**Decision:** PO naming must clearly connect to the Project/Job context and version.  
**Impact:** PO display/PDF/files.

### DR-034 — Generic `PO-YYYY-NNNN`
**Status:** SUPERSEDED  
**Decision:** Earlier generic numbering existed; later P0/contextual naming rules take precedence where they conflict.  
**Impact:** Do not reintroduce old generic-only display naming.

### DR-035 — PO contractual reduction clause; no new adjustment workflow
**Status:** LOCKED / earlier broad adjustment proposal SUPERSEDED  
**Source:** Current Master D009 and current Agreement/PO scope  
**Decision:** The approved task is the contractual reduction/correction-cost sentence in generated Freelancer POs. That clause does **not** authorize building a new adjustment workflow, negative-line mechanism, new statuses, or changes to PO totals, supplier/project expense, profit, margin, or Financials. Preserve existing versioning and immutable history.  
**Impact:** PO generation only unless a later explicit decision expands scope.

---

## E. Resources and access

### DR-040 — Resource record is separate from portal access
**Status:** LOCKED  
**Source:** 2026-09-07  
**Decision:** Admin-created/imported external Resources may exist without Auth. Portal access is a separate invitation action.  
**Impact:** Resource onboarding, Auth, admin UI.

### DR-041 — Invitation flow
**Status:** LOCKED  
**Source:** Update 042 flow / 2026-09-08  
**Decision:** Invitation → set/create password → automatic portal activation → Resource dashboard. No separate redundant approval after password creation.  
**Impact:** Auth callbacks, resource status, invitations.

### DR-042 — Work approval separate from access
**Status:** LOCKED  
**Decision:** Portal access does not by itself equal work approval/eligibility.  
**Impact:** Resource status/qualification.

### DR-043 — Self-registration
**Status:** LOCKED in principle / activation behavior UNRESOLVED  
**Decision:** Resource self-registration is allowed and is distinct from admin-created invitation flow. The exact public-registration activation/pending-admin-approval behavior is not currently recovered consistently. Existing-account registration has a verified failure path; Update 053 prepared recovery but live acceptance remains unverified.  
**Impact:** Do not apply staff-invitation activation rules to public registration by assumption.

### DR-044 — Resource permissions
**Status:** LOCKED  
**Decision:** Resource sees only own Jobs/POs/files/issues and minimum Project/Scoop context needed to work. Client name is hidden by default. Preserve RLS.  
**Impact:** RLS, API, portal UI.

### DR-045 — Internal resources
**Status:** LOCKED  
**Decision:** Simplified fields: Name, Position, Gender, Email, Status; multiple roles; deactivation preserves history.  
**Impact:** PM/QA/Project role selectors and audit history.

---

## F. Storage and files

### DR-050 — Cloudflare R2 operational storage
**Status:** LOCKED  
**Source:** Accepted after Update 044 planning / 2026-09-09  
**Decision:** TMS operational files use Cloudflare R2 direction with TMS-mediated access and short-lived presigned links as appropriate.  
**Impact:** File APIs, storage credentials, permissions.

### DR-051 — Supabase active files + Google Drive closed archive
**Status:** SUPERSEDED  
**Source:** Earlier 2026-08-28 plan  
**Decision:** Earlier storage concept was replaced by R2 for TMS operational files.  
**Impact:** Do not build new functionality around the old storage architecture.

### DR-052 — Resource access and lifecycle policy boundary
**Status:** LOCKED access requirement / retention timing UNRESOLVED  
**Decision:** R2 strategy must preserve authorized Resource access according to job/role rules. Update 045 package source contains 3-month archive and 24-month archived-binary deletion mechanics with retention holds, but those exact timings are not promoted to locked business policy without explicit approval/live reconciliation.  
**Impact:** Authorization is locked; lifecycle timing remains an implementation/policy reconciliation item.

### DR-053 — Duplicate-file deletion
**Status:** LOCKED  
**Source:** TMS4 / 2026-09-14  
**Decision:** Authorized users must be able to delete duplicate Compliance documents/files according to role.  
**Impact:** Compliance/document UI and storage lifecycle.

---

## G. Compliance and qualification

### DR-060 — Education evidence fields
**Status:** LOCKED  
**Source:** 2026-09-10  
**Decision:** Highest relevant degree; Degree type; Field of study; Institution; Country; Graduation date/year; Upload diploma/certificate.  
**Impact:** Compliance profile and Blind CV source data.

### DR-061 — Professional experience source fields
**Status:** LOCKED  
**Source:** 2026-09-10  
**Decision:** Translation/Revision/MTPE professional since (`MM/YYYY`), evidence type = CV, evidence file(s) upload.  
**Impact:** Compliance, eligibility, Blind CV.

### DR-062 — Dynamic experience
**Status:** LOCKED  
**Decision:** Start month/year fields are source of truth; durations recalculate automatically against current month as X years Y months.  
**Impact:** UI, eligibility calculations, Blind CV.

### DR-063 — ISO eligibility
**Status:** LOCKED  
**Decision:** Internal automatic eligibility/rationale for ISO 17100 Translator/Reviser and ISO 18587 Post-editor.  
**Impact:** Compliance admin review and qualification state.

### DR-064 — Test record
**Status:** LOCKED  
**Decision:** Track pre-TMS tested indicator, pass/fail result and test/job size in words/hours.  
**Impact:** Tests & Qualifications and Compliance prompting.

### DR-065 — Resource can work before full Compliance
**Status:** LOCKED  
**Decision:** Compliance is not necessarily a universal precondition to all work; after test pass the Compliance phase is prompted according to workflow.  
**Impact:** Assignment eligibility logic.

---

## H. Agreement/signatures

### DR-070 — Two-sided signing workflow
**Status:** LOCKED  
**Source:** User accepted flow / 2026-09-14  
**Decision:** No separate “Send Agreement”. Retodo performs first signature within the established Compliance flow; Resource uses `Accept and sign` for the second/final signature.  
**Impact:** Compliance state, sign UI, PDF.

### DR-071 — Final filled PDF
**Status:** LOCKED  
**Decision:** After signing, the filled/final agreement PDF must be downloadable; admin must see the filled version.  
**Impact:** PDF generation/storage and portal.

### DR-072 — Compliance progress/review
**Status:** LOCKED  
**Decision:** Resource can save progress; admin sees submitted data; admin can request changes; Resource can edit and resubmit; relevant submission/review notifications are sent.  
**Impact:** Compliance state machine.

### DR-073 — ID/Tax/VAT
**Status:** LOCKED  
**Decision:** Agreement/profile flow treats ID/Tax/VAT as one combined field where specified.  
**Impact:** Agreement autofill and resource data.

### DR-074 — Original DOCX template
**Status:** LOCKED  
**Decision:** Preserve the original DOCX agreement source/template unless explicitly replaced.  
**Impact:** PDF generation and legal document maintenance.

---

## I. UI/UX

### DR-080 — Holistic visual QA
**Status:** LOCKED  
**Source:** TMS4 user feedback / 2026-09-19 context  
**Decision:** Do not require the user to enumerate every alignment/readability defect after each update. Apply canonical visual hierarchy, alignment, spacing, containment, contrast and consistency rules to the whole affected screen.  
**Impact:** All frontend work.

### DR-081 — Resource profile visual corrections
**Status:** LOCKED requirements / acceptance UNRESOLVED  
**Decision/requirements:** Fix small heading text above test card, alignment of Tests & Qualifications, Save changes vs Assign Test, Compliance phase and Account Qualifications headings; keep help/question icons inline with headings; ensure helper text stays inside bubbles/cards; consistent button size/color/type; align comparable cards such as Master's degree and Diploma upload.  
**Impact:** Current Resource profile UI task.


### DR-082 — Daily cross-business Master
**Status:** LOCKED  
**Source:** Current Master D001 / new-session instructions  
**Decision:** `Retodo_Ops_Master_Context_and_Decisions.md` is the portable cross-business decision/evidence register. Read it before substantive new-session work, keep one canonical identity/version history, and reconcile it at the end of each work session/day. The rolling TMS handoff supplements rather than replaces it.  
**Impact:** Context synchronization.

### DR-083 — Actual TMS repository
**Status:** VERIFIED  
**Source:** Master deployment history + GitHub inspection 2026-09-19  
**Decision/evidence:** TMS code is in `RetodoOps/retodo-ops-site`, branch `main`, under `/tms`; `RetodoOps/Retodo-App` is a different HR/Luma People application.  
**Impact:** Codex/repository selection.

### DR-084 — Current repository build 056
**Status:** VERIFIED repository state / live acceptance UNRESOLVED  
**Source:** GitHub `main`, `tms/build.json`, Update 056 README  
**Decision/evidence:** `main` contains Update 055 source and Update 056 Global Visual System; `tms/build.json` reports build `056`, source baseline Update 055. Update 056 is UI/auth-session work only and declares no new migration/audit/env variable.  
**Impact:** New work must start from build 056 source; production DB/Netlify/live acceptance must be checked separately.

### DR-085 — Separate browser profiles for role QA
**Status:** LOCKED operational QA rule  
**Source:** User TMS4 acknowledgement + Update 056 README  
**Decision:** Test Admin and Resource simultaneously in separate browser profiles or Incognito. Do not rely on two roles sharing one Supabase session in one browser profile.  
**Impact:** Acceptance testing and false RLS/session-error avoidance.

---

## J. Development and deployment

### DR-090 — Manual deployment by user
**Status:** LOCKED  
**Source:** 2026-09-06  
**Decision:** User performs uploads/deployments. Assistant/agents must not automatically push GitHub or deploy Netlify unless the user explicitly changes this rule for a specific task.  
**Impact:** Delivery workflow.

### DR-091 — Full ZIPs / full files
**Status:** LOCKED  
**Decision:** Repository updates are provided as complete replacement/addition files in a ZIP, not piecemeal snippets requiring manual reconstruction.  
**Impact:** Implementation handoff.

### DR-092 — SQL migrations separate
**Status:** LOCKED  
**Source:** 2026-09-02  
**Decision:** Provide migrations as separate `.sql` files; GitHub package contains repository files.  
**Impact:** Deployment packaging.

### DR-093 — Preserve RLS
**Status:** LOCKED  
**Decision:** RLS is not to be weakened casually. New access flows must retain least-privilege visibility.  
**Impact:** Supabase policies/API.

### DR-094 — Forward-only migrations
**Status:** LOCKED  
**Decision:** New migrations only; do not rewrite already executed production migrations.  
**Impact:** Database change management.

### DR-095 — Tests before delivery
**Status:** LOCKED  
**Decision:** Test before packaging/delivery and report exact test results and any unverified production steps.  
**Impact:** Every update.

---

## K. Historical implementation milestones

### DR-100 — P0 architecture baseline
**Status:** IMPLEMENTED-REPORTED  
**Source:** 2026-09-06  
**Reported result:** Client→Account→Project→Scoop→Job→Resource/PO→Financials; Scoop-owned pricing/deadlines; read-only Project Financials; contextual PO numbering; flat-fee assignments; corrected Scoop transitions; CAT breakdown.

### DR-101 — Update 042 invitation activation
**Status:** IMPLEMENTED-REPORTED  
**Source:** 2026-09-08  
**Reported result:** Migration 041 succeeded; password activation/direct Resource dashboard confirmed.

### DR-102 — Update 044
**Status:** IMPLEMENTED-REPORTED / state uncertain
**Source:** 2026-09-09 onward  
**Scope:** active-only PO views, historical PO display, private Job-file lifecycle, staff issue workflow. Exact historical PO label remains unresolved.  
**Note:** Prepared/not-deployed status appeared in earlier handover; later work continued. Confirm production state rather than assuming.

### DR-103 — Updates 048–049
**Status:** IMPLEMENTED-REPORTED  
**Source:** TMS4 consolidated state / 2026-09-18  
**Reported:** deployed.

### DR-104 — Update 050
**Status:** IMPLEMENTED-REPORTED but REJECTED
**Source:** 2026-09-14  
**Reported:** deployed, but frontend behavior rejected due deadline/V3 issues and missing Resource on Dashboard. Follow-up required.

### DR-105 — Update 052
**Status:** IMPLEMENTED-REPORTED  
**Source:** TMS4 consolidated state / 2026-09-18  
**Reported:** deployed; Cancelled flow PASS.

### DR-106 — Updates 053–055
**Status:** VERIFIED PRESENT IN GITHUB SOURCE / LIVE ACCEPTANCE UNRESOLVED  
**Source:** GitHub `main` inspection 2026-09-19  
**Evidence:** Updates 053, 054 and 055 source commits exist on `main`. Update 056 is based on Update 055. This advances repository source state only; migration 051/audit 013, Netlify live state, registration recovery, and two-signature/PDF acceptance remain unverified.
