-- RetodoOps TMS — Update 038
-- Job language inheritance/editability, manual flat-fee assignment and PO labels.
-- Run after migration 034_internal_resources_scoop_deadlines_and_context_numbers.sql.

BEGIN;

-- ---------------------------------------------------------------------------
-- A PO display name is its PO number. Project and Job identifiers remain
-- available in their own fields and in the immutable job/PO snapshots.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_supplier_po_display_name(p_po_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po_number TEXT;
BEGIN
    SELECT po_number
    INTO v_po_number
    FROM public.supplier_purchase_orders
    WHERE id = p_po_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    UPDATE public.supplier_purchase_orders
    SET display_name = COALESCE(NULLIF(btrim(v_po_number), ''), 'Supplier PO'),
        updated_at = NOW()
    WHERE id = p_po_id
      AND display_name IS DISTINCT FROM COALESCE(NULLIF(btrim(v_po_number), ''), 'Supplier PO');
END;
$$;

DO $$
DECLARE
    v_po_id UUID;
BEGIN
    FOR v_po_id IN SELECT id FROM public.supplier_purchase_orders LOOP
        PERFORM public.refresh_supplier_po_display_name(v_po_id);
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Allow a Resource to be assigned when no approved matching rate card exists.
-- The assignment is represented as one Fixed fee line and still uses the
-- existing offer acceptance, PO version and email-audit workflow.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_job_and_issue_po_flat_fee(
    p_job_id UUID,
    p_resource_id UUID,
    p_flat_fee NUMERIC,
    p_currency TEXT DEFAULT NULL,
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
    v_currency TEXT;
    v_analysis JSONB;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF p_flat_fee IS NULL OR p_flat_fee <= 0 THEN
        RAISE EXCEPTION 'Manual flat fee must be greater than zero';
    END IF;

    SELECT *
    INTO v_job
    FROM public.project_jobs
    WHERE id = p_job_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job not found';
    END IF;
    IF NOT v_job.po_required THEN
        RAISE EXCEPTION 'Enable Supplier PO required before assigning an External Resource';
    END IF;

    SELECT *
    INTO v_resource
    FROM public.resources
    WHERE id = p_resource_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Selected Resource not found';
    END IF;
    IF v_resource.lifecycle_status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'The selected Resource lifecycle is %. Change it to Active before assignment',
            COALESCE(v_resource.lifecycle_status, 'not set');
    END IF;
    IF v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred') THEN
        RAISE EXCEPTION 'The selected Resource status is %. Use Assignable, Proven or Preferred before assignment',
            COALESCE(v_resource.resource_status, 'not set');
    END IF;
    IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
        RAISE EXCEPTION 'The selected Resource profile is not assignment-ready because its email address is missing';
    END IF;

    SELECT *
    INTO v_current_po
    FROM public.supplier_purchase_orders
    WHERE job_id = p_job_id
      AND status IN ('Draft', 'Issued', 'Acknowledged')
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
        IF v_job.resource_id = p_resource_id THEN
            RAISE EXCEPTION 'This Resource is already assigned. Save Job changes to create the next PO version';
        END IF;
        IF NULLIF(btrim(p_reassignment_reason), '') IS NULL THEN
            RAISE EXCEPTION 'A reason is required when replacing an assigned Resource';
        END IF;
        PERFORM public.cancel_job_supplier_po(p_job_id, p_reassignment_reason);
    ELSIF v_job.resource_id IS NOT NULL THEN
        IF v_job.resource_id = p_resource_id THEN
            RAISE EXCEPTION 'This Resource is already assigned';
        END IF;
        IF NULLIF(btrim(p_reassignment_reason), '') IS NULL THEN
            RAISE EXCEPTION 'A reason is required when replacing an assigned Resource';
        END IF;
        PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
        UPDATE public.project_jobs
        SET resource_id = NULL,
            assigned_from_offer_id = NULL,
            status = 'Unassigned',
            accepted_at = NULL,
            supplier_rate = NULL,
            supplier_amount = 0,
            resource_rate_id = NULL,
            cat_analysis = NULL,
            updated_at = NOW()
        WHERE id = p_job_id;
    END IF;

    UPDATE public.job_offers
    SET status = 'Withdrawn',
        responded_at = NOW(),
        decline_reason = 'Replaced by manual flat-fee assignment'
    WHERE job_id = p_job_id
      AND status IN ('Draft', 'Sent', 'Viewed');

    v_currency := COALESCE(
        NULLIF(btrim(p_currency), ''),
        NULLIF(btrim(v_job.supplier_currency), ''),
        'EUR'
    );
    v_analysis := jsonb_build_object(
        'mode', 'Flat fee',
        'quantity', 1,
        'total', round(p_flat_fee, 2),
        'currency', v_currency,
        'base_rate_id', NULL,
        'rows', jsonb_build_array(jsonb_build_object(
            'resource_rate_id', NULL,
            'cat_band', NULL,
            'unit', 'Fixed fee',
            'quantity', 1,
            'unit_price', p_flat_fee,
            'amount', round(p_flat_fee, 2),
            'currency', v_currency
        ))
    );

    v_offer_id := public.create_job_offer(
        p_job_id,
        p_resource_id,
        NOW(),
        'Fixed fee',
        1,
        p_flat_fee,
        v_currency,
        'Manual flat-fee assignment; no approved matching Supplier rate card',
        FALSE,
        FALSE,
        NULL
    );

    UPDATE public.job_offers
    SET status = 'Sent',
        sent_at = NOW(),
        resource_rate_id = NULL,
        cat_analysis = v_analysis
    WHERE id = v_offer_id;

    v_po_id := public.respond_job_offer(v_offer_id, 'Accepted', NULL);
    RETURN v_po_id;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_job_and_issue_po_flat_fee(
    UUID, UUID, NUMERIC, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_job_and_issue_po_flat_fee(
    UUID, UUID, NUMERIC, TEXT, TEXT
) TO authenticated;

COMMIT;
