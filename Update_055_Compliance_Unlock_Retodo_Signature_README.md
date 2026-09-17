# Retodo Ops TMS — Update 055

## Purpose

Update 055 makes the existing **Request / Unlock Compliance** action the Retodo-side electronic signature of the Freelancer Framework Agreement. There is no separate **Send Agreement** step.

The Service Provider keeps the existing **Accept and sign** action. That action applies the second and final signature and makes the Agreement effective.

## Locked workflow

1. An authorised internal user unlocks Compliance for a Resource.
2. In the same database transaction, Retodo signs and locks Agreement version 1.1 for that Resource.
3. The Resource sees the exact issued Agreement and selects **Accept and sign**.
4. The accepted snapshot contains both signature records and becomes effective at the time of the Resource's final signature.
5. Compliance submission remains blocked until the Resource has signed that exact Agreement version and SHA-256 hash.

## Agreement version

- Version: `1.1`
- SHA-256: `9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c`
- Retodo signatory: `Demir Atanasov`, Owner
- Retodo signing email: `ops@retodo-ops.com`

The Agreement now expressly states that both parties agree under Article 13(4) of the Bulgarian Electronic Document and Electronic Trust Services Act that their respective TMS electronic signatures have the legal effect of handwritten signatures.

## Database changes

- Adds an immutable Retodo issuance/signature record for each Resource and Agreement version.
- Adds Retodo signature fields to the final accepted Agreement snapshot.
- Adds `resource_compliance_workflow_dispatch_055`, which wraps the existing workflow and signs only on the `request` action.
- Updates the portal Agreement projection, Resource acceptance, internal summary and Compliance submit gate for version 1.1.
- Records both actions in the trusted TMS audit trail.

## PDF changes

The generated signed PDF contains:

- the completed Agreement and provider details;
- the Retodo electronic signature record;
- the Service Provider electronic signature record;
- Agreement version and SHA-256 hash.

## Deployment

1. Run `tms/migrations/051_update_055_compliance_unlock_retodo_signature.sql` once.
2. Run `tms/audits/013_update_055_compliance_unlock_retodo_signature_audit.sql`; every row must be `PASS`.
3. Publish the supplied complete files through GitHub / Netlify.
4. Verify `/build.json` reports build `055`.

Do not repeat earlier migrations or audits. There are no new environment variables.

## Acceptance test

Use a Resource whose Compliance status is `Not requested`:

1. Select **Request Compliance** internally.
2. Confirm the internal Agreement card says `Awaiting Service Provider signature` and shows the Retodo signer and timestamp.
3. Sign in as the Resource and confirm Agreement version 1.1 is available.
4. Select **Accept and sign**.
5. Download the signed PDF from both the Resource and internal views.
6. Confirm both signature records, version 1.1 and the document hash are present.

