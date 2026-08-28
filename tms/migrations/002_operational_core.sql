-- Retodo Ops TMS — normalized operational core
-- Run after 001_operational_foundation.sql.
--
-- This migration is deliberately additive. It preserves the original proof-of-
-- concept columns while adding the normalized records required by the approved
-- workflow. The frontend can therefore be migrated module by module.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Shared helpers and roles
-- ---------------------------------------------------------------------------

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('admin', 'pm', 'qa', 'client_relations', 'resource', 'user'));

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(public.current_app_role() = 'admin', FALSE);
$$;

CREATE OR REPLACE FUNCTION public.is_company_user()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        public.current_app_role() IN ('admin', 'pm', 'qa', 'client_relations'),
        FALSE
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_operations()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        public.current_app_role() IN ('admin', 'pm', 'client_relations'),
        FALSE
    );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_company_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_manage_operations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_company_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_operations() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Clients, accounts, contacts and rate cards
-- ---------------------------------------------------------------------------

ALTER TABLE public.clients
    ADD COLUMN IF NOT EXISTS code                    TEXT,
    ADD COLUMN IF NOT EXISTS client_type             TEXT NOT NULL DEFAULT 'LSP',
    ADD COLUMN IF NOT EXISTS legal_name              TEXT,
    ADD COLUMN IF NOT EXISTS website                 TEXT,
    ADD COLUMN IF NOT EXISTS country_code            TEXT,
    ADD COLUMN IF NOT EXISTS default_currency        TEXT NOT NULL DEFAULT 'EUR',
    ADD COLUMN IF NOT EXISTS default_payment_days    INTEGER,
    ADD COLUMN IF NOT EXISTS default_cat_system      TEXT,
    ADD COLUMN IF NOT EXISTS instructions            TEXT,
    ADD COLUMN IF NOT EXISTS confidentiality_notes   TEXT,
    ADD COLUMN IF NOT EXISTS restriction_status      TEXT NOT NULL DEFAULT 'Active',
    ADD COLUMN IF NOT EXISTS restriction_reason      TEXT,
    ADD COLUMN IF NOT EXISTS updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.clients
    DROP CONSTRAINT IF EXISTS clients_client_type_check,
    DROP CONSTRAINT IF EXISTS clients_restriction_status_check;

ALTER TABLE public.clients
    ADD CONSTRAINT clients_client_type_check
        CHECK (client_type IN ('LSP', 'Direct')),
    ADD CONSTRAINT clients_restriction_status_check
        CHECK (restriction_status IN ('Active', 'On Hold', 'Do not work with'));

CREATE UNIQUE INDEX IF NOT EXISTS clients_code_unique_idx
    ON public.clients (upper(code)) WHERE code IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.specializations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    code        TEXT,
    active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS specializations_name_unique_idx
    ON public.specializations (lower(name));

INSERT INTO public.specializations (name, code)
VALUES
    ('IT / Technology / Software', 'IT'),
    ('Medical', 'MED'),
    ('Instructions for Use (IFU)', 'IFU'),
    ('Patents', 'PAT'),
    ('Legal', 'LEG'),
    ('Life Sciences', 'LS'),
    ('Marketing', 'MKT'),
    ('Finance', 'FIN'),
    ('Technical', 'TECH'),
    ('Automotive', 'AUTO'),
    ('General', 'GEN')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.client_accounts (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id                  UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    name                       TEXT NOT NULL,
    code                       TEXT,
    blind_cv_label             TEXT,
    allow_name_in_blind_cv     BOOLEAN NOT NULL DEFAULT FALSE,
    website                    TEXT,
    default_source_language    TEXT,
    default_cat_system         TEXT,
    default_production_mode    TEXT NOT NULL DEFAULT 'Not selected'
        CHECK (default_production_mode IN (
            'Not selected', 'Client CAT', 'Retodo memoQ', 'File workflow'
        )),
    instructions               TEXT,
    terminology_notes          TEXT,
    communication_boundaries   TEXT,
    confidentiality_notes      TEXT,
    restriction_status         TEXT NOT NULL DEFAULT 'Active'
        CHECK (restriction_status IN ('Active', 'On Hold', 'Do not work with')),
    restriction_reason         TEXT,
    active                     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (client_id, name)
);

CREATE TABLE IF NOT EXISTS public.client_account_specializations (
    account_id         UUID NOT NULL REFERENCES public.client_accounts(id) ON DELETE CASCADE,
    specialization_id  UUID NOT NULL REFERENCES public.specializations(id),
    is_default         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, specialization_id)
);

CREATE TABLE IF NOT EXISTS public.client_contacts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id       UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    account_id      UUID REFERENCES public.client_accounts(id) ON DELETE SET NULL,
    full_name       TEXT NOT NULL,
    job_title       TEXT,
    email           TEXT,
    phone           TEXT,
    is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.client_billing_entities (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id               UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    name                    TEXT NOT NULL,
    legal_name              TEXT NOT NULL,
    address_line_1          TEXT NOT NULL,
    address_line_2          TEXT,
    city                    TEXT NOT NULL,
    postal_code             TEXT,
    region                  TEXT,
    country_code            TEXT NOT NULL,
    vat_number              TEXT,
    registration_number     TEXT,
    billing_email           TEXT,
    default_currency        TEXT NOT NULL DEFAULT 'EUR',
    payment_terms_days      INTEGER,
    invoice_notes           TEXT,
    is_default              BOOLEAN NOT NULL DEFAULT FALSE,
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (client_id, name)
);

CREATE UNIQUE INDEX IF NOT EXISTS client_billing_entities_one_default_idx
    ON public.client_billing_entities(client_id)
    WHERE is_default;

CREATE OR REPLACE FUNCTION public.set_single_default_billing_entity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.is_default THEN
        UPDATE public.client_billing_entities
        SET is_default = FALSE
        WHERE client_id = NEW.client_id
          AND id IS DISTINCT FROM NEW.id
          AND is_default;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS client_billing_entities_single_default
ON public.client_billing_entities;
CREATE TRIGGER client_billing_entities_single_default
BEFORE INSERT OR UPDATE OF is_default ON public.client_billing_entities
FOR EACH ROW EXECUTE FUNCTION public.set_single_default_billing_entity();

CREATE OR REPLACE FUNCTION public.validate_selected_billing_entity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.billing_entity_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.client_billing_entities entity
           WHERE entity.id = NEW.billing_entity_id
             AND entity.client_id = NEW.client_id
       ) THEN
        RAISE EXCEPTION 'The selected Billing Entity does not belong to this Client';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_client_relations()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_accounts account
        WHERE account.id = NEW.account_id
          AND account.client_id = NEW.client_id
          AND account.active
          AND account.restriction_status = 'Active'
    ) THEN
        RAISE EXCEPTION 'The selected Account is unavailable or does not belong to this Client';
    END IF;
    IF NEW.contact_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_contacts contact
        WHERE contact.id = NEW.contact_id
          AND contact.client_id = NEW.client_id
          AND contact.active
    ) THEN
        RAISE EXCEPTION 'The selected Contact is unavailable or does not belong to this Client';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.client_rate_cards (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id       UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    account_id      UUID REFERENCES public.client_accounts(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    currency        TEXT NOT NULL DEFAULT 'EUR',
    valid_from      DATE,
    valid_to        DATE,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.client_rate_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_card_id        UUID NOT NULL REFERENCES public.client_rate_cards(id) ON DELETE CASCADE,
    source_language     TEXT,
    requested_deadline  TIMESTAMPTZ,
    target_language     TEXT,
    service_type        TEXT NOT NULL,
    specialization_id   UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    unit                TEXT NOT NULL CHECK (unit IN (
        'Source words', 'Target words', 'Hours', 'Pages', 'Minutes', 'Fixed fee'
    )),
    cat_band            TEXT,
    rate                NUMERIC(14, 4) NOT NULL,
    minimum_fee         NUMERIC(14, 2),
    notes               TEXT,
    accepted_by         UUID REFERENCES public.profiles(id),
    accepted_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Quotes and accepted work
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.quotes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_number        TEXT NOT NULL UNIQUE,
    client_id           UUID NOT NULL REFERENCES public.clients(id),
    account_id          UUID REFERENCES public.client_accounts(id) ON DELETE SET NULL,
    contact_id          UUID REFERENCES public.client_contacts(id) ON DELETE SET NULL,
    billing_entity_id   UUID REFERENCES public.client_billing_entities(id) ON DELETE SET NULL,
    client_reference    TEXT,
    email_reference     TEXT,
    title               TEXT,
    source_language     TEXT,
    status              TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
        'Draft', 'Awaiting Client', 'Revision Requested', 'Accepted',
        'Declined', 'Expired', 'Cancelled'
    )),
    valid_until         DATE NOT NULL DEFAULT (CURRENT_DATE + 30),
    currency            TEXT NOT NULL DEFAULT 'EUR',
    subtotal            NUMERIC(14, 2) NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(14, 2) NOT NULL DEFAULT 0,
    total               NUMERIC(14, 2) NOT NULL DEFAULT 0,
    notes               TEXT,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.quote_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_id            UUID NOT NULL REFERENCES public.quotes(id) ON DELETE CASCADE,
    target_language     TEXT NOT NULL,
    target_language_code TEXT NOT NULL,
    service_type        TEXT NOT NULL,
    specialization_id   UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    quantity            NUMERIC(14, 3),
    unit                TEXT CHECK (unit IN (
        'Source words', 'Target words', 'Hours', 'Pages', 'Minutes', 'Fixed fee'
    )),
    cat_band            TEXT,
    unit_price          NUMERIC(14, 4),
    amount              NUMERIC(14, 2) NOT NULL DEFAULT 0,
    rate_source         TEXT CHECK (rate_source IN ('Account', 'Client', 'Manual', 'Fixed')),
    override_reason     TEXT,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.quote_number_sequences (
    sequence_year   INTEGER PRIMARY KEY,
    next_number     INTEGER NOT NULL CHECK (next_number > 0),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.quote_number_sequences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quote_number_sequences FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_quote_number(p_quote_date DATE DEFAULT CURRENT_DATE)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_year      INTEGER := EXTRACT(YEAR FROM COALESCE(p_quote_date, CURRENT_DATE))::INTEGER;
    v_number    INTEGER;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    INSERT INTO public.quote_number_sequences (sequence_year, next_number)
    VALUES (v_year, 2)
    ON CONFLICT (sequence_year) DO UPDATE
    SET next_number = public.quote_number_sequences.next_number + 1,
        updated_at = NOW()
    RETURNING next_number - 1 INTO v_number;

    RETURN 'Q-' || v_year::TEXT || '-' || lpad(v_number::TEXT, 4, '0');
END;
$$;

REVOKE ALL ON FUNCTION public.next_quote_number(DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_quote_number(DATE) TO authenticated;

CREATE OR REPLACE FUNCTION public.recalculate_quote_totals()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_quote_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_quote_id := OLD.quote_id;
    ELSE
        v_quote_id := NEW.quote_id;
    END IF;
    UPDATE public.quotes quote
    SET subtotal = totals.subtotal,
        total = GREATEST(totals.subtotal - quote.discount_amount, 0),
        updated_at = NOW()
    FROM (
        SELECT COALESCE(sum(amount), 0)::NUMERIC(14, 2) AS subtotal
        FROM public.quote_items
        WHERE quote_id = v_quote_id
    ) totals
    WHERE quote.id = v_quote_id;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quote_items_recalculate_totals ON public.quote_items;
CREATE TRIGGER quote_items_recalculate_totals
AFTER INSERT OR UPDATE OF amount OR DELETE ON public.quote_items
FOR EACH ROW EXECUTE FUNCTION public.recalculate_quote_totals();

CREATE OR REPLACE FUNCTION public.set_quote_total()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.total := GREATEST(COALESCE(NEW.subtotal, 0) - COALESCE(NEW.discount_amount, 0), 0);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quotes_set_total ON public.quotes;
CREATE TRIGGER quotes_set_total
BEFORE INSERT OR UPDATE OF subtotal, discount_amount ON public.quotes
FOR EACH ROW EXECUTE FUNCTION public.set_quote_total();

CREATE OR REPLACE FUNCTION public.protect_accepted_quote()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_quote_id UUID;
    v_status TEXT;
BEGIN
    IF TG_TABLE_NAME = 'quotes' THEN
        IF OLD.status = 'Accepted' THEN
            RAISE EXCEPTION 'Accepted quotes are locked; create a revision instead';
        END IF;
    ELSE
        v_quote_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.quote_id ELSE NEW.quote_id END;
        SELECT status INTO v_status FROM public.quotes WHERE id = v_quote_id;
        IF v_status = 'Accepted' THEN
            RAISE EXCEPTION 'Items on an accepted quote are locked';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quotes_protect_accepted ON public.quotes;
CREATE TRIGGER quotes_protect_accepted
BEFORE UPDATE OR DELETE ON public.quotes
FOR EACH ROW EXECUTE FUNCTION public.protect_accepted_quote();

DROP TRIGGER IF EXISTS quote_items_protect_accepted ON public.quote_items;
CREATE TRIGGER quote_items_protect_accepted
BEFORE INSERT OR UPDATE OR DELETE ON public.quote_items
FOR EACH ROW EXECUTE FUNCTION public.protect_accepted_quote();

DROP TRIGGER IF EXISTS quotes_validate_billing_entity ON public.quotes;
CREATE TRIGGER quotes_validate_billing_entity
BEFORE INSERT OR UPDATE OF client_id, billing_entity_id ON public.quotes
FOR EACH ROW EXECUTE FUNCTION public.validate_selected_billing_entity();

DROP TRIGGER IF EXISTS quotes_validate_client_relations ON public.quotes;
CREATE TRIGGER quotes_validate_client_relations
BEFORE INSERT OR UPDATE OF client_id, account_id, contact_id ON public.quotes
FOR EACH ROW EXECUTE FUNCTION public.validate_client_relations();

-- ---------------------------------------------------------------------------
-- Projects and naming
-- ---------------------------------------------------------------------------

ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_status_check;

UPDATE public.projects SET status = 'Ready for QA'       WHERE status = 'QA Ready';
UPDATE public.projects SET status = 'Waiting'            WHERE status = 'QA Issues';
UPDATE public.projects SET status = 'Ready to Deliver'   WHERE status IN ('PM Ready', 'Delivery');
UPDATE public.projects SET status = 'Delivered to Client' WHERE status = 'Completed';

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS display_name             TEXT,
    ADD COLUMN IF NOT EXISTS project_date             DATE NOT NULL DEFAULT CURRENT_DATE,
    ADD COLUMN IF NOT EXISTS client_reference         TEXT,
    ADD COLUMN IF NOT EXISTS client_reference_received_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS client_reference_updated_by UUID REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS email_reference          TEXT,
    ADD COLUMN IF NOT EXISTS account_id               UUID REFERENCES public.client_accounts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS contact_id               UUID REFERENCES public.client_contacts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS billing_entity_id        UUID REFERENCES public.client_billing_entities(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS quote_id                 UUID REFERENCES public.quotes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS source_language_code     TEXT,
    ADD COLUMN IF NOT EXISTS target_language_code     TEXT,
    ADD COLUMN IF NOT EXISTS cat_system               TEXT,
    ADD COLUMN IF NOT EXISTS production_mode          TEXT NOT NULL DEFAULT 'Not selected',
    ADD COLUMN IF NOT EXISTS client_instructions      TEXT,
    ADD COLUMN IF NOT EXISTS waiting_reason           TEXT,
    ADD COLUMN IF NOT EXISTS waiting_follow_up_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS financial_status         TEXT NOT NULL DEFAULT 'Not Ready',
    ADD COLUMN IF NOT EXISTS issue_status             TEXT,
    ADD COLUMN IF NOT EXISTS expense                  NUMERIC(14, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS margin_amount            NUMERIC(14, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS price_source             TEXT,
    ADD COLUMN IF NOT EXISTS price_override_reason    TEXT,
    ADD COLUMN IF NOT EXISTS created_by               UUID REFERENCES public.profiles(id);

UPDATE public.projects
SET display_name = project_number
WHERE display_name IS NULL;

ALTER TABLE public.projects
    ALTER COLUMN display_name SET NOT NULL,
    DROP CONSTRAINT IF EXISTS projects_new_status_check,
    DROP CONSTRAINT IF EXISTS projects_financial_status_check,
    DROP CONSTRAINT IF EXISTS projects_issue_status_check,
    DROP CONSTRAINT IF EXISTS projects_price_source_check,
    DROP CONSTRAINT IF EXISTS projects_production_mode_check;

ALTER TABLE public.projects
    ADD CONSTRAINT projects_new_status_check CHECK (status IN (
        'Assign', 'Ongoing', 'Ready for QA', 'Waiting', 'Ready to Deliver',
        'Delivered to Client', 'Approved'
    )),
    ADD CONSTRAINT projects_financial_status_check CHECK (financial_status IN (
        'Not Ready', 'Ready to Invoice', 'Invoiced', 'Partially Paid', 'Paid',
        'Overdue', 'Disputed', 'Cancelled', 'Credited'
    )),
    ADD CONSTRAINT projects_issue_status_check CHECK (
        issue_status IS NULL OR issue_status IN (
            'Issue Reported', 'Investigating', 'Correction Requested',
            'Corrected', 'Resolved'
        )
    ),
    ADD CONSTRAINT projects_price_source_check CHECK (
        price_source IS NULL OR price_source IN ('Account', 'Client', 'Manual', 'Fixed')
    ),
    ADD CONSTRAINT projects_production_mode_check CHECK (
        production_mode IN ('Not selected', 'Client CAT', 'Retodo memoQ', 'File workflow')
    );

CREATE UNIQUE INDEX IF NOT EXISTS projects_display_name_unique_idx
    ON public.projects(display_name);

DROP TRIGGER IF EXISTS projects_validate_billing_entity ON public.projects;
CREATE TRIGGER projects_validate_billing_entity
BEFORE INSERT OR UPDATE OF client_id, billing_entity_id ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.validate_selected_billing_entity();

DROP TRIGGER IF EXISTS projects_validate_client_relations ON public.projects;
CREATE TRIGGER projects_validate_client_relations
BEFORE INSERT OR UPDATE OF client_id, account_id, contact_id ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.validate_client_relations();

CREATE TABLE IF NOT EXISTS public.project_specializations (
    project_id          UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    specialization_id   UUID NOT NULL REFERENCES public.specializations(id),
    source              TEXT NOT NULL DEFAULT 'Manual'
        CHECK (source IN ('Account default', 'Manual')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (project_id, specialization_id)
);

CREATE OR REPLACE FUNCTION public.safe_code(p_value TEXT, p_fallback TEXT DEFAULT 'NA')
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
    SELECT COALESCE(NULLIF(upper(regexp_replace(p_value, '[^A-Za-z0-9]+', '', 'g')), ''), p_fallback);
$$;

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
    v_base        TEXT;
    v_candidate   TEXT;
    v_suffix      INTEGER := 1;
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

    IF v_client_code IS NULL THEN
        RAISE EXCEPTION 'Client not found';
    END IF;

    v_base := to_char(COALESCE(p_project_date, CURRENT_DATE), 'YYMMDD')
        || '_' || v_client_code
        || '_' || public.safe_code(p_target_code, 'XX')
        || '_' || CASE
            WHEN NULLIF(btrim(p_client_reference), '') IS NULL THEN 'NOREF'
            ELSE left(public.safe_code(p_client_reference, 'NOREF'), 40)
        END;

    PERFORM pg_advisory_xact_lock(hashtext(v_base));
    v_candidate := v_base;

    WHILE EXISTS (
        SELECT 1 FROM public.projects WHERE display_name = v_candidate
    ) LOOP
        v_suffix := v_suffix + 1;
        v_candidate := v_base || '_' || lpad(v_suffix::TEXT, 2, '0');
    END LOOP;

    RETURN v_candidate;
END;
$$;

REVOKE ALL ON FUNCTION public.next_project_display_name(UUID, TEXT, TEXT, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_project_display_name(UUID, TEXT, TEXT, DATE) TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_account_project_specializations()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.account_id IS DISTINCT FROM OLD.account_id THEN
        DELETE FROM public.project_specializations
        WHERE project_id = NEW.id AND source = 'Account default';

        IF NEW.account_id IS NOT NULL THEN
            INSERT INTO public.project_specializations (
                project_id, specialization_id, source
            )
            SELECT NEW.id, cas.specialization_id, 'Account default'
            FROM public.client_account_specializations cas
            WHERE cas.account_id = NEW.account_id AND cas.is_default
            ON CONFLICT (project_id, specialization_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_sync_account_specializations ON public.projects;
CREATE TRIGGER projects_sync_account_specializations
AFTER INSERT OR UPDATE OF account_id ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.sync_account_project_specializations();

CREATE OR REPLACE FUNCTION public.apply_project_workflow_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'Waiting'
       AND (NULLIF(btrim(NEW.waiting_reason), '') IS NULL
            OR NEW.waiting_follow_up_at IS NULL) THEN
        RAISE EXCEPTION 'Waiting status requires a reason and follow-up date';
    END IF;

    IF NEW.status = 'Approved' AND NEW.financial_status = 'Not Ready' THEN
        NEW.financial_status := 'Ready to Invoice';
    END IF;

    NEW.margin_amount := COALESCE(NEW.price, 0) - COALESCE(NEW.expense, 0);
    NEW.scoop_margin := CASE
        WHEN COALESCE(NEW.price, 0) = 0 THEN 0
        ELSE round(((NEW.price - COALESCE(NEW.expense, 0)) / NEW.price * 100)::NUMERIC, 2)
    END;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_apply_workflow_rules ON public.projects;
CREATE TRIGGER projects_apply_workflow_rules
BEFORE INSERT OR UPDATE OF status, waiting_reason, waiting_follow_up_at, price, expense
ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.apply_project_workflow_rules();

CREATE OR REPLACE FUNCTION public.create_project(p_payload JSONB)
RETURNS TABLE (created_project_id UUID, created_project_name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_client_id UUID := (p_payload->>'client_id')::UUID;
    v_account_id UUID := NULLIF(p_payload->>'account_id', '')::UUID;
    v_contact_id UUID := NULLIF(p_payload->>'contact_id', '')::UUID;
    v_billing_entity_id UUID := NULLIF(p_payload->>'billing_entity_id', '')::UUID;
    v_project_date DATE := COALESCE(NULLIF(p_payload->>'project_date', '')::DATE, CURRENT_DATE);
    v_client_reference TEXT := NULLIF(btrim(p_payload->>'client_reference'), '');
    v_target_code TEXT := NULLIF(btrim(p_payload->>'target_language_code'), '');
    v_name TEXT;
    v_id UUID;
    v_account public.client_accounts%ROWTYPE;
    v_client public.clients%ROWTYPE;
    v_price NUMERIC(14, 2) := COALESCE(NULLIF(p_payload->>'price', '')::NUMERIC, 0);
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;
    IF v_client_id IS NULL OR v_target_code IS NULL
       OR NULLIF(btrim(p_payload->>'target_language'), '') IS NULL THEN
        RAISE EXCEPTION 'Client and target language are required';
    END IF;

    SELECT * INTO v_client FROM public.clients WHERE id = v_client_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Client not found'; END IF;
    IF v_client.restriction_status <> 'Active' THEN
        RAISE EXCEPTION 'Client is %: %', v_client.restriction_status,
            COALESCE(v_client.restriction_reason, 'no reason recorded');
    END IF;

    IF v_account_id IS NOT NULL THEN
        SELECT * INTO v_account
        FROM public.client_accounts
        WHERE id = v_account_id AND client_id = v_client_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Account does not belong to the selected Client'; END IF;
        IF v_account.restriction_status <> 'Active' OR NOT v_account.active THEN
            RAISE EXCEPTION 'Account is unavailable: %',
                COALESCE(v_account.restriction_reason, v_account.restriction_status);
        END IF;
    END IF;

    IF v_contact_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.client_contacts
        WHERE id = v_contact_id AND client_id = v_client_id AND active
    ) THEN RAISE EXCEPTION 'Contact does not belong to the selected Client'; END IF;

    v_name := public.next_project_display_name(
        v_client_id, v_target_code, v_client_reference, v_project_date
    );

    INSERT INTO public.projects (
        project_number, display_name, project_date, client_id, account_id,
        contact_id, billing_entity_id, client_reference, email_reference,
        source_language, source_language_code, target_language,
        target_language_code, deadline, project_manager, qa_specialist,
        project_coordinator, status, project_type, price, currency,
        price_source, price_override_reason, po_number, missing_po,
        production_mode, cat_system, client_instructions, urgent,
        upcoming, created_by
    ) VALUES (
        v_name, v_name, v_project_date, v_client_id, v_account_id,
        v_contact_id, v_billing_entity_id, v_client_reference,
        NULLIF(btrim(p_payload->>'email_reference'), ''),
        NULLIF(btrim(p_payload->>'source_language'), ''),
        NULLIF(btrim(p_payload->>'source_language_code'), ''),
        btrim(p_payload->>'target_language'), v_target_code,
        NULLIF(p_payload->>'deadline', '')::TIMESTAMPTZ,
        NULLIF(btrim(p_payload->>'project_manager'), ''),
        NULLIF(btrim(p_payload->>'qa_specialist'), ''),
        NULLIF(btrim(p_payload->>'project_coordinator'), ''),
        COALESCE(NULLIF(p_payload->>'status', ''), 'Assign'),
        NULLIF(btrim(p_payload->>'project_type'), ''), v_price,
        COALESCE(NULLIF(p_payload->>'currency', ''), v_client.default_currency, 'EUR'),
        NULLIF(p_payload->>'price_source', ''),
        NULLIF(btrim(p_payload->>'price_override_reason'), ''),
        NULLIF(btrim(p_payload->>'po_number'), ''),
        COALESCE((p_payload->>'missing_po')::BOOLEAN, FALSE),
        COALESCE(NULLIF(p_payload->>'production_mode', ''),
                 CASE WHEN v_account_id IS NOT NULL THEN v_account.default_production_mode END,
                 'Not selected'),
        COALESCE(NULLIF(btrim(p_payload->>'cat_system'), ''),
                 CASE WHEN v_account_id IS NOT NULL THEN v_account.default_cat_system END,
                 v_client.default_cat_system),
        COALESCE(NULLIF(btrim(p_payload->>'client_instructions'), ''),
                 CASE WHEN v_account_id IS NOT NULL THEN v_account.instructions END,
                 v_client.instructions),
        COALESCE((p_payload->>'urgent')::BOOLEAN, FALSE),
        COALESCE((p_payload->>'upcoming')::BOOLEAN, FALSE),
        auth.uid()
    ) RETURNING id INTO v_id;

    created_project_id := v_id;
    created_project_name := v_name;
    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_project(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_quote(p_quote_id UUID)
RETURNS TABLE (created_project_id UUID, created_project_name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_quote public.quotes%ROWTYPE;
    v_target RECORD;
    v_project_id UUID;
    v_project_name TEXT;
    v_target_discount NUMERIC(14, 2);
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational role required';
    END IF;

    SELECT * INTO v_quote
    FROM public.quotes
    WHERE id = p_quote_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quote not found';
    END IF;

    IF v_quote.status = 'Accepted' THEN
        RETURN QUERY
        SELECT project.id, project.display_name
        FROM public.projects project
        WHERE project.quote_id = p_quote_id
        ORDER BY project.display_name;
        RETURN;
    END IF;

    IF v_quote.status IN ('Declined', 'Expired', 'Cancelled') THEN
        RAISE EXCEPTION 'A quote with status % cannot be accepted', v_quote.status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.quote_items WHERE quote_id = p_quote_id) THEN
        RAISE EXCEPTION 'Add at least one quote item before accepting the quote';
    END IF;

    FOR v_target IN
        SELECT
            item.target_language,
            item.target_language_code,
            sum(item.amount)::NUMERIC(14, 2) AS target_total,
            string_agg(DISTINCT item.service_type, ', ' ORDER BY item.service_type) AS services
        FROM public.quote_items item
        WHERE item.quote_id = p_quote_id
        GROUP BY item.target_language, item.target_language_code
        ORDER BY item.target_language
    LOOP
        v_target_discount := CASE
            WHEN v_quote.subtotal > 0
                THEN round(v_quote.discount_amount * v_target.target_total / v_quote.subtotal, 2)
            ELSE 0
        END;
        v_project_name := public.next_project_display_name(
            v_quote.client_id,
            v_target.target_language_code,
            v_quote.client_reference,
            CURRENT_DATE
        );

        INSERT INTO public.projects (
            project_number, display_name, project_date, client_id, account_id,
            contact_id, billing_entity_id, quote_id, client_reference,
            email_reference, source_language, target_language,
            target_language_code, deadline, project_type, price, currency,
            status, created_by
        ) VALUES (
            v_project_name, v_project_name, CURRENT_DATE, v_quote.client_id,
            v_quote.account_id, v_quote.contact_id, v_quote.billing_entity_id,
            v_quote.id, v_quote.client_reference, v_quote.email_reference,
            v_quote.source_language, v_target.target_language,
            v_target.target_language_code, v_quote.requested_deadline,
            v_target.services, v_target.target_total - v_target_discount, v_quote.currency,
            'Assign', auth.uid()
        )
        RETURNING id INTO v_project_id;

        INSERT INTO public.scope_items (
            project_id, service_type, specialization_id, quantity, price_unit,
            cat_band, unit_price, price, rate_source, override_reason, sort_order
        )
        SELECT
            v_project_id, item.service_type, item.specialization_id,
            item.quantity, item.unit, item.cat_band, item.unit_price,
            item.amount, item.rate_source, item.override_reason, item.sort_order
        FROM public.quote_items item
        WHERE item.quote_id = p_quote_id
          AND item.target_language = v_target.target_language
          AND item.target_language_code = v_target.target_language_code;

        IF v_target_discount > 0 THEN
            INSERT INTO public.scope_items (
                project_id, service_type, quantity, price_unit, unit_price,
                price, rate_source, override_reason, sort_order
            ) VALUES (
                v_project_id, 'Quote discount', 1, 'Fixed fee',
                -v_target_discount, -v_target_discount, 'Manual',
                'Allocated proportionally from ' || v_quote.quote_number,
                9999
            );
        END IF;

        created_project_id := v_project_id;
        created_project_name := v_project_name;
        RETURN NEXT;
    END LOOP;

    UPDATE public.quotes
    SET status = 'Accepted', accepted_by = auth.uid(), accepted_at = NOW(), updated_at = NOW()
    WHERE id = p_quote_id;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_quote(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_quote(UUID) TO authenticated;

-- Commercial lines from the proof of concept receive the normalized fields.
ALTER TABLE public.scope_items
    ADD COLUMN IF NOT EXISTS service_type       TEXT,
    ADD COLUMN IF NOT EXISTS specialization_id UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS cat_band           TEXT,
    ADD COLUMN IF NOT EXISTS rate_source        TEXT,
    ADD COLUMN IF NOT EXISTS override_reason    TEXT,
    ADD COLUMN IF NOT EXISTS sort_order         INTEGER NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- Resources and portal foundation
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.resources (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    internal_number            TEXT NOT NULL UNIQUE,
    profile_id                 UUID UNIQUE REFERENCES public.profiles(id) ON DELETE SET NULL,
    resource_type              TEXT NOT NULL DEFAULT 'Freelancer'
        CHECK (resource_type IN ('Freelancer', 'Company', 'Internal')),
    classification             TEXT NOT NULL DEFAULT 'D — Not assessed' CHECK (classification IN (
        'A — Preferred', 'B — Proven / previously used',
        'C — Approved / no recorded work', 'D — Not assessed',
        'Hold — Inactive', 'Hold — Unavailable', 'Hold — Terms not accepted',
        'Do not use'
    )),
    assignment_approved        BOOLEAN NOT NULL DEFAULT FALSE,
    portal_status              TEXT NOT NULL DEFAULT 'Not invited' CHECK (portal_status IN (
        'Not invited', 'Invited', 'Active', 'Financial only', 'Read-only', 'Closed'
    )),
    legal_name                 TEXT,
    company_name               TEXT,
    initials                   TEXT,
    nationality                TEXT,
    country_of_residence       TEXT,
    email                      TEXT,
    phone                      TEXT,
    linkedin_url               TEXT,
    website                    TEXT,
    native_language            TEXT,
    timezone                   TEXT,
    tax_id                     TEXT,
    payment_terms_days         INTEGER NOT NULL DEFAULT 60,
    invoice_cycle              TEXT NOT NULL DEFAULT '15th and 30th',
    priority_resource          BOOLEAN NOT NULL DEFAULT FALSE,
    quality_rating             NUMERIC(2, 1) CHECK (quality_rating BETWEEN 1 AND 5),
    quality_evidence           TEXT,
    compliance_status          TEXT NOT NULL DEFAULT 'Unknown'
        CHECK (compliance_status IN ('Unknown', 'Valid', 'Missing', 'Expired', 'Waived')),
    compliance_expiry          DATE,
    restriction_reason         TEXT,
    financial_access_until     DATE,
    notes                      TEXT,
    created_by                 UUID REFERENCES public.profiles(id),
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.resource_language_pairs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    source_language     TEXT NOT NULL,
    target_language     TEXT NOT NULL,
    native_target       BOOLEAN NOT NULL DEFAULT FALSE,
    approved            BOOLEAN NOT NULL DEFAULT FALSE,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (resource_id, source_language, target_language)
);

CREATE TABLE IF NOT EXISTS public.resource_services (
    resource_id     UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    service_type    TEXT NOT NULL,
    approved        BOOLEAN NOT NULL DEFAULT FALSE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (resource_id, service_type)
);

CREATE TABLE IF NOT EXISTS public.resource_specializations (
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    specialization_id   UUID NOT NULL REFERENCES public.specializations(id),
    experience_years    NUMERIC(4, 1),
    approved             BOOLEAN NOT NULL DEFAULT FALSE,
    evidence             TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (resource_id, specialization_id)
);

CREATE TABLE IF NOT EXISTS public.resource_rates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    source_language     TEXT,
    target_language     TEXT,
    service_type        TEXT NOT NULL,
    specialization_id   UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    unit                TEXT NOT NULL CHECK (unit IN (
        'Source words', 'Target words', 'Hours', 'Pages', 'Minutes', 'Fixed fee'
    )),
    cat_band            TEXT,
    rate                NUMERIC(14, 4) NOT NULL,
    currency            TEXT NOT NULL DEFAULT 'EUR',
    minimum_fee         NUMERIC(14, 2),
    status              TEXT NOT NULL DEFAULT 'Pending'
        CHECK (status IN ('Pending', 'Approved', 'Rejected', 'Expired')),
    valid_from          DATE,
    valid_to            DATE,
    approved_by         UUID REFERENCES public.profiles(id),
    approved_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.resource_education (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    institution         TEXT,
    degree              TEXT,
    field_of_study      TEXT,
    start_year          INTEGER,
    end_year            INTEGER,
    verified            BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.resource_tools (
    resource_id     UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    tool_name       TEXT NOT NULL,
    version_notes   TEXT,
    proficiency     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (resource_id, tool_name)
);

CREATE TABLE IF NOT EXISTS public.resource_documents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    document_type       TEXT NOT NULL,
    file_record_id      UUID,
    issued_on           DATE,
    expires_on          DATE,
    status              TEXT NOT NULL DEFAULT 'Pending'
        CHECK (status IN ('Pending', 'Valid', 'Expired', 'Rejected', 'Waived')),
    reviewed_by         UUID REFERENCES public.profiles(id),
    reviewed_at         TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.resource_availability (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    status              TEXT NOT NULL CHECK (status IN ('Available', 'Limited', 'Unavailable')),
    starts_at           TIMESTAMPTZ NOT NULL,
    ends_at             TIMESTAMPTZ,
    notes               TEXT,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.resource_invitations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    token_hash          TEXT NOT NULL UNIQUE,
    email               TEXT NOT NULL,
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '14 days'),
    used_at             TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    created_by          UUID NOT NULL REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.resource_rate_change_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    current_rate_id     UUID REFERENCES public.resource_rates(id) ON DELETE SET NULL,
    proposed_values     JSONB NOT NULL,
    status              TEXT NOT NULL DEFAULT 'Pending'
        CHECK (status IN ('Pending', 'Approved', 'Rejected', 'Withdrawn')),
    submitted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by         UUID REFERENCES public.profiles(id),
    reviewed_at         TIMESTAMPTZ,
    decision_notes      TEXT
);

-- ---------------------------------------------------------------------------
-- Jobs, project history and post-delivery issues
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.project_jobs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id              UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    job_number              TEXT NOT NULL,
    resource_id             UUID REFERENCES public.resources(id) ON DELETE SET NULL,
    service_type            TEXT NOT NULL,
    source_language         TEXT,
    target_language         TEXT,
    specialization_id       UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    status                  TEXT NOT NULL DEFAULT 'Offered' CHECK (status IN (
        'Offered', 'In Progress', 'Delivered', 'Revision Required', 'Approved',
        'Declined', 'Cancelled'
    )),
    offered_at              TIMESTAMPTZ,
    accepted_at             TIMESTAMPTZ,
    deadline                TIMESTAMPTZ,
    delivered_at            TIMESTAMPTZ,
    approved_at             TIMESTAMPTZ,
    quantity                NUMERIC(14, 3),
    unit                    TEXT CHECK (unit IS NULL OR unit IN (
        'Source words', 'Target words', 'Hours', 'Pages', 'Minutes', 'Fixed fee'
    )),
    cat_analysis            JSONB NOT NULL DEFAULT '{}'::JSONB,
    supplier_rate           NUMERIC(14, 4),
    supplier_currency       TEXT NOT NULL DEFAULT 'EUR',
    supplier_amount         NUMERIC(14, 2) NOT NULL DEFAULT 0,
    po_required             BOOLEAN NOT NULL DEFAULT TRUE,
    restriction_warning     BOOLEAN NOT NULL DEFAULT FALSE,
    restriction_overridden  BOOLEAN NOT NULL DEFAULT FALSE,
    override_reason         TEXT,
    overridden_by           UUID REFERENCES public.profiles(id),
    overridden_at           TIMESTAMPTZ,
    notes                   TEXT,
    created_by              UUID REFERENCES public.profiles(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (project_id, job_number)
);

CREATE OR REPLACE FUNCTION public.prepare_project_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource public.resources%ROWTYPE;
    v_project_name TEXT;
    v_sequence INTEGER;
    v_assignment_changed BOOLEAN := TG_OP = 'INSERT';
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_assignment_changed := NEW.resource_id IS DISTINCT FROM OLD.resource_id;
    END IF;

    IF TG_OP = 'INSERT' AND NULLIF(btrim(NEW.job_number), '') IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext(NEW.project_id::TEXT || ':job'));
        SELECT display_name INTO v_project_name FROM public.projects WHERE id = NEW.project_id;
        SELECT COALESCE(max(
            NULLIF(substring(job_number FROM '-J([0-9]+)$'), '')::INTEGER
        ), 0) + 1
        INTO v_sequence
        FROM public.project_jobs
        WHERE project_id = NEW.project_id;
        NEW.job_number := v_project_name || '-J' || lpad(v_sequence::TEXT, 2, '0');
    END IF;

    IF NEW.resource_id IS NOT NULL AND v_assignment_changed THEN
        SELECT * INTO v_resource FROM public.resources WHERE id = NEW.resource_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Resource not found'; END IF;

        NEW.restriction_warning := (
            NOT v_resource.assignment_approved
            OR v_resource.classification IN (
                'Hold — Inactive', 'Hold — Unavailable',
                'Hold — Terms not accepted', 'Do not use'
            )
            OR v_resource.compliance_status <> 'Valid'
            OR (v_resource.compliance_expiry IS NOT NULL
                AND v_resource.compliance_expiry < CURRENT_DATE)
        );

        IF NEW.restriction_warning THEN
            IF NOT NEW.restriction_overridden THEN
                RAISE EXCEPTION 'Resource is not eligible for assignment; Administrator override required';
            END IF;
            IF NOT public.is_admin() THEN
                RAISE EXCEPTION 'Only the Administrator can override Resource eligibility';
            END IF;
            IF NULLIF(btrim(NEW.override_reason), '') IS NULL THEN
                RAISE EXCEPTION 'An override reason is required';
            END IF;
            NEW.overridden_by := auth.uid();
            NEW.overridden_at := NOW();
        END IF;
    END IF;

    IF NEW.supplier_amount = 0
       AND NEW.quantity IS NOT NULL AND NEW.supplier_rate IS NOT NULL THEN
        NEW.supplier_amount := round(NEW.quantity * NEW.supplier_rate, 2);
    END IF;
    IF NEW.status = 'Offered' AND NEW.offered_at IS NULL THEN NEW.offered_at := NOW(); END IF;
    IF NEW.status = 'In Progress' AND NEW.accepted_at IS NULL THEN NEW.accepted_at := NOW(); END IF;
    IF NEW.status = 'Delivered' AND NEW.delivered_at IS NULL THEN NEW.delivered_at := NOW(); END IF;
    IF NEW.status = 'Approved' AND NEW.approved_at IS NULL THEN NEW.approved_at := NOW(); END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_prepare ON public.project_jobs;
CREATE TRIGGER project_jobs_prepare
BEFORE INSERT OR UPDATE OF resource_id, status, quantity, supplier_rate, supplier_amount,
    restriction_overridden, override_reason
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.prepare_project_job();

CREATE OR REPLACE FUNCTION public.recalculate_project_expense()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_project_id UUID;
BEGIN
    v_project_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.project_id ELSE NEW.project_id END;
    UPDATE public.projects project
    SET expense = COALESCE((
        SELECT sum(job.supplier_amount)
        FROM public.project_jobs job
        WHERE job.project_id = v_project_id
          AND job.status NOT IN ('Declined', 'Cancelled')
    ), 0),
    updated_at = NOW()
    WHERE project.id = v_project_id;

    IF TG_OP = 'UPDATE' AND OLD.project_id IS DISTINCT FROM NEW.project_id THEN
        UPDATE public.projects project
        SET expense = COALESCE((
            SELECT sum(job.supplier_amount)
            FROM public.project_jobs job
            WHERE job.project_id = OLD.project_id
              AND job.status NOT IN ('Declined', 'Cancelled')
        ), 0),
        updated_at = NOW()
        WHERE project.id = OLD.project_id;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_recalculate_expense ON public.project_jobs;
CREATE TRIGGER project_jobs_recalculate_expense
AFTER INSERT OR UPDATE OF project_id, supplier_amount, status OR DELETE
ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.recalculate_project_expense();

CREATE TABLE IF NOT EXISTS public.resource_project_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id             UUID NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    project_id              UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    job_id                  UUID UNIQUE REFERENCES public.project_jobs(id) ON DELETE SET NULL,
    account_id              UUID REFERENCES public.client_accounts(id) ON DELETE SET NULL,
    account_display_label   TEXT,
    project_year            INTEGER,
    period_start            DATE,
    period_end              DATE,
    source_language         TEXT,
    target_language         TEXT,
    service_type            TEXT,
    specialization_id       UUID REFERENCES public.specializations(id) ON DELETE SET NULL,
    project_summary         TEXT,
    include_in_blind_cv     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.job_issues (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id              UUID NOT NULL REFERENCES public.project_jobs(id) ON DELETE CASCADE,
    status              TEXT NOT NULL DEFAULT 'Issue Reported' CHECK (status IN (
        'Issue Reported', 'Investigating', 'Correction Requested', 'Corrected', 'Resolved'
    )),
    severity            TEXT CHECK (severity IN ('Low', 'Medium', 'High', 'Critical')),
    description         TEXT NOT NULL,
    resolution          TEXT,
    financial_impact    NUMERIC(14, 2),
    reported_by         UUID REFERENCES public.profiles(id),
    assigned_to         UUID REFERENCES public.profiles(id),
    reported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.feed_approved_job_to_resource_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id UUID;
    v_account_label TEXT;
    v_project_date DATE;
BEGIN
    IF NEW.status = 'Approved'
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status)
       AND NEW.resource_id IS NOT NULL THEN
        SELECT p.account_id, p.project_date,
               CASE
                   WHEN a.allow_name_in_blind_cv THEN a.name
                   ELSE COALESCE(NULLIF(a.blind_cv_label, ''), 'Confidential account')
               END
        INTO v_account_id, v_project_date, v_account_label
        FROM public.projects p
        LEFT JOIN public.client_accounts a ON a.id = p.account_id
        WHERE p.id = NEW.project_id;

        INSERT INTO public.resource_project_history (
            resource_id, project_id, job_id, account_id, account_display_label,
            project_year, period_start, period_end, source_language,
            target_language, service_type, specialization_id
        ) VALUES (
            NEW.resource_id, NEW.project_id, NEW.id, v_account_id, v_account_label,
            EXTRACT(YEAR FROM COALESCE(v_project_date, CURRENT_DATE))::INTEGER,
            v_project_date, COALESCE(NEW.delivered_at::DATE, CURRENT_DATE),
            NEW.source_language, NEW.target_language, NEW.service_type,
            NEW.specialization_id
        )
        ON CONFLICT (job_id) DO UPDATE SET
            resource_id = EXCLUDED.resource_id,
            account_id = EXCLUDED.account_id,
            account_display_label = EXCLUDED.account_display_label,
            project_year = EXCLUDED.project_year,
            period_start = EXCLUDED.period_start,
            period_end = EXCLUDED.period_end,
            source_language = EXCLUDED.source_language,
            target_language = EXCLUDED.target_language,
            service_type = EXCLUDED.service_type,
            specialization_id = EXCLUDED.specialization_id,
            updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_jobs_feed_resource_history ON public.project_jobs;
CREATE TRIGGER project_jobs_feed_resource_history
AFTER INSERT OR UPDATE OF status ON public.project_jobs
FOR EACH ROW EXECUTE FUNCTION public.feed_approved_job_to_resource_history();

-- ---------------------------------------------------------------------------
-- Supplier POs, invoices and payments
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.supplier_purchase_orders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_number           TEXT NOT NULL UNIQUE,
    resource_id         UUID NOT NULL REFERENCES public.resources(id),
    project_id          UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    job_id              UUID REFERENCES public.project_jobs(id) ON DELETE SET NULL,
    status              TEXT NOT NULL DEFAULT 'Draft'
        CHECK (status IN ('Draft', 'Issued', 'Acknowledged', 'Cancelled', 'Superseded')),
    current_version     INTEGER NOT NULL DEFAULT 1,
    currency            TEXT NOT NULL DEFAULT 'EUR',
    subtotal            NUMERIC(14, 2) NOT NULL DEFAULT 0,
    adjustment_amount   NUMERIC(14, 2) NOT NULL DEFAULT 0,
    total               NUMERIC(14, 2) NOT NULL DEFAULT 0,
    issued_at           TIMESTAMPTZ,
    acknowledged_at     TIMESTAMPTZ,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.supplier_po_versions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id   UUID NOT NULL REFERENCES public.supplier_purchase_orders(id) ON DELETE CASCADE,
    version_number      INTEGER NOT NULL,
    snapshot            JSONB NOT NULL,
    change_reason       TEXT,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (purchase_order_id, version_number)
);

CREATE TABLE IF NOT EXISTS public.supplier_po_lines (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id   UUID NOT NULL REFERENCES public.supplier_purchase_orders(id) ON DELETE CASCADE,
    description         TEXT,
    quantity            NUMERIC(14, 3),
    unit                TEXT,
    unit_price          NUMERIC(14, 4),
    adjustment_type     TEXT CHECK (adjustment_type IS NULL OR adjustment_type IN (
        'Discount', 'Credit', 'Surcharge', 'Minimum fee'
    )),
    amount              NUMERIC(14, 2) NOT NULL DEFAULT 0,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.client_invoices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_reference     TEXT NOT NULL UNIQUE,
    invoice_number      TEXT UNIQUE,
    proposed_number     TEXT,
    client_id           UUID NOT NULL REFERENCES public.clients(id),
    account_id          UUID REFERENCES public.client_accounts(id) ON DELETE SET NULL,
    billing_entity_id   UUID REFERENCES public.client_billing_entities(id) ON DELETE SET NULL,
    billing_snapshot    JSONB NOT NULL DEFAULT '{}'::JSONB,
    status              TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
        'Draft', 'Issued', 'Partially Paid', 'Paid', 'Overdue', 'Disputed',
        'Cancelled', 'Credited', 'Annulled'
    )),
    currency            TEXT NOT NULL DEFAULT 'EUR',
    exchange_rate_to_eur NUMERIC(18, 8) NOT NULL DEFAULT 1,
    issue_date          DATE,
    due_date            DATE,
    subtotal            NUMERIC(14, 2) NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(14, 2) NOT NULL DEFAULT 0,
    total               NUMERIC(14, 2) NOT NULL DEFAULT 0,
    total_eur           NUMERIC(14, 2) NOT NULL DEFAULT 0,
    issued_by           UUID REFERENCES public.profiles(id),
    issued_at           TIMESTAMPTZ,
    annulled_at         TIMESTAMPTZ,
    replacement_invoice_id UUID REFERENCES public.client_invoices(id) ON DELETE SET NULL,
    notes               TEXT,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (invoice_number IS NULL OR invoice_number ~ '^[0-9]{10}$'),
    CHECK (proposed_number IS NULL OR proposed_number ~ '^[0-9]{10}$')
);

CREATE TABLE IF NOT EXISTS public.client_invoice_lines (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id          UUID NOT NULL REFERENCES public.client_invoices(id) ON DELETE CASCADE,
    project_id          UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    description         TEXT,
    quantity            NUMERIC(14, 3),
    unit                TEXT,
    unit_price          NUMERIC(14, 4),
    amount              NUMERIC(14, 2) NOT NULL DEFAULT 0,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.supplier_invoices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id         UUID NOT NULL REFERENCES public.resources(id),
    supplier_invoice_number TEXT,
    status              TEXT NOT NULL DEFAULT 'Submitted' CHECK (status IN (
        'Submitted', 'Under Review', 'Approved', 'Rejected', 'Partially Paid', 'Paid'
    )),
    invoice_date        DATE,
    due_date            DATE,
    currency            TEXT NOT NULL DEFAULT 'EUR',
    exchange_rate_to_eur NUMERIC(18, 8) NOT NULL DEFAULT 1,
    total               NUMERIC(14, 2) NOT NULL DEFAULT 0,
    total_eur           NUMERIC(14, 2) NOT NULL DEFAULT 0,
    approved_by         UUID REFERENCES public.profiles(id),
    approved_at         TIMESTAMPTZ,
    file_record_id      UUID,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (resource_id, supplier_invoice_number)
);

CREATE TABLE IF NOT EXISTS public.supplier_invoice_lines (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id          UUID NOT NULL REFERENCES public.supplier_invoices(id) ON DELETE CASCADE,
    purchase_order_id   UUID REFERENCES public.supplier_purchase_orders(id) ON DELETE SET NULL,
    job_id              UUID REFERENCES public.project_jobs(id) ON DELETE SET NULL,
    description         TEXT,
    amount              NUMERIC(14, 2) NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    direction           TEXT NOT NULL CHECK (direction IN ('Receivable', 'Payable')),
    client_invoice_id   UUID REFERENCES public.client_invoices(id) ON DELETE SET NULL,
    supplier_invoice_id UUID REFERENCES public.supplier_invoices(id) ON DELETE SET NULL,
    payment_date        DATE NOT NULL,
    amount              NUMERIC(14, 2) NOT NULL,
    currency            TEXT NOT NULL DEFAULT 'EUR',
    amount_eur          NUMERIC(14, 2),
    exchange_difference_eur NUMERIC(14, 2),
    reference           TEXT,
    approved_by         UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
        (direction = 'Receivable' AND client_invoice_id IS NOT NULL AND supplier_invoice_id IS NULL)
        OR
        (direction = 'Payable' AND supplier_invoice_id IS NOT NULL AND client_invoice_id IS NULL)
    )
);

-- ---------------------------------------------------------------------------
-- Files, email, reminders and audit
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.file_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id          UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    job_id              UUID REFERENCES public.project_jobs(id) ON DELETE SET NULL,
    resource_id         UUID REFERENCES public.resources(id) ON DELETE SET NULL,
    storage_provider    TEXT NOT NULL CHECK (storage_provider IN (
        'Supabase', 'Google Drive', 'Client server', 'memoQ', 'External link'
    )),
    bucket_name         TEXT,
    object_key          TEXT,
    external_url        TEXT,
    original_filename   TEXT NOT NULL,
    mime_type           TEXT,
    size_bytes          BIGINT,
    file_role           TEXT NOT NULL,
    checksum_sha256     TEXT,
    retention_until     DATE DEFAULT (CURRENT_DATE + INTERVAL '3 months')::DATE,
    archived_at         TIMESTAMPTZ,
    uploaded_by         UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (object_key IS NOT NULL OR external_url IS NOT NULL)
);

ALTER TABLE public.resource_documents
    DROP CONSTRAINT IF EXISTS resource_documents_file_record_id_fkey;
ALTER TABLE public.resource_documents
    ADD CONSTRAINT resource_documents_file_record_id_fkey
    FOREIGN KEY (file_record_id) REFERENCES public.file_records(id) ON DELETE SET NULL;

ALTER TABLE public.supplier_invoices
    DROP CONSTRAINT IF EXISTS supplier_invoices_file_record_id_fkey;
ALTER TABLE public.supplier_invoices
    ADD CONSTRAINT supplier_invoices_file_record_id_fkey
    FOREIGN KEY (file_record_id) REFERENCES public.file_records(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.file_access_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_record_id  UUID NOT NULL REFERENCES public.file_records(id) ON DELETE CASCADE,
    profile_id      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    resource_id     UUID REFERENCES public.resources(id) ON DELETE SET NULL,
    action          TEXT NOT NULL CHECK (action IN ('View', 'Download', 'Upload', 'Archive', 'Delete')),
    ip_hash         TEXT,
    user_agent      TEXT,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.email_templates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key    TEXT NOT NULL UNIQUE,
    name            TEXT NOT NULL,
    subject_template TEXT NOT NULL,
    body_template   TEXT NOT NULL,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.email_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id          UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    job_id              UUID REFERENCES public.project_jobs(id) ON DELETE SET NULL,
    quote_id            UUID REFERENCES public.quotes(id) ON DELETE SET NULL,
    resource_id         UUID REFERENCES public.resources(id) ON DELETE SET NULL,
    direction           TEXT NOT NULL CHECK (direction IN ('Incoming', 'Outgoing')),
    status              TEXT NOT NULL DEFAULT 'Linked' CHECK (status IN (
        'Linked', 'Draft requested', 'Draft created', 'Sent', 'Failed'
    )),
    from_address        TEXT,
    to_addresses        TEXT[] NOT NULL DEFAULT '{}',
    cc_addresses        TEXT[] NOT NULL DEFAULT '{}',
    subject             TEXT,
    gmail_message_id    TEXT,
    gmail_thread_id     TEXT,
    external_url        TEXT,
    sent_at             TIMESTAMPTZ,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.reminders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reminder_type       TEXT NOT NULL,
    title               TEXT NOT NULL,
    body                TEXT,
    due_at              TIMESTAMPTZ NOT NULL,
    project_id          UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    job_id              UUID REFERENCES public.project_jobs(id) ON DELETE CASCADE,
    resource_id         UUID REFERENCES public.resources(id) ON DELETE CASCADE,
    dashboard_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    email_enabled       BOOLEAN NOT NULL DEFAULT FALSE,
    email_recipient     TEXT,
    status              TEXT NOT NULL DEFAULT 'Open'
        CHECK (status IN ('Open', 'Acknowledged', 'Completed', 'Dismissed')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.audit_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    entity_type     TEXT NOT NULL,
    entity_id       UUID,
    action          TEXT NOT NULL,
    before_values   JSONB,
    after_values    JSONB,
    reason          TEXT,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.track_project_client_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NULLIF(btrim(NEW.client_reference), '') IS NOT NULL THEN
            NEW.client_reference_received_at := COALESCE(
                NEW.client_reference_received_at, NOW()
            );
            NEW.client_reference_updated_by := COALESCE(
                NEW.client_reference_updated_by, auth.uid()
            );
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.client_reference IS DISTINCT FROM OLD.client_reference THEN
        IF NULLIF(btrim(NEW.client_reference), '') IS NOT NULL
           AND OLD.client_reference_received_at IS NULL THEN
            NEW.client_reference_received_at := NOW();
        END IF;
        NEW.client_reference_updated_by := auth.uid();

        INSERT INTO public.audit_events (
            actor_id, entity_type, entity_id, action, before_values, after_values
        ) VALUES (
            auth.uid(), 'Project', NEW.id, 'Client reference changed',
            jsonb_build_object('client_reference', OLD.client_reference),
            jsonb_build_object('client_reference', NEW.client_reference)
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_track_client_reference ON public.projects;
CREATE TRIGGER projects_track_client_reference
BEFORE INSERT OR UPDATE OF client_reference ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.track_project_client_reference();

UPDATE public.projects
SET client_reference_received_at = COALESCE(client_reference_received_at, created_at),
    client_reference_updated_by = COALESCE(client_reference_updated_by, created_by)
WHERE NULLIF(btrim(client_reference), '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.protect_project_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.display_name IS DISTINCT FROM OLD.display_name
       OR NEW.project_number IS DISTINCT FROM OLD.project_number THEN
        RAISE EXCEPTION
            'Project name and number are permanent. Store a later Client reference in client_reference.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_protect_identity ON public.projects;
CREATE TRIGGER projects_protect_identity
BEFORE UPDATE OF display_name, project_number ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.protect_project_identity();

-- ---------------------------------------------------------------------------
-- Integration adapter boundary (memoQ-ready, but provider-independent)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.integration_connections (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider            TEXT NOT NULL CHECK (provider IN (
        'memoQ', 'Google Drive', 'Gmail', 'Accounting', 'Client CAT', 'Other'
    )),
    name                TEXT NOT NULL,
    environment         TEXT NOT NULL DEFAULT 'Production'
        CHECK (environment IN ('Production', 'Sandbox', 'Client-owned')),
    base_url            TEXT,
    secret_reference    TEXT,
    settings            JSONB NOT NULL DEFAULT '{}'::JSONB,
    active              BOOLEAN NOT NULL DEFAULT FALSE,
    last_tested_at      TIMESTAMPTZ,
    last_test_status    TEXT,
    created_by          UUID REFERENCES public.profiles(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (provider, name),
    CHECK (settings::TEXT !~* '"(password|secret|token|api[_-]?key)"[[:space:]]*:')
);

COMMENT ON COLUMN public.integration_connections.secret_reference IS
    'Reference to a server-side secret/vault entry. Never store the secret itself here.';

CREATE TABLE IF NOT EXISTS public.integration_links (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id           UUID NOT NULL REFERENCES public.integration_connections(id) ON DELETE CASCADE,
    internal_entity_type    TEXT NOT NULL CHECK (internal_entity_type IN (
        'Client', 'Account', 'Project', 'Job', 'Resource', 'File', 'Invoice'
    )),
    internal_entity_id      UUID NOT NULL,
    external_entity_type    TEXT NOT NULL,
    external_id             TEXT,
    external_guid           UUID,
    external_url            TEXT,
    sync_direction          TEXT NOT NULL DEFAULT 'Manual' CHECK (sync_direction IN (
        'Manual', 'Retodo to external', 'External to Retodo', 'Bidirectional'
    )),
    sync_status             TEXT NOT NULL DEFAULT 'Not linked' CHECK (sync_status IN (
        'Not linked', 'Linked', 'Pending', 'Synced', 'Conflict', 'Error', 'Disabled'
    )),
    last_synced_at          TIMESTAMPTZ,
    last_error              TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_by              UUID REFERENCES public.profiles(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (external_id IS NOT NULL OR external_guid IS NOT NULL OR external_url IS NOT NULL),
    UNIQUE (connection_id, internal_entity_type, internal_entity_id, external_entity_type)
);

CREATE INDEX IF NOT EXISTS integration_links_external_guid_idx
    ON public.integration_links(connection_id, external_guid)
    WHERE external_guid IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.integration_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id       UUID NOT NULL REFERENCES public.integration_connections(id) ON DELETE CASCADE,
    integration_link_id UUID REFERENCES public.integration_links(id) ON DELETE SET NULL,
    event_type          TEXT NOT NULL,
    direction           TEXT NOT NULL CHECK (direction IN ('Outbound', 'Inbound', 'Internal')),
    status              TEXT NOT NULL CHECK (status IN ('Queued', 'Running', 'Succeeded', 'Failed', 'Ignored')),
    idempotency_key     TEXT,
    request_metadata    JSONB NOT NULL DEFAULT '{}'::JSONB,
    response_metadata   JSONB NOT NULL DEFAULT '{}'::JSONB,
    error_message       TEXT,
    attempt_count       INTEGER NOT NULL DEFAULT 0,
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    UNIQUE (connection_id, idempotency_key)
);

COMMENT ON TABLE public.integration_links IS
    'Maps Retodo records to external systems. For memoQ, external_guid stores ProjectGuid or document Guid.';

-- ---------------------------------------------------------------------------
-- Administrator-only state changes
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_admin_only_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_billing_entity_id UUID;
    v_billing_snapshot JSONB;
BEGIN
    IF TG_TABLE_NAME = 'resources' THEN
        IF NEW.classification = 'Do not use'
           AND (TG_OP = 'INSERT' OR NEW.classification IS DISTINCT FROM OLD.classification)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can mark a resource Do not use';
        END IF;
        IF NEW.assignment_approved
           AND (TG_OP = 'INSERT' OR NEW.assignment_approved IS DISTINCT FROM OLD.assignment_approved)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can approve a resource for assignment';
        END IF;
    ELSIF TG_TABLE_NAME = 'resource_rates' THEN
        IF (NEW.status IN ('Approved', 'Rejected') OR NEW.approved_by IS NOT NULL)
           AND (TG_OP = 'INSERT'
                OR NEW.status IS DISTINCT FROM OLD.status
                OR NEW.approved_by IS DISTINCT FROM OLD.approved_by)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can approve or reject supplier rates';
        END IF;
    ELSIF TG_TABLE_NAME = 'supplier_invoices' THEN
        IF NEW.status IN ('Approved', 'Partially Paid', 'Paid')
           AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can approve supplier invoices or payments';
        END IF;
    ELSIF TG_TABLE_NAME = 'client_invoices' THEN
        IF NEW.status IN ('Issued', 'Annulled', 'Credited')
           AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status)
           AND NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can issue, annul or credit official invoices';
        END IF;
        IF NEW.status = 'Issued'
           AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
            v_billing_entity_id := NEW.billing_entity_id;
            IF v_billing_entity_id IS NULL THEN
                SELECT entity.id
                INTO v_billing_entity_id
                FROM public.client_billing_entities entity
                WHERE entity.client_id = NEW.client_id
                  AND entity.is_default
                  AND entity.active
                LIMIT 1;
            END IF;
            IF v_billing_entity_id IS NULL THEN
                RAISE EXCEPTION 'A Billing Entity is required before an invoice can be issued';
            END IF;

            SELECT jsonb_build_object(
                'billing_entity_id', entity.id,
                'name', entity.name,
                'legal_name', entity.legal_name,
                'address_line_1', entity.address_line_1,
                'address_line_2', entity.address_line_2,
                'city', entity.city,
                'postal_code', entity.postal_code,
                'region', entity.region,
                'country_code', entity.country_code,
                'vat_number', entity.vat_number,
                'registration_number', entity.registration_number,
                'billing_email', entity.billing_email
            )
            INTO v_billing_snapshot
            FROM public.client_billing_entities entity
            WHERE entity.id = v_billing_entity_id
              AND entity.client_id = NEW.client_id
              AND entity.active;

            IF v_billing_snapshot IS NULL THEN
                RAISE EXCEPTION 'The selected Billing Entity does not belong to this Client';
            END IF;
            NEW.billing_entity_id := v_billing_entity_id;
            NEW.billing_snapshot := v_billing_snapshot;
        END IF;
        IF TG_OP = 'UPDATE'
           AND OLD.status IN ('Issued', 'Partially Paid', 'Paid', 'Overdue', 'Disputed', 'Credited', 'Annulled')
           AND (NEW.invoice_number IS DISTINCT FROM OLD.invoice_number
                OR NEW.issue_date IS DISTINCT FROM OLD.issue_date
                OR NEW.client_id IS DISTINCT FROM OLD.client_id
                OR NEW.billing_entity_id IS DISTINCT FROM OLD.billing_entity_id
                OR NEW.billing_snapshot IS DISTINCT FROM OLD.billing_snapshot
                OR NEW.total IS DISTINCT FROM OLD.total)
           AND NOT (public.is_admin() AND NEW.status IN ('Annulled', 'Credited')) THEN
            RAISE EXCEPTION 'Issued invoice facts are locked; use annulment/replacement or a credit document';
        END IF;
    ELSIF TG_TABLE_NAME = 'payments' THEN
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only the Administrator can record payments';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resources_admin_only_changes ON public.resources;
CREATE TRIGGER resources_admin_only_changes
BEFORE INSERT OR UPDATE ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.protect_admin_only_changes();

DROP TRIGGER IF EXISTS resource_rates_admin_only_changes ON public.resource_rates;
CREATE TRIGGER resource_rates_admin_only_changes
BEFORE INSERT OR UPDATE ON public.resource_rates
FOR EACH ROW EXECUTE FUNCTION public.protect_admin_only_changes();

DROP TRIGGER IF EXISTS supplier_invoices_admin_only_changes ON public.supplier_invoices;
CREATE TRIGGER supplier_invoices_admin_only_changes
BEFORE INSERT OR UPDATE ON public.supplier_invoices
FOR EACH ROW EXECUTE FUNCTION public.protect_admin_only_changes();

DROP TRIGGER IF EXISTS client_invoices_admin_only_changes ON public.client_invoices;
CREATE TRIGGER client_invoices_admin_only_changes
BEFORE INSERT OR UPDATE ON public.client_invoices
FOR EACH ROW EXECUTE FUNCTION public.protect_admin_only_changes();

DROP TRIGGER IF EXISTS payments_admin_only_changes ON public.payments;
CREATE TRIGGER payments_admin_only_changes
BEFORE INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.protect_admin_only_changes();

-- ---------------------------------------------------------------------------
-- Indexes and updated_at triggers
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS client_accounts_client_id_idx ON public.client_accounts(client_id);
CREATE INDEX IF NOT EXISTS client_contacts_client_id_idx ON public.client_contacts(client_id);
CREATE INDEX IF NOT EXISTS client_billing_entities_client_id_idx
    ON public.client_billing_entities(client_id, active, is_default DESC);
CREATE INDEX IF NOT EXISTS quotes_client_status_idx ON public.quotes(client_id, status);
CREATE INDEX IF NOT EXISTS projects_account_id_idx ON public.projects(account_id);
CREATE INDEX IF NOT EXISTS projects_deadline_status_idx ON public.projects(deadline, status);
CREATE INDEX IF NOT EXISTS resources_classification_idx ON public.resources(classification);
CREATE INDEX IF NOT EXISTS resource_language_pair_search_idx
    ON public.resource_language_pairs(target_language, source_language);
CREATE INDEX IF NOT EXISTS resource_specializations_search_idx
    ON public.resource_specializations(specialization_id, approved);
CREATE INDEX IF NOT EXISTS project_jobs_project_status_idx ON public.project_jobs(project_id, status);
CREATE INDEX IF NOT EXISTS project_jobs_resource_status_idx ON public.project_jobs(resource_id, status);
CREATE INDEX IF NOT EXISTS history_resource_year_idx
    ON public.resource_project_history(resource_id, project_year DESC);
CREATE INDEX IF NOT EXISTS reminders_due_status_idx ON public.reminders(status, due_at);
CREATE INDEX IF NOT EXISTS audit_entity_idx ON public.audit_events(entity_type, entity_id, occurred_at DESC);

DO $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'clients', 'specializations', 'client_accounts', 'client_contacts',
        'client_billing_entities',
        'client_rate_cards', 'client_rate_items', 'quotes', 'quote_items',
        'projects', 'scope_items', 'resources', 'resource_rates',
        'resource_education', 'resource_documents', 'resource_availability',
        'resource_project_history', 'project_jobs', 'job_issues',
        'supplier_purchase_orders', 'supplier_po_lines', 'client_invoices',
        'client_invoice_lines', 'supplier_invoices', 'supplier_invoice_lines',
        'file_records', 'email_templates', 'reminders',
        'integration_connections', 'integration_links'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I_set_updated_at ON public.%I', table_name, table_name);
        EXECUTE format(
            'CREATE TRIGGER %I_set_updated_at BEFORE UPDATE ON public.%I '
            'FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
            table_name, table_name
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

-- During the operational UI milestone, all new records are company-only.
-- Freelancer self-service policies will be added with the portal RPCs so a
-- portal user can never alter assignment, classification or financial controls.
DO $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'specializations', 'client_accounts', 'client_account_specializations',
        'client_contacts', 'client_billing_entities', 'client_rate_cards', 'client_rate_items',
        'quotes', 'quote_items', 'project_specializations',
        'resources', 'resource_language_pairs', 'resource_services',
        'resource_specializations', 'resource_rates', 'resource_education',
        'resource_tools', 'resource_documents', 'resource_availability',
        'resource_invitations', 'resource_rate_change_requests',
        'project_jobs', 'resource_project_history', 'job_issues',
        'supplier_purchase_orders', 'supplier_po_versions', 'supplier_po_lines',
        'client_invoices', 'client_invoice_lines', 'supplier_invoices',
        'supplier_invoice_lines', 'payments', 'file_records', 'file_access_logs',
        'email_templates', 'email_records', 'reminders', 'audit_events',
        'integration_connections', 'integration_links', 'integration_events'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    END LOOP;
END;
$$;

DROP POLICY IF EXISTS projects_admin_all ON public.projects;
DROP POLICY IF EXISTS scope_items_admin_all ON public.scope_items;
DROP POLICY IF EXISTS projects_company_select ON public.projects;
DROP POLICY IF EXISTS projects_operations_write ON public.projects;
DROP POLICY IF EXISTS scope_items_company_select ON public.scope_items;
DROP POLICY IF EXISTS scope_items_operations_write ON public.scope_items;

CREATE POLICY projects_company_select
ON public.projects FOR SELECT TO authenticated
USING (public.is_company_user());

CREATE POLICY projects_operations_write
ON public.projects FOR ALL TO authenticated
USING (public.can_manage_operations())
WITH CHECK (public.can_manage_operations());

CREATE POLICY scope_items_company_select
ON public.scope_items FOR SELECT TO authenticated
USING (public.is_company_user());

CREATE POLICY scope_items_operations_write
ON public.scope_items FOR ALL TO authenticated
USING (public.can_manage_operations())
WITH CHECK (public.can_manage_operations());

-- Existing Client policies remain, with QA read access added.
DROP POLICY IF EXISTS clients_company_read ON public.clients;
CREATE POLICY clients_company_read
ON public.clients FOR SELECT TO authenticated
USING (public.is_company_user());

-- Standard operational tables: company read, operations write.
DO $$
DECLARE
    table_name TEXT;
    read_policy TEXT;
    write_policy TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'specializations', 'client_accounts', 'client_account_specializations',
        'client_contacts', 'client_billing_entities', 'client_rate_cards', 'client_rate_items',
        'quotes', 'quote_items', 'project_specializations',
        'resources', 'resource_language_pairs', 'resource_services',
        'resource_specializations', 'resource_rates', 'resource_education',
        'resource_tools', 'resource_documents', 'resource_availability',
        'resource_invitations', 'resource_rate_change_requests',
        'project_jobs', 'resource_project_history', 'job_issues',
        'supplier_purchase_orders', 'supplier_po_versions', 'supplier_po_lines',
        'client_invoices', 'client_invoice_lines', 'supplier_invoices',
        'supplier_invoice_lines', 'payments', 'file_records', 'file_access_logs',
        'email_templates', 'email_records', 'reminders', 'audit_events',
        'integration_links', 'integration_events'
    ] LOOP
        read_policy := table_name || '_company_select';
        write_policy := table_name || '_operations_write';
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', read_policy, table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', write_policy, table_name);
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.is_company_user())',
            read_policy, table_name
        );
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
            'USING (public.can_manage_operations()) WITH CHECK (public.can_manage_operations())',
            write_policy, table_name
        );
    END LOOP;
END;
$$;

-- Connection configuration is security-sensitive. Only the Administrator can
-- view or change it. Operational users can still see the non-secret links and
-- synchronization results in integration_links/integration_events.
DROP POLICY IF EXISTS integration_connections_admin_all ON public.integration_connections;
CREATE POLICY integration_connections_admin_all
ON public.integration_connections FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Explicit grants; RLS still decides which rows/actions are allowed.
DO $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'specializations', 'client_accounts', 'client_account_specializations',
        'client_contacts', 'client_billing_entities', 'client_rate_cards', 'client_rate_items',
        'quotes', 'quote_items', 'project_specializations',
        'resources', 'resource_language_pairs', 'resource_services',
        'resource_specializations', 'resource_rates', 'resource_education',
        'resource_tools', 'resource_documents', 'resource_availability',
        'resource_invitations', 'resource_rate_change_requests',
        'project_jobs', 'resource_project_history', 'job_issues',
        'supplier_purchase_orders', 'supplier_po_versions', 'supplier_po_lines',
        'client_invoices', 'client_invoice_lines', 'supplier_invoices',
        'supplier_invoice_lines', 'payments', 'file_records', 'file_access_logs',
        'email_templates', 'email_records', 'reminders', 'audit_events',
        'integration_connections', 'integration_links', 'integration_events'
    ] LOOP
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', table_name);
    END LOOP;
END;
$$;

COMMIT;
