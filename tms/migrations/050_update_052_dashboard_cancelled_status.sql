-- Retodo Ops TMS — Update 052
-- Allow an explicit Cancelled production status for both Projects and Scoops.
-- Existing rows and automatic status rules are preserved.

BEGIN;

ALTER TABLE public.projects
    DROP CONSTRAINT IF EXISTS projects_new_status_check;
ALTER TABLE public.projects
    ADD CONSTRAINT projects_new_status_check CHECK (status IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting', 'Ready to Deliver',
        'Delivered to Client', 'Approved', 'Cancelled'
    ));

ALTER TABLE public.project_scoops
    DROP CONSTRAINT IF EXISTS project_scoops_status_check;
ALTER TABLE public.project_scoops
    ADD CONSTRAINT project_scoops_status_check CHECK (status IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting', 'Ready to Deliver',
        'Delivered to Client', 'Approved', 'Cancelled'
    ));

COMMENT ON CONSTRAINT projects_new_status_check ON public.projects IS
    'Production status, including explicit operational cancellation (Update 052).';
COMMENT ON CONSTRAINT project_scoops_status_check ON public.project_scoops IS
    'Scoop production status, including manual cancellation (Update 052).';

COMMIT;
