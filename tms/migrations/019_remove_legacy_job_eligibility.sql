-- RetodoOps TMS — align direct Job assignment with the unified Resource status.
-- Run after 018_job_assignment_validation_messages.sql.

BEGIN;

-- This trigger predates resource_status and still checked assignment_approved,
-- classification and compliance. Keep its numbering, amount and timestamp
-- responsibilities, but make assignment readiness follow the current model.
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

        SELECT COALESCE(max(
            NULLIF(substring(job_number FROM '-J([0-9]+)$'), '')::INTEGER
        ), 0) + 1
        INTO v_sequence
        FROM public.project_jobs
        WHERE project_id = NEW.project_id;

        NEW.job_number := v_project_name || '-J' || lpad(v_sequence::TEXT, 2, '0');
    END IF;

    IF v_assignment_changed THEN
        -- Legacy Administrator overrides are no longer part of assignment.
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

    -- CAT totals are authoritative. Retain the legacy single-rate fallback for
    -- non-CAT Jobs only.
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

DROP TRIGGER IF EXISTS project_jobs_prepare ON public.project_jobs;
CREATE TRIGGER project_jobs_prepare
BEFORE INSERT OR UPDATE OF resource_id, status, quantity, supplier_rate,
    supplier_amount, cat_analysis, restriction_overridden, override_reason
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.prepare_project_job();

-- The second assignment guard uses the same readiness definition and supplies
-- a defensive email check for direct database writes.
CREATE OR REPLACE FUNCTION public.block_inactive_job_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
BEGIN
    IF NEW.resource_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR OLD.resource_id IS DISTINCT FROM NEW.resource_id) THEN
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
    RETURN NEW;
END;
$$;

COMMIT;
