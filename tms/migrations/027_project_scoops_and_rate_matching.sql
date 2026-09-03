-- RetodoOps TMS — Project Scoops, Scoop-aware Job identities and precise
-- Supplier rate validation. Run once after 026_service_catalog_and_settings.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS public.project_scoops (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id       UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    scoop_number     TEXT NOT NULL,
    source_language  TEXT NOT NULL CHECK (btrim(source_language) <> ''),
    target_language  TEXT NOT NULL CHECK (btrim(target_language) <> ''),
    deadline         TIMESTAMPTZ,
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_by       UUID REFERENCES public.profiles(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (project_id, scoop_number)
);

CREATE INDEX IF NOT EXISTS project_scoops_project_id_idx
    ON public.project_scoops(project_id, created_at);

DROP TRIGGER IF EXISTS project_scoops_set_updated_at ON public.project_scoops;
CREATE TRIGGER project_scoops_set_updated_at
BEFORE UPDATE ON public.project_scoops
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.project_scoops ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_scoops_company_read ON public.project_scoops;
CREATE POLICY project_scoops_company_read ON public.project_scoops
FOR SELECT TO authenticated USING (public.is_company_user());
DROP POLICY IF EXISTS project_scoops_operational_manage ON public.project_scoops;
CREATE POLICY project_scoops_operational_manage ON public.project_scoops
FOR ALL TO authenticated
USING (public.can_manage_operations())
WITH CHECK (public.can_manage_operations());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_scoops TO authenticated;

CREATE OR REPLACE FUNCTION public.tms_language_code(p_language TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE lower(btrim(COALESCE(p_language, '')))
        WHEN 'english' THEN 'EN'
        WHEN 'english (uk)' THEN 'EN-GB'
        WHEN 'english (us)' THEN 'EN-US'
        WHEN 'bulgarian' THEN 'BG'
        WHEN 'swedish' THEN 'SV'
        WHEN 'danish' THEN 'DA'
        WHEN 'finnish' THEN 'FI'
        WHEN 'norwegian' THEN 'NO'
        WHEN 'norwegian (bokmål)' THEN 'NB'
        WHEN 'norwegian (nynorsk)' THEN 'NN'
        WHEN 'german' THEN 'DE'
        WHEN 'french' THEN 'FR'
        WHEN 'spanish' THEN 'ES'
        WHEN 'italian' THEN 'IT'
        WHEN 'dutch' THEN 'NL'
        WHEN 'polish' THEN 'PL'
        WHEN 'portuguese' THEN 'PT'
        WHEN 'russian' THEN 'RU'
        WHEN 'ukrainian' THEN 'UK'
        WHEN 'czech' THEN 'CS'
        WHEN 'slovak' THEN 'SK'
        WHEN 'hungarian' THEN 'HU'
        WHEN 'romanian' THEN 'RO'
        WHEN 'greek' THEN 'EL'
        WHEN 'turkish' THEN 'TR'
        WHEN 'estonian' THEN 'ET'
        WHEN 'latvian' THEN 'LV'
        WHEN 'lithuanian' THEN 'LT'
        WHEN 'icelandic' THEN 'IS'
        WHEN 'chinese (simplified)' THEN 'ZH-CN'
        WHEN 'chinese (traditional)' THEN 'ZH-TW'
        WHEN 'japanese' THEN 'JA'
        WHEN 'korean' THEN 'KO'
        WHEN 'arabic' THEN 'AR'
        WHEN 'hebrew' THEN 'HE'
        WHEN 'hindi' THEN 'HI'
        WHEN 'thai' THEN 'TH'
        WHEN 'vietnamese' THEN 'VI'
        ELSE upper(left(regexp_replace(COALESCE(p_language, 'XX'), '[^A-Za-z]', '', 'g'), 3))
    END;
$$;

-- Every existing Project becomes a one-Scoop Project without changing any
-- commercial, PO or workflow history.
INSERT INTO public.project_scoops (
    project_id, scoop_number, source_language, target_language,
    deadline, created_by, created_at, updated_at
)
SELECT
    project.id,
    project.project_number || '-S01',
    COALESCE(NULLIF(btrim(project.source_language), ''), 'English (UK)'),
    COALESCE(NULLIF(btrim(project.target_language), ''), 'Other'),
    project.deadline,
    project.created_by,
    project.created_at,
    project.updated_at
FROM public.projects project
WHERE NOT EXISTS (
    SELECT 1 FROM public.project_scoops scoop WHERE scoop.project_id = project.id
);

ALTER TABLE public.project_jobs
    ADD COLUMN IF NOT EXISTS project_scoop_id UUID
    REFERENCES public.project_scoops(id) ON DELETE RESTRICT;

UPDATE public.project_jobs job
SET project_scoop_id = (
    SELECT scoop.id FROM public.project_scoops scoop
    WHERE scoop.project_id = job.project_id
    ORDER BY scoop.created_at, scoop.id LIMIT 1
)
WHERE job.project_scoop_id IS NULL;

ALTER TABLE public.project_jobs
    ALTER COLUMN project_scoop_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS project_jobs_scoop_id_idx
    ON public.project_jobs(project_scoop_id, created_at);

-- Financial lines remain Project totals, but are tagged with their Scoop so
-- per-Scoop pricing can be expanded without another data migration.
ALTER TABLE public.scope_items
    ADD COLUMN IF NOT EXISTS project_scoop_id UUID
    REFERENCES public.project_scoops(id) ON DELETE SET NULL;

UPDATE public.scope_items line
SET project_scoop_id = (
    SELECT scoop.id FROM public.project_scoops scoop
    WHERE scoop.project_id = line.project_id
    ORDER BY scoop.created_at, scoop.id LIMIT 1
)
WHERE line.project_scoop_id IS NULL;

CREATE INDEX IF NOT EXISTS scope_items_scoop_id_idx
    ON public.scope_items(project_scoop_id, sort_order);

CREATE OR REPLACE FUNCTION public.inherit_scope_item_scoop()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.project_scoop_id IS NULL THEN
        SELECT scoop.id INTO NEW.project_scoop_id
        FROM public.project_scoops scoop
        WHERE scoop.project_id = NEW.project_id AND scoop.active
        ORDER BY scoop.created_at, scoop.id LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_inherit_scoop ON public.scope_items;
CREATE TRIGGER scope_items_inherit_scoop
BEFORE INSERT ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.inherit_scope_item_scoop();

CREATE OR REPLACE FUNCTION public.create_initial_project_scoop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.project_scoops (
        project_id, scoop_number, source_language, target_language,
        deadline, created_by
    ) VALUES (
        NEW.id,
        NEW.project_number || '-S01',
        COALESCE(NULLIF(btrim(NEW.source_language), ''), 'English (UK)'),
        COALESCE(NULLIF(btrim(NEW.target_language), ''), 'Other'),
        NEW.deadline,
        NEW.created_by
    ) ON CONFLICT (project_id, scoop_number) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_create_initial_scoop ON public.projects;
CREATE TRIGGER projects_create_initial_scoop
AFTER INSERT ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.create_initial_project_scoop();

CREATE OR REPLACE FUNCTION public.protect_project_scoop_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.project_id IS DISTINCT FROM OLD.project_id
       OR NEW.scoop_number IS DISTINCT FROM OLD.scoop_number THEN
        RAISE EXCEPTION 'Scoop identity is permanent';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_scoops_protect_identity ON public.project_scoops;
CREATE TRIGGER project_scoops_protect_identity
BEFORE UPDATE OF project_id, scoop_number ON public.project_scoops
FOR EACH ROW EXECUTE FUNCTION public.protect_project_scoop_identity();

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
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF v_source IS NULL OR v_target IS NULL THEN
        RAISE EXCEPTION 'Source and Target languages are required';
    END IF;
    IF v_deadline IS NOT NULL AND v_deadline < NOW() THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_project_id::TEXT || ':scoop'));
    SELECT COALESCE(max(NULLIF(substring(scoop_number FROM '-S([0-9]+)$'), '')::INTEGER), 0) + 1
    INTO v_sequence
    FROM public.project_scoops WHERE project_id = p_project_id;

    INSERT INTO public.project_scoops (
        project_id, scoop_number, source_language, target_language,
        deadline, created_by
    ) VALUES (
        p_project_id,
        v_project.project_number || '-S' || lpad(v_sequence::TEXT, 2, '0'),
        v_source, v_target, COALESCE(v_deadline, v_project.deadline), auth.uid()
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
    v_scoop public.project_scoops%ROWTYPE;
    v_source TEXT := NULLIF(btrim(p_payload->>'source_language'), '');
    v_target TEXT := NULLIF(btrim(p_payload->>'target_language'), '');
    v_deadline TIMESTAMPTZ := NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ;
    v_is_primary BOOLEAN;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_scoop FROM public.project_scoops WHERE id = p_scoop_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Scoop not found'; END IF;
    IF v_source IS NULL OR v_target IS NULL THEN
        RAISE EXCEPTION 'Source and Target languages are required';
    END IF;
    IF v_deadline IS NOT NULL
       AND v_deadline < NOW()
       AND v_deadline IS DISTINCT FROM v_scoop.deadline THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;

    UPDATE public.project_scoops
    SET source_language = v_source,
        target_language = v_target,
        deadline = v_deadline,
        updated_at = NOW()
    WHERE id = p_scoop_id;

    -- Unassigned Jobs inherit corrected Scoop languages. Assigned Jobs retain
    -- their issued commercial terms and can be revised from Job Overview.
    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs
    SET source_language = v_source,
        target_language = v_target,
        updated_at = NOW()
    WHERE project_scoop_id = p_scoop_id
      AND resource_id IS NULL
      AND status = 'Unassigned';

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
            deadline = COALESCE(v_deadline, deadline),
            updated_at = NOW()
        WHERE id = v_scoop.project_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_project_scoop(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_project_scoop(UUID, JSONB) TO authenticated;

-- One-time Scoop-aware Job rename. PO version snapshots remain immutable.
DROP TRIGGER IF EXISTS project_jobs_protect_identity ON public.project_jobs;

WITH numbered AS (
    SELECT
        job.id,
        scoop.scoop_number,
        public.job_service_code(job.service_type) AS service_code,
        row_number() OVER (
            PARTITION BY job.project_scoop_id
            ORDER BY job.created_at, job.id
        ) AS sequence_number
    FROM public.project_jobs job
    JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
)
UPDATE public.project_jobs job
SET job_number = numbered.scoop_number || '-' || numbered.service_code || '_J'
    || lpad(numbered.sequence_number::TEXT, 2, '0')
FROM numbered WHERE numbered.id = job.id;

CREATE OR REPLACE FUNCTION public.protect_project_job_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.project_id IS DISTINCT FROM OLD.project_id
       OR NEW.project_scoop_id IS DISTINCT FROM OLD.project_scoop_id THEN
        RAISE EXCEPTION 'A Job cannot be moved to another Project or Scoop';
    END IF;
    IF NEW.job_number IS DISTINCT FROM OLD.job_number THEN
        RAISE EXCEPTION 'Job number is a permanent technical reference';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER project_jobs_protect_identity
BEFORE UPDATE OF project_id, project_scoop_id, job_number ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.protect_project_job_identity();

CREATE OR REPLACE FUNCTION public.prepare_project_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_scoop public.project_scoops%ROWTYPE;
    v_sequence INTEGER;
    v_assignment_changed BOOLEAN := TG_OP = 'INSERT';
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_assignment_changed := NEW.resource_id IS DISTINCT FROM OLD.resource_id;
    END IF;

    IF NEW.project_scoop_id IS NULL THEN
        SELECT scoop.id INTO NEW.project_scoop_id
        FROM public.project_scoops scoop
        WHERE scoop.project_id = NEW.project_id AND scoop.active
        ORDER BY scoop.created_at, scoop.id LIMIT 1;
    END IF;
    SELECT * INTO v_scoop FROM public.project_scoops WHERE id = NEW.project_scoop_id;
    IF NOT FOUND OR v_scoop.project_id IS DISTINCT FROM NEW.project_id THEN
        RAISE EXCEPTION 'Select a Scoop belonging to this Project';
    END IF;

    IF TG_OP = 'INSERT' AND NULLIF(btrim(NEW.job_number), '') IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext(NEW.project_scoop_id::TEXT || ':job'));
        SELECT COALESCE(max(NULLIF(substring(job_number FROM '[-_]J([0-9]+)$'), '')::INTEGER), 0) + 1
        INTO v_sequence FROM public.project_jobs WHERE project_scoop_id = NEW.project_scoop_id;
        NEW.job_number := v_scoop.scoop_number || '-'
            || public.job_service_code(NEW.service_type) || '_J'
            || lpad(v_sequence::TEXT, 2, '0');
    END IF;

    IF v_assignment_changed THEN
        NEW.restriction_warning := FALSE;
        NEW.restriction_overridden := FALSE;
        NEW.override_reason := NULL;
        NEW.overridden_by := NULL;
        NEW.overridden_at := NULL;
        IF NEW.resource_id IS NOT NULL THEN
            SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
            IF NOT FOUND THEN RAISE EXCEPTION 'Selected Resource not found'; END IF;
            IF v_resource.lifecycle_status IS DISTINCT FROM 'Active' THEN
                RAISE EXCEPTION 'Only an Active Resource may receive a new Job assignment';
            END IF;
            IF v_resource.resource_status NOT IN ('Assignable', 'Proven', 'Preferred') THEN
                RAISE EXCEPTION 'Resource status must be Assignable, Proven or Preferred before assignment';
            END IF;
            IF NULLIF(btrim(v_resource.email), '') IS NULL THEN
                RAISE EXCEPTION 'Add a Resource email address before assignment';
            END IF;
        END IF;
    END IF;

    IF jsonb_typeof(NEW.cat_analysis->'rows') = 'array'
       AND jsonb_array_length(NEW.cat_analysis->'rows') > 0 THEN
        NEW.supplier_amount := COALESCE((NEW.cat_analysis->>'total')::NUMERIC, 0);
    ELSIF COALESCE(NEW.supplier_amount, 0) = 0
       AND NEW.quantity IS NOT NULL AND NEW.supplier_rate IS NOT NULL THEN
        NEW.supplier_amount := CASE WHEN NEW.unit = 'Fixed fee'
            THEN round(NEW.supplier_rate, 2)
            ELSE round(NEW.quantity * NEW.supplier_rate, 2) END;
    END IF;
    IF NEW.status IN ('Assigned', 'In Progress') AND NEW.accepted_at IS NULL THEN NEW.accepted_at := NOW(); END IF;
    IF NEW.status = 'Delivered' AND NEW.delivered_at IS NULL THEN NEW.delivered_at := NOW(); END IF;
    IF NEW.status = 'Approved' AND NEW.approved_at IS NULL THEN NEW.approved_at := NOW(); END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_prepare ON public.project_jobs;
CREATE TRIGGER project_jobs_prepare
BEFORE INSERT OR UPDATE OF project_scoop_id, resource_id, status, quantity,
    supplier_rate, supplier_amount, cat_analysis, restriction_overridden, override_reason
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.prepare_project_job();

CREATE OR REPLACE FUNCTION public.create_project_job(
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
    v_scoop public.project_scoops%ROWTYPE;
    v_job_id UUID;
    v_job_number TEXT;
    v_sequence INTEGER;
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
    v_specialization_id UUID := NULLIF(p_payload->>'specialization_id', '')::UUID;
    v_deadline TIMESTAMPTZ := NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ;
    v_scoop_id UUID := NULLIF(p_payload->>'project_scoop_id', '')::UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN RAISE EXCEPTION 'Operational role required'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    IF v_scoop_id IS NULL THEN
        SELECT id INTO v_scoop_id FROM public.project_scoops
        WHERE project_id = p_project_id AND active ORDER BY created_at, id LIMIT 1;
    END IF;
    SELECT * INTO v_scoop FROM public.project_scoops
    WHERE id = v_scoop_id AND project_id = p_project_id AND active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Select an active Scoop belonging to this Project'; END IF;
    IF v_service IS NULL THEN RAISE EXCEPTION 'Job service is required'; END IF;
    IF v_specialization_id IS NULL THEN RAISE EXCEPTION 'Job specialization is required'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.project_specializations link
        WHERE link.project_id = p_project_id AND link.specialization_id = v_specialization_id
    ) THEN RAISE EXCEPTION 'The Job specialization must belong to the Project'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_scoop_id::TEXT || ':job'));
    SELECT COALESCE(max(NULLIF(substring(job_number FROM '[-_]J([0-9]+)$'), '')::INTEGER), 0) + 1
    INTO v_sequence FROM public.project_jobs WHERE project_scoop_id = v_scoop_id;
    v_job_number := v_scoop.scoop_number || '-'
        || public.job_service_code(v_service) || '_J'
        || lpad(v_sequence::TEXT, 2, '0');

    INSERT INTO public.project_jobs (
        id, project_id, project_scoop_id, job_number, resource_id, service_type,
        source_language, target_language, specialization_id, status, deadline,
        quantity, unit, supplier_rate, supplier_currency, supplier_amount,
        po_required, notes, created_by
    ) VALUES (
        gen_random_uuid(), p_project_id, v_scoop_id, v_job_number, NULL, v_service,
        v_scoop.source_language, v_scoop.target_language, v_specialization_id,
        'Unassigned', COALESCE(v_deadline, v_scoop.deadline), NULL, 'Source words',
        NULL, COALESCE(v_project.currency, 'EUR'), 0,
        COALESCE((p_payload->>'po_required')::BOOLEAN, TRUE),
        NULLIF(btrim(p_payload->>'notes'), ''), auth.uid()
    ) RETURNING id INTO v_job_id;
    PERFORM public.refresh_project_financials(p_project_id);
    RETURN v_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_job(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_job(UUID, JSONB) TO authenticated;

-- The previous generic error hid which stored property did not match. This
-- version accepts legacy scalar language cards and reports the exact mismatch.
CREATE OR REPLACE FUNCTION public.create_job_offer_from_rate(
    p_job_id UUID,
    p_resource_id UUID,
    p_resource_rate_id UUID,
    p_response_due_at TIMESTAMPTZ DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_client_identity_disclosed BOOLEAN DEFAULT FALSE,
    p_override BOOLEAN DEFAULT FALSE,
    p_override_reason TEXT DEFAULT NULL,
    p_cat_rows JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.project_jobs%ROWTYPE;
    v_project public.projects%ROWTYPE;
    v_rate public.resource_rates%ROWTYPE;
    v_analysis JSONB;
    v_offer_id UUID;
BEGIN
    SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = v_job.project_id;
    SELECT * INTO v_rate FROM public.resource_rates
    WHERE id = p_resource_rate_id AND resource_id = p_resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'The selected Supplier rate does not belong to this Resource'; END IF;
    IF v_rate.base_rate_id IS NOT NULL THEN RAISE EXCEPTION 'Select the Supplier base rate, not a CAT child row'; END IF;
    IF NOT COALESCE(v_rate.active, FALSE) THEN RAISE EXCEPTION 'The selected Supplier rate is inactive'; END IF;
    IF v_rate.status IS DISTINCT FROM 'Approved' THEN
        RAISE EXCEPTION 'The selected Supplier rate status is %, not Approved', COALESCE(v_rate.status, 'not set');
    END IF;
    IF v_rate.account_id IS NOT NULL AND v_rate.account_id IS DISTINCT FROM v_project.account_id THEN
        RAISE EXCEPTION 'The selected Supplier rate belongs to a different Client Account';
    END IF;
    IF lower(btrim(v_rate.service_type)) IS DISTINCT FROM lower(btrim(v_job.service_type)) THEN
        RAISE EXCEPTION 'Supplier rate Service (%) does not match Job Service (%)', v_rate.service_type, v_job.service_type;
    END IF;
    IF lower(btrim(v_rate.unit)) IS DISTINCT FROM lower(btrim(v_job.unit)) THEN
        RAISE EXCEPTION 'Supplier rate Unit (%) does not match Job Unit (%)', v_rate.unit, v_job.unit;
    END IF;
    IF COALESCE(cardinality(v_rate.source_languages), 0) > 0 THEN
        IF NOT (v_job.source_language = ANY(v_rate.source_languages)) THEN
            RAISE EXCEPTION 'Supplier rate does not cover Job Source language %', v_job.source_language;
        END IF;
    ELSIF v_rate.source_language IS NOT NULL
          AND v_rate.source_language IS DISTINCT FROM v_job.source_language THEN
        RAISE EXCEPTION 'Supplier rate Source language (%) does not match Job Source language (%)',
            v_rate.source_language, v_job.source_language;
    END IF;
    IF COALESCE(cardinality(v_rate.target_languages), 0) > 0 THEN
        IF NOT (v_job.target_language = ANY(v_rate.target_languages)) THEN
            RAISE EXCEPTION 'Supplier rate does not cover Job Target language %', v_job.target_language;
        END IF;
    ELSIF v_rate.target_language IS NOT NULL
          AND v_rate.target_language IS DISTINCT FROM v_job.target_language THEN
        RAISE EXCEPTION 'Supplier rate Target language (%) does not match Job Target language (%)',
            v_rate.target_language, v_job.target_language;
    END IF;
    IF v_rate.specialization_id IS NOT NULL
       AND v_rate.specialization_id IS DISTINCT FROM v_job.specialization_id THEN
        RAISE EXCEPTION 'Supplier rate specialization does not match the Job specialization';
    END IF;

    v_analysis := public.normalize_supplier_cat_analysis(p_resource_rate_id, p_cat_rows);
    IF COALESCE((v_analysis->>'quantity')::NUMERIC, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter a quantity in at least one Supplier CAT row';
    END IF;
    v_offer_id := public.create_job_offer(
        p_job_id, p_resource_id, p_response_due_at, v_rate.unit,
        COALESCE((v_analysis->>'quantity')::NUMERIC, p_quantity, v_job.quantity),
        v_rate.rate, v_rate.currency, p_message, p_client_identity_disclosed,
        p_override, p_override_reason
    );
    UPDATE public.job_offers
    SET resource_rate_id = p_resource_rate_id, cat_analysis = v_analysis
    WHERE id = v_offer_id;
    RETURN v_offer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT, JSONB
) TO authenticated;

COMMIT;
