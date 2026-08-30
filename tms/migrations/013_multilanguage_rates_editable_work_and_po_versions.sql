-- RetodoOps TMS — multi-language Supplier rate cards, directly editable
-- Project/Job operational fields and automatic Supplier PO revisions.
-- Run after 012_resource_selection_and_editable_capabilities.sql.

BEGIN;

-- One Supplier rate card can cover several Source and Target languages.  The
-- scalar columns remain populated for backwards compatibility; all current
-- matching uses the arrays below.
ALTER TABLE public.resource_rates
    ADD COLUMN IF NOT EXISTS source_languages TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS target_languages TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE public.resource_rates
SET source_languages = CASE
        WHEN cardinality(source_languages) = 0 AND source_language IS NOT NULL
        THEN ARRAY[source_language] ELSE source_languages END,
    target_languages = CASE
        WHEN cardinality(target_languages) = 0 AND target_language IS NOT NULL
        THEN ARRAY[target_language] ELSE target_languages END;

CREATE INDEX IF NOT EXISTS resource_rates_source_languages_gin_idx
    ON public.resource_rates USING gin(source_languages);
CREATE INDEX IF NOT EXISTS resource_rates_target_languages_gin_idx
    ON public.resource_rates USING gin(target_languages);

-- Project display names are operational labels and may be corrected.  The
-- permanent project_number remains the immutable technical reference.
CREATE OR REPLACE FUNCTION public.protect_project_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.project_number IS DISTINCT FROM OLD.project_number THEN
        RAISE EXCEPTION 'Project number is a permanent technical reference';
    END IF;
    IF NULLIF(btrim(NEW.display_name), '') IS NULL THEN
        RAISE EXCEPTION 'Project name is required';
    END IF;
    NEW.display_name := btrim(NEW.display_name);
    RETURN NEW;
END;
$$;

-- Every issued/revised version now snapshots the Job facts printed on the PO,
-- not only the price lines and Supplier identity.
CREATE OR REPLACE FUNCTION public.supplier_po_snapshot(p_po_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'po_number', po.po_number,
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
            FROM public.supplier_po_lines line WHERE line.purchase_order_id = po.id
        ), '[]'::JSONB)
    )
    FROM public.supplier_purchase_orders po
    LEFT JOIN public.project_jobs job ON job.id = po.job_id
    WHERE public.is_company_user() AND po.id = p_po_id;
$$;

CREATE OR REPLACE FUNCTION public.save_resource_rate_card(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base_id UUID := NULLIF(p_payload->>'base_rate_id', '')::UUID;
    v_resource_id UUID := NULLIF(p_payload->>'resource_id', '')::UUID;
    v_sources TEXT[];
    v_targets TEXT[];
    v_source TEXT;
    v_target TEXT;
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
    v_specialization_id UUID := NULLIF(p_payload->>'specialization_id', '')::UUID;
    v_unit TEXT := NULLIF(btrim(p_payload->>'unit'), '');
    v_base_rate NUMERIC := NULLIF(p_payload->>'base_rate', '')::NUMERIC;
    v_currency TEXT := COALESCE(NULLIF(btrim(p_payload->>'currency'), ''), 'EUR');
    v_minimum_fee NUMERIC := NULLIF(p_payload->>'minimum_fee', '')::NUMERIC;
    v_status TEXT := COALESCE(NULLIF(btrim(p_payload->>'status'), ''), 'Pending');
    v_discount JSONB;
    v_band TEXT;
    v_percent NUMERIC;
    v_child_id UUID;
    v_seen_bands TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT btrim(language) ORDER BY btrim(language)), ARRAY[]::TEXT[])
    INTO v_sources
    FROM jsonb_array_elements_text(COALESCE(p_payload->'source_languages', '[]'::JSONB)) AS item(language)
    WHERE NULLIF(btrim(language), '') IS NOT NULL;
    SELECT COALESCE(array_agg(DISTINCT btrim(language) ORDER BY btrim(language)), ARRAY[]::TEXT[])
    INTO v_targets
    FROM jsonb_array_elements_text(COALESCE(p_payload->'target_languages', '[]'::JSONB)) AS item(language)
    WHERE NULLIF(btrim(language), '') IS NOT NULL;

    -- Accept the legacy scalar payload during a mixed frontend deployment.
    IF cardinality(v_sources) = 0 AND NULLIF(btrim(p_payload->>'source_language'), '') IS NOT NULL THEN
        v_sources := ARRAY[btrim(p_payload->>'source_language')];
    END IF;
    IF cardinality(v_targets) = 0 AND NULLIF(btrim(p_payload->>'target_language'), '') IS NOT NULL THEN
        v_targets := ARRAY[btrim(p_payload->>'target_language')];
    END IF;

    IF v_resource_id IS NULL OR cardinality(v_sources) = 0 OR cardinality(v_targets) = 0
       OR v_service IS NULL OR v_unit IS NULL OR v_base_rate IS NULL THEN
        RAISE EXCEPTION 'Resource, Source languages, Target languages, service, unit and base price are required';
    END IF;
    IF v_base_rate < 0 OR COALESCE(v_minimum_fee, 0) < 0 THEN
        RAISE EXCEPTION 'Rates and minimum fees cannot be negative';
    END IF;
    IF v_status NOT IN ('Pending', 'Approved', 'Rejected') THEN
        RAISE EXCEPTION 'Unsupported Resource rate status';
    END IF;

    -- Multiple Sources × multiple Targets intentionally describe the full
    -- cross-product.  Every combination must therefore exist on the Resource.
    FOREACH v_source IN ARRAY v_sources LOOP
        FOREACH v_target IN ARRAY v_targets LOOP
            IF NOT EXISTS (
                SELECT 1 FROM public.resource_language_pairs pair
                WHERE pair.resource_id = v_resource_id
                  AND pair.source_language = v_source
                  AND pair.target_language = v_target
            ) THEN
                RAISE EXCEPTION 'Add the Resource language pair % → % before using it in this rate card', v_source, v_target;
            END IF;
        END LOOP;
    END LOOP;
    IF NOT EXISTS (
        SELECT 1 FROM public.resource_services service
        WHERE service.resource_id = v_resource_id AND service.service_type = v_service
    ) THEN
        RAISE EXCEPTION 'Select a service configured on the Resource profile';
    END IF;
    IF v_specialization_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.resource_specializations spec
        WHERE spec.resource_id = v_resource_id AND spec.specialization_id = v_specialization_id
    ) THEN
        RAISE EXCEPTION 'Select a specialization configured on the Resource profile';
    END IF;

    IF v_base_id IS NULL THEN
        INSERT INTO public.resource_rates (
            resource_id, source_language, target_language, source_languages,
            target_languages, service_type, specialization_id, unit, cat_band,
            rate, currency, minimum_fee, status, valid_from, valid_to,
            approved_by, approved_at, active
        ) VALUES (
            v_resource_id, v_sources[1], v_targets[1], v_sources, v_targets,
            v_service, v_specialization_id, v_unit, NULL, v_base_rate,
            v_currency, v_minimum_fee, v_status, NULL, NULL,
            CASE WHEN v_status = 'Approved' THEN auth.uid() ELSE NULL END,
            CASE WHEN v_status = 'Approved' THEN NOW() ELSE NULL END, TRUE
        ) RETURNING id INTO v_base_id;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM public.resource_rates base
            WHERE base.id = v_base_id AND base.resource_id = v_resource_id
              AND base.base_rate_id IS NULL
        ) THEN
            RAISE EXCEPTION 'Supplier base rate not found for this Resource';
        END IF;
        UPDATE public.resource_rates
        SET source_language = v_sources[1], target_language = v_targets[1],
            source_languages = v_sources, target_languages = v_targets,
            service_type = v_service, specialization_id = v_specialization_id,
            unit = v_unit, rate = v_base_rate, currency = v_currency,
            minimum_fee = v_minimum_fee, status = v_status,
            approved_by = CASE WHEN v_status = 'Approved' THEN auth.uid() ELSE NULL END,
            approved_at = CASE WHEN v_status = 'Approved' THEN NOW() ELSE NULL END,
            valid_from = NULL, valid_to = NULL, active = TRUE, updated_at = NOW()
        WHERE id = v_base_id;
        UPDATE public.resource_rates SET active = FALSE, updated_at = NOW()
        WHERE base_rate_id = v_base_id;
    END IF;

    FOR v_discount IN
        SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'cat_discounts', '[]'::JSONB))
    LOOP
        v_band := NULLIF(btrim(v_discount->>'cat_band'), '');
        v_percent := NULLIF(v_discount->>'discount_percent', '')::NUMERIC;
        IF v_band IS NULL OR v_percent IS NULL OR v_percent < 0 OR v_percent > 100 THEN
            RAISE EXCEPTION 'Each CAT band requires a discount between 0 and 100 percent';
        END IF;
        IF lower(v_band) = ANY(v_seen_bands) THEN RAISE EXCEPTION 'Duplicate CAT band: %', v_band; END IF;
        v_seen_bands := array_append(v_seen_bands, lower(v_band));

        SELECT child.id INTO v_child_id
        FROM public.resource_rates child
        WHERE child.base_rate_id = v_base_id AND lower(child.cat_band) = lower(v_band)
        LIMIT 1;
        IF v_child_id IS NULL THEN
            INSERT INTO public.resource_rates (
                resource_id, base_rate_id, cat_band, discount_percent,
                source_language, target_language, source_languages, target_languages,
                service_type, specialization_id, unit, rate, currency,
                minimum_fee, status, active
            ) VALUES (
                v_resource_id, v_base_id, v_band, v_percent,
                v_sources[1], v_targets[1], v_sources, v_targets,
                v_service, v_specialization_id, v_unit, v_base_rate,
                v_currency, v_minimum_fee, v_status, TRUE
            );
        ELSE
            UPDATE public.resource_rates
            SET discount_percent = v_percent, source_language = v_sources[1],
                target_language = v_targets[1], source_languages = v_sources,
                target_languages = v_targets, service_type = v_service,
                specialization_id = v_specialization_id, unit = v_unit,
                currency = v_currency, minimum_fee = v_minimum_fee,
                status = v_status, active = TRUE, updated_at = NOW()
            WHERE id = v_child_id;
        END IF;
        v_child_id := NULL;
    END LOOP;
    RETURN v_base_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_resource_rate_card(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_resource_rate_card(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_job_offer_from_rate(
    p_job_id UUID, p_resource_id UUID, p_resource_rate_id UUID,
    p_response_due_at TIMESTAMPTZ DEFAULT NULL, p_quantity NUMERIC DEFAULT NULL,
    p_message TEXT DEFAULT NULL, p_client_identity_disclosed BOOLEAN DEFAULT FALSE,
    p_override BOOLEAN DEFAULT FALSE, p_override_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.project_jobs%ROWTYPE;
    v_rate public.resource_rates%ROWTYPE;
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
    IF NOT FOUND THEN RAISE EXCEPTION 'Select an active approved matching base rate from the Resource profile'; END IF;

    v_offer_id := public.create_job_offer(
        p_job_id, p_resource_id, p_response_due_at, v_rate.unit,
        COALESCE(p_quantity, v_job.quantity), v_rate.rate, v_rate.currency,
        p_message, p_client_identity_disclosed, p_override, p_override_reason
    );
    UPDATE public.job_offers SET resource_rate_id = p_resource_rate_id WHERE id = v_offer_id;
    RETURN v_offer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_job_offer_from_rate(UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_job_offer_from_rate(UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_resource_language_pair(p_pair_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_pair public.resource_language_pairs%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_pair FROM public.resource_language_pairs WHERE id = p_pair_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Resource language pair not found'; END IF;
    UPDATE public.resource_rates SET active = FALSE, updated_at = NOW()
    WHERE resource_id = v_pair.resource_id AND base_rate_id IS NULL
      AND v_pair.source_language = ANY(source_languages)
      AND v_pair.target_language = ANY(target_languages);
    DELETE FROM public.resource_language_pairs WHERE id = p_pair_id;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_resource_language_pair(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_resource_language_pair(UUID) TO authenticated;

-- Existing trigger protection remains in force for ad-hoc table updates.  The
-- transactional editor below is the only path allowed to alter quoted terms.
CREATE OR REPLACE FUNCTION public.protect_job_commercial_terms()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF COALESCE(current_setting('retodo.job_overview_edit', TRUE), '') = 'on' THEN
        RETURN NEW;
    END IF;
    IF (
        NEW.service_type IS DISTINCT FROM OLD.service_type
        OR NEW.specialization_id IS DISTINCT FROM OLD.specialization_id
        OR NEW.source_language IS DISTINCT FROM OLD.source_language
        OR NEW.target_language IS DISTINCT FROM OLD.target_language
        OR NEW.unit IS DISTINCT FROM OLD.unit
        OR NEW.quantity IS DISTINCT FROM OLD.quantity
    ) AND (
        OLD.resource_id IS NOT NULL OR EXISTS (
            SELECT 1 FROM public.job_offers offer
            WHERE offer.job_id = OLD.id AND offer.status IN ('Draft', 'Sent', 'Viewed')
        )
    ) THEN
        RAISE EXCEPTION 'Use the Job Save action so Offer history and PO versions remain consistent';
    END IF;
    RETURN NEW;
END;
$$;

-- Save every operational Job field in one transaction.  Active unaccepted
-- offers are withdrawn if the terms they quote change.  An issued PO receives
-- an immutable new version; a Draft PO is refreshed without creating a version.
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
    v_terms_changed BOOLEAN;
    v_po_changed BOOLEAN;
    v_new_version INTEGER := 0;
    v_snapshot JSONB;
    v_description TEXT;
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
    END IF;

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs job SET
        status = COALESCE(NULLIF(p_payload->>'status', ''), job.status),
        deadline = CASE WHEN p_payload ? 'deadline' THEN NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ ELSE job.deadline END,
        service_type = COALESCE(NULLIF(btrim(p_payload->>'service_type'), ''), job.service_type),
        source_language = CASE WHEN p_payload ? 'source_language' THEN NULLIF(btrim(p_payload->>'source_language'), '') ELSE job.source_language END,
        target_language = CASE WHEN p_payload ? 'target_language' THEN NULLIF(btrim(p_payload->>'target_language'), '') ELSE job.target_language END,
        specialization_id = COALESCE(NULLIF(p_payload->>'specialization_id', '')::UUID, job.specialization_id),
        quantity = CASE WHEN p_payload ? 'quantity' THEN NULLIF(p_payload->>'quantity', '')::NUMERIC ELSE job.quantity END,
        unit = COALESCE(NULLIF(btrim(p_payload->>'unit'), ''), job.unit),
        po_required = COALESCE((p_payload->>'po_required')::BOOLEAN, job.po_required),
        notes = CASE WHEN p_payload ? 'notes' THEN NULLIF(p_payload->>'notes', '') ELSE job.notes END,
        resource_rate_id = COALESCE(v_rate_id, job.resource_rate_id),
        supplier_rate = CASE WHEN v_rate_id IS NOT NULL THEN v_rate.rate ELSE job.supplier_rate END,
        supplier_currency = CASE WHEN v_rate_id IS NOT NULL THEN v_rate.currency ELSE job.supplier_currency END,
        updated_at = NOW()
    WHERE job.id = p_job_id RETURNING * INTO v_new;

    -- Validate a selected replacement rate against the newly saved terms.
    IF v_rate_id IS NOT NULL AND NOT (
        v_rate.service_type = v_new.service_type AND v_rate.unit = v_new.unit
        AND (cardinality(v_rate.source_languages) = 0 OR v_new.source_language = ANY(v_rate.source_languages))
        AND (cardinality(v_rate.target_languages) = 0 OR v_new.target_language = ANY(v_rate.target_languages))
        AND (v_rate.specialization_id IS NULL OR v_rate.specialization_id = v_new.specialization_id)
    ) THEN
        RAISE EXCEPTION 'The selected Supplier rate does not match the saved Job terms';
    END IF;

    IF v_new.resource_id IS NOT NULL AND v_new.supplier_rate IS NOT NULL THEN
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
        OR v_old.unit IS DISTINCT FROM v_new.unit;
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
        v_description := concat_ws(' · ', v_new.job_number, v_new.service_type,
            concat_ws(' → ', v_new.source_language, v_new.target_language));
        IF v_po.status IN ('Issued', 'Acknowledged') THEN
            PERFORM set_config('retodo.po_revision', 'on', TRUE);
        END IF;

        UPDATE public.supplier_po_lines line SET
            description = v_description,
            quantity = v_new.quantity,
            unit = v_new.unit,
            unit_price = v_new.supplier_rate,
            amount = CASE WHEN v_new.unit = 'Fixed fee'
                THEN round(COALESCE(v_new.supplier_rate, 0), 2)
                ELSE round(COALESCE(v_new.quantity, 0) * COALESCE(v_new.supplier_rate, 0), 2) END,
            resource_rate_id = v_new.resource_rate_id,
            updated_at = NOW()
        WHERE line.id = (
            SELECT current_line.id FROM public.supplier_po_lines current_line
            WHERE current_line.purchase_order_id = v_po.id
              AND current_line.adjustment_type IS NULL
            ORDER BY current_line.sort_order, current_line.created_at LIMIT 1
        );

        UPDATE public.supplier_purchase_orders SET currency = v_new.supplier_currency
        WHERE id = v_po.id;

        IF v_po.status IN ('Issued', 'Acknowledged') THEN
            v_new_version := v_po.current_version + 1;
            UPDATE public.supplier_purchase_orders
            SET current_version = v_new_version, status = 'Issued',
                last_change_reason = 'Job terms updated', acknowledgement_requested_at = NOW()
            WHERE id = v_po.id;
            v_snapshot := public.supplier_po_snapshot(v_po.id) || jsonb_build_object(
                'job', jsonb_build_object('job_number', v_new.job_number,
                    'service_type', v_new.service_type, 'source_language', v_new.source_language,
                    'target_language', v_new.target_language, 'specialization_id', v_new.specialization_id,
                    'deadline', v_new.deadline, 'quantity', v_new.quantity, 'unit', v_new.unit)
            );
            INSERT INTO public.supplier_po_versions(
                purchase_order_id, version_number, snapshot, document_status,
                change_reason, created_by
            ) VALUES (v_po.id, v_new_version, v_snapshot, 'Revised', 'Job terms updated', auth.uid());
        END IF;
    END IF;
    RETURN v_new_version;
END;
$$;

REVOKE ALL ON FUNCTION public.save_job_overview(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_job_overview(UUID, JSONB) TO authenticated;

COMMENT ON COLUMN public.resource_rates.source_languages IS
    'Source languages covered by this current rate card; Offer/Job/PO snapshots remain immutable.';
COMMENT ON COLUMN public.resource_rates.target_languages IS
    'Target languages covered by this current rate card; the card covers their cross-product with Source languages.';

COMMIT;
