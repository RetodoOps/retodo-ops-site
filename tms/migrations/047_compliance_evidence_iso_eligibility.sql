-- RetodoOps TMS — Update 048 / Compliance evidence and internal ISO eligibility
-- Forward-only migration. Previously applied migrations remain immutable.
--
-- Professional start months are the sole experience source of truth. Durations
-- and ISO eligibility are derived at read time. Compliance binaries remain in
-- private Cloudflare R2 while Supabase stores protected metadata and audit data.

BEGIN;

SET LOCAL check_function_bodies = off;

DO $$
BEGIN
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.resource_education') IS NULL
       OR to_regclass('public.resource_documents') IS NULL
       OR to_regclass('public.file_records') IS NULL
       OR to_regclass('public.file_access_logs') IS NULL
       OR to_regprocedure('public.can_manage_operations()') IS NULL
       OR to_regprocedure('public.is_company_user()') IS NULL
       OR to_regprocedure('public.get_blind_cv_data(uuid)') IS NULL
       OR to_regprocedure('public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text)') IS NULL
       OR to_regprocedure('auth.role()') IS NULL THEN
        RAISE EXCEPTION
            'Migration 047 requires the operational core and migrations 036–046';
    END IF;
END;
$$;

-- -------------------------------------------------------------------------
-- Evidence fields and month-granular professional start dates
-- -------------------------------------------------------------------------

ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS translation_professional_since DATE,
    ADD COLUMN IF NOT EXISTS revision_professional_since DATE,
    ADD COLUMN IF NOT EXISTS mtpe_professional_since DATE;

ALTER TABLE public.resource_education
    ADD COLUMN IF NOT EXISTS degree_type TEXT,
    ADD COLUMN IF NOT EXISTS country TEXT,
    ADD COLUMN IF NOT EXISTS graduation_date DATE,
    ADD COLUMN IF NOT EXISTS is_highest_relevant BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_education'::regclass
          AND conname = 'resource_education_degree_type_check'
    ) THEN
        ALTER TABLE public.resource_education
            ADD CONSTRAINT resource_education_degree_type_check CHECK (
                degree_type IS NULL OR degree_type IN (
                    'Translation / language degree',
                    'Other university degree',
                    'No university degree'
                )
            );
    END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS resource_education_one_highest_relevant_idx
    ON public.resource_education(resource_id)
    WHERE is_highest_relevant;

ALTER TABLE public.resource_documents
    ADD COLUMN IF NOT EXISTS education_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.resource_documents'::regclass
          AND conname = 'resource_documents_education_id_fkey'
    ) THEN
        ALTER TABLE public.resource_documents
            ADD CONSTRAINT resource_documents_education_id_fkey
            FOREIGN KEY (education_id)
            REFERENCES public.resource_education(id) ON DELETE SET NULL;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS resource_documents_compliance_evidence_idx
    ON public.resource_documents(resource_id, document_type, status, created_at DESC);
CREATE INDEX IF NOT EXISTS file_records_resource_compliance_idx
    ON public.file_records(resource_id, upload_status, created_at DESC)
    WHERE job_id IS NULL AND storage_provider = 'Cloudflare R2';

-- A browser session may read company-authorized metadata, but it may not
-- manufacture a Ready Compliance object or reassign its immutable R2 identity.
CREATE OR REPLACE FUNCTION public.guard_resource_compliance_file_047()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.file_role IN (
            'Compliance - CV', 'Compliance - Diploma / certificate'
        ) AND auth.role() IS DISTINCT FROM 'service_role' THEN
            RAISE EXCEPTION 'Compliance file changes require the server';
        END IF;
        RETURN OLD;
    END IF;
    IF (NEW.file_role IN (
            'Compliance - CV', 'Compliance - Diploma / certificate'
        ) OR (TG_OP = 'UPDATE' AND OLD.file_role IN (
            'Compliance - CV', 'Compliance - Diploma / certificate'
        ))) AND auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Compliance file changes require the server';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS file_records_guard_resource_compliance_047
    ON public.file_records;
CREATE TRIGGER file_records_guard_resource_compliance_047
BEFORE INSERT OR UPDATE OR DELETE ON public.file_records
FOR EACH ROW EXECUTE FUNCTION public.guard_resource_compliance_file_047();

-- The education association is part of the record, not a filename convention.
-- Other legacy document types and their workflows are left untouched.
CREATE OR REPLACE FUNCTION public.guard_resource_compliance_document_047()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_file public.file_records%ROWTYPE;
    v_old_is_compliance BOOLEAN := FALSE;
    v_new_is_compliance BOOLEAN := FALSE;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.file_record_id IS NOT NULL THEN
        SELECT file.file_role IN (
            'Compliance - CV', 'Compliance - Diploma / certificate'
        ) INTO v_old_is_compliance
        FROM public.file_records file WHERE file.id = OLD.file_record_id;
        v_old_is_compliance := COALESCE(v_old_is_compliance, FALSE);
    END IF;
    IF NEW.file_record_id IS NOT NULL THEN
        SELECT * INTO v_file FROM public.file_records
        WHERE id = NEW.file_record_id;
        v_new_is_compliance := FOUND AND v_file.file_role IN (
            'Compliance - CV', 'Compliance - Diploma / certificate'
        );
    END IF;
    IF NOT v_old_is_compliance AND NOT v_new_is_compliance THEN
        RETURN NEW;
    END IF;
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Compliance evidence changes require the server';
    END IF;
    IF NOT v_new_is_compliance
       OR NEW.document_type NOT IN ('CV', 'Diploma / certificate')
       OR v_file.resource_id IS DISTINCT FROM NEW.resource_id
       OR v_file.job_id IS NOT NULL
       OR v_file.file_role IS DISTINCT FROM
            'Compliance - ' || NEW.document_type THEN
        RAISE EXCEPTION 'Compliance evidence must belong to this Resource';
    END IF;
    IF NEW.document_type = 'Diploma / certificate' AND (
        NEW.education_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.resource_education education
            WHERE education.id = NEW.education_id
              AND education.resource_id = NEW.resource_id
        )
    ) THEN
        RAISE EXCEPTION 'Diploma evidence must match this education record';
    END IF;
    IF NEW.document_type = 'CV' AND NEW.education_id IS NOT NULL THEN
        RAISE EXCEPTION 'CV evidence cannot be attached to an education record';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_documents_guard_compliance_047
    ON public.resource_documents;
CREATE TRIGGER resource_documents_guard_compliance_047
BEFORE INSERT OR UPDATE OF resource_id, education_id, document_type, file_record_id,
    status, reviewed_at, reviewed_by
ON public.resource_documents
FOR EACH ROW EXECUTE FUNCTION public.guard_resource_compliance_document_047();

CREATE OR REPLACE FUNCTION public.normalize_resource_professional_since_047()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_current_month DATE := date_trunc('month', CURRENT_DATE)::DATE;
BEGIN
    IF NEW.translation_professional_since IS NOT NULL THEN
        NEW.translation_professional_since :=
            date_trunc('month', NEW.translation_professional_since)::DATE;
        IF NEW.translation_professional_since > v_current_month THEN
            RAISE EXCEPTION 'Translation professional since cannot be in the future';
        END IF;
    END IF;
    IF NEW.revision_professional_since IS NOT NULL THEN
        NEW.revision_professional_since :=
            date_trunc('month', NEW.revision_professional_since)::DATE;
        IF NEW.revision_professional_since > v_current_month THEN
            RAISE EXCEPTION 'Revision professional since cannot be in the future';
        END IF;
    END IF;
    IF NEW.mtpe_professional_since IS NOT NULL THEN
        NEW.mtpe_professional_since :=
            date_trunc('month', NEW.mtpe_professional_since)::DATE;
        IF NEW.mtpe_professional_since > v_current_month THEN
            RAISE EXCEPTION 'MTPE professional since cannot be in the future';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resources_normalize_professional_since_047
    ON public.resources;
CREATE TRIGGER resources_normalize_professional_since_047
BEFORE INSERT OR UPDATE OF
    translation_professional_since,
    revision_professional_since,
    mtpe_professional_since
ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.normalize_resource_professional_since_047();

-- Deterministic helper used by the live views and by month-boundary tests.
-- The start date is canonicalized to its month, so no partial-day values exist.
CREATE OR REPLACE FUNCTION public.professional_experience_duration_047(
    p_start_date DATE,
    p_as_of DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_start DATE;
    v_as_of DATE;
    v_total_months INTEGER;
    v_years INTEGER;
    v_months INTEGER;
BEGIN
    IF p_start_date IS NULL OR p_as_of IS NULL THEN RETURN NULL; END IF;
    v_start := date_trunc('month', p_start_date)::DATE;
    v_as_of := date_trunc('month', p_as_of)::DATE;
    IF v_start > v_as_of THEN RETURN NULL; END IF;

    v_total_months :=
        (extract(YEAR FROM v_as_of)::INTEGER - extract(YEAR FROM v_start)::INTEGER) * 12
        + extract(MONTH FROM v_as_of)::INTEGER
        - extract(MONTH FROM v_start)::INTEGER;
    v_years := v_total_months / 12;
    v_months := v_total_months % 12;

    RETURN jsonb_build_object(
        'start_month', to_char(v_start, 'MM/YYYY'),
        'years', v_years,
        'months', v_months,
        'total_months', v_total_months,
        'display', format(
            '%s %s %s %s',
            v_years, CASE WHEN v_years = 1 THEN 'year' ELSE 'years' END,
            v_months, CASE WHEN v_months = 1 THEN 'month' ELSE 'months' END
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.professional_experience_duration_047(DATE, DATE)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_experience_duration_047(DATE, DATE)
    TO authenticated, service_role;

-- -------------------------------------------------------------------------
-- Protected writes for education and professional start dates
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_resource_education_047(
    p_resource_id UUID,
    p_education_id UUID,
    p_payload JSONB
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
    v_degree_type TEXT := NULLIF(btrim(COALESCE(p_payload->>'degree_type', '')), '');
    v_highest BOOLEAN := COALESCE((p_payload->>'is_highest_relevant')::BOOLEAN, FALSE);
    v_verified BOOLEAN := COALESCE((p_payload->>'verified')::BOOLEAN, FALSE);
    v_graduation DATE := NULLIF(p_payload->>'graduation_date', '')::DATE;
    v_end_year INTEGER := NULLIF(p_payload->>'end_year', '')::INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.resources resource
        WHERE resource.id = p_resource_id
          AND resource.resource_type IN ('Freelancer', 'Company')
    ) THEN
        RAISE EXCEPTION 'External Resource not found';
    END IF;
    IF v_degree_type IS NOT NULL AND v_degree_type NOT IN (
        'Translation / language degree',
        'Other university degree',
        'No university degree'
    ) THEN
        RAISE EXCEPTION 'Unsupported degree type';
    END IF;
    IF v_graduation IS NOT NULL THEN
        v_end_year := extract(YEAR FROM v_graduation)::INTEGER;
    END IF;
    IF v_graduation > CURRENT_DATE OR
       v_end_year > extract(YEAR FROM CURRENT_DATE)::INTEGER THEN
        RAISE EXCEPTION 'Graduation cannot be in the future';
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
            resource_id, institution, degree, degree_type, field_of_study,
            country, graduation_date, end_year, verified,
            is_highest_relevant, sort_order
        ) VALUES (
            p_resource_id,
            NULLIF(btrim(COALESCE(p_payload->>'institution', '')), ''),
            NULLIF(btrim(COALESCE(p_payload->>'degree', '')), ''),
            v_degree_type,
            NULLIF(btrim(COALESCE(p_payload->>'field_of_study', '')), ''),
            NULLIF(btrim(COALESCE(p_payload->>'country', '')), ''),
            v_graduation,
            v_end_year,
            v_verified,
            v_highest,
            COALESCE((SELECT max(sort_order) + 1
                      FROM public.resource_education
                      WHERE resource_id = p_resource_id), 0)
        ) RETURNING id INTO v_id;
        v_before := NULL;
    ELSE
        SELECT to_jsonb(education) INTO v_before
        FROM public.resource_education education
        WHERE education.id = p_education_id
          AND education.resource_id = p_resource_id
        FOR UPDATE;
        IF v_before IS NULL THEN RAISE EXCEPTION 'Education record not found'; END IF;

        UPDATE public.resource_education
        SET institution = NULLIF(btrim(COALESCE(p_payload->>'institution', '')), ''),
            degree = NULLIF(btrim(COALESCE(p_payload->>'degree', '')), ''),
            degree_type = v_degree_type,
            field_of_study = NULLIF(btrim(COALESCE(p_payload->>'field_of_study', '')), ''),
            country = NULLIF(btrim(COALESCE(p_payload->>'country', '')), ''),
            graduation_date = v_graduation,
            end_year = v_end_year,
            verified = v_verified,
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
        'Education evidence metadata changed'
    );
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_resource_professional_since_047(
    p_resource_id UUID,
    p_translation_since DATE,
    p_revision_since DATE,
    p_mtpe_since DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_before JSONB;
    v_after JSONB;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;
    SELECT jsonb_build_object(
        'translation_professional_since', translation_professional_since,
        'revision_professional_since', revision_professional_since,
        'mtpe_professional_since', mtpe_professional_since
    ) INTO v_before
    FROM public.resources
    WHERE id = p_resource_id
      AND resource_type IN ('Freelancer', 'Company')
    FOR UPDATE;
    IF v_before IS NULL THEN RAISE EXCEPTION 'External Resource not found'; END IF;

    UPDATE public.resources
    SET translation_professional_since = p_translation_since,
        revision_professional_since = p_revision_since,
        mtpe_professional_since = p_mtpe_since
    WHERE id = p_resource_id;

    SELECT jsonb_build_object(
        'translation_professional_since', translation_professional_since,
        'revision_professional_since', revision_professional_since,
        'mtpe_professional_since', mtpe_professional_since
    ) INTO v_after
    FROM public.resources WHERE id = p_resource_id;

    PERFORM public.append_trusted_tms_audit_event(
        'Resource', p_resource_id, 'Professional experience dates updated',
        v_before, v_after,
        'MM/YYYY professional start dates are the experience source of truth'
    );
    RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.save_resource_education_047(UUID, UUID, JSONB)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_resource_professional_since_047(
    UUID, DATE, DATE, DATE
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_resource_education_047(UUID, UUID, JSONB)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_resource_professional_since_047(
    UUID, DATE, DATE, DATE
) TO authenticated;

-- -------------------------------------------------------------------------
-- Internal-only, live ISO eligibility calculation
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_compliance_summary_047(
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
    v_education public.resource_education%ROWTYPE;
    v_has_education BOOLEAN := FALSE;
    v_education_complete BOOLEAN := FALSE;
    v_has_diploma BOOLEAN := FALSE;
    v_has_cv BOOLEAN := FALSE;
    v_translation JSONB;
    v_revision JSONB;
    v_mtpe JSONB;
    v_translation_months INTEGER;
    v_revision_months INTEGER;
    v_mtpe_months INTEGER;
    v_postedit_months INTEGER;
    v_postedit_display TEXT;
    v_postedit_label TEXT;
    v_translator_eligible BOOLEAN := FALSE;
    v_reviser_eligible BOOLEAN := FALSE;
    v_posteditor_eligible BOOLEAN := FALSE;
    v_translator_reason TEXT;
    v_reviser_reason TEXT;
    v_posteditor_reason TEXT;
    v_translator_route TEXT;
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;

    SELECT * INTO v_resource
    FROM public.resources resource
    WHERE resource.id = p_resource_id
      AND resource.resource_type IN ('Freelancer', 'Company');
    IF NOT FOUND THEN RAISE EXCEPTION 'External Resource not found'; END IF;

    SELECT * INTO v_education
    FROM public.resource_education education
    WHERE education.resource_id = p_resource_id
      AND education.is_highest_relevant
    ORDER BY education.sort_order, education.created_at
    LIMIT 1;
    v_has_education := FOUND;

    IF v_has_education THEN
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
              AND file.job_id IS NULL
              AND file.file_role = 'Compliance - Diploma / certificate'
              AND file.upload_status = 'Ready'
              AND file.archived_at IS NULL
              AND file.deleted_at IS NULL
        ) INTO v_has_diploma;

        v_education_complete := v_education.verified
            AND v_education.degree_type IS NOT NULL
            AND (
                (v_education.degree_type = 'No university degree')
                OR (
                    NULLIF(btrim(COALESCE(v_education.degree, '')), '') IS NOT NULL
                    AND NULLIF(btrim(COALESCE(v_education.field_of_study, '')), '') IS NOT NULL
                    AND NULLIF(btrim(COALESCE(v_education.institution, '')), '') IS NOT NULL
                    AND NULLIF(btrim(COALESCE(v_education.country, '')), '') IS NOT NULL
                    AND COALESCE(
                        v_education.graduation_date,
                        CASE WHEN v_education.end_year IS NOT NULL
                             THEN make_date(v_education.end_year, 1, 1) END
                    ) IS NOT NULL
                    AND v_has_diploma
                )
            );
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.resource_documents document
        JOIN public.file_records file ON file.id = document.file_record_id
        WHERE document.resource_id = p_resource_id
          AND document.document_type = 'CV'
          AND document.status = 'Valid'
          AND file.resource_id = p_resource_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.job_id IS NULL
          AND file.file_role = 'Compliance - CV'
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND file.deleted_at IS NULL
    ) INTO v_has_cv;

    v_translation := public.professional_experience_duration_047(
        v_resource.translation_professional_since, CURRENT_DATE
    );
    v_revision := public.professional_experience_duration_047(
        v_resource.revision_professional_since, CURRENT_DATE
    );
    v_mtpe := public.professional_experience_duration_047(
        v_resource.mtpe_professional_since, CURRENT_DATE
    );
    v_translation_months := NULLIF(v_translation->>'total_months', '')::INTEGER;
    v_revision_months := NULLIF(v_revision->>'total_months', '')::INTEGER;
    v_mtpe_months := NULLIF(v_mtpe->>'total_months', '')::INTEGER;

    -- ISO 17100 Translator: translation/language degree, other degree + 2
    -- years, or explicitly recorded no-degree route + 5 years. Every route
    -- requires reviewed underlying records and a Ready CV evidence file.
    IF NOT v_has_education OR NOT v_education_complete
       OR NOT v_has_cv OR v_translation IS NULL THEN
        v_translator_reason :=
            'Not eligible — Required education/experience evidence is incomplete.';
    ELSIF v_education.degree_type = 'Translation / language degree' THEN
        v_translator_eligible := TRUE;
        v_translator_route := format(
            'Translation / language degree + %s professional translation experience',
            v_translation->>'display'
        );
        v_translator_reason := 'Eligible — ' || v_translator_route || '.';
    ELSIF v_education.degree_type = 'Other university degree'
          AND v_translation_months >= 24 THEN
        v_translator_eligible := TRUE;
        v_translator_route := format(
            'Other university degree + %s professional translation experience',
            v_translation->>'display'
        );
        v_translator_reason := 'Eligible — ' || v_translator_route || '.';
    ELSIF v_education.degree_type = 'No university degree'
          AND v_translation_months >= 60 THEN
        v_translator_eligible := TRUE;
        v_translator_route := format(
            'No university degree + %s documented professional translation experience',
            v_translation->>'display'
        );
        v_translator_reason := 'Eligible — ' || v_translator_route || '.';
    ELSE
        v_translator_reason := format(
            'Not eligible — %s recorded, but only %s professional translation experience documented.',
            v_education.degree_type,
            v_translation->>'display'
        );
    END IF;

    -- ISO 17100 Reviser: the Translator route must already be satisfied and
    -- revision experience must be independently documented from its own date.
    IF NOT v_translator_eligible THEN
        v_reviser_reason := 'Not eligible — ISO 17100 Translator prerequisite: '
            || replace(v_translator_reason, 'Not eligible — ', '');
    ELSIF v_revision IS NULL OR NOT v_has_cv THEN
        v_reviser_reason :=
            'Not eligible — Required professional revision evidence is incomplete.';
    ELSIF v_revision_months < 1 THEN
        v_reviser_reason :=
            'Not eligible — Less than one complete month of professional revision experience is documented.';
    ELSE
        v_reviser_eligible := TRUE;
        v_reviser_reason := format(
            'Eligible — %s + %s professional revision experience.',
            v_translator_route,
            v_revision->>'display'
        );
    END IF;

    -- ISO 18587 Post-editor: the 2/5-year routes may use documented
    -- translation or MTPE experience, whichever is the stronger current route.
    IF v_translation_months IS NULL AND v_mtpe_months IS NULL THEN
        v_postedit_months := NULL;
    ELSIF COALESCE(v_mtpe_months, -1) >= COALESCE(v_translation_months, -1) THEN
        v_postedit_months := v_mtpe_months;
        v_postedit_display := v_mtpe->>'display';
        v_postedit_label := 'professional MTPE experience';
    ELSE
        v_postedit_months := v_translation_months;
        v_postedit_display := v_translation->>'display';
        v_postedit_label := 'professional translation experience';
    END IF;

    IF NOT v_has_education OR NOT v_education_complete
       OR NOT v_has_cv OR v_mtpe IS NULL OR v_postedit_months IS NULL THEN
        v_posteditor_reason :=
            'Not eligible — Required education or documented MTPE/CV evidence is incomplete.';
    ELSIF v_mtpe_months < 1 OR v_postedit_months < 1 THEN
        v_posteditor_reason :=
            'Not eligible — Less than one complete month of professional MTPE experience is documented.';
    ELSIF v_education.degree_type = 'Translation / language degree' THEN
        v_posteditor_eligible := TRUE;
        v_posteditor_reason := format(
            'Eligible — Translation / language degree + %s %s.',
            v_postedit_display, v_postedit_label
        );
    ELSIF v_education.degree_type = 'Other university degree'
          AND v_postedit_months >= 24 THEN
        v_posteditor_eligible := TRUE;
        v_posteditor_reason := format(
            'Eligible — Other university degree + %s %s.',
            v_postedit_display, v_postedit_label
        );
    ELSIF v_education.degree_type = 'No university degree'
          AND v_postedit_months >= 60 THEN
        v_posteditor_eligible := TRUE;
        v_posteditor_reason := format(
            'Eligible — No university degree + %s documented %s.',
            v_postedit_display, v_postedit_label
        );
    ELSE
        v_posteditor_reason := format(
            'Not eligible — %s recorded, but only %s %s documented.',
            v_education.degree_type,
            v_postedit_display,
            v_postedit_label
        );
    END IF;

    RETURN jsonb_build_object(
        'calculated_on', CURRENT_DATE,
        'professional_experience', jsonb_build_object(
            'translation', v_translation,
            'revision', v_revision,
            'mtpe', v_mtpe
        ),
        'evidence', jsonb_build_object(
            'highest_relevant_education_id',
                CASE WHEN v_has_education THEN v_education.id ELSE NULL END,
            'education_complete', v_education_complete,
            'diploma_ready', v_has_diploma,
            'cv_ready', v_has_cv
        ),
        'iso_eligibility', jsonb_build_object(
            'translator', jsonb_build_object(
                'label', 'ISO 17100 Translator',
                'status', CASE WHEN v_translator_eligible
                               THEN 'Eligible' ELSE 'Not eligible' END,
                'eligible', v_translator_eligible,
                'explanation', v_translator_reason
            ),
            'reviser', jsonb_build_object(
                'label', 'ISO 17100 Reviser',
                'status', CASE WHEN v_reviser_eligible
                               THEN 'Eligible' ELSE 'Not eligible' END,
                'eligible', v_reviser_eligible,
                'explanation', v_reviser_reason
            ),
            'post_editor', jsonb_build_object(
                'label', 'ISO 18587 Post-editor',
                'status', CASE WHEN v_posteditor_eligible
                               THEN 'Eligible' ELSE 'Not eligible' END,
                'eligible', v_posteditor_eligible,
                'explanation', v_posteditor_reason
            )
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_compliance_summary_047(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_compliance_summary_047(UUID)
    TO authenticated;

-- -------------------------------------------------------------------------
-- Service-only R2 dispatcher for Compliance evidence
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_compliance_file_dispatch_047(
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

    IF v_action = 'prepare_upload' THEN
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
            RAISE EXCEPTION 'Operational access required';
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
            ) THEN
                RAISE EXCEPTION 'A matching education record is required for diploma evidence';
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
            'Pending', p_actor_id, 'Private R2 upload pending verification'
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
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
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
          AND file.upload_status = 'Pending'
        FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Pending Compliance file not found'; END IF;

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
                    'education_id', v_document.education_id
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
            SET status = 'Rejected', reviewed_by = p_actor_id,
                reviewed_at = NOW(), notes = v_failure_reason
            WHERE id = v_document.id;
            RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Failed');
        END IF;
    END IF;

    IF v_action = 'review_evidence' THEN
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
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
            jsonb_build_object('document_id', v_document.id, 'file_id', v_file.id),
            'Operational reviewer confirmed the uploaded evidence'
        );
        RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Valid');
    END IF;

    IF v_action = 'authorize_download' THEN
        IF v_role NOT IN ('admin', 'pm', 'qa', 'client_relations') THEN
            RAISE EXCEPTION 'Compliance file not found';
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

REVOKE ALL ON FUNCTION public.resource_compliance_file_dispatch_047(
    TEXT, UUID, UUID, UUID, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_compliance_file_dispatch_047(
    TEXT, UUID, UUID, UUID, JSONB
) TO service_role;

-- -------------------------------------------------------------------------
-- Blind CV: add only current calculated durations; ISO decisions remain
-- internal and are deliberately absent from the anonymized output.
-- -------------------------------------------------------------------------

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
                'degree', education.degree,
                'degree_type', education.degree_type,
                'field_of_study', education.field_of_study,
                'country', education.country,
                'graduation_date', education.graduation_date,
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

REVOKE ALL ON FUNCTION public.get_blind_cv_data(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_blind_cv_data(UUID) TO authenticated;

COMMIT;
