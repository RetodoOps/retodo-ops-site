-- RetodoOps TMS — central service catalog and extensible Settings foundation.
-- Run once after 025_inherited_job_terms_scoped_rates_and_financial_rollup.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS public.service_catalog (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL CHECK (btrim(name) <> ''),
    code        TEXT NOT NULL CHECK (upper(code) ~ '^[A-Z0-9]{2,8}$'),
    description TEXT,
    active      BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order  INTEGER NOT NULL DEFAULT 100,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS service_catalog_name_unique_idx
    ON public.service_catalog (lower(btrim(name)));
CREATE UNIQUE INDEX IF NOT EXISTS service_catalog_code_unique_idx
    ON public.service_catalog (upper(btrim(code)));
CREATE INDEX IF NOT EXISTS service_catalog_active_sort_idx
    ON public.service_catalog (active, sort_order, name);

INSERT INTO public.service_catalog (name, code, sort_order) VALUES
    ('Translation', 'TRA', 10),
    ('MTPE', 'MTP', 20),
    ('Proofreading', 'PRF', 30),
    ('Independent Review', 'REV', 40),
    ('LQA', 'LQA', 50),
    ('Terminology', 'TER', 60),
    ('DTP', 'DTP', 70),
    ('Transcription', 'TRS', 80),
    ('Subtitling', 'SUB', 90),
    ('Voice-over', 'VO', 100),
    ('Transcreation', 'TRC', 110),
    ('Project Management', 'PM', 120),
    ('Other', 'OTH', 900)
ON CONFLICT DO NOTHING;

-- Preserve any service names already used before the catalog existed.
WITH used_services AS (
    SELECT service_type AS name FROM public.resource_services
    UNION SELECT service_type FROM public.resource_rates
    UNION SELECT service_type FROM public.client_rate_items
    UNION SELECT service_type FROM public.quote_items
    UNION SELECT service_type FROM public.scope_items
    UNION SELECT service_type FROM public.project_jobs
), missing AS (
    SELECT DISTINCT btrim(name) AS name
    FROM used_services
    WHERE NULLIF(btrim(name), '') IS NOT NULL
      AND lower(btrim(name)) <> 'quote discount'
      AND NOT EXISTS (
          SELECT 1 FROM public.service_catalog catalog
          WHERE lower(btrim(catalog.name)) = lower(btrim(used_services.name))
      )
)
INSERT INTO public.service_catalog (name, code, sort_order)
SELECT name, 'C' || upper(substr(md5(name), 1, 7)), 800
FROM missing
ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS service_catalog_set_updated_at ON public.service_catalog;
CREATE TRIGGER service_catalog_set_updated_at
BEFORE UPDATE ON public.service_catalog
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.service_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_catalog_read ON public.service_catalog;
CREATE POLICY service_catalog_read ON public.service_catalog
FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS service_catalog_admin_manage ON public.service_catalog;
CREATE POLICY service_catalog_admin_manage ON public.service_catalog
FOR ALL TO authenticated
USING (public.current_app_role() = 'admin')
WITH CHECK (public.current_app_role() = 'admin');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.service_catalog TO authenticated;

CREATE OR REPLACE FUNCTION public.is_supported_tms_service(p_service_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.service_catalog catalog
        WHERE catalog.active
          AND lower(btrim(catalog.name)) = lower(btrim(COALESCE(p_service_type, '')))
    );
$$;

CREATE OR REPLACE FUNCTION public.job_service_code(p_service_type TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((
        SELECT upper(catalog.code)
        FROM public.service_catalog catalog
        WHERE lower(btrim(catalog.name)) = lower(btrim(COALESCE(p_service_type, '')))
        LIMIT 1
    ), 'OTH');
$$;

CREATE OR REPLACE FUNCTION public.validate_resource_service_catalog()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.service_type IS NOT DISTINCT FROM OLD.service_type THEN
        RETURN NEW;
    END IF;
    IF NOT public.is_supported_tms_service(NEW.service_type) THEN
        RAISE EXCEPTION 'Select an active service from Settings';
    END IF;
    RETURN NEW;
END;
$$;

-- Saving a Supplier rate for a catalog service also records that service as
-- a Resource capability. This keeps the full catalog visible in the rate form
-- without weakening the capability validation in save_resource_rate_card().
CREATE OR REPLACE FUNCTION public.save_scoped_resource_rate_card(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base_id UUID;
    v_resource_id UUID := NULLIF(p_payload->>'resource_id', '')::UUID;
    v_account_id UUID := NULLIF(p_payload->>'account_id', '')::UUID;
    v_service TEXT := NULLIF(btrim(p_payload->>'service_type'), '');
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_resource_id IS NULL OR v_service IS NULL THEN
        RAISE EXCEPTION 'Resource and service are required';
    END IF;
    IF NOT public.is_supported_tms_service(v_service) THEN
        RAISE EXCEPTION 'Select an active service from Settings';
    END IF;
    IF v_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_accounts account
        WHERE account.id = v_account_id AND account.active
    ) THEN
        RAISE EXCEPTION 'Select an active Account for this Supplier rate card';
    END IF;

    INSERT INTO public.resource_services (
        resource_id, service_type, approved, notes
    ) VALUES (
        v_resource_id, v_service, TRUE, 'Added from Supplier rate card'
    ) ON CONFLICT (resource_id, service_type) DO NOTHING;

    v_base_id := public.save_resource_rate_card(p_payload);

    UPDATE public.resource_rates
    SET account_id = v_account_id,
        updated_at = NOW()
    WHERE id = v_base_id OR base_rate_id = v_base_id;

    RETURN v_base_id;
END;
$$;

REVOKE ALL ON FUNCTION public.save_scoped_resource_rate_card(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_scoped_resource_rate_card(JSONB) TO authenticated;

COMMIT;
