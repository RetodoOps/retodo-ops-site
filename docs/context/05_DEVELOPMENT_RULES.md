# Retodo Ops TMS — Development Rules

**Version:** 1.0  
**Date:** 2026-09-19

---

## 1. Change workflow

For each task:

1. Read context and latest handover.
2. Define scope.
3. Identify affected locked decisions.
4. Inspect current code/schema.
5. Implement on a dedicated branch/worktree where possible.
6. Run static/build/unit/integration tests available.
7. Run targeted business-flow checks.
8. Produce a complete implementation report.
9. Update context files when the user approves/implementation state changes.
10. Package complete repository files and separate SQL migrations according to the user's established workflow.

---

## 2. No silent architecture changes

Do not:
- rename core entities;
- add new statuses;
- change status transition rules;
- alter financial ownership;
- change signing order;
- weaken permissions;
- switch storage provider;
- change invitation semantics;
- change PO acceptance/versioning

as an incidental fix.

Such changes require an explicit new decision.

---

## 3. Git / parallel work

Preferred:

```text
main
 ├─ codex/resource-profile-ui
 ├─ codex/compliance-pdf-fix
 ├─ codex/invitation-delivery
 └─ codex/reports
```

Rules:

- one workstream per branch;
- no two agents editing the same migration or core workflow concurrently;
- rebase/merge latest accepted dependency before final review;
- do not auto-push/merge unless explicitly authorized;
- document branch base commit when practical.

---

## 4. Packaging rule

The user has explicitly requested:

- full files rather than snippets;
- a complete GitHub ZIP for repository changes;
- separate `.sql` migration files;
- no need to manually replace many individual files from conversational instructions.

When only a few repository files change, the ZIP should contain only the necessary replacement/addition paths while preserving their directory structure — not an unnecessary full-repository dump.

This combines the established preference: complete changed files, but only the files needed for the update.

---

## 5. Migrations

- forward-only;
- sequentially named according to current repository convention;
- one clear purpose per migration where practical;
- safe to run once;
- avoid destructive data loss;
- use transactions where appropriate;
- preserve existing RLS unless intentionally changed;
- include rollback/recovery note in handover even if production rollback would be forward-fix rather than down migration.

For each migration record:
- filename;
- prerequisite migration;
- tables/functions/policies touched;
- data backfill;
- expected row impact;
- verification query.

---

## 6. RLS/security

Test:
- admin allowed;
- correct Resource allowed;
- other Resource denied;
- unauthenticated denied;
- client identity hidden where required;
- signed/presigned file links expire appropriately;
- service-role key never appears client-side.

Do not “fix” a permissions bug by moving privileged keys into browser code.

---

## 7. Email reliability

For email-triggered flows:

- persist intended recipient;
- persist/record send attempt where architecture supports it;
- handle provider error explicitly;
- allow retry without duplicating business state;
- do not report successful delivery based only on a successful HTTP request to an intermediate function;
- verify provider logs/delivery when diagnosing non-receipt.

Known high-priority example: Resource access invitation delivery.

---

## 8. PDF/document testing

A PDF feature is not verified merely because a PDF file downloads.

Test:
- correct Resource data populated;
- agreement fields visible;
- first signature rendered;
- second/final signature rendered;
- versions are not blank/identical when they should differ;
- filename/version correct;
- admin and Resource receive authorized artifact;
- old document versions are handled as designed.

---

## 9. Financial tests

At minimum after financial/PO changes test:

- client value unchanged by supplier-only PO revision;
- supplier cost follows active PO;
- profit updates;
- margin updates;
- older PO version no longer drives current supplier cost;
- cancel/reassign does not double-count;
- Project totals equal underlying Scoops/Jobs;
- flat-fee paths work;
- zero client value does not break margin calculation.

Historical regression example:
- Client: 31.00 EUR
- Supplier: 10.68 EUR
- Profit: 20.32 EUR
- Margin: 65.55%

Use only as a regression fixture, not as business data.

---

## 10. UI test gate

For any frontend update:

- run lint/type/build available in repo;
- inspect the entire changed page visually;
- check spacing/alignment/containment;
- check at least one narrower width;
- verify primary workflows with real-looking content lengths;
- verify long helper text;
- verify empty states and validation states.

Do not mark “done” if the user-visible page remains obviously inconsistent.

---

## 11. Environment/config

Never overwrite working environment configuration casually.

If new variables are required:
- add placeholders to `.env.example`;
- document variable name/purpose;
- never include live values;
- state whether Netlify/Supabase/R2/email configuration is required manually.

Preserve `config.js` where present unless explicitly instructed.

---

## 12. Implementation status vocabulary

Use precise deployment wording:

- `PREPARED` — files generated.
- `LOCAL TEST PASS` — local/static tests passed.
- `MIGRATION PENDING` — SQL not yet executed.
- `MIGRATION EXECUTED` — user confirmed production migration.
- `DEPLOY PENDING` — not yet published.
- `DEPLOYED` — user confirmed production deploy.
- `PRODUCTION VERIFIED` — actual browser/API flow tested successfully.

Never collapse these into a vague “done”.

---

## 13. Required handover template

```text
Update:
Date:
Branch/base:
Objective:

LOCKED decisions implemented:
Files changed:
Migration(s):
Env/config:
Tests:
Production migration:
Production deploy:
Production browser verification:

Known defects:
Open issues:
Next recommended task:
Context docs updated:
```
