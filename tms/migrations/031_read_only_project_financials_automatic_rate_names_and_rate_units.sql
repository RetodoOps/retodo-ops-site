-- RetodoOps TMS — Scoop-owned financial editing, automatic rate-card names,
-- and rate-card-owned Supplier Units. Run after 030_catalog_rate_coverage_and_project_total_repair.sql.

BEGIN;

-- Client rate-card names are derived from their active base rows. A card may
-- contain several rows, so the first five are shown and the remainder are
-- counted rather than asking the PM to maintain a second, stale name field.
CREATE OR REPLACE FUNCTION public.refresh_client_rate_card_name(p_card_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account TEXT;
    v_currency TEXT;
    v_count INTEGER;
    v_summary TEXT;
    v_name TEXT;
BEGIN
    SELECT COALESCE(account.name, 'Client-wide'), card.currency
    INTO v_account, v_currency
    FROM public.client_rate_cards card
    LEFT JOIN public.client_accounts account ON account.id = card.account_id
    WHERE card.id = p_card_id;
    IF NOT FOUND THEN RETURN; END IF;

    SELECT count(*)::INTEGER
    INTO v_count
    FROM public.client_rate_items item
    WHERE item.rate_card_id = p_card_id
      AND item.base_rate_id IS NULL
      AND item.active;

    SELECT string_agg(row_data.label, ' | ' ORDER BY row_data.created_at, row_data.id)
    INTO v_summary
    FROM (
        SELECT item.id, item.created_at,
            concat_ws(' · ',
                concat_ws(' → ',
                    COALESCE(NULLIF(array_to_string(item.source_languages, ', '), ''), item.source_language, 'Any'),
                    COALESCE(NULLIF(array_to_string(item.target_languages, ', '), ''), item.target_language, 'Any')
                ),
                item.service_type,
                concat(
                    rtrim(rtrim(to_char(item.rate, 'FM999999999990.0000'), '0'), '.'),
                    ' ', v_currency, ' / ', item.unit
                ),
                COALESCE(spec.name, 'All specializations')
            ) AS label
        FROM public.client_rate_items item
        LEFT JOIN public.specializations spec ON spec.id = item.specialization_id
        WHERE item.rate_card_id = p_card_id
          AND item.base_rate_id IS NULL
          AND item.active
        ORDER BY item.created_at, item.id
        LIMIT 5
    ) row_data;

    IF v_summary IS NULL THEN
        v_name := concat_ws(' · ', v_account, 'New rate card', v_currency);
    ELSE
        v_name := concat_ws(' · ', v_summary, v_account);
        IF v_count > 5 THEN
            v_name := v_name || format(' · +%s more rate%s', v_count - 5, CASE WHEN v_count - 5 = 1 THEN '' ELSE 's' END);
        END IF;
    END IF;

    UPDATE public.client_rate_cards
    SET name = v_name, updated_at = NOW()
    WHERE id = p_card_id
      AND name IS DISTINCT FROM v_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_client_rate_card_name_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.refresh_client_rate_card_name(OLD.rate_card_id);
        RETURN OLD;
    END IF;
    PERFORM public.refresh_client_rate_card_name(NEW.rate_card_id);
    IF TG_OP = 'UPDATE' AND OLD.rate_card_id IS DISTINCT FROM NEW.rate_card_id THEN
        PERFORM public.refresh_client_rate_card_name(OLD.rate_card_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_rate_items_refresh_card_name
    ON public.client_rate_items;
CREATE TRIGGER client_rate_items_refresh_card_name
AFTER INSERT OR UPDATE OR DELETE ON public.client_rate_items
FOR EACH ROW EXECUTE FUNCTION public.refresh_client_rate_card_name_trigger();

-- Keep the generated Account portion current when an Account is renamed.
CREATE OR REPLACE FUNCTION public.refresh_client_rate_card_names_for_account_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_card_id UUID;
BEGIN
    FOR v_card_id IN
        SELECT id FROM public.client_rate_cards WHERE account_id = NEW.id
    LOOP
        PERFORM public.refresh_client_rate_card_name(v_card_id);
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_accounts_refresh_rate_card_names
    ON public.client_accounts;
CREATE TRIGGER client_accounts_refresh_rate_card_names
AFTER UPDATE OF name ON public.client_accounts
FOR EACH ROW
WHEN (OLD.name IS DISTINCT FROM NEW.name)
EXECUTE FUNCTION public.refresh_client_rate_card_names_for_account_trigger();

-- Also normalize the generated header when a card is created or its scope or
-- currency is changed by an administrator or an integration.
CREATE OR REPLACE FUNCTION public.refresh_client_rate_card_header_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.refresh_client_rate_card_name(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_rate_cards_refresh_generated_name
    ON public.client_rate_cards;
CREATE TRIGGER client_rate_cards_refresh_generated_name
AFTER INSERT OR UPDATE OF account_id, currency ON public.client_rate_cards
FOR EACH ROW EXECUTE FUNCTION public.refresh_client_rate_card_header_trigger();

DO $$
DECLARE
    v_card_id UUID;
BEGIN
    FOR v_card_id IN SELECT id FROM public.client_rate_cards LOOP
        PERFORM public.refresh_client_rate_card_name(v_card_id);
    END LOOP;
END;
$$;

-- The Job page no longer exposes Unit before a Supplier rate is selected.
-- Keep the existing, version-aware save function as the source of truth, but
-- inject the selected rate's Unit so its legacy validation cannot reject a
-- valid card merely because the old Job snapshot used another Unit.
CREATE OR REPLACE FUNCTION public.save_job_overview_inherit_rate_unit(
    p_job_id UUID,
    p_payload JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payload JSONB := COALESCE(p_payload, '{}'::JSONB);
    v_rate_id UUID := NULLIF(p_payload->>'resource_rate_id', '')::UUID;
    v_rate public.resource_rates%ROWTYPE;
BEGIN
    IF v_rate_id IS NOT NULL THEN
        SELECT * INTO v_rate
        FROM public.resource_rates
        WHERE id = v_rate_id
          AND base_rate_id IS NULL
          AND active
          AND status = 'Approved';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Select an active Approved base Supplier rate card';
        END IF;
        v_payload := jsonb_set(v_payload, '{unit}', to_jsonb(v_rate.unit), TRUE);
    END IF;
    RETURN public.save_job_overview(p_job_id, v_payload);
END;
$$;

REVOKE ALL ON FUNCTION public.save_job_overview_inherit_rate_unit(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_job_overview_inherit_rate_unit(UUID, JSONB) TO authenticated;

-- Assignment uses the same existing PO/version workflow after first syncing
-- the Job's Unit to the selected Supplier base rate.
CREATE OR REPLACE FUNCTION public.assign_job_and_issue_po_inherit_rate_unit(
    p_job_id UUID,
    p_resource_id UUID,
    p_resource_rate_id UUID,
    p_cat_rows JSONB,
    p_reassignment_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rate public.resource_rates%ROWTYPE;
BEGIN
    SELECT * INTO v_rate
    FROM public.resource_rates
    WHERE id = p_resource_rate_id
      AND resource_id = p_resource_id
      AND base_rate_id IS NULL
      AND active
      AND status = 'Approved';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Select an active Approved base Supplier rate card';
    END IF;

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs
    SET unit = v_rate.unit, updated_at = NOW()
    WHERE id = p_job_id;

    RETURN public.assign_job_and_issue_po(
        p_job_id, p_resource_id, p_resource_rate_id,
        p_cat_rows, p_reassignment_reason
    );
END;
$$;

REVOKE ALL ON FUNCTION public.assign_job_and_issue_po_inherit_rate_unit(
    UUID, UUID, UUID, JSONB, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_job_and_issue_po_inherit_rate_unit(
    UUID, UUID, UUID, JSONB, TEXT
) TO authenticated;

COMMIT;
