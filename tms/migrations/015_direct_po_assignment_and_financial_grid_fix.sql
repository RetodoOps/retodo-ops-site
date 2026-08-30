-- RetodoOps TMS — direct PO assignment, Resource reassignment and Financial grid fix.
-- Run after 014_cat_quantities_assignment_and_quick_navigation.sql.

BEGIN;

-- Some early installations already had scope_items before migration 001 and
-- therefore missed this column although the shared updated-at trigger existed.
ALTER TABLE public.scope_items
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.supplier_purchase_orders
    ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- A selected Client rate card must have a real base row matching the Project.
-- Do not silently generate a zero-price grid when its context is incompatible.
CREATE OR REPLACE FUNCTION public.replace_project_cat_grid(
    p_project_id UUID,
    p_rate_card_id UUID DEFAULT NULL,
    p_service_type TEXT DEFAULT 'Translation',
    p_specialization_id UUID DEFAULT NULL,
    p_unit TEXT DEFAULT 'Source words'
)
RETURNS SETOF public.scope_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_card public.client_rate_cards%ROWTYPE;
    v_base public.client_rate_items%ROWTYPE;
    v_rate public.client_rate_items%ROWTYPE;
    v_band TEXT;
    v_sort INTEGER := 0;
    v_source TEXT;
    v_bands CONSTANT TEXT[] := ARRAY[
        'New words', '50–74%', '75–84%', '85–94%',
        '95–99%', '100%', 'Repetitions'
    ];
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF p_service_type IS DISTINCT FROM v_project.project_type THEN
        RAISE EXCEPTION 'CAT grid service must match the Project primary service';
    END IF;
    IF p_specialization_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.project_specializations project_spec
        WHERE project_spec.project_id = p_project_id
          AND project_spec.specialization_id = p_specialization_id
    ) THEN RAISE EXCEPTION 'CAT grid specialization must belong to this Project'; END IF;

    IF p_rate_card_id IS NOT NULL THEN
        SELECT * INTO v_card FROM public.client_rate_cards card
        WHERE card.id = p_rate_card_id AND card.client_id = v_project.client_id
          AND card.active
          AND (card.account_id IS NULL OR card.account_id = v_project.account_id);
        IF NOT FOUND THEN RAISE EXCEPTION 'Selected rate card is not available for this Client/Account'; END IF;
        v_source := CASE WHEN v_card.account_id IS NULL THEN 'Client' ELSE 'Account' END;

        SELECT item.* INTO v_base FROM public.client_rate_items item
        WHERE item.rate_card_id = p_rate_card_id AND item.active
          AND item.base_rate_id IS NULL AND item.cat_band IS NULL
          AND item.service_type = p_service_type AND item.unit = p_unit
          AND (item.source_language IS NULL
               OR item.source_language = v_project.source_language
               OR v_project.source_language LIKE item.source_language || ' (%)')
          AND (item.target_language IS NULL
               OR item.target_language = v_project.target_language
               OR v_project.target_language LIKE item.target_language || ' (%)')
          AND (item.specialization_id IS NULL OR item.specialization_id = p_specialization_id)
        ORDER BY
          (item.source_language IS NOT NULL)::INTEGER DESC,
          (item.target_language IS NOT NULL)::INTEGER DESC,
          (item.specialization_id IS NOT NULL)::INTEGER DESC,
          item.updated_at DESC, item.created_at DESC
        LIMIT 1;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'The selected Client rate card has no matching base price for this Project language direction, service, specialization and unit';
        END IF;
    ELSE
        v_source := 'Manual';
    END IF;

    DELETE FROM public.scope_items line
    WHERE line.project_id = p_project_id
      AND line.service_type = p_service_type
      AND line.specialization_id = p_specialization_id
      AND line.price_unit = p_unit
      AND line.cat_band = ANY(v_bands);

    FOREACH v_band IN ARRAY v_bands LOOP
        v_sort := v_sort + 10;
        v_rate.id := NULL;
        v_rate.rate := NULL;
        IF p_rate_card_id IS NOT NULL THEN
            IF v_band = 'New words' THEN
                v_rate := v_base;
            ELSE
                SELECT item.* INTO v_rate FROM public.client_rate_items item
                WHERE item.base_rate_id = v_base.id AND item.active
                  AND regexp_replace(lower(COALESCE(item.cat_band, '')), '[^a-z0-9%]+', '', 'g')
                    = regexp_replace(lower(v_band), '[^a-z0-9%]+', '', 'g')
                ORDER BY item.updated_at DESC, item.created_at DESC LIMIT 1;
            END IF;
        END IF;

        INSERT INTO public.scope_items(
            project_id, service_type, specialization_id, quantity, price_unit,
            cat_band, unit_price, price, rate_source, override_reason,
            sort_order, client_rate_item_id
        ) VALUES (
            p_project_id, p_service_type, p_specialization_id, 0, p_unit,
            v_band, COALESCE(v_rate.rate, 0), 0, v_source,
            CASE
                WHEN p_rate_card_id IS NULL THEN 'Blank CAT grid'
                WHEN v_rate.id IS NULL THEN 'CAT discount not defined in selected rate card'
                ELSE NULL
            END,
            v_sort, v_rate.id
        );
    END LOOP;

    UPDATE public.projects project SET
        currency = CASE WHEN p_rate_card_id IS NULL THEN project.currency ELSE v_card.currency END,
        price_source = v_source,
        price_override_reason = CASE WHEN p_rate_card_id IS NULL THEN 'Blank CAT grid' ELSE NULL END,
        updated_at = NOW()
    WHERE id = p_project_id;

    RETURN QUERY SELECT line.* FROM public.scope_items line
    WHERE line.project_id = p_project_id
      AND line.service_type = p_service_type
      AND line.specialization_id = p_specialization_id
      AND line.price_unit = p_unit AND line.cat_band = ANY(v_bands)
    ORDER BY line.sort_order, line.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_project_cat_grid(UUID, UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.replace_project_cat_grid(UUID, UUID, TEXT, UUID, TEXT) TO authenticated;

-- Cancel the current PO without erasing its number, lines or earlier versions.
-- The Job becomes available for reassignment.
CREATE OR REPLACE FUNCTION public.cancel_job_supplier_po(
    p_job_id UUID,
    p_reason TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.project_jobs%ROWTYPE;
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_version INTEGER;
    v_snapshot JSONB;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'Cancellation reason is required'; END IF;
    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    SELECT * INTO v_po FROM public.supplier_purchase_orders
    WHERE job_id = p_job_id AND status IN ('Draft', 'Issued', 'Acknowledged')
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'No current Supplier PO found for this Job'; END IF;

    v_version := v_po.current_version + 1;
    UPDATE public.supplier_purchase_orders SET
        status = 'Cancelled', current_version = v_version,
        last_change_reason = btrim(p_reason), cancelled_at = NOW(), updated_at = NOW()
    WHERE id = v_po.id;
    v_snapshot := public.supplier_po_snapshot(v_po.id);
    INSERT INTO public.supplier_po_versions(
        purchase_order_id, version_number, snapshot, document_status,
        change_reason, created_by
    ) VALUES (v_po.id, v_version, v_snapshot, 'Cancelled', btrim(p_reason), auth.uid());

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs SET
        resource_id = NULL, assigned_from_offer_id = NULL, status = 'Unassigned',
        accepted_at = NULL, supplier_rate = NULL, supplier_amount = 0,
        resource_rate_id = NULL, cat_analysis = NULL, updated_at = NOW()
    WHERE id = p_job_id;
    UPDATE public.job_offers SET status = 'Withdrawn', responded_at = NOW(),
        decline_reason = 'Supplier PO cancelled: ' || btrim(p_reason)
    WHERE job_id = p_job_id AND status IN ('Draft', 'Sent', 'Viewed');
    UPDATE public.projects project SET status = 'Assign', updated_at = NOW()
    WHERE project.id = v_job.project_id AND project.status = 'Ongoing'
      AND NOT EXISTS (
          SELECT 1 FROM public.project_jobs other_job
          WHERE other_job.project_id = project.id
            AND other_job.id <> p_job_id
            AND other_job.status IN ('Assigned', 'In Progress', 'Delivered', 'Revision Required')
      );
    RETURN v_version;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_job_supplier_po(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_job_supplier_po(UUID, TEXT) TO authenticated;

-- Operational agreement already exists outside the portal. This action creates
-- an internal commercial snapshot, assigns the Resource and immediately issues
-- and queues the PO. No Resource acceptance step exists in the UI.
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
    v_current_po public.supplier_purchase_orders%ROWTYPE;
    v_offer_id UUID;
    v_po_id UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    IF NOT v_job.po_required THEN RAISE EXCEPTION 'Enable Supplier PO required before assigning an External Resource'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.resources resource
        WHERE resource.id = p_resource_id
          AND resource.lifecycle_status = 'Active'
          AND resource.resource_status IN ('Assignable', 'Proven', 'Preferred')
          AND NULLIF(btrim(resource.email), '') IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Select an Active Assignable, Proven or Preferred Resource with an email address';
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
        IF v_job.resource_id = p_resource_id THEN
            RAISE EXCEPTION 'This Resource is already assigned';
        END IF;
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
