-- RetodoOps TMS — required Project/Job specializations and linked Resource rates
-- Run after 006_internal_staff_assignments.sql.

BEGIN;

-- Ensure a safe fallback exists for legacy records.
INSERT INTO public.specializations (name, code, active)
VALUES ('General', 'GENERAL', TRUE)
ON CONFLICT DO NOTHING;

UPDATE public.specializations
SET active = TRUE
WHERE lower(name) = 'general';

-- Accounts must define at least one specialization. Legacy empty Accounts
-- receive General and can be refined later in the Client module.
INSERT INTO public.client_account_specializations (account_id, specialization_id, is_default)
SELECT account.id, spec.id, TRUE
FROM public.client_accounts account
CROSS JOIN public.specializations spec
WHERE lower(spec.name) = 'general'
  AND NOT EXISTS (
      SELECT 1 FROM public.client_account_specializations link
      WHERE link.account_id = account.id
  )
ON CONFLICT DO NOTHING;

-- Account Projects inherit only the specializations configured on the Account.
DELETE FROM public.project_specializations project_spec
USING public.projects project
WHERE project_spec.project_id = project.id
  AND project.account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.client_account_specializations account_spec
      WHERE account_spec.account_id = project.account_id
        AND account_spec.specialization_id = project_spec.specialization_id
  );

INSERT INTO public.project_specializations (project_id, specialization_id, source)
SELECT project.id, account_spec.specialization_id, 'Account default'
FROM public.projects project
JOIN public.client_account_specializations account_spec
  ON account_spec.account_id = project.account_id
ON CONFLICT (project_id, specialization_id) DO UPDATE
SET source = 'Account default';

-- General Projects choose freely. Backfill General only where no choice exists.
INSERT INTO public.project_specializations (project_id, specialization_id, source)
SELECT project.id, spec.id, 'Manual'
FROM public.projects project
CROSS JOIN public.specializations spec
WHERE project.account_id IS NULL
  AND lower(spec.name) = 'general'
  AND NOT EXISTS (
      SELECT 1 FROM public.project_specializations existing
      WHERE existing.project_id = project.id
  )
ON CONFLICT DO NOTHING;

-- Quote items and Jobs must always carry a specialization.
UPDATE public.quote_items item
SET specialization_id = COALESCE(
    (
        SELECT account_spec.specialization_id
        FROM public.quotes quote
        JOIN public.client_account_specializations account_spec
          ON account_spec.account_id = quote.account_id
        WHERE quote.id = item.quote_id
        ORDER BY account_spec.created_at
        LIMIT 1
    ),
    (SELECT id FROM public.specializations WHERE lower(name) = 'general' LIMIT 1)
)
WHERE item.specialization_id IS NULL;

UPDATE public.quote_items item
SET specialization_id = (
    SELECT account_spec.specialization_id
    FROM public.quotes quote
    JOIN public.client_account_specializations account_spec
      ON account_spec.account_id = quote.account_id
    WHERE quote.id = item.quote_id
    ORDER BY account_spec.created_at
    LIMIT 1
)
WHERE EXISTS (
    SELECT 1 FROM public.quotes quote
    WHERE quote.id = item.quote_id AND quote.account_id IS NOT NULL
)
AND NOT EXISTS (
    SELECT 1
    FROM public.quotes quote
    JOIN public.client_account_specializations account_spec
      ON account_spec.account_id = quote.account_id
    WHERE quote.id = item.quote_id
      AND account_spec.specialization_id = item.specialization_id
);

ALTER TABLE public.quote_items
    ALTER COLUMN specialization_id SET NOT NULL;

CREATE OR REPLACE FUNCTION public.validate_quote_item_specialization()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_account_id UUID;
BEGIN
    SELECT account_id INTO v_account_id
    FROM public.quotes
    WHERE id = NEW.quote_id;
    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_account_specializations account_spec
        WHERE account_spec.account_id = v_account_id
          AND account_spec.specialization_id = NEW.specialization_id
    ) THEN
        RAISE EXCEPTION 'Quote item specialization must be configured on the selected Account';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quote_items_validate_specialization ON public.quote_items;
CREATE TRIGGER quote_items_validate_specialization
BEFORE INSERT OR UPDATE OF quote_id, specialization_id
ON public.quote_items
FOR EACH ROW EXECUTE FUNCTION public.validate_quote_item_specialization();

UPDATE public.project_jobs job
SET specialization_id = COALESCE(
    (
        SELECT project_spec.specialization_id
        FROM public.project_specializations project_spec
        WHERE project_spec.project_id = job.project_id
        ORDER BY project_spec.created_at
        LIMIT 1
    ),
    (SELECT id FROM public.specializations WHERE lower(name) = 'general' LIMIT 1)
)
WHERE job.specialization_id IS NULL;

-- Normalize legacy Jobs whose specialization is not currently selected on the
-- Project so the new relationship can be enforced without orphaned values.
UPDATE public.project_jobs job
SET specialization_id = (
    SELECT project_spec.specialization_id
    FROM public.project_specializations project_spec
    WHERE project_spec.project_id = job.project_id
    ORDER BY project_spec.created_at
    LIMIT 1
)
WHERE NOT EXISTS (
    SELECT 1 FROM public.project_specializations project_spec
    WHERE project_spec.project_id = job.project_id
      AND project_spec.specialization_id = job.specialization_id
);

ALTER TABLE public.project_jobs
    ALTER COLUMN specialization_id SET NOT NULL;

-- Keep provenance to the exact approved Resource price-list row while retaining
-- immutable commercial snapshots on Offers and Jobs.
ALTER TABLE public.job_offers
    ADD COLUMN IF NOT EXISTS resource_rate_id UUID
        REFERENCES public.resource_rates(id) ON DELETE SET NULL;

ALTER TABLE public.project_jobs
    ADD COLUMN IF NOT EXISTS resource_rate_id UUID
        REFERENCES public.resource_rates(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS job_offers_resource_rate_idx
    ON public.job_offers(resource_rate_id);
CREATE INDEX IF NOT EXISTS project_jobs_resource_rate_idx
    ON public.project_jobs(resource_rate_id);

CREATE OR REPLACE FUNCTION public.validate_project_specialization()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_account_id UUID;
BEGIN
    SELECT account_id INTO v_account_id
    FROM public.projects
    WHERE id = NEW.project_id;

    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_account_specializations account_spec
        WHERE account_spec.account_id = v_account_id
          AND account_spec.specialization_id = NEW.specialization_id
    ) THEN
        RAISE EXCEPTION 'Project specialization must be configured on the selected Account';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_specializations_validate_account
    ON public.project_specializations;
CREATE TRIGGER project_specializations_validate_account
BEFORE INSERT OR UPDATE OF project_id, specialization_id
ON public.project_specializations
FOR EACH ROW EXECUTE FUNCTION public.validate_project_specialization();

CREATE OR REPLACE FUNCTION public.protect_used_project_specialization()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.project_jobs job
        WHERE job.project_id = OLD.project_id
          AND job.specialization_id = OLD.specialization_id
    ) OR EXISTS (
        SELECT 1 FROM public.scope_items line
        WHERE line.project_id = OLD.project_id
          AND line.specialization_id = OLD.specialization_id
          AND line.service_type <> 'Quote discount'
    ) THEN
        RAISE EXCEPTION 'A Project specialization used by a Job or commercial line cannot be removed';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS project_specializations_protect_used
    ON public.project_specializations;
CREATE TRIGGER project_specializations_protect_used
BEFORE DELETE ON public.project_specializations
FOR EACH ROW EXECUTE FUNCTION public.protect_used_project_specialization();

CREATE OR REPLACE FUNCTION public.sync_scope_specialization_to_project()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.specialization_id IS NOT NULL THEN
        INSERT INTO public.project_specializations (
            project_id, specialization_id, source
        ) VALUES (
            NEW.project_id, NEW.specialization_id, 'Manual'
        )
        ON CONFLICT (project_id, specialization_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scope_items_sync_project_specialization
    ON public.scope_items;
CREATE TRIGGER scope_items_sync_project_specialization
AFTER INSERT OR UPDATE OF project_id, specialization_id
ON public.scope_items
FOR EACH ROW EXECUTE FUNCTION public.sync_scope_specialization_to_project();

CREATE OR REPLACE FUNCTION public.validate_job_project_specialization()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.specialization_id IS NULL THEN
        RAISE EXCEPTION 'Job specialization is required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.project_specializations project_spec
        WHERE project_spec.project_id = NEW.project_id
          AND project_spec.specialization_id = NEW.specialization_id
    ) THEN
        RAISE EXCEPTION 'Job specialization must be selected on its Project';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_validate_specialization
    ON public.project_jobs;
CREATE TRIGGER project_jobs_validate_specialization
BEFORE INSERT OR UPDATE OF project_id, specialization_id
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.validate_job_project_specialization();

CREATE OR REPLACE FUNCTION public.validate_job_assignment_workflow()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status IN ('In Progress', 'Delivered', 'Revision Required', 'Approved')
       AND NEW.resource_id IS NULL THEN
        RAISE EXCEPTION 'A Resource must be assigned before the Job enters production';
    END IF;
    IF NEW.status = 'Unassigned' AND NEW.resource_id IS NOT NULL THEN
        RAISE EXCEPTION 'An assigned Job cannot return to Unassigned';
    END IF;
    RETURN NEW;
END;
$$;

UPDATE public.project_jobs
SET status = 'Unassigned'
WHERE resource_id IS NULL
  AND status IN ('In Progress', 'Delivered', 'Revision Required', 'Approved');

DROP TRIGGER IF EXISTS project_jobs_validate_assignment_workflow
    ON public.project_jobs;
CREATE TRIGGER project_jobs_validate_assignment_workflow
BEFORE INSERT OR UPDATE OF status, resource_id
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.validate_job_assignment_workflow();

CREATE OR REPLACE FUNCTION public.protect_job_commercial_terms()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF (
        NEW.service_type IS DISTINCT FROM OLD.service_type
        OR NEW.specialization_id IS DISTINCT FROM OLD.specialization_id
        OR NEW.source_language IS DISTINCT FROM OLD.source_language
        OR NEW.target_language IS DISTINCT FROM OLD.target_language
        OR NEW.unit IS DISTINCT FROM OLD.unit
        OR NEW.quantity IS DISTINCT FROM OLD.quantity
    ) AND (
        OLD.resource_id IS NOT NULL
        OR EXISTS (
            SELECT 1 FROM public.job_offers offer
            WHERE offer.job_id = OLD.id
              AND offer.status IN ('Draft', 'Sent', 'Viewed')
        )
    ) THEN
        RAISE EXCEPTION 'Job terms are locked while an active Offer or assignment exists';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_protect_commercial_terms
    ON public.project_jobs;
CREATE TRIGGER project_jobs_protect_commercial_terms
BEFORE UPDATE OF service_type, specialization_id, source_language,
    target_language, unit, quantity
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.protect_job_commercial_terms();

CREATE OR REPLACE FUNCTION public.create_project_with_specializations(p_payload JSONB)
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
BEGIN
    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_account_specializations
        WHERE account_id = v_account_id
    ) THEN
        RAISE EXCEPTION 'Configure at least one specialization on the selected Account';
    END IF;

    IF v_account_id IS NULL
       AND jsonb_array_length(COALESCE(p_payload->'specialization_ids', '[]'::JSONB)) = 0
    THEN
        RAISE EXCEPTION 'Select at least one Project specialization';
    END IF;

    SELECT result.created_project_id, result.created_project_name
    INTO v_id, v_name
    FROM public.create_project(p_payload) result
    LIMIT 1;

    IF v_account_id IS NULL THEN
        INSERT INTO public.project_specializations (
            project_id, specialization_id, source
        )
        SELECT v_id, spec.id, 'Manual'
        FROM jsonb_array_elements_text(p_payload->'specialization_ids') requested(id)
        JOIN public.specializations spec
          ON spec.id = requested.id::UUID AND spec.active
        ON CONFLICT DO NOTHING;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count = 0 THEN
            RAISE EXCEPTION 'Select at least one valid Project specialization';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.project_specializations
        WHERE project_id = v_id
    ) THEN
        RAISE EXCEPTION 'Project specialization is required';
    END IF;

    created_project_id := v_id;
    created_project_name := v_name;
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_with_specializations(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project_with_specializations(JSONB)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.create_job_offer_from_rate(
    p_job_id UUID,
    p_resource_id UUID,
    p_resource_rate_id UUID,
    p_response_due_at TIMESTAMPTZ DEFAULT NULL,
    p_quantity NUMERIC DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_client_identity_disclosed BOOLEAN DEFAULT FALSE,
    p_override BOOLEAN DEFAULT FALSE,
    p_override_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.project_jobs%ROWTYPE;
    v_rate public.resource_rates%ROWTYPE;
    v_offer_id UUID;
BEGIN
    SELECT * INTO v_job
    FROM public.project_jobs
    WHERE id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;

    SELECT * INTO v_rate
    FROM public.resource_rates rate
    WHERE rate.id = p_resource_rate_id
      AND rate.resource_id = p_resource_id
      AND rate.status = 'Approved'
      AND rate.service_type = v_job.service_type
      AND rate.unit = v_job.unit
      AND (rate.source_language IS NULL
           OR rate.source_language = v_job.source_language
           OR v_job.source_language LIKE rate.source_language || ' (%)')
      AND (rate.target_language IS NULL
           OR rate.target_language = v_job.target_language
           OR v_job.target_language LIKE rate.target_language || ' (%)')
      AND (rate.specialization_id IS NULL OR rate.specialization_id = v_job.specialization_id)
      AND (rate.valid_from IS NULL OR rate.valid_from <= CURRENT_DATE)
      AND (rate.valid_to IS NULL OR rate.valid_to >= CURRENT_DATE);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Select an approved matching rate from the Resource profile';
    END IF;

    v_offer_id := public.create_job_offer(
        p_job_id, p_resource_id, p_response_due_at, v_rate.unit,
        COALESCE(p_quantity, v_job.quantity), v_rate.rate, v_rate.currency,
        p_message, p_client_identity_disclosed, p_override, p_override_reason
    );

    UPDATE public.job_offers
    SET resource_rate_id = p_resource_rate_id
    WHERE id = v_offer_id;

    RETURN v_offer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_job_offer_from_rate(
    UUID, UUID, UUID, TIMESTAMPTZ, NUMERIC, TEXT, BOOLEAN, BOOLEAN, TEXT
) TO authenticated;

-- Operational users must use the rate-linked wrapper. It still calls the
-- underlying SECURITY DEFINER function internally, but the browser cannot use
-- that legacy entry point to submit a free-text supplier rate.
REVOKE EXECUTE ON FUNCTION public.create_job_offer(
    UUID, UUID, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC, TEXT, TEXT,
    BOOLEAN, BOOLEAN, TEXT
) FROM authenticated;

CREATE OR REPLACE FUNCTION public.copy_accepted_offer_rate_link()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'Accepted' AND OLD.status IS DISTINCT FROM NEW.status THEN
        UPDATE public.project_jobs
        SET resource_rate_id = NEW.resource_rate_id
        WHERE id = NEW.job_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS job_offers_copy_rate_link ON public.job_offers;
CREATE TRIGGER job_offers_copy_rate_link
AFTER UPDATE OF status ON public.job_offers
FOR EACH ROW EXECUTE FUNCTION public.copy_accepted_offer_rate_link();

COMMIT;
