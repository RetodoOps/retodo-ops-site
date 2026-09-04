-- RetodoOps TMS — Settings language catalogue and Scoop-scoped financial lines.
-- Run once after 028_scoop_financials_and_dashboard.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS public.language_catalog (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL CHECK (btrim(name) <> ''),
    code        TEXT NOT NULL CHECK (upper(btrim(code)) ~ '^[A-Z]{2,3}(-[A-Z]{2})?$'),
    active      BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order  INTEGER NOT NULL DEFAULT 100,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS language_catalog_name_unique_idx
    ON public.language_catalog (lower(btrim(name)));
CREATE UNIQUE INDEX IF NOT EXISTS language_catalog_code_unique_idx
    ON public.language_catalog (upper(btrim(code)));
CREATE INDEX IF NOT EXISTS language_catalog_active_sort_idx
    ON public.language_catalog (active, sort_order, name);

INSERT INTO public.language_catalog (name, code, sort_order) VALUES
('English','EN',10),('English (US)','EN-US',20),('English (UK)','EN-GB',30),
('Bulgarian','BG',40),('Swedish','SV',50),('Danish','DA',60),('Finnish','FI',70),
('Norwegian','NO',80),('Norwegian (Bokmål)','NB',90),('Norwegian (Nynorsk)','NN',100),
('Icelandic','IS',110),('German','DE',120),('French','FR',130),('Spanish','ES',140),
('Italian','IT',150),('Dutch','NL',160),('Polish','PL',170),('Portuguese','PT',180),
('Portuguese (Brazil)','PT-BR',190),('Portuguese (Portugal)','PT-PT',200),
('Russian','RU',210),('Ukrainian','UK',220),('Czech','CS',230),('Slovak','SK',240),
('Hungarian','HU',250),('Romanian','RO',260),('Greek','EL',270),('Turkish','TR',280),
('Estonian','ET',290),('Latvian','LV',300),('Lithuanian','LT',310),('Slovenian','SL',320),
('Croatian','HR',330),('Serbian','SR',340),('Bosnian','BS',350),('Macedonian','MK',360),
('Albanian','SQ',370),('Chinese (Simplified)','ZH-CN',380),
('Chinese (Traditional)','ZH-TW',390),('Japanese','JA',400),('Korean','KO',410),
('Arabic','AR',420),('Hebrew','HE',430),('Hindi','HI',440),('Thai','TH',450),
('Vietnamese','VI',460),('Indonesian','ID',470),('Malay','MS',480)
ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS language_catalog_set_updated_at ON public.language_catalog;
CREATE TRIGGER language_catalog_set_updated_at
BEFORE UPDATE ON public.language_catalog
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.language_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS language_catalog_read ON public.language_catalog;
CREATE POLICY language_catalog_read ON public.language_catalog
FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS language_catalog_admin_manage ON public.language_catalog;
CREATE POLICY language_catalog_admin_manage ON public.language_catalog
FOR ALL TO authenticated
USING (public.current_app_role() = 'admin')
WITH CHECK (public.current_app_role() = 'admin');
GRANT SELECT, INSERT, UPDATE, DELETE ON public.language_catalog TO authenticated;

CREATE OR REPLACE FUNCTION public.tms_language_code(p_language TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT upper(catalog.code) FROM public.language_catalog catalog
         WHERE lower(btrim(catalog.name)) = lower(btrim(COALESCE(p_language,'')))
         LIMIT 1),
        upper(left(regexp_replace(COALESCE(p_language,'XX'),'[^A-Za-z]','','g'),3))
    );
$$;

DROP TRIGGER IF EXISTS specializations_set_updated_at ON public.specializations;
CREATE TRIGGER specializations_set_updated_at
BEFORE UPDATE ON public.specializations
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Save exactly the detailed Client-price lines belonging to one Scoop.
-- Linked rate-card rows preserve their snapshot and allow quantity edits;
-- manual rows remain fully editable. The existing triggers roll the line total
-- into the Scoop and then the sum of active Scoops into the Project.
CREATE OR REPLACE FUNCTION public.save_scoop_financial_lines(
    p_scoop_id UUID,
    p_lines JSONB,
    p_deleted_ids JSONB DEFAULT '[]'::JSONB,
    p_fallback_price NUMERIC DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_scoop public.project_scoops%ROWTYPE;
    v_line JSONB;
    v_id UUID;
    v_existing public.scope_items%ROWTYPE;
    v_description TEXT;
    v_source TEXT;
    v_reason TEXT;
    v_specialization UUID;
    v_rate_id UUID;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    SELECT * INTO v_scoop FROM public.project_scoops
    WHERE id = p_scoop_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Scoop not found'; END IF;
    IF jsonb_typeof(COALESCE(p_lines, '[]'::JSONB)) <> 'array'
       OR jsonb_typeof(COALESCE(p_deleted_ids, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Financial lines must be JSON arrays';
    END IF;

    DELETE FROM public.scope_items line
    WHERE line.project_scoop_id = p_scoop_id
      AND line.id IN (
          SELECT value::UUID
          FROM jsonb_array_elements_text(COALESCE(p_deleted_ids, '[]'::JSONB))
      );

    FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
    LOOP
        v_id := NULLIF(v_line->>'id', '')::UUID;
        v_rate_id := NULLIF(v_line->>'client_rate_item_id', '')::UUID;
        v_description := NULLIF(btrim(v_line->>'description'), '');
        v_source := COALESCE(NULLIF(btrim(v_line->>'rate_source'), ''), 'Manual');
        v_reason := NULLIF(btrim(v_line->>'override_reason'), '');
        v_specialization := NULLIF(v_line->>'specialization_id', '')::UUID;
        IF v_description IS NULL THEN RAISE EXCEPTION 'Every Scoop financial line requires a description'; END IF;
        IF v_specialization IS NULL THEN RAISE EXCEPTION 'Every Scoop financial line requires a specialization'; END IF;
        IF NOT EXISTS (SELECT 1 FROM public.project_specializations link
            WHERE link.project_id = v_scoop.project_id
              AND link.specialization_id = v_specialization) THEN
            RAISE EXCEPTION 'Financial line specialization must belong to the Project';
        END IF;
        IF v_source IN ('Manual','Fixed') AND v_reason IS NULL THEN
            RAISE EXCEPTION 'A manual or fixed Scoop line requires a reason';
        END IF;

        IF v_id IS NOT NULL THEN
            SELECT * INTO v_existing FROM public.scope_items
            WHERE id = v_id AND project_scoop_id = p_scoop_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Scoop financial line not found'; END IF;
            IF v_existing.client_rate_item_id IS NOT NULL THEN
                UPDATE public.scope_items SET
                    quantity = COALESCE(NULLIF(v_line->>'quantity','')::NUMERIC,0),
                    updated_at = NOW()
                WHERE id = v_id;
            ELSE
                UPDATE public.scope_items SET
                    description = v_description,
                    service_type = COALESCE(NULLIF(v_line->>'service_type',''),service_type),
                    specialization_id = v_specialization,
                    cat_band = NULLIF(v_line->>'cat_band',''),
                    quantity = COALESCE(NULLIF(v_line->>'quantity','')::NUMERIC,0),
                    price_unit = COALESCE(NULLIF(v_line->>'price_unit',''),'Source words'),
                    unit_price = COALESCE(NULLIF(v_line->>'unit_price','')::NUMERIC,0),
                    rate_source = v_source,
                    adjustment_type = NULLIF(v_line->>'adjustment_type',''),
                    override_reason = v_reason,
                    sort_order = COALESCE(NULLIF(v_line->>'sort_order','')::INTEGER,sort_order),
                    updated_at = NOW()
                WHERE id = v_id;
            END IF;
        ELSE
            IF v_source IN ('Account','Client') AND v_rate_id IS NULL THEN
                RAISE EXCEPTION 'A linked Client or Account line requires a rate-card row';
            END IF;
            INSERT INTO public.scope_items(
                project_id, project_scoop_id, description, service_type,
                specialization_id, cat_band, quantity, price_unit, unit_price,
                price, rate_source, adjustment_type, override_reason,
                client_rate_item_id, sort_order
            ) VALUES (
                v_scoop.project_id, p_scoop_id, v_description,
                COALESCE(NULLIF(v_line->>'service_type',''),'Other'),
                v_specialization, NULLIF(v_line->>'cat_band',''),
                COALESCE(NULLIF(v_line->>'quantity','')::NUMERIC,0),
                COALESCE(NULLIF(v_line->>'price_unit',''),'Source words'),
                COALESCE(NULLIF(v_line->>'unit_price','')::NUMERIC,0), 0,
                v_source, NULLIF(v_line->>'adjustment_type',''), v_reason,
                v_rate_id, COALESCE(NULLIF(v_line->>'sort_order','')::INTEGER,0)
            );
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM public.scope_items WHERE project_scoop_id = p_scoop_id) THEN
        UPDATE public.project_scoops
        SET price = GREATEST(COALESCE(p_fallback_price,0),0), updated_at = NOW()
        WHERE id = p_scoop_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.save_scoop_financial_lines(UUID, JSONB, JSONB, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_scoop_financial_lines(UUID, JSONB, JSONB, NUMERIC) TO authenticated;

COMMIT;
