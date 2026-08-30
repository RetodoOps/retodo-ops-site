-- RetodoOps TMS — repair missing Client base/CAT rate-card columns.
-- Run after 016_multilanguage_client_rate_cards.sql.

BEGIN;

-- Some installations received the newer Client UI without the structural
-- part of migration 011. Recreate it idempotently without changing Project,
-- Quote, Job, Offer or PO snapshots.
ALTER TABLE public.client_rate_items
    ADD COLUMN IF NOT EXISTS base_rate_id UUID
        REFERENCES public.client_rate_items(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5, 2),
    ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.client_rate_items
    DROP CONSTRAINT IF EXISTS client_rate_items_discount_percent_check;
ALTER TABLE public.client_rate_items
    ADD CONSTRAINT client_rate_items_discount_percent_check
    CHECK (discount_percent IS NULL OR discount_percent BETWEEN 0 AND 100);

CREATE INDEX IF NOT EXISTS client_rate_items_base_rate_idx
    ON public.client_rate_items(base_rate_id);

-- A legacy New words row is the base price. Other legacy CAT rows are linked
-- to the closest matching base and retain their current calculated price.
UPDATE public.client_rate_items
SET cat_band = NULL, discount_percent = NULL
WHERE base_rate_id IS NULL
  AND regexp_replace(lower(COALESCE(cat_band, '')), '[^a-z0-9%]+', '', 'g')
      = 'newwords';

WITH matches AS (
    SELECT child.id AS child_id, base.id AS base_id,
        CASE WHEN base.rate = 0 THEN 0 ELSE round(LEAST(100, GREATEST(0,
            100 - (child.rate / base.rate * 100))), 2) END AS calculated_discount
    FROM public.client_rate_items child
    JOIN LATERAL (
        SELECT candidate.* FROM public.client_rate_items candidate
        WHERE candidate.rate_card_id = child.rate_card_id
          AND candidate.id <> child.id
          AND candidate.base_rate_id IS NULL
          AND candidate.cat_band IS NULL
          AND candidate.source_language IS NOT DISTINCT FROM child.source_language
          AND candidate.target_language IS NOT DISTINCT FROM child.target_language
          AND candidate.service_type = child.service_type
          AND candidate.specialization_id IS NOT DISTINCT FROM child.specialization_id
          AND candidate.unit = child.unit
        ORDER BY candidate.created_at, candidate.id LIMIT 1
    ) base ON TRUE
    WHERE child.base_rate_id IS NULL AND child.cat_band IS NOT NULL
)
UPDATE public.client_rate_items child
SET base_rate_id = matches.base_id,
    discount_percent = matches.calculated_discount
FROM matches
WHERE child.id = matches.child_id;

-- Migration 016 already defines this function. The trigger may be absent on
-- installations that missed migration 011, so recreate it explicitly.
DROP TRIGGER IF EXISTS client_rate_items_prepare_card_row
    ON public.client_rate_items;
CREATE TRIGGER client_rate_items_prepare_card_row
BEFORE INSERT OR UPDATE ON public.client_rate_items
FOR EACH ROW EXECUTE FUNCTION public.prepare_client_rate_card_row();

-- Make sure every existing child inherits the current multi-language context
-- and its rate is recalculated from the stored percentage.
UPDATE public.client_rate_items child
SET source_languages = base.source_languages,
    target_languages = base.target_languages,
    source_language = base.source_language,
    target_language = base.target_language,
    service_type = base.service_type,
    specialization_id = base.specialization_id,
    unit = base.unit,
    minimum_fee = base.minimum_fee,
    rate = round(base.rate * (100 - child.discount_percent) / 100, 4),
    updated_at = NOW()
FROM public.client_rate_items base
WHERE child.base_rate_id = base.id
  AND child.discount_percent IS NOT NULL;

COMMIT;
