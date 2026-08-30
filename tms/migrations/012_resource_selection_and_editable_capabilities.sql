-- RetodoOps TMS — status-only Resource selection and editable capabilities
-- Run after 011_client_rate_cards_and_simplified_project_grid.sql.

BEGIN;

-- Current rate-card rows can be retired without removing the exact rate IDs
-- retained by historical Offers, Jobs and Supplier PO lines.
ALTER TABLE public.resource_rates
    ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS resource_rates_active_base_idx
    ON public.resource_rates(resource_id, active, base_rate_id, status);

-- Resource selection is controlled only by lifecycle + unified Resource status.
-- Capability, qualification, availability and compliance data remain visible
-- as operational context, but they do not disable an otherwise selectable row.
CREATE OR REPLACE FUNCTION public.search_job_candidates(
    p_job_id UUID,
    p_search TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    id UUID,
    internal_number TEXT,
    legal_name TEXT,
    company_name TEXT,
    resource_status TEXT,
    lifecycle_status TEXT,
    source_languages TEXT[],
    target_languages TEXT[],
    services TEXT[],
    specialization_qualification TEXT,
    account_qualification TEXT,
    compliance_status TEXT,
    availability_status TEXT,
    candidate_state TEXT,
    requires_override BOOLEAN,
    warning_text TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.project_jobs%ROWTYPE;
    v_project public.projects%ROWTYPE;
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;
    SELECT * INTO v_job FROM public.project_jobs WHERE project_jobs.id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE projects.id = v_job.project_id;

    RETURN QUERY
    WITH candidates AS (
        SELECT r.*,
            COALESCE(rs.qualification_status, 'Not tested') AS spec_status,
            CASE WHEN v_project.account_id IS NULL THEN 'Not applicable'
                 ELSE COALESCE(account_specific.qualification_status,
                               account_general.qualification_status, 'Not tested') END
                AS account_status,
            COALESCE(current_availability.status, 'Unknown') AS current_availability,
            EXISTS (
                SELECT 1 FROM public.resource_language_pairs pair
                WHERE pair.resource_id = r.id
                  AND (pair.source_language = v_job.source_language
                       OR v_job.source_language LIKE pair.source_language || ' (%)')
                  AND (pair.target_language = v_job.target_language
                       OR v_job.target_language LIKE pair.target_language || ' (%)')
            ) AS has_job_pair,
            EXISTS (
                SELECT 1 FROM public.resource_services service
                WHERE service.resource_id = r.id
                  AND service.service_type = v_job.service_type
            ) AS has_job_service
        FROM public.resources r
        LEFT JOIN public.resource_specializations rs
          ON rs.resource_id = r.id AND rs.specialization_id = v_job.specialization_id
        LEFT JOIN public.resource_account_qualifications account_specific
          ON account_specific.resource_id = r.id
         AND account_specific.account_id = v_project.account_id
         AND account_specific.specialization_id = v_job.specialization_id
        LEFT JOIN public.resource_account_qualifications account_general
          ON account_general.resource_id = r.id
         AND account_general.account_id = v_project.account_id
         AND account_general.specialization_id IS NULL
        LEFT JOIN LATERAL (
            SELECT availability.status
            FROM public.resource_availability availability
            WHERE availability.resource_id = r.id
              AND availability.starts_at <= NOW()
              AND (availability.ends_at IS NULL OR availability.ends_at >= NOW())
            ORDER BY availability.starts_at DESC LIMIT 1
        ) current_availability ON TRUE
        WHERE r.resource_type <> 'Internal'
          AND r.lifecycle_status = 'Active'
          AND r.resource_status IN ('Assignable', 'Proven', 'Preferred')
          AND (NULLIF(btrim(p_search), '') IS NULL OR concat_ws(' ',
                r.internal_number, r.legal_name, r.company_name, r.initials, r.email
              ) ILIKE '%' || btrim(p_search) || '%')
    )
    SELECT c.id, c.internal_number, c.legal_name, c.company_name,
        c.resource_status, c.lifecycle_status,
        ARRAY(SELECT DISTINCT pair.source_language
              FROM public.resource_language_pairs pair
              WHERE pair.resource_id = c.id ORDER BY 1),
        ARRAY(SELECT DISTINCT pair.target_language
              FROM public.resource_language_pairs pair
              WHERE pair.resource_id = c.id ORDER BY 1),
        ARRAY(SELECT DISTINCT service.service_type
              FROM public.resource_services service
              WHERE service.resource_id = c.id ORDER BY 1),
        c.spec_status, c.account_status, c.compliance_status,
        c.current_availability,
        'Ready'::TEXT,
        FALSE,
        concat_ws(' · ',
            CASE WHEN NOT c.has_job_pair THEN 'Job language pair not recorded' END,
            CASE WHEN NOT c.has_job_service THEN 'Job service not recorded' END,
            CASE WHEN c.spec_status <> 'Approved'
                 THEN 'Domain ' || lower(c.spec_status) END,
            CASE WHEN c.account_status NOT IN ('Approved', 'Not applicable')
                 THEN 'Account ' || lower(c.account_status) END,
            CASE WHEN c.compliance_status NOT IN ('Valid', 'Waived')
                 THEN 'Compliance ' || c.compliance_status
                 WHEN c.compliance_expiry IS NOT NULL
                      AND c.compliance_expiry < CURRENT_DATE
                 THEN 'Compliance expired' END,
            CASE WHEN c.current_availability IN ('Limited', 'Unavailable')
                 THEN 'Availability ' || c.current_availability END
        )
    FROM candidates c
    ORDER BY CASE c.resource_status
        WHEN 'Preferred' THEN 1 WHEN 'Proven' THEN 2 ELSE 3 END,
        COALESCE(c.legal_name, c.company_name), c.internal_number
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200);
END;
$$;

-- Offer and assignment protection now follows the same single source of truth.
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
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
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

    IF NEW.unit = 'Fixed fee' AND NEW.supplier_rate IS NOT NULL THEN
        NEW.amount := round(NEW.supplier_rate, 2);
    ELSIF NEW.quantity IS NOT NULL AND NEW.supplier_rate IS NOT NULL THEN
        NEW.amount := round(NEW.quantity * NEW.supplier_rate, 2);
    END IF;
    IF NEW.status = 'Sent' AND NEW.sent_at IS NULL THEN NEW.sent_at := NOW(); END IF;
    IF NEW.status = 'Viewed' AND NEW.viewed_at IS NULL THEN NEW.viewed_at := NOW(); END IF;
    IF NEW.status IN ('Accepted', 'Declined') AND NEW.responded_at IS NULL THEN
        NEW.responded_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;

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
        SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
        IF v_resource.lifecycle_status <> 'Active'
           OR v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred') THEN
            RAISE EXCEPTION 'Only an Active Assignable, Proven or Preferred Resource may receive a new Job assignment';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- One RPC creates or updates a complete Supplier rate card and its calculated
-- CAT rows. Missing CAT rows are retired rather than deleted so historical
-- provenance remains intact.
CREATE OR REPLACE FUNCTION public.save_resource_rate_card(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base_id UUID := NULLIF(p_payload->>'base_rate_id', '')::UUID;
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
    v_discount JSONB;
    v_band TEXT;
    v_percent NUMERIC;
    v_child_id UUID;
    v_seen_bands TEXT[] := ARRAY[]::TEXT[];
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
          AND pair.source_language = v_source AND pair.target_language = v_target
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

    IF v_base_id IS NULL THEN
        INSERT INTO public.resource_rates (
            resource_id, source_language, target_language, service_type,
            specialization_id, unit, cat_band, rate, currency, minimum_fee,
            status, valid_from, valid_to, approved_by, approved_at, active
        ) VALUES (
            v_resource_id, v_source, v_target, v_service,
            v_specialization_id, v_unit, NULL, v_base_rate, v_currency,
            v_minimum_fee, v_status, NULL, NULL,
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
        SET source_language = v_source, target_language = v_target,
            service_type = v_service, specialization_id = v_specialization_id,
            unit = v_unit, rate = v_base_rate, currency = v_currency,
            minimum_fee = v_minimum_fee, status = v_status,
            approved_by = CASE WHEN v_status = 'Approved' THEN auth.uid() ELSE NULL END,
            approved_at = CASE WHEN v_status = 'Approved' THEN NOW() ELSE NULL END,
            valid_from = NULL, valid_to = NULL, active = TRUE, updated_at = NOW()
        WHERE id = v_base_id;

        UPDATE public.resource_rates
        SET active = FALSE, updated_at = NOW()
        WHERE base_rate_id = v_base_id;
    END IF;

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
        IF lower(v_band) = ANY(v_seen_bands) THEN
            RAISE EXCEPTION 'Duplicate CAT band: %', v_band;
        END IF;
        v_seen_bands := array_append(v_seen_bands, lower(v_band));

        SELECT child.id INTO v_child_id
        FROM public.resource_rates child
        WHERE child.base_rate_id = v_base_id
          AND lower(child.cat_band) = lower(v_band)
        LIMIT 1;

        IF v_child_id IS NULL THEN
            INSERT INTO public.resource_rates (
                resource_id, base_rate_id, cat_band, discount_percent,
                source_language, target_language, service_type,
                specialization_id, unit, rate, currency, minimum_fee,
                status, active
            ) VALUES (
                v_resource_id, v_base_id, v_band, v_percent,
                v_source, v_target, v_service, v_specialization_id, v_unit,
                v_base_rate, v_currency, v_minimum_fee, v_status, TRUE
            );
        ELSE
            UPDATE public.resource_rates
            SET discount_percent = v_percent, active = TRUE, updated_at = NOW()
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
    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;

    SELECT * INTO v_rate
    FROM public.resource_rates rate
    WHERE rate.id = p_resource_rate_id
      AND rate.resource_id = p_resource_id
      AND rate.active
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
      AND (rate.specialization_id IS NULL
           OR rate.specialization_id = v_job.specialization_id);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Select an active approved matching base rate from the Resource profile';
    END IF;

    v_offer_id := public.create_job_offer(
        p_job_id, p_resource_id, p_response_due_at, v_rate.unit,
        COALESCE(p_quantity, v_job.quantity), v_rate.rate, v_rate.currency,
        p_message, p_client_identity_disclosed, p_override, p_override_reason
    );
    UPDATE public.job_offers SET resource_rate_id = p_resource_rate_id
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

CREATE OR REPLACE FUNCTION public.remove_resource_language_pair(p_pair_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pair public.resource_language_pairs%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_pair FROM public.resource_language_pairs WHERE id = p_pair_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Resource language pair not found'; END IF;

    UPDATE public.resource_rates
    SET active = FALSE, updated_at = NOW()
    WHERE resource_id = v_pair.resource_id
      AND base_rate_id IS NULL
      AND source_language = v_pair.source_language
      AND target_language = v_pair.target_language;
    DELETE FROM public.resource_language_pairs WHERE id = p_pair_id;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_resource_language_pair(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_resource_language_pair(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_resource_service(
    p_resource_id UUID,
    p_service_type TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.resource_services service
        WHERE service.resource_id = p_resource_id
          AND service.service_type = p_service_type
    ) THEN
        RAISE EXCEPTION 'Resource service not found';
    END IF;

    UPDATE public.resource_rates
    SET active = FALSE, updated_at = NOW()
    WHERE resource_id = p_resource_id AND base_rate_id IS NULL
      AND service_type = p_service_type;
    DELETE FROM public.resource_services
    WHERE resource_id = p_resource_id AND service_type = p_service_type;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_resource_service(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_resource_service(UUID, TEXT) TO authenticated;

COMMENT ON COLUMN public.resource_rates.active IS
    'Current operational availability. Historical Offer, Job and PO snapshots remain unchanged when a rate card is retired.';

COMMIT;
