-- RetodoOps TMS — simplified Internal Resources, mandatory Scoop deadlines,
-- daily Project sequencing and Project/Job-connected Supplier PO numbers.
-- Run once after migration 033.

BEGIN;

-- ---------------------------------------------------------------------------
-- Internal Resources: employee identity, multiple operational positions and
-- lifecycle-based access. Historical assignments remain linked to the same row.
-- ---------------------------------------------------------------------------
ALTER TABLE public.resources
    ADD COLUMN IF NOT EXISTS gender TEXT,
    ADD COLUMN IF NOT EXISTS internal_positions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE public.resources
    DROP CONSTRAINT IF EXISTS resources_internal_positions_check;
ALTER TABLE public.resources
    ADD CONSTRAINT resources_internal_positions_check CHECK (
        resource_type <> 'Internal'
        OR internal_positions <@ ARRAY['Project Manager', 'QA', 'Project']::TEXT[]
    );

-- Derive positions only where existing Project assignments or the linked app
-- role provide evidence. Empty arrays remain backward-compatible until edited.
UPDATE public.resources resource
SET internal_positions = ARRAY_REMOVE(ARRAY[
        CASE WHEN EXISTS (
            SELECT 1 FROM public.projects project
            WHERE project.project_manager_resource_id = resource.id
        ) OR EXISTS (
            SELECT 1 FROM public.profiles profile
            WHERE profile.id = resource.profile_id
              AND profile.role IN ('admin', 'pm')
        ) THEN 'Project Manager' END,
        CASE WHEN EXISTS (
            SELECT 1 FROM public.projects project
            WHERE project.qa_specialist_resource_id = resource.id
        ) OR EXISTS (
            SELECT 1 FROM public.profiles profile
            WHERE profile.id = resource.profile_id
              AND profile.role IN ('admin', 'qa')
        ) THEN 'QA' END,
        CASE WHEN EXISTS (
            SELECT 1 FROM public.projects project
            WHERE project.project_coordinator_resource_id = resource.id
        ) OR EXISTS (
            SELECT 1 FROM public.profiles profile
            WHERE profile.id = resource.profile_id
              AND profile.role IN ('admin', 'pm', 'client_relations')
        ) THEN 'Project' END
    ], NULL)::TEXT[],
    updated_at = NOW()
WHERE resource.resource_type = 'Internal'
  AND cardinality(resource.internal_positions) = 0;

CREATE OR REPLACE FUNCTION public.current_user_access_enabled()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = auth.uid()
    ) AND NOT EXISTS (
        SELECT 1
        FROM public.resources resource
        WHERE resource.profile_id = auth.uid()
          AND resource.resource_type = 'Internal'
          AND resource.lifecycle_status = 'Inactive'
    );
$$;

REVOKE ALL ON FUNCTION public.current_user_access_enabled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_access_enabled() TO authenticated;

-- All existing role-dependent RLS and RPC checks now also honour an Internal
-- Resource deactivation. The auth account is retained for audit/history.
CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.resources resource
            WHERE resource.profile_id = auth.uid()
              AND resource.resource_type = 'Internal'
              AND resource.lifecycle_status = 'Inactive'
        ) THEN NULL
        ELSE profile.role
    END
    FROM public.profiles profile
    WHERE profile.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_app_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;

CREATE OR REPLACE FUNCTION public.next_internal_resource_number()
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
    PERFORM pg_advisory_xact_lock(hashtext('retodo:internal-resource-number'));
    SELECT COALESCE(max(
        CASE WHEN internal_number ~ '^RO-INT-[0-9]+$'
            THEN substring(internal_number FROM '([0-9]+)$')::INTEGER END
    ), 0) + 1
    INTO v_next
    FROM public.resources;
    RETURN 'RO-INT-' || lpad(v_next::TEXT, 5, '0');
END;
$$;

REVOKE ALL ON FUNCTION public.next_internal_resource_number() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.internal_positions_from_payload(p_payload JSONB)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
    v_positions TEXT[];
BEGIN
    IF jsonb_typeof(COALESCE(p_payload->'positions', '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Positions must be an array';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT value ORDER BY value), ARRAY[]::TEXT[])
    INTO v_positions
    FROM jsonb_array_elements_text(COALESCE(p_payload->'positions', '[]'::JSONB));

    IF cardinality(v_positions) = 0 THEN
        RAISE EXCEPTION 'Select at least one Internal Resource position';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_positions) position_name
        WHERE position_name NOT IN ('Project Manager', 'QA', 'Project')
    ) THEN
        RAISE EXCEPTION 'Invalid Internal Resource position';
    END IF;
    RETURN v_positions;
END;
$$;

REVOKE ALL ON FUNCTION public.internal_positions_from_payload(JSONB) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.profile_id_for_internal_email(p_email TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT profile.id
    FROM public.profiles profile
    JOIN auth.users app_user ON app_user.id = profile.id
    WHERE lower(app_user.email) = lower(NULLIF(btrim(p_email), ''))
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.profile_id_for_internal_email(TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.create_internal_resource(p_payload JSONB)
RETURNS TABLE (created_resource_id UUID, created_internal_number TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_number TEXT;
    v_name TEXT := NULLIF(btrim(p_payload->>'name'), '');
    v_email TEXT := NULLIF(btrim(p_payload->>'email'), '');
    v_gender TEXT := NULLIF(btrim(p_payload->>'gender'), '');
    v_status TEXT := COALESCE(NULLIF(btrim(p_payload->>'status'), ''), 'Active');
    v_positions TEXT[] := public.internal_positions_from_payload(p_payload);
    v_profile_id UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_name IS NULL OR v_email IS NULL THEN
        RAISE EXCEPTION 'Name and Email are required';
    END IF;
    IF v_status NOT IN ('Active', 'On leave', 'Inactive') THEN
        RAISE EXCEPTION 'Invalid Internal Resource status';
    END IF;

    v_profile_id := public.profile_id_for_internal_email(v_email);
    IF v_profile_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.resources WHERE profile_id = v_profile_id
    ) THEN
        RAISE EXCEPTION 'An Internal Resource is already linked to this TMS user';
    END IF;

    v_number := public.next_internal_resource_number();
    INSERT INTO public.resources (
        internal_number, profile_id, resource_type, lifecycle_status,
        internal_positions, gender, legal_name, initials, email,
        resource_status, portal_status, compliance_status,
        payment_terms_days, invoice_cycle, created_by
    ) VALUES (
        v_number, v_profile_id, 'Internal', v_status,
        v_positions, v_gender, v_name,
        upper(left(split_part(v_name, ' ', 1), 1)
            || left(split_part(v_name, ' ', 2), 1)),
        v_email, 'Preferred',
        CASE WHEN v_profile_id IS NULL THEN 'Not invited' ELSE 'Active' END,
        'Valid', 60, '15th and 30th', auth.uid()
    ) RETURNING id INTO v_id;

    created_resource_id := v_id;
    created_internal_number := v_number;
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_internal_resource(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_internal_resource(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_internal_resource_profile(
    p_resource_id UUID,
    p_payload JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_name TEXT := NULLIF(btrim(p_payload->>'name'), '');
    v_email TEXT := NULLIF(btrim(p_payload->>'email'), '');
    v_gender TEXT := NULLIF(btrim(p_payload->>'gender'), '');
    v_status TEXT := COALESCE(NULLIF(btrim(p_payload->>'status'), ''), 'Active');
    v_positions TEXT[] := public.internal_positions_from_payload(p_payload);
    v_profile_id UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_resource
    FROM public.resources
    WHERE id = p_resource_id
    FOR UPDATE;
    IF NOT FOUND OR v_resource.resource_type <> 'Internal' THEN
        RAISE EXCEPTION 'Internal Resource not found';
    END IF;
    IF v_name IS NULL OR v_email IS NULL THEN
        RAISE EXCEPTION 'Name and Email are required';
    END IF;
    IF v_status NOT IN ('Active', 'On leave', 'Inactive') THEN
        RAISE EXCEPTION 'Invalid Internal Resource status';
    END IF;
    IF v_resource.profile_id = auth.uid() AND v_status = 'Inactive' THEN
        RAISE EXCEPTION 'You cannot deactivate your own active TMS session';
    END IF;

    v_profile_id := COALESCE(
        v_resource.profile_id,
        public.profile_id_for_internal_email(v_email)
    );
    IF v_profile_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.resources other
        WHERE other.profile_id = v_profile_id
          AND other.id <> p_resource_id
    ) THEN
        RAISE EXCEPTION 'Another Resource is already linked to this TMS user';
    END IF;

    UPDATE public.resources
    SET legal_name = v_name,
        initials = upper(left(split_part(v_name, ' ', 1), 1)
            || left(split_part(v_name, ' ', 2), 1)),
        email = v_email,
        gender = v_gender,
        internal_positions = v_positions,
        lifecycle_status = v_status,
        profile_id = v_profile_id,
        portal_status = CASE
            WHEN v_status = 'Inactive' THEN 'Closed'
            WHEN v_profile_id IS NOT NULL THEN 'Active'
            ELSE 'Not invited'
        END,
        updated_at = NOW()
    WHERE id = p_resource_id;

    IF v_profile_id IS NOT NULL THEN
        UPDATE public.profiles
        SET full_name = v_name
        WHERE id = v_profile_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_internal_resource_profile(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_internal_resource_profile(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_project_staff_positions()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
BEGIN
    IF NEW.project_manager_resource_id IS NOT NULL
       AND (TG_OP = 'INSERT'
            OR NEW.project_manager_resource_id IS DISTINCT FROM OLD.project_manager_resource_id) THEN
        SELECT * INTO v_resource FROM public.resources
        WHERE id = NEW.project_manager_resource_id;
        IF NOT FOUND OR v_resource.resource_type <> 'Internal' THEN
            RAISE EXCEPTION 'Project Manager must be an Internal Resource';
        END IF;
        IF v_resource.lifecycle_status <> 'Active' THEN
            RAISE EXCEPTION 'Project Manager must be Active';
        END IF;
        IF cardinality(v_resource.internal_positions) > 0
           AND NOT ('Project Manager' = ANY(v_resource.internal_positions)) THEN
            RAISE EXCEPTION 'Selected employee does not have the Project Manager position';
        END IF;
    END IF;

    IF NEW.qa_specialist_resource_id IS NOT NULL
       AND (TG_OP = 'INSERT'
            OR NEW.qa_specialist_resource_id IS DISTINCT FROM OLD.qa_specialist_resource_id) THEN
        SELECT * INTO v_resource FROM public.resources
        WHERE id = NEW.qa_specialist_resource_id;
        IF NOT FOUND OR v_resource.resource_type <> 'Internal' THEN
            RAISE EXCEPTION 'QA Specialist must be an Internal Resource';
        END IF;
        IF v_resource.lifecycle_status <> 'Active' THEN
            RAISE EXCEPTION 'QA Specialist must be Active';
        END IF;
        IF cardinality(v_resource.internal_positions) > 0
           AND NOT ('QA' = ANY(v_resource.internal_positions)) THEN
            RAISE EXCEPTION 'Selected employee does not have the QA position';
        END IF;
    END IF;

    IF NEW.project_coordinator_resource_id IS NOT NULL
       AND (TG_OP = 'INSERT'
            OR NEW.project_coordinator_resource_id IS DISTINCT FROM OLD.project_coordinator_resource_id) THEN
        SELECT * INTO v_resource FROM public.resources
        WHERE id = NEW.project_coordinator_resource_id;
        IF NOT FOUND OR v_resource.resource_type <> 'Internal' THEN
            RAISE EXCEPTION 'Project coordinator must be an Internal Resource';
        END IF;
        IF v_resource.lifecycle_status <> 'Active' THEN
            RAISE EXCEPTION 'Project coordinator must be Active';
        END IF;
        IF cardinality(v_resource.internal_positions) > 0
           AND NOT ('Project' = ANY(v_resource.internal_positions)) THEN
            RAISE EXCEPTION 'Selected employee does not have the Project position';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_validate_staff_positions ON public.projects;
CREATE TRIGGER projects_validate_staff_positions
BEFORE INSERT OR UPDATE OF project_manager_resource_id,
    qa_specialist_resource_id, project_coordinator_resource_id
ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.validate_project_staff_positions();

-- ---------------------------------------------------------------------------
-- Scoop deadlines are created and maintained at Scoop level only. Manually
-- created Projects no longer auto-create S01 because that would bypass the
-- mandatory Scoop deadline. Quote conversion may retain its dated S01.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS projects_create_initial_scoop ON public.projects;

CREATE OR REPLACE FUNCTION public.require_project_scoop_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.deadline IS NULL THEN
        RAISE EXCEPTION 'Scoop deadline date and time are required';
    END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.deadline IS NOT NULL
       AND NEW.deadline IS NULL THEN
        RAISE EXCEPTION 'Scoop deadline date and time are required';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_scoops_require_deadline ON public.project_scoops;
CREATE TRIGGER project_scoops_require_deadline
BEFORE INSERT OR UPDATE OF deadline ON public.project_scoops
FOR EACH ROW EXECUTE FUNCTION public.require_project_scoop_deadline();

CREATE OR REPLACE FUNCTION public.create_initial_project_scoop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Accepted Quotes already carry a requested deadline and commercial lines.
    -- Keep that conversion atomic; ordinary Project creation proceeds to the
    -- Scoop editor, where date and time are explicitly required.
    IF NEW.quote_id IS NULL OR NEW.deadline IS NULL THEN
        RETURN NEW;
    END IF;
    INSERT INTO public.project_scoops (
        project_id, scoop_number, source_language, target_language,
        deadline, price, created_by
    ) VALUES (
        NEW.id, NEW.project_number || '-S01',
        COALESCE(NULLIF(btrim(NEW.source_language), ''), 'English (UK)'),
        COALESCE(NULLIF(btrim(NEW.target_language), ''), 'Other'),
        NEW.deadline, COALESCE(NEW.price, 0), NEW.created_by
    ) ON CONFLICT (project_id, scoop_number) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE TRIGGER projects_create_initial_scoop
AFTER INSERT ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.create_initial_project_scoop();

CREATE OR REPLACE FUNCTION public.create_project_scoop(
    p_project_id UUID,
    p_payload JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_scoop_id UUID;
    v_sequence INTEGER;
    v_source TEXT := NULLIF(btrim(p_payload->>'source_language'), '');
    v_target TEXT := NULLIF(btrim(p_payload->>'target_language'), '');
    v_deadline TIMESTAMPTZ := NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ;
    v_price NUMERIC := COALESCE(NULLIF(p_payload->>'price', '')::NUMERIC, 0);
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_project
    FROM public.projects
    WHERE id = p_project_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF v_source IS NULL OR v_target IS NULL THEN
        RAISE EXCEPTION 'Source and Target languages are required';
    END IF;
    IF v_source = v_target THEN
        RAISE EXCEPTION 'Source and Target languages must be different';
    END IF;
    IF v_deadline IS NULL THEN
        RAISE EXCEPTION 'Scoop deadline date and time are required';
    END IF;
    IF v_deadline < NOW() THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;
    IF v_price < 0 THEN
        RAISE EXCEPTION 'Scoop price cannot be negative';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_project_id::TEXT || ':scoop'));
    SELECT COALESCE(
        max(NULLIF(substring(scoop_number FROM '-S([0-9]+)$'), '')::INTEGER),
        0
    ) + 1
    INTO v_sequence
    FROM public.project_scoops
    WHERE project_id = p_project_id;

    INSERT INTO public.project_scoops (
        project_id, scoop_number, source_language, target_language,
        deadline, price, created_by
    ) VALUES (
        p_project_id,
        v_project.project_number || '-S' || lpad(v_sequence::TEXT, 2, '0'),
        v_source, v_target, v_deadline, v_price, auth.uid()
    ) RETURNING id INTO v_scoop_id;
    RETURN v_scoop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_scoop(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_scoop(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_project_scoop(
    p_scoop_id UUID,
    p_payload JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payload JSONB := COALESCE(p_payload, '{}'::JSONB);
    v_scoop public.project_scoops%ROWTYPE;
    v_source TEXT;
    v_target TEXT;
    v_deadline TIMESTAMPTZ;
    v_price NUMERIC;
    v_status TEXT := NULLIF(btrim(v_payload->>'status'), '');
    v_status_manual BOOLEAN;
    v_is_primary BOOLEAN;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_scoop
    FROM public.project_scoops
    WHERE id = p_scoop_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Scoop not found'; END IF;

    v_source := COALESCE(NULLIF(btrim(v_payload->>'source_language'), ''), v_scoop.source_language);
    v_target := COALESCE(NULLIF(btrim(v_payload->>'target_language'), ''), v_scoop.target_language);
    v_deadline := CASE WHEN v_payload ? 'deadline'
        THEN NULLIF(v_payload->>'deadline', '')::TIMESTAMPTZ
        ELSE v_scoop.deadline END;
    v_price := COALESCE(NULLIF(v_payload->>'price', '')::NUMERIC, v_scoop.price, 0);

    IF v_payload ? 'status_manual' THEN
        v_status_manual := COALESCE(NULLIF(v_payload->>'status_manual', '')::BOOLEAN, FALSE);
    ELSE
        v_status_manual := COALESCE(v_scoop.status_manual, FALSE);
    END IF;
    IF v_status IS NOT NULL AND NOT (v_payload ? 'status_manual') THEN
        v_status_manual := TRUE;
    END IF;
    IF v_status_manual AND v_status IS NULL THEN
        v_status := COALESCE(v_scoop.status, 'Assign');
    END IF;

    IF v_source IS NULL OR v_target IS NULL THEN
        RAISE EXCEPTION 'Source and Target languages are required';
    END IF;
    IF v_source = v_target THEN
        RAISE EXCEPTION 'Source and Target languages must be different';
    END IF;
    IF (v_payload ? 'deadline') AND v_deadline IS NULL THEN
        RAISE EXCEPTION 'Scoop deadline date and time are required';
    END IF;
    IF v_deadline IS NOT NULL
       AND v_deadline < NOW()
       AND v_deadline IS DISTINCT FROM v_scoop.deadline THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;
    IF v_price < 0 THEN RAISE EXCEPTION 'Scoop price cannot be negative'; END IF;
    IF v_status_manual AND v_status NOT IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting',
        'Ready to Deliver', 'Delivered to Client', 'Approved'
    ) THEN
        RAISE EXCEPTION 'Invalid Scoop status';
    END IF;

    UPDATE public.project_scoops
    SET source_language = v_source,
        target_language = v_target,
        deadline = v_deadline,
        price = v_price,
        status = CASE WHEN v_status_manual THEN v_status ELSE status END,
        status_manual = v_status_manual,
        updated_at = NOW()
    WHERE id = p_scoop_id;

    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs
    SET source_language = v_source,
        target_language = v_target,
        updated_at = NOW()
    WHERE project_scoop_id = p_scoop_id;

    SELECT NOT EXISTS (
        SELECT 1 FROM public.project_scoops earlier
        WHERE earlier.project_id = v_scoop.project_id
          AND (earlier.created_at, earlier.id) < (v_scoop.created_at, v_scoop.id)
    ) INTO v_is_primary;
    IF v_is_primary THEN
        UPDATE public.projects
        SET source_language = v_source,
            source_language_code = public.tms_language_code(v_source),
            target_language = v_target,
            target_language_code = public.tms_language_code(v_target),
            deadline = v_deadline,
            updated_at = NOW()
        WHERE id = v_scoop.project_id;
    END IF;

    IF NOT v_status_manual THEN
        PERFORM public.refresh_project_scoop_status(p_scoop_id);
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_project_scoop(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_project_scoop(UUID, JSONB) TO authenticated;

-- ---------------------------------------------------------------------------
-- New Projects receive a concurrency-safe sequence within their Project date.
-- Existing Project identities are neither renamed nor otherwise modified.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.project_daily_counters (
    project_date DATE PRIMARY KEY,
    last_number INTEGER NOT NULL CHECK (last_number > 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.project_daily_counters(project_date, last_number)
SELECT project.project_date,
       GREATEST(
           count(*)::INTEGER,
           COALESCE(max(CASE
               WHEN project.project_number ~ ('^' || to_char(project.project_date, 'YYMMDD') || '-[0-9]+_')
               THEN substring(project.project_number FROM '^[0-9]{6}-([0-9]+)_')::INTEGER
           END), 0)
       )
FROM public.projects project
WHERE project.project_date IS NOT NULL
GROUP BY project.project_date
ON CONFLICT (project_date) DO UPDATE
SET last_number = GREATEST(
        public.project_daily_counters.last_number,
        EXCLUDED.last_number
    ),
    updated_at = NOW();

CREATE OR REPLACE FUNCTION public.next_project_display_name(
    p_client_id UUID,
    p_target_code TEXT,
    p_client_reference TEXT DEFAULT NULL,
    p_project_date DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_client_code TEXT;
    v_date DATE := COALESCE(p_project_date, CURRENT_DATE);
    v_sequence INTEGER;
    v_base TEXT;
    v_candidate TEXT;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT COALESCE(
        NULLIF(public.safe_code(code, ''), ''),
        left(public.safe_code(name, 'CLIENT'), 8)
    )
    INTO v_client_code
    FROM public.clients
    WHERE id = p_client_id;
    IF v_client_code IS NULL THEN RAISE EXCEPTION 'Client not found'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('retodo:project-day:' || v_date::TEXT));
    INSERT INTO public.project_daily_counters(project_date, last_number)
    VALUES (v_date, 1)
    ON CONFLICT (project_date) DO UPDATE
    SET last_number = public.project_daily_counters.last_number + 1,
        updated_at = NOW()
    RETURNING last_number INTO v_sequence;

    LOOP
        v_base := to_char(v_date, 'YYMMDD') || '-' || v_sequence::TEXT
            || '_' || v_client_code
            || '_' || public.safe_code(p_target_code, 'XX')
            || '_' || CASE
                WHEN NULLIF(btrim(p_client_reference), '') IS NULL THEN 'NOREF'
                ELSE left(public.safe_code(p_client_reference, 'NOREF'), 40)
            END;
        v_candidate := v_base;
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.projects project
            WHERE project.project_number = v_candidate
               OR project.display_name = v_candidate
        );
        UPDATE public.project_daily_counters
        SET last_number = last_number + 1,
            updated_at = NOW()
        WHERE project_date = v_date
        RETURNING last_number INTO v_sequence;
    END LOOP;
    RETURN v_candidate;
END;
$$;

REVOKE ALL ON FUNCTION public.next_project_display_name(UUID, TEXT, TEXT, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_project_display_name(UUID, TEXT, TEXT, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- New Supplier PO numbers expose only the daily Project sequence, Scoop,
-- service code and Job sequence. Existing PO numbers and immutable versions
-- remain untouched. A reassignment receives R02, R03, ... only when needed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.contextual_supplier_po_number(p_job_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_number TEXT;
    v_scoop_number TEXT;
    v_job_number TEXT;
    v_service_type TEXT;
    v_project_key TEXT;
    v_scoop_sequence TEXT;
    v_job_sequence TEXT;
    v_base TEXT;
    v_candidate TEXT;
    v_revision INTEGER := 2;
BEGIN
    SELECT project.project_number, scoop.scoop_number,
           job.job_number, job.service_type
    INTO v_project_number, v_scoop_number, v_job_number, v_service_type
    FROM public.project_jobs job
    JOIN public.projects project ON project.id = job.project_id
    LEFT JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    WHERE job.id = p_job_id;
    IF NOT FOUND THEN RETURN NULL; END IF;

    v_project_key := substring(v_project_number FROM '^([0-9]{6}-[0-9]+)_');
    IF v_project_key IS NULL THEN RETURN NULL; END IF;
    v_scoop_sequence := COALESCE(
        substring(v_scoop_number FROM '-S([0-9]+)$'),
        '01'
    );
    v_job_sequence := COALESCE(
        substring(v_job_number FROM '_J([0-9]+)$'),
        '01'
    );
    v_base := 'PO-' || v_project_key
        || '_S' || lpad(v_scoop_sequence, 2, '0')
        || '-' || public.job_service_code(v_service_type)
        || '_J' || lpad(v_job_sequence, 2, '0');

    PERFORM pg_advisory_xact_lock(hashtext('retodo:supplier-po:' || v_base));
    v_candidate := v_base;
    WHILE EXISTS (
        SELECT 1 FROM public.supplier_purchase_orders po
        WHERE po.po_number = v_candidate
    ) LOOP
        v_candidate := v_base || '-R' || lpad(v_revision::TEXT, 2, '0');
        v_revision := v_revision + 1;
    END LOOP;
    RETURN v_candidate;
END;
$$;

REVOKE ALL ON FUNCTION public.contextual_supplier_po_number(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.apply_contextual_supplier_po_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_contextual_number TEXT;
BEGIN
    IF NEW.job_id IS NULL THEN RETURN NEW; END IF;
    v_contextual_number := public.contextual_supplier_po_number(NEW.job_id);
    IF v_contextual_number IS NOT NULL THEN
        NEW.po_number := v_contextual_number;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS supplier_pos_apply_contextual_number
    ON public.supplier_purchase_orders;
CREATE TRIGGER supplier_pos_apply_contextual_number
BEFORE INSERT ON public.supplier_purchase_orders
FOR EACH ROW EXECUTE FUNCTION public.apply_contextual_supplier_po_number();

COMMIT;
