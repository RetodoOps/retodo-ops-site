-- RetodoOps TMS — unified Resource status, testing and qualification workflow
-- Run after 009_project_financials_and_cat_grid.sql.

BEGIN;

-- ---------------------------------------------------------------------------
-- One operational status replaces Relationship, Classification, Eligibility,
-- Assignment approval and Priority as user-editable controls. The old columns
-- remain as synchronized compatibility fields for earlier migrations/views.
-- ---------------------------------------------------------------------------

ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS resource_status TEXT;

ALTER TABLE public.resources
    DROP CONSTRAINT IF EXISTS resources_resource_status_check;

UPDATE public.resources
SET resource_status = CASE
    WHEN resource_type = 'Internal' THEN 'Preferred'
    WHEN classification = 'Do not use' OR eligibility_status = 'Do not use'
        THEN 'Do not use'
    WHEN classification = 'A — Preferred' OR priority_resource
        THEN 'Preferred'
    WHEN classification = 'B — Proven / previously used'
        THEN 'Proven'
    WHEN classification = 'C — Approved / no recorded work'
         OR assignment_approved OR eligibility_status = 'Eligible'
        THEN 'Assignable'
    WHEN eligibility_status IN ('Restricted', 'Hold')
         OR classification LIKE 'Hold —%'
        THEN 'Restricted'
    WHEN lower(COALESCE(relationship_status, '')) LIKE '%test%'
        THEN 'Test assigned'
    WHEN lower(COALESCE(relationship_status, '')) LIKE '%onboard%'
         OR lower(COALESCE(relationship_status, '')) LIKE '%discussion%'
        THEN 'Onboarding'
    ELSE 'New contact'
END
WHERE resource_status IS NULL
   OR resource_status NOT IN (
       'New contact', 'Onboarding', 'Test assigned', 'Assignable',
       'Proven', 'Preferred', 'Restricted', 'Do not use'
   );

ALTER TABLE public.resources
    ALTER COLUMN resource_status SET DEFAULT 'New contact',
    ALTER COLUMN resource_status SET NOT NULL,
    ADD CONSTRAINT resources_resource_status_check CHECK (resource_status IN (
        'New contact', 'Onboarding', 'Test assigned', 'Assignable',
        'Proven', 'Preferred', 'Restricted', 'Do not use'
    ));

CREATE INDEX IF NOT EXISTS resources_resource_status_idx
    ON public.resources(resource_status, lifecycle_status);

CREATE OR REPLACE FUNCTION public.sync_resource_status_legacy_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.relationship_status := NEW.resource_status;
    NEW.priority_resource := NEW.resource_status = 'Preferred';

    NEW.classification := CASE NEW.resource_status
        WHEN 'Preferred' THEN 'A — Preferred'
        WHEN 'Proven' THEN 'B — Proven / previously used'
        WHEN 'Assignable' THEN 'C — Approved / no recorded work'
        WHEN 'Do not use' THEN 'Do not use'
        ELSE 'D — Not assessed'
    END;

    NEW.eligibility_status := CASE NEW.resource_status
        WHEN 'Preferred' THEN 'Eligible'
        WHEN 'Proven' THEN 'Eligible'
        WHEN 'Assignable' THEN 'Eligible'
        WHEN 'Restricted' THEN 'Restricted'
        WHEN 'Do not use' THEN 'Do not use'
        ELSE 'Review'
    END;

    NEW.assignment_approved := NEW.lifecycle_status = 'Active'
        AND NEW.resource_status IN ('Assignable', 'Proven', 'Preferred');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resources_apply_lifecycle ON public.resources;
DROP TRIGGER IF EXISTS resources_sync_unified_status ON public.resources;
CREATE TRIGGER resources_sync_unified_status
BEFORE INSERT OR UPDATE OF resource_status, lifecycle_status
ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.sync_resource_status_legacy_fields();

-- Bring all existing compatibility fields into line immediately.
UPDATE public.resources SET resource_status = resource_status;

-- Administrator protection now follows the unified status rather than the
-- legacy Assignment approved / Classification controls.
CREATE OR REPLACE FUNCTION public.protect_admin_only_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_billing_entity_id UUID;
    v_billing_snapshot JSONB;
BEGIN
    IF TG_TABLE_NAME = 'resources' THEN
        IF NEW.resource_status = 'Do not use'
           AND (TG_OP = 'INSERT' OR NEW.resource_status IS DISTINCT FROM OLD.resource_status)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can mark a Resource Do not use';
        END IF;
        IF NEW.resource_status = 'Preferred'
           AND (TG_OP = 'INSERT' OR NEW.resource_status IS DISTINCT FROM OLD.resource_status)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can mark a Resource Preferred';
        END IF;
    ELSIF TG_TABLE_NAME = 'resource_rates' THEN
        IF (NEW.status IN ('Approved', 'Rejected') OR NEW.approved_by IS NOT NULL)
           AND (TG_OP = 'INSERT'
                OR NEW.status IS DISTINCT FROM OLD.status
                OR NEW.approved_by IS DISTINCT FROM OLD.approved_by)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can approve or reject supplier rates';
        END IF;
    ELSIF TG_TABLE_NAME = 'supplier_invoices' THEN
        IF NEW.status IN ('Approved', 'Partially Paid', 'Paid')
           AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can approve supplier invoices or payments';
        END IF;
    ELSIF TG_TABLE_NAME = 'client_invoices' THEN
        IF NEW.status IN ('Issued', 'Annulled', 'Credited')
           AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can issue, annul or credit official invoices';
        END IF;
        IF NEW.status = 'Issued'
           AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
            v_billing_entity_id := NEW.billing_entity_id;
            IF v_billing_entity_id IS NULL THEN
                SELECT entity.id INTO v_billing_entity_id
                FROM public.client_billing_entities entity
                WHERE entity.client_id = NEW.client_id
                  AND entity.is_default AND entity.active
                LIMIT 1;
            END IF;
            IF v_billing_entity_id IS NULL THEN
                RAISE EXCEPTION 'A Billing Entity is required before an invoice can be issued';
            END IF;

            SELECT jsonb_build_object(
                'billing_entity_id', entity.id,
                'name', entity.name,
                'legal_name', entity.legal_name,
                'address_line_1', entity.address_line_1,
                'address_line_2', entity.address_line_2,
                'city', entity.city,
                'postal_code', entity.postal_code,
                'region', entity.region,
                'country_code', entity.country_code,
                'vat_number', entity.vat_number,
                'registration_number', entity.registration_number,
                'billing_email', entity.billing_email
            ) INTO v_billing_snapshot
            FROM public.client_billing_entities entity
            WHERE entity.id = v_billing_entity_id
              AND entity.client_id = NEW.client_id
              AND entity.active;

            IF v_billing_snapshot IS NULL THEN
                RAISE EXCEPTION 'The selected Billing Entity does not belong to this Client';
            END IF;
            NEW.billing_entity_id := v_billing_entity_id;
            NEW.billing_snapshot := v_billing_snapshot;
        END IF;
        IF TG_OP = 'UPDATE'
           AND OLD.status IN ('Issued', 'Partially Paid', 'Paid', 'Overdue',
                              'Disputed', 'Credited', 'Annulled')
           AND (NEW.invoice_number IS DISTINCT FROM OLD.invoice_number
                OR NEW.issue_date IS DISTINCT FROM OLD.issue_date
                OR NEW.client_id IS DISTINCT FROM OLD.client_id
                OR NEW.billing_entity_id IS DISTINCT FROM OLD.billing_entity_id
                OR NEW.billing_snapshot IS DISTINCT FROM OLD.billing_snapshot
                OR NEW.total IS DISTINCT FROM OLD.total)
           AND NOT (public.is_admin() AND NEW.status IN ('Annulled', 'Credited')) THEN
            RAISE EXCEPTION 'Issued invoice facts are locked; use annulment/replacement or a credit document';
        END IF;
    ELSIF TG_TABLE_NAME = 'payments' THEN
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can record payments';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Declared capabilities and qualification records
-- ---------------------------------------------------------------------------

ALTER TABLE public.resource_specializations
    ADD COLUMN IF NOT EXISTS qualification_status TEXT;

UPDATE public.resource_specializations
SET qualification_status = CASE WHEN approved THEN 'Approved' ELSE 'Not tested' END
WHERE qualification_status IS NULL
   OR qualification_status NOT IN ('Not tested', 'Test assigned', 'Approved', 'Not approved');

ALTER TABLE public.resource_specializations
    ALTER COLUMN qualification_status SET DEFAULT 'Not tested',
    ALTER COLUMN qualification_status SET NOT NULL,
    DROP CONSTRAINT IF EXISTS resource_specializations_qualification_status_check;

ALTER TABLE public.resource_specializations
    ADD CONSTRAINT resource_specializations_qualification_status_check
    CHECK (qualification_status IN (
        'Not tested', 'Test assigned', 'Approved', 'Not approved'
    ));

CREATE OR REPLACE FUNCTION public.sync_specialization_approval_legacy()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.approved := NEW.qualification_status = 'Approved';
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_specializations_sync_approval
    ON public.resource_specializations;
CREATE TRIGGER resource_specializations_sync_approval
BEFORE INSERT OR UPDATE OF qualification_status
ON public.resource_specializations
FOR EACH ROW EXECUTE FUNCTION public.sync_specialization_approval_legacy();

CREATE TABLE IF NOT EXISTS public.resource_account_qualifications (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id          UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    account_id           UUID NOT NULL REFERENCES public.client_accounts(id) ON DELETE CASCADE,
    specialization_id    UUID REFERENCES public.specializations(id) ON DELETE CASCADE,
    qualification_status TEXT NOT NULL DEFAULT 'Not tested' CHECK (
        qualification_status IN ('Not tested', 'Test assigned', 'Approved', 'Not approved')
    ),
    evidence             TEXT,
    updated_by           UUID REFERENCES public.profiles(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE NULLS NOT DISTINCT (resource_id, account_id, specialization_id)
);

CREATE TABLE IF NOT EXISTS public.resource_tests (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id           UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    test_type             TEXT NOT NULL CHECK (test_type IN ('General', 'Domain', 'Account')),
    status                TEXT NOT NULL DEFAULT 'Assigned' CHECK (
        status IN ('Assigned', 'In review', 'Passed', 'Failed', 'Cancelled')
    ),
    source_language       TEXT,
    target_language       TEXT,
    service_type          TEXT,
    specialization_id     UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    account_id            UUID REFERENCES public.client_accounts(id) ON DELETE SET NULL,
    assigned_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at          TIMESTAMPTZ,
    memoq_project_ref     TEXT,
    reviewer_name         TEXT,
    evidence              TEXT,
    created_by            UUID REFERENCES public.profiles(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
        (test_type = 'General' AND specialization_id IS NULL AND account_id IS NULL)
        OR (test_type = 'Domain' AND specialization_id IS NOT NULL AND account_id IS NULL)
        OR (test_type = 'Account' AND account_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS resource_tests_resource_idx
    ON public.resource_tests(resource_id, assigned_at DESC);

ALTER TABLE public.resource_account_qualifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resource_tests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS resource_account_qualifications_company_select
    ON public.resource_account_qualifications;
CREATE POLICY resource_account_qualifications_company_select
ON public.resource_account_qualifications FOR SELECT TO authenticated
USING (public.is_company_user());

DROP POLICY IF EXISTS resource_account_qualifications_operations_write
    ON public.resource_account_qualifications;
CREATE POLICY resource_account_qualifications_operations_write
ON public.resource_account_qualifications FOR ALL TO authenticated
USING (public.can_manage_operations())
WITH CHECK (public.can_manage_operations());

DROP POLICY IF EXISTS resource_tests_company_select ON public.resource_tests;
CREATE POLICY resource_tests_company_select
ON public.resource_tests FOR SELECT TO authenticated
USING (public.is_company_user());

DROP POLICY IF EXISTS resource_tests_operations_write ON public.resource_tests;
CREATE POLICY resource_tests_operations_write
ON public.resource_tests FOR ALL TO authenticated
USING (public.can_manage_operations())
WITH CHECK (public.can_manage_operations());

GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.resource_account_qualifications, public.resource_tests
    TO authenticated;

CREATE OR REPLACE FUNCTION public.apply_resource_test_result()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status IN ('Assigned', 'In review') THEN
        IF NEW.test_type = 'General' THEN
            UPDATE public.resources
            SET resource_status = 'Test assigned', updated_at = NOW()
            WHERE id = NEW.resource_id
              AND resource_status IN ('New contact', 'Onboarding', 'Test assigned');
        ELSIF NEW.test_type = 'Domain' THEN
            INSERT INTO public.resource_specializations (
                resource_id, specialization_id, qualification_status, evidence
            ) VALUES (
                NEW.resource_id, NEW.specialization_id, 'Test assigned', NEW.evidence
            )
            ON CONFLICT (resource_id, specialization_id) DO UPDATE SET
                qualification_status = 'Test assigned',
                evidence = COALESCE(EXCLUDED.evidence, public.resource_specializations.evidence);
        ELSE
            INSERT INTO public.resource_account_qualifications (
                resource_id, account_id, specialization_id,
                qualification_status, evidence, updated_by
            ) VALUES (
                NEW.resource_id, NEW.account_id, NEW.specialization_id,
                'Test assigned', NEW.evidence, auth.uid()
            )
            ON CONFLICT (resource_id, account_id, specialization_id) DO UPDATE SET
                qualification_status = 'Test assigned',
                evidence = COALESCE(EXCLUDED.evidence,
                    public.resource_account_qualifications.evidence),
                updated_by = auth.uid(), updated_at = NOW();
        END IF;
    ELSIF NEW.status IN ('Passed', 'Failed') THEN
        NEW.completed_at := COALESCE(NEW.completed_at, NOW());
        IF NEW.test_type = 'General' THEN
            UPDATE public.resources
            SET resource_status = CASE WHEN NEW.status = 'Passed'
                    THEN 'Assignable' ELSE 'Do not use' END,
                updated_at = NOW()
            WHERE id = NEW.resource_id
              AND (NEW.status = 'Failed'
                   OR resource_status IN ('New contact', 'Onboarding',
                                          'Test assigned', 'Assignable'));
        ELSIF NEW.test_type = 'Domain' THEN
            INSERT INTO public.resource_specializations (
                resource_id, specialization_id, qualification_status, evidence
            ) VALUES (
                NEW.resource_id, NEW.specialization_id,
                CASE WHEN NEW.status = 'Passed' THEN 'Approved' ELSE 'Not approved' END,
                NEW.evidence
            )
            ON CONFLICT (resource_id, specialization_id) DO UPDATE SET
                qualification_status = EXCLUDED.qualification_status,
                evidence = COALESCE(EXCLUDED.evidence, public.resource_specializations.evidence);
        ELSE
            INSERT INTO public.resource_account_qualifications (
                resource_id, account_id, specialization_id,
                qualification_status, evidence, updated_by
            ) VALUES (
                NEW.resource_id, NEW.account_id, NEW.specialization_id,
                CASE WHEN NEW.status = 'Passed' THEN 'Approved' ELSE 'Not approved' END,
                NEW.evidence, auth.uid()
            )
            ON CONFLICT (resource_id, account_id, specialization_id) DO UPDATE SET
                qualification_status = EXCLUDED.qualification_status,
                evidence = COALESCE(EXCLUDED.evidence,
                    public.resource_account_qualifications.evidence),
                updated_by = auth.uid(), updated_at = NOW();
        END IF;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_tests_apply_result ON public.resource_tests;
CREATE TRIGGER resource_tests_apply_result
BEFORE INSERT OR UPDATE OF status, evidence, completed_at
ON public.resource_tests
FOR EACH ROW EXECUTE FUNCTION public.apply_resource_test_result();

-- ---------------------------------------------------------------------------
-- Resource creation, search and blind CV use the unified model.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_resource(p_payload JSONB)
RETURNS TABLE (created_resource_id UUID, created_internal_number TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_number TEXT;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF NULLIF(btrim(p_payload->>'legal_name'), '') IS NULL
       AND NULLIF(btrim(p_payload->>'company_name'), '') IS NULL THEN
        RAISE EXCEPTION 'A person or company name is required';
    END IF;

    v_number := public.next_resource_internal_number();

    INSERT INTO public.resources (
        internal_number, resource_type, legal_name, company_name, initials,
        nationality, country_of_residence, email, phone, linkedin_url,
        resource_status, portal_status, compliance_status,
        payment_terms_days, invoice_cycle, created_by
    ) VALUES (
        v_number,
        COALESCE(NULLIF(p_payload->>'resource_type', ''), 'Freelancer'),
        NULLIF(btrim(p_payload->>'legal_name'), ''),
        NULLIF(btrim(p_payload->>'company_name'), ''),
        NULLIF(btrim(p_payload->>'initials'), ''),
        NULLIF(btrim(p_payload->>'nationality'), ''),
        NULLIF(btrim(p_payload->>'country_of_residence'), ''),
        NULLIF(btrim(p_payload->>'email'), ''),
        NULLIF(btrim(p_payload->>'phone'), ''),
        NULLIF(btrim(p_payload->>'linkedin_url'), ''),
        'New contact', 'Not invited', 'Unknown',
        COALESCE(NULLIF(p_payload->>'payment_terms_days', '')::INTEGER, 60),
        COALESCE(NULLIF(p_payload->>'invoice_cycle', ''), '15th and 30th'),
        auth.uid()
    ) RETURNING id INTO v_id;

    created_resource_id := v_id;
    created_internal_number := v_number;
    RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS public.search_resources(
    TEXT, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, INTEGER
);

CREATE FUNCTION public.search_resources(
    p_search TEXT DEFAULT NULL,
    p_source_language TEXT DEFAULT NULL,
    p_target_language TEXT DEFAULT NULL,
    p_service_type TEXT DEFAULT NULL,
    p_specialization_id UUID DEFAULT NULL,
    p_classification TEXT DEFAULT NULL,
    p_eligibility TEXT DEFAULT NULL,
    p_availability TEXT DEFAULT NULL,
    p_only_approved_capabilities BOOLEAN DEFAULT FALSE,
    p_resource_type TEXT DEFAULT 'external',
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    internal_number TEXT,
    legal_name TEXT,
    company_name TEXT,
    initials TEXT,
    resource_type TEXT,
    relationship_status TEXT,
    resource_status TEXT,
    classification TEXT,
    eligibility_status TEXT,
    assignment_approved BOOLEAN,
    lifecycle_status TEXT,
    target_languages TEXT[],
    source_languages TEXT[],
    services TEXT[],
    specializations TEXT[],
    country_of_residence TEXT,
    availability_status TEXT,
    first_recorded_job DATE,
    last_recorded_job DATE,
    linkedin_url TEXT,
    compliance_status TEXT,
    total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;

    RETURN QUERY
    WITH filtered AS (
        SELECT r.*,
               COALESCE(current_availability.status, 'Unknown') AS current_availability
        FROM public.resources r
        LEFT JOIN LATERAL (
            SELECT a.status
            FROM public.resource_availability a
            WHERE a.resource_id = r.id
              AND a.starts_at <= NOW()
              AND (a.ends_at IS NULL OR a.ends_at >= NOW())
            ORDER BY a.starts_at DESC LIMIT 1
        ) current_availability ON TRUE
        WHERE (p_resource_type IS NULL
               OR (p_resource_type = 'external' AND r.resource_type <> 'Internal')
               OR (p_resource_type = 'internal' AND r.resource_type = 'Internal'))
          AND (NULLIF(btrim(p_search), '') IS NULL OR concat_ws(' ',
                r.internal_number, r.legal_name, r.company_name, r.initials,
                r.email, r.legacy_id
              ) ILIKE '%' || btrim(p_search) || '%')
          -- p_classification is retained as the compatible RPC parameter name;
          -- its value now filters the single Resource status.
          AND (p_classification IS NULL OR r.resource_status = p_classification)
          AND (p_eligibility IS NULL OR r.resource_status = p_eligibility)
          AND (p_availability IS NULL
               OR COALESCE(current_availability.status, 'Unknown') = p_availability)
          AND ((p_source_language IS NULL AND p_target_language IS NULL) OR EXISTS (
                SELECT 1 FROM public.resource_language_pairs pair
                WHERE pair.resource_id = r.id
                  AND (p_source_language IS NULL OR pair.source_language = p_source_language)
                  AND (p_target_language IS NULL OR pair.target_language = p_target_language)
              ))
          AND (p_service_type IS NULL OR EXISTS (
                SELECT 1 FROM public.resource_services service
                WHERE service.resource_id = r.id
                  AND service.service_type = p_service_type
              ))
          AND (p_specialization_id IS NULL OR EXISTS (
                SELECT 1 FROM public.resource_specializations rs
                WHERE rs.resource_id = r.id
                  AND rs.specialization_id = p_specialization_id
                  AND rs.qualification_status <> 'Not approved'
              ))
    )
    SELECT
        f.id, f.internal_number, f.legal_name, f.company_name, f.initials,
        f.resource_type, f.relationship_status, f.resource_status,
        f.classification, f.eligibility_status, f.assignment_approved,
        f.lifecycle_status,
        ARRAY(SELECT DISTINCT pair.target_language
              FROM public.resource_language_pairs pair
              WHERE pair.resource_id = f.id ORDER BY 1),
        ARRAY(SELECT DISTINCT pair.source_language
              FROM public.resource_language_pairs pair
              WHERE pair.resource_id = f.id ORDER BY 1),
        ARRAY(SELECT DISTINCT service.service_type
              FROM public.resource_services service
              WHERE service.resource_id = f.id ORDER BY 1),
        ARRAY(SELECT DISTINCT spec.name
              FROM public.resource_specializations rs
              JOIN public.specializations spec ON spec.id = rs.specialization_id
              WHERE rs.resource_id = f.id
                AND rs.qualification_status <> 'Not approved' ORDER BY 1),
        f.country_of_residence, f.current_availability,
        f.first_recorded_job, f.last_recorded_job, f.linkedin_url,
        f.compliance_status, count(*) OVER ()
    FROM filtered f
    ORDER BY
        CASE f.resource_status
            WHEN 'Preferred' THEN 1 WHEN 'Proven' THEN 2
            WHEN 'Assignable' THEN 3 WHEN 'Test assigned' THEN 4
            WHEN 'Onboarding' THEN 5 WHEN 'New contact' THEN 6
            WHEN 'Restricted' THEN 7 WHEN 'Do not use' THEN 8 ELSE 9
        END,
        f.last_recorded_job DESC NULLS LAST,
        COALESCE(f.legal_name, f.company_name), f.internal_number
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

REVOKE ALL ON FUNCTION public.search_resources(
    TEXT, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, INTEGER
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_resources(
    TEXT, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, INTEGER
) TO authenticated;

-- Job-specific search treats a missing domain/Account test as a warning, not a
-- rejection. Only an explicit Not approved result blocks that exact scope.
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
            COALESCE(current_availability.status, 'Unknown') AS current_availability
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
          AND r.resource_status <> 'Do not use'
          AND (NULLIF(btrim(p_search), '') IS NULL OR concat_ws(' ',
                r.internal_number, r.legal_name, r.company_name, r.initials, r.email
              ) ILIKE '%' || btrim(p_search) || '%')
          AND EXISTS (
              SELECT 1 FROM public.resource_language_pairs pair
              WHERE pair.resource_id = r.id
                AND (pair.source_language = v_job.source_language
                     OR v_job.source_language LIKE pair.source_language || ' (%)')
                AND (pair.target_language = v_job.target_language
                     OR v_job.target_language LIKE pair.target_language || ' (%)')
          )
          AND EXISTS (
              SELECT 1 FROM public.resource_services service
              WHERE service.resource_id = r.id
                AND service.service_type = v_job.service_type
          )
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
        CASE
            WHEN c.spec_status = 'Not approved' OR c.account_status = 'Not approved'
                THEN 'Blocked'
            WHEN c.resource_status IN ('New contact', 'Onboarding', 'Test assigned')
                THEN 'Blocked'
            WHEN c.resource_status = 'Restricted'
                 OR c.compliance_status NOT IN ('Valid', 'Waived')
                 OR (c.compliance_expiry IS NOT NULL
                     AND c.compliance_expiry < CURRENT_DATE)
                 OR c.spec_status IN ('Not tested', 'Test assigned')
                 OR c.account_status IN ('Not tested', 'Test assigned')
                THEN 'Warning'
            ELSE 'Ready'
        END,
        c.resource_status = 'Restricted'
            OR c.compliance_status NOT IN ('Valid', 'Waived')
            OR (c.compliance_expiry IS NOT NULL
                AND c.compliance_expiry < CURRENT_DATE),
        concat_ws(' · ',
            CASE WHEN c.resource_status = 'Restricted' THEN 'Restricted Resource' END,
            CASE WHEN c.resource_status IN ('New contact', 'Onboarding', 'Test assigned')
                 THEN c.resource_status || ' — not ready for production' END,
            CASE WHEN c.spec_status = 'Not tested' THEN 'Domain not tested'
                 WHEN c.spec_status = 'Test assigned' THEN 'Domain test assigned'
                 WHEN c.spec_status = 'Not approved' THEN 'Domain not approved' END,
            CASE WHEN c.account_status = 'Not tested' THEN 'Account not tested'
                 WHEN c.account_status = 'Test assigned' THEN 'Account test assigned'
                 WHEN c.account_status = 'Not approved' THEN 'Account not approved' END,
            CASE WHEN c.compliance_status NOT IN ('Valid', 'Waived')
                 THEN 'Compliance ' || c.compliance_status
                 WHEN c.compliance_expiry IS NOT NULL
                      AND c.compliance_expiry < CURRENT_DATE
                 THEN 'Compliance expired' END
        )
    FROM candidates c
    ORDER BY
        CASE
            WHEN c.spec_status = 'Approved' AND c.account_status IN ('Approved', 'Not applicable') THEN 1
            WHEN c.spec_status = 'Approved' THEN 2
            WHEN c.spec_status = 'Not tested' THEN 3
            ELSE 4
        END,
        CASE c.resource_status WHEN 'Preferred' THEN 1 WHEN 'Proven' THEN 2
            WHEN 'Assignable' THEN 3 WHEN 'Restricted' THEN 4 ELSE 5 END,
        COALESCE(c.legal_name, c.company_name), c.internal_number
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200);
END;
$$;

REVOKE ALL ON FUNCTION public.search_job_candidates(UUID, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_job_candidates(UUID, TEXT, INTEGER)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.get_blind_cv_data(p_resource_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;
    SELECT jsonb_build_object(
        'resource', jsonb_build_object(
            'internal_number', r.internal_number, 'initials', r.initials,
            'nationality', r.nationality,
            'country_of_residence', r.country_of_residence,
            'native_language', r.native_language
        ),
        'language_pairs', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'source', pair.source_language, 'target', pair.target_language,
                'native_target', pair.native_target
            ) ORDER BY pair.target_language, pair.source_language)
            FROM public.resource_language_pairs pair WHERE pair.resource_id = r.id
        ), '[]'::JSONB),
        'services', COALESCE((
            SELECT jsonb_agg(service.service_type ORDER BY service.service_type)
            FROM public.resource_services service WHERE service.resource_id = r.id
        ), '[]'::JSONB),
        'specializations', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'name', spec.name, 'experience_years', rs.experience_years,
                'evidence', rs.evidence
            ) ORDER BY spec.name)
            FROM public.resource_specializations rs
            JOIN public.specializations spec ON spec.id = rs.specialization_id
            WHERE rs.resource_id = r.id AND rs.qualification_status = 'Approved'
        ), '[]'::JSONB),
        'education', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'institution', education.institution, 'degree', education.degree,
                'field_of_study', education.field_of_study,
                'start_year', education.start_year, 'end_year', education.end_year,
                'verified', education.verified
            ) ORDER BY education.sort_order, education.end_year DESC NULLS LAST)
            FROM public.resource_education education WHERE education.resource_id = r.id
        ), '[]'::JSONB),
        'project_history', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'year', history.project_year, 'period_start', history.period_start,
                'period_end', history.period_end,
                'account', history.account_display_label,
                'source_language', history.source_language,
                'target_language', history.target_language,
                'service', history.service_type, 'specialization', spec.name,
                'summary', history.project_summary
            ) ORDER BY history.project_year DESC, history.period_end DESC NULLS LAST)
            FROM public.resource_project_history history
            LEFT JOIN public.specializations spec ON spec.id = history.specialization_id
            WHERE history.resource_id = r.id AND history.include_in_blind_cv
        ), '[]'::JSONB)
    ) INTO v_result FROM public.resources r WHERE r.id = p_resource_id;
    IF v_result IS NULL THEN RAISE EXCEPTION 'Resource not found'; END IF;
    RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- Offer and final-assignment protection
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prepare_job_offer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_job public.project_jobs%ROWTYPE;
    v_project public.projects%ROWTYPE;
    v_sequence INTEGER;
    v_spec_status TEXT;
    v_account_status TEXT;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Resource not found'; END IF;
    SELECT * INTO v_job FROM public.project_jobs WHERE id = NEW.job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = v_job.project_id;

    IF v_resource.lifecycle_status <> 'Active' THEN
        RAISE EXCEPTION 'Only an Active Resource may receive a new offer';
    END IF;
    IF v_resource.resource_status = 'Do not use' THEN
        RAISE EXCEPTION 'A Do not use Resource cannot receive a new offer';
    END IF;

    SELECT qualification_status INTO v_spec_status
    FROM public.resource_specializations
    WHERE resource_id = NEW.resource_id
      AND specialization_id = v_job.specialization_id;
    v_spec_status := COALESCE(v_spec_status, 'Not tested');

    IF v_project.account_id IS NOT NULL THEN
        SELECT qualification_status INTO v_account_status
        FROM public.resource_account_qualifications
        WHERE resource_id = NEW.resource_id
          AND account_id = v_project.account_id
          AND (specialization_id = v_job.specialization_id OR specialization_id IS NULL)
        ORDER BY (specialization_id IS NOT NULL) DESC LIMIT 1;
        v_account_status := COALESCE(v_account_status, 'Not tested');
    ELSE
        v_account_status := 'Not applicable';
    END IF;

    IF v_spec_status = 'Not approved' THEN
        RAISE EXCEPTION 'Resource is Not approved for this specialization';
    END IF;
    IF v_account_status = 'Not approved' THEN
        RAISE EXCEPTION 'Resource is Not approved for this Account';
    END IF;

    IF TG_OP = 'INSERT' AND COALESCE(NEW.sequence_number, 0) < 1 THEN
        PERFORM pg_advisory_xact_lock(hashtext(NEW.job_id::TEXT || ':offer'));
        SELECT COALESCE(max(sequence_number), 0) + 1 INTO v_sequence
        FROM public.job_offers WHERE job_id = NEW.job_id;
        NEW.sequence_number := v_sequence;
    END IF;

    NEW.restriction_warning := (
        v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred')
        OR v_resource.compliance_status NOT IN ('Valid', 'Waived')
        OR (v_resource.compliance_expiry IS NOT NULL
            AND v_resource.compliance_expiry < CURRENT_DATE)
    );

    IF NEW.restriction_warning THEN
        IF NOT NEW.restriction_overridden THEN
            RAISE EXCEPTION 'Resource requires an Administrator override for this offer';
        END IF;
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can override Resource restrictions';
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

CREATE OR REPLACE FUNCTION public.block_inactive_job_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_account_id UUID;
    v_status TEXT;
BEGIN
    IF NEW.resource_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR OLD.resource_id IS DISTINCT FROM NEW.resource_id) THEN
        SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
        IF v_resource.lifecycle_status <> 'Active' THEN
            RAISE EXCEPTION 'Only an Active Resource may receive a new Job assignment';
        END IF;
        IF v_resource.resource_status = 'Do not use' THEN
            RAISE EXCEPTION 'A Do not use Resource cannot receive a new Job assignment';
        END IF;
        IF v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred')
           AND NOT COALESCE(NEW.restriction_overridden, FALSE) THEN
            RAISE EXCEPTION 'Resource status requires an Administrator override';
        END IF;
        IF (v_resource.compliance_status NOT IN ('Valid', 'Waived')
            OR (v_resource.compliance_expiry IS NOT NULL
                AND v_resource.compliance_expiry < CURRENT_DATE))
           AND NOT COALESCE(NEW.restriction_overridden, FALSE) THEN
            RAISE EXCEPTION 'Resource compliance requires an Administrator override';
        END IF;

        SELECT qualification_status INTO v_status
        FROM public.resource_specializations
        WHERE resource_id = NEW.resource_id
          AND specialization_id = NEW.specialization_id;
        IF v_status = 'Not approved' THEN
            RAISE EXCEPTION 'Resource is Not approved for this specialization';
        END IF;

        SELECT project.account_id INTO v_account_id
        FROM public.projects project WHERE project.id = NEW.project_id;
        IF v_account_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.resource_account_qualifications qualification
            WHERE qualification.resource_id = NEW.resource_id
              AND qualification.account_id = v_account_id
              AND (qualification.specialization_id = NEW.specialization_id
                   OR qualification.specialization_id IS NULL)
              AND qualification.qualification_status = 'Not approved'
        ) THEN
            RAISE EXCEPTION 'Resource is Not approved for this Account';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.promote_resource_after_approved_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'Approved'
       AND OLD.status IS DISTINCT FROM NEW.status
       AND NEW.resource_id IS NOT NULL THEN
        UPDATE public.resources
        SET resource_status = 'Proven', updated_at = NOW()
        WHERE id = NEW.resource_id AND resource_status = 'Assignable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_promote_resource ON public.project_jobs;
CREATE TRIGGER project_jobs_promote_resource
AFTER UPDATE OF status ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.promote_resource_after_approved_job();

COMMENT ON COLUMN public.resources.resource_status IS
    'Single relationship and work-readiness status: New contact, Onboarding, Test assigned, Assignable, Proven, Preferred, Restricted or Do not use.';
COMMENT ON COLUMN public.resource_specializations.qualification_status IS
    'Not tested is informative; only Not approved blocks assignment for the specialization.';

COMMIT;
