-- RetodoOps TMS — Operational foundation migration
-- Run once in Supabase SQL Editor before deploying the matching frontend files.
-- This migration is additive and keeps existing project records intact.

BEGIN;

-- The project editor already uses these fields, but the original setup script
-- did not create them.
ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS email_subject       TEXT,
    ADD COLUMN IF NOT EXISTS client_contact      TEXT,
    ADD COLUMN IF NOT EXISTS place_of_delivery   TEXT,
    ADD COLUMN IF NOT EXISTS accounting_comment TEXT,
    ADD COLUMN IF NOT EXISTS project_coordinator TEXT;

-- Commercial scope/price lines shown on the project page.
CREATE TABLE IF NOT EXISTS public.scope_items (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_id  UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    quantity    NUMERIC(14, 3),
    price_unit  TEXT,
    unit_price  NUMERIC(14, 4),
    price       NUMERIC(14, 2),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS scope_items_project_id_idx
    ON public.scope_items(project_id);

-- Add the first operational roles. Client-relations access is deliberately
-- limited to client records until its project visibility is agreed.
ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('admin', 'pm', 'qa', 'client_relations', 'user'));

-- Fail before changing access rules if the bootstrap administrator is absent.
DO $$
DECLARE
    bootstrap_admin_email CONSTANT TEXT := 'aleksandra.atanasoff@gmail.com';
    bootstrap_admin_id UUID;
BEGIN
    SELECT id INTO bootstrap_admin_id
    FROM auth.users
    WHERE lower(email) = lower(bootstrap_admin_email)
    LIMIT 1;

    IF bootstrap_admin_id IS NULL THEN
        RAISE EXCEPTION
            'Bootstrap administrator % was not found. Update bootstrap_admin_email before running this migration.',
            bootstrap_admin_email;
    END IF;

    INSERT INTO public.profiles (id, full_name, role)
    SELECT
        u.id,
        COALESCE(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
        'admin'
    FROM auth.users u
    WHERE u.id = bootstrap_admin_id
    ON CONFLICT (id) DO UPDATE SET role = 'admin';
END;
$$;

-- Central role lookup. SECURITY DEFINER prevents recursive profile policies;
-- the fixed search path prevents object-shadowing attacks.
CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_app_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;

ALTER TABLE public.profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scope_items ENABLE ROW LEVEL SECURITY;

-- Replace the original blanket policies.
DROP POLICY IF EXISTS auth_profiles ON public.profiles;
DROP POLICY IF EXISTS auth_clients ON public.clients;
DROP POLICY IF EXISTS auth_projects ON public.projects;

DROP POLICY IF EXISTS profiles_select_own_or_admin ON public.profiles;
DROP POLICY IF EXISTS profiles_admin_insert ON public.profiles;
DROP POLICY IF EXISTS profiles_admin_update ON public.profiles;
DROP POLICY IF EXISTS profiles_admin_delete ON public.profiles;
DROP POLICY IF EXISTS clients_operational_select ON public.clients;
DROP POLICY IF EXISTS clients_operational_insert ON public.clients;
DROP POLICY IF EXISTS clients_operational_update ON public.clients;
DROP POLICY IF EXISTS clients_admin_delete ON public.clients;
DROP POLICY IF EXISTS projects_admin_all ON public.projects;
DROP POLICY IF EXISTS scope_items_admin_all ON public.scope_items;

CREATE POLICY profiles_select_own_or_admin
ON public.profiles FOR SELECT TO authenticated
USING (id = auth.uid() OR public.current_app_role() = 'admin');

CREATE POLICY profiles_admin_insert
ON public.profiles FOR INSERT TO authenticated
WITH CHECK (public.current_app_role() = 'admin');

CREATE POLICY profiles_admin_update
ON public.profiles FOR UPDATE TO authenticated
USING (public.current_app_role() = 'admin')
WITH CHECK (public.current_app_role() = 'admin');

CREATE POLICY profiles_admin_delete
ON public.profiles FOR DELETE TO authenticated
USING (public.current_app_role() = 'admin');

CREATE POLICY clients_operational_select
ON public.clients FOR SELECT TO authenticated
USING (public.current_app_role() IN ('admin', 'pm', 'client_relations'));

CREATE POLICY clients_operational_insert
ON public.clients FOR INSERT TO authenticated
WITH CHECK (public.current_app_role() IN ('admin', 'pm', 'client_relations'));

CREATE POLICY clients_operational_update
ON public.clients FOR UPDATE TO authenticated
USING (public.current_app_role() IN ('admin', 'pm', 'client_relations'))
WITH CHECK (public.current_app_role() IN ('admin', 'pm', 'client_relations'));

CREATE POLICY clients_admin_delete
ON public.clients FOR DELETE TO authenticated
USING (public.current_app_role() = 'admin');

-- Only the administrator can access projects and financial fields during this
-- first phase. More granular project views will be added with the Jobs module.
CREATE POLICY projects_admin_all
ON public.projects FOR ALL TO authenticated
USING (public.current_app_role() = 'admin')
WITH CHECK (public.current_app_role() = 'admin');

CREATE POLICY scope_items_admin_all
ON public.scope_items FOR ALL TO authenticated
USING (public.current_app_role() = 'admin')
WITH CHECK (public.current_app_role() = 'admin');

COMMIT;
