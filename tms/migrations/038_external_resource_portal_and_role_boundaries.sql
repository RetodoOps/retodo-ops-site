-- RetodoOps TMS — Update 039 / P1.2 External Resource portal and role boundaries
-- Run once after 037_p1_trusted_audit_and_snapshot_writes.sql.
--
-- This migration deliberately keeps all company tables company-only. External
-- Resources receive read-only, least-privilege projections through dedicated
-- SECURITY DEFINER RPCs; no direct Project, Scoop, Job, Client, Account,
-- financial or Settings table policy is opened to the resource role.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.project_jobs') IS NULL
       OR to_regclass('public.project_scoops') IS NULL
       OR to_regclass('public.supplier_purchase_orders') IS NULL
       OR to_regclass('public.supplier_po_versions') IS NULL
       OR to_regclass('public.file_records') IS NULL
       OR to_regprocedure('public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text)') IS NULL THEN
        RAISE EXCEPTION
            'Migration 038 requires the operational core and migrations 027, 036 and 037';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Authenticated External Resource identity and access state
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.current_external_resource_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT resource.id
    FROM public.profiles profile
    JOIN public.resources resource ON resource.profile_id = profile.id
    JOIN auth.users app_user ON app_user.id = profile.id
    WHERE profile.id = auth.uid()
      AND profile.role = 'resource'
      AND lower(app_user.email) = lower(NULLIF(btrim(resource.email), ''))
      AND resource.resource_type IN ('Freelancer', 'Company')
      AND resource.portal_status IN ('Active', 'Read-only')
      AND resource.lifecycle_status IN ('Active', 'On leave')
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_external_financial_resource_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT resource.id
    FROM public.profiles profile
    JOIN public.resources resource ON resource.profile_id = profile.id
    JOIN auth.users app_user ON app_user.id = profile.id
    WHERE profile.id = auth.uid()
      AND profile.role = 'resource'
      AND lower(app_user.email) = lower(NULLIF(btrim(resource.email), ''))
      AND resource.resource_type IN ('Freelancer', 'Company')
      AND (
          (
              resource.portal_status IN ('Active', 'Read-only')
              AND resource.lifecycle_status IN ('Active', 'On leave')
          )
          OR (
              resource.portal_status = 'Financial only'
              AND (
                  resource.financial_access_until IS NULL
                  OR resource.financial_access_until >= CURRENT_DATE
              )
          )
      )
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.current_external_resource_id()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_external_financial_resource_id()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_external_resource_id()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_external_financial_resource_id()
    TO authenticated;

-- Resource users must be linked to exactly one External Resource with a live
-- portal state. Generic users receive no TMS workspace. Existing company-role
-- behavior, including Internal Resource deactivation, remains intact.
CREATE OR REPLACE FUNCTION public.current_user_access_enabled()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((
        SELECT CASE
            WHEN profile.role = 'resource' THEN
                public.current_external_financial_resource_id() IS NOT NULL
            WHEN profile.role IN ('admin', 'pm', 'qa', 'client_relations') THEN
                NOT EXISTS (
                    SELECT 1
                    FROM public.resources resource
                    WHERE resource.profile_id = profile.id
                      AND resource.resource_type = 'Internal'
                      AND resource.lifecycle_status = 'Inactive'
                )
            ELSE FALSE
        END
        FROM public.profiles profile
        WHERE profile.id = auth.uid()
    ), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN profile.role = 'resource'
             AND public.current_external_financial_resource_id() IS NULL
            THEN NULL
        WHEN profile.role IN ('admin', 'pm', 'qa', 'client_relations')
             AND EXISTS (
                 SELECT 1
                 FROM public.resources resource
                 WHERE resource.profile_id = profile.id
                   AND resource.resource_type = 'Internal'
                   AND resource.lifecycle_status = 'Inactive'
             )
            THEN NULL
        WHEN profile.role IN ('admin', 'pm', 'qa', 'client_relations', 'resource')
            THEN profile.role
        ELSE NULL
    END
    FROM public.profiles profile
    WHERE profile.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_user_access_enabled()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_app_role()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_access_enabled()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_app_role()
    TO authenticated;

-- The standard operations policy permits Resource profile maintenance, but an
-- Auth identity link is a security action. Every External Resource link is
-- Administrator-only and must match an Auth user with the exact Resource email
-- and the dedicated resource role. Portal state and financial access dates are
-- also Administrator-controlled.
CREATE OR REPLACE FUNCTION public.protect_external_resource_portal_security()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_link_changed BOOLEAN;
    v_access_state_changed BOOLEAN;
    v_auth_email TEXT;
    v_profile_role TEXT;
BEGIN
    IF NEW.resource_type = 'Internal' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_profile_link_changed := NEW.profile_id IS NOT NULL;
        v_access_state_changed :=
            NEW.portal_status IS DISTINCT FROM 'Not invited'
            OR NEW.financial_access_until IS NOT NULL;
    ELSE
        v_profile_link_changed :=
            NEW.profile_id IS DISTINCT FROM OLD.profile_id
            OR (
                OLD.resource_type = 'Internal'
                AND NEW.resource_type <> 'Internal'
                AND NEW.profile_id IS NOT NULL
            )
            OR (
                NEW.profile_id IS NOT NULL
                AND NEW.email IS DISTINCT FROM OLD.email
            );
        v_access_state_changed :=
            NEW.portal_status IS DISTINCT FROM OLD.portal_status
            OR NEW.financial_access_until IS DISTINCT FROM OLD.financial_access_until;
    END IF;

    IF v_profile_link_changed AND NOT public.is_admin() THEN
        RAISE EXCEPTION
            'Only the Administrator can change an External Resource Authentication account link';
    END IF;
    IF v_access_state_changed
       AND NOT public.is_admin() THEN
        RAISE EXCEPTION
            'Only the Administrator can change External Resource portal or financial access';
    END IF;

    IF NEW.profile_id IS NOT NULL THEN
        SELECT profile.role, app_user.email
        INTO v_profile_role, v_auth_email
        FROM public.profiles profile
        JOIN auth.users app_user ON app_user.id = profile.id
        WHERE profile.id = NEW.profile_id;

        IF v_profile_role IS DISTINCT FROM 'resource' THEN
            RAISE EXCEPTION
                'An External Resource must link to an Authentication profile with role resource';
        END IF;
        IF lower(COALESCE(v_auth_email, ''))
               IS DISTINCT FROM lower(COALESCE(NULLIF(btrim(NEW.email), ''), '')) THEN
            RAISE EXCEPTION
                'The External Resource email must exactly match the linked Authentication user email';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.protect_external_resource_portal_security()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS resources_protect_external_portal_security
    ON public.resources;
CREATE TRIGGER resources_protect_external_portal_security
BEFORE INSERT OR UPDATE OF profile_id, resource_type, portal_status,
    financial_access_until, email
ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.protect_external_resource_portal_security();

-- ---------------------------------------------------------------------------
-- Existing company RPCs and internal helpers
-- ---------------------------------------------------------------------------

-- These three browser-facing wrappers previously reached company data before
-- their guarded inner operation ran. Keep their signatures and workflows, but
-- reject a Resource/generic account before any lookup or write is attempted.
CREATE OR REPLACE FUNCTION public.save_job_overview_inherit_rate_unit(
    p_job_id UUID,
    p_payload JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payload JSONB := COALESCE(p_payload, '{}'::JSONB);
    v_rate_id UUID := NULLIF(p_payload->>'resource_rate_id', '')::UUID;
    v_rate public.resource_rates%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_rate_id IS NOT NULL THEN
        SELECT * INTO v_rate
        FROM public.resource_rates
        WHERE id = v_rate_id
          AND base_rate_id IS NULL
          AND active
          AND status = 'Approved';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Select an active Approved base Supplier rate card';
        END IF;
        v_payload := jsonb_set(v_payload, '{unit}', to_jsonb(v_rate.unit), TRUE);
    END IF;
    RETURN public.save_job_overview(p_job_id, v_payload);
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_job_and_issue_po_inherit_rate_unit(
    p_job_id UUID,
    p_resource_id UUID,
    p_resource_rate_id UUID,
    p_cat_rows JSONB,
    p_reassignment_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rate public.resource_rates%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_rate
    FROM public.resource_rates
    WHERE id = p_resource_rate_id
      AND resource_id = p_resource_id
      AND base_rate_id IS NULL
      AND active
      AND status = 'Approved';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Select an active Approved base Supplier rate card';
    END IF;

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs
    SET unit = v_rate.unit, updated_at = NOW()
    WHERE id = p_job_id;

    RETURN public.assign_job_and_issue_po(
        p_job_id, p_resource_id, p_resource_rate_id,
        p_cat_rows, p_reassignment_reason
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_project_with_specializations(
    p_payload JSONB
)
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
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
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

REVOKE ALL ON FUNCTION public.save_job_overview_inherit_rate_unit(UUID, JSONB)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_job_and_issue_po_inherit_rate_unit(
    UUID, UUID, UUID, JSONB, TEXT
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_project_with_specializations(JSONB)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_job_overview_inherit_rate_unit(UUID, JSONB)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_job_and_issue_po_inherit_rate_unit(
    UUID, UUID, UUID, JSONB, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_project_with_specializations(JSONB)
    TO authenticated;

-- The following SECURITY DEFINER helpers are implementation details used by
-- guarded company workflows and triggers. They are not browser RPCs. Explicit
-- revocation prevents a Resource from using them as data or mutation oracles.
-- Service validation is also used by an invoker trigger, so it remains
-- executable but reveals catalogue membership only to company/service roles.
CREATE OR REPLACE FUNCTION public.is_supported_tms_service(p_service_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (
        public.is_company_user()
        OR public.is_admin()
    ) AND EXISTS (
        SELECT 1
        FROM public.service_catalog catalog
        WHERE catalog.active
          AND lower(btrim(catalog.name)) =
              lower(btrim(COALESCE(p_service_type, '')))
    );
$$;

REVOKE ALL ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT, JSONB
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_supplier_cat_analysis(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.contextual_supplier_po_number(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.profile_id_for_internal_email(TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_job_specialization(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_supported_tms_service(TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_supported_tms_service(TEXT)
    TO authenticated;
REVOKE ALL ON FUNCTION public.job_service_code(TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tms_compact_language_code(TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tms_compact_rate_line_label(
    TEXT[], TEXT, TEXT[], TEXT, TEXT, UUID, TEXT, NUMERIC, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_client_rate_card_name(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_project_financials(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_project_price_from_scoops(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_project_scoop_status(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_supplier_po_display_name(UUID)
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Administrator-controlled Auth account link
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.external_resource_portal_link_status(
    p_resource_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_auth_user_id UUID;
    v_profile_role TEXT;
    v_other_resource_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Administrator access required';
    END IF;

    SELECT * INTO v_resource
    FROM public.resources
    WHERE id = p_resource_id;
    IF NOT FOUND OR v_resource.resource_type = 'Internal' THEN
        RAISE EXCEPTION 'External Resource not found';
    END IF;

    SELECT app_user.id INTO v_auth_user_id
    FROM auth.users app_user
    WHERE lower(app_user.email) = lower(NULLIF(btrim(v_resource.email), ''))
    LIMIT 1;

    IF v_auth_user_id IS NOT NULL THEN
        SELECT role INTO v_profile_role
        FROM public.profiles
        WHERE id = v_auth_user_id;

        SELECT resource.id INTO v_other_resource_id
        FROM public.resources resource
        WHERE resource.profile_id = v_auth_user_id
          AND resource.id <> p_resource_id
        LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'resource_id', v_resource.id,
        'resource_email_present', NULLIF(btrim(v_resource.email), '') IS NOT NULL,
        'auth_user_exists', v_auth_user_id IS NOT NULL,
        'linked_to_this_resource',
            v_auth_user_id IS NOT NULL
            AND v_resource.profile_id = v_auth_user_id,
        'resource_has_other_profile_link',
            v_resource.profile_id IS NOT NULL
            AND (
                v_auth_user_id IS NULL
                OR v_resource.profile_id <> v_auth_user_id
            ),
        'profile_role', v_profile_role,
        'linked_to_another_resource', v_other_resource_id IS NOT NULL,
        'portal_status', v_resource.portal_status
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_external_resource_portal(
    p_resource_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_auth_user_id UUID;
    v_auth_email TEXT;
    v_existing_role TEXT;
    v_other_resource_id UUID;
    v_display_name TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only the Administrator can activate an External Resource portal';
    END IF;

    SELECT * INTO v_resource
    FROM public.resources
    WHERE id = p_resource_id
    FOR UPDATE;
    IF NOT FOUND OR v_resource.resource_type = 'Internal' THEN
        RAISE EXCEPTION 'External Resource not found';
    END IF;
    IF v_resource.lifecycle_status = 'Inactive' THEN
        RAISE EXCEPTION 'Activate the Resource lifecycle before activating portal access';
    END IF;
    IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
        RAISE EXCEPTION 'Add the Resource email address before activating portal access';
    END IF;

    SELECT app_user.id, app_user.email
    INTO v_auth_user_id, v_auth_email
    FROM auth.users app_user
    WHERE lower(app_user.email) = lower(btrim(v_resource.email))
    LIMIT 1;
    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION
            'No Supabase Authentication user exists for %. Create that user first, then activate the portal',
            v_resource.email;
    END IF;

    SELECT role INTO v_existing_role
    FROM public.profiles
    WHERE id = v_auth_user_id;
    IF v_existing_role IS NOT NULL
       AND v_existing_role NOT IN ('user', 'resource') THEN
        RAISE EXCEPTION
            'This Authentication user already has company role % and cannot be converted to an External Resource',
            v_existing_role;
    END IF;

    SELECT resource.id INTO v_other_resource_id
    FROM public.resources resource
    WHERE resource.profile_id = v_auth_user_id
      AND resource.id <> p_resource_id
    LIMIT 1;
    IF v_other_resource_id IS NOT NULL THEN
        RAISE EXCEPTION 'This Authentication user is already linked to another Resource';
    END IF;
    IF v_resource.profile_id IS NOT NULL
       AND v_resource.profile_id <> v_auth_user_id THEN
        RAISE EXCEPTION 'This External Resource is already linked to another Authentication user';
    END IF;

    v_display_name := COALESCE(
        NULLIF(btrim(v_resource.legal_name), ''),
        NULLIF(btrim(v_resource.company_name), ''),
        split_part(v_auth_email, '@', 1)
    );

    INSERT INTO public.profiles (id, full_name, role)
    VALUES (v_auth_user_id, v_display_name, 'resource')
    ON CONFLICT (id) DO UPDATE
    SET role = 'resource',
        full_name = COALESCE(
            NULLIF(btrim(public.profiles.full_name), ''),
            EXCLUDED.full_name
        );

    UPDATE public.resources
    SET profile_id = v_auth_user_id,
        portal_status = 'Active',
        updated_at = NOW()
    WHERE id = p_resource_id;

    PERFORM public.append_trusted_tms_audit_event(
        'Resource',
        p_resource_id,
        'External portal activated',
        jsonb_build_object(
            'profile_linked', v_resource.profile_id IS NOT NULL,
            'portal_status', v_resource.portal_status
        ),
        jsonb_build_object(
            'profile_linked', TRUE,
            'portal_status', 'Active'
        ),
        'Administrator linked an existing Supabase Authentication user by exact Resource email'
    );

    RETURN jsonb_build_object(
        'resource_id', p_resource_id,
        'linked', TRUE,
        'portal_status', 'Active',
        'role', 'resource'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.external_resource_portal_link_status(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.activate_external_resource_portal(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.external_resource_portal_link_status(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_external_resource_portal(UUID)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- Read-only portal projections
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_portal_context()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_financial_resource_id();
    v_work_resource_id UUID := public.current_external_resource_id();
    v_result JSONB;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'External Resource portal access required';
    END IF;

    SELECT jsonb_build_object(
        'resource_number', resource.internal_number,
        'display_name', COALESCE(
            NULLIF(btrim(resource.legal_name), ''),
            NULLIF(btrim(resource.company_name), ''),
            resource.internal_number
        ),
        'portal_status', resource.portal_status,
        'can_view_jobs', v_work_resource_id IS NOT NULL,
        'can_view_financials', TRUE,
        'job_count', CASE WHEN v_work_resource_id IS NULL THEN 0 ELSE (
            SELECT count(*)
            FROM public.project_jobs job
            WHERE job.resource_id = v_work_resource_id
        ) END,
        'purchase_order_count', (
            SELECT count(*)
            FROM public.supplier_purchase_orders po
            WHERE po.resource_id = v_resource_id
              AND po.status <> 'Draft'
              AND EXISTS (
                  SELECT 1
                  FROM public.supplier_po_versions version
                  WHERE version.purchase_order_id = po.id
              )
        )
    ) INTO v_result
    FROM public.resources resource
    WHERE resource.id = v_resource_id;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_jobs()
RETURNS TABLE (
    job_id UUID,
    job_number TEXT,
    project_number TEXT,
    scoop_number TEXT,
    job_status TEXT,
    service_type TEXT,
    source_language TEXT,
    target_language TEXT,
    specialization_name TEXT,
    deadline TIMESTAMPTZ,
    quantity NUMERIC,
    unit TEXT,
    instructions TEXT,
    purchase_order_id UUID,
    purchase_order_number TEXT,
    purchase_order_status TEXT,
    purchase_order_version INTEGER,
    purchase_order_total NUMERIC,
    purchase_order_currency TEXT,
    issue_count BIGINT,
    file_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;

    RETURN QUERY
    SELECT
        job.id,
        job.job_number,
        project.project_number,
        scoop.scoop_number,
        job.status,
        job.service_type,
        job.source_language,
        job.target_language,
        specialization.name,
        job.deadline,
        job.quantity,
        job.unit,
        COALESCE(
            NULLIF(btrim(job.assignment_notes), ''),
            NULLIF(btrim(job.notes), '')
        ),
        po.id,
        po.po_number,
        po.status,
        po.current_version,
        po.total,
        po.currency,
        (
            SELECT count(*)
            FROM public.job_issues issue
            WHERE issue.job_id = job.id
        ),
        (
            SELECT count(*)
            FROM public.file_records file
            WHERE file.job_id = job.id
              AND file.archived_at IS NULL
              AND (file.resource_id IS NULL OR file.resource_id = v_resource_id)
        )
    FROM public.project_jobs job
    JOIN public.projects project ON project.id = job.project_id
    JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    LEFT JOIN public.specializations specialization
        ON specialization.id = job.specialization_id
    LEFT JOIN LATERAL (
        SELECT
            purchase_order.id,
            purchase_order.po_number,
            purchase_order.status,
            immutable.version_number AS current_version,
            COALESCE(
                NULLIF(immutable.snapshot->>'total', '')::NUMERIC,
                purchase_order.total
            ) AS total,
            COALESCE(
                NULLIF(immutable.snapshot->>'currency', ''),
                purchase_order.currency
            ) AS currency
        FROM public.supplier_purchase_orders purchase_order
        JOIN LATERAL (
            SELECT version.version_number, version.snapshot
            FROM public.supplier_po_versions version
            WHERE version.purchase_order_id = purchase_order.id
            ORDER BY version.version_number DESC
            LIMIT 1
        ) immutable ON TRUE
        WHERE purchase_order.job_id = job.id
          AND purchase_order.resource_id = v_resource_id
          AND purchase_order.status <> 'Draft'
        ORDER BY COALESCE(purchase_order.issued_at, purchase_order.created_at) DESC
        LIMIT 1
    ) po ON TRUE
    WHERE job.resource_id = v_resource_id
    ORDER BY job.deadline NULLS LAST, job.job_number;
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_job(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_job public.project_jobs%ROWTYPE;
    v_project_number TEXT;
    v_scoop_number TEXT;
    v_specialization_name TEXT;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;

    SELECT job.*
    INTO v_job
    FROM public.project_jobs job
    WHERE job.id = p_job_id
      AND job.resource_id = v_resource_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assigned Job not found';
    END IF;

    SELECT project.project_number, scoop.scoop_number, specialization.name
    INTO v_project_number, v_scoop_number, v_specialization_name
    FROM public.projects project
    JOIN public.project_scoops scoop ON scoop.id = v_job.project_scoop_id
    LEFT JOIN public.specializations specialization
        ON specialization.id = v_job.specialization_id
    WHERE project.id = v_job.project_id;

    RETURN jsonb_build_object(
        'job', jsonb_build_object(
            'id', v_job.id,
            'job_number', v_job.job_number,
            'project_number', v_project_number,
            'scoop_number', v_scoop_number,
            'status', v_job.status,
            'service_type', v_job.service_type,
            'source_language', v_job.source_language,
            'target_language', v_job.target_language,
            'specialization', v_specialization_name,
            'deadline', v_job.deadline,
            'quantity', v_job.quantity,
            'unit', v_job.unit,
            'instructions', COALESCE(
                NULLIF(btrim(v_job.assignment_notes), ''),
                NULLIF(btrim(v_job.notes), '')
            )
        ),
        'purchase_orders', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', po.id,
                'po_number', po.po_number,
                'status', po.status,
                'current_version', immutable.version_number,
                'currency', COALESCE(
                    NULLIF(immutable.snapshot->>'currency', ''),
                    po.currency
                ),
                'total', COALESCE(
                    NULLIF(immutable.snapshot->>'total', '')::NUMERIC,
                    po.total
                ),
                'issued_at', po.issued_at,
                'acknowledged_at', po.acknowledged_at
            ) ORDER BY COALESCE(po.issued_at, po.created_at) DESC)
            FROM public.supplier_purchase_orders po
            JOIN LATERAL (
                SELECT version.version_number, version.snapshot
                FROM public.supplier_po_versions version
                WHERE version.purchase_order_id = po.id
                ORDER BY version.version_number DESC
                LIMIT 1
            ) immutable ON TRUE
            WHERE po.job_id = v_job.id
              AND po.resource_id = v_resource_id
              AND po.status <> 'Draft'
        ), '[]'::JSONB),
        'files', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', file.id,
                'filename', file.original_filename,
                'file_role', file.file_role,
                'mime_type', file.mime_type,
                'size_bytes', file.size_bytes,
                'storage_provider', file.storage_provider,
                'bucket_name', file.bucket_name,
                'object_key', file.object_key,
                'external_url', file.external_url,
                'created_at', file.created_at
            ) ORDER BY file.created_at DESC)
            FROM public.file_records file
            WHERE file.job_id = v_job.id
              AND file.archived_at IS NULL
              AND (file.resource_id IS NULL OR file.resource_id = v_resource_id)
        ), '[]'::JSONB),
        'issues', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', issue.id,
                'status', issue.status,
                'severity', issue.severity,
                'description', issue.description,
                'resolution', issue.resolution,
                'reported_at', issue.reported_at,
                'resolved_at', issue.resolved_at
            ) ORDER BY issue.reported_at DESC)
            FROM public.job_issues issue
            WHERE issue.job_id = v_job.id
        ), '[]'::JSONB)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_purchase_orders()
RETURNS TABLE (
    purchase_order_id UUID,
    purchase_order_number TEXT,
    purchase_order_status TEXT,
    current_version INTEGER,
    currency TEXT,
    total NUMERIC,
    issued_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    job_number TEXT,
    project_number TEXT,
    scoop_number TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_financial_resource_id();
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'External Resource financial access required';
    END IF;

    RETURN QUERY
    SELECT
        po.id,
        po.po_number,
        po.status,
        version.version_number,
        COALESCE(NULLIF(version.snapshot->>'currency', ''), po.currency),
        COALESCE(NULLIF(version.snapshot->>'total', '')::NUMERIC, po.total),
        po.issued_at,
        po.acknowledged_at,
        COALESCE(version.snapshot->'job'->>'job_number', job.job_number),
        project.project_number,
        scoop.scoop_number
    FROM public.supplier_purchase_orders po
    JOIN LATERAL (
        SELECT immutable.version_number, immutable.snapshot
        FROM public.supplier_po_versions immutable
        WHERE immutable.purchase_order_id = po.id
        ORDER BY immutable.version_number DESC
        LIMIT 1
    ) version ON TRUE
    LEFT JOIN public.project_jobs job ON job.id = po.job_id
    LEFT JOIN public.projects project ON project.id = po.project_id
    LEFT JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    WHERE po.resource_id = v_resource_id
      AND po.status <> 'Draft'
    ORDER BY COALESCE(po.issued_at, po.created_at) DESC, po.po_number DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_purchase_order(
    p_purchase_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_financial_resource_id();
    v_po public.supplier_purchase_orders%ROWTYPE;
    v_project_number TEXT;
    v_scoop_number TEXT;
    v_version RECORD;
    v_snapshot JSONB;
    v_lines JSONB;
    v_versions JSONB := '[]'::JSONB;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'External Resource financial access required';
    END IF;

    SELECT * INTO v_po
    FROM public.supplier_purchase_orders po
    WHERE po.id = p_purchase_order_id
      AND po.resource_id = v_resource_id
      AND po.status <> 'Draft';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier PO not found';
    END IF;

    SELECT project.project_number, scoop.scoop_number
    INTO v_project_number, v_scoop_number
    FROM public.projects project
    LEFT JOIN public.project_jobs job ON job.id = v_po.job_id
    LEFT JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    WHERE project.id = v_po.project_id;

    FOR v_version IN
        SELECT
            immutable.version_number,
            immutable.document_status,
            immutable.change_reason,
            immutable.created_at,
            immutable.snapshot
        FROM public.supplier_po_versions immutable
        WHERE immutable.purchase_order_id = v_po.id
        ORDER BY immutable.version_number DESC
    LOOP
        v_snapshot := COALESCE(v_version.snapshot, '{}'::JSONB);
        v_lines := '[]'::JSONB;
        IF jsonb_typeof(v_snapshot->'lines') = 'array' THEN
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'description', line.value->>'description',
                'quantity', line.value->'quantity',
                'unit', line.value->>'unit',
                'unit_price', line.value->'unit_price',
                'adjustment_type', line.value->>'adjustment_type',
                'amount', line.value->'amount'
            ) ORDER BY line.ordinality), '[]'::JSONB)
            INTO v_lines
            FROM jsonb_array_elements(v_snapshot->'lines')
                WITH ORDINALITY AS line(value, ordinality);
        END IF;

        v_versions := v_versions || jsonb_build_array(jsonb_build_object(
            'version_number', v_version.version_number,
            'document_status', v_version.document_status,
            'change_reason', v_version.change_reason,
            'created_at', v_version.created_at,
            'currency', COALESCE(NULLIF(v_snapshot->>'currency', ''), v_po.currency),
            'subtotal', COALESCE(NULLIF(v_snapshot->>'subtotal', '')::NUMERIC, 0),
            'adjustment_amount', COALESCE(
                NULLIF(v_snapshot->>'adjustment_amount', '')::NUMERIC,
                0
            ),
            'total', COALESCE(NULLIF(v_snapshot->>'total', '')::NUMERIC, 0),
            'work_may_begin_before_acknowledgement', COALESCE(
                (v_snapshot->>'work_may_begin_before_acknowledgement')::BOOLEAN,
                v_po.work_may_begin_before_acknowledgement
            ),
            'job', jsonb_build_object(
                'job_number', v_snapshot->'job'->>'job_number',
                'service_type', v_snapshot->'job'->>'service_type',
                'source_language', v_snapshot->'job'->>'source_language',
                'target_language', v_snapshot->'job'->>'target_language',
                'deadline', v_snapshot->'job'->>'deadline',
                'quantity', v_snapshot->'job'->'quantity',
                'unit', v_snapshot->'job'->>'unit'
            ),
            'lines', v_lines
        ));
    END LOOP;

    IF jsonb_array_length(v_versions) = 0 THEN
        RAISE EXCEPTION 'Supplier PO has no immutable issued version';
    END IF;

    RETURN jsonb_build_object(
        'purchase_order', jsonb_build_object(
            'id', v_po.id,
            'po_number', v_po.po_number,
            'status', v_po.status,
            'currency', v_po.currency,
            'subtotal', v_po.subtotal,
            'adjustment_amount', v_po.adjustment_amount,
            'total', v_po.total,
            'issued_at', v_po.issued_at,
            'acknowledged_at', v_po.acknowledged_at,
            'project_number', v_project_number,
            'scoop_number', v_scoop_number
        ),
        'versions', v_versions
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_context()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_jobs()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_job(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_purchase_orders()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_purchase_order(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_context()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_jobs()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_job(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_purchase_orders()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_purchase_order(UUID)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- Own-Job file access and trusted immutable access logging
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_can_access_file(p_file_record_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.file_records file
        JOIN public.project_jobs job ON job.id = file.job_id
        WHERE file.id = p_file_record_id
          AND file.archived_at IS NULL
          AND job.resource_id = public.current_external_resource_id()
          AND (
              file.resource_id IS NULL
              OR file.resource_id = public.current_external_resource_id()
          )
    ), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.resource_can_access_storage_object(
    p_bucket_name TEXT,
    p_object_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.file_records file
        JOIN public.project_jobs job ON job.id = file.job_id
        WHERE file.storage_provider = 'Supabase'
          AND file.bucket_name = p_bucket_name
          AND file.object_key = p_object_key
          AND file.archived_at IS NULL
          AND job.resource_id = public.current_external_resource_id()
          AND (
              file.resource_id IS NULL
              OR file.resource_id = public.current_external_resource_id()
          )
    ), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.record_resource_file_access(
    p_file_record_id UUID,
    p_action TEXT DEFAULT 'View'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_log_id UUID;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    IF p_action NOT IN ('View', 'Download') THEN
        RAISE EXCEPTION 'External Resource file action must be View or Download';
    END IF;
    IF NOT public.resource_can_access_file(p_file_record_id) THEN
        RAISE EXCEPTION 'Job file not found';
    END IF;

    INSERT INTO public.file_access_logs (
        file_record_id,
        profile_id,
        resource_id,
        action
    ) VALUES (
        p_file_record_id,
        auth.uid(),
        v_resource_id,
        p_action
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resource_can_access_file(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_can_access_storage_object(TEXT, TEXT)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_resource_file_access(UUID, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_can_access_file(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_can_access_storage_object(TEXT, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_resource_file_access(UUID, TEXT)
    TO authenticated;

-- Supabase Storage remains private. The policy permits SELECT only when a
-- file_record maps the exact bucket/object to the caller's currently assigned
-- Job. Upload, update and delete policies are intentionally not added.
DO $$
BEGIN
    IF to_regclass('storage.objects') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS resource_portal_own_job_file_select ON storage.objects';
        EXECUTE $policy$
            CREATE POLICY resource_portal_own_job_file_select
            ON storage.objects
            FOR SELECT TO authenticated
            USING (
                public.resource_can_access_storage_object(bucket_id, name)
            )
        $policy$;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Settings catalogue: company read; PM may add; only Admin may alter/remove
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS service_catalog_read ON public.service_catalog;
DROP POLICY IF EXISTS service_catalog_admin_manage ON public.service_catalog;
DROP POLICY IF EXISTS service_catalog_company_select ON public.service_catalog;
DROP POLICY IF EXISTS service_catalog_admin_pm_insert ON public.service_catalog;
DROP POLICY IF EXISTS service_catalog_admin_update ON public.service_catalog;
DROP POLICY IF EXISTS service_catalog_admin_delete ON public.service_catalog;

CREATE POLICY service_catalog_company_select
ON public.service_catalog FOR SELECT TO authenticated
USING (public.is_company_user());
CREATE POLICY service_catalog_admin_pm_insert
ON public.service_catalog FOR INSERT TO authenticated
WITH CHECK (
    public.current_app_role() = 'admin'
    OR (public.current_app_role() = 'pm' AND active)
);
CREATE POLICY service_catalog_admin_update
ON public.service_catalog FOR UPDATE TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY service_catalog_admin_delete
ON public.service_catalog FOR DELETE TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS language_catalog_read ON public.language_catalog;
DROP POLICY IF EXISTS language_catalog_admin_manage ON public.language_catalog;
DROP POLICY IF EXISTS language_catalog_company_select ON public.language_catalog;
DROP POLICY IF EXISTS language_catalog_admin_pm_insert ON public.language_catalog;
DROP POLICY IF EXISTS language_catalog_admin_update ON public.language_catalog;
DROP POLICY IF EXISTS language_catalog_admin_delete ON public.language_catalog;

CREATE POLICY language_catalog_company_select
ON public.language_catalog FOR SELECT TO authenticated
USING (public.is_company_user());
CREATE POLICY language_catalog_admin_pm_insert
ON public.language_catalog FOR INSERT TO authenticated
WITH CHECK (
    public.current_app_role() = 'admin'
    OR (public.current_app_role() = 'pm' AND active)
);
CREATE POLICY language_catalog_admin_update
ON public.language_catalog FOR UPDATE TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY language_catalog_admin_delete
ON public.language_catalog FOR DELETE TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS specializations_company_select ON public.specializations;
DROP POLICY IF EXISTS specializations_operations_write ON public.specializations;
DROP POLICY IF EXISTS specializations_admin_manage ON public.specializations;
DROP POLICY IF EXISTS specializations_admin_pm_insert ON public.specializations;
DROP POLICY IF EXISTS specializations_admin_update ON public.specializations;
DROP POLICY IF EXISTS specializations_admin_delete ON public.specializations;

CREATE POLICY specializations_company_select
ON public.specializations FOR SELECT TO authenticated
USING (public.is_company_user());
CREATE POLICY specializations_admin_pm_insert
ON public.specializations FOR INSERT TO authenticated
WITH CHECK (
    public.current_app_role() = 'admin'
    OR (public.current_app_role() = 'pm' AND active)
);
CREATE POLICY specializations_admin_update
ON public.specializations FOR UPDATE TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY specializations_admin_delete
ON public.specializations FOR DELETE TO authenticated
USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- PM Supplier PO revisions (issue remains Administrator-only)
-- ---------------------------------------------------------------------------

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
    IF public.current_app_role() NOT IN ('admin', 'pm') THEN
        RAISE EXCEPTION 'Administrator or Project Manager role required to revise a Supplier PO';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'A revision reason is required';
    END IF;
    IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'At least one PO line is required';
    END IF;

    SELECT * INTO v_po
    FROM public.supplier_purchase_orders
    WHERE id = p_po_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier PO not found'; END IF;
    IF v_po.status NOT IN ('Issued', 'Acknowledged') THEN
        RAISE EXCEPTION 'Only an Issued or Acknowledged PO can be revised';
    END IF;

    PERFORM set_config('retodo.po_revision', 'on', TRUE);
    DELETE FROM public.supplier_po_lines
    WHERE purchase_order_id = p_po_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        INSERT INTO public.supplier_po_lines (
            purchase_order_id,
            description,
            quantity,
            unit,
            unit_price,
            adjustment_type,
            amount,
            sort_order
        ) VALUES (
            p_po_id,
            NULLIF(btrim(v_line->>'description'), ''),
            NULLIF(v_line->>'quantity', '')::NUMERIC,
            NULLIF(v_line->>'unit', ''),
            NULLIF(v_line->>'unit_price', '')::NUMERIC,
            NULLIF(v_line->>'adjustment_type', ''),
            COALESCE(NULLIF(v_line->>'amount', '')::NUMERIC, 0),
            COALESCE(NULLIF(v_line->>'sort_order', '')::INTEGER, 0)
        );
    END LOOP;

    SELECT GREATEST(
        COALESCE(v_po.current_version, 0),
        COALESCE(max(version.version_number), 0)
    ) + 1
    INTO v_new_version
    FROM public.supplier_po_versions version
    WHERE version.purchase_order_id = p_po_id;
    UPDATE public.supplier_purchase_orders
    SET current_version = v_new_version,
        status = 'Issued',
        last_change_reason = btrim(p_reason),
        acknowledgement_requested_at = NOW()
    WHERE id = p_po_id;

    v_snapshot := public.supplier_po_snapshot(p_po_id);
    INSERT INTO public.supplier_po_versions (
        purchase_order_id,
        version_number,
        snapshot,
        document_status,
        change_reason,
        created_by
    ) VALUES (
        p_po_id,
        v_new_version,
        v_snapshot,
        'Revised',
        btrim(p_reason),
        auth.uid()
    );

    INSERT INTO public.email_records (
        purchase_order_id,
        po_version,
        project_id,
        job_id,
        resource_id,
        direction,
        status,
        from_address,
        to_addresses,
        subject,
        created_by
    )
    SELECT
        po.id,
        v_new_version,
        po.project_id,
        po.job_id,
        po.resource_id,
        'Outgoing',
        'Draft requested',
        'ops@retodo-ops.com',
        ARRAY[resource.email],
        po.po_number || ' · Revised Supplier purchase order v' || v_new_version,
        auth.uid()
    FROM public.supplier_purchase_orders po
    JOIN public.resources resource ON resource.id = po.resource_id
    WHERE po.id = p_po_id
      AND NULLIF(btrim(resource.email), '') IS NOT NULL;

    RETURN v_new_version;
END;
$$;

REVOKE ALL ON FUNCTION public.revise_supplier_po(UUID, JSONB, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revise_supplier_po(UUID, JSONB, TEXT)
    TO authenticated;

COMMIT;
