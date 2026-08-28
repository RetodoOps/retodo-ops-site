-- RetodoOps TMS — Jobs, Resource offers and Supplier POs
-- Run after 003_resources_module.sql.

BEGIN;

-- A Job is the production task. Candidate invitations live in job_offers.
ALTER TABLE public.project_jobs
    ALTER COLUMN status SET DEFAULT 'Unassigned';

ALTER TABLE public.project_jobs
    DROP CONSTRAINT IF EXISTS project_jobs_status_check;

UPDATE public.project_jobs
SET status = CASE
    WHEN status = 'Offered' AND resource_id IS NULL THEN 'Unassigned'
    WHEN status = 'Offered' THEN 'In Progress'
    WHEN status = 'Declined' THEN 'Cancelled'
    ELSE status
END
WHERE status IN ('Offered', 'Declined');

ALTER TABLE public.project_jobs
    ADD CONSTRAINT project_jobs_status_check CHECK (status IN (
        'Unassigned', 'In Progress', 'Delivered', 'Revision Required',
        'Approved', 'Cancelled'
    ));

ALTER TABLE public.project_jobs
    ADD COLUMN IF NOT EXISTS client_identity_disclosed BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS assigned_from_offer_id UUID,
    ADD COLUMN IF NOT EXISTS assignment_notes TEXT;

CREATE TABLE IF NOT EXISTS public.job_offers (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                      UUID NOT NULL REFERENCES public.project_jobs(id) ON DELETE CASCADE,
    resource_id                 UUID NOT NULL REFERENCES public.resources(id) ON DELETE RESTRICT,
    sequence_number             INTEGER NOT NULL,
    status                      TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
        'Draft', 'Sent', 'Viewed', 'Accepted', 'Declined', 'Expired', 'Withdrawn'
    )),
    response_due_at             TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '4 hours'),
    sent_at                     TIMESTAMPTZ,
    viewed_at                   TIMESTAMPTZ,
    responded_at                TIMESTAMPTZ,
    decline_reason              TEXT,
    message                     TEXT,
    unit                        TEXT CHECK (unit IS NULL OR unit IN (
        'Source words', 'Target words', 'Hours', 'Pages', 'Minutes', 'Fixed fee'
    )),
    quantity                    NUMERIC(14, 3),
    supplier_rate               NUMERIC(14, 4),
    currency                    TEXT NOT NULL DEFAULT 'EUR',
    amount                      NUMERIC(14, 2) NOT NULL DEFAULT 0,
    cat_analysis                JSONB NOT NULL DEFAULT '{}'::JSONB,
    client_identity_disclosed   BOOLEAN NOT NULL DEFAULT FALSE,
    restriction_warning         BOOLEAN NOT NULL DEFAULT FALSE,
    restriction_overridden      BOOLEAN NOT NULL DEFAULT FALSE,
    override_reason             TEXT,
    overridden_by               UUID REFERENCES public.profiles(id),
    overridden_at               TIMESTAMPTZ,
    created_by                  UUID REFERENCES public.profiles(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (job_id, sequence_number)
);

CREATE UNIQUE INDEX IF NOT EXISTS job_offers_one_active_candidate_idx
    ON public.job_offers(job_id)
    WHERE status IN ('Draft', 'Sent', 'Viewed');

CREATE INDEX IF NOT EXISTS job_offers_resource_status_idx
    ON public.job_offers(resource_id, status, response_due_at);

ALTER TABLE public.project_jobs
    DROP CONSTRAINT IF EXISTS project_jobs_assigned_from_offer_id_fkey;
ALTER TABLE public.project_jobs
    ADD CONSTRAINT project_jobs_assigned_from_offer_id_fkey
    FOREIGN KEY (assigned_from_offer_id) REFERENCES public.job_offers(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.supplier_po_counters (
    counter_year INTEGER PRIMARY KEY,
    last_number  INTEGER NOT NULL DEFAULT 0,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.supplier_purchase_orders
    ADD COLUMN IF NOT EXISTS supplier_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
    ADD COLUMN IF NOT EXISTS work_may_begin_before_acknowledgement BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS acknowledgement_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_change_reason TEXT;

ALTER TABLE public.supplier_po_versions
    ADD COLUMN IF NOT EXISTS document_status TEXT NOT NULL DEFAULT 'Draft' CHECK (
        document_status IN ('Draft', 'Issued', 'Revised', 'Cancelled')
    );

CREATE OR REPLACE FUNCTION public.next_supplier_po_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_year INTEGER := EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;
    v_next INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    INSERT INTO public.supplier_po_counters(counter_year, last_number)
    VALUES (v_year, 1)
    ON CONFLICT (counter_year) DO UPDATE
    SET last_number = public.supplier_po_counters.last_number + 1,
        updated_at = NOW()
    RETURNING last_number INTO v_next;

    RETURN 'PO-' || v_year::TEXT || '-' || lpad(v_next::TEXT, 4, '0');
END;
$$;

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

    IF TG_OP = 'INSERT' AND COALESCE(NEW.sequence_number, 0) < 1 THEN
        PERFORM pg_advisory_xact_lock(hashtext(NEW.job_id::TEXT || ':offer'));
        SELECT COALESCE(max(sequence_number), 0) + 1 INTO v_sequence
        FROM public.job_offers WHERE job_id = NEW.job_id;
        NEW.sequence_number := v_sequence;
    END IF;

    NEW.restriction_warning := (
        NOT v_resource.assignment_approved
        OR v_resource.eligibility_status <> 'Eligible'
        OR v_resource.classification IN (
            'Hold — Inactive', 'Hold — Unavailable',
            'Hold — Terms not accepted', 'Do not use'
        )
        OR v_resource.compliance_status <> 'Valid'
        OR (v_resource.compliance_expiry IS NOT NULL
            AND v_resource.compliance_expiry < CURRENT_DATE)
    );

    IF NEW.restriction_warning THEN
        IF NOT NEW.restriction_overridden THEN
            RAISE EXCEPTION 'Resource is not eligible for an offer; Administrator override required';
        END IF;
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can override Resource eligibility';
        END IF;
        IF NULLIF(btrim(NEW.override_reason), '') IS NULL THEN
            RAISE EXCEPTION 'An override reason is required';
        END IF;
        NEW.overridden_by := auth.uid();
        NEW.overridden_at := NOW();
    ELSE
        NEW.restriction_overridden := FALSE;
        NEW.override_reason := NULL;
        NEW.overridden_by := NULL;
        NEW.overridden_at := NULL;
    END IF;

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

DROP TRIGGER IF EXISTS job_offers_prepare ON public.job_offers;
CREATE TRIGGER job_offers_prepare
BEFORE INSERT OR UPDATE ON public.job_offers
FOR EACH ROW EXECUTE FUNCTION public.prepare_job_offer();

CREATE OR REPLACE FUNCTION public.prepare_supplier_po_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF COALESCE(NEW.amount, 0) = 0
       AND NEW.quantity IS NOT NULL AND NEW.unit_price IS NOT NULL THEN
        NEW.amount := round(NEW.quantity * NEW.unit_price, 2);
    END IF;
    IF NEW.adjustment_type IN ('Discount', 'Credit') THEN
        NEW.amount := -abs(NEW.amount);
    ELSIF NEW.adjustment_type IN ('Surcharge', 'Minimum fee') THEN
        NEW.amount := abs(NEW.amount);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.protect_supplier_po_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po_id UUID := CASE WHEN TG_OP = 'DELETE' THEN OLD.purchase_order_id ELSE NEW.purchase_order_id END;
    v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM public.supplier_purchase_orders WHERE id = v_po_id;
    IF v_status <> 'Draft'
       AND COALESCE(current_setting('retodo.po_revision', TRUE), '') <> 'on' THEN
        RAISE EXCEPTION 'Issued PO lines are locked; create an Administrator revision';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_supplier_po()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po_id UUID := CASE WHEN TG_OP = 'DELETE' THEN OLD.purchase_order_id ELSE NEW.purchase_order_id END;
BEGIN
    UPDATE public.supplier_purchase_orders po
    SET subtotal = COALESCE((
            SELECT sum(line.amount) FROM public.supplier_po_lines line
            WHERE line.purchase_order_id = v_po_id AND line.adjustment_type IS NULL
        ), 0),
        adjustment_amount = COALESCE((
            SELECT sum(line.amount) FROM public.supplier_po_lines line
            WHERE line.purchase_order_id = v_po_id AND line.adjustment_type IS NOT NULL
        ), 0),
        total = COALESCE((
            SELECT sum(line.amount) FROM public.supplier_po_lines line
            WHERE line.purchase_order_id = v_po_id
        ), 0),
        updated_at = NOW()
    WHERE po.id = v_po_id;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_po_lines_protect ON public.supplier_po_lines;
CREATE TRIGGER supplier_po_lines_protect
BEFORE INSERT OR UPDATE OR DELETE ON public.supplier_po_lines
FOR EACH ROW EXECUTE FUNCTION public.protect_supplier_po_line();

DROP TRIGGER IF EXISTS supplier_po_lines_prepare ON public.supplier_po_lines;
CREATE TRIGGER supplier_po_lines_prepare
BEFORE INSERT OR UPDATE ON public.supplier_po_lines
FOR EACH ROW EXECUTE FUNCTION public.prepare_supplier_po_line();

DROP TRIGGER IF EXISTS supplier_po_lines_recalculate ON public.supplier_po_lines;
CREATE TRIGGER supplier_po_lines_recalculate
AFTER INSERT OR UPDATE OR DELETE ON public.supplier_po_lines
FOR EACH ROW EXECUTE FUNCTION public.recalculate_supplier_po();

CREATE INDEX IF NOT EXISTS supplier_po_job_idx
    ON public.supplier_purchase_orders(job_id, status);

CREATE OR REPLACE FUNCTION public.create_job_offer(
    p_job_id UUID,
    p_resource_id UUID,
    p_response_due_at TIMESTAMPTZ DEFAULT NULL,
    p_unit TEXT DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_supplier_rate NUMERIC DEFAULT NULL,
    p_currency TEXT DEFAULT 'EUR',
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
    v_sequence INTEGER;
    v_unit TEXT;
    v_quantity NUMERIC;
    v_supplier_rate NUMERIC;
    v_currency TEXT;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF p_client_identity_disclosed AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only the Administrator can disclose Client identity';
    END IF;

    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    IF v_job.status IN ('Approved', 'Cancelled') THEN
        RAISE EXCEPTION 'Offers cannot be created for a closed Job';
    END IF;
    IF v_job.resource_id IS NOT NULL THEN
        RAISE EXCEPTION 'This Job already has an assigned Resource';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.job_offers
        WHERE job_id = p_job_id AND status IN ('Draft', 'Sent', 'Viewed')
    ) THEN
        RAISE EXCEPTION 'Withdraw or resolve the active offer before selecting another candidate';
    END IF;

    v_unit := COALESCE(p_unit, v_job.unit);
    v_quantity := COALESCE(p_quantity, v_job.quantity);
    v_supplier_rate := p_supplier_rate;
    v_currency := COALESCE(NULLIF(p_currency, ''), v_job.supplier_currency, 'EUR');

    IF v_supplier_rate IS NULL THEN
        SELECT * INTO v_rate
        FROM public.resource_rates rate
        WHERE rate.resource_id = p_resource_id
          AND rate.status = 'Approved'
          AND rate.service_type = v_job.service_type
          AND rate.unit = v_unit
          AND (rate.source_language IS NULL OR rate.source_language = v_job.source_language)
          AND (rate.target_language IS NULL OR rate.target_language = v_job.target_language)
          AND (rate.specialization_id IS NULL OR rate.specialization_id = v_job.specialization_id)
          AND (rate.valid_from IS NULL OR rate.valid_from <= CURRENT_DATE)
          AND (rate.valid_to IS NULL OR rate.valid_to >= CURRENT_DATE)
        ORDER BY (rate.specialization_id IS NOT NULL) DESC,
                 (rate.source_language IS NOT NULL) DESC,
                 rate.approved_at DESC NULLS LAST
        LIMIT 1;
        IF FOUND THEN
            v_supplier_rate := v_rate.rate;
            v_currency := v_rate.currency;
        END IF;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_job_id::TEXT || ':offer'));
    SELECT COALESCE(max(sequence_number), 0) + 1 INTO v_sequence
    FROM public.job_offers WHERE job_id = p_job_id;

    INSERT INTO public.job_offers (
        job_id, resource_id, sequence_number, response_due_at, unit, quantity,
        supplier_rate, currency, message, client_identity_disclosed,
        restriction_overridden, override_reason, created_by
    ) VALUES (
        p_job_id, p_resource_id, v_sequence,
        COALESCE(p_response_due_at, NOW() + INTERVAL '4 hours'),
        v_unit, v_quantity, v_supplier_rate, v_currency, NULLIF(btrim(p_message), ''),
        p_client_identity_disclosed, p_override, NULLIF(btrim(p_override_reason), ''),
        auth.uid()
    ) RETURNING id INTO v_offer_id;

    RETURN v_offer_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_job_offer(p_offer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_offer public.job_offers%ROWTYPE;
    v_job public.project_jobs%ROWTYPE;
    v_resource public.resources%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_offer FROM public.job_offers WHERE id = p_offer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Offer not found'; END IF;
    IF v_offer.status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft offer can be sent'; END IF;
    SELECT * INTO v_job FROM public.project_jobs WHERE id = v_offer.job_id;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_offer.resource_id;
    IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
        RAISE EXCEPTION 'Resource has no email address';
    END IF;

    UPDATE public.job_offers SET status = 'Sent' WHERE id = p_offer_id;
    INSERT INTO public.email_records (
        project_id, job_id, resource_id, direction, status, from_address,
        to_addresses, subject, created_by
    ) VALUES (
        v_job.project_id, v_job.id, v_resource.id, 'Outgoing', 'Draft requested',
        'ops@retodo-ops.com', ARRAY[v_resource.email],
        'Job offer ' || v_job.job_number, auth.uid()
    );
END;
$$;

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
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF p_response NOT IN ('Accepted', 'Declined') THEN
        RAISE EXCEPTION 'Response must be Accepted or Declined';
    END IF;

    SELECT * INTO v_offer FROM public.job_offers WHERE id = p_offer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Offer not found'; END IF;
    IF v_offer.status NOT IN ('Sent', 'Viewed') THEN
        RAISE EXCEPTION 'Only a sent offer can be answered';
    END IF;

    IF p_response = 'Declined' THEN
        UPDATE public.job_offers
        SET status = 'Declined', decline_reason = NULLIF(btrim(p_decline_reason), '')
        WHERE id = p_offer_id;
        RETURN NULL;
    END IF;

    SELECT * INTO v_job FROM public.project_jobs WHERE id = v_offer.job_id FOR UPDATE;
    IF v_job.resource_id IS NOT NULL THEN RAISE EXCEPTION 'Job already has an assigned Resource'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_offer.resource_id;

    UPDATE public.job_offers SET status = 'Accepted' WHERE id = p_offer_id;
    UPDATE public.project_jobs
    SET resource_id = v_offer.resource_id,
        assigned_from_offer_id = v_offer.id,
        status = 'In Progress',
        accepted_at = NOW(),
        unit = v_offer.unit,
        quantity = v_offer.quantity,
        supplier_rate = v_offer.supplier_rate,
        supplier_currency = v_offer.currency,
        supplier_amount = v_offer.amount,
        cat_analysis = v_offer.cat_analysis,
        client_identity_disclosed = v_offer.client_identity_disclosed,
        restriction_overridden = v_offer.restriction_overridden,
        override_reason = v_offer.override_reason
    WHERE id = v_job.id;

    IF v_job.po_required THEN
        v_po_number := public.next_supplier_po_number();
        INSERT INTO public.supplier_purchase_orders (
            po_number, resource_id, project_id, job_id, status, currency,
            supplier_snapshot, work_may_begin_before_acknowledgement, created_by
        ) VALUES (
            v_po_number, v_resource.id, v_job.project_id, v_job.id, 'Draft',
            v_offer.currency,
            jsonb_build_object(
                'internal_number', v_resource.internal_number,
                'legal_name', v_resource.legal_name,
                'company_name', v_resource.company_name,
                'email', v_resource.email,
                'tax_id', v_resource.tax_id,
                'payment_terms_days', v_resource.payment_terms_days,
                'invoice_cycle', v_resource.invoice_cycle
            ), TRUE, auth.uid()
        ) RETURNING id INTO v_po_id;

        INSERT INTO public.supplier_po_lines (
            purchase_order_id, description, quantity, unit, unit_price, amount, sort_order
        ) VALUES (
            v_po_id,
            concat_ws(' · ', v_job.service_type,
                NULLIF(concat_ws(' → ', v_job.source_language, v_job.target_language), '')),
            v_offer.quantity, v_offer.unit, v_offer.supplier_rate, v_offer.amount, 10
        );
    END IF;

    RETURN v_po_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_job_offer(p_offer_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'A withdrawal reason is required'; END IF;
    UPDATE public.job_offers
    SET status = 'Withdrawn', decline_reason = btrim(p_reason), responded_at = NOW()
    WHERE id = p_offer_id AND status IN ('Draft', 'Sent', 'Viewed');
    IF NOT FOUND THEN RAISE EXCEPTION 'No active offer found'; END IF;
END;
$$;

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
    WHERE public.is_company_user() AND po.id = p_po_id;
$$;

CREATE OR REPLACE FUNCTION public.save_supplier_po_draft(p_po_id UUID, p_lines JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_line JSONB;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'At least one PO line is required';
    END IF;
    SELECT status INTO v_status FROM public.supplier_purchase_orders WHERE id = p_po_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier PO not found'; END IF;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft PO can be edited directly'; END IF;

    DELETE FROM public.supplier_po_lines WHERE purchase_order_id = p_po_id;
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        INSERT INTO public.supplier_po_lines (
            purchase_order_id, description, quantity, unit, unit_price,
            adjustment_type, amount, sort_order
        ) VALUES (
            p_po_id, NULLIF(btrim(v_line->>'description'), ''),
            NULLIF(v_line->>'quantity', '')::NUMERIC,
            NULLIF(v_line->>'unit', ''), NULLIF(v_line->>'unit_price', '')::NUMERIC,
            NULLIF(v_line->>'adjustment_type', ''),
            COALESCE(NULLIF(v_line->>'amount', '')::NUMERIC, 0),
            COALESCE(NULLIF(v_line->>'sort_order', '')::INTEGER, 0)
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_supplier_po(p_po_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_snapshot JSONB;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only the Administrator can issue a Supplier PO'; END IF;
    SELECT * INTO v_po FROM public.supplier_purchase_orders WHERE id = p_po_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier PO not found'; END IF;
    IF v_po.status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft PO can be issued'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.supplier_po_lines WHERE purchase_order_id = p_po_id) THEN
        RAISE EXCEPTION 'The PO requires at least one line';
    END IF;

    UPDATE public.supplier_purchase_orders
    SET status = 'Issued', current_version = 1, issued_at = NOW(),
        acknowledgement_requested_at = NOW()
    WHERE id = p_po_id;

    v_snapshot := public.supplier_po_snapshot(p_po_id);
    INSERT INTO public.supplier_po_versions (
        purchase_order_id, version_number, snapshot, document_status, created_by
    ) VALUES (p_po_id, 1, v_snapshot, 'Issued', auth.uid())
    ON CONFLICT (purchase_order_id, version_number) DO UPDATE
    SET snapshot = EXCLUDED.snapshot, document_status = EXCLUDED.document_status,
        created_by = EXCLUDED.created_by, created_at = NOW();

    INSERT INTO public.email_records (
        project_id, job_id, resource_id, direction, status, from_address,
        to_addresses, subject, created_by
    )
    SELECT po.project_id, po.job_id, po.resource_id, 'Outgoing', 'Draft requested',
           'ops@retodo-ops.com', ARRAY[r.email],
           po.po_number || ' · Supplier purchase order', auth.uid()
    FROM public.supplier_purchase_orders po
    JOIN public.resources r ON r.id = po.resource_id
    WHERE po.id = p_po_id AND NULLIF(btrim(r.email), '') IS NOT NULL;

    RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.revise_supplier_po(
    p_po_id UUID,
    p_lines JSONB,
    p_reason TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_line JSONB;
    v_new_version INTEGER;
    v_snapshot JSONB;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only the Administrator can revise a Supplier PO'; END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'A revision reason is required'; END IF;
    IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'At least one PO line is required';
    END IF;

    SELECT * INTO v_po FROM public.supplier_purchase_orders WHERE id = p_po_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier PO not found'; END IF;
    IF v_po.status NOT IN ('Issued', 'Acknowledged') THEN
        RAISE EXCEPTION 'Only an Issued or Acknowledged PO can be revised';
    END IF;

    PERFORM set_config('retodo.po_revision', 'on', TRUE);
    DELETE FROM public.supplier_po_lines WHERE purchase_order_id = p_po_id;
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        INSERT INTO public.supplier_po_lines (
            purchase_order_id, description, quantity, unit, unit_price,
            adjustment_type, amount, sort_order
        ) VALUES (
            p_po_id, NULLIF(btrim(v_line->>'description'), ''),
            NULLIF(v_line->>'quantity', '')::NUMERIC,
            NULLIF(v_line->>'unit', ''), NULLIF(v_line->>'unit_price', '')::NUMERIC,
            NULLIF(v_line->>'adjustment_type', ''),
            COALESCE(NULLIF(v_line->>'amount', '')::NUMERIC, 0),
            COALESCE(NULLIF(v_line->>'sort_order', '')::INTEGER, 0)
        );
    END LOOP;

    v_new_version := v_po.current_version + 1;
    UPDATE public.supplier_purchase_orders
    SET current_version = v_new_version, status = 'Issued',
        last_change_reason = btrim(p_reason), acknowledgement_requested_at = NOW()
    WHERE id = p_po_id;
    v_snapshot := public.supplier_po_snapshot(p_po_id);

    INSERT INTO public.supplier_po_versions (
        purchase_order_id, version_number, snapshot, document_status,
        change_reason, created_by
    ) VALUES (
        p_po_id, v_new_version, v_snapshot, 'Revised', btrim(p_reason), auth.uid()
    );

    INSERT INTO public.email_records (
        project_id, job_id, resource_id, direction, status, from_address,
        to_addresses, subject, created_by
    )
    SELECT po.project_id, po.job_id, po.resource_id, 'Outgoing', 'Draft requested',
           'ops@retodo-ops.com', ARRAY[r.email],
           po.po_number || ' · Revised Supplier purchase order v' || v_new_version,
           auth.uid()
    FROM public.supplier_purchase_orders po
    JOIN public.resources r ON r.id = po.resource_id
    WHERE po.id = p_po_id AND NULLIF(btrim(r.email), '') IS NOT NULL;

    RETURN v_new_version;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_job_offers()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    UPDATE public.job_offers
    SET status = 'Expired', responded_at = NOW()
    WHERE status IN ('Sent', 'Viewed') AND response_due_at < NOW();
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

ALTER TABLE public.job_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_po_counters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS job_offers_company_select ON public.job_offers;
CREATE POLICY job_offers_company_select ON public.job_offers
FOR SELECT TO authenticated USING (public.is_company_user());

DROP POLICY IF EXISTS job_offers_operations_write ON public.job_offers;
CREATE POLICY job_offers_operations_write ON public.job_offers
FOR ALL TO authenticated
USING (public.can_manage_operations()) WITH CHECK (public.can_manage_operations());

DROP POLICY IF EXISTS supplier_po_counters_admin_all ON public.supplier_po_counters;
CREATE POLICY supplier_po_counters_admin_all ON public.supplier_po_counters
FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP TRIGGER IF EXISTS job_offers_set_updated_at ON public.job_offers;
CREATE TRIGGER job_offers_set_updated_at BEFORE UPDATE ON public.job_offers
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.job_offers TO authenticated;
GRANT SELECT ON public.supplier_po_counters TO authenticated;

REVOKE ALL ON FUNCTION public.next_supplier_po_number() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_job_offer(UUID, UUID, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_job_offer(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.respond_job_offer(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.withdraw_job_offer(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.supplier_po_snapshot(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_supplier_po_draft(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.issue_supplier_po(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revise_supplier_po(UUID, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_job_offers() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.next_supplier_po_number() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_job_offer(UUID, UUID, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_job_offer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_job_offer(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_job_offer(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.supplier_po_snapshot(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_supplier_po_draft(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_supplier_po(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revise_supplier_po(UUID, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_job_offers() TO authenticated;

COMMIT;
