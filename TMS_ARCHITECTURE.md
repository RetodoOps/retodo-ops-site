# Retodo Ops TMS — Approved Operational Architecture

This document records the workflow decisions approved during the module review.
The database and interface must preserve these distinctions rather than
collapsing commercial, production and financial states into one status.

## Core record flow

Inquiry → Quote → Client confirmation → Project → Jobs → Client invoice → Payment

- A Quote may contain several target languages.
- Acceptance creates one linked Project per target language.
- A confirmed client PO/email assignment may create a Project without a Quote.
- A Project may contain several sequential or parallel Jobs.

## Numbering and names

- Project display name: `YYMMDD_CLIENTCODE_TARGET_CLIENTREF`.
- Missing client reference uses `NOREF`.
- Duplicate names receive `_02`, `_03`, and so on.
- Example: `260828_RWS_SV_1GX12151`.
- Project display names are immutable after creation. If a Client reference is
  supplied later, a Project originally named with `NOREF` keeps that name,
  folder path and external links. The later reference is stored separately,
  remains visible/searchable and records its first receipt time and updater.
- Official Bulgarian invoice numbers are ten digits and are assigned at issue,
  not while the invoice is still a draft.

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

### Job and Job Offer

The production Job and the invitation to a candidate are separate records.

- Job: Unassigned → In Progress → Delivered → Revision Required → Approved
- Job outcome: Cancelled
- Job Offer: Draft → Sent → Viewed → Accepted
- Job Offer outcomes: Declined, Expired, Withdrawn

Only one active candidate offer (Draft, Sent or Viewed) may exist for a Job at
a time. Accepting an offer assigns the Resource, moves the Job to In Progress,
copies the agreed commercial snapshot to the Job and creates a Draft Supplier
PO. Declined, expired and withdrawn offers remain in the Job history.

### Financial

Not Ready → Ready to Invoice → Invoiced → Partially Paid → Paid

Additional states: Overdue, Disputed, Cancelled, Credited.

The Project tab is named **Financials**. A Project may use either a single
manual/fixed Client price or detailed financial lines. Once financial lines
exist, their sum is authoritative and the total Client price is calculated
automatically.

For CAT work, the operator may load an eligible Account/Client price list or a
blank zero-price grid. The grid always starts with all standard rows — New
words, 50–74%, 75–84%, 85–94%, 95–99%, 100% and Repetitions — and quantity 0.
Individual rows may be removed when they do not apply. A price-list line keeps
the exact Client rate-item link plus a Project snapshot, so a later price-list
change does not rewrite historical Project pricing.

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

Classification:

- A — Preferred
- B — Proven / previously used
- C — Approved / no recorded work
- D — Not assessed
- Hold — Inactive
- Hold — Unavailable
- Hold — Terms not accepted
- Do not use

Resource profile sections include identity/contact, language pairs, services,
specializations, rates and CAT bands, education/CV, tools, availability,
quality/restrictions, compliance, project history, LinkedIn/outreach, invoicing
details and audit history.

The original database is imported in full. Imported Resources remain
unapproved for assignment until reviewed. Source and target language filters
are independent and may be combined with service, specialization,
classification, eligibility and availability. Raw legacy notes are preserved
in an Administrator-only archive; operational users see only a concise current
restriction/assignment instruction.

Quality uses an internal 1–5 rating plus written evidence.

## Freelancer portal

- Invitation-only, single-use link valid for 14 days.
- Portal account activates automatically after registration.
- Assignment eligibility requires manual approval.
- Rate changes remain pending until approved.
- Initial release includes profile management, availability, job offers,
  accept/decline, project files, delivery, PO acknowledgement, revisions,
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

Creating or changing a Job assignment checks Resource approval,
classification and compliance. Only the Administrator may acknowledge and
override a failed eligibility check, with a mandatory reason. Active Job
amounts roll up automatically to Project expense and margin.

## Rates, CAT analysis and POs

Supported pricing units: source words, target words, hours, pages, minutes and
fixed fee. Each supplier rate card contains one base price. Optional CAT rows
store a discount percentage against that base; the TMS calculates and retains
the derived repetition, context-match, exact-match and fuzzy-match prices.
Validity dates are not used in the operational interface: approval status and
commercial version history control whether a rate may be selected.

Client rates load from Client/Account rate cards. Supplier expenses load only
from an approved base Resource price-list row matching the Job's language
pair, service, unit and specialization. The selected rate-row ID remains linked
to the Offer and Job for provenance, while the agreed rate, currency, quantity
and amount are retained as immutable commercial snapshots. Fixed/manual Client
pricing remains available with an override reason; a Job Offer cannot use a
free-text supplier rate. Supplier PO production lines retain the Resource-rate
reference and CAT band/discount provenance; manual and adjustment lines remain
explicitly distinguishable.

Supplier POs are sent through portal and email. Work may begin before portal
acknowledgement. Draft POs are editable; issued revisions are versioned.
Discounts, credits, surcharges and minimum-fee adjustments are supported.
Supplier PO numbers use `PO-YYYY-NNNN`. Only the Administrator may issue or
revise a PO. Client and Account identity remain hidden from the Resource by
default; disclosure is an explicit Administrator action.

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

Gmail remains the mailbox for `ops@retodo-ops.com`. The TMS creates reviewable
Gmail drafts initially; only invitations and routine reminders may later send
automatically. Incoming emails are linked manually at first.

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
- Client Relations/Operations (Eli): full financial visibility; may manage
  Clients, Accounts, Quotes, Projects, Jobs, assignments, email and document
  drafts.
- Only Administrator may issue/annul official invoices, approve supplier
  invoices/payments/rates, override compliance, apply Do not use or manage
  users/security.
- Freelancer: own profile, offers, assigned Jobs, files, POs, invoices and
  payments only.

MFA and sensitive-action reauthentication are deferred. Sessions must persist
reliably. Backups run daily. Direct AI integration is deferred until the
operational modules are tested and working.
