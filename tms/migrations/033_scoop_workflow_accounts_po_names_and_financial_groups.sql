-- RetodoOps TMS — Scoop workflow controls, connected PO labels, Scoop-only
-- pricing and Account-aware rate-card defaults. Run after migration 032.

BEGIN;

-- ---------------------------------------------------------------------------
-- Scoop status: automatic by default, with an explicit manual override.
-- ---------------------------------------------------------------------------
ALTER TABLE public.project_scoops
    ADD COLUMN IF NOT EXISTS status_manual BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.project_scoops
    DROP CONSTRAINT IF EXISTS project_scoops_status_check;
ALTER TABLE public.project_scoops
    ADD CONSTRAINT project_scoops_status_check CHECK (status IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting',
        'Ready to Deliver', 'Delivered to Client', 'Approved'
    ));

CREATE OR REPLACE FUNCTION public.refresh_project_scoop_status(p_scoop_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_manual BOOLEAN;
BEGIN
    SELECT COALESCE(scoop.status_manual, FALSE)
    INTO v_manual
    FROM public.project_scoops scoop
    WHERE scoop.id = p_scoop_id;

    IF NOT FOUND OR v_manual THEN
        RETURN;
    END IF;

    SELECT CASE
        WHEN count(*) = 0 THEN 'Assign'
        WHEN count(*) FILTER (WHERE job.status = 'Unassigned') = count(*)
            THEN 'Assign'
        WHEN count(*) FILTER (WHERE job.status = 'Approved') = count(*)
            THEN 'Approved'
        WHEN count(*) FILTER (WHERE job.status IN ('Delivered', 'Approved')) = count(*)
             AND count(*) FILTER (WHERE job.status = 'Delivered') > 0
            THEN 'Ready for QA'
        ELSE 'Ongoing'
    END
    INTO v_status
    FROM public.project_jobs job
    WHERE job.project_scoop_id = p_scoop_id
      AND job.status NOT IN ('Declined', 'Cancelled');

    UPDATE public.project_scoops scoop
    SET status = v_status,
        status_manual = FALSE,
        updated_at = NOW()
    WHERE scoop.id = p_scoop_id
      AND NOT scoop.status_manual
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
    IF TG_OP <> 'DELETE' THEN
        v_new_scoop_id := NEW.project_scoop_id;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        v_old_scoop_id := OLD.project_scoop_id;
    END IF;

    IF v_old_scoop_id IS NOT NULL
       AND (TG_OP = 'DELETE' OR v_old_scoop_id IS DISTINCT FROM v_new_scoop_id) THEN
        PERFORM public.refresh_project_scoop_status(v_old_scoop_id);
    END IF;
    IF v_new_scoop_id IS NOT NULL THEN
        PERFORM public.refresh_project_scoop_status(v_new_scoop_id);
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_sync_scoop_status
    ON public.project_jobs;
CREATE TRIGGER project_jobs_sync_scoop_status
AFTER INSERT OR UPDATE OF project_scoop_id, resource_id, status OR DELETE
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.sync_project_scoop_status_from_job();

-- The Scoop is the only place where client pricing is created or edited.
-- The dashboard wrapper still accepts the legacy payload shape, but forces
-- the newly created Project price to zero.
CREATE OR REPLACE FUNCTION public.create_project_with_specializations(p_payload JSONB)
RETURNS TABLE (created_project_id UUID, created_project_name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_name TEXT;
    v_account_id UUID := NULLIF(p_payload->>'account_id', '')::UUID;
    v_count INTEGER;
    v_project_payload JSONB := (
        COALESCE(p_payload, '{}'::JSONB)
        - 'price'
        - 'price_source'
        - 'price_override_reason'
    ) || jsonb_build_object('price', 0);
BEGIN
    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.client_account_specializations
        WHERE account_id = v_account_id
    ) THEN
        RAISE EXCEPTION 'Configure at least one specialization on the selected Account';
    END IF;

    IF v_account_id IS NULL
       AND jsonb_array_length(COALESCE(p_payload->'specialization_ids', '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'Select at least one Project specialization';
    END IF;

    SELECT result.created_project_id, result.created_project_name
    INTO v_id, v_name
    FROM public.create_project(v_project_payload) result
    LIMIT 1;

    IF v_account_id IS NULL THEN
        INSERT INTO public.project_specializations (
            project_id, specialization_id, source
        )
        SELECT v_id, spec.id, 'Manual'
        FROM jsonb_array_elements_text(p_payload->'specialization_ids') requested(id)
        JOIN public.specializations spec
          ON spec.id = requested.id::UUID
         AND spec.active
        ON CONFLICT DO NOTHING;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count = 0 THEN
            RAISE EXCEPTION 'Select at least one valid Project specialization';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.project_specializations
        WHERE project_id = v_id
    ) THEN
        RAISE EXCEPTION 'Project specialization is required';
    END IF;

    created_project_id := v_id;
    created_project_name := v_name;
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_with_specializations(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_with_specializations(JSONB) TO authenticated;

-- Allow a new manual Scoop line to be saved without an explanatory reason.
CREATE OR REPLACE FUNCTION public.save_scoop_financial_lines(
    p_scoop_id UUID,
    p_lines JSONB,
    p_deleted_ids JSONB DEFAULT '[]'::JSONB,
    p_fallback_price NUMERIC DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_scoop public.project_scoops%ROWTYPE;
    v_line JSONB;
    v_id UUID;
    v_existing public.scope_items%ROWTYPE;
    v_description TEXT;
    v_source TEXT;
    v_reason TEXT;
    v_specialization UUID;
    v_rate_id UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT *
    INTO v_scoop
    FROM public.project_scoops
    WHERE id = p_scoop_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Scoop not found';
    END IF;
    IF jsonb_typeof(COALESCE(p_lines, '[]'::JSONB)) <> 'array'
       OR jsonb_typeof(COALESCE(p_deleted_ids, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Financial lines must be JSON arrays';
    END IF;

    DELETE FROM public.scope_items line
    WHERE line.project_scoop_id = p_scoop_id
      AND line.id IN (
          SELECT value::UUID
          FROM jsonb_array_elements_text(COALESCE(p_deleted_ids, '[]'::JSONB))
      );

    FOR v_line IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
    LOOP
        v_id := NULLIF(v_line->>'id', '')::UUID;
        v_rate_id := NULLIF(v_line->>'client_rate_item_id', '')::UUID;
        v_description := NULLIF(btrim(v_line->>'description'), '');
        v_source := COALESCE(NULLIF(btrim(v_line->>'rate_source'), ''), 'Manual');
        v_reason := NULLIF(btrim(v_line->>'override_reason'), '');
        v_specialization := NULLIF(v_line->>'specialization_id', '')::UUID;

        IF v_description IS NULL THEN
            RAISE EXCEPTION 'Every Scoop financial line requires a description';
        END IF;
        IF v_specialization IS NULL THEN
            RAISE EXCEPTION 'Every Scoop financial line requires a specialization';
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM public.project_specializations link
            WHERE link.project_id = v_scoop.project_id
              AND link.specialization_id = v_specialization
        ) THEN
            RAISE EXCEPTION 'Financial line specialization must belong to the Project';
        END IF;

        IF v_id IS NOT NULL THEN
            SELECT *
            INTO v_existing
            FROM public.scope_items
            WHERE id = v_id
              AND project_scoop_id = p_scoop_id
            FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Scoop financial line not found';
            END IF;

            IF v_existing.client_rate_item_id IS NOT NULL THEN
                UPDATE public.scope_items
                SET quantity = COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 0),
                    updated_at = NOW()
                WHERE id = v_id;
            ELSE
                UPDATE public.scope_items
                SET description = v_description,
                    service_type = COALESCE(NULLIF(v_line->>'service_type', ''), service_type),
                    specialization_id = v_specialization,
                    cat_band = NULLIF(v_line->>'cat_band', ''),
                    quantity = COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 0),
                    price_unit = COALESCE(NULLIF(v_line->>'price_unit', ''), 'Source words'),
                    unit_price = COALESCE(NULLIF(v_line->>'unit_price', '')::NUMERIC, 0),
                    rate_source = v_source,
                    adjustment_type = NULLIF(v_line->>'adjustment_type', ''),
                    override_reason = v_reason,
                    sort_order = COALESCE(NULLIF(v_line->>'sort_order', '')::INTEGER, sort_order),
                    updated_at = NOW()
                WHERE id = v_id;
            END IF;
        ELSE
            IF v_source IN ('Account', 'Client') AND v_rate_id IS NULL THEN
                RAISE EXCEPTION 'A linked Client or Account line requires a rate-card row';
            END IF;
            INSERT INTO public.scope_items (
                project_id, project_scoop_id, description, service_type,
                specialization_id, cat_band, quantity, price_unit, unit_price,
                price, rate_source, adjustment_type, override_reason,
                client_rate_item_id, sort_order
            )
            VALUES (
                v_scoop.project_id, p_scoop_id, v_description,
                COALESCE(NULLIF(v_line->>'service_type', ''), 'Other'),
                v_specialization, NULLIF(v_line->>'cat_band', ''),
                COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 0),
                COALESCE(NULLIF(v_line->>'price_unit', ''), 'Source words'),
                COALESCE(NULLIF(v_line->>'unit_price', '')::NUMERIC, 0), 0,
                v_source, NULLIF(v_line->>'adjustment_type', ''), v_reason,
                v_rate_id, COALESCE(NULLIF(v_line->>'sort_order', '')::INTEGER, 0)
            );
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1
        FROM public.scope_items
        WHERE project_scoop_id = p_scoop_id
    ) THEN
        UPDATE public.project_scoops
        SET price = GREATEST(COALESCE(p_fallback_price, 0), 0),
            updated_at = NOW()
        WHERE id = p_scoop_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.save_scoop_financial_lines(UUID, JSONB, JSONB, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_scoop_financial_lines(UUID, JSONB, JSONB, NUMERIC) TO authenticated;

-- Extend the existing Scoop update RPC with status override support while
-- retaining language propagation and immutable PO history.
CREATE OR REPLACE FUNCTION public.update_project_scoop(
    p_scoop_id UUID,
    p_payload JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payload JSONB := COALESCE(p_payload, '{}'::JSONB);
    v_scoop public.project_scoops%ROWTYPE;
    v_source TEXT := NULLIF(btrim(v_payload->>'source_language'), '');
    v_target TEXT := NULLIF(btrim(v_payload->>'target_language'), '');
    v_deadline TIMESTAMPTZ := NULLIF(v_payload->>'deadline', '')::TIMESTAMPTZ;
    v_price NUMERIC;
    v_status TEXT := NULLIF(btrim(v_payload->>'status'), '');
    v_status_manual BOOLEAN;
    v_is_primary BOOLEAN;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    SELECT *
    INTO v_scoop
    FROM public.project_scoops
    WHERE id = p_scoop_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Scoop not found';
    END IF;

    v_price := COALESCE(
        NULLIF(v_payload->>'price', '')::NUMERIC,
        v_scoop.price,
        0
    );
    IF v_payload ? 'status_manual' THEN
        v_status_manual := COALESCE(NULLIF(v_payload->>'status_manual', '')::BOOLEAN, FALSE);
    ELSE
        v_status_manual := COALESCE(v_scoop.status_manual, FALSE);
    END IF;
    IF v_status IS NOT NULL AND NOT (v_payload ? 'status_manual') THEN
        v_status_manual := TRUE;
    END IF;
    IF v_status_manual AND v_status IS NULL THEN
        v_status := COALESCE(v_scoop.status, 'Assign');
    END IF;

    IF v_source IS NULL OR v_target IS NULL THEN
        RAISE EXCEPTION 'Source and Target languages are required';
    END IF;
    IF v_source = v_target THEN
        RAISE EXCEPTION 'Source and Target languages must be different';
    END IF;
    IF v_deadline IS NOT NULL
       AND v_deadline < NOW()
       AND v_deadline IS DISTINCT FROM v_scoop.deadline THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;
    IF v_price < 0 THEN
        RAISE EXCEPTION 'Scoop price cannot be negative';
    END IF;
    IF v_status_manual AND v_status NOT IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting',
        'Ready to Deliver', 'Delivered to Client', 'Approved'
    ) THEN
        RAISE EXCEPTION 'Invalid Scoop status';
    END IF;

    UPDATE public.project_scoops
    SET source_language = v_source,
        target_language = v_target,
        deadline = v_deadline,
        price = v_price,
        status = CASE WHEN v_status_manual THEN v_status ELSE status END,
        status_manual = v_status_manual,
        updated_at = NOW()
    WHERE id = p_scoop_id;

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs
    SET source_language = v_source,
        target_language = v_target,
        updated_at = NOW()
    WHERE project_scoop_id = p_scoop_id;

    SELECT NOT EXISTS (
        SELECT 1
        FROM public.project_scoops earlier
        WHERE earlier.project_id = v_scoop.project_id
          AND (earlier.created_at, earlier.id) <
              (v_scoop.created_at, v_scoop.id)
    )
    INTO v_is_primary;

    IF v_is_primary THEN
        UPDATE public.projects
        SET source_language = v_source,
            source_language_code = public.tms_language_code(v_source),
            target_language = v_target,
            target_language_code = public.tms_language_code(v_target),
            deadline = COALESCE(v_deadline, deadline),
            updated_at = NOW()
        WHERE id = v_scoop.project_id;
    END IF;

    IF NOT v_status_manual THEN
        PERFORM public.refresh_project_scoop_status(p_scoop_id);
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_project_scoop(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_project_scoop(UUID, JSONB) TO authenticated;

-- ---------------------------------------------------------------------------
-- Connected PO labels. po_number remains the immutable technical sequence.
-- ---------------------------------------------------------------------------
ALTER TABLE public.supplier_purchase_orders
    ADD COLUMN IF NOT EXISTS display_name TEXT;

CREATE OR REPLACE FUNCTION public.refresh_supplier_po_display_name(p_po_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job_number TEXT;
    v_project_name TEXT;
    v_po_number TEXT;
    v_display_name TEXT;
BEGIN
    SELECT po.po_number, job.job_number, project.display_name
    INTO v_po_number, v_job_number, v_project_name
    FROM public.supplier_purchase_orders po
    LEFT JOIN public.project_jobs job ON job.id = po.job_id
    LEFT JOIN public.projects project ON project.id = po.project_id
    WHERE po.id = p_po_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    v_display_name := concat_ws(
        ' · ',
        COALESCE(
            NULLIF(btrim(v_job_number), ''),
            NULLIF(btrim(v_project_name), ''),
            'Supplier PO'
        ),
        NULLIF(btrim(v_po_number), '')
    );

    UPDATE public.supplier_purchase_orders
    SET display_name = v_display_name,
        updated_at = NOW()
    WHERE id = p_po_id
      AND display_name IS DISTINCT FROM v_display_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_supplier_po_display_name_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.refresh_supplier_po_display_name(NEW.id);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_supplier_po_display_names_for_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po_id UUID;
BEGIN
    FOR v_po_id IN
        SELECT id
        FROM public.supplier_purchase_orders
        WHERE job_id = NEW.id
    LOOP
        PERFORM public.refresh_supplier_po_display_name(v_po_id);
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_supplier_po_display_names_for_project()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po_id UUID;
BEGIN
    FOR v_po_id IN
        SELECT id
        FROM public.supplier_purchase_orders
        WHERE project_id = NEW.id
    LOOP
        PERFORM public.refresh_supplier_po_display_name(v_po_id);
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_pos_refresh_display_name
    ON public.supplier_purchase_orders;
CREATE TRIGGER supplier_pos_refresh_display_name
AFTER INSERT OR UPDATE OF project_id, job_id, po_number
ON public.supplier_purchase_orders
FOR EACH ROW EXECUTE FUNCTION public.refresh_supplier_po_display_name_trigger();

DROP TRIGGER IF EXISTS project_jobs_refresh_po_display_name
    ON public.project_jobs;
CREATE TRIGGER project_jobs_refresh_po_display_name
AFTER UPDATE OF job_number, project_id
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.refresh_supplier_po_display_names_for_job();

DROP TRIGGER IF EXISTS projects_refresh_po_display_name
    ON public.projects;
CREATE TRIGGER projects_refresh_po_display_name
AFTER UPDATE OF project_number, display_name
ON public.projects
FOR EACH ROW
EXECUTE FUNCTION public.refresh_supplier_po_display_names_for_project();

CREATE OR REPLACE FUNCTION public.supplier_po_snapshot(p_po_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'po_number', po.po_number,
        'display_name', COALESCE(
            po.display_name,
            concat_ws(' · ', COALESCE(job.job_number, project.display_name, 'Supplier PO'), po.po_number)
        ),
        'status', po.status,
        'version', po.current_version,
        'resource_id', po.resource_id,
        'project_id', po.project_id,
        'job_id', po.job_id,
        'currency', po.currency,
        'supplier', po.supplier_snapshot,
        'job', CASE WHEN job.id IS NULL THEN NULL ELSE jsonb_build_object(
            'job_number', job.job_number,
            'service_type', job.service_type,
            'source_language', job.source_language,
            'target_language', job.target_language,
            'specialization_id', job.specialization_id,
            'deadline', job.deadline,
            'quantity', job.quantity,
            'unit', job.unit
        ) END,
        'subtotal', po.subtotal,
        'adjustment_amount', po.adjustment_amount,
        'total', po.total,
        'work_may_begin_before_acknowledgement', po.work_may_begin_before_acknowledgement,
        'lines', COALESCE((
            SELECT jsonb_agg(to_jsonb(line) - 'created_at' - 'updated_at'
                ORDER BY line.sort_order, line.id)
            FROM public.supplier_po_lines line
            WHERE line.purchase_order_id = po.id
        ), '[]'::JSONB)
    )
    FROM public.supplier_purchase_orders po
    LEFT JOIN public.project_jobs job ON job.id = po.job_id
    LEFT JOIN public.projects project ON project.id = po.project_id
    WHERE public.is_company_user()
      AND po.id = p_po_id;
$$;

-- Keep queued PO subjects connected even when a legacy RPC supplies only the
-- technical number.
CREATE OR REPLACE FUNCTION public.tag_supplier_po_email_queue()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_label TEXT;
BEGIN
    IF NEW.direction <> 'Outgoing'
       OR NEW.job_id IS NULL
       OR NEW.status <> 'Draft requested'
       OR (NEW.purchase_order_id IS NULL
           AND COALESCE(NEW.subject, '') NOT ILIKE '%purchase order%') THEN
        RETURN NEW;
    END IF;

    SELECT *
    INTO v_po
    FROM public.supplier_purchase_orders po
    WHERE (NEW.purchase_order_id IS NOT NULL AND po.id = NEW.purchase_order_id)
       OR (NEW.purchase_order_id IS NULL
           AND po.job_id = NEW.job_id
           AND po.resource_id = NEW.resource_id
           AND po.status IN ('Issued', 'Acknowledged'))
    ORDER BY po.created_at DESC
    LIMIT 1;

    IF FOUND THEN
        v_label := COALESCE(v_po.display_name, v_po.po_number);
        NEW.purchase_order_id := COALESCE(NEW.purchase_order_id, v_po.id);
        NEW.po_version := COALESCE(NEW.po_version, v_po.current_version);
        NEW.subject := v_label || ' · V' || NEW.po_version ||
            ' · Supplier Purchase Order';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS email_records_tag_supplier_po_version
    ON public.email_records;
CREATE TRIGGER email_records_tag_supplier_po_version
BEFORE INSERT ON public.email_records
FOR EACH ROW EXECUTE FUNCTION public.tag_supplier_po_email_queue();

CREATE OR REPLACE FUNCTION public.sync_supplier_po_email_subject()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_label TEXT;
BEGIN
    IF NEW.direction <> 'Outgoing' THEN
        RETURN NEW;
    END IF;

    IF NEW.purchase_order_id IS NOT NULL THEN
        SELECT *
        INTO v_po
        FROM public.supplier_purchase_orders po
        WHERE po.id = NEW.purchase_order_id;
    ELSIF NEW.job_id IS NOT NULL THEN
        SELECT *
        INTO v_po
        FROM public.supplier_purchase_orders po
        WHERE po.job_id = NEW.job_id
          AND po.resource_id = NEW.resource_id
          AND po.status IN ('Issued', 'Acknowledged')
        ORDER BY po.created_at DESC
        LIMIT 1;
    END IF;

    IF FOUND THEN
        v_label := COALESCE(v_po.display_name, v_po.po_number);
        NEW.purchase_order_id := COALESCE(NEW.purchase_order_id, v_po.id);
        NEW.po_version := COALESCE(NEW.po_version, v_po.current_version, 1);
        NEW.subject := v_label || ' · V' || NEW.po_version ||
            ' · Supplier Purchase Order';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS email_records_sync_supplier_po_subject
    ON public.email_records;
CREATE TRIGGER email_records_sync_supplier_po_subject
BEFORE INSERT OR UPDATE OF purchase_order_id, po_version, subject
ON public.email_records
FOR EACH ROW EXECUTE FUNCTION public.sync_supplier_po_email_subject();

-- Backfill connected labels and repair statuses after all replacement
-- functions/triggers are installed.
DO $$
DECLARE
    v_po_id UUID;
    v_scoop_id UUID;
BEGIN
    FOR v_po_id IN SELECT id FROM public.supplier_purchase_orders LOOP
        PERFORM public.refresh_supplier_po_display_name(v_po_id);
    END LOOP;
    FOR v_scoop_id IN SELECT id FROM public.project_scoops LOOP
        PERFORM public.refresh_project_scoop_status(v_scoop_id);
    END LOOP;
END;
$$;

COMMIT;
