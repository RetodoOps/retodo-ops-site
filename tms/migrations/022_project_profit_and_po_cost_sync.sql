-- RetodoOps TMS — keep Project expense/profit synchronized with the current
-- immutable Supplier PO version. Run after 021.

BEGIN;

-- One calculation path is shared by Job changes, PO revisions and the
-- migration backfill. A current non-cancelled PO is the authoritative supplier
-- cost; Jobs without a PO retain their saved supplier_amount fallback.
CREATE OR REPLACE FUNCTION public.refresh_project_financials(p_project_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.projects project
    SET expense = COALESCE((
        SELECT sum(COALESCE((
            SELECT po.total
            FROM public.supplier_purchase_orders po
            WHERE po.job_id = job.id
              AND po.status IN ('Issued', 'Acknowledged')
            ORDER BY po.created_at DESC, po.id DESC
            LIMIT 1
        ), job.supplier_amount, 0))
        FROM public.project_jobs job
        WHERE job.project_id = p_project_id
          AND job.status NOT IN ('Declined', 'Cancelled')
    ), 0),
    updated_at = NOW()
    WHERE project.id = p_project_id;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_project_financials(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refresh_project_financials(UUID) FROM authenticated;

-- Job assignment, amount and status changes continue to update the Project,
-- but now use the current PO total whenever one exists.
CREATE OR REPLACE FUNCTION public.recalculate_project_expense()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_id UUID;
BEGIN
    v_project_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.project_id ELSE NEW.project_id END;
    PERFORM public.refresh_project_financials(v_project_id);

    IF TG_OP = 'UPDATE' AND OLD.project_id IS DISTINCT FROM NEW.project_id THEN
        PERFORM public.refresh_project_financials(OLD.project_id);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

-- Every immutable PO version is a financial event. Recalculate after the
-- version row exists so the PO header/lines and the Project summary agree.
CREATE OR REPLACE FUNCTION public.sync_project_financials_from_po_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_id UUID;
BEGIN
    SELECT po.project_id INTO v_project_id
    FROM public.supplier_purchase_orders po
    WHERE po.id = NEW.purchase_order_id;

    IF v_project_id IS NOT NULL THEN
        PERFORM public.refresh_project_financials(v_project_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_po_versions_sync_project_financials
    ON public.supplier_po_versions;
CREATE TRIGGER supplier_po_versions_sync_project_financials
AFTER INSERT OR UPDATE OF snapshot, document_status
ON public.supplier_po_versions
FOR EACH ROW EXECUTE FUNCTION public.sync_project_financials_from_po_version();

-- Repair Projects whose PO was revised before this synchronization existed.
DO $$
DECLARE
    v_project_id UUID;
BEGIN
    FOR v_project_id IN SELECT id FROM public.projects LOOP
        PERFORM public.refresh_project_financials(v_project_id);
    END LOOP;
END;
$$;

COMMIT;
