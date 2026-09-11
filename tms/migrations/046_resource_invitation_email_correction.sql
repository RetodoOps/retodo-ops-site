-- RetodoOps TMS — Update 047 / forward-only migration 046
-- Run once after 045_r2_server_role_claim_compatibility.sql.
--
-- A linked External Resource email is an Authentication identity, not an
-- ordinary contact-field edit. This migration adds a service-only, resumable
-- correction workflow for an Administrator. It is deliberately limited to
-- linked accounts that have never signed in.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.resources') IS NULL
       OR to_regclass('public.profiles') IS NULL
       OR to_regclass('public.resource_access_invitations') IS NULL
       OR to_regprocedure('public.resource_onboarding_040(text,uuid,uuid,jsonb,uuid)') IS NULL
       OR to_regprocedure('public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text)') IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'auth'
             AND table_name = 'users'
             AND column_name = 'last_sign_in_at'
       ) THEN
        RAISE EXCEPTION
            'Migration 046 requires the Resource onboarding, trusted audit and Supabase Auth schema';
    END IF;
END;
$$;

CREATE TABLE public.resource_email_correction_requests (
    request_id uuid PRIMARY KEY,
    resource_id uuid NOT NULL REFERENCES public.resources(id),
    actor_id uuid NOT NULL REFERENCES public.profiles(id),
    completed_by uuid REFERENCES public.profiles(id),
    auth_user_id uuid NOT NULL REFERENCES auth.users(id),
    previous_email text NOT NULL,
    corrected_email text NOT NULL,
    previous_portal_status text NOT NULL,
    status text NOT NULL CHECK (status IN ('prepared', 'completed', 'cancelled')),
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz
);

CREATE UNIQUE INDEX resource_email_correction_one_open
ON public.resource_email_correction_requests(resource_id)
WHERE status = 'prepared';

ALTER TABLE public.resource_email_correction_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.resource_email_correction_requests
    FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.resource_email_correction_requests TO service_role;

CREATE FUNCTION public.resource_email_correction_046(
    p_action text,
    p_actor_id uuid,
    p_resource_id uuid,
    p_new_email text,
    p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_actor_role text;
    v_resource public.resources%ROWTYPE;
    v_auth_user auth.users%ROWTYPE;
    v_profile_role text;
    v_request public.resource_email_correction_requests%ROWTYPE;
    v_open_request public.resource_email_correction_requests%ROWTYPE;
    v_current_email text;
    v_auth_email text;
    v_new_email text;
    v_domain text;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Server access required';
    END IF;
    IF p_action NOT IN ('prepare', 'complete') THEN
        RAISE EXCEPTION 'Unknown email correction action';
    END IF;
    IF p_request_id IS NULL THEN
        RAISE EXCEPTION 'Request ID required';
    END IF;

    SELECT profile.role INTO v_actor_role
    FROM public.profiles AS profile
    JOIN auth.users AS app_user ON app_user.id = profile.id
    WHERE profile.id = p_actor_id;
    IF v_actor_role IS DISTINCT FROM 'admin'
       OR EXISTS (
           SELECT 1
           FROM public.resources AS actor_resource
           WHERE actor_resource.profile_id = p_actor_id
             AND actor_resource.resource_type = 'Internal'
             AND actor_resource.lifecycle_status = 'Inactive'
       ) THEN
        RAISE EXCEPTION 'Administrator access required';
    END IF;

    v_new_email := NULLIF(lower(btrim(p_new_email)), '');
    IF v_new_email IS NULL
       OR length(v_new_email) > 320
       OR v_new_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
        RAISE EXCEPTION 'Enter a valid corrected email address';
    END IF;
    v_domain := split_part(v_new_email, '@', 2);
    IF v_domain IN ('gmai.com', 'gmial.com', 'gamil.com', 'gmail.con',
                    'hotnail.com', 'outlok.com', 'yaho.com') THEN
        RAISE EXCEPTION 'The corrected email domain looks mistyped';
    END IF;

    SELECT * INTO v_resource
    FROM public.resources
    WHERE id = p_resource_id
    FOR UPDATE;
    IF NOT FOUND OR v_resource.resource_type = 'Internal' THEN
        RAISE EXCEPTION 'External Resource not found';
    END IF;
    IF v_resource.profile_id IS NULL THEN
        RAISE EXCEPTION 'No linked login account exists; save the email and send an invitation instead';
    END IF;
    IF v_resource.lifecycle_status = 'Inactive'
       OR v_resource.portal_status = 'Closed' THEN
        RAISE EXCEPTION 'Restore the Resource before correcting its login email';
    END IF;

    SELECT * INTO v_auth_user
    FROM auth.users
    WHERE id = v_resource.profile_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Linked Authentication user not found';
    END IF;
    SELECT role INTO v_profile_role
    FROM public.profiles
    WHERE id = v_auth_user.id
    FOR UPDATE;
    IF v_profile_role IS DISTINCT FROM 'resource' THEN
        RAISE EXCEPTION 'Linked account is not an External Resource login';
    END IF;
    IF v_auth_user.last_sign_in_at IS NOT NULL THEN
        RAISE EXCEPTION 'This login has already been used. Its email cannot be corrected through the invitation workflow';
    END IF;

    v_current_email := NULLIF(lower(btrim(v_resource.email)), '');
    v_auth_email := NULLIF(lower(btrim(v_auth_user.email)), '');

    IF EXISTS (
        SELECT 1
        FROM public.resources AS other_resource
        WHERE other_resource.id <> v_resource.id
          AND NULLIF(lower(btrim(other_resource.email)), '') = v_new_email
    ) OR EXISTS (
        SELECT 1
        FROM auth.users AS other_user
        WHERE other_user.id <> v_auth_user.id
          AND NULLIF(lower(btrim(other_user.email)), '') = v_new_email
    ) THEN
        RAISE EXCEPTION 'The corrected email is already used by another account';
    END IF;

    IF p_action = 'prepare' THEN
        SELECT * INTO v_request
        FROM public.resource_email_correction_requests
        WHERE request_id = p_request_id
        FOR UPDATE;
        IF FOUND THEN
            IF v_request.resource_id <> v_resource.id
               OR v_request.corrected_email <> v_new_email
               OR v_request.auth_user_id <> v_auth_user.id THEN
                RAISE EXCEPTION 'Email correction request does not match this Resource';
            END IF;
            IF v_request.status = 'completed' THEN
                RETURN jsonb_build_object(
                    'request_id', v_request.request_id,
                    'completed', true,
                    'auth_update_required', false,
                    'auth_user_id', v_request.auth_user_id
                );
            END IF;
            IF v_request.status <> 'prepared' THEN
                RAISE EXCEPTION 'Email correction request is no longer active';
            END IF;
            IF v_auth_email NOT IN (v_request.previous_email, v_request.corrected_email) THEN
                RAISE EXCEPTION 'Linked login email changed outside this correction request';
            END IF;
            RETURN jsonb_build_object(
                'request_id', v_request.request_id,
                'completed', false,
                'auth_update_required', v_auth_email <> v_request.corrected_email,
                'auth_user_id', v_request.auth_user_id
            );
        END IF;

        SELECT * INTO v_open_request
        FROM public.resource_email_correction_requests
        WHERE resource_id = v_resource.id
          AND status = 'prepared'
        FOR UPDATE;
        IF FOUND THEN
            IF v_open_request.corrected_email = v_new_email
               AND v_auth_email IN (v_open_request.previous_email, v_open_request.corrected_email) THEN
                RETURN jsonb_build_object(
                    'request_id', v_open_request.request_id,
                    'completed', false,
                    'auth_update_required', v_auth_email <> v_open_request.corrected_email,
                    'auth_user_id', v_open_request.auth_user_id
                );
            END IF;
            IF v_auth_email IS DISTINCT FROM v_current_email THEN
                RAISE EXCEPTION 'Finish the existing email correction before starting another one';
            END IF;
            UPDATE public.resource_email_correction_requests
            SET status = 'cancelled', finished_at = now()
            WHERE request_id = v_open_request.request_id;
        END IF;

        IF v_auth_email IS DISTINCT FROM v_current_email THEN
            RAISE EXCEPTION 'Resource and linked login email are already inconsistent';
        END IF;
        IF v_new_email = v_current_email THEN
            RAISE EXCEPTION 'The linked login already uses this email address';
        END IF;

        INSERT INTO public.resource_email_correction_requests(
            request_id, resource_id, actor_id, auth_user_id,
            previous_email, corrected_email, previous_portal_status, status
        ) VALUES (
            p_request_id, v_resource.id, p_actor_id, v_auth_user.id,
            v_current_email, v_new_email, v_resource.portal_status, 'prepared'
        ) RETURNING * INTO v_request;

        RETURN jsonb_build_object(
            'request_id', v_request.request_id,
            'completed', false,
            'auth_update_required', true,
            'auth_user_id', v_request.auth_user_id
        );
    END IF;

    SELECT * INTO v_request
    FROM public.resource_email_correction_requests
    WHERE request_id = p_request_id
      AND resource_id = v_resource.id
    FOR UPDATE;
    IF NOT FOUND OR v_request.corrected_email <> v_new_email
       OR v_request.auth_user_id <> v_auth_user.id THEN
        RAISE EXCEPTION 'Email correction request not found';
    END IF;
    IF v_request.status = 'completed' THEN
        RETURN jsonb_build_object(
            'request_id', v_request.request_id,
            'completed', true,
            'resource_id', v_resource.id
        );
    END IF;
    IF v_request.status <> 'prepared' THEN
        RAISE EXCEPTION 'Email correction request is no longer active';
    END IF;
    IF v_auth_email IS DISTINCT FROM v_request.corrected_email THEN
        RAISE EXCEPTION 'Authentication email update has not completed';
    END IF;
    IF v_current_email IS DISTINCT FROM v_request.previous_email THEN
        RAISE EXCEPTION 'Resource email changed while the correction was in progress';
    END IF;

    UPDATE public.resources
    SET email = v_request.corrected_email,
        portal_status = 'Invited',
        updated_at = now()
    WHERE id = v_resource.id;

    -- The old delivery state cannot activate the corrected login. Backdating
    -- this failed marker permits the replacement invitation immediately.
    UPDATE public.resource_access_invitations
    SET email = v_request.corrected_email,
        status = 'failed',
        started_at = now() - interval '2 minutes',
        finished_at = now() - interval '2 minutes'
    WHERE resource_id = v_resource.id;

    UPDATE public.resource_email_correction_requests
    SET status = 'completed',
        completed_by = p_actor_id,
        finished_at = now()
    WHERE request_id = v_request.request_id;

    PERFORM public.append_trusted_tms_audit_event(
        'Resource',
        v_resource.id,
        'External Resource login email corrected',
        jsonb_build_object(
            'email', v_request.previous_email,
            'portal_status', v_request.previous_portal_status
        ),
        jsonb_build_object(
            'email', v_request.corrected_email,
            'portal_status', 'Invited'
        ),
        'Administrator corrected an unused linked login before sending a replacement invitation'
    );

    RETURN jsonb_build_object(
        'request_id', v_request.request_id,
        'completed', true,
        'resource_id', v_resource.id,
        'portal_status', 'Invited'
    );
END;
$$;

COMMENT ON FUNCTION public.resource_email_correction_046(text,uuid,uuid,text,uuid) IS
    'Service-only, resumable correction for an unused linked External Resource login; requires a verified Administrator actor.';

REVOKE ALL ON FUNCTION public.resource_email_correction_046(text,uuid,uuid,text,uuid)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resource_email_correction_046(text,uuid,uuid,text,uuid)
    TO service_role;

COMMIT;
