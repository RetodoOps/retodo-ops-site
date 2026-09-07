# Retodo Ops TMS — Entity, Field, Status and Permission Matrix

Status date: 2026-09-06  
Session: TMS3  
Deployment mode: local/manual upload only; Codex must not push GitHub or Netlify changes.

This is the P1 architecture control document following the user's report that
P0 is complete. It turns the current TMS3 decisions and the implemented
migrations into an ownership matrix that can be used for live hardening,
future migrations and acceptance testing.

## Reading and evidence rules

The labels below are deliberately conservative.

| Label | Meaning in this document |
|---|---|
| `LOCKED` | Explicitly decided or approved by the user, or retained as an explicit architectural rule. |
| `SUPERSEDED` | An earlier rule or implementation was replaced by a later decision. |
| `PROPOSED` | Suggested but not approved; it must not be implemented as a requirement. |
| `IMPLEMENTED-REPORTED` | The user reported that the behavior worked or that P0 was complete. It is not treated as independent live proof. |
| `VERIFIED` | Directly confirmed from the current local schema, migration, trigger, RPC or frontend source. |
| `UNRESOLVED` | Discussed but still requiring a decision, live test or implementation. |

Evidence boundaries:

- P0 is recorded as `IMPLEMENTED-REPORTED` because the user said “P0 is
  completed”, but did not provide individual test outputs in that message.
- The `VERIFIED` entries below are source-level findings from migrations
  `001`–`035` and the local Update 038 package. They do not claim that the
  same files are already deployed to the user's live Supabase/Netlify
  environment.
- If a legacy column remains in the schema while the UI no longer exposes it,
  this document names both the current authority and the compatibility column.

## 1. Canonical architecture

### 1.1 Commercial and production hierarchy

`Client → Client Account → Project → Scoop → Job → Resource / Supplier PO → Financials`

| Layer | Current authority | Status |
|---|---|---|
| Client | Company/customer identity, Accounts, contacts, billing entities and client-side pricing context. | `LOCKED`, `VERIFIED` |
| Client Account | Optional account under a Client; owns account-specific specializations, instructions and account-scoped pricing. `Non-defined` is allowed in the UI. | `LOCKED`, `VERIFIED` |
| Project | Commercial and operational context, client/account references, internal staff, overall workflow and references. It is not the owner of editable price rows. | `LOCKED`, `VERIFIED` |
| Scoop | Independent language and client-pricing unit inside a Project. It owns the mandatory deadline, language pair, detailed client financial rows, client price and Scoop status. | `LOCKED`, `VERIFIED`, `IMPLEMENTED-REPORTED` |
| Job | Assignable production task inside one Scoop. It owns the Resource assignment, supplier terms, CAT analysis, job status and job-specific deadline. | `LOCKED`, `VERIFIED`, `IMPLEMENTED-REPORTED` |
| Resource | External Freelancer/Company or Internal employee. The same record remains referenced by historical work after deactivation. | `LOCKED`, `VERIFIED` |
| Supplier PO | Supplier-cost snapshot for a Job, with immutable issued versions and revision history. | `LOCKED`, `VERIFIED`, `IMPLEMENTED-REPORTED` |
| Financials | Project-level read-only aggregation. Detailed editing is performed inside the owning Scoop; supplier expense originates from Jobs/current POs. | `LOCKED`, `VERIFIED`, `IMPLEMENTED-REPORTED` |

### 1.2 Record cardinality and propagation

| Relationship | Rule | Status and evidence |
|---|---|---|
| Client → Client Account | One Client can have many Accounts; an Account belongs to exactly one Client. | `VERIFIED` in `client_accounts(client_id)` and relation validation. |
| Client → Contact/Billing Entity | A Client can have many contacts and billing entities. A selected Project/Quote contact, Account and Billing Entity must belong to the selected Client. | `VERIFIED` by `validate_client_relations()` and `validate_selected_billing_entity()`. |
| Quote → Project | Acceptance creates one linked Project per distinct target language. | `LOCKED` in the approved architecture; exact multi-Scoop Quote cardinality remains `UNRESOLVED`. |
| Project → Scoop | One Project can contain multiple Scoops. The first Scoop is created for an existing/new Project; later Scoops are `S02`, `S03`, etc. | `LOCKED`, `VERIFIED` in migrations `027`, `028`, `034`. |
| Scoop → Job | One Scoop can contain multiple Jobs. `project_jobs.project_scoop_id` is the required parent link after migration `027`. | `LOCKED`, `VERIFIED`. |
| Scoop → Client financial lines | Every detailed line belongs to one Scoop through `scope_items.project_scoop_id`. Project Financials must show a Scoop group once, not once per CAT row. | `LOCKED`, `IMPLEMENTED-REPORTED`; source relation `VERIFIED`. |
| Job → Resource | A Job can have zero or one current Resource; reassignment preserves history and requires a reason. | `LOCKED`, `VERIFIED` in assignment RPCs. |
| Job → Supplier PO | A Job can have current PO state plus immutable PO versions. A cancelled/replaced PO is retained. | `LOCKED`, `VERIFIED`. |
| Project → Financials | Project client price is the sum of active Scoop prices. Project expense is the sum of non-cancelled Job/current PO supplier costs. | `VERIFIED` in `refresh_project_price_from_scoops()` and `refresh_project_financials()`; P0 result `IMPLEMENTED-REPORTED`. |

### 1.3 End-to-end flow

`Inquiry → Quote → Client confirmation → Project → Scoop(s) → Job(s) → Client invoice → Payment`

- A confirmed Client PO/email assignment may create a Project without a Quote.
- Project creation collects the work context only. Client price is established
  when a Scoop is created/edited.
- Scoop creation requires a source language, target language and mandatory
  deadline date/time.
- Job creation inherits the Scoop source and target language and leaves both
  fields editable in Job Overview.
- Assignment with an approved Supplier rate creates the supplier snapshot and
  PO workflow. Assignment with no matching approved rate may use a manual
  `Fixed fee` exception.

## 2. Entity ownership matrix

| Entity / table family | Owns | Does not own | Main screens | Current state |
|---|---|---|---|---|
| Client / `clients` | Client code/name, legal identity, type, currency, payment defaults, restrictions and client-level instructions. | Account-only specialization or account-only pricing. | Clients, Project, Quote. | `VERIFIED` in migration `002`. |
| Account / `client_accounts` | Account name/code, blind-CV label, default source/CAT/production mode, instructions, terminology, restrictions and active flag. | Client identity; it cannot be selected for another Client. | Clients → Accounts, Project, Quote, rate-card selection. | `LOCKED`, `VERIFIED`. |
| Account specialization / `client_account_specializations` | Account default specialization links. | Final Project/Scoop specialization ownership; those are copied/selected in Project/Scoop context. | Accounts, Project, Scoop, rates. | `VERIFIED`; account defaults sync to Project. |
| Contacts / `client_contacts` | Contact identity and Account link, email/phone, primary/active flag. | Billing identity or project pricing. | Clients, Quote, Project. | `VERIFIED`. |
| Billing / `client_billing_entities` | Legal billing entity, address, tax/VAT data, currency, terms and default flag. | Historical issued invoice facts after issuance. | Clients, Project, Invoice. | `VERIFIED`; one default per Client. |
| Client rate card / `client_rate_cards`, `client_rate_items` | Account/client pricing rows by language pair, Service, Specialization, Unit, CAT band, currency and rate. | Supplier cost; Project Financials; historical Scoop snapshot values. | Client, Scoop Financials, Settings/catalogues. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Quote / `quotes`, `quote_items` | Quote number, client/account/contact/billing context, target-language items, validity, discount and acceptance status. | Accepted Project identity after conversion. | Quotes, Quote detail. | `VERIFIED`; portal/client acceptance is incomplete. |
| Project / `projects`, `project_specializations` | Project identity, Client/Account context, references, staff, production status, financial status, issue status and overall rollups. | Editable detailed client price lines, Scoop-specific deadline or Job supplier terms. | Projects, Project Overview, Financials. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Scoop / `project_scoops` | `S01` identity, language pair, mandatory deadline, client price, status/manual override and active flag. | Supplier assignment, PO version or Job-specific supplier cost. | Project → Scoops, Dashboard, Scoop editor. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Scoop financial line / `scope_items` | Description, quantity, unit, exact rate snapshot, CAT band, rate source, adjustment and amount for one Scoop. | Direct Project-wide editing. | Scoop editor; Project Financials read-only. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Job / `project_jobs` | Job number, Service, specialization, languages, Resource, deadline, quantity/unit, CAT analysis, supplier rate/currency/amount and production status. | Scoop client price; issued PO history. | Job Overview, Scoop job list, Dashboard. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Resource / `resources` and capability children | Internal or external identity, lifecycle, readiness, language pairs, Services, Specializations, compliance, availability, documents and rates. | Historical assignment ownership after deactivation. | Resources, Resource profile, assignment picker. | `LOCKED`, `VERIFIED`; external portal is incomplete. |
| Supplier rate card / `resource_rates` plus CAT rows | Resource-side language pair, Service, Specialization, Account scope, Unit, CAT band, rate, currency, validity and approval state. | Matching by Unit; Unit is inherited after selection. | Resource profile, Job assignment, PO. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Supplier PO / `supplier_purchase_orders` | Contextual PO number, current status/version, Resource/Project/Job links, currency and totals. | Mutable historical versions. | Job → Supplier PO. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| PO versions/lines / `supplier_po_versions`, `supplier_po_lines` | Immutable issued snapshot and its line-level quantity/unit/rate/adjustment/amount. | Current mutable rate card. | Supplier PO, version history/PDF/email. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Client invoice / `client_invoices`, `client_invoice_lines` | Draft/issued invoice facts, billing snapshot, official invoice number, currency, exchange rate and status. | Quote or Project identity mutation after issue. | Invoicing. | `VERIFIED`; full UI workflow `UNRESOLVED`. |
| Supplier invoice / `supplier_invoices`, `supplier_invoice_lines`, `payments` | Payable invoice and payment records, approval and payment dates. | Operational Job assignment. | Finance. | `VERIFIED`; full UI workflow `UNRESOLVED`. |
| Files / `file_records`, `file_access_logs` | File metadata, storage provider/object, role, checksum, retention/archive and access audit. | Uncontrolled direct public storage. | Project, Job, Resource documents. | `VERIFIED` schema; retention/access behavior `UNRESOLVED`. |
| Email/reminders/audit / `email_records`, `email_templates`, `reminders`, `audit_events` | Durable communication record, reminders, before/after values, actor, reason and timestamps. | Secrets or credentials. | PO email, dashboard, audit. | `VERIFIED` schema; coverage audit is P1. |
| Integration adapter / `integration_connections`, `integration_links`, `integration_events` | Provider configuration reference, entity links, sync state and errors for memoQ/Gmail/other systems. | Raw passwords/tokens; `secret_reference` must point to a server-side secret. | Settings/integration administration. | `VERIFIED` boundary; implementation `UNRESOLVED`. |

## 3. Field ownership and propagation matrix

### 3.1 Client, Account, Quote and Project

| Field / field group | Owner and editable location | Propagation/snapshot rule | Status |
|---|---|---|---|
| `clients.id`, `code`, legal/name and restriction fields | Client record; operational users may manage according to role, Administrator controls restricted actions. | Referenced by Account, Quote, Project and rate cards. Historical PO/invoice snapshots must not reread mutable Client data. | `VERIFIED`; snapshot audit `UNRESOLVED`. |
| `client_accounts.client_id`, `name`, `code`, `active`, restriction fields | Client → Accounts section; create/edit here only. | Account is filtered by selected Client. Account defaults can seed Project specializations and rate-card context. | `LOCKED`, `VERIFIED`. |
| `client_contacts.account_id` | Contacts are filtered by selected Client and optional Account. | Changing a Project Account cannot silently make an unrelated Contact valid; relation trigger rejects it. | `LOCKED`, `VERIFIED`. |
| `client_billing_entities.*` | Client billing section. | Project/Quote select only entities belonging to the Client; issued invoice stores a `billing_snapshot`. | `VERIFIED`. |
| `quotes.quote_number` | Generated annual sequence `Q-YYYY-NNNN`. | Accepted Quote is locked; revision preserves the accepted version. | `LOCKED`, `VERIFIED`. |
| Quote `status`, validity and `discount_amount` | Quote screen until acceptance. | `total = max(subtotal - discount_amount, 0)`; accepted Quote cannot be edited directly. | `LOCKED`, `VERIFIED`. |
| `projects.project_date` | Project creation. | Drives daily sequence and does not rename an existing identity. | `LOCKED`, `VERIFIED`. |
| `projects.project_number`, `display_name` | Generated by `next_project_display_name()`. | Immutable after creation; `protect_project_identity()` rejects later changes. | `LOCKED`, `VERIFIED`. |
| Project name format | `YYMMDD-N_CLIENTCODE_TARGET_CLIENTREF`; blank reference uses `NOREF`; `N` is that day's sequence. | Example: `260906-12_TEST_NB_NOREF`. A later Client reference is stored separately rather than renaming the Project. | `LOCKED`, `VERIFIED`. |
| `projects.client_id`, `account_id`, `contact_id`, `billing_entity_id`, `quote_id` | Project creation/edit by operations role, subject to relation validation. | Account/contact/billing selection stays within the Client. | `VERIFIED`. |
| `projects.source_language*`, `target_language*` | Primary language mirror for the first/primary Scoop; Scoop is the detailed language authority. | Editing the first Scoop updates Project mirror fields and connected Jobs/Dashboard fields under current propagation rules. Issued PO versions are not rewritten. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `projects.deadline` | Legacy compatibility/primary-Scoop mirror. | Project creation UI must not request it; Scoop deadline is the required operational deadline. | `SUPERSEDED` as creation input; `VERIFIED` as compatibility field. |
| Project Manager / QA / Coordinator resource links | `project_manager_resource_id`, `qa_specialist_resource_id`, `project_coordinator_resource_id`; Project creation selectors. | Project Manager selector lists active Internal Resources with the matching internal position. Historical Project staff links remain stored if an employee is later deactivated. | `LOCKED`, `VERIFIED` for schema/migration; live selector test `UNRESOLVED`. |
| Project specializations | `project_specializations`; seeded from Account defaults and editable in Project context. | Jobs and Scoop financial rows must use a Project specialization. | `VERIFIED`. |
| Project `price` | Read-only rollup from active Scoop prices. | `price = Σ active project_scoops.price`; UI editing is `SUPERSEDED` and must not return. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Project `expense` | Read-only supplier-cost rollup. | For each non-cancelled Job, current `Issued`/`Acknowledged` PO total is authoritative; otherwise the Job `supplier_amount` fallback is used. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Project profit/margin | Derived in the UI/rollup path: `Profit = Client price − Supplier expense`; `Margin = Profit / Client price × 100`; zero price produces `0`. | Dashboard, Scoop and Project summaries must use the same calculation and rounding authority. | Formula `VERIFIED`; cross-screen rounding audit `UNRESOLVED`. |
| Project `status`, `financial_status`, `issue_status` | Project workflow, finance and issue lifecycles are separate. | `Waiting` requires `waiting_reason` and `waiting_follow_up_at`; `Approved` changes `financial_status` from `Not Ready` to `Ready to Invoice`. | `LOCKED`, `VERIFIED`. |

### 3.2 Scoop and Scoop Financials

| Field / field group | Owner and editable location | Propagation/snapshot rule | Status |
|---|---|---|---|
| `project_scoops.scoop_number` | Generated per Project as `<project-number>-S01`, `-S02`, etc. | Differentiates Scoops and must be present in Dashboard, Project and Job breadcrumb links. | `LOCKED`, `VERIFIED`. |
| `source_language`, `target_language` | Scoop editor. Both are editable after initial selection. | Connected Job source/target values and Dashboard language values are updated by current Scoop update logic; immutable PO snapshots remain unchanged. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `deadline` | Scoop creation/edit; date and time are mandatory for new Scoops. | Past dates are rejected for new/changed deadlines and displayed red on Dashboard after they pass. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `price` | Calculated from Scoop financial lines; fallback only when no detail lines exist. | `project_scoops.price = Σ scope_items.price` for that Scoop; Project price then sums active Scoops. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `status`, `status_manual` | Scoop editor may select a manual status and enable override. | Without override: no active jobs/all Unassigned → `Assign`; assigned work → `Ongoing`; all active Jobs Delivered/Approved with at least one Delivered → `Ready for QA`; all Approved → `Approved`. A Job Delivered must not set Scoop to `Delivered to Client`. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `scope_items.project_scoop_id` | Required financial ownership link. | Project Financials groups by Scoop and must list each Scoop once, with CAT rows underneath rather than repeating the Scoop name on every row. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| CAT line `description`, `cat_band`, `quantity`, `price_unit`, `unit_price` | Scoop Financials editor. | Standard CAT bands: `New words`, `50–74%`, `75–84%`, `85–94%`, `95–99%`, `100%`, `Repetitions`. Quantity zero is valid; the current UI shows the full breakdown and no visibility selector. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Linked rate line `client_rate_item_id`, `rate_source` | Loaded from Client/Account rate card; only quantity is editable after linkage. | Service, Unit, Specialization and unit price remain a rate-card snapshot; later rate-card edits do not rewrite an existing Scoop. | `LOCKED`, `VERIFIED`. |
| Manual Scoop line | Add directly in Scoop without requiring a “reason” field. | It remains a manual line and is included in Scoop/Project totals. | `LOCKED`, `VERIFIED` in latest local replacement function; live test `UNRESOLVED`. |
| Adjustment fields | Scoop financial line supports adjustment type/amount where implemented. | Discount, surcharge, credit and minimum-fee behavior must be aligned with PO revisions and formula tests. | Base schema `VERIFIED`; full commercial behavior `UNRESOLVED`. |

### 3.3 Job, Resource assignment and supplier terms

| Field / field group | Owner and editable location | Propagation/snapshot rule | Status |
|---|---|---|---|
| `project_jobs.job_number` | Generated within the Scoop as `<scoop-number>-<service-code>_J01`, `J02`, etc. | Used in Job title, breadcrumbs and PO context; historical identities must remain stable. | `LOCKED`, `VERIFIED`. |
| `project_scoop_id` | Job creation from a specific Scoop; not a free Project-only selector. | Determines inherited languages, status aggregation, Scoop link and financial context. | `LOCKED`, `VERIFIED`. |
| `source_language`, `target_language` | Preselected from Scoop in Create Job; editable in Job Overview after selection. | Edits affect the current Job and current operational views, but must not mutate issued PO version snapshots. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `service_type`, compact service code | Job creation/overview from the shared Service catalogue. | Generates Job and PO code, e.g. `TRA`, `MTP`, `PRF`, `REV`. | `LOCKED`, `VERIFIED`. |
| `specialization_id` | Inherited from Project/service context and validated against Project specializations. | A Job cannot use an unrelated specialization. | `VERIFIED`. |
| `resource_id` | Assignment operation; new assignment only to an assignment-ready Resource. | Reassignment requires a reason, cancels the current active PO and preserves assignment/PO history. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `status` | Job Overview and assignment/delivery actions. | Assignment makes Job `Assigned`; it must have a Resource for production statuses. | `LOCKED`, `VERIFIED`. |
| Job `deadline` | Job-specific operational deadline. | It is distinct from Project and Scoop creation fields; past changed Job deadlines are rejected by trigger. | `LOCKED`, `VERIFIED`. |
| `quantity`, `unit`, `cat_analysis` | Job/Supplier PO context. Unit is inherited from the selected rate after card selection; Job must not ask for a separate pre-matching Unit. | CAT quantity and rates are normalized in the database; amounts are recalculated. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `supplier_rate`, `supplier_currency`, `supplier_amount` | Assignment/PO snapshot. | Current non-cancelled PO total is the financial source once a PO exists; Job fallback remains for no-PO cases. | `VERIFIED`. |
| Approved Supplier rate matching | Resource rate selected by language pair + Service + Specialization, with Account scope when applicable. Unit is not a matching rejection criterion. | Selected Unit/rate is copied into the Job/PO snapshot after selection. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Manual Supplier `Fixed fee` | Assignment action `assign_job_and_issue_po_flat_fee(job, resource, fee, currency, reassignment_reason)`. | Creates one `Fixed fee` line with no `resource_rate_id`, while retaining PO/version/email/audit workflow. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |

### 3.4 Resources and Internal Resources

| Field / field group | Owner and editable location | Propagation/snapshot rule | Status |
|---|---|---|---|
| Internal Resource identity | Resource profile: `Name`, `ResourceNumber`, `Email`, `Gender`, `Status`. | `internal_number` is generated as `RO-INT-00001` style; deactivation blocks access but does not delete historical links. | `LOCKED`, `VERIFIED` in migration `034`. |
| Internal positions | `internal_positions TEXT[]`; allowed values exactly `Project Manager`, `QA`, `Project`. Multiple selections are allowed. | Positions drive Project staff selectors; a position edit must not rewrite historical Projects. | `LOCKED`, `VERIFIED`. |
| `lifecycle_status` | Resource profile: `Active`, `On leave`, `Inactive`. | Non-Active Resources cannot receive new Job assignments; Internal `Inactive` makes `current_app_role()` return `NULL` and blocks application access. | `LOCKED`, `VERIFIED`. |
| `resource_status` | Unified readiness status: `New contact`, `Onboarding`, `Test assigned`, `Assignable`, `Proven`, `Preferred`, `Restricted`, `Do not use`. | Legacy `classification`, `eligibility_status`, `relationship_status` and `assignment_approved` are synchronized compatibility fields. | `LOCKED`, `VERIFIED`. |
| Assignment eligibility | Database requires lifecycle `Active`, resource status `Assignable`/`Proven`/`Preferred`, a non-empty email and relevant specialization/account checks. | `Do not use` and inactive resources are blocked. `Not tested` is informative; `Not approved` blocks the relevant specialization/account. | `LOCKED`, `VERIFIED`. |
| Resource test/qualification | `resource_tests` and `resource_account_qualifications`; test `Passed` promotes an eligible Resource to `Assignable`, failure maps to `Do not use` for the applicable flow. | Domain/account qualification is separate from general Resource readiness. | `VERIFIED`; full compliance workflow `UNRESOLVED`. |
| Resource rate card | `resource_rates` with language pair, Service, Specialization, optional Account, Unit, CAT band, rate to four decimals, currency, validity and `Pending/Approved/Rejected/Expired`. | Names are generated from included language pairs, rate, Service and Account context; rate selection happens before Unit is fixed in the Job. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Resource documents/compliance | `resource_documents`, `compliance_status`, expiry and review metadata. | Assignment eligibility must be checked against the applicable policy before production. | `VERIFIED` schema; policy completeness `UNRESOLVED`. |

### 3.5 Rate-card and pricing fields

| Area | Rule | Status |
|---|---|---|
| Matching key | Language pair + Service + Specialization; Account scope is applied where a rate card is Account-specific. | `LOCKED`, `VERIFIED`. |
| Unit | Unit is a property of the selected rate-card row and is selected/shown after card selection. Unit must not prevent an otherwise matching card from being selected. | `LOCKED`, `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Rate precision | Stored supplier rates use `NUMERIC(14,4)`; UI may display rounded values such as `11.9999 EUR` as `12 EUR` while calculations use the stored exact value. | `LOCKED`, `VERIFIED`; cross-screen display audit `UNRESOLVED`. |
| Client amount | Non-fixed line: `round(quantity × unit_price, 2)`. Fixed fee: amount is the rate when quantity is greater than zero, otherwise zero. | `VERIFIED` in `prepare_scope_amount()` and related triggers. |
| Supplier CAT amount | Each normalized CAT row uses its selected approved rate and `round(quantity × rate, 2)`; fixed fee uses the fixed-fee rule. | `VERIFIED` in `normalize_supplier_cat_analysis()`. |
| Scoop total | Sum of the active Scoop financial line amounts. | `VERIFIED` in migration `028`; P0 `IMPLEMENTED-REPORTED`. |
| Project client price | Sum of active Scoop prices. | `VERIFIED`; P0 `IMPLEMENTED-REPORTED`. |
| Supplier expense | Sum of non-cancelled Job costs; current `Issued`/`Acknowledged` PO total wins over the Job fallback. | `VERIFIED`; P0 `IMPLEMENTED-REPORTED`. |
| Profit | `Client price − Supplier expense`. | `VERIFIED` in UI/rollup paths. |
| Margin | `Profit / Client price × 100`; if Client price is zero, margin is `0`. | `VERIFIED` in current frontend; database-wide authority `UNRESOLVED`. |
| Discounts/surcharges/credits/minimum fees | Supported fields exist on financial/PO lines. Exact cross-module application and revision semantics still need one authoritative acceptance test. | `UNRESOLVED`. |

## 4. Status and transition matrix

### 4.1 Project and Scoop production statuses

Allowed labels:

`Assign`, `Ongoing`, `Ready for QA`, `Waiting`, `Ready to Deliver`, `Delivered to Client`, `Approved`

| Current status/event | Automatic result | Permitted manual result | Required data/notes |
|---|---|---|---|
| New Project/Scoop with no production work | `Assign`. | User may choose another Scoop status only with manual Scoop override. | Scoop has its own mandatory deadline. |
| A connected Job is assigned | Scoop becomes `Ongoing` unless manual override is active; Project workflow also moves the operational Project toward `Ongoing`. | Manual override may keep/return an earlier status. | Job must have a valid Resource/assignment workflow. |
| Job becomes `Delivered` | Scoop becomes `Ready for QA` when all active Jobs are Delivered/Approved and at least one is Delivered. | User may manually override Scoop status. | It must not become `Delivered to Client` merely because a Job was delivered. |
| All active Jobs become `Approved` | Scoop becomes `Approved`. | Manual override can return it to an earlier status. | Manual override must be explicitly stored. |
| `Waiting` | Remains `Waiting`. | User can leave/return from it according to operations workflow. | `waiting_reason` and `waiting_follow_up_at` are mandatory. |
| Manual Scoop override selected | Automatic Job-derived refresh stops. | User can explicitly return Scoop to a previous step for correction. | `status_manual = TRUE`; exact permission audit is P1. |
| Past Scoop deadline | Status is not automatically redefined by date. Dashboard deadline text is red. | User manages status separately. | Deadline display behavior is P0 `IMPLEMENTED-REPORTED`. |

### 4.2 Job statuses

Current final database check from migration `014`:

`Unassigned`, `Assigned`, `In Progress`, `Delivered`, `Revision Required`, `Approved`, `Cancelled`

| Transition | Rule | Status |
|---|---|---|
| Create Job → `Unassigned` | No Resource/PO assignment yet. | `VERIFIED`. |
| `Unassigned` → `Assigned` | Assignment RPC succeeds and Resource is valid. | `LOCKED`, `VERIFIED`. |
| `Assigned` → `In Progress` | Production starts after assignment. | `LOCKED` architecture; live UI transition `UNRESOLVED`. |
| `In Progress` → `Delivered` | Resource delivery action. | `LOCKED`, `VERIFIED` status label. |
| `Delivered` → `Revision Required` | QA/client issue requires correction. | `LOCKED`, `VERIFIED` label. |
| `Delivered`/`Revision Required` → `Approved` | QA/operations approval. | `LOCKED`, `VERIFIED` label. |
| Any applicable Job → `Cancelled` | Cancellation must preserve history and must not create a false completed cost. | `VERIFIED` status check; full cancellation UI `UNRESOLVED`. |
| Assigned Job → `Unassigned` | Only through cancellation/reassignment workflow, not by silently clearing Resource. | `LOCKED`, `VERIFIED` in assignment functions. |

Older migrations contained `Offered`/`Declined`; those are historical/legacy
labels and are not the current final production status contract. Job offer
records retain their own offer lifecycle.

### 4.3 Resource statuses

| Status family | Allowed labels | Effect |
|---|---|---|
| Lifecycle/access | `Active`, `On leave`, `Inactive` | Only Active Resources may receive new assignment. Internal Inactive Resources lose application access while their historical rows remain. |
| Readiness | `New contact`, `Onboarding`, `Test assigned`, `Assignable`, `Proven`, `Preferred`, `Restricted`, `Do not use` | Only Assignable/Proven/Preferred are assignment-ready; Preferred and Do not use have Administrator-only protection. |
| Specialization/account qualification | `Not tested`, `Test assigned`, `Approved`, `Not approved` | Not tested is informative; Not approved blocks the applicable specialization/account. |
| Compliance/document | `Unknown`, `Valid`, `Missing`, `Expired`, `Waived`; document rows `Pending`, `Valid`, `Expired`, `Rejected`, `Waived` | Compliance policy is recorded but full assignment gate coverage remains a P1 audit item. |

### 4.4 PO, Quote, financial, issue and integration statuses

| Entity | Allowed status labels | Transition/immutability rule |
|---|---|---|
| Supplier PO | `Draft`, `Issued`, `Acknowledged`, `Cancelled`, `Superseded` | Issued versions are immutable; revision creates a new version; cancellation preserves PO number, lines, versions and audit history. |
| Job offer | Current implementation uses offer records with draft/sent/viewed/accepted/declined/withdrawn behavior across the assignment RPCs. | The Resource does not operate a separate in-app accept/decline workflow in the current architecture; the operator confirms the assignment and issues the PO. |
| Quote | `Draft`, `Awaiting Client`, `Revision Requested`, `Accepted`, `Declined`, `Expired`, `Cancelled` | Accepted Quote and items are locked; change requires revision. |
| Project financial | `Not Ready`, `Ready to Invoice`, `Invoiced`, `Partially Paid`, `Paid`, `Overdue`, `Disputed`, `Cancelled`, `Credited` | Project production status and financial status remain separate. |
| Client invoice | `Draft`, `Issued`, `Partially Paid`, `Paid`, `Overdue`, `Disputed`, `Cancelled`, `Credited`, `Annulled` | Issued invoice facts are locked except Administrator-controlled annulment/credit path. |
| Job issue | `Issue Reported`, `Investigating`, `Correction Requested`, `Corrected`, `Resolved` | Issue is a separate lifecycle from Job production status. |
| Reminder | `Open`, `Acknowledged`, `Completed`, `Dismissed` | Reminder completion does not itself change Project/Scoop/Job production status. |
| Integration link | `Not linked`, `Linked`, `Pending`, `Synced`, `Conflict`, `Error`, `Disabled` | Provider sync is an adapter boundary; no provider may bypass internal audit/identity rules. |

## 5. Permission and access matrix

### 5.1 Current roles

The database profile role constraint currently permits:

`admin`, `pm`, `qa`, `client_relations`, `resource`, `user`

Current helper semantics:

- `is_admin()` → current application role is `admin`.
- `is_company_user()` → `admin`, `pm`, `qa` or `client_relations`.
- `can_manage_operations()` → `admin`, `pm` or `client_relations`.
- Internal Resource with `lifecycle_status = 'Inactive'` receives no current
  application role through `current_app_role()`.
- `resource` is returned only for an Auth profile linked to one External
  Resource with a currently permitted portal state. Generic `user` returns no
  workspace role.

### 5.2 Role matrix

The table below describes the current intended boundary. A row marked “audit”
means the database/source boundary exists or is partly implemented but still
needs a role-by-role live test.

| Capability | Administrator | PM / Operations | Client Relations | QA | External Resource / generic user | Evidence/status |
|---|---|---|---|---|---|---|
| Read company operational records | Yes | Yes | Yes | Yes | No through company policies; External Resource uses own-record RPCs and generic `user` has no workspace | `VERIFIED` RLS helpers; Update 039 local. |
| Create/edit Client, Account, Contact, Billing data | Yes | Yes through operations gate | Yes through operations gate | Read only under current helper | No | `VERIFIED` standard RLS. |
| Create/edit Quote/Project/Scoop/Job | Yes | Yes | Yes | No via `can_manage_operations()` | No | `VERIFIED`; exact UI permission split `UNRESOLVED`. |
| Edit Scoop financial lines | Yes | Yes | Yes | No current operations write | No | `VERIFIED` via `save_scoop_financial_lines()` and RLS. |
| Read Project Financials | Yes | Yes | Yes | Yes | No | `LOCKED`, `VERIFIED`. |
| Assign/reassign Resource and issue PO | Yes | Yes | Yes | No current operations gate | No | `VERIFIED` assignment RPC checks. |
| Revise an issued Supplier PO | Yes | Yes | No | No | No | Update 039 local; live role test required. |
| Add a new active catalogue value | Yes | Yes | No | No | No | Update 039 local; existing-value changes remain Administrator-only. |
| Link External Resource Auth account | Yes only | No | No | No | No | Update 039 Admin-only RPC. |
| Use manual Supplier `Fixed fee` | Yes | Yes | Yes | No current operations gate | No | `VERIFIED` `assign_job_and_issue_po_flat_fee()`. |
| Approve/reject Supplier rate | Yes | Operations may prepare but Administrator protection applies to approval/rejection | Same preparation boundary | No | No | `VERIFIED` `protect_admin_only_changes()`. |
| Mark Resource `Preferred` or `Do not use` | Yes | No | No | No | No | `VERIFIED` Administrator-only trigger. |
| Deactivate Internal Resource access | Yes, through lifecycle update | Operations may edit profile only if allowed; exact split audit | Operations may edit profile only if allowed; exact split audit | No | No | Access effect `VERIFIED`; actor permission `UNRESOLVED`. |
| Manage integration connections/secrets references | Yes only | No | No | No | No | `VERIFIED` admin-only RLS. |
| View non-secret integration links/events | Yes | Yes | Yes | Yes | No | `VERIFIED` standard company-read RLS. |
| Create/approve/annul official invoices | Administrator controls payment/approval-sensitive actions | Preparation only unless a later role rule is approved | Preparation only unless a later role rule is approved | No | No | `VERIFIED` admin-only protection for sensitive transitions; full UI `UNRESOLVED`. |
| Record payments | Yes only | No | No | No | No | `VERIFIED` trigger: only Administrator. |
| Download/upload/archival files | Administrator and operations according to current company policy | Operations | Operations | Company read only | External Resource may read/download files on its currently assigned Job; generic `user` has no access | Update 039 uses exact object policy and trusted immutable access logging; live test required. |

### 5.3 P1 permission hardening tests

These are the next live checks; they are not claimed complete.

1. Log in separately as each role and verify that the UI and Supabase RLS
   agree for every row in the role matrix.
2. Confirm `qa` can read the required Project/Job/Financial rows but cannot
   call operation-write RPCs unexpectedly.
3. Confirm `resource` cannot read company-wide operational tables or another
   Resource's Job/PO through direct routes or RPC parameters; confirm `user`
   cannot enter either workspace.
4. Deactivate an Internal Resource, confirm current access stops, then confirm
   old Project staff links, Jobs, POs and audit rows remain visible to
   authorized company users.
5. Confirm only Administrator can approve/reject rates, mark `Preferred` or
   `Do not use`, record payments, and manage integration connection rows.
6. Confirm changing Client, Account, Resource or rate-card data never changes
   an issued PO version snapshot or an approved historical invoice snapshot.

## 6. RPC and database write boundary

These are the principal write boundaries that the frontend should call instead
of reconstructing commercial rules in browser JavaScript.

| RPC/trigger boundary | Responsibility | Authority/status |
|---|---|---|
| `create_project()` / `create_project_with_specializations()` | Validate Client/Account/contact/billing relations, generate Project identity and create the initial Scoop context. | `VERIFIED`; Project pricing/deadline UI rules are `LOCKED`. |
| `next_project_display_name()` | Allocate concurrency-safe daily Project sequence and build `YYMMDD-N_CLIENTCODE_TARGET_CLIENTREF`. | `VERIFIED`; identity immutability trigger protects result. |
| `create_project_scoop()` / `update_project_scoop()` | Create/edit Scoop language pair, deadline, price/status/override; propagate current language fields to connected Jobs. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `refresh_project_scoop_status()` / `sync_project_scoop_status_from_job()` | Derive Scoop status from its Jobs unless manual override is active. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `save_scoop_financial_lines()` | Atomically replace/edit/delete the detailed lines of one Scoop, preserving linked rate provenance and recalculating totals through triggers. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `create_project_job()` / `prepare_project_job()` | Create a Job in its Scoop, generate service-code Job number, inherit languages/specialization and validate deadline/terms. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `save_job_overview()` / `save_job_overview_inherit_rate_unit()` | Persist editable Job overview values while protecting issued commercial/PO snapshots. | `VERIFIED`; later Job-term edit policy needs P1 decision. |
| `assign_job_and_issue_po()` | Assign Resource from an approved Supplier rate and issue PO through the existing offer/acceptance/version/email path. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `assign_job_and_issue_po_inherit_rate_unit()` | Current rate-selection path where Unit is inherited after the selected card row. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `assign_job_and_issue_po_flat_fee()` | Assign eligible Resource with manual `Fixed fee` when no matching approved rate exists. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `cancel_job_supplier_po()` | Cancel current PO, retain history, and support reassignment with reason. | `VERIFIED`. |
| `supplier_po_snapshot()` / `issue_supplier_po()` / `revise_supplier_po()` | Generate immutable PO version snapshots and controlled revisions. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `contextual_supplier_po_number()` / PO insert trigger | Build `PO-YYMMDD-N_S01-TRA_J01`; use `-R02`, `-R03`, etc. only to avoid a collision. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `refresh_supplier_po_display_name()` | Keep display title equal to PO number only; the Project name is not prefixed. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `create_internal_resource()` / `update_internal_resource_profile()` | Create/update simplified Internal Resource identity, positions, lifecycle and linked profile/access behavior. | `VERIFIED`; live access test `UNRESOLVED`. |
| `current_user_access_enabled()` / `current_app_role()` | Remove application role from an inactive Internal Resource without deleting history. | `VERIFIED`. |
| `normalize_supplier_cat_analysis()` | Resolve approved Supplier CAT rows, normalize quantity/unit/rate and calculate row/total amounts. | `VERIFIED`. |
| `refresh_project_financials()` / `sync_project_financials_from_po()` | Recalculate supplier expense from current non-cancelled PO totals and Job fallback. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| `protect_accepted_quote()`, identity protections and admin-only triggers | Lock accepted Quotes, Project identity, used specializations, PO lines and sensitive Resource/rate/invoice/payment changes. | `VERIFIED`; trigger coverage audit is P1. |

## 7. Audit, snapshot and integrity requirements

### 7.1 Required immutable or historical facts

| Fact | Required preservation | Current evidence/status |
|---|---|---|
| Project identity | `project_number` and `display_name` cannot be renamed; later Client reference is separate and audited. | `VERIFIED`, `LOCKED`. |
| Scoop language history | Current Scoop/Job operational fields may propagate; issued PO versions keep old language snapshot. | `VERIFIED` source rule; P0 `IMPLEMENTED-REPORTED`. |
| Rate-card history | Scoop/Job/PO store selected rate values/snapshots rather than rereading a later card. | `VERIFIED` in link/snapshot code; complete reread audit `UNRESOLVED`. |
| Supplier assignment history | Resource replacement requires reason; cancelled PO and old assignment remain. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| PO versions | Issued version rows and snapshots are immutable; revisions are new versions. | `VERIFIED`, P0 `IMPLEMENTED-REPORTED`. |
| Invoice facts | Billing snapshot and issued invoice facts are protected; credit/annulment is the correction route. | `VERIFIED` trigger; full workflow `UNRESOLVED`. |
| Resource deactivation | Access is disabled but historical Jobs/POs/Projects and audit rows remain. | `VERIFIED` access function; live test `UNRESOLVED`. |
| Files | Access/download/archive actions must be logged and retention respected. | Schema `VERIFIED`; policy and job tests `UNRESOLVED`. |

### 7.2 P1 audit coverage checklist

The following events must produce an `audit_events` row with actor, entity,
before/after values and reason where the action is a correction or exception:

- Project identity and Client reference changes;
- Project/Account/Contact/Billing changes;
- Scoop language, deadline, status/manual override and financial edits;
- Job language, Service, specialization, deadline, quantity and status edits;
- Resource lifecycle, readiness, compliance and assignment changes;
- Supplier rate creation, approval, rejection and expiry;
- Client rate-card creation, change and deactivation;
- Assignment, reassignment and reassignment reason;
- PO issue, email send, acknowledgement, cancellation and revision;
- PO line quantity/rate/adjustment changes;
- Invoice issue, credit, annulment and payment;
- File upload, view, download, archive and delete;
- Integration link create, sync, conflict, error and disable.

Current schema contains `audit_events` and `file_access_logs`, but complete
coverage for every bullet is `UNRESOLVED` until the live/database trigger
audit is completed.

## 8. Migration and deployment controls

### 8.1 Relevant migration chain

| Migration | Role in current architecture |
|---|---|
| `001_operational_foundation.sql` | Foundation, profiles/roles, early Client/Project/Financial records and RLS. |
| `002_operational_core.sql` | Normalized Client/Account/Quote/Project/Resource/Job/PO/Invoice/File/Audit/Integration schema, statuses and standard RLS. |
| `003_resources_module.sql` through `006_internal_staff_assignments.sql` | Resource operations, lifecycle and internal staff links. |
| `007_specializations_and_resource_rates.sql` through `010_unified_resource_status_and_tests.sql` | Specializations, Supplier rate structure, test/qualification and unified Resource readiness. |
| `011_client_rate_cards_and_simplified_project_grid.sql` through `022_project_profit_and_po_cost_sync.sql` | Client rate cards, CAT financials, PO versions/email, financial rollups and historical fixes. |
| `023_multiple_project_jobs.sql` | Multiple Jobs per Project baseline. |
| `024_job_service_codes_and_sorting.sql` | Shared service codes and Job ordering. |
| `025_inherited_job_terms_scoped_rates_and_financial_rollup.sql` | Inherited Job terms, Account-scoped Resource rates and financial rollup repair. |
| `026_service_catalog_and_settings.sql` | Shared Service catalogue and Settings foundation. |
| `027_project_scoops_and_rate_matching.sql` | Scoop layer, Scoop parent link for Jobs and precise rate matching. |
| `028_scoop_financials_and_dashboard.sql` | Scoop prices and Scoop-first financial rollup. |
| `029_catalogs_and_scoop_financial_editor.sql` | Language catalogue and Scoop-owned financial editor. |
| `030_catalog_rate_coverage_and_project_total_repair.sql` | Language/rate coverage and Project total repair. |
| `031_read_only_project_financials_automatic_rate_names_and_rate_units.sql` | Read-only Project Financials, generated rate names, inherited Unit behavior. |
| `032_scoop_status_and_compact_rate_card_names.sql` | Scoop status automation/manual override and compact names. |
| `033_scoop_workflow_accounts_po_names_and_financial_groups.sql` | Account workflow, contextual connected PO labels, one-group financial presentation and no manual-line reason requirement. |
| `034_internal_resources_scoop_deadlines_and_context_numbers.sql` | Internal Resource simplification/access, mandatory Scoop deadline, daily Project sequence and contextual PO numbering. |
| `035_job_language_flat_fee_po_label_and_deadline.sql` | Job language fallback/editability, manual flat-fee assignment, PO label normalization and deadline UI support. |
| `036_p1_permission_snapshot_hardening.sql` | P1.1 append-only PO versions/audit/file-access logs, restricted write policies and status-change audit events. Prepared locally; live execution pending. |
| Local Update 038 package | Frontend/manual package for the P0 behaviors: no CAT visibility selector/full grid, PO display label, Dashboard overdue deadline styling and connected Job language/flat-fee UI. The exact package must be uploaded manually by the user. |

### 8.2 Deployment rule

Codex must not upload or push updates. The user manually uploads the prepared
files, runs the migrations in the intended order, waits for the host deploy and
reports the live test result. Any future migration must be:

1. additive and idempotent where possible;
2. explicit about the migration it follows;
3. safe for existing Projects, Scoops, Jobs, POs and snapshots;
4. accompanied by a rollback/data-repair note if it changes a stored total;
5. added to a live-applied ledger rather than relying only on filename order.

The live-applied migration ledger is currently `UNRESOLVED`.

## 9. P1 hardening backlog

| Priority | Work item | Acceptance condition | Status |
|---|---|---|---|
| P1 | Complete entity/field matrix | Every editable field has one owner, one UI editor and one database boundary. | This document created; live sign-off `UNRESOLVED`. |
| P1 | Audit RLS and `SECURITY DEFINER` RPCs | Direct table writes cannot bypass role rules; each RPC checks actor and parent ownership. | `UNRESOLVED`. |
| P1 | Audit snapshot boundaries | Issued PO, accepted Quote, invoice and historical rate facts never reread mutable parent data. | `UNRESOLVED`. |
| P1 | Add/verify audit coverage | All events in section 7.2 have actor, before/after, reason and timestamp. | `UNRESOLVED`. |
| P1 | Live Internal Resource deactivation | Access stops; historical selectors/reports preserve old rows; new assignment is blocked. | `UNRESOLVED`. |
| P1 | Formula/rounding authority | Same exact cents/four-decimal rules produce identical Scoop, Project and Dashboard totals in EUR and non-EUR cases. | `UNRESOLVED`. |
| P1 | Commercial adjustments | Discount, surcharge, credit and minimum fee work in Scoop, PO revisions, Project Financials and invoices. | `UNRESOLVED`. |
| P1 | Manual flat-fee revisions | Decide whether a manual fee may be changed after assignment and define the required PO version/reason. | `UNRESOLVED`. |
| P1 | Migration ledger/repair scripts | Live database records applied migrations and can safely repair partially applied chains. | `UNRESOLVED`. |
| P2 | Client onboarding and outreach | Qualification, outreach stages, follow-up logic and communication rules are represented in the TMS or explicitly integrated. | `UNRESOLVED`. |
| P2 | Freelancer onboarding/compliance | Registration, profile, tests, agreements, signatures, portal and assignment eligibility are complete. | `UNRESOLVED`. |
| P2 | Invoices/payments | Client and Supplier invoice workflows, official numbering, credits, annulments and payment reconciliation are complete. | `UNRESOLVED`. |
| P3 | memoQ/Gmail/backup automation | Server-side integrations, retries, reminders, backups, retention and restore tests are production-ready. | `UNRESOLVED`. |

## 10. Decisions still requiring confirmation

These are not silently converted into implementation requirements.

1. Exact Quote → Project → Scoop cardinality when one Quote contains multiple
   target languages and the operator later adds additional Scoops.
2. Whether a Project display name remains permanently immutable when Client,
   Account or target language changes after creation. The current source locks
   the name/number, but this remains listed because the broader business rule
   was not separately re-confirmed in the P0 message.
3. Whether an assigned manual-flat-fee Job may change language/Service terms
   without first creating or approving a Supplier rate card.
4. Whether the contextual Supplier PO number is immutable for the entire Job
   history, or whether only issued PO versions are immutable while a new
   contextual number may be generated after reassignment.
5. Authoritative currency-conversion source, rate date and rounding rule when
   Client and Supplier currencies differ.
6. Whether a later release should permit a Resource to acknowledge a PO or
   update delivery status. Update 039 intentionally remains read-only.
7. Whether outreach CRM belongs inside the TMS or remains external until the
   operational core is fully audited.
8. Whether QA should receive any write permissions in a later phase. Update
   039 keeps QA read-only.
9. Whether Operations/PM/Client Relations should be split further for Client,
   Account, rate-card and invoice actions.

## 11. Chronological implementation checkpoints

| Approximate sequence | Decision/checkpoint | Classification |
|---|---|---|
| Updates 027–031 | Scoop inserted between Project and Job; Scoop-owned pricing; Project Financials made read-only; rate matching narrowed; Unit inherited after card selection. | `LOCKED`, `VERIFIED` from local migrations. |
| Update 032 | Scoop status automation/manual override; compact rate-card names. | `LOCKED`, `VERIFIED`. |
| Update 033 | Account workflow, one Scoop grouping in financial presentation, no reason for manual Scoop line, connected PO labels. | `LOCKED`, `VERIFIED`. |
| Update 034 | Internal Resource simplified fields/multiple positions/deactivation, mandatory Scoop deadline, daily Project sequence, contextual PO numbering. | `LOCKED`, `VERIFIED`. |
| Update 035 / local Update 038 | Job language inheritance/editability, manual Supplier flat-fee path, PO display label without Project name, no CAT visibility selector, overdue Dashboard deadline. | `LOCKED`, `VERIFIED` locally; P0 `IMPLEMENTED-REPORTED`. |
| 2026-09-06 | User reported: “P0 is completed.” | `IMPLEMENTED-REPORTED`. |
| 2026-09-06 | P1 entity/field/status/permission matrix and hardening plan prepared locally. | `VERIFIED` as documentation; live implementation `UNRESOLVED`. |
| 2026-09-06 | P1.1 append-only history, trusted writers and live audit checks completed. | `IMPLEMENTED-REPORTED`. |
| Update 039 | Dedicated External Resource portal, generic-user rejection, QA UI read-only gate, PM catalogue-add and PO-revision boundary. | Implemented locally; migration/audit and live role tests pending. |

## 12. What the next AI must know from TMS3

- Treat Scoop, not Project, as the owner of client price and detailed financial
  lines.
- Treat Project Financials as read-only aggregation and show each Scoop once;
  CAT rows must not duplicate the Scoop name on every row.
- Do not restore Project-level price or Project-level creation deadline fields
  in the UI. Price and mandatory date/time deadline are Scoop fields.
- A Job belongs to exactly one Scoop, inherits its languages initially and may
  edit Source/Target afterward. Issued PO snapshots are not rewritten by such
  edits.
- Rate matching is language pair + Service + Specialization, with Account
  scope when relevant. Unit is inherited after a matching rate is selected and
  is not a pre-filter that rejects the card.
- If no approved Supplier rate card matches, an eligible Resource may still be
  assigned with a manual `Fixed fee`, keeping the PO/version/email/audit flow.
- CAT rows use exact normalized rates and quantity-based amounts. The current
  accepted UI shows the full CAT breakdown and has no “show zero-quantity rows”
  selector.
- Project/Scoop status is not one generic status: Job Delivered should move a
  Scoop to `Ready for QA`, not `Delivered to Client`; manual Scoop override is
  allowed.
- The current production status labels are exact and case-sensitive:
  `Assign`, `Ongoing`, `Ready for QA`, `Waiting`, `Ready to Deliver`,
  `Delivered to Client`, `Approved`.
- Project identity format is exact: `YYMMDD-N_CLIENTCODE_TARGET_CLIENTREF`;
  Scoop uses `-S01`; Job uses `-TRA_J01`-style compact service numbering;
  PO uses `PO-YYMMDD-N_S01-TRA_J01` and its display title is PO number/version
  only.
- Internal Resource positions are a multi-select restricted to `Project
  Manager`, `QA`, `Project`; deactivation must stop access without deleting
  historical references.
- Current role helpers are `admin`, `pm`, `qa`, `client_relations`, `resource`
  and `user`; `can_manage_operations()` excludes `qa`, while
  `is_company_user()` includes `qa`. External `resource` is resolved only from
  an exact linked External Resource and receives RPC projections, while
  generic `user` receives no workspace.
- Do not push or upload updates automatically. Prepare local files, migrations
  and documentation for the user to upload manually.
- P0 is reported complete; P1 is the next work package and must begin with
  RLS/permission, audit, snapshot, migration-ledger and formula hardening
  before adding large new UI modules.
