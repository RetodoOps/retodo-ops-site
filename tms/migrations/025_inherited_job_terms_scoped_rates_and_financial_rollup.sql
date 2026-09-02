-- RetodoOps TMS — inherited Job specialization, deadline validation,
-- Account-scoped Supplier rates and authoritative multi-Job financial rollup.
-- Run after 024_job_service_codes_and_sorting.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.job_service_code(p_service_type TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE lower(btrim(COALESCE(p_service_type, '')))
        WHEN 'translation' THEN 'TRA'
        WHEN 'mtpe' THEN 'MTP'
        WHEN 'machine translation post-editing' THEN 'MTP'
        WHEN 'proofreading' THEN 'PRF'
        WHEN 'independent review' THEN 'REV'
        WHEN 'review' THEN 'REV'
        WHEN 'lqa' THEN 'LQA'
        WHEN 'terminology' THEN 'TER'
        WHEN 'dtp' THEN 'DTP'
        WHEN 'transcription' THEN 'TRS'
        WHEN 'subtitling' THEN 'SUB'
        WHEN 'voice-over' THEN 'VO'
        WHEN 'transcreation' THEN 'TRC'
        WHEN 'project management' THEN 'PM'
        ELSE 'OTH'
    END;
$$;

CREATE OR REPLACE FUNCTION public.is_supported_tms_service(p_service_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT btrim(COALESCE(p_service_type, '')) = ANY(ARRAY[
        'Translation', 'MTPE', 'Proofreading', 'Independent Review', 'LQA',
        'Terminology', 'DTP', 'Transcription', 'Subtitling', 'Voice-over',
        'Transcreation', 'Project Management', 'Other'
    ]::TEXT[]);
$$;

CREATE OR REPLACE FUNCTION public.validate_resource_service_catalog()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_supported_tms_service(NEW.service_type) THEN
        RAISE EXCEPTION 'Select a service from the shared Project service list';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_services_validate_catalog ON public.resource_services;
CREATE TRIGGER resource_services_validate_catalog
BEFORE INSERT OR UPDATE OF service_type ON public.resource_services
FOR EACH ROW EXECUTE FUNCTION public.validate_resource_service_catalog();

CREATE OR REPLACE FUNCTION public.project_job_specialization(
    p_project_id UUID,
    p_service_type TEXT
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (
            SELECT line.specialization_id
            FROM public.scope_items line
            WHERE line.project_id = p_project_id
              AND line.service_type = p_service_type
              AND line.specialization_id IS NOT NULL
            ORDER BY line.sort_order, line.created_at, line.id
            LIMIT 1
        ),
        (
            SELECT link.specialization_id
            FROM public.project_specializations link
            WHERE link.project_id = p_project_id
            ORDER BY link.created_at, link.specialization_id
            LIMIT 1
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.inherit_project_job_specialization()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_specialization_id UUID;
BEGIN
    v_specialization_id := public.project_job_specialization(
        NEW.project_id,
        NEW.service_type
    );
    IF v_specialization_id IS NULL THEN
        RAISE EXCEPTION 'Add a specialization to the Project before creating or updating a Job';
    END IF;
    NEW.specialization_id := v_specialization_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_inherit_specialization ON public.project_jobs;
CREATE TRIGGER project_jobs_inherit_specialization
BEFORE INSERT OR UPDATE OF project_id, service_type, specialization_id
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.inherit_project_job_specialization();

-- Align existing Jobs once. Issued PO versions remain immutable audit records.
SELECT set_config('retodo.job_overview_edit', 'on', TRUE);
UPDATE public.project_jobs
SET specialization_id = specialization_id;

CREATE OR REPLACE FUNCTION public.prevent_past_job_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.deadline IS NOT NULL
       AND NEW.deadline < NOW()
       AND (
           TG_OP = 'INSERT'
           OR NEW.deadline IS DISTINCT FROM OLD.deadline
           OR NEW.resource_id IS DISTINCT FROM OLD.resource_id
       ) THEN
        RAISE EXCEPTION 'Resource deadline cannot be in the past';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_prevent_past_deadline ON public.project_jobs;
CREATE TRIGGER project_jobs_prevent_past_deadline
BEFORE INSERT OR UPDATE OF deadline, resource_id ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.prevent_past_job_deadline();

ALTER TABLE public.resource_rates
    ADD COLUMN IF NOT EXISTS account_id UUID
    REFERENCES public.client_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS resource_rates_account_id_idx
    ON public.resource_rates(account_id)
    WHERE account_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.save_scoped_resource_rate_card(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base_id UUID;
    v_account_id UUID := NULLIF(p_payload->>'account_id', '')::UUID;
BEGIN
    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.client_accounts account
        WHERE account.id = v_account_id
          AND account.active
    ) THEN
        RAISE EXCEPTION 'Select an active Account for this Supplier rate card';
    END IF;

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

CREATE OR REPLACE FUNCTION public.validate_job_rate_account_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rate_account_id UUID;
    v_project_account_id UUID;
BEGIN
    IF NEW.resource_rate_id IS NULL THEN RETURN NEW; END IF;

    SELECT rate.account_id INTO v_rate_account_id
    FROM public.resource_rates rate
    WHERE rate.id = NEW.resource_rate_id;

    IF v_rate_account_id IS NULL THEN RETURN NEW; END IF;

    SELECT project.account_id INTO v_project_account_id
    FROM public.projects project
    WHERE project.id = NEW.project_id;

    IF v_rate_account_id IS DISTINCT FROM v_project_account_id THEN
        RAISE EXCEPTION 'The selected Supplier rate card belongs to a different Account';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_validate_rate_account ON public.project_jobs;
CREATE TRIGGER project_jobs_validate_rate_account
BEFORE INSERT OR UPDATE OF project_id, resource_rate_id ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.validate_job_rate_account_scope();

-- The Job trigger also listens to CAT changes. This closes the gap where a
-- live draft total changed on the Job but the stored Project expense remained
-- on the previous set of Jobs.
DROP TRIGGER IF EXISTS project_jobs_recalculate_expense ON public.project_jobs;
CREATE TRIGGER project_jobs_recalculate_expense
AFTER INSERT OR UPDATE OF project_id, supplier_amount, status, cat_analysis,
    resource_rate_id OR DELETE
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.recalculate_project_expense();

CREATE OR REPLACE FUNCTION public.sync_project_financials_from_po()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_id UUID;
BEGIN
    v_project_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.project_id ELSE NEW.project_id END;
    IF v_project_id IS NOT NULL THEN
        PERFORM public.refresh_project_financials(v_project_id);
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.project_id IS DISTINCT FROM NEW.project_id
       AND OLD.project_id IS NOT NULL THEN
        PERFORM public.refresh_project_financials(OLD.project_id);
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_pos_sync_project_financials
    ON public.supplier_purchase_orders;
CREATE TRIGGER supplier_pos_sync_project_financials
AFTER INSERT OR UPDATE OF project_id, job_id, total, status OR DELETE
ON public.supplier_purchase_orders
FOR EACH ROW EXECUTE FUNCTION public.sync_project_financials_from_po();

DO $$
DECLARE
    v_project_id UUID;
BEGIN
    FOR v_project_id IN SELECT id FROM public.projects LOOP
        PERFORM public.refresh_project_financials(v_project_id);
    END LOOP;
END;
$$;

COMMIT;
