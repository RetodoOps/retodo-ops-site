-- RetodoOps TMS — Scoop pricing, language propagation and Scoop-first
-- Dashboard support. Run once after 027_project_scoops_and_rate_matching.sql.

BEGIN;

ALTER TABLE public.project_scoops
    ADD COLUMN IF NOT EXISTS price NUMERIC(14, 2) NOT NULL DEFAULT 0;

ALTER TABLE public.project_scoops
    DROP CONSTRAINT IF EXISTS project_scoops_price_check;
ALTER TABLE public.project_scoops
    ADD CONSTRAINT project_scoops_price_check CHECK (price >= 0);

-- Preserve the former Project price as the first Scoop price. Additional
-- Scoops start at zero until the PM gives each one its own Client price.
WITH primary_scoops AS (
    SELECT DISTINCT ON (scoop.project_id)
        scoop.id,
        scoop.project_id
    FROM public.project_scoops scoop
    ORDER BY scoop.project_id, scoop.created_at, scoop.id
), unpriced_projects AS (
    SELECT project.id, project.price
    FROM public.projects project
    WHERE COALESCE(project.price, 0) <> 0
      AND NOT EXISTS (
          SELECT 1
          FROM public.project_scoops scoop
          WHERE scoop.project_id = project.id
            AND COALESCE(scoop.price, 0) <> 0
      )
)
UPDATE public.project_scoops scoop
SET price = project.price,
    updated_at = NOW()
FROM primary_scoops primary_scoop
JOIN unpriced_projects project ON project.id = primary_scoop.project_id
WHERE scoop.id = primary_scoop.id;

CREATE OR REPLACE FUNCTION public.refresh_project_price_from_scoops(
    p_project_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.projects project
    SET price = COALESCE((
            SELECT sum(scoop.price)
            FROM public.project_scoops scoop
            WHERE scoop.project_id = p_project_id
              AND scoop.active
        ), 0),
        updated_at = NOW()
    WHERE project.id = p_project_id;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_project_price_from_scoops(UUID)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refresh_project_price_from_scoops(UUID)
    FROM authenticated;

CREATE OR REPLACE FUNCTION public.recalculate_project_price_from_scoops()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_id UUID := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.project_id
        ELSE NEW.project_id
    END;
BEGIN
    PERFORM public.refresh_project_price_from_scoops(v_project_id);

    IF TG_OP = 'UPDATE' AND OLD.project_id IS DISTINCT FROM NEW.project_id THEN
        PERFORM public.refresh_project_price_from_scoops(OLD.project_id);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_scoops_recalculate_project_price
    ON public.project_scoops;
CREATE TRIGGER project_scoops_recalculate_project_price
AFTER INSERT OR UPDATE OF project_id, price, active OR DELETE
ON public.project_scoops
FOR EACH ROW EXECUTE FUNCTION public.recalculate_project_price_from_scoops();

-- New Projects still create S01 automatically. Its price starts with the
-- price entered in the Project creation form, then becomes part of the sum.
CREATE OR REPLACE FUNCTION public.create_initial_project_scoop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.project_scoops (
        project_id, scoop_number, source_language, target_language,
        deadline, price, created_by
    ) VALUES (
        NEW.id,
        NEW.project_number || '-S01',
        COALESCE(NULLIF(btrim(NEW.source_language), ''), 'English (UK)'),
        COALESCE(NULLIF(btrim(NEW.target_language), ''), 'Other'),
        NEW.deadline,
        COALESCE(NEW.price, 0),
        NEW.created_by
    ) ON CONFLICT (project_id, scoop_number) DO NOTHING;
    RETURN NEW;
END;
$$;

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
    IF v_deadline IS NOT NULL AND v_deadline < NOW() THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;
    IF v_price < 0 THEN RAISE EXCEPTION 'Scoop price cannot be negative'; END IF;

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
        v_source,
        v_target,
        COALESCE(v_deadline, v_project.deadline),
        v_price,
        auth.uid()
    ) RETURNING id INTO v_scoop_id;
    RETURN v_scoop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_scoop(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_scoop(UUID, JSONB)
    TO authenticated;

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
    v_price NUMERIC;
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
    v_price := COALESCE(
        NULLIF(p_payload->>'price', '')::NUMERIC,
        v_scoop.price,
        0
    );
    IF v_source IS NULL OR v_target IS NULL THEN
        RAISE EXCEPTION 'Source and Target languages are required';
    END IF;
    IF v_source = v_target THEN
        RAISE EXCEPTION 'Source and Target languages must be different';
    END IF;
    IF v_deadline IS NOT NULL
       AND v_deadline < NOW()
       AND v_deadline IS DISTINCT FROM v_scoop.deadline THEN
        RAISE EXCEPTION 'Scoop deadline cannot be in the past';
    END IF;
    IF v_price < 0 THEN RAISE EXCEPTION 'Scoop price cannot be negative'; END IF;

    UPDATE public.project_scoops
    SET source_language = v_source,
        target_language = v_target,
        deadline = v_deadline,
        price = v_price,
        updated_at = NOW()
    WHERE id = p_scoop_id;

    -- The Scoop is authoritative for its language pair. All connected Jobs,
    -- including assigned Jobs, show the edit immediately. Immutable PO version
    -- snapshots remain preserved as historical documents.
    PERFORM set_config('retodo.job_overview_edit', 'on', TRUE);
    UPDATE public.project_jobs
    SET source_language = v_source,
        target_language = v_target,
        updated_at = NOW()
    WHERE project_scoop_id = p_scoop_id;

    SELECT NOT EXISTS (
        SELECT 1
        FROM public.project_scoops earlier
        WHERE earlier.project_id = v_scoop.project_id
          AND (earlier.created_at, earlier.id) <
              (v_scoop.created_at, v_scoop.id)
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
GRANT EXECUTE ON FUNCTION public.update_project_scoop(UUID, JSONB)
    TO authenticated;

-- Detailed Client price rows now update the price of their owning Scoop;
-- the Scoop trigger above then updates the Project total.
CREATE OR REPLACE FUNCTION public.recalculate_project_client_price()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_scoop_id UUID := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.project_scoop_id
        ELSE NEW.project_scoop_id
    END;
BEGIN
    IF v_scoop_id IS NOT NULL THEN
        UPDATE public.project_scoops scoop
        SET price = COALESCE((
                SELECT sum(line.price)
                FROM public.scope_items line
                WHERE line.project_scoop_id = v_scoop_id
            ), 0),
            updated_at = NOW()
        WHERE scoop.id = v_scoop_id;
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.project_scoop_id IS DISTINCT FROM NEW.project_scoop_id
       AND OLD.project_scoop_id IS NOT NULL THEN
        UPDATE public.project_scoops scoop
        SET price = COALESCE((
                SELECT sum(line.price)
                FROM public.scope_items line
                WHERE line.project_scoop_id = OLD.project_scoop_id
            ), 0),
            updated_at = NOW()
        WHERE scoop.id = OLD.project_scoop_id;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_recalculate_project_price
    ON public.scope_items;
CREATE TRIGGER scope_items_recalculate_project_price
AFTER INSERT OR UPDATE OF project_id, project_scoop_id, quantity,
    price_unit, unit_price, price OR DELETE
ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.recalculate_project_client_price();

-- Reconcile the Project totals once after adding/backfilling Scoop prices.
DO $$
DECLARE
    v_project_id UUID;
BEGIN
    FOR v_project_id IN SELECT id FROM public.projects LOOP
        PERFORM public.refresh_project_price_from_scoops(v_project_id);
    END LOOP;
END;
$$;

COMMIT;
