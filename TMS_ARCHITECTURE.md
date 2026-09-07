# Retodo Ops TMS — Approved Operational Architecture

This document records the workflow decisions approved during the module review.
The database and interface must preserve these distinctions rather than
collapsing commercial, production and financial states into one status.

## TMS3 canonical baseline

This section is the current architecture authority for the implemented TMS
core. Older descriptions elsewhere in this document remain useful historical
context, but they must not reintroduce Project-level pricing, Project-level
delivery deadlines or editable Project Financials.

### Canonical hierarchy

`Client → Client Account → Project → Scoop → Job → Resource / Supplier PO → Financials`

- **Client** owns Accounts, contacts, billing entities and client-side rate
  cards.
- **Account** supplies account-specific specializations, instructions and
  pricing context. Account is optional and may be `Non-defined`.
- **Project** owns the client/work context, project manager, QA, coordinator,
  references and overall production context. A Project may contain multiple
  Scoops.
- **Scoop** is the independent language/pricing unit inside a Project. It has
  its own source language, target language, mandatory deadline, client price,
  financial lines, status and differentiator (`S01`, `S02`, …). A Scoop may
  contain multiple Jobs.
- **Job** is the assignable production task. It inherits Scoop languages on
  creation but Source and Target remain editable in Job Overview. Each Job has
  its own Resource assignment, supplier cost, PO and production status.
- **Supplier PO** is the supplier-cost and assignment snapshot. Its issued
  versions are immutable; later changes create a new version.
- **Project Financials** is a consolidated read-only view. Client price and
  detailed financial rows are edited only inside the owning Scoop.

### TMS3 commercial invariants

- Project creation does not request a Client price. Price is defined while a
  Scoop is created or edited.
- Project creation does not request a Project deadline. Scoop creation
  requires deadline date and time.
- Project Financials lists each Scoop once as its owning financial group; CAT
  breakdown rows must not repeat the Scoop name on every row.
- Client and Supplier rate matching uses language pair, Service and
  Specialization. Unit is selected after a rate card is selected and is not a
  reason to reject an otherwise matching card.
- If no approved matching Supplier rate card exists, an eligible Resource may
  still be assigned with a manually entered `Fixed fee`. That exception keeps
  the PO and audit workflow but has no rate-card provenance.
- CAT payment grids have no zero-quantity visibility selector. The full
  breakdown is displayed when the grid is shown, including zero-quantity rows.
- Source and Target edits on a Scoop propagate to connected operational fields
  and Dashboard views according to the existing history rules. Issued PO
  versions remain immutable snapshots.
- An External Resource signs into a dedicated read-only workspace. It sees only
  its currently assigned Jobs, minimum technical Project/Scoop references,
  production terms/instructions, own Job files/issues and its own immutable
  Supplier PO history. Client/Account identity, Client price, profit, margin,
  other Jobs/Resources, Settings and company actions are excluded.

### Current naming authority

- Project: `YYMMDD-N_CLIENTCODE_TARGET_CLIENTREF`, where `N` is the sequence
  of the Project on that date. `NOREF` is used when the Client reference is
  blank.
- Scoop: `<project-number>-S01`, `<project-number>-S02`, …
- Job: `<scoop-number>-<service-code>_J01`, `<scoop-number>-<service-code>_J02`, …
- Supplier PO number: contextual format such as
  `PO-260906-1_S01-TRA_J01`.
- PO display title: the PO number and version only, for example
  `PO-260906-1_S01-TRA_J01 · V1`; the Project or Job name is not prepended.

### Current status authority

- Project/Scoop production flow: `Assign → Ongoing → Ready for QA → Waiting →
  Ready to Deliver → Delivered to Client → Approved`.
- A Scoop becomes `Ongoing` when a connected Job is assigned. A Job reaching
  `Delivered` moves the Scoop to `Ready for QA`; it does not move the Scoop
  directly to `Delivered to Client`.
- Scoop status is automatic from Jobs unless the user selects Manual status
  override. Manual override may return a Scoop to an earlier step when an
  operational correction requires it.
- Job flow: `Unassigned → Assigned → In Progress → Delivered → Revision
  Required → Approved`; `Cancelled` is the terminal outcome.
- Resource readiness requires lifecycle `Active`, status `Assignable`,
  `Proven` or `Preferred`, and a valid email address.

## Core record flow

Inquiry → Quote → Client confirmation → Project → Scoop(s) → Job(s) → Client invoice → Payment

- A Quote may contain several target languages.
- Acceptance creates one linked Project per target language.
- A confirmed client PO/email assignment may create a Project without a Quote.
- A Project may contain several independent Scoops. Each Scoop may contain
  several sequential or parallel Jobs.

## Numbering and names

- Project display name: `YYMMDD-N_CLIENTCODE_TARGET_CLIENTREF`, where `N` is the
  daily Project sequence.
- Missing client reference uses `NOREF`.
- Example: `260906-12_TEST_NB_NOREF`.
- Scoop names append `-S01`, `-S02`, and so on. Job names append the compact
  Service code and Job sequence, for example
  `260906-12_TEST_NB_NOREF-S01-TRA_J01`.
- Project display names are immutable after creation. If a Client reference is
  supplied later, a Project originally named with `NOREF` keeps that name,
  folder path and external links. The later reference is stored separately,
  remains visible/searchable and records its first receipt time and updater.
- Official Bulgarian invoice numbers are ten digits and are assigned at issue,
  not while the invoice is still a draft.
- Project creation does not request a Project deadline. The Scoop deadline
  date and time are mandatory and are entered when the Scoop is created.

## Separate lifecycles

### Quote

Draft → Awaiting Client → Revision Requested → Accepted

Other outcomes: Declined, Expired, Cancelled.

- Quote numbers use an annual sequence: `Q-YYYY-NNNN` (for example,
  `Q-2026-0001`).
- Default validity is 30 days and remains editable per Quote.
- Accepted Quotes are locked. A later commercial change requires a revision,
  preserving the accepted version and its Project links.
- Acceptance is transactional and creates one Project per distinct target
  language. Quote-wide discounts are allocated proportionally to those
  Projects.

### Project production

Assign → Ongoing → Ready for QA → Waiting → Ready to Deliver →
Delivered to Client → Approved

- Waiting requires a reason and follow-up date.
- Approved means ready to invoice.

### Job, assignment and Supplier PO

- Job: Unassigned → Assigned → In Progress → Delivered → Revision Required → Approved
- Job outcome: Cancelled

Resource agreement happens operationally before the PO is issued; the Resource
does not accept or decline an offer inside the TMS. The operator selects the
Resource, Approved Supplier rate card and CAT quantities, then issues the PO.
That single action creates an internal commercial snapshot, assigns the Job,
moves an Assign Project to Ongoing and issues Supplier PO version 1. The PO
email is placed in the durable outbound queue for the configured mail worker.

If the Resource later withdraws, the PO is Cancelled without deleting its
number, lines or versions, and the Job returns to Unassigned. Selecting a new
Resource requires a reason, cancels the current PO and issues a new PO while
preserving both assignment histories.

### Financial

Not Ready → Ready to Invoice → Invoiced → Partially Paid → Paid

Additional states: Overdue, Disputed, Cancelled, Credited.

The Project tab is named **Financials**. It is a consolidated read-only view;
the owning Scoop is the only place where Client price, quantities and detailed
rate-card rows may be edited. Once financial lines exist, their sum is
authoritative and the Scoop Client price is calculated automatically.

For CAT work, the operator may load an eligible Account/Client rate card or a
blank zero-price grid inside a Scoop. The grid always starts with all standard rows — New
words, 50–74%, 75–84%, 85–94%, 95–99%, 100% and Repetitions — and quantity 0.
Each Client rate-card group stores one base price; its CAT rows store discount
percentages and are recalculated automatically. The Scoop grid inherits its
Service and Specialization from the Project rather than asking for them again.
Quantities are typed directly in the grid and the bold Scoop total at the
bottom recalculates immediately. Individual rows may be removed when they do
not apply. A rate-card line keeps
the exact Client rate-item link plus a Scoop snapshot, so a later rate-card
change does not rewrite historical Scoop pricing.

Detailed Scoop financial rows use the same inline table pattern as Supplier
PO lines: Description, Quantity, Unit, Unit price, Rate source, Adjustment and
Amount. Manual rows are added directly in the Scoop table without requiring a
reason; linked Client/Account rate rows retain their provenance and allow
quantity-only edits. Discount, Credit,
Surcharge and Minimum fee adjustments are explicit rather than encoded as
unlabelled positive or negative values. The Project Financials result remains
visible as a read-only consolidated summary and shows Client price, current
Supplier expense, Profit and Profit margin together. Fixed-price Scoops use the
same calculation path.

### Post-delivery issue

Issue Reported → Investigating → Correction Requested → Corrected → Resolved

This does not overwrite the Job or financial status.

## Dashboard columns

Project | Client | Account | Language Pair | Deadline | PM | Status | Type |
PO | Price | Expense | Margin | Email Reference

Project creation runs as one database transaction. It validates Client,
Account, Contact and Billing Entity relationships, applies Account defaults,
generates the collision-safe display name and then creates the record. A blank
Client reference is represented as `NOREF` in the name while remaining blank in
the underlying Client-reference field.

## Client and Account model

- Client supports LSP/Agency and Direct Client types.
- A Client may have multiple legal Billing Entities. One may be the default;
  Quotes, Projects and invoices may override it.
- Issued invoices retain an immutable billing-details snapshot so later changes
  to a legal name, address, registration or VAT number do not rewrite history.
- Account is optional; projects may use `Non-defined`.
- Every Account defines at least one specialization. Account selection supplies
  and locks those Project specializations, together with instructions, CAT
  tool, confidentiality settings and Account-specific pricing. When Account is
  `Non-defined`, at least one Project specialization is selected manually.
- Every Job has exactly one required specialization selected from its Project's
  specializations. Existing Job or commercial-line use prevents that
  specialization from being removed from the Project.
- Pricing precedence: Account rate → Client rate → manual/fixed project price.
- Project contacts are limited to Client-wide contacts and contacts belonging
  to the selected Account. Place of delivery is captured from Project creation
  and may contain a portal, email address, folder or delivery link.
- Account names have a separate blind-CV label and disclosure permission.
- Do-not-work-with Clients remain in financial and audit records.

## Resource model

Resource lifecycle is independent of work history and commercial records:

- Active — available for approval and new assignment.
- On leave — retained on existing Projects/Jobs but excluded from new work.
- Inactive — retained permanently on historical and still-open records, while
  excluded from all new assignments. Portal/financial access is managed
  separately so outstanding payments can still be completed.

Project Manager, QA Specialist and Project Coordinator are references to
Internal Resources, with a name snapshot retained for readable history. An
Inactive Internal Resource remains visible on the Project and can be replaced
with an Active Internal Resource.

Relationship, classification, eligibility, assignment approval and priority are
represented by one user-facing Resource status:

- New contact
- Onboarding — includes discussion, profile completion, documents and rate
  negotiation
- Test assigned
- Assignable — passed the General test and may receive production work
- Proven — completed approved work successfully
- Preferred
- Restricted — retained in the Resource list but unavailable for new assignments
- Do not use — blocks all new assignments

Lifecycle remains independent: Active / On leave / Inactive. It controls current
availability without rewriting historical Project or Job relationships.

Language pairs and Services are declared capabilities without separate approval
checkboxes. Domain and Account qualification use Not tested / Test assigned /
Approved / Not approved. These values provide operational evidence and warnings;
the unified Resource status remains the only approval gate. A failed General
test changes the Resource status to Do not use. A Resource moves from Assignable
to Proven after its first approved Job; Preferred remains an explicit management
decision.

Resource profile sections include identity/contact, language pairs, services,
specializations, rates and CAT bands, education/CV, tools, availability,
quality/restrictions, compliance, project history, LinkedIn/outreach, invoicing
details and audit history.

The original database is imported in full. Imported Resources begin at the
mapped Resource status and remain subject to review. Source and target language
filters are independent and may be combined with service, specialization,
Resource status and availability. Raw legacy notes are preserved
in an Administrator-only archive; operational users see only a concise current
restriction/assignment instruction.

Quality uses an internal 1–5 rating plus written evidence.

## Freelancer portal

- Invitation-only, single-use link valid for 14 days.
- Portal account activates automatically after registration.
- Assignment readiness follows the unified Resource status and test results.
- Rate changes remain pending until approved.
- Initial release includes profile management, availability, assigned Jobs,
  project files, delivery, PO acknowledgement, revisions,
  invoice submission and payment tracking.

Portal, assignment and financial statuses remain independent. A Do-not-use
resource with unpaid obligations receives Financial-only portal access. After
final payment, read-only financial access remains for 90 days before closure.
Only the Administrator can apply Do not use.

## Blind CV

Output: editable DOCX plus final PDF.

Include internal Resource ID, initials, nationality, country of residence,
language pairs, services, specializations, education, experience,
certifications, tools and selected anonymized project history.

Exclude name, personal contact details, LinkedIn URL, supplier rates and client
identity. Account names appear only when disclosure is explicitly allowed;
otherwise the Account's blind-CV label is used.

Approved Jobs feed Resource Project History automatically. The CV generator
groups work by period, Account/blind label, language pair, service and
specialization.

Creating or changing a Job assignment checks Resource status, lifecycle,
compliance and the exact domain/Account qualification. Only the Administrator
may override a Restricted or incomplete-compliance Resource, with a mandatory
reason. An explicit Not approved qualification and Do not use status remain
blocking. The current non-cancelled Supplier PO version is the authoritative
Job cost. Its total rolls up automatically to Project expense, Profit and
Profit margin; a Job without a PO falls back to its saved supplier amount.

## Rates, CAT analysis and POs

Supported pricing units: source words, target words, hours, pages, minutes and
fixed fee. Each supplier rate card contains one base price. Optional CAT rows
store a discount percentage against that base; the TMS calculates and retains
the derived repetition, context-match, exact-match and fuzzy-match prices.
Validity dates are not used in the operational interface: approval status and
commercial version history control whether a rate may be selected.

Client rates load from Client/Account rate cards. Supplier expenses load from
an approved base Supplier rate-card row matching the Job's language pair,
Service and Specialization. Unit is inherited from the selected rate-card row
after selection and is not a matching blocker. The selected rate-row ID remains linked
to the assignment snapshot and Job for provenance, while the agreed rate, currency, quantity
and amount are retained as immutable commercial snapshots. Fixed/manual Client
pricing remains available with an override reason; an assignment cannot use a
free-text supplier rate. Supplier PO production lines retain the Resource-rate
reference and CAT band/discount provenance; manual and adjustment lines remain
explicitly distinguishable.

Candidate Resource selection uses the unified Resource status as its single
approval control. An External Resource is selectable when lifecycle is Active
and Resource status is Assignable, Proven or Preferred. Language pairs,
Services, domain/Account qualifications, compliance and availability remain
visible context; the approved matching Supplier rate card separately controls
which commercial terms can be assigned.

Resource capabilities and qualifications are maintained data, not immutable
intake facts: language pairs and Services may be removed, Specialization
qualification may be revised after new evidence, and Supplier rate cards may be
edited. Removing a capability retires affected current rate cards without
rewriting historical assignment, Job or Supplier PO snapshots.

Supplier POs are sent through portal and email. Work may begin as soon as the
PO is issued. There is no intermediate Draft or Resource-acceptance step:
version 1 is issued immediately and any later correction creates a new
immutable version.
Discounts, credits, surcharges and minimum-fee adjustments are supported.
Supplier PO numbers use the contextual Project/Scoop/Service/Job format, such
as `PO-260906-1_S01-TRA_J01`. The PO display title contains only that number
and its version. Automatic issue through an allowed Resource-assignment flow
remains available to operational roles; only Administrator may manually issue
an existing Draft PO; Administrator and PM may create an immutable revision.
Client and Account identity remain hidden from the External Resource.

## Invoices

- The TMS generates official Retodo EOOD client invoices.
- Drafts have internal draft IDs; official numbers are assigned at issue.
- The proposed number is Administrator-editable before issue and validated for
  uniqueness/sequence.
- Issued invoices are locked. Corrections use annulment/replacement or credit
  documents rather than overwriting.
- No Statements module in the initial release.
- EUR is the reporting base; original currency and exchange differences remain
  separately visible.

Default freelancer invoicing cycle: 15th and 30th; default payment term: 60
days. Resource-specific terms may override it.

## Files, CAT and memoQ

- Client CAT servers are used when supplied.
- Retodo Ops plans to use its own memoQ server when the Client provides none.
- Active files use private Supabase Storage with role/job-specific access.
- Closed projects archive to Google Drive.
- Default active-file retention is three months unless the Client/Account rule
  differs.
- Every freelancer download is logged.
- Client file exchange is by email initially.

memoQ integration is deferred but supported by stable external system,
connection, ProjectGuid, document Guid, link, synchronization state and event
records. API secrets must remain server-side and never be stored in frontend
configuration.

Implementation boundary:

- Retodo remains the operational source of truth for Client, Account, Quote,
  Project, Job, Resource, price, deadline, PO, invoice and audit data.
- `integration_connections` represents Retodo-owned, Client-owned and sandbox
  environments. It stores only non-secret configuration and a server-side vault
  reference.
- `integration_links` maps any Retodo Project, Job, Resource or File to the
  corresponding memoQ identifier, `ProjectGuid`, document `Guid` and web link.
- `integration_events` records queued/succeeded/failed sync attempts and allows
  safe retries with an idempotency key.
- The later connector must run server-side. No memoQ API key, password or
  session token may appear in `config.js`, browser storage, public Netlify
  variables or plaintext database fields.
- Linking remains optional per Project. This permits Client CAT servers, a
  future Retodo memoQ server and non-memoQ/file-only projects to coexist.
- Each Account may default to `Client CAT`, `Retodo memoQ`, `File workflow` or
  `Not selected`; the Project retains an override. Once a connector exists, the
  Project screen should offer both **Create in memoQ** and **Link existing
  memoQ project** actions.

## Email and reminders

Gmail remains the mailbox for `ops@retodo-ops.com`. Supplier POs are sent by an
authenticated Netlify server function using the narrow `gmail.send` scope;
OAuth credentials and the refresh token exist only in the Netlify Functions
runtime configuration and never in browser code. Every delivery attempt is
linked to one immutable PO version and recorded as Sent or Failed with
recipient, timestamp and Gmail message/thread IDs. Email subjects include the
PO number and explicit version label (`V1`, `V2`, `V3`, and so on). Re-sending
one version creates a separate audit attempt and never replaces or rolls back a
newer PO version. Incoming emails are linked manually at first.

Operational reminders appear in the dashboard and selected reminders also use
email. No email reminder is sent for Quote expiring, Missing PO, Ready to
Deliver, Invoice ready to issue or expiring CV. Those remain dashboard states.

Priority/high-use Resource unavailability sends an email to
`ops@retodo-ops.com`, including dates, languages and active deadline conflicts.

## Reports

Project and Job reports mirror the reference TMS's complete filter/report
structure using Retodo Ops terminology. Other initial reports: Quotes,
Resources, Financial and Workload. Reports run on demand only. Financial views
show original currency and converted EUR values.

## Roles

- Administrator: full control and final approvals.
- Project Manager: operational access; may add new active catalogue entries
  and create Supplier PO revisions, but may not alter existing catalogue
  entries or link an External Resource Authentication account.
- Client Relations/Operations (Eli): full financial visibility; may manage
  Clients, Accounts, Quotes, Projects, Jobs, assignments, email and document
  drafts.
- QA: company read-only access. Operational form controls and write actions are
  disabled, and database write boundaries remain authoritative.
- Only Administrator may issue/annul official invoices, approve supplier
  invoices/payments/rates, override compliance, apply Do not use or manage
  users/security.
- External Resource: dedicated read-only portal for own assigned Jobs,
  technical work context, own Job files/issues and own issued Supplier PO
  versions. No Client identity or Client economics.
- Generic `user`: no TMS workspace. It is not a fallback Resource role.

## Editable work records and Supplier PO versions

- `project_number` and `job_number` are permanent technical references. The
  Project display name and every operational Project/Job field are edited
  directly in their Overview forms and committed with **Save**.
- A Project has one or more independent Scoops, and each Scoop has one or more
  independent Jobs. Creating another Job always inserts a new immutable
  identity and the next per-Scoop sequence (`_J02`, `_J03`, …); it never edits
  or replaces an existing Job. Each Job owns its Resource assignment,
  Supplier PO and version history, Supplier cost and production status.
- A Supplier rate card stores sets of Source and Target languages and covers
  their configured cross-product. Existing one-pair cards are migrated as
  one-element sets.
- A Client base rate uses the same multi-language model. Empty Source or Target
sets mean Any language; otherwise the rate covers the cross-product of all
selected Source and Target languages. Scoop CAT grids link only to a real
base row matching the Scoop Service, Specialization and direction; Unit is
inherited after selection.
- A newly matching Approved Supplier rate is required before an assigned Job
  can save changed commercial terms unless the Job explicitly uses the manual
  Fixed fee exception.
- Assignment records per-band Supplier CAT quantities and amounts from the
  selected approved rate card. These rows become the issued PO lines.
- PO-facing Job changes create the next immutable PO version and snapshot both
  the Job facts and all price lines.
- Assignment history includes every immutable PO version as a dated commercial
  event. The Supplier PO workspace has one consolidated Version history at the
  bottom; each row shows its PO value and opens a read-only snapshot preview.
- A Resource cannot use `Assignable`, `Proven` or `Preferred` without an email
  address. This is enforced when the Resource profile is saved and again by the
  database; PO issue is only a final defensive check.
- Direct Job assignment uses only the unified readiness definition: lifecycle
  `Active`, Resource status `Assignable` / `Proven` / `Preferred`, and a saved
  email address. Legacy eligibility, classification, assignment approval and
  compliance fields do not trigger an Administrator override.
- A new or reassigned Job Supplier CAT grid inherits quantities from matching
  Scoop CAT bands. The grid has no zero-quantity visibility selector; when it
  is shown, the complete CAT breakdown is visible.
- The Job financial summary calculates Client value from the matching Scoop
  CAT price rows and the Job's editable quantities. When a Scoop has one
  active Job, the Scoop's full current Client price is authoritative so
  manual lines and adjustments are reflected in the Job margin. Once a
  Supplier PO exists, its latest immutable version supplies the displayed
  Supplier cost; changing editable Job terms switches the preview to the
  unsaved recalculated cost.
  Profit and Profit margin are shown together. A margin is not shown when the
  Client and Supplier currencies differ until a currency-conversion model is
  configured.
- Project Supplier expense is the sum of the current active PO total for every
  non-cancelled Job, falling back to that Job's saved Supplier amount when it
  has no PO. Project Profit and Profit margin use this combined expense.

## Navigation and readability

Authenticated operational screens share a top Project/Job quick search. Empty
search shows the eight most recently visited records; text search covers names,
numbers, references, workflow status, service and language direction. Keyboard
shortcut `/` focuses it. Forms and data tables use higher-
contrast labels, larger controls, clearer focus states and stronger totals.

MFA and sensitive-action reauthentication are deferred. Sessions must persist
reliably. Until scheduled Supabase backups are enabled, a manual logical backup
is required before migrations. Direct AI integration is deferred until the
operational modules are tested and working.
