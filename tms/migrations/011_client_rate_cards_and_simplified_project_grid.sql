-- RetodoOps TMS — Client base-rate cards, CAT discounts and simplified Project grid
-- Run after 010_unified_resource_status_and_tests.sql.

BEGIN;

-- Client and Supplier pricing use the same structure: one base row plus linked
-- CAT rows whose rates are calculated from discount percentages.
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
-- Normalize existing New words rows as bases, then connect any existing CAT
-- rows to the matching base without changing their historical prices.
UPDATE public.client_rate_items
SET cat_band = NULL, discount_percent = NULL
WHERE base_rate_id IS NULL
  AND regexp_replace(lower(COALESCE(cat_band, '')), '[^a-z0-9%]+', '', 'g')
      = 'newwords';

WITH matches AS (
    SELECT child.id AS child_id, base.id AS base_id,
        CASE
            WHEN base.rate = 0 THEN 0
            ELSE round(LEAST(100, GREATEST(0,
                100 - (child.rate / base.rate * 100))), 2)
        END AS calculated_discount
    FROM public.client_rate_items child
    JOIN LATERAL (
        SELECT candidate.*
        FROM public.client_rate_items candidate
        WHERE candidate.rate_card_id = child.rate_card_id
          AND candidate.id <> child.id
          AND candidate.base_rate_id IS NULL
          AND candidate.cat_band IS NULL
          AND candidate.source_language IS NOT DISTINCT FROM child.source_language
          AND candidate.target_language IS NOT DISTINCT FROM child.target_language
          AND candidate.service_type = child.service_type
          AND candidate.specialization_id IS NOT DISTINCT FROM child.specialization_id
          AND candidate.unit = child.unit
        ORDER BY candidate.created_at, candidate.id
        LIMIT 1
    ) base ON TRUE
    WHERE child.base_rate_id IS NULL AND child.cat_band IS NOT NULL
)
UPDATE public.client_rate_items child
SET base_rate_id = matches.base_id,
    discount_percent = matches.calculated_discount
FROM matches
WHERE child.id = matches.child_id;

CREATE OR REPLACE FUNCTION public.prepare_client_rate_card_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    -- Validity dates are deprecated; Active/Inactive controls availability.
    NEW.valid_from := NULL;
    NEW.valid_to := NULL;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_rate_cards_prepare_header
    ON public.client_rate_cards;
CREATE TRIGGER client_rate_cards_prepare_header
BEFORE INSERT OR UPDATE ON public.client_rate_cards
FOR EACH ROW EXECUTE FUNCTION public.prepare_client_rate_card_header();

UPDATE public.client_rate_cards
SET valid_from = NULL, valid_to = NULL;

CREATE OR REPLACE FUNCTION public.prepare_client_rate_card_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_base public.client_rate_items%ROWTYPE;
BEGIN
    IF NEW.base_rate_id IS NOT NULL THEN
        SELECT * INTO v_base
        FROM public.client_rate_items
        WHERE id = NEW.base_rate_id;
        IF NOT FOUND OR v_base.base_rate_id IS NOT NULL THEN
            RAISE EXCEPTION 'CAT rate must reference a valid base Client rate';
        END IF;
        IF NEW.rate_card_id <> v_base.rate_card_id THEN
            RAISE EXCEPTION 'CAT rate and base rate must belong to the same Client rate card';
        END IF;
        IF NULLIF(btrim(NEW.cat_band), '') IS NULL OR NEW.discount_percent IS NULL THEN
            RAISE EXCEPTION 'CAT band and discount percentage are required';
        END IF;

        NEW.source_language := v_base.source_language;
        NEW.target_language := v_base.target_language;
        NEW.service_type := v_base.service_type;
        NEW.specialization_id := v_base.specialization_id;
        NEW.unit := v_base.unit;
        NEW.minimum_fee := v_base.minimum_fee;
        NEW.rate := round(v_base.rate * (100 - NEW.discount_percent) / 100, 4);
    ELSE
        NEW.cat_band := NULL;
        NEW.discount_percent := NULL;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_rate_items_prepare_card_row
    ON public.client_rate_items;
CREATE TRIGGER client_rate_items_prepare_card_row
BEFORE INSERT OR UPDATE ON public.client_rate_items
FOR EACH ROW EXECUTE FUNCTION public.prepare_client_rate_card_row();

CREATE OR REPLACE FUNCTION public.sync_client_rate_card_rows()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.base_rate_id IS NULL THEN
        UPDATE public.client_rate_items child
        SET source_language = NEW.source_language,
            target_language = NEW.target_language,
            service_type = NEW.service_type,
            specialization_id = NEW.specialization_id,
            unit = NEW.unit,
            minimum_fee = NEW.minimum_fee,
            rate = round(NEW.rate * (100 - child.discount_percent) / 100, 4),
            updated_at = NOW()
        WHERE child.base_rate_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_rate_items_sync_card_rows
    ON public.client_rate_items;
CREATE TRIGGER client_rate_items_sync_card_rows
AFTER UPDATE OF source_language, target_language, service_type,
    specialization_id, unit, rate, minimum_fee
ON public.client_rate_items
FOR EACH ROW EXECUTE FUNCTION public.sync_client_rate_card_rows();

CREATE OR REPLACE FUNCTION public.save_client_rate_card_item(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base_id UUID := NULLIF(p_payload->>'base_rate_id', '')::UUID;
    v_rate_card_id UUID := NULLIF(p_payload->>'rate_card_id', '')::UUID;
    v_source TEXT := NULLIF(btrim(p_payload->>'source_language'), '');
    v_target TEXT := NULLIF(btrim(p_payload->>'target_language'), '');
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
    v_specialization_id UUID := NULLIF(p_payload->>'specialization_id', '')::UUID;
    v_unit TEXT := NULLIF(btrim(p_payload->>'unit'), '');
    v_base_rate NUMERIC := NULLIF(p_payload->>'base_rate', '')::NUMERIC;
    v_minimum_fee NUMERIC := NULLIF(p_payload->>'minimum_fee', '')::NUMERIC;
    v_notes TEXT := NULLIF(btrim(p_payload->>'notes'), '');
    v_discount JSONB;
    v_band TEXT;
    v_percent NUMERIC;
    v_child_id UUID;
    v_seen_bands TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_rate_card_id IS NULL OR v_service IS NULL OR v_unit IS NULL
       OR v_base_rate IS NULL THEN
        RAISE EXCEPTION 'Rate card, service, unit and base price are required';
    END IF;
    IF v_base_rate < 0 OR COALESCE(v_minimum_fee, 0) < 0 THEN
        RAISE EXCEPTION 'Rates and minimum fees cannot be negative';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.client_rate_cards card
        WHERE card.id = v_rate_card_id AND card.active
    ) THEN
        RAISE EXCEPTION 'Select an active Client rate card';
    END IF;

    IF v_base_id IS NULL THEN
        INSERT INTO public.client_rate_items (
            rate_card_id, source_language, target_language, service_type,
            specialization_id, unit, rate, minimum_fee, notes,
            cat_band, discount_percent, active
        ) VALUES (
            v_rate_card_id, v_source, v_target, v_service,
            v_specialization_id, v_unit, v_base_rate, v_minimum_fee, v_notes,
            NULL, NULL, TRUE
        ) RETURNING id INTO v_base_id;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM public.client_rate_items base
            WHERE base.id = v_base_id
              AND base.rate_card_id = v_rate_card_id
              AND base.base_rate_id IS NULL
        ) THEN
            RAISE EXCEPTION 'Client base rate not found in the selected rate card';
        END IF;
        UPDATE public.client_rate_items
        SET source_language = v_source,
            target_language = v_target,
            service_type = v_service,
            specialization_id = v_specialization_id,
            unit = v_unit,
            rate = v_base_rate,
            minimum_fee = v_minimum_fee,
            notes = v_notes,
            active = TRUE,
            updated_at = NOW()
        WHERE id = v_base_id;

        UPDATE public.client_rate_items
        SET active = FALSE, updated_at = NOW()
        WHERE base_rate_id = v_base_id;
    END IF;

    FOR v_discount IN
        SELECT value FROM jsonb_array_elements(
            COALESCE(p_payload->'cat_discounts', '[]'::JSONB)
        )
    LOOP
        v_band := NULLIF(btrim(v_discount->>'cat_band'), '');
        v_percent := NULLIF(v_discount->>'discount_percent', '')::NUMERIC;
        IF v_band IS NULL OR v_percent IS NULL OR v_percent < 0 OR v_percent > 100 THEN
            RAISE EXCEPTION 'Each CAT band requires a discount between 0 and 100 percent';
        END IF;
        IF lower(v_band) = ANY(v_seen_bands) THEN
            RAISE EXCEPTION 'Duplicate CAT band: %', v_band;
        END IF;
        v_seen_bands := array_append(v_seen_bands, lower(v_band));

        SELECT child.id INTO v_child_id
        FROM public.client_rate_items child
        WHERE child.base_rate_id = v_base_id
          AND lower(child.cat_band) = lower(v_band)
        LIMIT 1;

        IF v_child_id IS NULL THEN
            INSERT INTO public.client_rate_items (
                rate_card_id, base_rate_id, source_language, target_language,
                service_type, specialization_id, unit, cat_band,
                discount_percent, rate, minimum_fee, notes, active
            ) VALUES (
                v_rate_card_id, v_base_id, v_source, v_target,
                v_service, v_specialization_id, v_unit, v_band,
                v_percent, v_base_rate, v_minimum_fee, v_notes, TRUE
            );
        ELSE
            UPDATE public.client_rate_items
            SET discount_percent = v_percent, active = TRUE, updated_at = NOW()
            WHERE id = v_child_id;
        END IF;
        v_child_id := NULL;
    END LOOP;

    RETURN v_base_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_client_rate_card_item(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_client_rate_card_item(JSONB)
    TO authenticated;

-- Linked Project rows retain their stored price snapshot. New links must point
-- to an active rate-card row and match its commercial definition.
CREATE OR REPLACE FUNCTION public.validate_scope_client_rate_link()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_rate public.client_rate_items%ROWTYPE;
    v_card public.client_rate_cards%ROWTYPE;
BEGIN
    IF NEW.client_rate_item_id IS NULL THEN RETURN NEW; END IF;

    SELECT * INTO v_project FROM public.projects WHERE id = NEW.project_id;
    SELECT * INTO v_rate FROM public.client_rate_items
    WHERE id = NEW.client_rate_item_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Client rate-card row not found'; END IF;

    SELECT * INTO v_card FROM public.client_rate_cards
    WHERE id = v_rate.rate_card_id;
    IF NOT FOUND OR v_card.client_id <> v_project.client_id THEN
        RAISE EXCEPTION 'Client rate-card row does not belong to the Project Client';
    END IF;
    IF v_card.account_id IS NOT NULL
       AND v_card.account_id IS DISTINCT FROM v_project.account_id THEN
        RAISE EXCEPTION 'Account rate card does not belong to the Project Account';
    END IF;
    IF TG_OP = 'INSERT' OR NEW.client_rate_item_id IS DISTINCT FROM OLD.client_rate_item_id THEN
        IF NOT v_rate.active OR NOT v_card.active THEN
            RAISE EXCEPTION 'The selected Client rate-card row is inactive';
        END IF;
        IF NEW.service_type IS DISTINCT FROM v_rate.service_type
           OR NEW.price_unit IS DISTINCT FROM v_rate.unit
           OR (v_rate.specialization_id IS NOT NULL
               AND NEW.specialization_id IS DISTINCT FROM v_rate.specialization_id)
           OR NEW.unit_price IS DISTINCT FROM v_rate.rate
           OR NOT (
               regexp_replace(lower(COALESCE(NEW.cat_band, '')), '[^a-z0-9%]+', '', 'g')
                 = regexp_replace(lower(COALESCE(v_rate.cat_band, '')), '[^a-z0-9%]+', '', 'g')
               OR (NEW.cat_band = 'New words'
                   AND v_rate.base_rate_id IS NULL AND v_rate.cat_band IS NULL)
           ) THEN
            RAISE EXCEPTION 'Linked Project values must match the selected Client rate-card row';
        END IF;
        NEW.rate_source := CASE WHEN v_card.account_id IS NULL
            THEN 'Client' ELSE 'Account' END;
    ELSIF TG_OP = 'UPDATE' AND (
        NEW.service_type IS DISTINCT FROM OLD.service_type
        OR NEW.specialization_id IS DISTINCT FROM OLD.specialization_id
        OR NEW.price_unit IS DISTINCT FROM OLD.price_unit
        OR NEW.cat_band IS DISTINCT FROM OLD.cat_band
        OR NEW.unit_price IS DISTINCT FROM OLD.unit_price
        OR NEW.rate_source IS DISTINCT FROM OLD.rate_source
    ) THEN
        RAISE EXCEPTION 'A linked Client rate-card snapshot may only change quantity';
    END IF;
    RETURN NEW;
END;
$$;

-- The function retains its compatible signature. Service and specialization
-- are now supplied automatically from the Project rather than selected inside
-- the CAT grid interface.
CREATE OR REPLACE FUNCTION public.replace_project_cat_grid(
    p_project_id UUID,
    p_rate_card_id UUID DEFAULT NULL,
    p_service_type TEXT DEFAULT 'Translation',
    p_specialization_id UUID DEFAULT NULL,
    p_unit TEXT DEFAULT 'Source words'
)
RETURNS SETOF public.scope_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_card public.client_rate_cards%ROWTYPE;
    v_band TEXT;
    v_sort INTEGER := 0;
    v_rate public.client_rate_items%ROWTYPE;
    v_source TEXT;
    v_bands CONSTANT TEXT[] := ARRAY[
        'New words', '50–74%', '75–84%', '85–94%',
        '95–99%', '100%', 'Repetitions'
    ];
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF p_service_type IS DISTINCT FROM v_project.project_type THEN
        RAISE EXCEPTION 'CAT grid service must match the Project primary service';
    END IF;
    IF p_specialization_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.project_specializations project_spec
        WHERE project_spec.project_id = p_project_id
          AND project_spec.specialization_id = p_specialization_id
    ) THEN
        RAISE EXCEPTION 'CAT grid specialization must belong to this Project';
    END IF;

    IF p_rate_card_id IS NOT NULL THEN
        SELECT * INTO v_card
        FROM public.client_rate_cards card
        WHERE card.id = p_rate_card_id
          AND card.client_id = v_project.client_id
          AND card.active
          AND (card.account_id IS NULL OR card.account_id = v_project.account_id);
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Selected rate card is not available for this Client/Account';
        END IF;
        v_source := CASE WHEN v_card.account_id IS NULL THEN 'Client' ELSE 'Account' END;
    ELSE
        v_source := 'Manual';
    END IF;

    DELETE FROM public.scope_items line
    WHERE line.project_id = p_project_id
      AND line.service_type = p_service_type
      AND line.specialization_id = p_specialization_id
      AND line.price_unit = p_unit
      AND line.cat_band = ANY(v_bands);

    FOREACH v_band IN ARRAY v_bands LOOP
        v_sort := v_sort + 10;
        v_rate.id := NULL;
        v_rate.rate := NULL;

        IF p_rate_card_id IS NOT NULL THEN
            SELECT item.* INTO v_rate
            FROM public.client_rate_items item
            WHERE item.rate_card_id = p_rate_card_id
              AND item.active
              AND item.service_type = p_service_type
              AND item.unit = p_unit
              AND (item.source_language IS NULL
                   OR item.source_language = v_project.source_language
                   OR v_project.source_language LIKE item.source_language || ' (%)')
              AND (item.target_language IS NULL
                   OR item.target_language = v_project.target_language
                   OR v_project.target_language LIKE item.target_language || ' (%)')
              AND (item.specialization_id IS NULL
                   OR item.specialization_id = p_specialization_id)
              AND (
                  (v_band = 'New words'
                   AND item.base_rate_id IS NULL AND item.cat_band IS NULL)
                  OR (v_band <> 'New words' AND item.cat_band IS NOT NULL
                      AND regexp_replace(lower(item.cat_band), '[^a-z0-9%]+', '', 'g')
                        = regexp_replace(lower(v_band), '[^a-z0-9%]+', '', 'g'))
              )
            ORDER BY
                (item.source_language IS NOT NULL)::INTEGER DESC,
                (item.target_language IS NOT NULL)::INTEGER DESC,
                (item.specialization_id IS NOT NULL)::INTEGER DESC,
                (item.base_rate_id IS NOT NULL)::INTEGER DESC,
                item.updated_at DESC, item.created_at DESC
            LIMIT 1;
        END IF;

        INSERT INTO public.scope_items (
            project_id, service_type, specialization_id, quantity, price_unit,
            cat_band, unit_price, price, rate_source, override_reason,
            sort_order, client_rate_item_id
        ) VALUES (
            p_project_id, p_service_type, p_specialization_id, 0, p_unit,
            v_band, COALESCE(v_rate.rate, 0), 0, v_source,
            CASE
                WHEN p_rate_card_id IS NULL THEN 'Blank CAT grid'
                WHEN v_rate.id IS NULL THEN 'No matching row in selected rate card'
                ELSE NULL
            END,
            v_sort, v_rate.id
        );
    END LOOP;

    IF p_rate_card_id IS NOT NULL THEN
        UPDATE public.projects
        SET currency = v_card.currency, price_source = v_source,
            price_override_reason = NULL, updated_at = NOW()
        WHERE id = p_project_id;
    ELSE
        UPDATE public.projects
        SET price_source = 'Manual', price_override_reason = 'Blank CAT grid',
            updated_at = NOW()
        WHERE id = p_project_id;
    END IF;

    RETURN QUERY
    SELECT line.* FROM public.scope_items line
    WHERE line.project_id = p_project_id
      AND line.service_type = p_service_type
      AND line.specialization_id = p_specialization_id
      AND line.price_unit = p_unit
      AND line.cat_band = ANY(v_bands)
    ORDER BY line.sort_order, line.created_at;
END;
$$;

COMMENT ON TABLE public.client_rate_cards IS
    'Client or Account rate cards. Each card contains one or more base-rate groups with calculated CAT discount rows.';
COMMENT ON COLUMN public.client_rate_items.base_rate_id IS
    'Links a calculated CAT row to its Client base rate.';

COMMIT;
