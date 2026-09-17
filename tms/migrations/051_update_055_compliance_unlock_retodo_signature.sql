-- Retodo Ops TMS - Update 055
-- Unlocking Compliance signs and locks Agreement 1.1 for Retodo.

BEGIN;

CREATE TABLE IF NOT EXISTS public.resource_framework_agreement_issuances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    agreement_title TEXT NOT NULL,
    agreement_version TEXT NOT NULL,
    agreement_sha256 TEXT NOT NULL,
    retodo_legal_name TEXT NOT NULL,
    retodo_signatory_name TEXT NOT NULL,
    retodo_signatory_title TEXT NOT NULL,
    retodo_registration_email TEXT NOT NULL,
    signed_by UUID NOT NULL REFERENCES public.profiles(id),
    signed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(resource_id, agreement_version, agreement_sha256),
    CONSTRAINT resource_framework_agreement_issuance_hash_055_check
        CHECK (agreement_sha256 ~ '^[0-9a-f]{64}$')
);

ALTER TABLE public.resource_framework_agreement_issuances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.resource_framework_agreement_issuances
    FROM PUBLIC, anon, authenticated;

ALTER TABLE public.resource_framework_agreements
    ADD COLUMN IF NOT EXISTS retodo_signatory_name TEXT,
    ADD COLUMN IF NOT EXISTS retodo_signatory_title TEXT,
    ADD COLUMN IF NOT EXISTS retodo_registration_email TEXT,
    ADD COLUMN IF NOT EXISTS retodo_signed_by UUID REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS retodo_signed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.resource_compliance_workflow_dispatch_055(
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
    v_result JSONB;
    v_action TEXT := lower(btrim(COALESCE(p_action, '')));
    v_issuance_id UUID;
    v_version CONSTANT TEXT := '1.1';
    v_hash CONSTANT TEXT := '9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c';
BEGIN
    v_result := public.resource_compliance_workflow_dispatch_048(
        p_action, p_actor_id, p_resource_id, p_reason
    );
    IF v_action = 'request' THEN
        INSERT INTO public.resource_framework_agreement_issuances (
            resource_id, agreement_title, agreement_version, agreement_sha256,
            retodo_legal_name, retodo_signatory_name, retodo_signatory_title,
            retodo_registration_email, signed_by, signed_at
        ) VALUES (
            p_resource_id, 'Freelancer Framework Agreement', v_version, v_hash,
            'Retodo EOOD', 'Demir Atanasov', 'Owner',
            'ops@retodo-ops.com', p_actor_id, NOW()
        ) RETURNING id INTO v_issuance_id;

        PERFORM public.append_trusted_tms_audit_event(
            'Resource', p_resource_id, 'Framework agreement signed by Retodo', NULL,
            jsonb_build_object(
                'issuance_id', v_issuance_id,
                'agreement_version', v_version,
                'agreement_sha256', v_hash,
                'retodo_signatory_name', 'Demir Atanasov',
                'retodo_signatory_title', 'Owner',
                'retodo_registration_email', 'ops@retodo-ops.com',
                'unlock_actor_profile_id', p_actor_id,
                'signed_at', NOW()
            ),
            'Unlocking Compliance applied the Retodo electronic signature to the immutable Agreement version'
        );
    END IF;
    RETURN v_result || jsonb_build_object(
        'agreement_version', v_version,
        'retodo_signed', v_action = 'request'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_workflow_dispatch_055(
    TEXT, UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_compliance_workflow_dispatch_055(
    TEXT, UUID, UUID, TEXT
) TO service_role;

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
    v_issuance public.resource_framework_agreement_issuances%ROWTYPE;
    v_agreement public.resource_framework_agreements%ROWTYPE;
    v_version CONSTANT TEXT := '1.1';
    v_hash CONSTANT TEXT := '9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c';
BEGIN
    IF v_resource_id IS NULL THEN RAISE EXCEPTION 'Active External Resource portal access required'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_resource_id;
    SELECT * INTO v_issuance FROM public.resource_framework_agreement_issuances issuance
     WHERE issuance.resource_id = v_resource_id AND issuance.agreement_version = v_version
       AND issuance.agreement_sha256 = v_hash LIMIT 1;
    SELECT * INTO v_agreement FROM public.resource_framework_agreements agreement
     WHERE agreement.resource_id = v_resource_id AND agreement.agreement_version = v_version
       AND agreement.agreement_sha256 = v_hash LIMIT 1;

    RETURN jsonb_build_object(
        'visible', v_issuance.id IS NOT NULL AND v_resource.compliance_phase_status <> 'Not requested',
        'resource_id', v_resource_id,
        'status', CASE WHEN v_issuance.id IS NULL THEN 'Not issued'
                       WHEN v_agreement.id IS NULL THEN 'Awaiting Service Provider signature'
                       ELSE 'Signed' END,
        'can_accept', v_issuance.id IS NOT NULL AND v_agreement.id IS NULL
            AND v_resource.portal_status = 'Active'
            AND v_resource.compliance_phase_status <> 'Not requested',
        'agreement_title', 'Freelancer Framework Agreement',
        'agreement_version', v_version,
        'agreement_sha256', v_hash,
        'document_path', 'agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx',
        'retodo', jsonb_build_object(
            'legal_name', 'Retodo EOOD', 'registration_number', '208524462',
            'address', '48A Svetla St., 1360 Sofia, Bulgaria',
            'primary_contact', 'Retodo Ops Operations / ops@retodo-ops.com',
            'signatory_name', v_issuance.retodo_signatory_name,
            'signatory_title', v_issuance.retodo_signatory_title,
            'registration_email', v_issuance.retodo_registration_email,
            'signed_at', v_issuance.signed_at,
            'unlock_actor_profile_id', v_issuance.signed_by
        ),
        'provider', jsonb_build_object(
            'service_provider_name', COALESCE(v_agreement.service_provider_name,
                NULLIF(btrim(v_resource.company_name), ''), NULLIF(btrim(v_resource.legal_name), ''), v_resource.internal_number),
            'registration_or_id_number', COALESCE(v_agreement.registration_or_id_number, v_resource.tax_id, ''),
            'service_provider_address', COALESCE(v_agreement.service_provider_address,
                NULLIF(concat_ws(', ', NULLIF(btrim(v_resource.city), ''), NULLIF(btrim(v_resource.country_of_residence), '')), ''), ''),
            'tax_vat_number', COALESCE(v_agreement.tax_vat_number, v_resource.tax_id, ''),
            'signatory_name', COALESCE(v_agreement.signatory_name, v_resource.legal_name, ''),
            'registration_email', COALESCE(v_agreement.registration_email, v_resource.email, '')
        ),
        'effective_date', v_agreement.effective_date,
        'accepted_at', v_agreement.accepted_at
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_accept_framework_agreement_050(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_resource public.resources%ROWTYPE;
    v_issuance public.resource_framework_agreement_issuances%ROWTYPE;
    v_agreement_id UUID;
    v_version CONSTANT TEXT := '1.1';
    v_hash CONSTANT TEXT := '9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c';
    v_provider_name TEXT := NULLIF(btrim(COALESCE(p_payload->>'service_provider_name', '')), '');
    v_registration TEXT := NULLIF(btrim(COALESCE(p_payload->>'registration_or_id_number', '')), '');
    v_address TEXT := NULLIF(btrim(COALESCE(p_payload->>'service_provider_address', '')), '');
    v_signatory TEXT := NULLIF(btrim(COALESCE(p_payload->>'signatory_name', '')), '');
    v_confirmed BOOLEAN := COALESCE((p_payload->>'accepted')::BOOLEAN, FALSE);
BEGIN
    IF v_resource_id IS NULL THEN RAISE EXCEPTION 'Active External Resource portal access required'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_resource_id FOR UPDATE;
    IF v_resource.portal_status <> 'Active' OR v_resource.compliance_phase_status = 'Not requested' THEN
        RAISE EXCEPTION 'The framework agreement is not available for acceptance';
    END IF;
    SELECT * INTO v_issuance FROM public.resource_framework_agreement_issuances issuance
     WHERE issuance.resource_id = v_resource_id AND issuance.agreement_version = v_version
       AND issuance.agreement_sha256 = v_hash FOR UPDATE;
    IF v_issuance.id IS NULL THEN RAISE EXCEPTION 'Retodo must sign the Agreement by unlocking Compliance first'; END IF;
    IF EXISTS (SELECT 1 FROM public.resource_framework_agreements agreement
        WHERE agreement.resource_id = v_resource_id AND agreement.agreement_version = v_version
          AND agreement.agreement_sha256 = v_hash) THEN
        RETURN public.resource_portal_framework_agreement_050();
    END IF;
    IF NOT v_confirmed THEN RAISE EXCEPTION 'Confirm that you have read and accept the Agreement'; END IF;
    IF v_provider_name IS NULL OR v_registration IS NULL OR v_address IS NULL OR v_signatory IS NULL THEN
        RAISE EXCEPTION 'Complete the Service Provider name, ID / Tax / VAT, address and signatory name';
    END IF;
    IF length(v_provider_name) > 300 OR length(v_registration) > 150
       OR length(v_address) > 500 OR length(v_signatory) > 300 THEN
        RAISE EXCEPTION 'One or more Agreement details exceed the supported length';
    END IF;
    IF NULLIF(btrim(COALESCE(v_resource.email, '')), '') IS NULL THEN
        RAISE EXCEPTION 'The linked Resource registration email is required';
    END IF;

    INSERT INTO public.resource_framework_agreements (
        resource_id, agreement_title, agreement_version, agreement_sha256,
        effective_date, service_provider_name, registration_or_id_number,
        service_provider_address, tax_vat_number, signatory_name,
        registration_email, accepted_by, accepted_at,
        retodo_signatory_name, retodo_signatory_title, retodo_registration_email,
        retodo_signed_by, retodo_signed_at
    ) VALUES (
        v_resource_id, 'Freelancer Framework Agreement', v_version, v_hash,
        CURRENT_DATE, v_provider_name, v_registration, v_address, v_registration,
        v_signatory, lower(btrim(v_resource.email)), auth.uid(), NOW(),
        v_issuance.retodo_signatory_name, v_issuance.retodo_signatory_title,
        v_issuance.retodo_registration_email, v_issuance.signed_by, v_issuance.signed_at
    ) RETURNING id INTO v_agreement_id;

    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_resource_id, 'Framework agreement fully signed', NULL,
        jsonb_build_object(
            'agreement_id', v_agreement_id, 'agreement_version', v_version,
            'agreement_sha256', v_hash, 'retodo_signed_at', v_issuance.signed_at,
            'retodo_signatory_name', v_issuance.retodo_signatory_name,
            'service_provider_signatory_name', v_signatory,
            'service_provider_registration_email', lower(btrim(v_resource.email)),
            'service_provider_signed_by_profile_id', auth.uid(), 'service_provider_signed_at', NOW()
        ),
        'Service Provider applied the second and final TMS electronic signature'
    );
    RETURN public.resource_portal_framework_agreement_050();
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_framework_agreement_summary_050(p_resource_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_issuance public.resource_framework_agreement_issuances%ROWTYPE;
    v_agreement public.resource_framework_agreements%ROWTYPE;
    v_version CONSTANT TEXT := '1.1';
    v_hash CONSTANT TEXT := '9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c';
BEGIN
    IF NOT public.is_company_user() THEN RAISE EXCEPTION 'Company access required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.resources resource WHERE resource.id = p_resource_id
        AND resource.resource_type IN ('Freelancer', 'Company')) THEN RAISE EXCEPTION 'External Resource not found'; END IF;
    SELECT * INTO v_issuance FROM public.resource_framework_agreement_issuances issuance
     WHERE issuance.resource_id = p_resource_id AND issuance.agreement_version = v_version
       AND issuance.agreement_sha256 = v_hash LIMIT 1;
    SELECT * INTO v_agreement FROM public.resource_framework_agreements agreement
     WHERE agreement.resource_id = p_resource_id AND agreement.agreement_version = v_version
       AND agreement.agreement_sha256 = v_hash LIMIT 1;
    RETURN jsonb_build_object(
        'status', CASE WHEN v_issuance.id IS NULL THEN 'Not issued'
                       WHEN v_agreement.id IS NULL THEN 'Awaiting Service Provider signature'
                       ELSE 'Signed' END,
        'agreement_title', 'Freelancer Framework Agreement', 'agreement_version', v_version,
        'agreement_sha256', v_hash,
        'document_path', 'agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx',
        'effective_date', v_agreement.effective_date,
        'retodo', jsonb_build_object(
            'legal_name', 'Retodo EOOD', 'registration_number', '208524462',
            'address', '48A Svetla St., 1360 Sofia, Bulgaria',
            'primary_contact', 'Retodo Ops Operations / ops@retodo-ops.com',
            'signatory_name', v_issuance.retodo_signatory_name,
            'signatory_title', v_issuance.retodo_signatory_title,
            'registration_email', v_issuance.retodo_registration_email,
            'signed_at', v_issuance.signed_at,
            'unlock_actor_profile_id', v_issuance.signed_by
        ),
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

REVOKE ALL ON FUNCTION public.resource_portal_framework_agreement_050() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_framework_agreement_050() TO authenticated;
REVOKE ALL ON FUNCTION public.resource_portal_accept_framework_agreement_050(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_accept_framework_agreement_050(JSONB) TO authenticated;
REVOKE ALL ON FUNCTION public.resource_framework_agreement_summary_050(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_framework_agreement_summary_050(UUID) TO authenticated;

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
    IF v_resource_id IS NULL THEN RAISE EXCEPTION 'Active External Resource portal access required'; END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_resource_id FOR UPDATE;
    IF v_resource.portal_status <> 'Active' OR v_resource.compliance_phase_status NOT IN (
        'Requested', 'In progress', 'Changes required'
    ) THEN RAISE EXCEPTION 'Compliance evidence cannot be submitted now'; END IF;

    SELECT * INTO v_education FROM public.resource_education education
     WHERE education.resource_id = v_resource_id AND education.is_highest_relevant
     ORDER BY education.sort_order, education.created_at LIMIT 1;
    IF v_education.id IS NULL OR v_education.degree_level IS NULL OR v_education.degree_type IS NULL THEN
        RAISE EXCEPTION 'Select the highest relevant degree and degree type';
    END IF;
    IF v_education.degree_level <> 'No university degree' AND (
        NULLIF(btrim(COALESCE(v_education.institution, '')), '') IS NULL
        OR NULLIF(btrim(COALESCE(v_education.field_of_study, '')), '') IS NULL
        OR NULLIF(btrim(COALESCE(v_education.country, '')), '') IS NULL
        OR v_education.end_year IS NULL
    ) THEN RAISE EXCEPTION 'Complete the institution, field of study, country and graduation year'; END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.resource_documents document
        JOIN public.file_records file ON file.id = document.file_record_id
        WHERE document.resource_id = v_resource_id AND document.document_type = 'CV'
          AND document.status IN ('Pending', 'Valid') AND file.resource_id = v_resource_id
          AND file.storage_provider = 'Cloudflare R2' AND file.file_role = 'Compliance - CV'
          AND file.upload_status = 'Ready' AND file.archived_at IS NULL AND file.deleted_at IS NULL
    ) INTO v_has_cv;
    IF NOT v_has_cv THEN RAISE EXCEPTION 'Upload at least one CV evidence file'; END IF;

    IF v_education.degree_level <> 'No university degree' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.resource_documents document
            JOIN public.file_records file ON file.id = document.file_record_id
            WHERE document.resource_id = v_resource_id AND document.education_id = v_education.id
              AND document.document_type = 'Diploma / certificate'
              AND document.status IN ('Pending', 'Valid') AND file.resource_id = v_resource_id
              AND file.storage_provider = 'Cloudflare R2'
              AND file.file_role = 'Compliance - Diploma / certificate'
              AND file.upload_status = 'Ready' AND file.archived_at IS NULL AND file.deleted_at IS NULL
        ) INTO v_has_diploma;
        IF NOT v_has_diploma THEN
            RAISE EXCEPTION 'Upload diploma/certificate evidence for the selected degree';
        END IF;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.resource_framework_agreements agreement
        WHERE agreement.resource_id = v_resource_id AND agreement.agreement_version = '1.1'
          AND agreement.agreement_sha256 =
              '9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c'
          AND agreement.retodo_signed_at IS NOT NULL
    ) INTO v_has_agreement;
    IF NOT v_has_agreement THEN
        RAISE EXCEPTION 'Both Parties must sign the Freelancer Framework Agreement before submitting Compliance';
    END IF;

    UPDATE public.resources SET compliance_phase_status = 'Submitted',
        compliance_submitted_at = NOW(), compliance_change_reason = NULL,
        compliance_submission_notification_sent_at = NULL,
        compliance_submission_notification_error = NULL, updated_at = NOW()
    WHERE id = v_resource_id;
    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_resource_id, 'Compliance submitted',
        jsonb_build_object('status', v_resource.compliance_phase_status),
        jsonb_build_object('status', 'Submitted', 'framework_agreement_version', '1.1'),
        'External Resource submitted Compliance evidence for internal review'
    );
    RETURN public.resource_portal_compliance_048();
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_submit_compliance_048() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_submit_compliance_048() TO authenticated;

COMMENT ON TABLE public.resource_framework_agreement_issuances IS
    'Immutable Retodo electronic signature created atomically when Compliance is unlocked.';

COMMIT;
