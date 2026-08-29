-- RetodoOps TMS — linked Resource reference data, base rates and CAT discounts
-- Run after 007_specializations_and_resource_rates.sql.

BEGIN;

-- A rate card has one base row. Optional CAT-band rows point to that base and
-- retain both the percentage and the calculated price.
ALTER TABLE public.resource_rates
    ADD COLUMN IF NOT EXISTS base_rate_id UUID
        REFERENCES public.resource_rates(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5, 2);

ALTER TABLE public.resource_rates
    DROP CONSTRAINT IF EXISTS resource_rates_discount_percent_check;
ALTER TABLE public.resource_rates
    ADD CONSTRAINT resource_rates_discount_percent_check
    CHECK (discount_percent IS NULL OR discount_percent BETWEEN 0 AND 100);

CREATE INDEX IF NOT EXISTS resource_rates_base_rate_idx
    ON public.resource_rates(base_rate_id);

CREATE OR REPLACE FUNCTION public.prepare_resource_rate_card_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_base public.resource_rates%ROWTYPE;
BEGIN
    -- Validity dates are deprecated. Status/version approval now controls use.
    NEW.valid_from := NULL;
    NEW.valid_to := NULL;

    IF NEW.base_rate_id IS NOT NULL THEN
        SELECT * INTO v_base
        FROM public.resource_rates
        WHERE id = NEW.base_rate_id;
        IF NOT FOUND OR v_base.base_rate_id IS NOT NULL THEN
            RAISE EXCEPTION 'CAT rate must reference a valid base Resource rate';
        END IF;
        IF NEW.resource_id <> v_base.resource_id THEN
            RAISE EXCEPTION 'CAT rate and base rate must belong to the same Resource';
        END IF;
        IF (v_base.status IN ('Approved', 'Rejected') OR v_base.approved_by IS NOT NULL)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can create CAT rows for an approved or rejected rate card';
        END IF;
        IF NULLIF(btrim(NEW.cat_band), '') IS NULL OR NEW.discount_percent IS NULL THEN
            RAISE EXCEPTION 'CAT band and discount percentage are required';
        END IF;

        NEW.source_language := v_base.source_language;
        NEW.target_language := v_base.target_language;
        NEW.service_type := v_base.service_type;
        NEW.specialization_id := v_base.specialization_id;
        NEW.unit := v_base.unit;
        NEW.currency := v_base.currency;
        NEW.minimum_fee := v_base.minimum_fee;
        NEW.status := v_base.status;
        NEW.approved_by := v_base.approved_by;
        NEW.approved_at := v_base.approved_at;
        NEW.rate := round(v_base.rate * (100 - NEW.discount_percent) / 100, 4);
    ELSIF NEW.cat_band IS NULL THEN
        NEW.discount_percent := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_rates_prepare_card_row
    ON public.resource_rates;
CREATE TRIGGER resource_rates_prepare_card_row
BEFORE INSERT OR UPDATE ON public.resource_rates
FOR EACH ROW EXECUTE FUNCTION public.prepare_resource_rate_card_row();

CREATE OR REPLACE FUNCTION public.sync_resource_rate_card_rows()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.base_rate_id IS NULL THEN
        UPDATE public.resource_rates child
        SET source_language = NEW.source_language,
            target_language = NEW.target_language,
            service_type = NEW.service_type,
            specialization_id = NEW.specialization_id,
            unit = NEW.unit,
            currency = NEW.currency,
            minimum_fee = NEW.minimum_fee,
            status = NEW.status,
            approved_by = NEW.approved_by,
            approved_at = NEW.approved_at,
            rate = round(NEW.rate * (100 - child.discount_percent) / 100, 4),
            valid_from = NULL,
            valid_to = NULL,
            updated_at = NOW()
        WHERE child.base_rate_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_rates_sync_card_rows
    ON public.resource_rates;
CREATE TRIGGER resource_rates_sync_card_rows
AFTER UPDATE OF source_language, target_language, service_type,
    specialization_id, unit, rate, currency, minimum_fee, status
ON public.resource_rates
FOR EACH ROW EXECUTE FUNCTION public.sync_resource_rate_card_rows();

CREATE OR REPLACE FUNCTION public.create_resource_rate_card(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := NULLIF(p_payload->>'resource_id', '')::UUID;
    v_source TEXT := NULLIF(btrim(p_payload->>'source_language'), '');
    v_target TEXT := NULLIF(btrim(p_payload->>'target_language'), '');
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
    v_specialization_id UUID := NULLIF(p_payload->>'specialization_id', '')::UUID;
    v_unit TEXT := NULLIF(btrim(p_payload->>'unit'), '');
    v_base_rate NUMERIC := NULLIF(p_payload->>'base_rate', '')::NUMERIC;
    v_currency TEXT := COALESCE(NULLIF(btrim(p_payload->>'currency'), ''), 'EUR');
    v_minimum_fee NUMERIC := NULLIF(p_payload->>'minimum_fee', '')::NUMERIC;
    v_status TEXT := COALESCE(NULLIF(btrim(p_payload->>'status'), ''), 'Pending');
    v_base_id UUID;
    v_discount JSONB;
    v_band TEXT;
    v_percent NUMERIC;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_resource_id IS NULL OR v_source IS NULL OR v_target IS NULL
       OR v_service IS NULL OR v_unit IS NULL OR v_base_rate IS NULL THEN
        RAISE EXCEPTION 'Resource, language pair, service, unit and base price are required';
    END IF;
    IF v_base_rate < 0 OR COALESCE(v_minimum_fee, 0) < 0 THEN
        RAISE EXCEPTION 'Rates and minimum fees cannot be negative';
    END IF;
    IF v_status NOT IN ('Pending', 'Approved', 'Rejected') THEN
        RAISE EXCEPTION 'Unsupported Resource rate status';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.resource_language_pairs pair
        WHERE pair.resource_id = v_resource_id
          AND pair.source_language = v_source
          AND pair.target_language = v_target
    ) THEN
        RAISE EXCEPTION 'Select a language pair from the Resource profile';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.resource_services service
        WHERE service.resource_id = v_resource_id
          AND service.service_type = v_service
    ) THEN
        RAISE EXCEPTION 'Select a service configured on the Resource profile';
    END IF;
    IF v_specialization_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.resource_specializations spec
        WHERE spec.resource_id = v_resource_id
          AND spec.specialization_id = v_specialization_id
    ) THEN
        RAISE EXCEPTION 'Select a specialization configured on the Resource profile';
    END IF;

    INSERT INTO public.resource_rates (
        resource_id, source_language, target_language, service_type,
        specialization_id, unit, cat_band, rate, currency, minimum_fee,
        status, valid_from, valid_to, approved_by, approved_at
    ) VALUES (
        v_resource_id, v_source, v_target, v_service,
        v_specialization_id, v_unit, NULL, v_base_rate, v_currency,
        v_minimum_fee, v_status, NULL, NULL,
        CASE WHEN v_status = 'Approved' THEN auth.uid() ELSE NULL END,
        CASE WHEN v_status = 'Approved' THEN NOW() ELSE NULL END
    ) RETURNING id INTO v_base_id;

    FOR v_discount IN
        SELECT value FROM jsonb_array_elements(
            COALESCE(p_payload->'cat_discounts', '[]'::JSONB)
        )
    LOOP
        v_band := NULLIF(btrim(v_discount->>'cat_band'), '');
        v_percent := NULLIF(v_discount->>'discount_percent', '')::NUMERIC;
        IF v_band IS NULL OR v_percent IS NULL OR v_percent < 0 OR v_percent > 100 THEN
            RAISE EXCEPTION 'Each CAT band requires a discount between 0 and 100 percent';
        END IF;
        IF EXISTS (
            SELECT 1 FROM public.resource_rates
            WHERE base_rate_id = v_base_id AND lower(cat_band) = lower(v_band)
        ) THEN
            RAISE EXCEPTION 'Duplicate CAT band: %', v_band;
        END IF;
        INSERT INTO public.resource_rates (
            resource_id, base_rate_id, cat_band, discount_percent,
            source_language, target_language, service_type,
            specialization_id, unit, rate, currency, minimum_fee, status
        ) VALUES (
            v_resource_id, v_base_id, v_band, v_percent,
            v_source, v_target, v_service, v_specialization_id, v_unit,
            v_base_rate, v_currency, v_minimum_fee, v_status
        );
    END LOOP;

    RETURN v_base_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_resource_rate_card(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_resource_rate_card(JSONB) TO authenticated;

-- Supplier PO lines keep a direct provenance link to the selected Resource
-- rate while retaining the issued commercial snapshot.
ALTER TABLE public.supplier_po_lines
    ADD COLUMN IF NOT EXISTS resource_rate_id UUID
        REFERENCES public.resource_rates(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS cat_band TEXT,
    ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5, 2);

CREATE INDEX IF NOT EXISTS supplier_po_lines_resource_rate_idx
    ON public.supplier_po_lines(resource_rate_id);

CREATE OR REPLACE FUNCTION public.link_supplier_po_line_to_resource_rate()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_rate public.resource_rates%ROWTYPE;
    v_rate_id UUID;
BEGIN
    IF NEW.adjustment_type IS NOT NULL THEN
        NEW.resource_rate_id := NULL;
        NEW.cat_band := NULL;
        NEW.discount_percent := NULL;
        RETURN NEW;
    END IF;

    -- The first ordinary line inherits the accepted Job rate. Additional
    -- manual lines remain unlinked unless a rate is selected explicitly.
    IF NEW.resource_rate_id IS NULL AND NOT EXISTS (
        SELECT 1
        FROM public.supplier_po_lines existing
        WHERE existing.purchase_order_id = NEW.purchase_order_id
          AND existing.adjustment_type IS NULL
          AND existing.id IS DISTINCT FROM NEW.id
    ) THEN
        SELECT job.resource_rate_id INTO v_rate_id
        FROM public.supplier_purchase_orders po
        JOIN public.project_jobs job ON job.id = po.job_id
        WHERE po.id = NEW.purchase_order_id;
        NEW.resource_rate_id := v_rate_id;
    END IF;

    IF NEW.resource_rate_id IS NOT NULL THEN
        SELECT * INTO v_rate FROM public.resource_rates
        WHERE id = NEW.resource_rate_id;
        IF FOUND THEN
            NEW.cat_band := v_rate.cat_band;
            NEW.discount_percent := v_rate.discount_percent;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_po_lines_link_resource_rate
    ON public.supplier_po_lines;
CREATE TRIGGER supplier_po_lines_link_resource_rate
BEFORE INSERT OR UPDATE OF purchase_order_id, resource_rate_id, adjustment_type
ON public.supplier_po_lines
FOR EACH ROW EXECUTE FUNCTION public.link_supplier_po_line_to_resource_rate();

-- Offers select only the approved base row. CAT-band rows are reserved for
-- CAT analysis and the corresponding Supplier PO price lines.
CREATE OR REPLACE FUNCTION public.create_job_offer_from_rate(
    p_job_id UUID,
    p_resource_id UUID,
    p_resource_rate_id UUID,
    p_response_due_at TIMESTAMPTZ DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_client_identity_disclosed BOOLEAN DEFAULT FALSE,
    p_override BOOLEAN DEFAULT FALSE,
    p_override_reason TEXT DEFAULT NULL
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
    SELECT * INTO v_job
    FROM public.project_jobs
    WHERE id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;

    SELECT * INTO v_rate
    FROM public.resource_rates rate
    WHERE rate.id = p_resource_rate_id
      AND rate.resource_id = p_resource_id
      AND rate.base_rate_id IS NULL
      AND rate.status = 'Approved'
      AND rate.service_type = v_job.service_type
      AND rate.unit = v_job.unit
      AND (rate.source_language IS NULL
           OR rate.source_language = v_job.source_language
           OR v_job.source_language LIKE rate.source_language || ' (%)')
      AND (rate.target_language IS NULL
           OR rate.target_language = v_job.target_language
           OR v_job.target_language LIKE rate.target_language || ' (%)')
      AND (rate.specialization_id IS NULL OR rate.specialization_id = v_job.specialization_id);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Select an approved matching base rate from the Resource profile';
    END IF;

    v_offer_id := public.create_job_offer(
        p_job_id, p_resource_id, p_response_due_at, v_rate.unit,
        COALESCE(p_quantity, v_job.quantity), v_rate.rate, v_rate.currency,
        p_message, p_client_identity_disclosed, p_override, p_override_reason
    );

    UPDATE public.job_offers
    SET resource_rate_id = p_resource_rate_id
    WHERE id = v_offer_id;

    RETURN v_offer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT
) TO authenticated;

COMMIT;
