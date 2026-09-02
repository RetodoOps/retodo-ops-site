-- RetodoOps TMS — service-aware Job numbers for multi-Job Projects.
-- Run after 023_multiple_project_jobs.sql.

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
        WHEN 'project management' THEN 'PM'
        ELSE 'OTH'
    END;
$$;

-- The identity guard is restored immediately after the one-time rename.
DROP TRIGGER IF EXISTS project_jobs_protect_identity ON public.project_jobs;

WITH numbered AS (
    SELECT
        job.id,
        project.display_name,
        public.job_service_code(job.service_type) AS service_code,
        row_number() OVER (
            PARTITION BY job.project_id
            ORDER BY
                COALESCE(
                    NULLIF(substring(job.job_number FROM '[-_]J([0-9]+)$'), '')::INTEGER,
                    2147483647
                ),
                job.created_at,
                job.id
        ) AS sequence_number
    FROM public.project_jobs job
    JOIN public.projects project ON project.id = job.project_id
)
UPDATE public.project_jobs job
SET job_number = numbered.display_name || '-' || numbered.service_code || '_J' ||
    lpad(numbered.sequence_number::TEXT, 2, '0')
FROM numbered
WHERE numbered.id = job.id;

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

CREATE TRIGGER project_jobs_protect_identity
BEFORE UPDATE OF project_id, job_number ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.protect_project_job_identity();

-- Preserve all existing assignment, cost and workflow validation while making
-- direct inserts follow the same service-aware numbering rule as the UI RPC.
CREATE OR REPLACE FUNCTION public.prepare_project_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_project_name TEXT;
    v_sequence INTEGER;
    v_assignment_changed BOOLEAN := TG_OP = 'INSERT';
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_assignment_changed := NEW.resource_id IS DISTINCT FROM OLD.resource_id;
    END IF;

    IF TG_OP = 'INSERT' AND NULLIF(btrim(NEW.job_number), '') IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext(NEW.project_id::TEXT || ':job'));
        SELECT display_name INTO v_project_name
        FROM public.projects
        WHERE id = NEW.project_id;

        SELECT GREATEST(
            COALESCE(max(
                NULLIF(substring(job_number FROM '[-_]J([0-9]+)$'), '')::INTEGER
            ), 0),
            count(*)::INTEGER
        ) + 1
        INTO v_sequence
        FROM public.project_jobs
        WHERE project_id = NEW.project_id;

        NEW.job_number := v_project_name || '-' ||
            public.job_service_code(NEW.service_type) || '_J' ||
            lpad(v_sequence::TEXT, 2, '0');
    END IF;

    IF v_assignment_changed THEN
        NEW.restriction_warning := FALSE;
        NEW.restriction_overridden := FALSE;
        NEW.override_reason := NULL;
        NEW.overridden_by := NULL;
        NEW.overridden_at := NULL;

        IF NEW.resource_id IS NOT NULL THEN
            SELECT * INTO v_resource
            FROM public.resources
            WHERE id = NEW.resource_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Selected Resource not found';
            END IF;
            IF v_resource.lifecycle_status IS DISTINCT FROM 'Active' THEN
                RAISE EXCEPTION 'Only an Active Resource may receive a new Job assignment';
            END IF;
            IF v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred') THEN
                RAISE EXCEPTION 'Resource status must be Assignable, Proven or Preferred before assignment';
            END IF;
            IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
                RAISE EXCEPTION 'Add a Resource email address before assignment';
            END IF;
        END IF;
    END IF;

    IF jsonb_typeof(NEW.cat_analysis->'rows') = 'array'
       AND jsonb_array_length(NEW.cat_analysis->'rows') > 0 THEN
        NEW.supplier_amount := COALESCE((NEW.cat_analysis->>'total')::NUMERIC, 0);
    ELSIF COALESCE(NEW.supplier_amount, 0) = 0
       AND NEW.quantity IS NOT NULL
       AND NEW.supplier_rate IS NOT NULL THEN
        NEW.supplier_amount := round(NEW.quantity * NEW.supplier_rate, 2);
    END IF;

    IF NEW.status IN ('Assigned', 'In Progress') AND NEW.accepted_at IS NULL THEN
        NEW.accepted_at := NOW();
    END IF;
    IF NEW.status = 'Delivered' AND NEW.delivered_at IS NULL THEN
        NEW.delivered_at := NOW();
    END IF;
    IF NEW.status = 'Approved' AND NEW.approved_at IS NULL THEN
        NEW.approved_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;

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
            NULLIF(substring(job_number FROM '[-_]J([0-9]+)$'), '')::INTEGER
        ), 0),
        count(*)::INTEGER
    ) + 1
    INTO v_sequence
    FROM public.project_jobs
    WHERE project_id = p_project_id;

    v_job_number := v_project.display_name || '-' ||
        public.job_service_code(v_service) || '_J' ||
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

    PERFORM public.refresh_project_financials(p_project_id);
    RETURN v_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_job(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_job(UUID, JSONB) TO authenticated;

COMMIT;
