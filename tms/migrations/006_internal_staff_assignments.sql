-- RetodoOps TMS — Internal Resource assignments for Project staff
-- Run after 005_project_financial_backfill.sql.

BEGIN;

ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS lifecycle_status TEXT NOT NULL DEFAULT 'Active';

ALTER TABLE public.resources
    DROP CONSTRAINT IF EXISTS resources_lifecycle_status_check;
ALTER TABLE public.resources
    ADD CONSTRAINT resources_lifecycle_status_check
        CHECK (lifecycle_status IN ('Active', 'On leave', 'Inactive'));

CREATE OR REPLACE FUNCTION public.apply_resource_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.lifecycle_status <> 'Active' THEN
        NEW.assignment_approved := FALSE;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resources_apply_lifecycle ON public.resources;
CREATE TRIGGER resources_apply_lifecycle
BEFORE INSERT OR UPDATE OF lifecycle_status, assignment_approved ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.apply_resource_lifecycle();

CREATE OR REPLACE FUNCTION public.block_inactive_job_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_lifecycle TEXT;
BEGIN
    IF NEW.resource_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR OLD.resource_id IS DISTINCT FROM NEW.resource_id)
    THEN
        SELECT lifecycle_status INTO v_lifecycle
        FROM public.resources
        WHERE id = NEW.resource_id;
        IF v_lifecycle <> 'Active' THEN
            RAISE EXCEPTION 'Only an Active Resource may receive a new Job assignment';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_block_inactive_resource ON public.project_jobs;
CREATE TRIGGER project_jobs_block_inactive_resource
BEFORE INSERT OR UPDATE OF resource_id ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.block_inactive_job_assignment();

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS project_manager_resource_id UUID REFERENCES public.resources(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS qa_specialist_resource_id UUID REFERENCES public.resources(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS project_coordinator_resource_id UUID REFERENCES public.resources(id) ON DELETE SET NULL;

-- The bootstrap Administrator becomes the first selectable Internal Resource.
INSERT INTO public.resources (
    internal_number, profile_id, resource_type, lifecycle_status, classification,
    assignment_approved, portal_status, legal_name, initials,
    relationship_status, eligibility_status, compliance_status,
    payment_terms_days, invoice_cycle, created_by
)
SELECT
    'RO-INT-00001', profile.id, 'Internal', 'Active', 'A — Preferred',
    TRUE, 'Active', profile.full_name,
    upper(left(split_part(profile.full_name, ' ', 1), 1)
        || left(split_part(profile.full_name, ' ', 2), 1)),
    'Internal team', 'Eligible', 'Valid', 60, '15th and 30th', profile.id
FROM public.profiles profile
WHERE profile.role = 'admin'
ORDER BY profile.id
LIMIT 1
ON CONFLICT (profile_id) DO UPDATE SET
    resource_type = 'Internal',
    lifecycle_status = 'Active',
    classification = 'A — Preferred',
    assignment_approved = TRUE,
    portal_status = 'Active',
    eligibility_status = 'Eligible',
    compliance_status = 'Valid',
    relationship_status = 'Internal team',
    updated_at = NOW();

CREATE OR REPLACE FUNCTION public.sync_project_staff_names()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_name TEXT;
    v_lifecycle TEXT;
BEGIN
    IF NEW.project_manager_resource_id IS NOT NULL THEN
        SELECT COALESCE(legal_name, company_name, internal_number), lifecycle_status
        INTO v_name, v_lifecycle
        FROM public.resources
        WHERE id = NEW.project_manager_resource_id AND resource_type = 'Internal';
        IF v_name IS NULL THEN RAISE EXCEPTION 'Project Manager must be an Internal Resource'; END IF;
        IF v_lifecycle <> 'Active'
           AND (TG_OP = 'INSERT' OR OLD.project_manager_resource_id IS DISTINCT FROM NEW.project_manager_resource_id)
        THEN RAISE EXCEPTION 'Project Manager must be an Active Internal Resource'; END IF;
        NEW.project_manager := v_name;
    ELSIF TG_OP = 'UPDATE' AND OLD.project_manager_resource_id IS NOT NULL THEN
        NEW.project_manager := NULL;
    END IF;

    IF NEW.qa_specialist_resource_id IS NOT NULL THEN
        SELECT COALESCE(legal_name, company_name, internal_number), lifecycle_status
        INTO v_name, v_lifecycle
        FROM public.resources
        WHERE id = NEW.qa_specialist_resource_id AND resource_type = 'Internal';
        IF v_name IS NULL THEN RAISE EXCEPTION 'QA Specialist must be an Internal Resource'; END IF;
        IF v_lifecycle <> 'Active'
           AND (TG_OP = 'INSERT' OR OLD.qa_specialist_resource_id IS DISTINCT FROM NEW.qa_specialist_resource_id)
        THEN RAISE EXCEPTION 'QA Specialist must be an Active Internal Resource'; END IF;
        NEW.qa_specialist := v_name;
    ELSIF TG_OP = 'UPDATE' AND OLD.qa_specialist_resource_id IS NOT NULL THEN
        NEW.qa_specialist := NULL;
    END IF;

    IF NEW.project_coordinator_resource_id IS NOT NULL THEN
        SELECT COALESCE(legal_name, company_name, internal_number), lifecycle_status
        INTO v_name, v_lifecycle
        FROM public.resources
        WHERE id = NEW.project_coordinator_resource_id AND resource_type = 'Internal';
        IF v_name IS NULL THEN RAISE EXCEPTION 'Project Coordinator must be an Internal Resource'; END IF;
        IF v_lifecycle <> 'Active'
           AND (TG_OP = 'INSERT' OR OLD.project_coordinator_resource_id IS DISTINCT FROM NEW.project_coordinator_resource_id)
        THEN RAISE EXCEPTION 'Project Coordinator must be an Active Internal Resource'; END IF;
        NEW.project_coordinator := v_name;
    ELSIF TG_OP = 'UPDATE' AND OLD.project_coordinator_resource_id IS NOT NULL THEN
        NEW.project_coordinator := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_sync_staff_names ON public.projects;
CREATE TRIGGER projects_sync_staff_names
BEFORE INSERT OR UPDATE OF project_manager_resource_id,
    qa_specialist_resource_id, project_coordinator_resource_id
ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.sync_project_staff_names();

-- Link legacy text assignments when an exact Internal Resource name exists.
UPDATE public.projects project
SET project_manager_resource_id = resource.id
FROM public.resources resource
WHERE project.project_manager_resource_id IS NULL
  AND resource.resource_type = 'Internal'
  AND lower(btrim(project.project_manager)) = lower(btrim(COALESCE(resource.legal_name, resource.company_name)));

UPDATE public.projects project
SET qa_specialist_resource_id = resource.id
FROM public.resources resource
WHERE project.qa_specialist_resource_id IS NULL
  AND resource.resource_type = 'Internal'
  AND lower(btrim(project.qa_specialist)) = lower(btrim(COALESCE(resource.legal_name, resource.company_name)));

UPDATE public.projects project
SET project_coordinator_resource_id = resource.id
FROM public.resources resource
WHERE project.project_coordinator_resource_id IS NULL
  AND resource.resource_type = 'Internal'
  AND lower(btrim(project.project_coordinator)) = lower(btrim(COALESCE(resource.legal_name, resource.company_name)));

CREATE INDEX IF NOT EXISTS projects_manager_resource_idx
    ON public.projects(project_manager_resource_id, status);

COMMIT;
