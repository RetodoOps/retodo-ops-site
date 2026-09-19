# Retodo Ops TMS — Current State

**Context snapshot:** 2026-09-19  
**Confidence note:** Based on prior session reports and user confirmations. Where production state was not directly re-verified in this context-building session, it is labeled accordingly.

---

## 1. Product baseline

Reported/established:

- TMS hierarchy: Client → Account → Project → Scoop → Job → Resource/PO → Financials.
- P0 architecture baseline was reported completed.
- Account price cards and Resource rate cards exist conceptually/through implementation iterations.
- Project/Scoop/Job naming and breadcrumbs have been iterated.
- PO versioning is an established core feature.
- Resource onboarding/invitation has been substantially implemented.
- Compliance/Agreement work is the major current workstream.
- Cloudflare R2 is the accepted file-storage direction.
- Reports remains incomplete.

---

## 2. Latest known update progression

From the latest consolidated TMS4 state available on 2026-09-18:

- Update 044: static/test work reported; production history needs reconciliation.
- Update 045: partial.
- Updates 048–049: reported deployed.
- Update 050: deployed but frontend result rejected because of deadline/V3 issues and missing Resource in Dashboard.
- Update 051: prepared; implementation/deployment not confirmed in latest state.
- Update 052: reported deployed; `Cancelled` flow PASS.
- Updates 053–055: prepared but not implemented/deployed as of the latest available handover.
- Production migration/audit/build status for the most recent prepared updates remained unconfirmed.

This context pack does not upgrade any of those items to `VERIFIED`.

---

## 3. Resource invitation

Previously verified/reported:

- Update 042 / migration 041 enabled invitation → password → Resource dashboard.
- Password activation/direct Resource dashboard was user-confirmed.

Current delivery issue:

- invitation to `[redacted Resource address at beconnected.no]` was reported not received;
- only test email behavior had been observed;
- provider/delivery-log verification remained missing.

Therefore:
- invitation mechanics may work;
- real production delivery remains an open issue.

---

## 4. Compliance

Locked model is documented in the decision register.

Current work has covered:

- education evidence;
- professional-since dates;
- dynamic experience;
- qualification logic;
- tests;
- agreement/signing;
- resource/admin views.

Latest UI still requires a holistic cleanup of the Resource profile/Tests & Qualifications/Compliance presentation.

---

## 5. Agreement/PDF

Latest known blocker before the current UI-focused work:

- both Agreement PDFs were reported blank/identical;
- real two-sided signing/PDF validation was not complete;
- Update 054/055 work was prepared in response but latest deploy status was not confirmed.

Treat final PDF generation as **not production-verified** until:
- populated first-signature PDF is confirmed;
- Resource final signature is confirmed;
- final PDF differs appropriately and contains data/signatures;
- admin and Resource download paths both work.

---

## 6. PO / Dashboard

Known recent regression:

- Update 050 introduced/revealed deadline/V3 issues;
- Resource was missing from Dashboard;
- follow-up Update 051 was prepared.

Cancelled flow:
- Update 052 reported deployed and PASS.

Before new financial/PO work, retest:
- active PO version;
- supplier cost;
- dashboard Resource;
- deadline;
- V3 history;
- cancelled reassignment.

---

## 7. Files / R2

Strategic storage decision is locked to Cloudflare R2.

However, full end-to-end current production verification of:
- upload;
- Resource download;
- Completed Job access;
- deletion;
- duplicate Compliance document deletion;
- issues/delivery file lifecycle

should be treated as incomplete unless the latest working session has since verified it.

---

## 8. Reports

Reports menu exists/planned, but report submodules are not considered built/complete.

Status: `UNRESOLVED`.

---

## 9. Blind CV

Requirements are known, but completion/production verification is not established in the latest handover.

Status: `UNRESOLVED`.

---

## 10. Current UI task

Latest user feedback requires Resource profile UI cleanup.

Outstanding visual defects/class of defects:

- text above `Test Test` too small;
- `Tests & Qualifications` alignment;
- `Save changes` misaligned relative to `+ Assign Test`;
- `Compliance phase` alignment differs from fields;
- `Account Qualifications from approved jobs` heading alignment;
- question/help icons placed below rather than inline with heading;
- explanatory text overflow/outside bubbles;
- inconsistent button sizes/colors/types;
- mismatched sizes of Master's degree and Diploma upload blocks;
- field backgrounds need stronger/darker distinction;
- overall page should be reviewed by canonical aesthetic/readability rules rather than only patching individually listed defects.

This is the highest-confidence immediate UI requirement.

---

## 11. Repository identity warning

The GitHub connector available during context-pack creation exposed:

- `RetodoOps/retodo-ops-site`
- `RetodoOps/Retodo-App`

Inspection of `RetodoOps/Retodo-App` showed HR/Luma People routes and dependencies. Therefore it must **not** be assumed to be the current TMS repository.

Before Codex work:
- open the actual local TMS working copy;
- confirm remote URL/repository;
- place this context pack in that repository root;
- only then start TMS modifications.

---

## 12. Deployment responsibility

Established current workflow:

- user controls GitHub upload/push and Netlify deployment;
- SQL migrations are manually executed/provided separately;
- agents prepare/test/package changes unless explicitly authorized otherwise.
