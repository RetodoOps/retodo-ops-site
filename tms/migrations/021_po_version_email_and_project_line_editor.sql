-- RetodoOps TMS — version-aware Supplier PO email and inline Project price lines.
-- Run after 020_supplier_po_gmail_delivery.sql.

BEGIN;

-- Every outbound PO email belongs to one immutable PO version. Re-sending a
-- version creates a new audit record instead of overwriting an earlier send.
ALTER TABLE public.email_records
    ADD COLUMN IF NOT EXISTS po_version INTEGER;

CREATE INDEX IF NOT EXISTS email_records_po_version_idx
    ON public.email_records(purchase_order_id, po_version, created_at DESC);

UPDATE public.email_records record
SET po_version = COALESCE(
        NULLIF(substring(record.subject FROM '[vV]([0-9]+)'), '')::INTEGER,
        1
    )
WHERE record.purchase_order_id IS NOT NULL
  AND record.po_version IS NULL;

UPDATE public.supplier_purchase_orders po
SET current_version = latest.version_number,
    updated_at = NOW()
FROM (
    SELECT purchase_order_id, max(version_number) AS version_number
    FROM public.supplier_po_versions
    GROUP BY purchase_order_id
) latest
WHERE po.id = latest.purchase_order_id
  AND po.current_version IS DISTINCT FROM latest.version_number;

-- Queue rows created by issue/revision RPCs pre-date the version-aware email
-- worker. Tag them at insert time without changing the PO lifecycle RPCs.
CREATE OR REPLACE FUNCTION public.tag_supplier_po_email_queue()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_po public.supplier_purchase_orders%ROWTYPE;
BEGIN
    IF NEW.direction <> 'Outgoing'
       OR NEW.job_id IS NULL
       OR NEW.status <> 'Draft requested'
       OR (NEW.purchase_order_id IS NULL
           AND COALESCE(NEW.subject, '') NOT ILIKE '%purchase order%') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_po
    FROM public.supplier_purchase_orders po
    WHERE po.job_id = NEW.job_id
      AND po.resource_id = NEW.resource_id
      AND po.status IN ('Issued', 'Acknowledged')
    ORDER BY po.created_at DESC
    LIMIT 1;

    IF FOUND THEN
        NEW.purchase_order_id := COALESCE(NEW.purchase_order_id, v_po.id);
        NEW.po_version := COALESCE(NEW.po_version, v_po.current_version);
        NEW.subject := v_po.po_number || ' · V' || NEW.po_version ||
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

-- The latest immutable version is authoritative. This also repairs a PO header
-- whose current_version was rendered stale while the version row still exists.
CREATE OR REPLACE FUNCTION public.prepare_supplier_po_email(p_po_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_job public.project_jobs%ROWTYPE;
    v_resource public.resources%ROWTYPE;
    v_email public.email_records%ROWTYPE;
    v_version_row public.supplier_po_versions%ROWTYPE;
    v_version INTEGER;
    v_snapshot JSONB;
    v_subject TEXT;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    SELECT * INTO v_po
    FROM public.supplier_purchase_orders
    WHERE id = p_po_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier PO not found'; END IF;
    IF v_po.status NOT IN ('Issued', 'Acknowledged') THEN
        RAISE EXCEPTION 'Only an Issued or Acknowledged Supplier PO can be emailed';
    END IF;

    SELECT * INTO v_version_row
    FROM public.supplier_po_versions version
    WHERE version.purchase_order_id = v_po.id
    ORDER BY version.version_number DESC
    LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'The Supplier PO has no issued version snapshot'; END IF;

    v_version := v_version_row.version_number;
    v_snapshot := v_version_row.snapshot;
    v_subject := v_po.po_number || ' · V' || v_version ||
        ' · Supplier Purchase Order';

    IF v_po.current_version IS DISTINCT FROM v_version THEN
        UPDATE public.supplier_purchase_orders
        SET current_version = v_version, updated_at = NOW()
        WHERE id = v_po.id;
        v_po.current_version := v_version;
    END IF;

    SELECT * INTO v_job FROM public.project_jobs WHERE id = v_po.job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'PO Job not found'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_po.resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'PO Resource not found'; END IF;
    IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
        RAISE EXCEPTION 'The assigned Resource has no email address';
    END IF;

    -- Reuse only an untouched queue entry for this exact version.
    SELECT * INTO v_email
    FROM public.email_records record
    WHERE record.direction = 'Outgoing'
      AND record.status = 'Draft requested'
      AND record.attempt_count = 0
      AND record.purchase_order_id = v_po.id
      AND record.po_version = v_version
    ORDER BY record.created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.email_records(
            purchase_order_id, po_version, project_id, job_id, resource_id,
            direction, status, from_address, to_addresses, subject, created_by
        ) VALUES (
            v_po.id, v_version, v_po.project_id, v_po.job_id, v_po.resource_id,
            'Outgoing', 'Draft requested', 'ops@retodo-ops.com',
            ARRAY[v_resource.email], v_subject, auth.uid()
        ) RETURNING * INTO v_email;
    END IF;

    UPDATE public.email_records
    SET purchase_order_id = v_po.id,
        po_version = v_version,
        status = 'Draft requested',
        attempt_count = attempt_count + 1,
        last_attempt_at = NOW(),
        failure_reason = NULL,
        from_address = 'ops@retodo-ops.com',
        to_addresses = ARRAY[v_resource.email],
        subject = v_subject
    WHERE id = v_email.id
    RETURNING * INTO v_email;

    RETURN jsonb_build_object(
        'email_record_id', v_email.id,
        'purchase_order_id', v_po.id,
        'po_number', v_po.po_number,
        'po_status', v_po.status,
        'version', v_version,
        'issued_at', v_po.issued_at,
        'currency', COALESCE(v_snapshot->>'currency', v_po.currency),
        'subtotal', COALESCE((v_snapshot->>'subtotal')::NUMERIC, v_po.subtotal),
        'adjustments', COALESCE(
            (v_snapshot->>'adjustment_amount')::NUMERIC,
            v_po.adjustment_amount
        ),
        'total', COALESCE((v_snapshot->>'total')::NUMERIC, v_po.total),
        'recipient_email', v_resource.email,
        'recipient_name', COALESCE(
            NULLIF(btrim(v_resource.legal_name), ''),
            NULLIF(btrim(v_resource.company_name), ''),
            v_resource.internal_number
        ),
        'internal_number', v_resource.internal_number,
        'payment_terms_days', v_resource.payment_terms_days,
        'invoice_cycle', v_resource.invoice_cycle,
        'job_number', COALESCE(v_snapshot->'job'->>'job_number', v_job.job_number),
        'service', COALESCE(v_snapshot->'job'->>'service_type', v_job.service_type),
        'source_language', COALESCE(
            v_snapshot->'job'->>'source_language', v_job.source_language
        ),
        'target_language', COALESCE(
            v_snapshot->'job'->>'target_language', v_job.target_language
        ),
        'deadline', COALESCE(
            v_snapshot->'job'->>'deadline', v_job.deadline::TEXT
        ),
        'notes', v_job.notes,
        'subject', v_subject,
        'lines', COALESCE(v_snapshot->'lines', '[]'::JSONB)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_supplier_po_email(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_supplier_po_email(UUID) TO authenticated;

-- Project financial rows now share the same clear line model as Supplier POs.
ALTER TABLE public.scope_items
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS adjustment_type TEXT;

ALTER TABLE public.scope_items
    DROP CONSTRAINT IF EXISTS scope_items_adjustment_type_check;
ALTER TABLE public.scope_items
    ADD CONSTRAINT scope_items_adjustment_type_check CHECK (
        adjustment_type IS NULL OR adjustment_type IN (
            'Discount', 'Credit', 'Surcharge', 'Minimum fee'
        )
    );

UPDATE public.scope_items line
SET description = COALESCE(
        NULLIF(btrim(line.description), ''),
        concat_ws(' · ', line.service_type, line.cat_band)
    ),
    adjustment_type = CASE
        WHEN line.adjustment_type IS NOT NULL THEN line.adjustment_type
        WHEN line.service_type = 'Quote discount' OR line.price < 0 THEN 'Discount'
        ELSE NULL
    END
WHERE NULLIF(btrim(line.description), '') IS NULL
   OR line.adjustment_type IS NULL;

CREATE OR REPLACE FUNCTION public.prepare_scope_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_amount NUMERIC;
BEGIN
    NEW.quantity := COALESCE(NEW.quantity, 0);
    NEW.unit_price := COALESCE(NEW.unit_price, 0);
    v_amount := CASE
        WHEN NEW.price_unit = 'Fixed fee' THEN NEW.unit_price
        ELSE NEW.quantity * NEW.unit_price
    END;
    NEW.price := CASE
        WHEN NEW.adjustment_type IN ('Discount', 'Credit')
            THEN -round(abs(v_amount), 2)
        ELSE round(abs(v_amount), 2)
    END;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_prepare_amount ON public.scope_items;
CREATE TRIGGER scope_items_prepare_amount
BEFORE INSERT OR UPDATE OF quantity, price_unit, unit_price, adjustment_type
ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.prepare_scope_amount();

-- Save the PO-style Project line editor atomically. Linked Client/Account rate
-- rows retain their commercial provenance and expose quantity as the only
-- editable value; manual rows may edit every visible line field.
CREATE OR REPLACE FUNCTION public.save_project_financial_lines(
    p_project_id UUID,
    p_lines JSONB,
    p_deleted_ids JSONB DEFAULT '[]'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_line JSONB;
    v_id UUID;
    v_existing public.scope_items%ROWTYPE;
    v_description TEXT;
    v_source TEXT;
    v_reason TEXT;
    v_specialization UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
        RAISE EXCEPTION 'Project not found';
    END IF;
    IF jsonb_typeof(COALESCE(p_lines, '[]'::JSONB)) <> 'array'
       OR jsonb_typeof(COALESCE(p_deleted_ids, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Financial lines must be JSON arrays';
    END IF;

    DELETE FROM public.scope_items line
    WHERE line.project_id = p_project_id
      AND line.id IN (
          SELECT value::UUID
          FROM jsonb_array_elements_text(COALESCE(p_deleted_ids, '[]'::JSONB))
      );

    FOR v_line IN
        SELECT value FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
    LOOP
        v_id := NULLIF(v_line->>'id', '')::UUID;
        v_description := NULLIF(btrim(v_line->>'description'), '');
        v_source := COALESCE(NULLIF(btrim(v_line->>'rate_source'), ''), 'Manual');
        v_reason := NULLIF(btrim(v_line->>'override_reason'), '');
        v_specialization := NULLIF(v_line->>'specialization_id', '')::UUID;

        IF v_description IS NULL THEN
            RAISE EXCEPTION 'Every Project financial line requires a description';
        END IF;
        IF v_source IN ('Manual', 'Fixed') AND v_reason IS NULL THEN
            RAISE EXCEPTION 'A manual or fixed Project line requires a reason';
        END IF;
        IF v_specialization IS NULL THEN
            RAISE EXCEPTION 'Every Project financial line requires a specialization';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.project_specializations link
            WHERE link.project_id = p_project_id
              AND link.specialization_id = v_specialization
        ) THEN
            RAISE EXCEPTION 'Financial line specialization must belong to the Project';
        END IF;

        IF v_id IS NOT NULL THEN
            SELECT * INTO v_existing FROM public.scope_items
            WHERE id = v_id AND project_id = p_project_id
            FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Project financial line not found'; END IF;

            IF v_existing.client_rate_item_id IS NOT NULL THEN
                UPDATE public.scope_items
                SET quantity = COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 0),
                    updated_at = NOW()
                WHERE id = v_id;
            ELSE
                UPDATE public.scope_items
                SET description = v_description,
                    service_type = COALESCE(
                        NULLIF(v_line->>'service_type', ''), service_type
                    ),
                    specialization_id = v_specialization,
                    cat_band = NULLIF(v_line->>'cat_band', ''),
                    quantity = COALESCE(
                        NULLIF(v_line->>'quantity', '')::NUMERIC, 0
                    ),
                    price_unit = COALESCE(
                        NULLIF(v_line->>'price_unit', ''), 'Source words'
                    ),
                    unit_price = COALESCE(
                        NULLIF(v_line->>'unit_price', '')::NUMERIC, 0
                    ),
                    rate_source = v_source,
                    adjustment_type = NULLIF(v_line->>'adjustment_type', ''),
                    override_reason = v_reason,
                    sort_order = COALESCE(
                        NULLIF(v_line->>'sort_order', '')::INTEGER, sort_order
                    ),
                    updated_at = NOW()
                WHERE id = v_id;
            END IF;
        ELSE
            IF v_source IN ('Account', 'Client') THEN
                RAISE EXCEPTION 'New Account/Client lines must be loaded from a rate card';
            END IF;
            INSERT INTO public.scope_items(
                project_id, description, service_type, specialization_id,
                cat_band, quantity, price_unit, unit_price, rate_source,
                adjustment_type, override_reason, sort_order
            ) VALUES (
                p_project_id, v_description,
                COALESCE(NULLIF(v_line->>'service_type', ''), 'Other'),
                v_specialization, NULLIF(v_line->>'cat_band', ''),
                COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 0),
                COALESCE(NULLIF(v_line->>'price_unit', ''), 'Source words'),
                COALESCE(NULLIF(v_line->>'unit_price', '')::NUMERIC, 0),
                v_source, NULLIF(v_line->>'adjustment_type', ''),
                v_reason,
                COALESCE(NULLIF(v_line->>'sort_order', '')::INTEGER, 0)
            );
        END IF;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.save_project_financial_lines(UUID, JSONB, JSONB)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_project_financial_lines(UUID, JSONB, JSONB)
    TO authenticated;

COMMIT;
