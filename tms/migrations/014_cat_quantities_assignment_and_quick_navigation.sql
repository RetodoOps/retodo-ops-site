-- RetodoOps TMS — CAT quantities on Jobs, immediate Supplier PO issue,
-- Assigned workflow and Project Ongoing transition.
-- Run after 013_multilanguage_rates_editable_work_and_po_versions.sql.

BEGIN;

ALTER TABLE public.project_jobs DROP CONSTRAINT IF EXISTS project_jobs_status_check;
ALTER TABLE public.project_jobs ADD CONSTRAINT project_jobs_status_check CHECK (status IN (
    'Unassigned', 'Assigned', 'In Progress', 'Delivered', 'Revision Required',
    'Approved', 'Cancelled'
));

CREATE OR REPLACE FUNCTION public.validate_job_assignment_workflow()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status IN ('Assigned', 'In Progress', 'Delivered', 'Revision Required', 'Approved')
       AND NEW.resource_id IS NULL THEN
        RAISE EXCEPTION 'A Resource must be assigned before the Job enters production';
    END IF;
    IF NEW.status = 'Unassigned' AND NEW.resource_id IS NOT NULL THEN
        RAISE EXCEPTION 'An assigned Job cannot return to Unassigned';
    END IF;
    RETURN NEW;
END;
$$;

-- Rebuild a CAT analysis exclusively from current rows belonging to the
-- selected Approved base rate. The browser sends only rate IDs and quantities;
-- prices and amounts are always resolved and calculated by the database.
CREATE OR REPLACE FUNCTION public.normalize_supplier_cat_analysis(
    p_base_rate_id UUID,
    p_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base public.resource_rates%ROWTYPE;
    v_input JSONB;
    v_rate public.resource_rates%ROWTYPE;
    v_quantity NUMERIC;
    v_amount NUMERIC;
    v_rows JSONB := '[]'::JSONB;
    v_total NUMERIC := 0;
    v_total_quantity NUMERIC := 0;
BEGIN
    SELECT * INTO v_base FROM public.resource_rates
    WHERE id = p_base_rate_id AND base_rate_id IS NULL
      AND active AND status = 'Approved';
    IF NOT FOUND THEN RAISE EXCEPTION 'Approved Supplier base rate not found'; END IF;
    IF jsonb_typeof(COALESCE(p_rows, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'CAT analysis rows must be an array';
    END IF;

    FOR v_input IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::JSONB))
    LOOP
        v_quantity := COALESCE(NULLIF(v_input->>'quantity', '')::NUMERIC, 0);
        IF v_quantity < 0 THEN RAISE EXCEPTION 'CAT quantities cannot be negative'; END IF;
        SELECT * INTO v_rate FROM public.resource_rates rate
        WHERE rate.id = NULLIF(v_input->>'resource_rate_id', '')::UUID
          AND rate.active AND rate.status = 'Approved'
          AND (rate.id = v_base.id OR rate.base_rate_id = v_base.id);
        IF NOT FOUND THEN RAISE EXCEPTION 'A CAT row does not belong to the selected Supplier rate card'; END IF;
        v_amount := CASE WHEN v_rate.unit = 'Fixed fee'
            THEN CASE WHEN v_quantity > 0 THEN v_rate.rate ELSE 0 END
            ELSE round(v_quantity * v_rate.rate, 2) END;
        v_rows := v_rows || jsonb_build_array(jsonb_build_object(
            'resource_rate_id', v_rate.id,
            'cat_band', COALESCE(v_rate.cat_band, 'New words'),
            'discount_percent', v_rate.discount_percent,
            'quantity', v_quantity,
            'unit', v_rate.unit,
            'unit_price', v_rate.rate,
            'currency', v_rate.currency,
            'amount', v_amount
        ));
        v_total := v_total + v_amount;
        v_total_quantity := v_total_quantity + v_quantity;
    END LOOP;

    IF jsonb_array_length(v_rows) = 0 THEN
        v_rows := jsonb_build_array(jsonb_build_object(
            'resource_rate_id', v_base.id, 'cat_band', 'New words',
            'discount_percent', NULL, 'quantity', 0, 'unit', v_base.unit,
            'unit_price', v_base.rate, 'currency', v_base.currency, 'amount', 0
        ));
    END IF;
    RETURN jsonb_build_object(
        'base_rate_id', v_base.id, 'currency', v_base.currency,
        'quantity', v_total_quantity, 'total', v_total, 'rows', v_rows
    );
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_supplier_cat_analysis(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_supplier_cat_analysis(UUID, JSONB) TO authenticated;

-- CAT rows are authoritative for an Offer total whenever present.
CREATE OR REPLACE FUNCTION public.prepare_job_offer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_sequence INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Resource not found'; END IF;
    IF v_resource.lifecycle_status <> 'Active'
       OR v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred') THEN
        RAISE EXCEPTION 'Only an Active Assignable, Proven or Preferred Resource may receive a new offer';
    END IF;
    IF TG_OP = 'INSERT' AND COALESCE(NEW.sequence_number, 0) < 1 THEN
        PERFORM pg_advisory_xact_lock(hashtext(NEW.job_id::TEXT || ':offer'));
        SELECT COALESCE(max(sequence_number), 0) + 1 INTO v_sequence
        FROM public.job_offers WHERE job_id = NEW.job_id;
        NEW.sequence_number := v_sequence;
    END IF;
    NEW.restriction_warning := FALSE;
    NEW.restriction_overridden := FALSE;
    NEW.override_reason := NULL;
    NEW.overridden_by := NULL;
    NEW.overridden_at := NULL;
    IF jsonb_typeof(NEW.cat_analysis->'rows') = 'array'
       AND jsonb_array_length(NEW.cat_analysis->'rows') > 0 THEN
        NEW.quantity := COALESCE((NEW.cat_analysis->>'quantity')::NUMERIC, 0);
        NEW.amount := COALESCE((NEW.cat_analysis->>'total')::NUMERIC, 0);
    ELSIF NEW.unit = 'Fixed fee' AND NEW.supplier_rate IS NOT NULL THEN
        NEW.amount := round(NEW.supplier_rate, 2);
    ELSIF NEW.quantity IS NOT NULL AND NEW.supplier_rate IS NOT NULL THEN
        NEW.amount := round(NEW.quantity * NEW.supplier_rate, 2);
    END IF;
    IF NEW.status = 'Sent' AND NEW.sent_at IS NULL THEN NEW.sent_at := NOW(); END IF;
    IF NEW.status = 'Viewed' AND NEW.viewed_at IS NULL THEN NEW.viewed_at := NOW(); END IF;
    IF NEW.status IN ('Accepted', 'Declined') AND NEW.responded_at IS NULL THEN NEW.responded_at := NOW(); END IF;
    RETURN NEW;
END;
$$;

-- New overload used by the CAT-aware frontend. The previous signature remains
-- compatible because the final CAT argument has a default.
DROP FUNCTION IF EXISTS public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT
);
CREATE OR REPLACE FUNCTION public.create_job_offer_from_rate(
    p_job_id UUID,
    p_resource_id UUID,
    p_resource_rate_id UUID,
    p_response_due_at TIMESTAMPTZ DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_client_identity_disclosed BOOLEAN DEFAULT FALSE,
    p_override BOOLEAN DEFAULT FALSE,
    p_override_reason TEXT DEFAULT NULL,
    p_cat_rows JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.project_jobs%ROWTYPE;
    v_rate public.resource_rates%ROWTYPE;
    v_analysis JSONB;
    v_offer_id UUID;
BEGIN
    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    SELECT * INTO v_rate FROM public.resource_rates rate
    WHERE rate.id = p_resource_rate_id AND rate.resource_id = p_resource_id
      AND rate.active AND rate.base_rate_id IS NULL AND rate.status = 'Approved'
      AND rate.service_type = v_job.service_type AND rate.unit = v_job.unit
      AND (cardinality(rate.source_languages) = 0 OR v_job.source_language = ANY(rate.source_languages))
      AND (cardinality(rate.target_languages) = 0 OR v_job.target_language = ANY(rate.target_languages))
      AND (rate.specialization_id IS NULL OR rate.specialization_id = v_job.specialization_id);
    IF NOT FOUND THEN RAISE EXCEPTION 'Select an active Approved matching base rate'; END IF;

    v_analysis := public.normalize_supplier_cat_analysis(p_resource_rate_id, p_cat_rows);
    IF COALESCE((v_analysis->>'quantity')::NUMERIC, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter a quantity in at least one Supplier CAT row';
    END IF;
    v_offer_id := public.create_job_offer(
        p_job_id, p_resource_id, p_response_due_at, v_rate.unit,
        COALESCE((v_analysis->>'quantity')::NUMERIC, p_quantity, v_job.quantity),
        v_rate.rate, v_rate.currency, p_message, p_client_identity_disclosed,
        p_override, p_override_reason
    );
    UPDATE public.job_offers
    SET resource_rate_id = p_resource_rate_id, cat_analysis = v_analysis
    WHERE id = v_offer_id;
    RETURN v_offer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_job_offer_from_rate(UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_job_offer_from_rate(UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_job_overview(p_job_id UUID, p_payload JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_old public.project_jobs%ROWTYPE;
    v_new public.project_jobs%ROWTYPE;
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_rate public.resource_rates%ROWTYPE;
    v_rate_id UUID := NULLIF(p_payload->>'resource_rate_id', '')::UUID;
    v_analysis JSONB;
    v_row JSONB;
    v_terms_changed BOOLEAN;
    v_po_changed BOOLEAN;
    v_new_version INTEGER := 0;
    v_snapshot JSONB;
    v_sort INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_old FROM public.project_jobs WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    IF v_rate_id IS NOT NULL THEN
        IF v_old.resource_id IS NULL THEN RAISE EXCEPTION 'Assign a Resource before changing the accepted rate'; END IF;
        SELECT * INTO v_rate FROM public.resource_rates rate
        WHERE rate.id = v_rate_id AND rate.resource_id = v_old.resource_id
          AND rate.base_rate_id IS NULL AND rate.active AND rate.status = 'Approved';
        IF NOT FOUND THEN RAISE EXCEPTION 'Select an active Approved base rate for the assigned Resource'; END IF;
        IF jsonb_typeof(p_payload->'cat_rows') = 'array' THEN
            v_analysis := public.normalize_supplier_cat_analysis(v_rate_id, p_payload->'cat_rows');
        END IF;
    END IF;

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs job SET
        status = COALESCE(NULLIF(p_payload->>'status', ''), job.status),
        deadline = CASE WHEN p_payload ? 'deadline' THEN NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ ELSE job.deadline END,
        service_type = COALESCE(NULLIF(btrim(p_payload->>'service_type'), ''), job.service_type),
        source_language = CASE WHEN p_payload ? 'source_language' THEN NULLIF(btrim(p_payload->>'source_language'), '') ELSE job.source_language END,
        target_language = CASE WHEN p_payload ? 'target_language' THEN NULLIF(btrim(p_payload->>'target_language'), '') ELSE job.target_language END,
        specialization_id = COALESCE(NULLIF(p_payload->>'specialization_id', '')::UUID, job.specialization_id),
        quantity = CASE WHEN v_analysis IS NOT NULL THEN (v_analysis->>'quantity')::NUMERIC
            WHEN p_payload ? 'quantity' THEN NULLIF(p_payload->>'quantity', '')::NUMERIC ELSE job.quantity END,
        unit = COALESCE(NULLIF(btrim(p_payload->>'unit'), ''), job.unit),
        po_required = COALESCE((p_payload->>'po_required')::BOOLEAN, job.po_required),
        notes = CASE WHEN p_payload ? 'notes' THEN NULLIF(p_payload->>'notes', '') ELSE job.notes END,
        resource_rate_id = COALESCE(v_rate_id, job.resource_rate_id),
        supplier_rate = CASE WHEN v_rate_id IS NOT NULL THEN v_rate.rate ELSE job.supplier_rate END,
        supplier_currency = CASE WHEN v_rate_id IS NOT NULL THEN v_rate.currency ELSE job.supplier_currency END,
        supplier_amount = CASE WHEN v_analysis IS NOT NULL THEN (v_analysis->>'total')::NUMERIC ELSE job.supplier_amount END,
        cat_analysis = COALESCE(v_analysis, job.cat_analysis),
        updated_at = NOW()
    WHERE job.id = p_job_id RETURNING * INTO v_new;

    IF v_rate_id IS NOT NULL AND NOT (
        v_rate.service_type = v_new.service_type AND v_rate.unit = v_new.unit
        AND (cardinality(v_rate.source_languages) = 0 OR v_new.source_language = ANY(v_rate.source_languages))
        AND (cardinality(v_rate.target_languages) = 0 OR v_new.target_language = ANY(v_rate.target_languages))
        AND (v_rate.specialization_id IS NULL OR v_rate.specialization_id = v_new.specialization_id)
    ) THEN RAISE EXCEPTION 'The selected Supplier rate does not match the saved Job terms'; END IF;

    IF v_analysis IS NULL AND v_new.resource_id IS NOT NULL AND v_new.supplier_rate IS NOT NULL THEN
        UPDATE public.project_jobs SET supplier_amount = CASE WHEN v_new.unit = 'Fixed fee'
            THEN round(v_new.supplier_rate, 2)
            ELSE round(COALESCE(v_new.quantity, 0) * v_new.supplier_rate, 2) END
        WHERE id = p_job_id RETURNING * INTO v_new;
    END IF;

    v_terms_changed := v_old.service_type IS DISTINCT FROM v_new.service_type
        OR v_old.source_language IS DISTINCT FROM v_new.source_language
        OR v_old.target_language IS DISTINCT FROM v_new.target_language
        OR v_old.specialization_id IS DISTINCT FROM v_new.specialization_id
        OR v_old.quantity IS DISTINCT FROM v_new.quantity
        OR v_old.unit IS DISTINCT FROM v_new.unit
        OR v_old.cat_analysis IS DISTINCT FROM v_new.cat_analysis;
    v_po_changed := v_terms_changed OR v_old.deadline IS DISTINCT FROM v_new.deadline
        OR v_old.resource_rate_id IS DISTINCT FROM v_new.resource_rate_id
        OR v_old.supplier_rate IS DISTINCT FROM v_new.supplier_rate
        OR v_old.supplier_currency IS DISTINCT FROM v_new.supplier_currency;
    IF v_new.resource_id IS NOT NULL AND v_terms_changed AND v_rate_id IS NULL THEN
        RAISE EXCEPTION 'Select an Approved Supplier rate matching the edited Job terms';
    END IF;
    IF v_terms_changed THEN
        UPDATE public.job_offers SET status = 'Withdrawn', responded_at = NOW(),
            decline_reason = 'Job terms changed after this Offer was prepared'
        WHERE job_id = p_job_id AND status IN ('Draft', 'Sent', 'Viewed');
    END IF;

    SELECT * INTO v_po FROM public.supplier_purchase_orders WHERE job_id = p_job_id FOR UPDATE;
    IF FOUND AND v_po_changed THEN
        IF v_po.status IN ('Issued', 'Acknowledged') THEN
            PERFORM set_config('retodo.po_revision', 'on', TRUE);
        END IF;
        IF v_analysis IS NOT NULL THEN
            DELETE FROM public.supplier_po_lines
            WHERE purchase_order_id = v_po.id AND adjustment_type IS NULL;
            v_sort := 0;
            FOR v_row IN SELECT value FROM jsonb_array_elements(v_analysis->'rows') LOOP
                IF COALESCE((v_row->>'quantity')::NUMERIC, 0) > 0 THEN
                    v_sort := v_sort + 10;
                    INSERT INTO public.supplier_po_lines(
                        purchase_order_id, description, quantity, unit, unit_price,
                        amount, sort_order, resource_rate_id, cat_band, discount_percent
                    ) VALUES (
                        v_po.id, concat_ws(' · ', v_new.service_type, v_row->>'cat_band',
                            NULLIF(concat_ws(' → ', v_new.source_language, v_new.target_language), '')),
                        (v_row->>'quantity')::NUMERIC, v_row->>'unit',
                        (v_row->>'unit_price')::NUMERIC, (v_row->>'amount')::NUMERIC,
                        v_sort, NULLIF(v_row->>'resource_rate_id', '')::UUID,
                        NULLIF(v_row->>'cat_band', ''), NULLIF(v_row->>'discount_percent', '')::NUMERIC
                    );
                END IF;
            END LOOP;
        ELSE
            UPDATE public.supplier_po_lines line SET
                description = concat_ws(' · ', v_new.job_number, v_new.service_type,
                    concat_ws(' → ', v_new.source_language, v_new.target_language)),
                quantity = v_new.quantity, unit = v_new.unit,
                unit_price = v_new.supplier_rate, amount = v_new.supplier_amount,
                resource_rate_id = v_new.resource_rate_id, updated_at = NOW()
            WHERE line.id = (SELECT current_line.id FROM public.supplier_po_lines current_line
                WHERE current_line.purchase_order_id = v_po.id
                  AND current_line.adjustment_type IS NULL
                ORDER BY current_line.sort_order, current_line.created_at LIMIT 1);
        END IF;
        UPDATE public.supplier_purchase_orders SET currency = v_new.supplier_currency WHERE id = v_po.id;
        IF v_po.status IN ('Issued', 'Acknowledged') THEN
            v_new_version := v_po.current_version + 1;
            UPDATE public.supplier_purchase_orders SET current_version = v_new_version,
                status = 'Issued', last_change_reason = 'Job terms or CAT quantities updated',
                acknowledgement_requested_at = NOW() WHERE id = v_po.id;
            v_snapshot := public.supplier_po_snapshot(v_po.id);
            INSERT INTO public.supplier_po_versions(
                purchase_order_id, version_number, snapshot, document_status,
                change_reason, created_by
            ) VALUES (v_po.id, v_new_version, v_snapshot, 'Revised',
                'Job terms or CAT quantities updated', auth.uid());
        END IF;
    END IF;
    RETURN v_new_version;
END;
$$;

REVOKE ALL ON FUNCTION public.save_job_overview(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_job_overview(UUID, JSONB) TO authenticated;

-- Acceptance now issues version 1 immediately and queues the PO email. There
-- is no intermediate Draft PO. Actual delivery is performed by the configured
-- email worker; email_records is its durable queue/audit record.
CREATE OR REPLACE FUNCTION public.respond_job_offer(
    p_offer_id UUID,
    p_response TEXT,
    p_decline_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_offer public.job_offers%ROWTYPE;
    v_job public.project_jobs%ROWTYPE;
    v_resource public.resources%ROWTYPE;
    v_po_id UUID;
    v_po_number TEXT;
    v_row JSONB;
    v_snapshot JSONB;
    v_sort INTEGER := 0;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    IF p_response NOT IN ('Accepted', 'Declined') THEN RAISE EXCEPTION 'Response must be Accepted or Declined'; END IF;
    SELECT * INTO v_offer FROM public.job_offers WHERE id = p_offer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Offer not found'; END IF;
    IF v_offer.status NOT IN ('Sent', 'Viewed') THEN RAISE EXCEPTION 'Only a sent offer can be answered'; END IF;
    IF p_response = 'Declined' THEN
        UPDATE public.job_offers SET status = 'Declined', decline_reason = NULLIF(btrim(p_decline_reason), '')
        WHERE id = p_offer_id;
        RETURN NULL;
    END IF;

    SELECT * INTO v_job FROM public.project_jobs WHERE id = v_offer.job_id FOR UPDATE;
    IF v_job.resource_id IS NOT NULL THEN RAISE EXCEPTION 'Job already has an assigned Resource'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_offer.resource_id;
    UPDATE public.job_offers SET status = 'Accepted' WHERE id = p_offer_id;
    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs SET
        resource_id = v_offer.resource_id, assigned_from_offer_id = v_offer.id,
        status = 'Assigned', accepted_at = NOW(), unit = v_offer.unit,
        quantity = v_offer.quantity, supplier_rate = v_offer.supplier_rate,
        supplier_currency = v_offer.currency, supplier_amount = v_offer.amount,
        cat_analysis = v_offer.cat_analysis,
        client_identity_disclosed = v_offer.client_identity_disclosed,
        restriction_overridden = v_offer.restriction_overridden,
        override_reason = v_offer.override_reason,
        resource_rate_id = v_offer.resource_rate_id
    WHERE id = v_job.id;
    UPDATE public.projects SET status = 'Ongoing', updated_at = NOW()
    WHERE id = v_job.project_id AND status = 'Assign';

    IF v_job.po_required THEN
        v_po_number := public.next_supplier_po_number();
        INSERT INTO public.supplier_purchase_orders(
            po_number, resource_id, project_id, job_id, status, current_version,
            currency, supplier_snapshot, work_may_begin_before_acknowledgement,
            issued_at, acknowledgement_requested_at, created_by
        ) VALUES (
            v_po_number, v_resource.id, v_job.project_id, v_job.id, 'Issued', 1,
            v_offer.currency, jsonb_build_object(
                'internal_number', v_resource.internal_number,
                'legal_name', v_resource.legal_name,
                'company_name', v_resource.company_name,
                'email', v_resource.email,
                'tax_id', v_resource.tax_id,
                'payment_terms_days', v_resource.payment_terms_days,
                'invoice_cycle', v_resource.invoice_cycle
            ), TRUE, NOW(), NOW(), auth.uid()
        ) RETURNING id INTO v_po_id;

        -- Lines are inserted as part of the same atomic issue transaction.
        PERFORM set_config('retodo.po_revision', 'on', TRUE);

        IF jsonb_typeof(v_offer.cat_analysis->'rows') = 'array' THEN
            FOR v_row IN SELECT value FROM jsonb_array_elements(v_offer.cat_analysis->'rows')
            LOOP
                IF COALESCE((v_row->>'quantity')::NUMERIC, 0) > 0 THEN
                    v_sort := v_sort + 10;
                    INSERT INTO public.supplier_po_lines(
                        purchase_order_id, description, quantity, unit,
                        unit_price, amount, sort_order, resource_rate_id,
                        cat_band, discount_percent
                    ) VALUES (
                        v_po_id,
                        concat_ws(' · ', v_job.service_type, v_row->>'cat_band',
                            NULLIF(concat_ws(' → ', v_job.source_language, v_job.target_language), '')),
                        (v_row->>'quantity')::NUMERIC, v_row->>'unit',
                        (v_row->>'unit_price')::NUMERIC, (v_row->>'amount')::NUMERIC,
                        v_sort, NULLIF(v_row->>'resource_rate_id', '')::UUID,
                        NULLIF(v_row->>'cat_band', ''),
                        NULLIF(v_row->>'discount_percent', '')::NUMERIC
                    );
                END IF;
            END LOOP;
        END IF;
        IF v_sort = 0 THEN
            INSERT INTO public.supplier_po_lines(
                purchase_order_id, description, quantity, unit, unit_price,
                amount, sort_order, resource_rate_id
            ) VALUES (
                v_po_id, concat_ws(' · ', v_job.service_type,
                    NULLIF(concat_ws(' → ', v_job.source_language, v_job.target_language), '')),
                v_offer.quantity, v_offer.unit, v_offer.supplier_rate,
                v_offer.amount, 10, v_offer.resource_rate_id
            );
        END IF;

        v_snapshot := public.supplier_po_snapshot(v_po_id);
        INSERT INTO public.supplier_po_versions(
            purchase_order_id, version_number, snapshot, document_status, created_by
        ) VALUES (v_po_id, 1, v_snapshot, 'Issued', auth.uid());

        INSERT INTO public.email_records(
            project_id, job_id, resource_id, direction, status, from_address,
            to_addresses, subject, created_by
        ) VALUES (
            v_job.project_id, v_job.id, v_resource.id, 'Outgoing', 'Draft requested',
            'ops@retodo-ops.com', ARRAY[v_resource.email],
            v_po_number || ' · Supplier purchase order', auth.uid()
        );
    END IF;
    RETURN v_po_id;
END;
$$;

REVOKE ALL ON FUNCTION public.respond_job_offer(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_job_offer(UUID, TEXT, TEXT) TO authenticated;

-- Keep the Project lifecycle synchronized even when an Administrator changes
-- the Job through the editable Overview rather than through offer acceptance.
CREATE OR REPLACE FUNCTION public.sync_project_ongoing_from_assigned_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'Assigned' THEN
        UPDATE public.projects
        SET status = 'Ongoing', updated_at = NOW()
        WHERE id = NEW.project_id AND status = 'Assign';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_sync_project_ongoing ON public.project_jobs;
CREATE TRIGGER project_jobs_sync_project_ongoing
AFTER INSERT OR UPDATE OF status ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.sync_project_ongoing_from_assigned_job();

COMMIT;
