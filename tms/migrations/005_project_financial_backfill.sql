-- RetodoOps TMS — Backfill calculated Project financial fields
-- Run after 004_jobs_and_supplier_pos.sql.

BEGIN;

-- Legacy Projects may retain an old scoop_margin value because the calculation
-- trigger only runs when price or expense changes. Touching both columns makes
-- the existing workflow trigger recompute margin_amount and scoop_margin using
-- the approved formula. No commercial source values are changed.
UPDATE public.projects
SET price = COALESCE(price, 0),
    expense = COALESCE(expense, 0);

COMMIT;
