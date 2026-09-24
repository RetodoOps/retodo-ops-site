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
IN_PROGRESS — first reporting implementation drafted; validation pending.

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
- tms/reports.html
- tms/reports.js
- tms/reports.css
- tms/migrations/052_read_only_reports.sql

## TEST RESULTS
Reports JavaScript syntax check PASS. Database and browser validation pending.

## UNRESOLVED / INCOMPLETE
- Reports page/API drafted with Projects/Jobs/Margin, filters, pagination and bounded CSV export.
- Existing company-role read permissions preserved via invoker RPC and table RLS; inactive/external users denied.
- Need database tests and browser fixtures before review.
- Prior mixed-currency arithmetic and bulk partial-write findings remain unresolved outside new report scope.
- Prior assessment is evidence/proposal, not proof of production correctness.

## REQUIRED CONTEXT
NONE — inspect relevant application source and schema as needed.

## NEXT EXACT ACTION
Run isolated database and browser tests; correct calculation/permission/UI defects; checkpoint tests and results.

## DO NOT REDO
- Do not restart context reconciliation.
- Do not claim existing Dashboard/Project arithmetic or bulk writes are fixed.
- Do not reopen user-confirmed signing/PDF/invitation behavior without regression evidence.
