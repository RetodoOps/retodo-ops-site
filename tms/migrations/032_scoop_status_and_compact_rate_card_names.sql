-- RetodoOps TMS — Scoop workflow status and compact generated rate-card names.
-- Run once after 031_read_only_project_financials_automatic_rate_names_and_rate_units.sql.

BEGIN;

-- A Scoop has its own workflow state. It is derived from the active Jobs in
-- that Scoop, so an unrelated Job in the same Project cannot change it.
ALTER TABLE public.project_scoops
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'Assign';

UPDATE public.project_scoops
SET status = 'Assign'
WHERE status IS NULL
   OR status NOT IN (
       'Assign', 'Ongoing', 'Ready for QA', 'Waiting',
       'Ready to Deliver', 'Delivered to Client', 'Approved'
   );

ALTER TABLE public.project_scoops
    ALTER COLUMN status SET DEFAULT 'Assign',
    ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.project_scoops
    DROP CONSTRAINT IF EXISTS project_scoops_status_check;
ALTER TABLE public.project_scoops
    ADD CONSTRAINT project_scoops_status_check CHECK (status IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting',
        'Ready to Deliver', 'Delivered to Client', 'Approved'
    ));

-- Compact labels use the Settings catalogue codes while retaining a readable
-- fallback for historical language names and custom catalogue entries.
CREATE OR REPLACE FUNCTION public.tms_compact_language_code(p_language TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN upper(COALESCE(code, '')) = 'EN-GB' THEN 'EN-UK'
        WHEN upper(COALESCE(code, '')) = 'NB' THEN 'NO-NB'
        ELSE COALESCE(
            NULLIF(regexp_replace(upper(COALESCE(code, '')), '[^A-Z0-9-]', '', 'g'), ''),
            'ANY'
        )
    END
    FROM (
        SELECT COALESCE(
            (
                SELECT catalog.code
                FROM public.language_catalog catalog
                WHERE lower(btrim(catalog.name)) = lower(btrim(COALESCE(p_language, '')))
                  AND catalog.active
                ORDER BY catalog.sort_order, catalog.name
                LIMIT 1
            ),
            public.tms_language_code(p_language)
        ) AS code
    ) resolved;
$$;

CREATE OR REPLACE FUNCTION public.tms_compact_unit(p_unit TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE btrim(COALESCE(p_unit, ''))
        WHEN 'Source words' THEN 'source-word'
        WHEN 'Target words' THEN 'target-word'
        WHEN 'Hours' THEN 'hour'
        WHEN 'Pages' THEN 'page'
        WHEN 'Minutes' THEN 'minute'
        WHEN 'Fixed fee' THEN 'fixed-fee'
        ELSE lower(COALESCE(NULLIF(btrim(p_unit), ''), 'unit'))
    END;
$$;

CREATE OR REPLACE FUNCTION public.tms_compact_rate_line_label(
    p_source_languages TEXT[],
    p_source_language TEXT,
    p_target_languages TEXT[],
    p_target_language TEXT,
    p_service_type TEXT,
    p_specialization_id UUID,
    p_account_label TEXT,
    p_rate NUMERIC,
    p_currency TEXT,
    p_unit TEXT
)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH source_values AS (
        SELECT CASE
            WHEN COALESCE(cardinality(p_source_languages), 0) > 0
                THEN p_source_languages
            WHEN NULLIF(btrim(p_source_language), '') IS NULL
                THEN ARRAY[]::TEXT[]
            ELSE ARRAY[p_source_language]::TEXT[]
        END AS language_values
    ), target_values AS (
        SELECT CASE
            WHEN COALESCE(cardinality(p_target_languages), 0) > 0
                THEN p_target_languages
            WHEN NULLIF(btrim(p_target_language), '') IS NULL
                THEN ARRAY[]::TEXT[]
            ELSE ARRAY[p_target_language]::TEXT[]
        END AS language_values
    ), pair AS (
        SELECT
            COALESCE((
                SELECT string_agg(public.tms_compact_language_code(value), '+' ORDER BY ord)
                FROM source_values, unnest(source_values.language_values) WITH ORDINALITY AS item(value, ord)
            ), 'ANY') AS source_code,
            COALESCE((
                SELECT string_agg(public.tms_compact_language_code(value), '+' ORDER BY ord)
                FROM target_values, unnest(target_values.language_values) WITH ORDINALITY AS item(value, ord)
            ), 'ANY') AS target_code
    )
    SELECT concat_ws(' · ',
        pair.source_code || '-' || pair.target_code,
        COALESCE((
            SELECT upper(catalog.code)
            FROM public.service_catalog catalog
            WHERE lower(btrim(catalog.name)) = lower(btrim(COALESCE(p_service_type, '')))
            LIMIT 1
        ), public.job_service_code(p_service_type), 'OTH'),
        COALESCE((
            SELECT spec.name FROM public.specializations spec
            WHERE spec.id = p_specialization_id
        ), 'All specs')
    )
    || format(' - %s - %s %s/%s',
        COALESCE(NULLIF(btrim(p_account_label), ''), 'All acc'),
        rtrim(rtrim(to_char(COALESCE(p_rate, 0), 'FM999999999990.0000'), '0'), '.'),
        COALESCE(NULLIF(btrim(p_currency), ''), 'EUR'),
        public.tms_compact_unit(p_unit)
    )
    FROM pair;
$$;

-- Replace the verbose Client card header with a generated compact summary.
-- The name is recomputed whenever a base/CAT row, account or currency changes.
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
    SELECT COALESCE(account.name, 'All acc'), card.currency
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
            public.tms_compact_rate_line_label(
                item.source_languages, item.source_language,
                item.target_languages, item.target_language,
                item.service_type, item.specialization_id,
                v_account, item.rate, v_currency, item.unit
            ) AS label
        FROM public.client_rate_items item
        WHERE item.rate_card_id = p_card_id
          AND item.base_rate_id IS NULL
          AND item.active
        ORDER BY item.created_at, item.id
        LIMIT 5
    ) row_data;

    IF v_summary IS NULL THEN
        v_name := concat_ws(' · ', v_account, 'New rate card', v_currency);
    ELSE
        v_name := v_summary;
        IF v_count > 5 THEN
            v_name := v_name || format(' · +%s more rate%s', v_count - 5,
                CASE WHEN v_count - 5 = 1 THEN '' ELSE 's' END);
        END IF;
    END IF;

    UPDATE public.client_rate_cards
    SET name = v_name, updated_at = NOW()
    WHERE id = p_card_id
      AND name IS DISTINCT FROM v_name;
END;
$$;

-- Keep the existing migration-031 triggers, but recreate them here so this
-- migration is safe on installations where an earlier trigger was missed.
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

-- Derive a Scoop status from its own active Job set. An assigned Job makes a
-- Scoop Ongoing even when another Job in the same Scoop remains Unassigned.
CREATE OR REPLACE FUNCTION public.refresh_project_scoop_status(p_scoop_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT CASE
        WHEN count(*) = 0 THEN 'Assign'
        WHEN count(*) FILTER (WHERE job.status IN (
            'Assigned', 'In Progress', 'Delivered', 'Revision Required', 'Approved'
        )) = 0 THEN 'Assign'
        WHEN count(*) FILTER (WHERE job.status = 'Approved') = count(*)
            THEN 'Approved'
        WHEN count(*) FILTER (WHERE job.status IN ('Delivered', 'Approved')) = count(*)
            THEN 'Delivered to Client'
        ELSE 'Ongoing'
    END
    INTO v_status
    FROM public.project_jobs job
    WHERE job.project_scoop_id = p_scoop_id
      AND job.status NOT IN ('Declined', 'Cancelled');

    UPDATE public.project_scoops scoop
    SET status = v_status, updated_at = NOW()
    WHERE scoop.id = p_scoop_id
      AND scoop.status IS DISTINCT FROM v_status;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_project_scoop_status_from_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_scoop_id UUID;
    v_old_scoop_id UUID;
BEGIN
    IF TG_OP <> 'DELETE' THEN v_new_scoop_id := NEW.project_scoop_id; END IF;
    IF TG_OP <> 'INSERT' THEN v_old_scoop_id := OLD.project_scoop_id; END IF;

    IF v_old_scoop_id IS NOT NULL
       AND (TG_OP = 'DELETE' OR v_old_scoop_id IS DISTINCT FROM v_new_scoop_id) THEN
        PERFORM public.refresh_project_scoop_status(v_old_scoop_id);
    END IF;
    IF v_new_scoop_id IS NOT NULL THEN
        PERFORM public.refresh_project_scoop_status(v_new_scoop_id);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_sync_scoop_status
    ON public.project_jobs;
CREATE TRIGGER project_jobs_sync_scoop_status
AFTER INSERT OR UPDATE OF project_scoop_id, resource_id, status OR DELETE
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.sync_project_scoop_status_from_job();

-- Backfill existing rows after all functions and triggers exist.
DO $$
DECLARE
    v_scoop_id UUID;
    v_card_id UUID;
BEGIN
    FOR v_scoop_id IN SELECT id FROM public.project_scoops LOOP
        PERFORM public.refresh_project_scoop_status(v_scoop_id);
    END LOOP;
    FOR v_card_id IN SELECT id FROM public.client_rate_cards LOOP
        PERFORM public.refresh_client_rate_card_name(v_card_id);
    END LOOP;
END;
$$;

COMMIT;
