-- RetodoOps TMS — P1.1 permission and snapshot hardening
-- Run after 035_job_language_flat_fee_po_label_and_deadline.sql.
--
-- This migration is intentionally narrow. It does not change the commercial
-- formulas or the Project/Scoop/Job UI. It closes the direct-write paths that
-- could mutate append-only audit, file-access or issued-PO-version records and
-- adds database audit events for the principal status transitions.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.supplier_po_versions') IS NULL
       OR to_regclass('public.audit_events') IS NULL
       OR to_regclass('public.file_access_logs') IS NULL THEN
        RAISE EXCEPTION
            'P1.1 requires supplier_po_versions, audit_events and file_access_logs from the operational core';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Append-only records
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_append_only_tms_record()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION
            '% is append-only; create a new record or revision instead',
            TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_po_versions_append_only
    ON public.supplier_po_versions;
CREATE TRIGGER supplier_po_versions_append_only
BEFORE UPDATE OR DELETE ON public.supplier_po_versions
FOR EACH ROW EXECUTE FUNCTION public.protect_append_only_tms_record();

DROP TRIGGER IF EXISTS audit_events_append_only
    ON public.audit_events;
CREATE TRIGGER audit_events_append_only
BEFORE UPDATE OR DELETE ON public.audit_events
FOR EACH ROW EXECUTE FUNCTION public.protect_append_only_tms_record();

DROP TRIGGER IF EXISTS file_access_logs_append_only
    ON public.file_access_logs;
CREATE TRIGGER file_access_logs_append_only
BEFORE UPDATE OR DELETE ON public.file_access_logs
FOR EACH ROW EXECUTE FUNCTION public.protect_append_only_tms_record();

-- RLS must express the same rule as the triggers. Existing migration 002
-- created generic company-read/operations-write policies for these tables;
-- replace those broad policies with SELECT + INSERT only.
DO $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'supplier_po_versions', 'audit_events', 'file_access_logs'
    ] LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON public.%I',
            table_name || '_company_select', table_name
        );
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON public.%I',
            table_name || '_operations_write', table_name
        );
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
            'USING (public.is_company_user())',
            table_name || '_company_select', table_name
        );
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR INSERT TO authenticated '
            'WITH CHECK (public.can_manage_operations())',
            table_name || '_operations_insert', table_name
        );
        EXECUTE format(
            'REVOKE UPDATE, DELETE ON public.%I FROM authenticated',
            table_name
        );
        EXECUTE format(
            'GRANT SELECT, INSERT ON public.%I TO authenticated',
            table_name
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Status-change audit events
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_tms_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_before JSONB;
    v_after JSONB;
    v_reason TEXT;
    v_action TEXT := 'Status changed';
BEGIN
    IF TG_TABLE_NAME = 'projects' THEN
        v_before := jsonb_build_object(
            'status', OLD.status,
            'financial_status', OLD.financial_status,
            'issue_status', OLD.issue_status
        );
        v_after := jsonb_build_object(
            'status', NEW.status,
            'financial_status', NEW.financial_status,
            'issue_status', NEW.issue_status
        );
        v_reason := NULLIF(btrim(NEW.waiting_reason), '');
    ELSIF TG_TABLE_NAME = 'project_scoops' THEN
        v_before := jsonb_build_object(
            'status', OLD.status,
            'status_manual', OLD.status_manual
        );
        v_after := jsonb_build_object(
            'status', NEW.status,
            'status_manual', NEW.status_manual
        );
        v_reason := NULL;
        IF NEW.status_manual IS TRUE AND OLD.status_manual IS DISTINCT FROM NEW.status_manual THEN
            v_action := 'Manual Scoop status override changed';
        END IF;
    ELSIF TG_TABLE_NAME = 'project_jobs' THEN
        v_before := jsonb_build_object('status', OLD.status);
        v_after := jsonb_build_object('status', NEW.status);
        v_reason := NULL;
    ELSIF TG_TABLE_NAME = 'resources' THEN
        v_before := jsonb_build_object(
            'lifecycle_status', OLD.lifecycle_status,
            'resource_status', OLD.resource_status,
            'compliance_status', OLD.compliance_status
        );
        v_after := jsonb_build_object(
            'lifecycle_status', NEW.lifecycle_status,
            'resource_status', NEW.resource_status,
            'compliance_status', NEW.compliance_status
        );
        v_reason := NULLIF(btrim(COALESCE(NEW.restriction_reason, NEW.notes)), '');
        IF OLD.lifecycle_status IS DISTINCT FROM NEW.lifecycle_status THEN
            v_action := 'Resource lifecycle changed';
        ELSIF OLD.resource_status IS DISTINCT FROM NEW.resource_status THEN
            v_action := 'Resource readiness changed';
        ELSE
            v_action := 'Resource compliance changed';
        END IF;
    ELSIF TG_TABLE_NAME = 'supplier_purchase_orders' THEN
        v_before := jsonb_build_object(
            'status', OLD.status,
            'current_version', OLD.current_version
        );
        v_after := jsonb_build_object(
            'status', NEW.status,
            'current_version', NEW.current_version
        );
        v_reason := NULLIF(btrim(NEW.last_change_reason), '');
        IF OLD.current_version IS DISTINCT FROM NEW.current_version THEN
            v_action := 'Supplier PO version changed';
        END IF;
    ELSIF TG_TABLE_NAME = 'client_invoices' THEN
        v_before := jsonb_build_object('status', OLD.status);
        v_after := jsonb_build_object('status', NEW.status);
        v_reason := NULL;
        v_action := 'Client invoice status changed';
    ELSIF TG_TABLE_NAME = 'supplier_invoices' THEN
        v_before := jsonb_build_object('status', OLD.status);
        v_after := jsonb_build_object('status', NEW.status);
        v_reason := NULL;
        v_action := 'Supplier invoice status changed';
    ELSE
        RETURN NEW;
    END IF;

    IF v_before IS NOT DISTINCT FROM v_after THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_events (
        actor_id, entity_type, entity_id, action,
        before_values, after_values, reason
    ) VALUES (
        auth.uid(),
        COALESCE(NULLIF(TG_ARGV[0], ''), initcap(replace(TG_TABLE_NAME, '_', ' '))),
        NEW.id,
        v_action,
        v_before,
        v_after,
        v_reason
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_audit_status_change ON public.projects;
CREATE TRIGGER projects_audit_status_change
AFTER UPDATE OF status, financial_status, issue_status ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Project');

DROP TRIGGER IF EXISTS project_scoops_audit_status_change ON public.project_scoops;
CREATE TRIGGER project_scoops_audit_status_change
AFTER UPDATE OF status, status_manual ON public.project_scoops
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Scoop');

DROP TRIGGER IF EXISTS project_jobs_audit_status_change ON public.project_jobs;
CREATE TRIGGER project_jobs_audit_status_change
AFTER UPDATE OF status ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Job');

DROP TRIGGER IF EXISTS resources_audit_status_change ON public.resources;
CREATE TRIGGER resources_audit_status_change
AFTER UPDATE OF lifecycle_status, resource_status, compliance_status ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Resource');

DROP TRIGGER IF EXISTS supplier_purchase_orders_audit_status_change
    ON public.supplier_purchase_orders;
CREATE TRIGGER supplier_purchase_orders_audit_status_change
AFTER UPDATE OF status, current_version ON public.supplier_purchase_orders
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Supplier PO');

DROP TRIGGER IF EXISTS client_invoices_audit_status_change ON public.client_invoices;
CREATE TRIGGER client_invoices_audit_status_change
AFTER UPDATE OF status ON public.client_invoices
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Client Invoice');

DROP TRIGGER IF EXISTS supplier_invoices_audit_status_change ON public.supplier_invoices;
CREATE TRIGGER supplier_invoices_audit_status_change
AFTER UPDATE OF status ON public.supplier_invoices
FOR EACH ROW EXECUTE FUNCTION public.audit_tms_status_change('Supplier Invoice');

COMMIT;
