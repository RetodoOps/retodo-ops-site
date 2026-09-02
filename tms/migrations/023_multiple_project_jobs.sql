-- RetodoOps TMS — atomic creation of multiple independent Jobs per Project.
-- Run after 022_project_profit_and_po_cost_sync.sql.

BEGIN;

-- Project and Job identity never change after creation. This prevents a Job
-- creation/edit path from being able to repurpose an existing production Job.
CREATE OR REPLACE FUNCTION public.protect_project_job_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.project_id IS DISTINCT FROM OLD.project_id THEN
        RAISE EXCEPTION 'A Job cannot be moved to another Project';
    END IF;
    IF NEW.job_number IS DISTINCT FROM OLD.job_number THEN
        RAISE EXCEPTION 'Job number is a permanent technical reference';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_protect_identity ON public.project_jobs;
CREATE TRIGGER project_jobs_protect_identity
BEFORE UPDATE OF project_id, job_number ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.protect_project_job_identity();

-- A dedicated creation transaction guarantees that every click creates a new
-- row and obtains the next per-Project sequence even under concurrent requests.
CREATE OR REPLACE FUNCTION public.create_project_job(
    p_project_id UUID,
    p_payload JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_job_id UUID;
    v_job_number TEXT;
    v_sequence INTEGER;
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
    v_specialization_id UUID := NULLIF(p_payload->>'specialization_id', '')::UUID;
    v_unit TEXT := COALESCE(NULLIF(btrim(p_payload->>'unit'), ''), 'Source words');
    v_quantity NUMERIC := NULLIF(p_payload->>'quantity', '')::NUMERIC;
    v_deadline TIMESTAMPTZ := NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    SELECT * INTO v_project
    FROM public.projects
    WHERE id = p_project_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF v_service IS NULL THEN RAISE EXCEPTION 'Job service is required'; END IF;
    IF v_specialization_id IS NULL THEN
        RAISE EXCEPTION 'Job specialization is required';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.project_specializations link
        WHERE link.project_id = p_project_id
          AND link.specialization_id = v_specialization_id
    ) THEN
        RAISE EXCEPTION 'The Job specialization must belong to the Project';
    END IF;
    IF v_unit NOT IN (
        'Source words', 'Target words', 'Hours', 'Pages', 'Minutes', 'Fixed fee'
    ) THEN
        RAISE EXCEPTION 'Unsupported Job unit';
    END IF;
    IF v_quantity IS NOT NULL AND v_quantity < 0 THEN
        RAISE EXCEPTION 'Job quantity cannot be negative';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_project_id::TEXT || ':job'));
    SELECT GREATEST(
        COALESCE(max(
            NULLIF(substring(job_number FROM '-J([0-9]+)$'), '')::INTEGER
        ), 0),
        count(*)::INTEGER
    ) + 1
    INTO v_sequence
    FROM public.project_jobs
    WHERE project_id = p_project_id;

    v_job_number := v_project.display_name || '-J' ||
        lpad(v_sequence::TEXT, 2, '0');

    INSERT INTO public.project_jobs(
        id, project_id, job_number, resource_id, service_type,
        source_language, target_language, specialization_id, status,
        deadline, quantity, unit, supplier_rate, supplier_currency,
        supplier_amount, po_required, notes, created_by
    ) VALUES (
        gen_random_uuid(), p_project_id, v_job_number, NULL, v_service,
        v_project.source_language, v_project.target_language,
        v_specialization_id, 'Unassigned', v_deadline, v_quantity, v_unit,
        NULL, COALESCE(v_project.currency, 'EUR'), 0,
        COALESCE((p_payload->>'po_required')::BOOLEAN, TRUE),
        NULLIF(btrim(p_payload->>'notes'), ''), auth.uid()
    )
    RETURNING id INTO v_job_id;

    -- The existing expense trigger includes every non-cancelled Job. Refreshing
    -- explicitly also repairs a Project if a previous client-side creation path
    -- left its stored roll-up stale.
    PERFORM public.refresh_project_financials(p_project_id);
    RETURN v_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_job(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_job(UUID, JSONB) TO authenticated;

-- Recalculate existing Projects so the stored expense equals the sum of each
-- active Job's current PO total (or supplier_amount when no PO exists).
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
