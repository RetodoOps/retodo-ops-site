-- RetodoOps TMS — Update 050 / status-only Job saves, Project History size,
-- Compliance file deletion, submission notification and framework agreement.
-- Forward-only migration. Do not edit or re-run older migration files instead.

BEGIN;

SET LOCAL check_function_bodies = off;

DO $$
BEGIN
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.project_jobs') IS NULL
       OR to_regclass('public.resource_project_history') IS NULL
       OR to_regclass('public.resource_documents') IS NULL
       OR to_regclass('public.file_records') IS NULL
       OR to_regclass('public.file_access_logs') IS NULL
       OR to_regprocedure('public.resource_portal_compliance_048()') IS NULL
       OR to_regprocedure('public.resource_portal_submit_compliance_048()') IS NULL
       OR to_regprocedure('public.resource_compliance_workflow_summary_048(uuid)') IS NULL
       OR to_regprocedure('public.current_external_resource_id()') IS NULL
       OR to_regprocedure('public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text)') IS NULL
       OR to_regprocedure('auth.role()') IS NULL THEN
        RAISE EXCEPTION 'Migration 049 requires the operational core and migration 048';
    END IF;
END;
$$;

-- -------------------------------------------------------------------------
-- Approved Job history keeps only operational size, never a financial value.
-- Existing records are back-filled from their immutable Job relationship.
-- -------------------------------------------------------------------------

ALTER TABLE public.resource_project_history
    ADD COLUMN IF NOT EXISTS quantity NUMERIC(14, 3),
    ADD COLUMN IF NOT EXISTS unit TEXT;

UPDATE public.resource_project_history history
SET quantity = job.quantity,
    unit = job.unit,
    updated_at = NOW()
FROM public.project_jobs job
WHERE history.job_id = job.id
  AND (history.quantity IS DISTINCT FROM job.quantity
       OR history.unit IS DISTINCT FROM job.unit);

ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS compliance_submission_notification_sent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_submission_notification_error TEXT;

CREATE OR REPLACE FUNCTION public.feed_approved_job_to_resource_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_account_id UUID;
    v_account_label TEXT;
    v_project_date DATE;
BEGIN
    IF NEW.status = 'Approved' AND NEW.resource_id IS NOT NULL THEN
        SELECT project.account_id, project.project_date,
               CASE
                   WHEN account.allow_name_in_blind_cv THEN account.name
                   ELSE COALESCE(NULLIF(account.blind_cv_label, ''),
                                 'Confidential account')
               END
        INTO v_account_id, v_project_date, v_account_label
        FROM public.projects project
        LEFT JOIN public.client_accounts account ON account.id = project.account_id
        WHERE project.id = NEW.project_id;

        INSERT INTO public.resource_project_history (
            resource_id, project_id, job_id, account_id, account_display_label,
            project_year, period_start, period_end, source_language,
            target_language, service_type, specialization_id, quantity, unit
        ) VALUES (
            NEW.resource_id, NEW.project_id, NEW.id, v_account_id, v_account_label,
            EXTRACT(YEAR FROM COALESCE(v_project_date, CURRENT_DATE))::INTEGER,
            v_project_date, COALESCE(NEW.delivered_at::DATE, CURRENT_DATE),
            NEW.source_language, NEW.target_language, NEW.service_type,
            NEW.specialization_id, NEW.quantity, NEW.unit
        )
        ON CONFLICT (job_id) DO UPDATE SET
            resource_id = EXCLUDED.resource_id,
            project_id = EXCLUDED.project_id,
            account_id = EXCLUDED.account_id,
            account_display_label = EXCLUDED.account_display_label,
            project_year = EXCLUDED.project_year,
            period_start = EXCLUDED.period_start,
            period_end = EXCLUDED.period_end,
            source_language = EXCLUDED.source_language,
            target_language = EXCLUDED.target_language,
            service_type = EXCLUDED.service_type,
            specialization_id = EXCLUDED.specialization_id,
            quantity = EXCLUDED.quantity,
            unit = EXCLUDED.unit,
            updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_feed_resource_history ON public.project_jobs;
CREATE TRIGGER project_jobs_feed_resource_history
AFTER INSERT OR UPDATE OF status, resource_id, project_id, source_language,
    target_language, service_type, specialization_id, quantity, unit, delivered_at
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.feed_approved_job_to_resource_history();

-- Blind CV retains the existing anonymisation boundary. The only new fields
-- are operational quantity/unit copied from approved Job history.
CREATE OR REPLACE FUNCTION public.get_blind_cv_data(p_resource_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;
    SELECT jsonb_build_object(
        'resource', jsonb_build_object(
            'internal_number', resource.internal_number,
            'initials', resource.initials,
            'nationality', resource.nationality,
            'country_of_residence', resource.country_of_residence,
            'native_language', resource.native_language
        ),
        'professional_experience', jsonb_build_object(
            'translation', public.professional_experience_duration_047(
                resource.translation_professional_since, CURRENT_DATE),
            'revision', public.professional_experience_duration_047(
                resource.revision_professional_since, CURRENT_DATE),
            'mtpe', public.professional_experience_duration_047(
                resource.mtpe_professional_since, CURRENT_DATE)
        ),
        'language_pairs', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'source', pair.source_language,
                'target', pair.target_language,
                'native_target', pair.native_target
            ) ORDER BY pair.target_language, pair.source_language)
            FROM public.resource_language_pairs pair
            WHERE pair.resource_id = resource.id
        ), '[]'::JSONB),
        'services', COALESCE((
            SELECT jsonb_agg(service.service_type ORDER BY service.service_type)
            FROM public.resource_services service
            WHERE service.resource_id = resource.id
        ), '[]'::JSONB),
        'specializations', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'name', specialization.name,
                'experience_years', selected.experience_years,
                'evidence', selected.evidence
            ) ORDER BY specialization.name)
            FROM public.resource_specializations selected
            JOIN public.specializations specialization
              ON specialization.id = selected.specialization_id
            WHERE selected.resource_id = resource.id
              AND selected.qualification_status = 'Approved'
        ), '[]'::JSONB),
        'education', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'institution', education.institution,
                'degree', COALESCE(education.degree_level, education.degree),
                'degree_type', education.degree_type,
                'field_of_study', COALESCE(
                    education.field_of_study_other,
                    education.field_of_study_category,
                    education.field_of_study),
                'country', education.country,
                'start_year', education.start_year,
                'end_year', education.end_year,
                'verified', education.verified,
                'is_highest_relevant', education.is_highest_relevant
            ) ORDER BY education.is_highest_relevant DESC,
                       education.sort_order,
                       education.end_year DESC NULLS LAST)
            FROM public.resource_education education
            WHERE education.resource_id = resource.id
        ), '[]'::JSONB),
        'project_history', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'year', history.project_year,
                'period_start', history.period_start,
                'period_end', history.period_end,
                'account', history.account_display_label,
                'source_language', history.source_language,
                'target_language', history.target_language,
                'service', history.service_type,
                'specialization', specialization.name,
                'summary', history.project_summary,
                'quantity', history.quantity,
                'unit', history.unit
            ) ORDER BY history.project_year DESC,
                       history.period_end DESC NULLS LAST)
            FROM public.resource_project_history history
            LEFT JOIN public.specializations specialization
              ON specialization.id = history.specialization_id
            WHERE history.resource_id = resource.id
              AND history.include_in_blind_cv
        ), '[]'::JSONB)
    ) INTO v_result
    FROM public.resources resource
    WHERE resource.id = p_resource_id;
    IF v_result IS NULL THEN RAISE EXCEPTION 'Resource not found'; END IF;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_blind_cv_data(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_blind_cv_data(UUID) TO authenticated;

-- -------------------------------------------------------------------------
-- Exact supplied Freelancer Framework Agreement. Acceptance snapshots are
-- immutable and inaccessible through direct browser table grants.
-- -------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.resource_framework_agreements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    agreement_title TEXT NOT NULL,
    agreement_version TEXT NOT NULL,
    agreement_sha256 TEXT NOT NULL,
    effective_date DATE NOT NULL,
    service_provider_name TEXT NOT NULL,
    registration_or_id_number TEXT NOT NULL,
    service_provider_address TEXT NOT NULL,
    tax_vat_number TEXT NOT NULL,
    signatory_name TEXT NOT NULL,
    registration_email TEXT NOT NULL,
    accepted_by UUID NOT NULL REFERENCES public.profiles(id),
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(resource_id, agreement_version),
    CONSTRAINT resource_framework_agreement_hash_050_check CHECK (
        agreement_sha256 ~ '^[0-9a-f]{64}$'
    )
);

ALTER TABLE public.resource_framework_agreements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.resource_framework_agreements
    FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS resource_framework_agreements_resource_050_idx
    ON public.resource_framework_agreements(resource_id, accepted_at DESC);

CREATE OR REPLACE FUNCTION public.resource_portal_framework_agreement_050()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_resource public.resources%ROWTYPE;
    v_agreement public.resource_framework_agreements%ROWTYPE;
    v_version CONSTANT TEXT := '1.0';
    v_hash CONSTANT TEXT := '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a';
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    SELECT * INTO v_resource
    FROM public.resources WHERE id = v_resource_id;
    SELECT * INTO v_agreement
    FROM public.resource_framework_agreements agreement
    WHERE agreement.resource_id = v_resource_id
      AND agreement.agreement_version = v_version
      AND agreement.agreement_sha256 = v_hash
    LIMIT 1;

    RETURN jsonb_build_object(
        'visible', v_resource.compliance_phase_status <> 'Not requested',
        'resource_id', v_resource_id,
        'status', CASE WHEN v_agreement.id IS NULL
                       THEN 'Not accepted' ELSE 'Accepted' END,
        'can_accept', v_agreement.id IS NULL
            AND v_resource.portal_status = 'Active'
            AND v_resource.compliance_phase_status <> 'Not requested',
        'agreement_title', 'Freelancer Framework Agreement',
        'agreement_version', v_version,
        'agreement_sha256', v_hash,
        'document_path', 'agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx',
        'retodo', jsonb_build_object(
            'legal_name', 'Retodo EOOD',
            'registration_number', '208524462',
            'address', '48A Svetla St., 1360 Sofia, Bulgaria',
            'primary_contact', 'Retodo Ops Operations / ops@retodo-ops.com',
            'signatory', 'Demir Atanasov / Owner'
        ),
        'provider', jsonb_build_object(
            'service_provider_name', COALESCE(
                v_agreement.service_provider_name,
                NULLIF(btrim(v_resource.company_name), ''),
                NULLIF(btrim(v_resource.legal_name), ''),
                v_resource.internal_number),
            'registration_or_id_number',
                COALESCE(v_agreement.registration_or_id_number, ''),
            'service_provider_address', COALESCE(
                v_agreement.service_provider_address,
                NULLIF(concat_ws(', ', NULLIF(btrim(v_resource.city), ''),
                    NULLIF(btrim(v_resource.country_of_residence), '')), ''), ''),
            'tax_vat_number', COALESCE(v_agreement.tax_vat_number,
                                      v_resource.tax_id, ''),
            'signatory_name', COALESCE(v_agreement.signatory_name,
                                      v_resource.legal_name, ''),
            'registration_email', COALESCE(v_agreement.registration_email,
                                           v_resource.email, '')
        ),
        'effective_date', COALESCE(v_agreement.effective_date, CURRENT_DATE),
        'accepted_at', v_agreement.accepted_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_framework_agreement_050()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_framework_agreement_050()
    TO authenticated;

CREATE OR REPLACE FUNCTION public.resource_portal_accept_framework_agreement_050(
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_resource public.resources%ROWTYPE;
    v_agreement_id UUID;
    v_version CONSTANT TEXT := '1.0';
    v_hash CONSTANT TEXT := '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a';
    v_provider_name TEXT := NULLIF(btrim(COALESCE(
        p_payload->>'service_provider_name', '')), '');
    v_registration TEXT := NULLIF(btrim(COALESCE(
        p_payload->>'registration_or_id_number', '')), '');
    v_address TEXT := NULLIF(btrim(COALESCE(
        p_payload->>'service_provider_address', '')), '');
    v_tax TEXT := NULLIF(btrim(COALESCE(
        p_payload->>'tax_vat_number', '')), '');
    v_signatory TEXT := NULLIF(btrim(COALESCE(
        p_payload->>'signatory_name', '')), '');
    v_confirmed BOOLEAN := COALESCE((p_payload->>'accepted')::BOOLEAN, FALSE);
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    SELECT * INTO v_resource
    FROM public.resources WHERE id = v_resource_id FOR UPDATE;
    IF v_resource.portal_status <> 'Active'
       OR v_resource.compliance_phase_status = 'Not requested' THEN
        RAISE EXCEPTION 'The framework agreement is not available for acceptance';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.resource_framework_agreements agreement
        WHERE agreement.resource_id = v_resource_id
          AND agreement.agreement_version = v_version
          AND agreement.agreement_sha256 = v_hash
    ) THEN
        RETURN public.resource_portal_framework_agreement_050();
    END IF;
    IF NOT v_confirmed THEN
        RAISE EXCEPTION 'Confirm that you have read and accept the Agreement';
    END IF;
    IF v_provider_name IS NULL OR v_registration IS NULL OR v_address IS NULL
       OR v_tax IS NULL OR v_signatory IS NULL THEN
        RAISE EXCEPTION 'Complete the Service Provider name, ID/registration number, address, tax/VAT number and signatory name';
    END IF;
    IF length(v_provider_name) > 300 OR length(v_registration) > 150
       OR length(v_address) > 500 OR length(v_tax) > 150
       OR length(v_signatory) > 300 THEN
        RAISE EXCEPTION 'One or more Agreement details exceed the supported length';
    END IF;
    IF NULLIF(btrim(COALESCE(v_resource.email, '')), '') IS NULL THEN
        RAISE EXCEPTION 'The linked Resource registration email is required';
    END IF;

    INSERT INTO public.resource_framework_agreements (
        resource_id, agreement_title, agreement_version, agreement_sha256,
        effective_date, service_provider_name, registration_or_id_number,
        service_provider_address, tax_vat_number, signatory_name,
        registration_email, accepted_by, accepted_at
    ) VALUES (
        v_resource_id, 'Freelancer Framework Agreement', v_version, v_hash,
        CURRENT_DATE, v_provider_name, v_registration, v_address, v_tax,
        v_signatory, lower(btrim(v_resource.email)), auth.uid(), NOW()
    ) RETURNING id INTO v_agreement_id;

    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_resource_id, 'Framework agreement accepted', NULL,
        jsonb_build_object(
            'agreement_id', v_agreement_id,
            'agreement_version', v_version,
            'agreement_sha256', v_hash,
            'signatory_name', v_signatory,
            'registration_email', lower(btrim(v_resource.email)),
            'accepted_by_profile_id', auth.uid()
        ),
        'Service Provider accepted the supplied Agreement electronically in the TMS'
    );
    RETURN public.resource_portal_framework_agreement_050();
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_accept_framework_agreement_050(JSONB)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_accept_framework_agreement_050(JSONB)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.resource_framework_agreement_summary_050(
    p_resource_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_agreement public.resource_framework_agreements%ROWTYPE;
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.resources resource
        WHERE resource.id = p_resource_id
          AND resource.resource_type IN ('Freelancer', 'Company')
    ) THEN RAISE EXCEPTION 'External Resource not found'; END IF;

    SELECT * INTO v_agreement
    FROM public.resource_framework_agreements agreement
    WHERE agreement.resource_id = p_resource_id
      AND agreement.agreement_version = '1.0'
      AND agreement.agreement_sha256 =
          '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a'
    LIMIT 1;
    RETURN jsonb_build_object(
        'status', CASE WHEN v_agreement.id IS NULL
                       THEN 'Not accepted' ELSE 'Accepted' END,
        'agreement_title', 'Freelancer Framework Agreement',
        'agreement_version', '1.0',
        'agreement_sha256',
            '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a',
        'document_path', 'agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx',
        'effective_date', v_agreement.effective_date,
        'service_provider_name', v_agreement.service_provider_name,
        'registration_or_id_number', v_agreement.registration_or_id_number,
        'service_provider_address', v_agreement.service_provider_address,
        'tax_vat_number', v_agreement.tax_vat_number,
        'signatory_name', v_agreement.signatory_name,
        'registration_email', v_agreement.registration_email,
        'accepted_at', v_agreement.accepted_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_framework_agreement_summary_050(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_framework_agreement_summary_050(UUID)
    TO authenticated;

-- -------------------------------------------------------------------------
-- Portal submission now requires the exact current Agreement. Existing
-- already-submitted/complete records are not rewritten or fabricated.
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_portal_submit_compliance_048()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_resource public.resources%ROWTYPE;
    v_education public.resource_education%ROWTYPE;
    v_has_cv BOOLEAN := FALSE;
    v_has_diploma BOOLEAN := FALSE;
    v_has_agreement BOOLEAN := FALSE;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    SELECT * INTO v_resource
    FROM public.resources WHERE id = v_resource_id FOR UPDATE;
    IF v_resource.portal_status <> 'Active'
       OR v_resource.compliance_phase_status NOT IN (
           'Requested', 'In progress', 'Changes required'
       ) THEN
        RAISE EXCEPTION 'Compliance evidence cannot be submitted now';
    END IF;

    SELECT * INTO v_education
    FROM public.resource_education education
    WHERE education.resource_id = v_resource_id
      AND education.is_highest_relevant
    ORDER BY education.sort_order, education.created_at
    LIMIT 1;
    IF v_education.id IS NULL OR v_education.degree_level IS NULL
       OR v_education.degree_type IS NULL THEN
        RAISE EXCEPTION 'Select the highest relevant degree and degree type';
    END IF;
    IF v_education.degree_level <> 'No university degree' AND (
        NULLIF(btrim(COALESCE(v_education.institution, '')), '') IS NULL
        OR NULLIF(btrim(COALESCE(v_education.field_of_study, '')), '') IS NULL
        OR NULLIF(btrim(COALESCE(v_education.country, '')), '') IS NULL
        OR v_education.end_year IS NULL
    ) THEN
        RAISE EXCEPTION 'Complete the institution, field of study, country and graduation year';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.resource_documents document
        JOIN public.file_records file ON file.id = document.file_record_id
        WHERE document.resource_id = v_resource_id
          AND document.document_type = 'CV'
          AND document.status IN ('Pending', 'Valid')
          AND file.resource_id = v_resource_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.file_role = 'Compliance - CV'
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND file.deleted_at IS NULL
    ) INTO v_has_cv;
    IF NOT v_has_cv THEN RAISE EXCEPTION 'Upload at least one CV evidence file'; END IF;

    IF v_education.degree_level <> 'No university degree' THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.resource_documents document
            JOIN public.file_records file ON file.id = document.file_record_id
            WHERE document.resource_id = v_resource_id
              AND document.education_id = v_education.id
              AND document.document_type = 'Diploma / certificate'
              AND document.status IN ('Pending', 'Valid')
              AND file.resource_id = v_resource_id
              AND file.storage_provider = 'Cloudflare R2'
              AND file.file_role = 'Compliance - Diploma / certificate'
              AND file.upload_status = 'Ready'
              AND file.archived_at IS NULL
              AND file.deleted_at IS NULL
        ) INTO v_has_diploma;
        IF NOT v_has_diploma THEN
            RAISE EXCEPTION 'Upload diploma/certificate evidence for the selected degree';
        END IF;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.resource_framework_agreements agreement
        WHERE agreement.resource_id = v_resource_id
          AND agreement.agreement_version = '1.0'
          AND agreement.agreement_sha256 =
              '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a'
    ) INTO v_has_agreement;
    IF NOT v_has_agreement THEN
        RAISE EXCEPTION 'Read and accept the Freelancer Framework Agreement before submitting Compliance';
    END IF;

    UPDATE public.resources
    SET compliance_phase_status = 'Submitted',
        compliance_submitted_at = NOW(),
        compliance_change_reason = NULL,
        compliance_submission_notification_sent_at = NULL,
        compliance_submission_notification_error = NULL,
        updated_at = NOW()
    WHERE id = v_resource_id;
    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_resource_id, 'Compliance submitted',
        jsonb_build_object('status', v_resource.compliance_phase_status),
        jsonb_build_object('status', 'Submitted',
                           'framework_agreement_version', '1.0'),
        'External Resource submitted Compliance evidence for internal review'
    );
    RETURN public.resource_portal_compliance_048();
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_submit_compliance_048()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_submit_compliance_048()
    TO authenticated;

-- -------------------------------------------------------------------------
-- Ready Compliance evidence can be safely deleted from R2 and soft-deleted
-- in metadata. Exact-own-resource and internal-operation boundaries remain.
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_compliance_file_delete_050(
    p_action TEXT,
    p_actor_id UUID,
    p_file_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_actor_resource_id UUID;
    v_actor_portal_status TEXT;
    v_actor_phase_status TEXT;
    v_is_operations BOOLEAN := FALSE;
    v_file public.file_records%ROWTYPE;
    v_document public.resource_documents%ROWTYPE;
    v_target_phase TEXT;
    v_action TEXT := lower(btrim(COALESCE(p_action, '')));
    v_reason TEXT := left(COALESCE(NULLIF(btrim(p_reason), ''),
        'Compliance evidence deleted by the authorized user'), 500);
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    IF p_actor_id IS NULL OR p_file_id IS NULL THEN
        RAISE EXCEPTION 'Verified actor and file are required';
    END IF;
    SELECT profile.role INTO v_role
    FROM public.profiles profile WHERE profile.id = p_actor_id;
    IF v_role IS NULL THEN RAISE EXCEPTION 'Active TMS profile required'; END IF;
    v_is_operations := v_role IN ('admin', 'pm', 'client_relations');

    IF v_role = 'resource' THEN
        SELECT resource.id, resource.portal_status,
               resource.compliance_phase_status
        INTO v_actor_resource_id, v_actor_portal_status, v_actor_phase_status
        FROM public.resources resource
        WHERE resource.profile_id = p_actor_id
          AND resource.resource_type IN ('Freelancer', 'Company')
          AND resource.lifecycle_status IN ('Active', 'On leave')
          AND resource.portal_status IN ('Active', 'Read-only')
        LIMIT 1;
    END IF;

    SELECT file.* INTO v_file
    FROM public.file_records file
    WHERE file.id = p_file_id
      AND file.storage_provider = 'Cloudflare R2'
      AND file.job_id IS NULL
      AND file.file_role IN (
          'Compliance - Diploma / certificate', 'Compliance - CV')
      AND file.upload_status = 'Ready'
      AND file.archived_at IS NULL
      AND file.deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Compliance file not found'; END IF;

    SELECT * INTO v_document
    FROM public.resource_documents document
    WHERE document.file_record_id = v_file.id
      AND document.resource_id = v_file.resource_id
      AND document.status IN ('Pending', 'Valid')
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Compliance evidence link not found'; END IF;
    SELECT resource.compliance_phase_status INTO v_target_phase
    FROM public.resources resource WHERE resource.id = v_file.resource_id;

    IF v_is_operations THEN
        IF v_target_phase = 'Complete' THEN
            RAISE EXCEPTION 'Request Compliance changes before deleting completed evidence';
        END IF;
    ELSIF NOT (
        v_role = 'resource'
        AND v_actor_resource_id = v_file.resource_id
        AND v_actor_portal_status = 'Active'
        AND v_actor_phase_status IN (
            'Requested', 'In progress', 'Changes required')
    ) THEN
        RAISE EXCEPTION 'Compliance file not found';
    END IF;

    IF v_action = 'inspect' THEN
        RETURN jsonb_build_object(
            'file_id', v_file.id,
            'object_key', v_file.object_key,
            'original_filename', v_file.original_filename,
            'resource_id', v_file.resource_id,
            'document_id', v_document.id
        );
    ELSIF v_action <> 'commit' THEN
        RAISE EXCEPTION 'Unsupported Compliance delete action';
    END IF;

    UPDATE public.file_records
    SET upload_status = 'Deleted', deleted_at = NOW(), archived_at = NOW(),
        storage_error = v_reason
    WHERE id = v_file.id;
    UPDATE public.resource_documents
    SET status = 'Rejected',
        reviewed_by = CASE WHEN v_is_operations THEN p_actor_id ELSE NULL END,
        reviewed_at = NOW(), notes = v_reason, updated_at = NOW()
    WHERE id = v_document.id;
    INSERT INTO public.file_access_logs(
        file_record_id, profile_id, resource_id, action
    ) VALUES (v_file.id, p_actor_id, v_file.resource_id, 'Delete');

    IF v_role = 'resource' THEN
        UPDATE public.resources
        SET compliance_phase_status = CASE
                WHEN compliance_phase_status IN ('Requested', 'Changes required')
                    THEN 'In progress'
                ELSE compliance_phase_status END,
            compliance_last_resource_edit_at = NOW(), updated_at = NOW()
        WHERE id = v_file.resource_id;
    END IF;
    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_file.resource_id, 'Compliance evidence deleted',
        jsonb_build_object(
            'document_id', v_document.id,
            'file_id', v_file.id,
            'status', v_document.status),
        jsonb_build_object(
            'document_id', v_document.id,
            'file_id', v_file.id,
            'status', 'Rejected',
            'deleted_by_profile_id', p_actor_id),
        v_reason
    );
    RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Deleted');
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_file_delete_050(
    TEXT, UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_compliance_file_delete_050(
    TEXT, UUID, UUID, TEXT
) TO service_role;

-- -------------------------------------------------------------------------
-- Durable state for the Resource-to-internal submission email. The server
-- sends it to the already configured Retodo Ops mailbox; no new env variable.
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_compliance_submission_notification_050(
    p_action TEXT,
    p_actor_id UUID,
    p_resource_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_resource public.resources%ROWTYPE;
    v_action TEXT := lower(btrim(COALESCE(p_action, '')));
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    SELECT profile.role INTO v_role
    FROM public.profiles profile WHERE profile.id = p_actor_id;
    IF v_role IS NULL THEN RAISE EXCEPTION 'Active TMS profile required'; END IF;

    SELECT * INTO v_resource
    FROM public.resources resource
    WHERE resource.id = p_resource_id
      AND resource.resource_type IN ('Freelancer', 'Company')
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'External Resource not found'; END IF;
    IF NOT (
        v_role IN ('admin', 'pm', 'client_relations')
        OR (v_role = 'resource' AND v_resource.profile_id = p_actor_id)
    ) THEN RAISE EXCEPTION 'Submission notification access denied'; END IF;
    IF v_resource.compliance_phase_status <> 'Submitted' THEN
        RAISE EXCEPTION 'Compliance is not submitted for review';
    END IF;

    IF v_action = 'sent' THEN
        UPDATE public.resources
        SET compliance_submission_notification_sent_at = NOW(),
            compliance_submission_notification_error = NULL,
            updated_at = NOW()
        WHERE id = p_resource_id;
    ELSIF v_action = 'failed' THEN
        UPDATE public.resources
        SET compliance_submission_notification_error = left(COALESCE(
                NULLIF(btrim(p_reason), ''),
                'Internal Compliance submission notification failed'), 500),
            updated_at = NOW()
        WHERE id = p_resource_id;
    ELSIF v_action <> 'prepare' THEN
        RAISE EXCEPTION 'Unsupported submission notification action';
    END IF;

    SELECT * INTO v_resource FROM public.resources WHERE id = p_resource_id;
    RETURN jsonb_build_object(
        'resource_id', v_resource.id,
        'internal_number', v_resource.internal_number,
        'name', COALESCE(NULLIF(btrim(v_resource.legal_name), ''),
                         NULLIF(btrim(v_resource.company_name), ''),
                         v_resource.internal_number),
        'submitted_at', v_resource.compliance_submitted_at,
        'notification_kind', CASE
            WHEN v_action = 'prepare'
             AND (v_resource.compliance_submission_notification_sent_at IS NULL
                  OR v_resource.compliance_submission_notification_sent_at
                     < v_resource.compliance_submitted_at)
                THEN 'compliance_submitted'
            ELSE NULL END,
        'already_sent', v_resource.compliance_submission_notification_sent_at
            IS NOT NULL
            AND v_resource.compliance_submission_notification_sent_at
                >= v_resource.compliance_submitted_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_submission_notification_050(
    TEXT, UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_compliance_submission_notification_050(
    TEXT, UUID, UUID, TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.resource_compliance_workflow_summary_048(
    p_resource_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;
    SELECT * INTO v_resource FROM public.resources
    WHERE id = p_resource_id
      AND resource_type IN ('Freelancer', 'Company');
    IF NOT FOUND THEN RAISE EXCEPTION 'External Resource not found'; END IF;

    RETURN jsonb_build_object(
        'status', v_resource.compliance_phase_status,
        'successful_general_test',
            public.resource_has_successful_general_test_048(p_resource_id),
        'can_request', v_resource.compliance_phase_status = 'Not requested'
            AND public.resource_has_successful_general_test_048(p_resource_id),
        'requested_at', v_resource.compliance_requested_at,
        'submitted_at', v_resource.compliance_submitted_at,
        'changes_requested_at', v_resource.compliance_changes_requested_at,
        'change_reason', v_resource.compliance_change_reason,
        'completed_at', v_resource.compliance_completed_at,
        'last_resource_edit_at', v_resource.compliance_last_resource_edit_at,
        'notification_sent_at', v_resource.compliance_notification_sent_at,
        'notification_error', v_resource.compliance_notification_error,
        'submission_notification_sent_at',
            v_resource.compliance_submission_notification_sent_at,
        'submission_notification_error',
            v_resource.compliance_submission_notification_error,
        'framework_agreement',
            public.resource_framework_agreement_summary_050(p_resource_id),
        'completion_check',
            public.resource_compliance_completion_check_048(p_resource_id)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_workflow_summary_048(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_compliance_workflow_summary_048(UUID)
    TO authenticated;

COMMENT ON COLUMN public.resource_project_history.quantity IS
    'Approximate approved Job size; operational only and never a financial value.';
COMMENT ON TABLE public.resource_framework_agreements IS
    'Immutable electronic acceptance snapshot for the supplied Retodo EOOD Freelancer Framework Agreement.';
COMMENT ON FUNCTION public.resource_compliance_file_delete_050(TEXT, UUID, UUID, TEXT) IS
    'Two-phase service-only authorization and metadata commit for deleting private Compliance evidence.';

COMMIT;
