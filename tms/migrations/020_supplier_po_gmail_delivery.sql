-- RetodoOps TMS — auditable Gmail delivery for Supplier purchase orders.
-- Run after 019_remove_legacy_job_eligibility.sql.

BEGIN;

ALTER TABLE public.email_records
    ADD COLUMN IF NOT EXISTS purchase_order_id UUID
        REFERENCES public.supplier_purchase_orders(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS failure_reason TEXT;

CREATE INDEX IF NOT EXISTS email_records_purchase_order_idx
    ON public.email_records(purchase_order_id, created_at DESC);

-- Reserve one email attempt and return only the operational facts required by
-- the Netlify sender. Client and Account identities remain undisclosed.
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
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    SELECT * INTO v_po
    FROM public.supplier_purchase_orders
    WHERE id = p_po_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier PO not found'; END IF;
    IF v_po.status NOT IN ('Issued', 'Acknowledged') THEN
        RAISE EXCEPTION 'Only an Issued or Acknowledged Supplier PO can be emailed';
    END IF;

    SELECT * INTO v_job FROM public.project_jobs WHERE id = v_po.job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'PO Job not found'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_po.resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'PO Resource not found'; END IF;
    IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
        RAISE EXCEPTION 'The assigned Resource has no email address';
    END IF;

    -- Reuse only the untouched queue entry created atomically with the PO.
    SELECT * INTO v_email
    FROM public.email_records record
    WHERE record.direction = 'Outgoing'
      AND record.status = 'Draft requested'
      AND record.attempt_count = 0
      AND (
          record.purchase_order_id = v_po.id
          OR (record.purchase_order_id IS NULL
              AND record.job_id = v_po.job_id
              AND record.resource_id = v_po.resource_id)
      )
    ORDER BY record.created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.email_records(
            purchase_order_id, project_id, job_id, resource_id, direction,
            status, from_address, to_addresses, subject, created_by
        ) VALUES (
            v_po.id, v_po.project_id, v_po.job_id, v_po.resource_id, 'Outgoing',
            'Draft requested', 'ops@retodo-ops.com', ARRAY[v_resource.email],
            v_po.po_number || ' · Supplier purchase order', auth.uid()
        ) RETURNING * INTO v_email;
    END IF;

    UPDATE public.email_records
    SET purchase_order_id = v_po.id,
        status = 'Draft requested',
        attempt_count = attempt_count + 1,
        last_attempt_at = NOW(),
        failure_reason = NULL,
        from_address = 'ops@retodo-ops.com',
        to_addresses = ARRAY[v_resource.email],
        subject = v_po.po_number || ' · Supplier purchase order'
    WHERE id = v_email.id
    RETURNING * INTO v_email;

    RETURN jsonb_build_object(
        'email_record_id', v_email.id,
        'purchase_order_id', v_po.id,
        'po_number', v_po.po_number,
        'po_status', v_po.status,
        'version', v_po.current_version,
        'issued_at', v_po.issued_at,
        'currency', v_po.currency,
        'subtotal', v_po.subtotal,
        'adjustments', v_po.adjustment_amount,
        'total', v_po.total,
        'recipient_email', v_resource.email,
        'recipient_name', COALESCE(
            NULLIF(btrim(v_resource.legal_name), ''),
            NULLIF(btrim(v_resource.company_name), ''),
            v_resource.internal_number
        ),
        'internal_number', v_resource.internal_number,
        'payment_terms_days', v_resource.payment_terms_days,
        'invoice_cycle', v_resource.invoice_cycle,
        'job_number', v_job.job_number,
        'service', v_job.service_type,
        'source_language', v_job.source_language,
        'target_language', v_job.target_language,
        'deadline', v_job.deadline,
        'notes', v_job.notes,
        'subject', v_email.subject,
        'lines', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'description', line.description,
                'quantity', line.quantity,
                'unit', line.unit,
                'unit_price', line.unit_price,
                'adjustment_type', line.adjustment_type,
                'amount', line.amount
            ) ORDER BY line.sort_order, line.created_at)
            FROM public.supplier_po_lines line
            WHERE line.purchase_order_id = v_po.id
        ), '[]'::JSONB)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_supplier_po_email(
    p_email_record_id UUID,
    p_gmail_message_id TEXT,
    p_gmail_thread_id TEXT DEFAULT NULL
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
    UPDATE public.email_records
    SET status = 'Sent',
        gmail_message_id = NULLIF(btrim(p_gmail_message_id), ''),
        gmail_thread_id = NULLIF(btrim(p_gmail_thread_id), ''),
        external_url = CASE
            WHEN NULLIF(btrim(p_gmail_thread_id), '') IS NOT NULL
                THEN 'https://mail.google.com/mail/u/0/#sent/' || btrim(p_gmail_thread_id)
            WHEN NULLIF(btrim(p_gmail_message_id), '') IS NOT NULL
                THEN 'https://mail.google.com/mail/u/0/#sent/' || btrim(p_gmail_message_id)
            ELSE NULL
        END,
        sent_at = NOW(),
        failure_reason = NULL
    WHERE id = p_email_record_id
      AND direction = 'Outgoing';
    IF NOT FOUND THEN RAISE EXCEPTION 'Email audit record not found'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_supplier_po_email(
    p_email_record_id UUID,
    p_failure_reason TEXT
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
    UPDATE public.email_records
    SET status = 'Failed',
        failure_reason = left(COALESCE(NULLIF(btrim(p_failure_reason), ''),
            'Unknown email delivery error'), 1000)
    WHERE id = p_email_record_id
      AND direction = 'Outgoing';
    IF NOT FOUND THEN RAISE EXCEPTION 'Email audit record not found'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_supplier_po_email(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_supplier_po_email(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fail_supplier_po_email(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_supplier_po_email(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_supplier_po_email(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fail_supplier_po_email(UUID, TEXT) TO authenticated;

COMMIT;
