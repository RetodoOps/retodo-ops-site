-- RetodoOps TMS — catalogue-backed Supplier language coverage and Project
-- total reconciliation. Run once after 029_catalogs_and_scoop_financial_editor.sql.

BEGIN;

-- A Supplier rate card may select any active language from Settings. Saving it
-- records the selected cross-product as approved Resource language coverage,
-- keeping the capability list and the rate card in sync.
CREATE OR REPLACE FUNCTION public.save_scoped_resource_rate_card(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base_id UUID;
    v_resource_id UUID := NULLIF(p_payload->>'resource_id', '')::UUID;
    v_account_id UUID := NULLIF(p_payload->>'account_id', '')::UUID;
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
    v_sources TEXT[];
    v_targets TEXT[];
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_resource_id IS NULL OR v_service IS NULL THEN
        RAISE EXCEPTION 'Resource and service are required';
    END IF;
    IF NOT public.is_supported_tms_service(v_service) THEN
        RAISE EXCEPTION 'Select an active service from Settings';
    END IF;
    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_accounts account
        WHERE account.id = v_account_id AND account.active
    ) THEN
        RAISE EXCEPTION 'Select an active Account for this Supplier rate card';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT btrim(value)), ARRAY[]::TEXT[])
    INTO v_sources
    FROM jsonb_array_elements_text(COALESCE(p_payload->'source_languages','[]'::JSONB));
    SELECT COALESCE(array_agg(DISTINCT btrim(value)), ARRAY[]::TEXT[])
    INTO v_targets
    FROM jsonb_array_elements_text(COALESCE(p_payload->'target_languages','[]'::JSONB));

    IF cardinality(v_sources) = 0 OR cardinality(v_targets) = 0 THEN
        RAISE EXCEPTION 'Select at least one Source and Target language';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_sources || v_targets) selected(language)
        WHERE NOT EXISTS (
            SELECT 1 FROM public.language_catalog catalog
            WHERE catalog.active
              AND lower(btrim(catalog.name)) = lower(btrim(selected.language))
        )
    ) THEN
        RAISE EXCEPTION 'Select active languages from Settings';
    END IF;

    INSERT INTO public.resource_language_pairs(
        resource_id, source_language, target_language,
        native_target, approved, notes
    )
    SELECT v_resource_id, source.language, target.language,
           FALSE, TRUE, 'Added from Supplier rate card'
    FROM unnest(v_sources) source(language)
    CROSS JOIN unnest(v_targets) target(language)
    WHERE source.language IS DISTINCT FROM target.language
    ON CONFLICT (resource_id, source_language, target_language)
    DO UPDATE SET approved = TRUE;

    INSERT INTO public.resource_services(
        resource_id, service_type, approved, notes
    ) VALUES (
        v_resource_id, v_service, TRUE, 'Added from Supplier rate card'
    ) ON CONFLICT (resource_id, service_type)
      DO UPDATE SET approved = TRUE;

    v_base_id := public.save_resource_rate_card(p_payload);

    UPDATE public.resource_rates
    SET account_id = v_account_id,
        updated_at = NOW()
    WHERE id = v_base_id OR base_rate_id = v_base_id;

    RETURN v_base_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_scoped_resource_rate_card(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_scoped_resource_rate_card(JSONB) TO authenticated;

-- Reconcile Scoop prices from their own detailed rows, then calculate every
-- Project exactly once as the sum of its active Scoops.
UPDATE public.scope_items line
SET project_scoop_id = (
    SELECT scoop.id FROM public.project_scoops scoop
    WHERE scoop.project_id = line.project_id
    ORDER BY scoop.created_at, scoop.id LIMIT 1
)
WHERE line.project_scoop_id IS NULL;

UPDATE public.project_scoops scoop
SET price = totals.price,
    updated_at = NOW()
FROM (
    SELECT line.project_scoop_id, round(COALESCE(sum(line.price),0),2) AS price
    FROM public.scope_items line
    WHERE line.project_scoop_id IS NOT NULL
    GROUP BY line.project_scoop_id
) totals
WHERE scoop.id = totals.project_scoop_id
  AND scoop.price IS DISTINCT FROM totals.price;

UPDATE public.projects project
SET price = COALESCE((
        SELECT round(sum(scoop.price),2)
        FROM public.project_scoops scoop
        WHERE scoop.project_id = project.id AND scoop.active
    ),0),
    updated_at = NOW();

COMMIT;
