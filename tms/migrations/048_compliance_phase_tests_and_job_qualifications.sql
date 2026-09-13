-- RetodoOps TMS — Update 049 / prompted Compliance phase, separated test
-- result, and approved-Job Account qualification evidence.
-- Forward-only migration. Do not edit or re-run older migration files instead.

BEGIN;

SET LOCAL check_function_bodies = off;

DO $$
BEGIN
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.resource_tests') IS NULL
       OR to_regclass('public.resource_education') IS NULL
       OR to_regclass('public.resource_documents') IS NULL
       OR to_regclass('public.project_jobs') IS NULL
       OR to_regprocedure('public.professional_experience_duration_047(date,date)') IS NULL
       OR to_regprocedure('public.resource_compliance_summary_047(uuid)') IS NULL
       OR to_regprocedure('public.current_external_resource_id()') IS NULL
       OR to_regprocedure('public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text)') IS NULL
       OR to_regprocedure('auth.role()') IS NULL THEN
        RAISE EXCEPTION
            'Migration 048 requires the operational core and migration 047';
    END IF;
END;
$$;

-- -------------------------------------------------------------------------
-- Tests: workflow status and result are independent. A legacy pre-TMS pass
-- deliberately has no assigned/completed date because no trustworthy TMS date
-- exists. It is never back-filled or fabricated.
-- -------------------------------------------------------------------------

ALTER TABLE public.resource_tests
    ADD COLUMN IF NOT EXISTS test_result TEXT,
    ADD COLUMN IF NOT EXISTS tested_before_tms BOOLEAN NOT NULL DEFAULT FALSE;

DROP TRIGGER IF EXISTS resource_tests_apply_result ON public.resource_tests;

ALTER TABLE public.resource_tests
    DROP CONSTRAINT IF EXISTS resource_tests_status_check;

UPDATE public.resource_tests
SET test_result = CASE status
        WHEN 'Passed' THEN 'Pass'
        WHEN 'Failed' THEN 'Fail'
        ELSE test_result
    END,
    completed_at = CASE
        WHEN status IN ('Passed', 'Failed')
            THEN COALESCE(completed_at, updated_at, created_at, NOW())
        ELSE completed_at
    END,
    status = CASE
        WHEN status IN ('Passed', 'Failed') THEN 'Completed'
        ELSE status
    END;

ALTER TABLE public.resource_tests
    ALTER COLUMN assigned_at DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_tests'::regclass
          AND conname = 'resource_tests_status_048_check'
    ) THEN
        ALTER TABLE public.resource_tests
            ADD CONSTRAINT resource_tests_status_048_check CHECK (
                status IN ('Assigned', 'In review', 'Completed', 'Cancelled')
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_tests'::regclass
          AND conname = 'resource_tests_result_048_check'
    ) THEN
        ALTER TABLE public.resource_tests
            ADD CONSTRAINT resource_tests_result_048_check CHECK (
                test_result IS NULL OR test_result IN ('Pass', 'Fail')
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_tests'::regclass
          AND conname = 'resource_tests_workflow_048_check'
    ) THEN
        ALTER TABLE public.resource_tests
            ADD CONSTRAINT resource_tests_workflow_048_check CHECK (
                (
                    tested_before_tms
                    AND status = 'Completed'
                    AND test_result = 'Pass'
                    AND assigned_at IS NULL
                    AND completed_at IS NULL
                )
                OR (
                    NOT tested_before_tms
                    AND (
                        (status = 'Completed'
                         AND test_result IS NOT NULL
                         AND test_result IN ('Pass', 'Fail')
                         AND completed_at IS NOT NULL)
                        OR
                        (status <> 'Completed' AND test_result IS NULL)
                    )
                )
            );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_resource_test_result()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.tested_before_tms THEN
        NEW.status := 'Completed';
        NEW.test_result := 'Pass';
        NEW.assigned_at := NULL;
        NEW.completed_at := NULL;
    ELSIF NEW.status = 'Completed' THEN
        IF NEW.test_result IS NULL OR NEW.test_result NOT IN ('Pass', 'Fail') THEN
            RAISE EXCEPTION 'A completed test requires a Pass or Fail result';
        END IF;
        NEW.completed_at := COALESCE(NEW.completed_at, NOW());
        NEW.assigned_at := COALESCE(NEW.assigned_at, NEW.created_at, NOW());
    ELSE
        NEW.test_result := NULL;
        NEW.completed_at := NULL;
        NEW.assigned_at := COALESCE(NEW.assigned_at, NEW.created_at, NOW());
    END IF;

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
                evidence = COALESCE(EXCLUDED.evidence,
                    public.resource_specializations.evidence);
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
    ELSIF NEW.status = 'Completed' THEN
        IF NEW.test_type = 'General' THEN
            UPDATE public.resources
            SET resource_status = CASE WHEN NEW.test_result = 'Pass'
                    THEN 'Assignable' ELSE 'Do not use' END,
                updated_at = NOW()
            WHERE id = NEW.resource_id
              AND (NEW.test_result = 'Fail'
                   OR resource_status IN ('New contact', 'Onboarding',
                                          'Test assigned', 'Assignable'));
        ELSIF NEW.test_type = 'Domain' THEN
            INSERT INTO public.resource_specializations (
                resource_id, specialization_id, qualification_status, evidence
            ) VALUES (
                NEW.resource_id, NEW.specialization_id,
                CASE WHEN NEW.test_result = 'Pass'
                     THEN 'Approved' ELSE 'Not approved' END,
                NEW.evidence
            )
            ON CONFLICT (resource_id, specialization_id) DO UPDATE SET
                qualification_status = EXCLUDED.qualification_status,
                evidence = COALESCE(EXCLUDED.evidence,
                    public.resource_specializations.evidence);
        ELSE
            INSERT INTO public.resource_account_qualifications (
                resource_id, account_id, specialization_id,
                qualification_status, evidence, updated_by
            ) VALUES (
                NEW.resource_id, NEW.account_id, NEW.specialization_id,
                CASE WHEN NEW.test_result = 'Pass'
                     THEN 'Approved' ELSE 'Not approved' END,
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

CREATE TRIGGER resource_tests_apply_result
BEFORE INSERT OR UPDATE OF status, test_result, tested_before_tms,
    assigned_at, completed_at, evidence
ON public.resource_tests
FOR EACH ROW EXECUTE FUNCTION public.apply_resource_test_result();

CREATE INDEX IF NOT EXISTS resource_tests_successful_general_048_idx
    ON public.resource_tests(resource_id, test_result)
    WHERE test_type = 'General' AND status = 'Completed';

-- -------------------------------------------------------------------------
-- Controlled education vocabulary. Legacy free-text values remain readable;
-- no existing record is assigned a new classification by this migration.
-- -------------------------------------------------------------------------

ALTER TABLE public.resource_education
    ADD COLUMN IF NOT EXISTS degree_level TEXT,
    ADD COLUMN IF NOT EXISTS field_of_study_category TEXT,
    ADD COLUMN IF NOT EXISTS field_of_study_other TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_education'::regclass
          AND conname = 'resource_education_degree_level_048_check'
    ) THEN
        ALTER TABLE public.resource_education
            ADD CONSTRAINT resource_education_degree_level_048_check CHECK (
                degree_level IS NULL OR degree_level IN (
                    'Doctorate',
                    'Master''s degree',
                    'Bachelor''s degree',
                    'Professional bachelor / short-cycle higher education',
                    'Other university degree',
                    'No university degree'
                )
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_education'::regclass
          AND conname = 'resource_education_field_category_048_check'
    ) THEN
        ALTER TABLE public.resource_education
            ADD CONSTRAINT resource_education_field_category_048_check CHECK (
                field_of_study_category IS NULL OR field_of_study_category IN (
                    'Translation', 'Interpreting',
                    'Translation and Interpreting', 'Linguistics',
                    'Philology / Language studies', 'Law',
                    'Economics / Finance', 'Business / Management',
                    'Medicine / Life sciences', 'Engineering / Technology',
                    'Computer science / IT', 'Other'
                )
            );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_resource_education_048(
    p_resource_id UUID,
    p_education_id UUID,
    p_payload JSONB,
    p_verified BOOLEAN,
    p_origin TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id UUID;
    v_before JSONB;
    v_after JSONB;
    v_degree_level TEXT := NULLIF(btrim(COALESCE(p_payload->>'degree_level', '')), '');
    v_degree_type TEXT := NULLIF(btrim(COALESCE(p_payload->>'degree_type', '')), '');
    v_field_category TEXT := NULLIF(btrim(COALESCE(p_payload->>'field_of_study_category', '')), '');
    v_field_other TEXT := NULLIF(btrim(COALESCE(p_payload->>'field_of_study_other', '')), '');
    v_institution TEXT := NULLIF(btrim(COALESCE(p_payload->>'institution', '')), '');
    v_country TEXT := NULLIF(btrim(COALESCE(p_payload->>'country', '')), '');
    v_end_year INTEGER := NULLIF(p_payload->>'end_year', '')::INTEGER;
    v_highest BOOLEAN := COALESCE((p_payload->>'is_highest_relevant')::BOOLEAN, TRUE);
    v_existing public.resource_education%ROWTYPE;
    v_final_field TEXT;
    v_final_degree TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.resources resource
        WHERE resource.id = p_resource_id
          AND resource.resource_type IN ('Freelancer', 'Company')
    ) THEN
        RAISE EXCEPTION 'External Resource not found';
    END IF;

    IF v_degree_level IS NOT NULL AND v_degree_level NOT IN (
        'Doctorate', 'Master''s degree', 'Bachelor''s degree',
        'Professional bachelor / short-cycle higher education',
        'Other university degree', 'No university degree'
    ) THEN
        RAISE EXCEPTION 'Unsupported highest relevant degree';
    END IF;
    IF v_degree_type IS NOT NULL AND v_degree_type NOT IN (
        'Translation / language degree',
        'Other university degree',
        'No university degree'
    ) THEN
        RAISE EXCEPTION 'Unsupported degree type';
    END IF;
    IF v_field_category IS NOT NULL AND v_field_category NOT IN (
        'Translation', 'Interpreting', 'Translation and Interpreting',
        'Linguistics', 'Philology / Language studies', 'Law',
        'Economics / Finance', 'Business / Management',
        'Medicine / Life sciences', 'Engineering / Technology',
        'Computer science / IT', 'Other'
    ) THEN
        RAISE EXCEPTION 'Unsupported field of study';
    END IF;
    IF v_field_category = 'Other' THEN
        v_final_field := v_field_other;
    ELSE
        v_field_other := NULL;
        v_final_field := v_field_category;
    END IF;
    IF v_end_year IS NOT NULL AND (
        v_end_year < 1900
        OR v_end_year > extract(YEAR FROM CURRENT_DATE)::INTEGER
    ) THEN
        RAISE EXCEPTION 'Enter a valid graduation year';
    END IF;

    IF p_education_id IS NOT NULL THEN
        SELECT * INTO v_existing
        FROM public.resource_education education
        WHERE education.id = p_education_id
          AND education.resource_id = p_resource_id
        FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Education record not found'; END IF;
        v_before := to_jsonb(v_existing);
    END IF;

    IF v_degree_level = 'No university degree' THEN
        v_degree_type := 'No university degree';
        v_field_category := NULL;
        v_field_other := NULL;
        v_final_field := NULL;
        v_institution := NULL;
        v_country := NULL;
        v_end_year := NULL;
    ELSIF v_degree_level IS NOT NULL
          AND v_degree_type = 'No university degree' THEN
        RAISE EXCEPTION 'Degree type does not match the selected university degree';
    END IF;

    v_final_degree := CASE
        WHEN v_degree_level IS NOT NULL THEN v_degree_level
        WHEN p_education_id IS NOT NULL THEN v_existing.degree
        ELSE NULL
    END;
    IF v_final_field IS NULL AND v_field_category IS NULL
       AND p_education_id IS NOT NULL
       AND v_existing.field_of_study_category IS NULL THEN
        v_final_field := v_existing.field_of_study;
    END IF;

    IF v_highest THEN
        UPDATE public.resource_education
        SET is_highest_relevant = FALSE
        WHERE resource_id = p_resource_id
          AND is_highest_relevant
          AND (p_education_id IS NULL OR id <> p_education_id);
    END IF;

    IF p_education_id IS NULL THEN
        INSERT INTO public.resource_education (
            resource_id, institution, degree, degree_level, degree_type,
            field_of_study, field_of_study_category, field_of_study_other,
            country, graduation_date, end_year, verified,
            is_highest_relevant, sort_order
        ) VALUES (
            p_resource_id, v_institution, v_final_degree, v_degree_level,
            v_degree_type, v_final_field, v_field_category, v_field_other,
            v_country, NULL, v_end_year, COALESCE(p_verified, FALSE),
            v_highest,
            COALESCE((SELECT max(sort_order) + 1
                      FROM public.resource_education
                      WHERE resource_id = p_resource_id), 0)
        ) RETURNING id INTO v_id;
        v_before := NULL;
    ELSE
        UPDATE public.resource_education
        SET institution = v_institution,
            degree = v_final_degree,
            degree_level = v_degree_level,
            degree_type = v_degree_type,
            field_of_study = v_final_field,
            field_of_study_category = v_field_category,
            field_of_study_other = v_field_other,
            country = v_country,
            -- graduation_date is retained only for backward compatibility.
            -- The locked Update 049 UI never asks for or invents a month.
            end_year = v_end_year,
            verified = COALESCE(p_verified, FALSE),
            is_highest_relevant = v_highest
        WHERE id = p_education_id
        RETURNING id INTO v_id;
    END IF;

    SELECT to_jsonb(education) INTO v_after
    FROM public.resource_education education WHERE education.id = v_id;
    PERFORM public.append_trusted_tms_audit_event(
        'Resource', p_resource_id,
        CASE WHEN p_education_id IS NULL
             THEN 'Compliance education added'
             ELSE 'Compliance education updated' END,
        v_before, v_after,
        COALESCE(NULLIF(btrim(p_origin), ''), 'Compliance education changed')
    );
    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_resource_education_048(
    UUID, UUID, JSONB, BOOLEAN, TEXT
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.save_resource_education_048(
    p_resource_id UUID,
    p_education_id UUID,
    p_payload JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;
    RETURN public.apply_resource_education_048(
        p_resource_id,
        p_education_id,
        COALESCE(p_payload, '{}'::JSONB),
        COALESCE((p_payload->>'verified')::BOOLEAN, FALSE),
        'Internal Compliance evidence edit'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.save_resource_education_048(UUID, UUID, JSONB)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_resource_education_048(UUID, UUID, JSONB)
    TO authenticated;

-- -------------------------------------------------------------------------
-- Prompted Compliance phase. This state is deliberately not consulted by Job
-- assignment or offer functions: Resources may work before it is complete.
-- -------------------------------------------------------------------------

ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS compliance_phase_status TEXT NOT NULL DEFAULT 'Not requested',
    ADD COLUMN IF NOT EXISTS compliance_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_requested_by UUID REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS compliance_submitted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_changes_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_changes_requested_by UUID REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS compliance_change_reason TEXT,
    ADD COLUMN IF NOT EXISTS compliance_completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_completed_by UUID REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS compliance_last_resource_edit_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_notification_sent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS compliance_notification_error TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resources'::regclass
          AND conname = 'resources_compliance_phase_048_check'
    ) THEN
        ALTER TABLE public.resources
            ADD CONSTRAINT resources_compliance_phase_048_check CHECK (
                compliance_phase_status IN (
                    'Not requested', 'Requested', 'In progress',
                    'Submitted', 'Changes required', 'Complete'
                )
            );
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS resources_compliance_phase_048_idx
    ON public.resources(compliance_phase_status, compliance_requested_at DESC)
    WHERE resource_type IN ('Freelancer', 'Company');

CREATE OR REPLACE FUNCTION public.resource_has_successful_general_test_048(
    p_resource_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.resource_tests test
        WHERE test.resource_id = p_resource_id
          AND test.test_type = 'General'
          AND test.status = 'Completed'
          AND test.test_result = 'Pass'
    ), FALSE);
$$;

REVOKE ALL ON FUNCTION public.resource_has_successful_general_test_048(UUID)
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.resource_compliance_completion_check_048(
    p_resource_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_education public.resource_education%ROWTYPE;
    v_cv_valid BOOLEAN := FALSE;
    v_diploma_valid BOOLEAN := FALSE;
    v_reason TEXT;
BEGIN
    SELECT * INTO v_education
    FROM public.resource_education education
    WHERE education.resource_id = p_resource_id
      AND education.is_highest_relevant
    ORDER BY education.sort_order, education.created_at
    LIMIT 1;

    SELECT EXISTS (
        SELECT 1
        FROM public.resource_documents document
        JOIN public.file_records file ON file.id = document.file_record_id
        WHERE document.resource_id = p_resource_id
          AND document.document_type = 'CV'
          AND document.status = 'Valid'
          AND file.resource_id = p_resource_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.file_role = 'Compliance - CV'
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND file.deleted_at IS NULL
    ) INTO v_cv_valid;

    IF v_education.id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.resource_documents document
            JOIN public.file_records file ON file.id = document.file_record_id
            WHERE document.resource_id = p_resource_id
              AND document.education_id = v_education.id
              AND document.document_type = 'Diploma / certificate'
              AND document.status = 'Valid'
              AND file.resource_id = p_resource_id
              AND file.storage_provider = 'Cloudflare R2'
              AND file.file_role = 'Compliance - Diploma / certificate'
              AND file.upload_status = 'Ready'
              AND file.archived_at IS NULL
              AND file.deleted_at IS NULL
        ) INTO v_diploma_valid;
    END IF;

    IF v_education.id IS NULL THEN
        v_reason := 'Highest relevant education has not been submitted.';
    ELSIF NOT v_education.verified THEN
        v_reason := 'Education evidence still requires internal review.';
    ELSIF v_education.degree_level IS NULL OR v_education.degree_type IS NULL THEN
        v_reason := 'Highest relevant degree and degree type are incomplete.';
    ELSIF v_education.degree_level <> 'No university degree' AND (
        NULLIF(btrim(COALESCE(v_education.institution, '')), '') IS NULL
        OR NULLIF(btrim(COALESCE(v_education.field_of_study, '')), '') IS NULL
        OR NULLIF(btrim(COALESCE(v_education.country, '')), '') IS NULL
        OR v_education.end_year IS NULL
    ) THEN
        v_reason := 'Education details are incomplete.';
    ELSIF v_education.degree_level <> 'No university degree'
          AND NOT v_diploma_valid THEN
        v_reason := 'Diploma/certificate evidence still requires internal review.';
    ELSIF NOT v_cv_valid THEN
        v_reason := 'CV evidence still requires internal review.';
    ELSE
        RETURN jsonb_build_object('complete', TRUE, 'reason', 'All required Compliance evidence is reviewed.');
    END IF;

    RETURN jsonb_build_object('complete', FALSE, 'reason', v_reason);
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_completion_check_048(UUID)
    FROM PUBLIC, anon, authenticated;

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
        'can_request',
            v_resource.compliance_phase_status = 'Not requested'
            AND public.resource_has_successful_general_test_048(p_resource_id),
        'requested_at', v_resource.compliance_requested_at,
        'submitted_at', v_resource.compliance_submitted_at,
        'changes_requested_at', v_resource.compliance_changes_requested_at,
        'change_reason', v_resource.compliance_change_reason,
        'completed_at', v_resource.compliance_completed_at,
        'last_resource_edit_at', v_resource.compliance_last_resource_edit_at,
        'notification_sent_at', v_resource.compliance_notification_sent_at,
        'notification_error', v_resource.compliance_notification_error,
        'completion_check',
            public.resource_compliance_completion_check_048(p_resource_id)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_workflow_summary_048(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_compliance_workflow_summary_048(UUID)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.resource_compliance_workflow_dispatch_048(
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
    v_completion JSONB;
    v_notification_kind TEXT;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    SELECT profile.role INTO v_role
    FROM public.profiles profile WHERE profile.id = p_actor_id;
    IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;

    SELECT * INTO v_resource
    FROM public.resources resource
    WHERE resource.id = p_resource_id
      AND resource.resource_type IN ('Freelancer', 'Company')
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'External Resource not found'; END IF;

    IF v_action IN ('request', 'resend', 'request_changes') THEN
        IF v_resource.profile_id IS NULL
           OR v_resource.portal_status IS DISTINCT FROM 'Active'
           OR NULLIF(btrim(COALESCE(v_resource.email, '')), '') IS NULL THEN
            RAISE EXCEPTION 'Activate the Resource portal before requesting Compliance';
        END IF;
    END IF;

    IF v_action = 'request' THEN
        IF v_resource.compliance_phase_status <> 'Not requested' THEN
            RAISE EXCEPTION 'Compliance has already been requested';
        END IF;
        IF NOT public.resource_has_successful_general_test_048(p_resource_id) THEN
            RAISE EXCEPTION 'A passed General test or pre-TMS General pass is required';
        END IF;
        UPDATE public.resources
        SET compliance_phase_status = 'Requested',
            compliance_requested_at = NOW(),
            compliance_requested_by = p_actor_id,
            compliance_submitted_at = NULL,
            compliance_changes_requested_at = NULL,
            compliance_changes_requested_by = NULL,
            compliance_change_reason = NULL,
            compliance_completed_at = NULL,
            compliance_completed_by = NULL,
            compliance_notification_error = NULL,
            compliance_status = 'Missing',
            updated_at = NOW()
        WHERE id = p_resource_id;
        v_notification_kind := 'compliance_requested';
        PERFORM public.append_trusted_tms_audit_event(
            'Resource', p_resource_id, 'Compliance requested',
            jsonb_build_object('status', v_resource.compliance_phase_status),
            jsonb_build_object('status', 'Requested', 'actor_id', p_actor_id),
            'Prompted Compliance phase opened after a successful General test'
        );
    ELSIF v_action = 'request_changes' THEN
        IF v_resource.compliance_phase_status NOT IN ('Submitted', 'Complete') THEN
            RAISE EXCEPTION 'Changes can be requested only after submission';
        END IF;
        IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
            RAISE EXCEPTION 'Explain which Compliance changes are required';
        END IF;
        UPDATE public.resources
        SET compliance_phase_status = 'Changes required',
            compliance_changes_requested_at = NOW(),
            compliance_changes_requested_by = p_actor_id,
            compliance_change_reason = left(btrim(p_reason), 2000),
            compliance_completed_at = NULL,
            compliance_completed_by = NULL,
            compliance_notification_error = NULL,
            compliance_status = 'Missing',
            updated_at = NOW()
        WHERE id = p_resource_id;
        v_notification_kind := 'changes_required';
        PERFORM public.append_trusted_tms_audit_event(
            'Resource', p_resource_id, 'Compliance changes requested',
            jsonb_build_object('status', v_resource.compliance_phase_status),
            jsonb_build_object('status', 'Changes required', 'actor_id', p_actor_id),
            left(btrim(p_reason), 2000)
        );
    ELSIF v_action = 'complete' THEN
        IF v_resource.compliance_phase_status <> 'Submitted' THEN
            RAISE EXCEPTION 'Only submitted Compliance evidence can be completed';
        END IF;
        v_completion := public.resource_compliance_completion_check_048(p_resource_id);
        IF NOT COALESCE((v_completion->>'complete')::BOOLEAN, FALSE) THEN
            RAISE EXCEPTION '%', v_completion->>'reason';
        END IF;
        UPDATE public.resources
        SET compliance_phase_status = 'Complete',
            compliance_completed_at = NOW(),
            compliance_completed_by = p_actor_id,
            compliance_change_reason = NULL,
            compliance_notification_error = NULL,
            compliance_status = 'Valid',
            updated_at = NOW()
        WHERE id = p_resource_id;
        PERFORM public.append_trusted_tms_audit_event(
            'Resource', p_resource_id, 'Compliance completed',
            jsonb_build_object('status', v_resource.compliance_phase_status),
            jsonb_build_object('status', 'Complete', 'actor_id', p_actor_id),
            'Required Compliance evidence was reviewed internally'
        );
    ELSIF v_action = 'resend' THEN
        IF v_resource.compliance_phase_status = 'Not requested' THEN
            RAISE EXCEPTION 'Compliance has not been requested';
        END IF;
        v_notification_kind := CASE
            WHEN v_resource.compliance_phase_status = 'Changes required'
                THEN 'changes_required'
            ELSE 'compliance_requested' END;
    ELSIF v_action = 'notification_sent' THEN
        UPDATE public.resources
        SET compliance_notification_sent_at = NOW(),
            compliance_notification_error = NULL,
            updated_at = NOW()
        WHERE id = p_resource_id;
    ELSIF v_action = 'notification_failed' THEN
        UPDATE public.resources
        SET compliance_notification_error = left(COALESCE(
                NULLIF(btrim(p_reason), ''), 'Notification delivery failed'
            ), 500),
            updated_at = NOW()
        WHERE id = p_resource_id;
    ELSE
        RAISE EXCEPTION 'Unsupported Compliance workflow action';
    END IF;

    SELECT * INTO v_resource FROM public.resources WHERE id = p_resource_id;
    RETURN jsonb_build_object(
        'resource_id', v_resource.id,
        'email', v_resource.email,
        'name', COALESCE(
            NULLIF(btrim(v_resource.legal_name), ''),
            NULLIF(btrim(v_resource.company_name), ''),
            v_resource.internal_number
        ),
        'status', v_resource.compliance_phase_status,
        'change_reason', v_resource.compliance_change_reason,
        'notification_kind', v_notification_kind
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_workflow_dispatch_048(
    TEXT, UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_compliance_workflow_dispatch_048(
    TEXT, UUID, UUID, TEXT
) TO service_role;

-- -------------------------------------------------------------------------
-- Resource-portal projection and writes. It exposes only the caller's own
-- Compliance task and never calls or returns the internal ISO projection.
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_portal_compliance_048()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_resource public.resources%ROWTYPE;
    v_education public.resource_education%ROWTYPE;
    v_visible BOOLEAN;
    v_editable BOOLEAN;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    SELECT * INTO v_resource FROM public.resources WHERE id = v_resource_id;
    v_visible := v_resource.compliance_phase_status <> 'Not requested';
    v_editable := v_resource.portal_status = 'Active'
        AND v_resource.compliance_phase_status IN (
            'Requested', 'In progress', 'Changes required'
        );

    IF NOT v_visible THEN
        RETURN jsonb_build_object(
            'visible', FALSE,
            'editable', FALSE,
            'status', v_resource.compliance_phase_status,
            'documents', '[]'::JSONB
        );
    END IF;

    SELECT * INTO v_education
    FROM public.resource_education education
    WHERE education.resource_id = v_resource_id
      AND education.is_highest_relevant
    ORDER BY education.sort_order, education.created_at
    LIMIT 1;

    RETURN jsonb_build_object(
        'visible', TRUE,
        'editable', v_editable,
        'resource_id', v_resource_id,
        'status', v_resource.compliance_phase_status,
        'requested_at', v_resource.compliance_requested_at,
        'submitted_at', v_resource.compliance_submitted_at,
        'completed_at', v_resource.compliance_completed_at,
        'change_reason', v_resource.compliance_change_reason,
        'professional_since', jsonb_build_object(
            'translation', v_resource.translation_professional_since,
            'revision', v_resource.revision_professional_since,
            'mtpe', v_resource.mtpe_professional_since
        ),
        'professional_experience', jsonb_build_object(
            'translation', public.professional_experience_duration_047(
                v_resource.translation_professional_since, CURRENT_DATE
            ),
            'revision', public.professional_experience_duration_047(
                v_resource.revision_professional_since, CURRENT_DATE
            ),
            'mtpe', public.professional_experience_duration_047(
                v_resource.mtpe_professional_since, CURRENT_DATE
            )
        ),
        'education', CASE WHEN v_education.id IS NULL THEN NULL ELSE
            jsonb_build_object(
                'id', v_education.id,
                'degree_level', v_education.degree_level,
                'legacy_degree', CASE WHEN v_education.degree_level IS NULL
                    THEN v_education.degree ELSE NULL END,
                'degree_type', v_education.degree_type,
                'field_of_study_category', v_education.field_of_study_category,
                'field_of_study_other', v_education.field_of_study_other,
                'legacy_field_of_study',
                    CASE WHEN v_education.field_of_study_category IS NULL
                         THEN v_education.field_of_study ELSE NULL END,
                'institution', v_education.institution,
                'country', v_education.country,
                'graduation_year', v_education.end_year,
                'review_status', CASE WHEN v_education.verified
                    THEN 'Reviewed' ELSE 'Pending review' END
            ) END,
        'documents', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'document_id', document.id,
                'file_id', file.id,
                'evidence_type', document.document_type,
                'education_id', document.education_id,
                'filename', file.original_filename,
                'size_bytes', file.size_bytes,
                'uploaded_at', file.created_at,
                'review_status', document.status
            ) ORDER BY file.created_at DESC)
            FROM public.resource_documents document
            JOIN public.file_records file ON file.id = document.file_record_id
            WHERE document.resource_id = v_resource_id
              AND document.document_type IN ('CV', 'Diploma / certificate')
              AND document.status IN ('Pending', 'Valid')
              AND file.resource_id = v_resource_id
              AND file.storage_provider = 'Cloudflare R2'
              AND file.upload_status = 'Ready'
              AND file.archived_at IS NULL
              AND file.deleted_at IS NULL
        ), '[]'::JSONB)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_compliance_048()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_compliance_048()
    TO authenticated;

CREATE OR REPLACE FUNCTION public.resource_portal_save_compliance_048(
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
    v_education_id UUID;
    v_translation DATE := NULLIF(p_payload->>'translation_professional_since', '')::DATE;
    v_revision DATE := NULLIF(p_payload->>'revision_professional_since', '')::DATE;
    v_mtpe DATE := NULLIF(p_payload->>'mtpe_professional_since', '')::DATE;
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
        RAISE EXCEPTION 'Compliance evidence is currently read-only';
    END IF;

    SELECT education.id INTO v_education_id
    FROM public.resource_education education
    WHERE education.resource_id = v_resource_id
      AND education.is_highest_relevant
    ORDER BY education.sort_order, education.created_at
    LIMIT 1;

    v_education_id := public.apply_resource_education_048(
        v_resource_id,
        v_education_id,
        COALESCE(p_payload->'education', '{}'::JSONB)
            || jsonb_build_object('is_highest_relevant', TRUE),
        FALSE,
        'External Resource Compliance submission edit'
    );

    UPDATE public.resources
    SET translation_professional_since = v_translation,
        revision_professional_since = v_revision,
        mtpe_professional_since = v_mtpe,
        compliance_phase_status = 'In progress',
        compliance_last_resource_edit_at = NOW(),
        compliance_notification_error = NULL,
        updated_at = NOW()
    WHERE id = v_resource_id;

    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_resource_id, 'Compliance progress saved',
        jsonb_build_object('status', v_resource.compliance_phase_status),
        jsonb_build_object(
            'status', 'In progress',
            'education_id', v_education_id,
            'professional_dates_updated', TRUE
        ),
        'External Resource saved prompted Compliance evidence'
    );
    RETURN public.resource_portal_compliance_048();
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_save_compliance_048(JSONB)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_save_compliance_048(JSONB)
    TO authenticated;

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

    IF v_education.id IS NULL
       OR v_education.degree_level IS NULL
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

    UPDATE public.resources
    SET compliance_phase_status = 'Submitted',
        compliance_submitted_at = NOW(),
        compliance_change_reason = NULL,
        updated_at = NOW()
    WHERE id = v_resource_id;
    PERFORM public.append_trusted_tms_audit_event(
        'Resource', v_resource_id, 'Compliance submitted',
        jsonb_build_object('status', v_resource.compliance_phase_status),
        jsonb_build_object('status', 'Submitted'),
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
-- Account qualification evidence derived only from Approved TMS Jobs. Job
-- volume is returned by unit; no supplier rate, amount, currency or EUR value
-- is selected or exposed by this function.
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_account_job_qualifications_048(
    p_resource_id UUID
)
RETURNS TABLE (
    account_id UUID,
    account_name TEXT,
    source_language TEXT,
    target_language TEXT,
    service_type TEXT,
    specialization_id UUID,
    specialization_name TEXT,
    approved_job_count BIGINT,
    last_approved_at TIMESTAMPTZ,
    approved_jobs JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;
    RETURN QUERY
    SELECT
        account.id,
        account.name,
        job.source_language,
        job.target_language,
        job.service_type,
        job.specialization_id,
        specialization.name,
        count(*)::BIGINT,
        max(job.approved_at),
        jsonb_agg(jsonb_build_object(
            'job_id', job.id,
            'job_number', job.job_number,
            'approved_at', job.approved_at,
            'quantity', CASE
                WHEN job.unit = 'Fixed fee' THEN COALESCE(job.quantity, 1)
                ELSE job.quantity END,
            'unit', CASE
                WHEN job.unit = 'Fixed fee' THEN 'Flat rate'
                ELSE job.unit END
        ) ORDER BY job.approved_at DESC NULLS LAST, job.job_number)
    FROM public.project_jobs job
    JOIN public.projects project ON project.id = job.project_id
    JOIN public.client_accounts account ON account.id = project.account_id
    LEFT JOIN public.specializations specialization
        ON specialization.id = job.specialization_id
    WHERE job.resource_id = p_resource_id
      AND job.status = 'Approved'
    GROUP BY
        account.id, account.name,
        job.source_language, job.target_language, job.service_type,
        job.specialization_id, specialization.name
    ORDER BY account.name, job.source_language, job.target_language,
        job.service_type, specialization.name;
END;
$$;

REVOKE ALL ON FUNCTION public.resource_account_job_qualifications_048(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_account_job_qualifications_048(UUID)
    TO authenticated;

-- -------------------------------------------------------------------------
-- Private R2 dispatcher extended to the prompted Resource workflow. The
-- Netlify endpoint supplies the verified Auth user ID; this function resolves
-- its role and exact linked Resource before authorizing any object operation.
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_compliance_file_dispatch_048(
    p_action TEXT,
    p_actor_id UUID,
    p_file_id UUID DEFAULT NULL,
    p_resource_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::JSONB
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
    v_file_id UUID;
    v_document_id UUID;
    v_education_id UUID;
    v_filename TEXT;
    v_safe_filename TEXT;
    v_checksum TEXT;
    v_size BIGINT;
    v_bucket TEXT;
    v_evidence_type TEXT;
    v_object_key TEXT;
    v_action TEXT := lower(btrim(COALESCE(p_action, '')));
    v_download_action TEXT;
    v_failure_reason TEXT;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    IF p_actor_id IS NULL THEN RAISE EXCEPTION 'Verified actor is required'; END IF;

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

    IF v_action = 'prepare_upload' THEN
        IF NOT v_is_operations AND NOT (
            v_role = 'resource'
            AND v_actor_resource_id = p_resource_id
            AND v_actor_portal_status = 'Active'
            AND v_actor_phase_status IN (
                'Requested', 'In progress', 'Changes required'
            )
        ) THEN
            RAISE EXCEPTION 'Compliance evidence upload is not available';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.resources resource
            WHERE resource.id = p_resource_id
              AND resource.resource_type IN ('Freelancer', 'Company')
        ) THEN
            RAISE EXCEPTION 'External Resource not found';
        END IF;

        v_filename := btrim(COALESCE(p_payload->>'original_filename', ''));
        v_checksum := lower(btrim(COALESCE(p_payload->>'checksum_sha256', '')));
        v_size := NULLIF(p_payload->>'size_bytes', '')::BIGINT;
        v_bucket := btrim(COALESCE(p_payload->>'bucket_name', ''));
        v_evidence_type := btrim(COALESCE(p_payload->>'evidence_type', ''));
        v_education_id := NULLIF(p_payload->>'education_id', '')::UUID;

        IF v_filename = '' OR length(v_filename) > 255 THEN
            RAISE EXCEPTION 'A filename between 1 and 255 characters is required';
        END IF;
        IF v_checksum !~ '^[0-9a-f]{64}$' THEN
            RAISE EXCEPTION 'A SHA-256 checksum is required';
        END IF;
        IF v_size IS NULL OR v_size < 0 OR v_size > 5363466240 THEN
            RAISE EXCEPTION 'File size exceeds the supported R2 single-upload limit';
        END IF;
        IF v_bucket = '' OR length(v_bucket) > 128 THEN
            RAISE EXCEPTION 'Private R2 bucket is not configured';
        END IF;
        IF v_evidence_type NOT IN ('Diploma / certificate', 'CV') THEN
            RAISE EXCEPTION 'Unsupported Compliance evidence type';
        END IF;
        IF v_evidence_type = 'Diploma / certificate' THEN
            IF v_education_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM public.resource_education education
                WHERE education.id = v_education_id
                  AND education.resource_id = p_resource_id
                  AND education.is_highest_relevant
                  AND education.degree_level IS DISTINCT FROM 'No university degree'
            ) THEN
                RAISE EXCEPTION 'A matching highest education record is required for diploma evidence';
            END IF;
        ELSE
            v_education_id := NULL;
        END IF;

        v_file_id := gen_random_uuid();
        v_safe_filename := regexp_replace(v_filename, '[^A-Za-z0-9._-]+', '_', 'g');
        v_safe_filename := regexp_replace(v_safe_filename, '^\.+', '');
        IF v_safe_filename = '' THEN v_safe_filename := 'file'; END IF;
        v_object_key := format(
            'active/resources/%s/compliance/%s/%s/%s',
            p_resource_id,
            CASE WHEN v_evidence_type = 'CV' THEN 'cv' ELSE 'education' END,
            v_file_id,
            v_safe_filename
        );

        INSERT INTO public.file_records (
            id, project_id, job_id, resource_id, storage_provider,
            bucket_name, object_key, original_filename, mime_type,
            size_bytes, file_role, checksum_sha256, retention_until,
            archived_at, uploaded_by, upload_status, storage_class
        ) VALUES (
            v_file_id, NULL, NULL, p_resource_id, 'Cloudflare R2',
            v_bucket, v_object_key, v_filename,
            NULLIF(btrim(COALESCE(p_payload->>'mime_type', '')), ''),
            v_size, 'Compliance - ' || v_evidence_type, v_checksum, NULL,
            NOW(), p_actor_id, 'Pending', 'STANDARD'
        );

        INSERT INTO public.resource_documents (
            resource_id, education_id, document_type, file_record_id,
            status, reviewed_by, notes
        ) VALUES (
            p_resource_id, v_education_id, v_evidence_type, v_file_id,
            'Pending', NULL, 'Private R2 upload pending verification'
        ) RETURNING id INTO v_document_id;

        RETURN jsonb_build_object(
            'file_id', v_file_id,
            'document_id', v_document_id,
            'object_key', v_object_key,
            'checksum_sha256', v_checksum,
            'mime_type', COALESCE(
                NULLIF(btrim(p_payload->>'mime_type'), ''),
                'application/octet-stream'
            )
        );
    END IF;

    IF v_action IN ('inspect_upload', 'publish_upload', 'fail_upload', 'discard_upload') THEN
        SELECT file.* INTO v_file
        FROM public.file_records file
        WHERE file.id = p_file_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.job_id IS NULL
          AND file.file_role IN (
              'Compliance - Diploma / certificate', 'Compliance - CV'
          )
          AND file.upload_status = 'Pending'
        FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Pending Compliance file not found'; END IF;

        IF NOT v_is_operations AND NOT (
            v_role = 'resource'
            AND v_actor_resource_id = v_file.resource_id
            AND v_actor_portal_status = 'Active'
            AND v_actor_phase_status IN (
                'Requested', 'In progress', 'Changes required'
            )
        ) THEN
            RAISE EXCEPTION 'Pending Compliance file not found';
        END IF;

        SELECT * INTO v_document
        FROM public.resource_documents document
        WHERE document.file_record_id = v_file.id
          AND document.resource_id = v_file.resource_id
        FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Compliance evidence link not found'; END IF;

        IF v_action = 'inspect_upload' THEN
            RETURN jsonb_build_object(
                'file_id', v_file.id,
                'object_key', v_file.object_key,
                'size_bytes', v_file.size_bytes,
                'checksum_sha256', v_file.checksum_sha256
            );
        ELSIF v_action = 'publish_upload' THEN
            IF NULLIF(p_payload->>'verified_size_bytes', '')::BIGINT
                    IS DISTINCT FROM v_file.size_bytes
               OR lower(COALESCE(p_payload->>'verified_checksum_sha256', ''))
                    IS DISTINCT FROM lower(COALESCE(v_file.checksum_sha256, '')) THEN
                RAISE EXCEPTION 'R2 upload verification does not match the file record';
            END IF;
            UPDATE public.file_records
            SET upload_status = 'Ready', archived_at = NULL,
                verified_at = NOW(), storage_error = NULL,
                r2_etag = NULLIF(p_payload->>'r2_etag', ''),
                r2_version_id = NULLIF(p_payload->>'r2_version_id', ''),
                storage_class = COALESCE(
                    NULLIF(p_payload->>'storage_class', ''), 'STANDARD'
                )
            WHERE id = v_file.id;
            UPDATE public.resource_documents
            SET status = 'Pending', reviewed_by = NULL,
                reviewed_at = NULL,
                notes = 'R2 upload verified; evidence review required'
            WHERE id = v_document.id;
            IF v_role = 'resource' THEN
                UPDATE public.resources
                SET compliance_phase_status = 'In progress',
                    compliance_last_resource_edit_at = NOW(),
                    updated_at = NOW()
                WHERE id = v_file.resource_id
                  AND compliance_phase_status IN ('Requested', 'Changes required');
            END IF;
            INSERT INTO public.file_access_logs(
                file_record_id, profile_id, resource_id, action
            ) VALUES (v_file.id, p_actor_id, v_file.resource_id, 'Upload');
            PERFORM public.append_trusted_tms_audit_event(
                'Resource', v_file.resource_id,
                'Compliance evidence published', NULL,
                jsonb_build_object(
                    'document_id', v_document.id,
                    'file_id', v_file.id,
                    'evidence_type', v_document.document_type,
                    'education_id', v_document.education_id,
                    'uploaded_by_profile_id', p_actor_id
                ),
                'Private R2 object passed size and checksum verification'
            );
            RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Ready');
        ELSE
            v_failure_reason := left(COALESCE(
                NULLIF(p_payload->>'reason', ''),
                'Pending Compliance upload discarded'
            ), 500);
            UPDATE public.file_records
            SET upload_status = 'Failed', archived_at = COALESCE(archived_at, NOW()),
                storage_error = v_failure_reason
            WHERE id = v_file.id;
            UPDATE public.resource_documents
            SET status = 'Rejected', reviewed_by = NULL,
                reviewed_at = NOW(), notes = v_failure_reason
            WHERE id = v_document.id;
            RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Failed');
        END IF;
    END IF;

    IF v_action = 'review_evidence' THEN
        IF NOT v_is_operations THEN
            RAISE EXCEPTION 'Operational access required';
        END IF;
        SELECT file.* INTO v_file
        FROM public.file_records file
        WHERE file.id = p_file_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.job_id IS NULL
          AND file.file_role IN (
              'Compliance - Diploma / certificate', 'Compliance - CV'
          )
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND file.deleted_at IS NULL;
        IF NOT FOUND THEN RAISE EXCEPTION 'Compliance file not found'; END IF;

        SELECT * INTO v_document FROM public.resource_documents document
        WHERE document.file_record_id = v_file.id
          AND document.resource_id = v_file.resource_id
        FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Compliance evidence link not found'; END IF;

        UPDATE public.resource_documents
        SET status = 'Valid', reviewed_by = p_actor_id,
            reviewed_at = NOW(), notes = NULL
        WHERE id = v_document.id;
        PERFORM public.append_trusted_tms_audit_event(
            'Resource', v_file.resource_id,
            'Compliance evidence reviewed', to_jsonb(v_document),
            jsonb_build_object(
                'document_id', v_document.id,
                'file_id', v_file.id,
                'reviewed_by_profile_id', p_actor_id
            ),
            'Operational reviewer confirmed the uploaded evidence'
        );
        RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Valid');
    END IF;

    IF v_action = 'authorize_download' THEN
        SELECT file.* INTO v_file
        FROM public.file_records file
        WHERE file.id = p_file_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.job_id IS NULL
          AND file.file_role IN (
              'Compliance - Diploma / certificate', 'Compliance - CV'
          )
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND file.deleted_at IS NULL;
        IF NOT FOUND THEN RAISE EXCEPTION 'Compliance file not found'; END IF;

        IF v_role IN ('admin', 'pm', 'qa', 'client_relations') THEN
            NULL;
        ELSIF NOT (
            v_role = 'resource'
            AND v_actor_resource_id = v_file.resource_id
            AND v_actor_phase_status <> 'Not requested'
        ) THEN
            RAISE EXCEPTION 'Compliance file not found';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.resource_documents document
            WHERE document.file_record_id = v_file.id
              AND document.resource_id = v_file.resource_id
              AND document.status IN ('Pending', 'Valid')
        ) THEN
            RAISE EXCEPTION 'Compliance file not found';
        END IF;

        v_download_action := CASE
            WHEN p_payload->>'file_action' = 'Download' THEN 'Download'
            ELSE 'View' END;
        INSERT INTO public.file_access_logs(
            file_record_id, profile_id, resource_id, action
        ) VALUES (
            v_file.id, p_actor_id, v_file.resource_id, v_download_action
        );
        RETURN jsonb_build_object(
            'file_id', v_file.id,
            'storage_provider', v_file.storage_provider,
            'bucket_name', v_file.bucket_name,
            'object_key', v_file.object_key,
            'original_filename', v_file.original_filename,
            'mime_type', v_file.mime_type
        );
    END IF;

    RAISE EXCEPTION 'Unsupported Compliance file action';
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_file_dispatch_048(
    TEXT, UUID, UUID, UUID, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_compliance_file_dispatch_048(
    TEXT, UUID, UUID, UUID, JSONB
) TO service_role;

-- Blind CV keeps the same anonymisation boundary while showing the controlled
-- degree label and graduation year. ISO and file metadata remain absent.
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
        'professional_experience', jsonb_build_object(
            'translation', public.professional_experience_duration_047(
                r.translation_professional_since, CURRENT_DATE
            ),
            'revision', public.professional_experience_duration_047(
                r.revision_professional_since, CURRENT_DATE
            ),
            'mtpe', public.professional_experience_duration_047(
                r.mtpe_professional_since, CURRENT_DATE
            )
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
                'institution', education.institution,
                'degree', COALESCE(education.degree_level, education.degree),
                'degree_type', education.degree_type,
                'field_of_study', COALESCE(
                    education.field_of_study_other,
                    education.field_of_study_category,
                    education.field_of_study
                ),
                'country', education.country,
                'start_year', education.start_year,
                'end_year', education.end_year,
                'verified', education.verified,
                'is_highest_relevant', education.is_highest_relevant
            ) ORDER BY
                education.is_highest_relevant DESC,
                education.sort_order,
                education.end_year DESC NULLS LAST)
            FROM public.resource_education education
            WHERE education.resource_id = r.id
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
            ) ORDER BY history.project_year DESC,
                       history.period_end DESC NULLS LAST)
            FROM public.resource_project_history history
            LEFT JOIN public.specializations spec
                ON spec.id = history.specialization_id
            WHERE history.resource_id = r.id AND history.include_in_blind_cv
        ), '[]'::JSONB)
    ) INTO v_result FROM public.resources r WHERE r.id = p_resource_id;
    IF v_result IS NULL THEN RAISE EXCEPTION 'Resource not found'; END IF;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_blind_cv_data(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_blind_cv_data(UUID) TO authenticated;

COMMENT ON COLUMN public.resource_tests.test_result IS
    'Pass/Fail outcome, separate from Assigned/In review/Completed/Cancelled workflow status.';
COMMENT ON COLUMN public.resource_tests.tested_before_tms IS
    'Legacy pass recorded without a fabricated assigned or completed date.';
COMMENT ON COLUMN public.resources.compliance_phase_status IS
    'Prompted evidence workflow only; it does not gate Job assignment.';
COMMENT ON FUNCTION public.resource_account_job_qualifications_048(UUID) IS
    'Internal Approved-Job evidence grouped by Account/capability; exposes operational quantity/unit only and no financial value.';

COMMIT;
