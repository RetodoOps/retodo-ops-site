-- RetodoOps TMS — External Resources module
-- Run after 001_operational_foundation.sql and 002_operational_core.sql.

BEGIN;

-- The one-time import runs with the Supabase service role. Interactive users
-- still qualify as Administrator only through their application profile.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT auth.role() = 'service_role'
        OR COALESCE(public.current_app_role() = 'admin', FALSE);
$$;

ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS legacy_id                  TEXT,
    ADD COLUMN IF NOT EXISTS relationship_status        TEXT,
    ADD COLUMN IF NOT EXISTS eligibility_status         TEXT NOT NULL DEFAULT 'Review',
    ADD COLUMN IF NOT EXISTS operational_restrictions   TEXT,
    ADD COLUMN IF NOT EXISTS city                        TEXT,
    ADD COLUMN IF NOT EXISTS linkedin_match_confidence   TEXT,
    ADD COLUMN IF NOT EXISTS linkedin_connection_status TEXT,
    ADD COLUMN IF NOT EXISTS next_action                 TEXT,
    ADD COLUMN IF NOT EXISTS first_recorded_job         DATE,
    ADD COLUMN IF NOT EXISTS last_recorded_job          DATE,
    ADD COLUMN IF NOT EXISTS legacy_status              TEXT,
    ADD COLUMN IF NOT EXISTS education_status           TEXT,
    ADD COLUMN IF NOT EXISTS blind_cv_status            TEXT NOT NULL DEFAULT 'Not ready',
    ADD COLUMN IF NOT EXISTS source_record              TEXT,
    ADD COLUMN IF NOT EXISTS import_batch_id            TEXT;

ALTER TABLE public.resources
    DROP CONSTRAINT IF EXISTS resources_eligibility_status_check,
    DROP CONSTRAINT IF EXISTS resources_blind_cv_status_check,
    DROP CONSTRAINT IF EXISTS resources_linkedin_confidence_check;

ALTER TABLE public.resources
    ADD CONSTRAINT resources_eligibility_status_check CHECK (
        eligibility_status IN ('Eligible', 'Review', 'Restricted', 'Hold', 'Do not use')
    ),
    ADD CONSTRAINT resources_blind_cv_status_check CHECK (
        blind_cv_status IN ('Not ready', 'Review required', 'Ready')
    ),
    ADD CONSTRAINT resources_linkedin_confidence_check CHECK (
        linkedin_match_confidence IS NULL OR linkedin_match_confidence IN (
            'High', 'Medium', 'Low', 'Not researched'
        )
    );

CREATE UNIQUE INDEX IF NOT EXISTS resources_legacy_id_unique_idx
    ON public.resources(legacy_id)
    WHERE legacy_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS resources_eligibility_idx
    ON public.resources(eligibility_status, assignment_approved);

CREATE INDEX IF NOT EXISTS resources_last_job_idx
    ON public.resources(last_recorded_job DESC NULLS LAST);

-- Raw historical notes are deliberately separated from day-to-day operational
-- instructions. Only the Administrator may read this archive.
CREATE TABLE IF NOT EXISTS public.resource_private_notes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id     UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    note_type       TEXT NOT NULL DEFAULT 'Legacy archive' CHECK (
        note_type IN ('Legacy archive', 'Private management note')
    ),
    content         TEXT NOT NULL,
    source_record   TEXT,
    created_by      UUID REFERENCES public.profiles(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.resource_private_notes
    ADD COLUMN IF NOT EXISTS import_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS resource_private_notes_import_key_unique_idx
    ON public.resource_private_notes(import_key)
    WHERE import_key IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'resource_private_notes_import_key_key'
          AND conrelid = 'public.resource_private_notes'::regclass
    ) THEN
        ALTER TABLE public.resource_private_notes
            ADD CONSTRAINT resource_private_notes_import_key_key UNIQUE (import_key);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS resource_private_notes_resource_idx
    ON public.resource_private_notes(resource_id, created_at DESC);

ALTER TABLE public.resource_private_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS resource_private_notes_admin_all
    ON public.resource_private_notes;
CREATE POLICY resource_private_notes_admin_all
ON public.resource_private_notes FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.resource_private_notes TO authenticated;

CREATE OR REPLACE FUNCTION public.stamp_resource_rate_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'Approved'
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
        NEW.approved_by := auth.uid();
        NEW.approved_at := NOW();
    ELSIF NEW.status <> 'Approved'
          AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
        NEW.approved_by := NULL;
        NEW.approved_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_rates_stamp_approval ON public.resource_rates;
CREATE TRIGGER resource_rates_stamp_approval
BEFORE INSERT OR UPDATE OF status ON public.resource_rates
FOR EACH ROW EXECUTE FUNCTION public.stamp_resource_rate_approval();

CREATE OR REPLACE FUNCTION public.notify_priority_resource_unavailable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
BEGIN
    IF NEW.status = 'Unavailable' THEN
        SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
        IF v_resource.priority_resource THEN
            INSERT INTO public.reminders (
                reminder_type, title, body, due_at, resource_id,
                dashboard_enabled, email_enabled, email_recipient
            ) VALUES (
                'Priority Resource unavailable',
                COALESCE(v_resource.internal_number, 'Resource') || ' is unavailable',
                concat_ws(' · ', COALESCE(v_resource.legal_name, v_resource.company_name),
                    NEW.notes, 'From ' || NEW.starts_at::TEXT,
                    CASE WHEN NEW.ends_at IS NOT NULL THEN 'Until ' || NEW.ends_at::TEXT END),
                NOW(), NEW.resource_id, TRUE, TRUE, 'ops@retodo-ops.com'
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resource_availability_priority_notice
    ON public.resource_availability;
CREATE TRIGGER resource_availability_priority_notice
AFTER INSERT ON public.resource_availability
FOR EACH ROW EXECUTE FUNCTION public.notify_priority_resource_unavailable();

CREATE OR REPLACE FUNCTION public.next_resource_internal_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_next INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('retodo:resource-number'));
    SELECT COALESCE(max(
        CASE
            WHEN internal_number ~ '^RO-LNG-[0-9]+$'
            THEN substring(internal_number FROM '([0-9]+)$')::INTEGER
        END
    ), 0) + 1
    INTO v_next
    FROM public.resources;

    RETURN 'RO-LNG-' || lpad(v_next::TEXT, 5, '0');
END;
$$;

REVOKE ALL ON FUNCTION public.next_resource_internal_number() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_resource_internal_number() TO authenticated;

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
        relationship_status, classification, eligibility_status,
        assignment_approved, portal_status, compliance_status,
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
        COALESCE(NULLIF(p_payload->>'relationship_status', ''), 'New contact'),
        'D — Not assessed', 'Review', FALSE, 'Not invited', 'Unknown',
        COALESCE(NULLIF(p_payload->>'payment_terms_days', '')::INTEGER, 60),
        COALESCE(NULLIF(p_payload->>'invoice_cycle', ''), '15th and 30th'),
        auth.uid()
    ) RETURNING id INTO v_id;

    created_resource_id := v_id;
    created_internal_number := v_number;
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_resource(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_resource(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.resource_filter_options()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;

    RETURN jsonb_build_object(
        'source_languages', COALESCE((
            SELECT jsonb_agg(value ORDER BY value)
            FROM (SELECT DISTINCT source_language AS value
                  FROM public.resource_language_pairs
                  WHERE NULLIF(source_language, '') IS NOT NULL) x
        ), '[]'::JSONB),
        'target_languages', COALESCE((
            SELECT jsonb_agg(value ORDER BY value)
            FROM (SELECT DISTINCT target_language AS value
                  FROM public.resource_language_pairs
                  WHERE NULLIF(target_language, '') IS NOT NULL) x
        ), '[]'::JSONB),
        'services', COALESCE((
            SELECT jsonb_agg(value ORDER BY value)
            FROM (SELECT DISTINCT service_type AS value
                  FROM public.resource_services
                  WHERE NULLIF(service_type, '') IS NOT NULL) x
        ), '[]'::JSONB)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_filter_options() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resource_filter_options() TO authenticated;

CREATE OR REPLACE FUNCTION public.search_resources(
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
    classification TEXT,
    eligibility_status TEXT,
    assignment_approved BOOLEAN,
    target_languages TEXT[],
    source_languages TEXT[],
    services TEXT[],
    specializations TEXT[],
    country_of_residence TEXT,
    availability_status TEXT,
    first_recorded_job DATE,
    last_recorded_job DATE,
    linkedin_url TEXT,
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
            ORDER BY a.starts_at DESC
            LIMIT 1
        ) current_availability ON TRUE
        WHERE (p_resource_type IS NULL
               OR (p_resource_type = 'external' AND r.resource_type <> 'Internal')
               OR (p_resource_type = 'internal' AND r.resource_type = 'Internal'))
          AND (NULLIF(btrim(p_search), '') IS NULL OR concat_ws(' ',
                r.internal_number, r.legal_name, r.company_name, r.initials,
                r.email, r.legacy_id
              ) ILIKE '%' || btrim(p_search) || '%')
          AND (p_classification IS NULL OR r.classification = p_classification)
          AND (p_eligibility IS NULL OR r.eligibility_status = p_eligibility)
          AND (p_availability IS NULL
               OR COALESCE(current_availability.status, 'Unknown') = p_availability)
          AND ((p_source_language IS NULL AND p_target_language IS NULL) OR EXISTS (
                SELECT 1 FROM public.resource_language_pairs pair
                WHERE pair.resource_id = r.id
                  AND (p_source_language IS NULL OR pair.source_language = p_source_language)
                  AND (p_target_language IS NULL OR pair.target_language = p_target_language)
                  AND (NOT p_only_approved_capabilities OR pair.approved)
              ))
          AND (p_service_type IS NULL OR EXISTS (
                SELECT 1 FROM public.resource_services service
                WHERE service.resource_id = r.id
                  AND service.service_type = p_service_type
                  AND (NOT p_only_approved_capabilities OR service.approved)
              ))
          AND (p_specialization_id IS NULL OR EXISTS (
                SELECT 1 FROM public.resource_specializations rs
                WHERE rs.resource_id = r.id
                  AND rs.specialization_id = p_specialization_id
                  AND (NOT p_only_approved_capabilities OR rs.approved)
              ))
    )
    SELECT
        f.id, f.internal_number, f.legal_name, f.company_name, f.initials,
        f.resource_type, f.relationship_status, f.classification,
        f.eligibility_status, f.assignment_approved,
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
              WHERE rs.resource_id = f.id ORDER BY 1),
        f.country_of_residence, f.current_availability,
        f.first_recorded_job, f.last_recorded_job, f.linkedin_url,
        count(*) OVER ()
    FROM filtered f
    ORDER BY
        CASE f.classification
            WHEN 'A — Preferred' THEN 1
            WHEN 'B — Proven / previously used' THEN 2
            WHEN 'C — Approved / no recorded work' THEN 3
            WHEN 'D — Not assessed' THEN 4
            WHEN 'Hold — Unavailable' THEN 5
            WHEN 'Hold — Inactive' THEN 6
            WHEN 'Hold — Terms not accepted' THEN 7
            WHEN 'Do not use' THEN 8
            ELSE 9
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
            'internal_number', r.internal_number,
            'initials', r.initials,
            'nationality', r.nationality,
            'country_of_residence', r.country_of_residence,
            'native_language', r.native_language
        ),
        'language_pairs', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'source', pair.source_language,
                'target', pair.target_language,
                'native_target', pair.native_target
            ) ORDER BY pair.target_language, pair.source_language)
            FROM public.resource_language_pairs pair
            WHERE pair.resource_id = r.id AND pair.approved
        ), '[]'::JSONB),
        'services', COALESCE((
            SELECT jsonb_agg(service.service_type ORDER BY service.service_type)
            FROM public.resource_services service
            WHERE service.resource_id = r.id AND service.approved
        ), '[]'::JSONB),
        'specializations', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'name', spec.name,
                'experience_years', rs.experience_years,
                'evidence', rs.evidence
            ) ORDER BY spec.name)
            FROM public.resource_specializations rs
            JOIN public.specializations spec ON spec.id = rs.specialization_id
            WHERE rs.resource_id = r.id AND rs.approved
        ), '[]'::JSONB),
        'education', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'institution', education.institution,
                'degree', education.degree,
                'field_of_study', education.field_of_study,
                'start_year', education.start_year,
                'end_year', education.end_year,
                'verified', education.verified
            ) ORDER BY education.sort_order, education.end_year DESC NULLS LAST)
            FROM public.resource_education education
            WHERE education.resource_id = r.id
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
                'specialization', spec.name,
                'summary', history.project_summary
            ) ORDER BY history.project_year DESC, history.period_end DESC NULLS LAST)
            FROM public.resource_project_history history
            LEFT JOIN public.specializations spec ON spec.id = history.specialization_id
            WHERE history.resource_id = r.id AND history.include_in_blind_cv
        ), '[]'::JSONB)
    )
    INTO v_result
    FROM public.resources r
    WHERE r.id = p_resource_id;

    IF v_result IS NULL THEN RAISE EXCEPTION 'Resource not found'; END IF;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_blind_cv_data(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_blind_cv_data(UUID) TO authenticated;

COMMIT;
