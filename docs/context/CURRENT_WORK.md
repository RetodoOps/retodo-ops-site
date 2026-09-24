# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: dev/reports-implementation-20260924
Starting HEAD: d7c3cb5b8dcc948a7820774c7448ae01df2baa49
Latest durable checkpoint: this commit on the active task branch; resolve branch HEAD
Build: 057 (unchanged)
Last updated: 2026-09-24

## CURRENT TASK
Build Reports: Projects, Jobs and Margin.

## STATUS
IN_PROGRESS — scope selected by user; inspecting data model and access rules.

## TASK-SPECIFIC LOCKED RULES
- User selected Projects, Jobs, Margin: read-only filters, CSV export, separate currency totals and unreliable-margin warnings.
- No merge/main push, production deployment, production migration, production data/auth/environment changes.
- Preserve existing permissions; no exchange-rate assumptions or accounting recognition.
- No unrelated context reconciliation or signing-flow changes.
- Checkpoint code and this record together on the active non-main branch.

## COMPLETED
- Verified current main and build 057.
- User explicitly requested Reports implementation and selected the three-report scope.
- Created task branch from current main.
- Inspected prior Reports assessment from existing local assessment branch because current main records proposal as partial and contains no detailed requirements.
- Current main application source matches local assessment checkout; only continuity documents differ.

## CHANGED FILES
- docs/context/CURRENT_WORK.md

## TEST RESULTS
No implementation tests yet.

## UNRESOLVED / INCOMPLETE
- Reports page/API not yet implemented.
- Need confirm schema, financial access boundaries and calculation behavior.
- Prior mixed-currency arithmetic and bulk partial-write findings remain unresolved outside new report scope.
- Prior assessment is evidence/proposal, not proof of production correctness.

## REQUIRED CONTEXT
NONE — inspect relevant application source and schema as needed.

## NEXT EXACT ACTION
Prepare isolated current-main working copy; implement read-only reporting with server-enforced permissions, currency-safe calculations and tests.

## DO NOT REDO
- Do not restart context reconciliation.
- Do not claim existing Dashboard/Project arithmetic or bulk writes are fixed.
- Do not reopen user-confirmed signing/PDF/invitation behavior without regression evidence.
