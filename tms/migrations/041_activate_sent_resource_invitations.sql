-- RetodoOps TMS — Update 042 / forward-only migration 041
-- Run once after 040_resource_onboarding.sql.
--
-- A staff-sent External Resource invitation is the Administrator's approval
-- to activate portal access. Authentication is linked before the invitation
-- attempt is marked sent; only that final sent transition may activate access.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.resource_access_invitations') IS NULL
       OR to_regclass('public.resources') IS NULL
       OR to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION
            'Update 041 requires the Resource onboarding schema from migration 040';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_sent_resource_invitation_041()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM 'sent'
       OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
        RETURN NEW;
    END IF;

    -- Invitation state is server-owned in migration 040. Keep a second
    -- boundary here so a database-owner maintenance statement cannot silently
    -- become an application approval path.
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Server access required';
    END IF;

    UPDATE public.resources AS resource
    SET portal_status = 'Active'
    WHERE resource.id = NEW.resource_id
      AND resource.portal_status = 'Invited'
      AND resource.resource_type IN ('Freelancer', 'Company')
      AND resource.lifecycle_status IN ('Active', 'On leave')
      AND resource.profile_id IS NOT NULL
      AND NULLIF(lower(btrim(resource.email)), '') =
          NULLIF(lower(btrim(NEW.email)), '')
      AND EXISTS (
          SELECT 1
          FROM public.profiles AS profile
          JOIN auth.users AS app_user
            ON app_user.id = profile.id
          WHERE profile.id = resource.profile_id
            AND profile.role = 'resource'
            AND NULLIF(lower(btrim(app_user.email)), '') =
                NULLIF(lower(btrim(resource.email)), '')
      );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.activate_sent_resource_invitation_041() IS
    'Activates a strictly validated External Resource only after its staff-sent Auth invitation is recorded as sent.';

REVOKE ALL ON FUNCTION public.activate_sent_resource_invitation_041()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS resource_invitation_activate_portal_041
    ON public.resource_access_invitations;
CREATE TRIGGER resource_invitation_activate_portal_041
AFTER UPDATE OF status
ON public.resource_access_invitations
FOR EACH ROW
WHEN (
    NEW.status = 'sent'
    AND OLD.status IS DISTINCT FROM NEW.status
)
EXECUTE FUNCTION public.activate_sent_resource_invitation_041();

-- One-time repair for valid staff invitations already recorded as sent before
-- this trigger existed. The predicates intentionally match the trigger.
DO $$
DECLARE
    v_previous_request_role text;
BEGIN
    v_previous_request_role :=
        current_setting('request.jwt.claim.role', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);

    BEGIN
        UPDATE public.resources AS resource
        SET portal_status = 'Active'
        FROM public.resource_access_invitations AS invitation
        WHERE invitation.resource_id = resource.id
          AND invitation.status = 'sent'
          AND resource.portal_status = 'Invited'
          AND resource.resource_type IN ('Freelancer', 'Company')
          AND resource.lifecycle_status IN ('Active', 'On leave')
          AND resource.profile_id IS NOT NULL
          AND NULLIF(lower(btrim(resource.email)), '') =
              NULLIF(lower(btrim(invitation.email)), '')
          AND EXISTS (
              SELECT 1
              FROM public.profiles AS profile
              JOIN auth.users AS app_user
                ON app_user.id = profile.id
              WHERE profile.id = resource.profile_id
                AND profile.role = 'resource'
                AND NULLIF(lower(btrim(app_user.email)), '') =
                    NULLIF(lower(btrim(resource.email)), '')
          );
    EXCEPTION WHEN OTHERS THEN
        PERFORM set_config(
            'request.jwt.claim.role',
            COALESCE(v_previous_request_role, ''),
            true
        );
        RAISE;
    END;

    PERFORM set_config(
        'request.jwt.claim.role',
        COALESCE(v_previous_request_role, ''),
        true
    );
END;
$$;

COMMIT;
