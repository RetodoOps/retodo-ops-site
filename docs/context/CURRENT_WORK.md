# CURRENT WORK

Repository: RetodoOps/retodo-ops-site
Base: main
Active task branch: dev/reports-review-20260924
Starting HEAD: adb01a2991d22684289bd943a879470b161099f0 (post-merge continuity follow-through)
Latest durable checkpoint: review merged to main at adb01a2991d22684289bd943a879470b161099f0; this follow-through checkpoint on dev/reports-review-20260924, resolve branch HEAD.
Build: 058 — unchanged
Last updated: 2026-09-24

## CURRENT TASK
Reports review completed and merged; awaiting implementation instruction for the proposed update.

## STATUS
REVIEW MERGED / UPDATE 059 PROPOSED — PR #26 merged by user; implementation has not started.

## TASK-SPECIFIC LOCKED RULES
- Inspect current Reports source, dependencies, schema and focused behavior; no broad context reconciliation.
- Preserve Projects/Jobs/Scoop-level Margin scope, currency separation, RLS and least privilege.
- No production deployment, migration, data, authentication or configuration changes; no main merge/push.
- Record verified defects separately from unverified live state and proposed enhancements.
- Keep existing local work intact; use this isolated task branch.
- User explicitly authorized publishing CURRENT_WORK.md and REPORTS_REVIEW_UPDATE_059_PROPOSAL.md to RetodoOps/retodo-ops-site on dev/reports-review-20260924.

## COMPLETED
- Fetched current main and read its CURRENT_WORK.md; PRs 24 and 25 merged.
- Created isolated worktree from main 5f84356; previous local branch preserved.
- Inspected Reports UI/RPC and relevant schema/workflows; migration 052 remains unverified in production.
- Completed focused reproductions and wrote the prioritized Update 059 proposal with concrete files, acceptance gates and scope boundaries.
- Published both approved documents at ada5914.
- User reported merge/push; verified PR #26 merge on remote main adb01a2, with ada5914 in its ancestry and identical file tree. Build remains 058.
- Fast-forwarded the local review branch to the merged baseline and recorded post-merge continuation state.

## CHANGED FILES
This post-merge checkpoint:
- docs/context/CURRENT_WORK.md

Already merged via PR #26:
- docs/context/CURRENT_WORK.md
- docs/reports/REPORTS_REVIEW_UPDATE_059_PROPOSAL.md

## TEST RESULTS
Five isolated reproductions confirmed: Project number search omission, Projects language/resource search omission, estimate/warning-count mismatch, and numeric losses exported as text. Source checks also found stale Job status options, omitted Margin export language pair and limited financial sorting. Live build GET returned 058; public read-only RPC probe returned PGRST202. Authenticated production behavior remains unverified. Earlier recorded fixture tests were not rerun unnecessarily.

## UNRESOLVED / INCOMPLETE
- Update 059 remains proposed, not implemented.
- Authenticated backend/migration/schema verification remains outstanding; public probe alone does not prove migration absent.
- Publication blockage is resolved; use the authenticated GitHub connector for task-branch checkpoints because command-line Git lacks write credentials.
- Prior Dashboard mixed-currency and bulk partial-write findings remain outside this review's implementation scope.

## REQUIRED CONTEXT
NONE

## NEXT EXACT ACTION
Await the user's implementation instruction for the proposed update. Then refresh main, check other profile work and reserve the next build/migration numbers; start with actual-schema staging and authenticated release verification.

## DO NOT REDO
- No context reconciliation, signing/PDF/invitation changes or wholesale Reports rewrite.
- Do not mark unverified live behavior as PASS or FAIL from fixture evidence.

## PRODUCTION STATE
Repository main contains the merged review at adb01a2 and build 058. The earlier live build check returned 058; live state was not rechecked for this documentation-only confirmation. No production writes performed. Earlier anonymous RPC lookup returned PGRST202; migration/schema availability for authenticated users is not yet verified.
