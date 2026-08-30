-- RetodoOps TMS — precise Resource assignment validation messages.
-- Run after 017_repair_client_rate_card_base_structure.sql.

BEGIN;

-- Assignment readiness is a Resource-profile invariant, not a PO-stage rule.
-- Repair legacy invalid records without touching their historical work.
UPDATE public.resources
SET resource_status = 'Onboarding', updated_at = NOW()
WHERE resource_status IN ('Assignable', 'Proven', 'Preferred')
  AND NULLIF(btrim(email), '') IS NULL;

CREATE OR REPLACE FUNCTION public.require_email_for_assignable_resource()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.resource_status IN ('Assignable', 'Proven', 'Preferred')
       AND NULLIF(btrim(NEW.email), '') IS NULL THEN
        RAISE EXCEPTION 'Add a Resource email address before using status %', NEW.resource_status;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resources_require_email_for_assignment ON public.resources;
CREATE TRIGGER resources_require_email_for_assignment
BEFORE INSERT OR UPDATE OF resource_status, email ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.require_email_for_assignable_resource();

CREATE OR REPLACE FUNCTION public.assign_job_and_issue_po(
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
    v_job public.project_jobs%ROWTYPE;
    v_resource public.resources%ROWTYPE;
    v_current_po public.supplier_purchase_orders%ROWTYPE;
    v_offer_id UUID;
    v_po_id UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    IF NOT v_job.po_required THEN RAISE EXCEPTION 'Enable Supplier PO required before assigning an External Resource'; END IF;

    SELECT * INTO v_resource FROM public.resources WHERE id = p_resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Selected Resource not found'; END IF;
    IF v_resource.lifecycle_status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'The selected Resource lifecycle is %. Change it to Active before assignment', COALESCE(v_resource.lifecycle_status, 'not set');
    END IF;
    IF v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred') THEN
        RAISE EXCEPTION 'The selected Resource status is %. Use Assignable, Proven or Preferred before assignment', COALESCE(v_resource.resource_status, 'not set');
    END IF;
    IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
        RAISE EXCEPTION 'The selected Resource profile is not assignment-ready because its email address is missing';
    END IF;

    SELECT * INTO v_current_po FROM public.supplier_purchase_orders
    WHERE job_id = p_job_id AND status IN ('Draft', 'Issued', 'Acknowledged')
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
    IF FOUND THEN
        IF v_job.resource_id = p_resource_id THEN
            RAISE EXCEPTION 'This Resource is already assigned. Save Job changes to create the next PO version';
        END IF;
        IF NULLIF(btrim(p_reassignment_reason), '') IS NULL THEN
            RAISE EXCEPTION 'A reason is required when replacing an assigned Resource';
        END IF;
        PERFORM public.cancel_job_supplier_po(p_job_id, p_reassignment_reason);
    ELSIF v_job.resource_id IS NOT NULL THEN
        IF v_job.resource_id = p_resource_id THEN RAISE EXCEPTION 'This Resource is already assigned'; END IF;
        IF NULLIF(btrim(p_reassignment_reason), '') IS NULL THEN
            RAISE EXCEPTION 'A reason is required when replacing an assigned Resource';
        END IF;
        PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
        UPDATE public.project_jobs SET resource_id = NULL, assigned_from_offer_id = NULL,
            status = 'Unassigned', accepted_at = NULL, supplier_rate = NULL,
            supplier_amount = 0, resource_rate_id = NULL, cat_analysis = NULL,
            updated_at = NOW() WHERE id = p_job_id;
    END IF;

    UPDATE public.job_offers SET status = 'Withdrawn', responded_at = NOW(),
        decline_reason = 'Replaced by direct PO assignment'
    WHERE job_id = p_job_id AND status IN ('Draft', 'Sent', 'Viewed');

    v_offer_id := public.create_job_offer_from_rate(
        p_job_id, p_resource_id, p_resource_rate_id, NOW(), NULL,
        'Direct assignment confirmed operationally; Supplier PO issued',
        FALSE, FALSE, NULL, p_cat_rows
    );
    UPDATE public.job_offers SET status = 'Sent', sent_at = NOW() WHERE id = v_offer_id;
    v_po_id := public.respond_job_offer(v_offer_id, 'Accepted', NULL);
    RETURN v_po_id;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_job_and_issue_po(UUID, UUID, UUID, JSONB, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_job_and_issue_po(UUID, UUID, UUID, JSONB, TEXT) TO authenticated;

COMMIT;
