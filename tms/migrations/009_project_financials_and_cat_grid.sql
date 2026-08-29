-- RetodoOps TMS — Project Financials, linked client price cards and CAT grid
-- Run after 008_resource_reference_data_and_cat_rates.sql.

BEGIN;

ALTER TABLE public.scope_items
    ADD COLUMN IF NOT EXISTS client_rate_item_id UUID
        REFERENCES public.client_rate_items(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS scope_items_client_rate_item_idx
    ON public.scope_items(client_rate_item_id);

-- A linked client rate is a provenance record. The commercial values stored on
-- the Project remain snapshots, so later price-card edits do not rewrite old work.
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
    IF NEW.client_rate_item_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_project FROM public.projects WHERE id = NEW.project_id;
    SELECT * INTO v_rate FROM public.client_rate_items
    WHERE id = NEW.client_rate_item_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Client price-list row not found'; END IF;

    SELECT * INTO v_card FROM public.client_rate_cards
    WHERE id = v_rate.rate_card_id;
    IF NOT FOUND OR v_card.client_id <> v_project.client_id THEN
        RAISE EXCEPTION 'Client price-list row does not belong to the Project Client';
    END IF;
    IF v_card.account_id IS NOT NULL
       AND v_card.account_id IS DISTINCT FROM v_project.account_id THEN
        RAISE EXCEPTION 'Account price list does not belong to the Project Account';
    END IF;
    IF TG_OP = 'INSERT' OR NEW.client_rate_item_id IS DISTINCT FROM OLD.client_rate_item_id THEN
        IF NEW.service_type IS DISTINCT FROM v_rate.service_type
           OR NEW.price_unit IS DISTINCT FROM v_rate.unit
           OR NEW.specialization_id IS DISTINCT FROM v_rate.specialization_id
              AND v_rate.specialization_id IS NOT NULL
           OR NEW.unit_price IS DISTINCT FROM v_rate.rate
           OR NOT (
               regexp_replace(lower(COALESCE(NEW.cat_band, '')), '[^a-z0-9%]+', '', 'g')
                 = regexp_replace(lower(COALESCE(v_rate.cat_band, '')), '[^a-z0-9%]+', '', 'g')
               OR (NEW.cat_band = 'New words' AND v_rate.cat_band IS NULL)
           )
        THEN
            RAISE EXCEPTION 'Linked Project price values must match the selected Client price-list row';
        END IF;
        NEW.rate_source := CASE WHEN v_card.account_id IS NULL THEN 'Client' ELSE 'Account' END;
    ELSIF TG_OP = 'UPDATE' AND (
        NEW.service_type IS DISTINCT FROM OLD.service_type
        OR NEW.specialization_id IS DISTINCT FROM OLD.specialization_id
        OR NEW.price_unit IS DISTINCT FROM OLD.price_unit
        OR NEW.cat_band IS DISTINCT FROM OLD.cat_band
        OR NEW.unit_price IS DISTINCT FROM OLD.unit_price
        OR NEW.rate_source IS DISTINCT FROM OLD.rate_source
    ) THEN
        RAISE EXCEPTION 'A linked Client price-list snapshot may only change quantity';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_validate_client_rate_link
    ON public.scope_items;
CREATE TRIGGER scope_items_validate_client_rate_link
BEFORE INSERT OR UPDATE OF project_id, client_rate_item_id, service_type,
    specialization_id, price_unit, cat_band, unit_price, rate_source
ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.validate_scope_client_rate_link();

-- Project price lines are authoritative whenever they exist.
CREATE OR REPLACE FUNCTION public.prepare_scope_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.quantity := COALESCE(NEW.quantity, 0);
    NEW.unit_price := COALESCE(NEW.unit_price, 0);
    NEW.price := CASE
        WHEN NEW.price_unit = 'Fixed fee' THEN round(NEW.unit_price, 2)
        ELSE round(NEW.quantity * NEW.unit_price, 2)
    END;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_prepare_amount ON public.scope_items;
CREATE TRIGGER scope_items_prepare_amount
BEFORE INSERT OR UPDATE OF quantity, price_unit, unit_price
ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.prepare_scope_amount();

CREATE OR REPLACE FUNCTION public.recalculate_project_client_price()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_id UUID := CASE WHEN TG_OP = 'DELETE' THEN OLD.project_id ELSE NEW.project_id END;
BEGIN
    UPDATE public.projects project
    SET price = COALESCE((
        SELECT sum(line.price)
        FROM public.scope_items line
        WHERE line.project_id = v_project_id
    ), 0),
    updated_at = NOW()
    WHERE project.id = v_project_id;

    IF TG_OP = 'UPDATE' AND OLD.project_id IS DISTINCT FROM NEW.project_id THEN
        UPDATE public.projects project
        SET price = COALESCE((
            SELECT sum(line.price)
            FROM public.scope_items line
            WHERE line.project_id = OLD.project_id
        ), 0),
        updated_at = NOW()
        WHERE project.id = OLD.project_id;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_recalculate_project_price
    ON public.scope_items;
CREATE TRIGGER scope_items_recalculate_project_price
AFTER INSERT OR UPDATE OF project_id, quantity, price_unit, unit_price, price OR DELETE
ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.recalculate_project_client_price();

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
    IF p_specialization_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.project_specializations project_spec
        WHERE project_spec.project_id = p_project_id
          AND project_spec.specialization_id = p_specialization_id
    ) THEN
        RAISE EXCEPTION 'Select a specialization used by this Project';
    END IF;

    IF p_rate_card_id IS NOT NULL THEN
        SELECT * INTO v_card
        FROM public.client_rate_cards card
        WHERE card.id = p_rate_card_id
          AND card.client_id = v_project.client_id
          AND card.active
          AND (card.valid_from IS NULL OR card.valid_from <= CURRENT_DATE)
          AND (card.valid_to IS NULL OR card.valid_to >= CURRENT_DATE)
          AND (card.account_id IS NULL OR card.account_id = v_project.account_id);
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Selected price list is not available for this Client/Account';
        END IF;
        v_source := CASE WHEN v_card.account_id IS NULL THEN 'Client' ELSE 'Account' END;
    ELSE
        v_source := 'Manual';
    END IF;

    -- Replace only the matching standard CAT grid. Other financial lines such
    -- as DTP, minimum fees or fixed adjustments remain untouched.
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
                  regexp_replace(lower(COALESCE(item.cat_band, '')), '[^a-z0-9%]+', '', 'g')
                    = regexp_replace(lower(v_band), '[^a-z0-9%]+', '', 'g')
                  OR (v_band = 'New words' AND item.cat_band IS NULL)
              )
            ORDER BY
                (item.source_language IS NOT NULL)::INTEGER DESC,
                (item.target_language IS NOT NULL)::INTEGER DESC,
                (item.specialization_id IS NOT NULL)::INTEGER DESC,
                (item.cat_band IS NOT NULL)::INTEGER DESC,
                item.created_at DESC
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
                WHEN v_rate.id IS NULL THEN 'No matching row in selected price list'
                ELSE NULL
            END,
            v_sort, v_rate.id
        );
    END LOOP;

    IF p_rate_card_id IS NOT NULL THEN
        UPDATE public.projects
        SET currency = v_card.currency,
            price_source = v_source,
            price_override_reason = NULL,
            updated_at = NOW()
        WHERE id = p_project_id;
    ELSE
        UPDATE public.projects
        SET price_source = 'Manual',
            price_override_reason = 'Blank CAT grid',
            updated_at = NOW()
        WHERE id = p_project_id;
    END IF;

    RETURN QUERY
    SELECT line.*
    FROM public.scope_items line
    WHERE line.project_id = p_project_id
      AND line.service_type = p_service_type
      AND line.specialization_id = p_specialization_id
      AND line.price_unit = p_unit
      AND line.cat_band = ANY(v_bands)
    ORDER BY line.sort_order, line.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_project_cat_grid(
    UUID, UUID, TEXT, UUID, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.replace_project_cat_grid(
    UUID, UUID, TEXT, UUID, TEXT
) TO authenticated;

COMMIT;
