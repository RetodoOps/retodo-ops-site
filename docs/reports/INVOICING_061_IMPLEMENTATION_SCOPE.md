# Update 061 — implemented scope

2026-09-27. Baseline: main 0c704f05e762f588cafcb3cd7e53ac44534cba95, build 060.
ZIP-only delivery. The user uploads complete files and commits to main. Nothing is pushed or deployed by the assistant.

## User decisions implemented

- One client invoice can include selected approved Scoops across multiple Projects.
- Eligibility is the individual active, approved Scoop, with a non-cancelled parent Project. This supersedes the earlier Project-only approval assumption and pending grouping question.
- Queue selection is manual. The client PO is the Project's po_number, not the supplier purchase order used for cost reporting.
- Due date uses clients.default_payment_days, even if a billing entity has a different historical override.
- Draft rows can be added, removed or corrected. A changed Scoop amount requires a reason and retains its source value. Further Scoops can be added by PO after a draft is saved.
- Reports display individual Scoops and convert supported original currencies to EUR using dated ECB reference rates. Unknown costs and missing rates are not invented.

## Delivered application behavior

Reports: one row per Scoop in Projects/Margin; Job-cost details identify missing costs; provisional profit is separate from final profit/margin. Known costs use issued PO commitments or labelled saved estimates. Explicit zero rates are valid zero costs. Dashboard's missing-as-zero behavior is unchanged; it explains the screenshot discrepancy. Project Scoops do not duplicate revenue across Jobs.

Reports exports default to a native XLSX workbook with numeric cells, Unicode text, readable headers, column widths, frozen headers, filters, summaries and FX metadata. Raw CSV remains optional and can still be interpreted differently by local Excel settings. Paging offers 25, 50, 100 or 250 rows; default 50. Full-result export remains capped at 10,000 matching rows.

Client invoicing reuses client_invoices/client_invoice_lines/payments. It adds guarded RPCs, a queue and invoice list, editable drafts, source snapshots, unique Scoop reservations, revision checks, invoice settings, administrative issue, print/PDF, received-payment recording and event history. Draft cancellation releases reservations. Issued facts are immutable, including line edits through future database paths. One invoice has one Client, billing entity and invoice currency. EUR is the initial currency; source currency conversions retain their rate/date. No email is sent.

Numbers retain the existing ten-digit format. The administrator configures the next number; a draft can propose another number. Official issue checks uniqueness under a settings-row lock and advances the next number from the number actually issued. Saving drafts does not consume official numbers.

Financial status is updated for a Project only when every active Scoop is covered by an issued invoice. A partly billed Project is not falsely marked fully Invoiced. Payments update invoice balances and, where the whole Project is billed, Project financial status. Payment recording is an administrative record of an existing receipt, not a transfer; it accepts the invoice currency and prevents duplicates/overpayment. It does not calculate bank FX differences.

## Permissions and safeguards

- Active admin/PM/client-relations users prepare drafts; QA reads/prints only.
- Administrator only: issuer/number settings, official issue, received payments.
- Resources and anonymous callers cannot use company invoice RPCs.
- Direct ordinary-user client finance mutation grants are revoked; guarded RPCs are the write path. Issued header/line facts also have immutability triggers.
- Source/client terms and eligibility are revalidated at issue. Price/currency/PO changes require draft review/resave. Source locks, unique reservations, official-number uniqueness and optimistic draft revisions prevent silent overwrite or duplicate allocation.
- Legacy Project-only invoice rows conservatively block that Project's Scoops from new billing until reviewed. They are not automatically migrated or deleted.
- ECB rates are fetched server-side from a fixed official endpoint. Authenticated company users can request refresh; only the server can store rates. No service credential is sent to the browser.

## Configuration and boundaries

Before official issuance, configure issuer legal/address/registration/bank details, next number, client payment terms, active legal billing entity and tax treatment. The application does not invent legal details or decide a VAT rate.

Foreign conversion needs the deployed Netlify function and its existing server-only Supabase environment configuration. The most recent saved ECB snapshot within seven days is used, including weekends. If no valid rate exists for a currency, its conversion remains unavailable. No 1:1 fallback is used. EUR requires no external rate. These are dated reference conversions, not actual bank settlement rates or historical transaction-date rates.

This release completes client invoicing. Supplier invoicing, credit/annulment/replacement documents, automated delivery/reminders, separate Invoice Reports and accounting exports remain future work. The supplier menu explains that scope. Issued edits are not enabled; corrections currently apply to Drafts. The saved invoice list shows the most recent 250 for the selected client.

Earlier supplier agreement decisions remain unchanged: 15th/last working day cycle and 60 calendar days from cycle date; a holiday calendar/cutoff still needs definition before implementing that module.

## Verification

See UPDATE_061_INSTALL_AND_TEST.md and CURRENT_WORK.md for exact executed checks. Local tests are not production acceptance. Missing historical migrations 037/040 are not reconstructed: compatibility testing replays the available schema through 038 with an explicit stub for the unrelated missing 037 audit writer, then 053/054/055.
