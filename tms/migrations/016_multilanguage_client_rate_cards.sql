-- RetodoOps TMS — multi-language Client rate cards and reliable Project CAT matching.
-- Run after 015_direct_po_assignment_and_financial_grid_fix.sql.

BEGIN;

-- One Client base rate may cover several Source and Target languages. Empty
-- arrays mean "Any language". Scalar columns remain populated for backwards
-- compatibility with historical exports and older snapshots.
ALTER TABLE public.client_rate_items
    ADD COLUMN IF NOT EXISTS source_languages TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS target_languages TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE public.client_rate_items
SET source_languages = CASE
        WHEN cardinality(source_languages) = 0 AND source_language IS NOT NULL
        THEN ARRAY[source_language] ELSE source_languages END,
    target_languages = CASE
        WHEN cardinality(target_languages) = 0 AND target_language IS NOT NULL
        THEN ARRAY[target_language] ELSE target_languages END;

CREATE INDEX IF NOT EXISTS client_rate_items_source_languages_gin_idx
    ON public.client_rate_items USING gin(source_languages);
CREATE INDEX IF NOT EXISTS client_rate_items_target_languages_gin_idx
    ON public.client_rate_items USING gin(target_languages);

CREATE OR REPLACE FUNCTION public.prepare_client_rate_card_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_base public.client_rate_items%ROWTYPE;
BEGIN
    IF NEW.base_rate_id IS NOT NULL THEN
        SELECT * INTO v_base FROM public.client_rate_items WHERE id = NEW.base_rate_id;
        IF NOT FOUND OR v_base.base_rate_id IS NOT NULL THEN
            RAISE EXCEPTION 'CAT rate must reference a valid base Client rate';
        END IF;
        IF NEW.rate_card_id <> v_base.rate_card_id THEN
            RAISE EXCEPTION 'CAT rate and base rate must belong to the same Client rate card';
        END IF;
        IF NULLIF(btrim(NEW.cat_band), '') IS NULL OR NEW.discount_percent IS NULL THEN
            RAISE EXCEPTION 'CAT band and discount percentage are required';
        END IF;

        NEW.source_languages := v_base.source_languages;
        NEW.target_languages := v_base.target_languages;
        NEW.source_language := v_base.source_language;
        NEW.target_language := v_base.target_language;
        NEW.service_type := v_base.service_type;
        NEW.specialization_id := v_base.specialization_id;
        NEW.unit := v_base.unit;
        NEW.minimum_fee := v_base.minimum_fee;
        NEW.rate := round(v_base.rate * (100 - NEW.discount_percent) / 100, 4);
    ELSE
        NEW.source_languages := COALESCE(NEW.source_languages, ARRAY[]::TEXT[]);
        NEW.target_languages := COALESCE(NEW.target_languages, ARRAY[]::TEXT[]);
        NEW.source_language := CASE WHEN cardinality(NEW.source_languages) > 0
            THEN NEW.source_languages[1] ELSE NULL END;
        NEW.target_language := CASE WHEN cardinality(NEW.target_languages) > 0
            THEN NEW.target_languages[1] ELSE NULL END;
        NEW.cat_band := NULL;
        NEW.discount_percent := NULL;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_client_rate_card_rows()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.base_rate_id IS NULL THEN
        UPDATE public.client_rate_items child
        SET source_languages = NEW.source_languages,
            target_languages = NEW.target_languages,
            source_language = NEW.source_language,
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

DROP TRIGGER IF EXISTS client_rate_items_sync_card_rows ON public.client_rate_items;
CREATE TRIGGER client_rate_items_sync_card_rows
AFTER UPDATE OF source_languages, target_languages, source_language,
    target_language, service_type, specialization_id, unit, rate, minimum_fee
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
    v_sources TEXT[];
    v_targets TEXT[];
    v_source TEXT;
    v_target TEXT;
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
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;

    SELECT COALESCE(array_agg(DISTINCT btrim(language) ORDER BY btrim(language)), ARRAY[]::TEXT[])
    INTO v_sources
    FROM jsonb_array_elements_text(COALESCE(p_payload->'source_languages', '[]'::JSONB)) AS item(language)
    WHERE NULLIF(btrim(language), '') IS NOT NULL;

    SELECT COALESCE(array_agg(DISTINCT btrim(language) ORDER BY btrim(language)), ARRAY[]::TEXT[])
    INTO v_targets
    FROM jsonb_array_elements_text(COALESCE(p_payload->'target_languages', '[]'::JSONB)) AS item(language)
    WHERE NULLIF(btrim(language), '') IS NOT NULL;

    -- Backwards compatibility for callers using the former scalar fields.
    IF cardinality(v_sources) = 0 AND NULLIF(btrim(p_payload->>'source_language'), '') IS NOT NULL THEN
        v_sources := ARRAY[btrim(p_payload->>'source_language')];
    END IF;
    IF cardinality(v_targets) = 0 AND NULLIF(btrim(p_payload->>'target_language'), '') IS NOT NULL THEN
        v_targets := ARRAY[btrim(p_payload->>'target_language')];
    END IF;
    v_source := CASE WHEN cardinality(v_sources) > 0 THEN v_sources[1] ELSE NULL END;
    v_target := CASE WHEN cardinality(v_targets) > 0 THEN v_targets[1] ELSE NULL END;

    IF v_rate_card_id IS NULL OR v_service IS NULL OR v_unit IS NULL OR v_base_rate IS NULL THEN
        RAISE EXCEPTION 'Rate card, service, unit and base price are required';
    END IF;
    IF v_base_rate < 0 OR COALESCE(v_minimum_fee, 0) < 0 THEN
        RAISE EXCEPTION 'Rates and minimum fees cannot be negative';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.client_rate_cards card
        WHERE card.id = v_rate_card_id AND card.active) THEN
        RAISE EXCEPTION 'Select an active Client rate card';
    END IF;

    IF v_base_id IS NULL THEN
        INSERT INTO public.client_rate_items(
            rate_card_id, source_language, target_language, source_languages,
            target_languages, service_type, specialization_id, unit, rate,
            minimum_fee, notes, cat_band, discount_percent, active
        ) VALUES (
            v_rate_card_id, v_source, v_target, v_sources, v_targets,
            v_service, v_specialization_id, v_unit, v_base_rate,
            v_minimum_fee, v_notes, NULL, NULL, TRUE
        ) RETURNING id INTO v_base_id;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.client_rate_items base
            WHERE base.id = v_base_id AND base.rate_card_id = v_rate_card_id
              AND base.base_rate_id IS NULL) THEN
            RAISE EXCEPTION 'Client base rate not found in the selected rate card';
        END IF;
        UPDATE public.client_rate_items
        SET source_languages = v_sources, target_languages = v_targets,
            source_language = v_source, target_language = v_target,
            service_type = v_service, specialization_id = v_specialization_id,
            unit = v_unit, rate = v_base_rate, minimum_fee = v_minimum_fee,
            notes = v_notes, active = TRUE, updated_at = NOW()
        WHERE id = v_base_id;

        UPDATE public.client_rate_items SET active = FALSE, updated_at = NOW()
        WHERE base_rate_id = v_base_id;
    END IF;

    FOR v_discount IN SELECT value FROM jsonb_array_elements(
        COALESCE(p_payload->'cat_discounts', '[]'::JSONB))
    LOOP
        v_band := NULLIF(btrim(v_discount->>'cat_band'), '');
        v_percent := NULLIF(v_discount->>'discount_percent', '')::NUMERIC;
        IF v_band IS NULL OR v_percent IS NULL OR v_percent < 0 OR v_percent > 100 THEN
            RAISE EXCEPTION 'Each CAT band requires a discount between 0 and 100 percent';
        END IF;
        IF lower(v_band) = ANY(v_seen_bands) THEN RAISE EXCEPTION 'Duplicate CAT band: %', v_band; END IF;
        v_seen_bands := array_append(v_seen_bands, lower(v_band));

        SELECT child.id INTO v_child_id FROM public.client_rate_items child
        WHERE child.base_rate_id = v_base_id AND lower(child.cat_band) = lower(v_band)
        LIMIT 1;
        IF v_child_id IS NULL THEN
            INSERT INTO public.client_rate_items(
                rate_card_id, base_rate_id, source_language, target_language,
                source_languages, target_languages, service_type,
                specialization_id, unit, cat_band, discount_percent, rate,
                minimum_fee, notes, active
            ) VALUES (
                v_rate_card_id, v_base_id, v_source, v_target, v_sources,
                v_targets, v_service, v_specialization_id, v_unit, v_band,
                v_percent, v_base_rate, v_minimum_fee, v_notes, TRUE
            );
        ELSE
            UPDATE public.client_rate_items SET discount_percent = v_percent,
                active = TRUE, updated_at = NOW() WHERE id = v_child_id;
        END IF;
        v_child_id := NULL;
    END LOOP;
    RETURN v_base_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_client_rate_card_item(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_client_rate_card_item(JSONB) TO authenticated;

-- A selected card must contain a real base row matching the Project. More
-- specific language/specialization rows win over Any-language defaults.
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
    v_base public.client_rate_items%ROWTYPE;
    v_rate public.client_rate_items%ROWTYPE;
    v_band TEXT;
    v_sort INTEGER := 0;
    v_source TEXT;
    v_bands CONSTANT TEXT[] := ARRAY['New words','50–74%','75–84%','85–94%','95–99%','100%','Repetitions'];
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF p_service_type IS DISTINCT FROM v_project.project_type THEN
        RAISE EXCEPTION 'CAT grid service must match the Project primary service';
    END IF;
    IF p_specialization_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.project_specializations ps
        WHERE ps.project_id = p_project_id AND ps.specialization_id = p_specialization_id) THEN
        RAISE EXCEPTION 'CAT grid specialization must belong to this Project';
    END IF;

    IF p_rate_card_id IS NOT NULL THEN
        SELECT * INTO v_card FROM public.client_rate_cards card
        WHERE card.id = p_rate_card_id AND card.client_id = v_project.client_id
          AND card.active AND (card.account_id IS NULL OR card.account_id = v_project.account_id);
        IF NOT FOUND THEN RAISE EXCEPTION 'Selected rate card is not available for this Client/Account'; END IF;
        v_source := CASE WHEN v_card.account_id IS NULL THEN 'Client' ELSE 'Account' END;

        SELECT item.* INTO v_base FROM public.client_rate_items item
        WHERE item.rate_card_id = p_rate_card_id AND item.active
          AND item.base_rate_id IS NULL AND item.cat_band IS NULL
          AND item.service_type = p_service_type AND item.unit = p_unit
          AND (cardinality(item.source_languages) = 0
               OR v_project.source_language = ANY(item.source_languages))
          AND (cardinality(item.target_languages) = 0
               OR v_project.target_language = ANY(item.target_languages))
          AND (item.specialization_id IS NULL OR item.specialization_id = p_specialization_id)
        ORDER BY (cardinality(item.source_languages) > 0)::INTEGER DESC,
          (cardinality(item.target_languages) > 0)::INTEGER DESC,
          (item.specialization_id IS NOT NULL)::INTEGER DESC,
          item.updated_at DESC, item.created_at DESC LIMIT 1;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'No base price in this Client rate card matches % -> %, %, specialization and %',
                v_project.source_language, v_project.target_language, p_service_type, p_unit;
        END IF;
    ELSE
        v_source := 'Manual';
    END IF;

    DELETE FROM public.scope_items line WHERE line.project_id = p_project_id
      AND line.service_type = p_service_type AND line.specialization_id = p_specialization_id
      AND line.price_unit = p_unit AND line.cat_band = ANY(v_bands);

    FOREACH v_band IN ARRAY v_bands LOOP
        v_sort := v_sort + 10; v_rate.id := NULL; v_rate.rate := NULL;
        IF p_rate_card_id IS NOT NULL THEN
            IF v_band = 'New words' THEN v_rate := v_base;
            ELSE
                SELECT item.* INTO v_rate FROM public.client_rate_items item
                WHERE item.base_rate_id = v_base.id AND item.active
                  AND regexp_replace(lower(COALESCE(item.cat_band,'')), '[^a-z0-9%]+','','g')
                    = regexp_replace(lower(v_band), '[^a-z0-9%]+','','g')
                ORDER BY item.updated_at DESC, item.created_at DESC LIMIT 1;
            END IF;
        END IF;
        INSERT INTO public.scope_items(
            project_id, service_type, specialization_id, quantity, price_unit,
            cat_band, unit_price, price, rate_source, override_reason,
            sort_order, client_rate_item_id
        ) VALUES (
            p_project_id, p_service_type, p_specialization_id, 0, p_unit,
            v_band, COALESCE(v_rate.rate,0), 0, v_source,
            CASE WHEN p_rate_card_id IS NULL THEN 'Blank CAT grid'
                 WHEN v_rate.id IS NULL THEN 'CAT discount not defined in selected rate card'
                 ELSE NULL END,
            v_sort, v_rate.id
        );
    END LOOP;

    UPDATE public.projects project SET
        currency = CASE WHEN p_rate_card_id IS NULL THEN project.currency ELSE v_card.currency END,
        price_source = v_source,
        price_override_reason = CASE WHEN p_rate_card_id IS NULL THEN 'Blank CAT grid' ELSE NULL END,
        updated_at = NOW()
    WHERE id = p_project_id;

    RETURN QUERY SELECT line.* FROM public.scope_items line
    WHERE line.project_id = p_project_id AND line.service_type = p_service_type
      AND line.specialization_id = p_specialization_id AND line.price_unit = p_unit
      AND line.cat_band = ANY(v_bands) ORDER BY line.sort_order, line.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_project_cat_grid(UUID, UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.replace_project_cat_grid(UUID, UUID, TEXT, UUID, TEXT) TO authenticated;

COMMENT ON COLUMN public.client_rate_items.source_languages IS
    'Source languages covered by this Client base rate; empty means Any language.';
COMMENT ON COLUMN public.client_rate_items.target_languages IS
    'Target languages covered by this Client base rate; empty means Any language.';

COMMIT;
