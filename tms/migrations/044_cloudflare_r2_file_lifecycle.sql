-- RetodoOps TMS — Update 045 / private Cloudflare R2 Job-file lifecycle
-- Forward-only migration. Migrations 036–043 are immutable and must not be edited.
--
-- Supabase remains the trusted metadata/Auth/RLS/audit layer. Binary objects are
-- private in Cloudflare R2 and are reachable only through server-issued,
-- short-lived URLs. External Resources keep read-only access to files belonging
-- to their own currently assigned Jobs; no Resource policy is opened on company
-- tables and no Client identity or internal economics are exposed.

BEGIN;

-- The service-worker functions are declared before their supporting tables in
-- this single transaction, then compiled on first use after every object exists.
SET LOCAL check_function_bodies = off;

DO $$
BEGIN
    IF to_regclass('public.file_records') IS NULL
       OR to_regclass('public.file_access_logs') IS NULL
       OR to_regclass('public.project_jobs') IS NULL
       OR to_regclass('public.projects') IS NULL
       OR to_regclass('public.clients') IS NULL
       OR to_regclass('public.client_accounts') IS NULL
       OR to_regclass('public.audit_events') IS NULL
       OR to_regprocedure('public.current_external_resource_id()') IS NULL
       OR to_regprocedure('public.is_company_user()') IS NULL
       OR to_regprocedure('public.is_admin()') IS NULL
       OR to_regprocedure('public.append_trusted_tms_audit_event(text,uuid,text,jsonb,jsonb,text)') IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'file_records'
             AND column_name = 'upload_status'
       ) THEN
        RAISE EXCEPTION
            'Migration 044 requires the operational core and migrations 036–043';
    END IF;
END;
$$;

-- -------------------------------------------------------------------------
-- Service-only queue: daily scheduler, leased worker and verified completion
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.system_enqueue_due_file_lifecycle_044()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
    v_archive RECORD;
    v_archive_id UUID;
    v_policy JSONB;
    v_archive_count INTEGER := 0;
    v_delete_count INTEGER := 0;
    v_cleanup_sources_count INTEGER := 0;
    v_cleanup_archive_count INTEGER := 0;
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;

    -- Repair an interrupted lease. Background workers have a 15-minute ceiling;
    -- twenty minutes means no active invocation can still own the task.
    UPDATE public.file_lifecycle_tasks
    SET status = 'Pending', started_at = NULL,
        available_at = NOW(), last_error = 'Recovered expired worker lease'
    WHERE status = 'Processing'
      AND started_at < NOW() - INTERVAL '20 minutes';

    FOR v_job IN
        SELECT job.id AS job_id, job.project_id
        FROM public.project_file_retention retention
        JOIN public.projects project ON project.id = retention.project_id
        JOIN public.project_jobs job ON job.project_id = project.id
        WHERE project.status = 'Approved'
          AND retention.archive_due_at IS NOT NULL
          AND retention.archive_due_at <= NOW()
          AND NOT retention.retention_hold
          AND EXISTS (
              SELECT 1 FROM public.file_records file
              WHERE file.job_id = job.id
                AND file.storage_provider = 'Cloudflare R2'
                AND file.upload_status = 'Ready'
                AND file.archived_at IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.job_file_archives archive
              WHERE archive.job_id = job.id
                AND archive.state IN ('Queued', 'Archiving', 'Archived', 'Restoring')
          )
    LOOP
        v_policy := public.effective_file_retention_044(v_job.project_id);
        IF COALESCE((v_policy->>'retention_hold')::BOOLEAN, FALSE) THEN CONTINUE; END IF;
        BEGIN
            v_archive_id := gen_random_uuid();
            INSERT INTO public.job_file_archives(
                id, project_id, job_id, archive_object_key, delete_after_months
            ) VALUES (
                v_archive_id, v_job.project_id, v_job.job_id,
                format('archives/projects/%s/jobs/%s/%s.zip',
                    v_job.project_id, v_job.job_id, v_archive_id),
                COALESCE((v_policy->>'delete_after_months')::INTEGER, 24)
            );
            INSERT INTO public.file_lifecycle_tasks(
                archive_id, project_id, job_id, action, requested_by
            ) VALUES (
                v_archive_id, v_job.project_id, v_job.job_id, 'Archive', NULL
            );
            v_archive_count := v_archive_count + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;
    END LOOP;

    FOR v_archive IN
        SELECT archive.*
        FROM public.job_file_archives archive
        JOIN public.project_file_retention retention
          ON retention.project_id = archive.project_id
        WHERE archive.state = 'Archived'
          AND archive.delete_due_at IS NOT NULL
          AND archive.delete_due_at <= NOW()
          AND NOT retention.retention_hold
          AND NOT EXISTS (
              SELECT 1 FROM public.file_lifecycle_tasks task
              WHERE task.archive_id = archive.id
                AND task.action = 'Delete'
                AND task.status IN ('Pending', 'Processing', 'Completed')
          )
    LOOP
        v_policy := public.effective_file_retention_044(v_archive.project_id);
        IF COALESCE((v_policy->>'retention_hold')::BOOLEAN, FALSE) THEN CONTINUE; END IF;
        BEGIN
            INSERT INTO public.file_lifecycle_tasks(
                archive_id, project_id, job_id, action, requested_by
            ) VALUES (
                v_archive.id, v_archive.project_id, v_archive.job_id, 'Delete', NULL
            );
            v_delete_count := v_delete_count + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;
    END LOOP;

    -- ZIP source objects are removed only after the archive metadata commits.
    -- A separate idempotent task makes a worker/DB interruption recoverable.
    FOR v_archive IN
        SELECT archive.*
        FROM public.job_file_archives archive
        WHERE archive.state = 'Archived'
          AND archive.strategy = 'zip'
          AND EXISTS (
              SELECT 1 FROM public.file_records file
              WHERE file.archive_id = archive.id
                AND file.source_removed_at IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.file_lifecycle_tasks task
              WHERE task.archive_id = archive.id
                AND task.action = 'CleanupSources'
                AND task.status IN ('Pending', 'Processing', 'Completed')
          )
    LOOP
        BEGIN
            INSERT INTO public.file_lifecycle_tasks(
                archive_id, project_id, job_id, action, requested_by
            ) VALUES (
                v_archive.id, v_archive.project_id, v_archive.job_id,
                'CleanupSources', NULL
            );
            v_cleanup_sources_count := v_cleanup_sources_count + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;
    END LOOP;

    -- The restored active objects are verified before the redundant ZIP is
    -- removed. Failed cleanup is harmless and is queued again on a later run.
    FOR v_archive IN
        SELECT archive.*
        FROM public.job_file_archives archive
        WHERE archive.state = 'Restored'
          AND archive.strategy = 'zip'
          AND archive.archive_object_key IS NOT NULL
          AND archive.archive_object_removed_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM public.file_lifecycle_tasks task
              WHERE task.archive_id = archive.id
                AND task.action = 'CleanupArchive'
                AND task.status IN ('Pending', 'Processing', 'Completed')
          )
    LOOP
        BEGIN
            INSERT INTO public.file_lifecycle_tasks(
                archive_id, project_id, job_id, action, requested_by
            ) VALUES (
                v_archive.id, v_archive.project_id, v_archive.job_id,
                'CleanupArchive', NULL
            );
            v_cleanup_archive_count := v_cleanup_archive_count + 1;
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'archive_tasks_queued', v_archive_count,
        'delete_tasks_queued', v_delete_count,
        'cleanup_sources_tasks_queued', v_cleanup_sources_count,
        'cleanup_archive_tasks_queued', v_cleanup_archive_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.system_claim_file_lifecycle_044()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.file_lifecycle_tasks%ROWTYPE;
    v_archive public.job_file_archives%ROWTYPE;
    v_files JSONB;
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;

    UPDATE public.file_lifecycle_tasks
    SET status = 'Pending', started_at = NULL,
        available_at = NOW(), last_error = 'Recovered expired worker lease'
    WHERE status = 'Processing'
      AND started_at < NOW() - INTERVAL '20 minutes';

    SELECT task.* INTO v_task
    FROM public.file_lifecycle_tasks task
    JOIN public.job_file_archives archive ON archive.id = task.archive_id
    WHERE task.status = 'Pending' AND task.available_at <= NOW()
      AND (
          (task.action = 'Archive' AND archive.state IN ('Queued', 'Archiving'))
          OR (task.action = 'Restore' AND archive.state IN ('Archived', 'Restoring'))
          OR (task.action = 'Delete' AND archive.state = 'Archived')
          OR (task.action = 'CleanupSources' AND archive.state = 'Archived')
          OR (task.action = 'CleanupArchive' AND archive.state = 'Restored')
      )
    ORDER BY task.created_at
    FOR UPDATE OF task SKIP LOCKED
    LIMIT 1;
    IF NOT FOUND THEN RETURN '{}'::JSONB; END IF;

    UPDATE public.file_lifecycle_tasks
    SET status = 'Processing', started_at = NOW(),
        attempts = attempts + 1, last_error = NULL
    WHERE id = v_task.id
    RETURNING * INTO v_task;

    SELECT * INTO v_archive
    FROM public.job_file_archives
    WHERE id = v_task.archive_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'File archive metadata is missing'; END IF;

    IF v_task.action = 'Archive' THEN
        UPDATE public.job_file_archives
        SET state = 'Archiving', failure_message = NULL
        WHERE id = v_archive.id RETURNING * INTO v_archive;
        UPDATE public.file_records
        SET upload_status = 'Archiving', archive_id = v_archive.id,
            storage_error = NULL
        WHERE job_id = v_task.job_id
          AND storage_provider = 'Cloudflare R2'
          AND upload_status = 'Ready' AND archived_at IS NULL;
    ELSIF v_task.action = 'Restore' THEN
        UPDATE public.job_file_archives
        SET state = 'Restoring', failure_message = NULL
        WHERE id = v_archive.id RETURNING * INTO v_archive;
        UPDATE public.file_records
        SET upload_status = 'Restoring', storage_error = NULL
        WHERE archive_id = v_archive.id AND upload_status = 'Archived';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'file_id', file.id,
        'object_key', file.object_key,
        'original_filename', file.original_filename,
        'mime_type', file.mime_type,
        'size_bytes', file.size_bytes,
        'checksum_sha256', file.checksum_sha256
    ) ORDER BY file.id), '[]'::JSONB)
    INTO v_files
    FROM public.file_records file
    WHERE file.archive_id = v_archive.id;

    IF jsonb_array_length(v_files) = 0
       AND jsonb_typeof(v_archive.manifest->'files') = 'array' THEN
        v_files := v_archive.manifest->'files';
    END IF;

    RETURN jsonb_build_object(
        'task_id', v_task.id,
        'action', v_task.action,
        'archive_id', v_archive.id,
        'project_id', v_archive.project_id,
        'job_id', v_archive.job_id,
        'strategy', v_archive.strategy,
        'archive_object_key', v_archive.archive_object_key,
        'archive_size_bytes', v_archive.archive_size_bytes,
        'manifest_sha256', v_archive.manifest_sha256,
        'manifest', v_archive.manifest,
        'files', v_files
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.system_complete_file_lifecycle_044(
    p_task_id UUID,
    p_result JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.file_lifecycle_tasks%ROWTYPE;
    v_archive public.job_file_archives%ROWTYPE;
    v_strategy TEXT;
    v_count INTEGER;
    v_policy JSONB;
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    SELECT * INTO v_task FROM public.file_lifecycle_tasks
    WHERE id = p_task_id AND status = 'Processing' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active lifecycle task not found'; END IF;
    SELECT * INTO v_archive FROM public.job_file_archives
    WHERE id = v_task.archive_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'File archive metadata is missing'; END IF;

    -- Complete the active lease inside this transaction before queuing a
    -- follow-up cleanup for the same Job. Any later error rolls this back.
    UPDATE public.file_lifecycle_tasks
    SET status = 'Completed', completed_at = NOW(), last_error = NULL
    WHERE id = v_task.id;

    IF v_task.action = 'Archive' THEN
        v_strategy := p_result->>'strategy';
        IF v_strategy NOT IN ('zip', 'infrequent')
           OR jsonb_typeof(p_result->'manifest') IS DISTINCT FROM 'object'
           OR jsonb_typeof(p_result->'manifest'->'files') IS DISTINCT FROM 'array'
           OR COALESCE(NULLIF(p_result->>'file_count', '')::INTEGER, 0) < 1 THEN
            RAISE EXCEPTION 'Archive worker result is incomplete';
        END IF;
        UPDATE public.job_file_archives
        SET strategy = v_strategy,
            state = 'Archived',
            manifest = p_result->'manifest',
            manifest_sha256 = p_result->>'manifest_sha256',
            archive_checksum_sha256 = NULLIF(p_result->>'archive_checksum_sha256', ''),
            original_size_bytes = NULLIF(p_result->>'original_size_bytes', '')::BIGINT,
            archive_size_bytes = NULLIF(p_result->>'archive_size_bytes', '')::BIGINT,
            file_count = NULLIF(p_result->>'file_count', '')::INTEGER,
            archived_at = NOW(),
            delete_due_at = NOW() + make_interval(months => delete_after_months),
            restored_at = NULL, failure_message = NULL
        WHERE id = v_archive.id
        RETURNING * INTO v_archive;

        UPDATE public.file_records
        SET upload_status = 'Archived', archived_at = NOW(),
            storage_class = COALESCE(NULLIF(p_result->>'storage_class', ''), 'STANDARD_IA'),
            source_removed_at = NULL,
            storage_error = NULL
        WHERE archive_id = v_archive.id AND upload_status = 'Archiving';
        INSERT INTO public.file_access_logs(file_record_id, resource_id, action)
        SELECT file.id, file.resource_id, 'Archive'
        FROM public.file_records file WHERE file.archive_id = v_archive.id;
        UPDATE public.project_file_retention
        SET archive_due_at = NULL
        WHERE project_id = v_archive.project_id;

        IF v_strategy = 'zip' THEN
            INSERT INTO public.file_lifecycle_tasks(
                archive_id, project_id, job_id, action, requested_by
            ) VALUES (
                v_archive.id, v_archive.project_id, v_archive.job_id,
                'CleanupSources', v_task.requested_by
            );
        END IF;
    ELSIF v_task.action = 'Restore' THEN
        INSERT INTO public.file_access_logs(file_record_id, resource_id, action)
        SELECT file.id, file.resource_id, 'Restore'
        FROM public.file_records file WHERE file.archive_id = v_archive.id;
        UPDATE public.file_records
        SET upload_status = 'Ready', archived_at = NULL, archive_id = NULL,
            storage_class = 'STANDARD', source_removed_at = NULL,
            verified_at = NOW(), storage_error = NULL
        WHERE archive_id = v_archive.id AND upload_status = 'Restoring';
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count < 1 THEN RAISE EXCEPTION 'No archived files were restored'; END IF;
        UPDATE public.job_file_archives
        SET state = 'Restored', restored_at = NOW(), delete_due_at = NULL,
            failure_message = NULL
        WHERE id = v_archive.id;
        UPDATE public.file_lifecycle_tasks
        SET status = 'Cancelled', completed_at = NOW(),
            last_error = 'Permanent deletion cancelled by restore'
        WHERE archive_id = v_archive.id AND action = 'Delete'
          AND status = 'Pending';
        INSERT INTO public.project_file_retention(project_id, last_restored_at)
        VALUES (v_archive.project_id, NOW())
        ON CONFLICT (project_id) DO UPDATE SET last_restored_at = EXCLUDED.last_restored_at;
        PERFORM public.recalculate_project_file_due_044(v_archive.project_id);

        IF v_archive.strategy = 'zip' AND v_archive.archive_object_removed_at IS NULL THEN
            INSERT INTO public.file_lifecycle_tasks(
                archive_id, project_id, job_id, action, requested_by
            ) VALUES (
                v_archive.id, v_archive.project_id, v_archive.job_id,
                'CleanupArchive', v_task.requested_by
            );
        END IF;
    ELSIF v_task.action = 'CleanupSources' THEN
        IF v_archive.state <> 'Archived' OR v_archive.strategy <> 'zip' THEN
            RAISE EXCEPTION 'ZIP source cleanup is no longer applicable';
        END IF;
        UPDATE public.file_records
        SET source_removed_at = NOW(), storage_error = NULL
        WHERE archive_id = v_archive.id AND upload_status = 'Archived';
    ELSIF v_task.action = 'CleanupArchive' THEN
        IF v_archive.state <> 'Restored' OR v_archive.strategy <> 'zip' THEN
            RAISE EXCEPTION 'Restored ZIP cleanup is no longer applicable';
        END IF;
        UPDATE public.job_file_archives
        SET archive_object_removed_at = NOW(), failure_message = NULL
        WHERE id = v_archive.id;
    ELSIF v_task.action = 'Delete' THEN
        INSERT INTO public.file_access_logs(file_record_id, resource_id, action)
        SELECT file.id, file.resource_id, 'Delete'
        FROM public.file_records file WHERE file.archive_id = v_archive.id;
        UPDATE public.file_records
        SET upload_status = 'Deleted', deleted_at = NOW(),
            storage_error = NULL
        WHERE archive_id = v_archive.id AND upload_status = 'Archived';
        UPDATE public.job_file_archives
        SET state = 'Deleted', deleted_at = NOW(), delete_due_at = NULL,
            failure_message = NULL
        WHERE id = v_archive.id;
    ELSE
        RAISE EXCEPTION 'Unsupported lifecycle task';
    END IF;

    INSERT INTO public.audit_events(
        actor_id, entity_type, entity_id, action, after_values, reason
    ) VALUES (
        v_task.requested_by, 'Job files', v_task.job_id,
        v_task.action || ' completed',
        jsonb_build_object('archive_id', v_archive.id, 'strategy', COALESCE(v_strategy, v_archive.strategy)),
        'Verified Cloudflare R2 lifecycle worker'
    );
    RETURN jsonb_build_object('task_id', v_task.id, 'status', 'Completed');
END;
$$;

CREATE OR REPLACE FUNCTION public.system_fail_file_lifecycle_044(
    p_task_id UUID,
    p_error TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.file_lifecycle_tasks%ROWTYPE;
    v_final BOOLEAN;
    v_error TEXT := left(COALESCE(NULLIF(btrim(p_error), ''), 'Lifecycle processing failed'), 500);
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    SELECT * INTO v_task FROM public.file_lifecycle_tasks
    WHERE id = p_task_id AND status = 'Processing' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active lifecycle task not found'; END IF;
    v_final := v_task.attempts >= 5;

    UPDATE public.file_lifecycle_tasks
    SET status = CASE WHEN v_final THEN 'Failed' ELSE 'Pending' END,
        started_at = NULL,
        available_at = NOW() + make_interval(hours => LEAST(24, GREATEST(1, attempts * attempts))),
        last_error = v_error,
        completed_at = CASE WHEN v_final THEN NOW() ELSE NULL END
    WHERE id = v_task.id;

    IF v_task.action = 'Archive' THEN
        UPDATE public.file_records
        SET upload_status = 'Ready', archive_id = NULL, storage_error = v_error
        WHERE archive_id = v_task.archive_id AND upload_status = 'Archiving';
        UPDATE public.job_file_archives
        SET state = CASE WHEN v_final THEN 'Failed' ELSE 'Queued' END,
            failure_message = v_error
        WHERE id = v_task.archive_id;
    ELSIF v_task.action = 'Restore' THEN
        UPDATE public.file_records
        SET upload_status = 'Archived', storage_error = v_error
        WHERE archive_id = v_task.archive_id AND upload_status = 'Restoring';
        UPDATE public.job_file_archives
        SET state = 'Archived', failure_message = v_error
        WHERE id = v_task.archive_id;
    ELSE
        UPDATE public.job_file_archives
        SET failure_message = v_error WHERE id = v_task.archive_id;
    END IF;
    RETURN jsonb_build_object(
        'task_id', v_task.id,
        'status', CASE WHEN v_final THEN 'Failed' ELSE 'Pending' END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.system_enqueue_due_file_lifecycle_044()
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_claim_file_lifecycle_044()
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_complete_file_lifecycle_044(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.system_fail_file_lifecycle_044(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.system_enqueue_due_file_lifecycle_044()
    TO service_role;
GRANT EXECUTE ON FUNCTION public.system_claim_file_lifecycle_044()
    TO service_role;
GRANT EXECUTE ON FUNCTION public.system_complete_file_lifecycle_044(UUID, JSONB)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.system_fail_file_lifecycle_044(UUID, TEXT)
    TO service_role;

-- The transaction continues with the metadata tables and browser-facing RPCs.

-- -------------------------------------------------------------------------
-- R2 metadata and explicit lifecycle states
-- -------------------------------------------------------------------------

ALTER TABLE public.file_records
    DROP CONSTRAINT IF EXISTS file_records_storage_provider_check,
    DROP CONSTRAINT IF EXISTS file_records_upload_status_check;

ALTER TABLE public.file_records
    ADD CONSTRAINT file_records_storage_provider_check CHECK (
        storage_provider IN (
            'Supabase', 'Cloudflare R2', 'Google Drive', 'Client server',
            'memoQ', 'External link'
        )
    ),
    ADD CONSTRAINT file_records_upload_status_check CHECK (
        upload_status IN (
            'Pending', 'Ready', 'Failed', 'Archiving',
            'Archived', 'Restoring', 'Deleted'
        )
    );

ALTER TABLE public.file_records
    ADD COLUMN IF NOT EXISTS storage_class TEXT,
    ADD COLUMN IF NOT EXISTS r2_etag TEXT,
    ADD COLUMN IF NOT EXISTS r2_version_id TEXT,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS source_removed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS storage_error TEXT;

ALTER TABLE public.file_records
    DROP CONSTRAINT IF EXISTS file_records_storage_class_check;
ALTER TABLE public.file_records
    ADD CONSTRAINT file_records_storage_class_check CHECK (
        storage_class IS NULL OR storage_class IN ('STANDARD', 'STANDARD_IA')
    );

ALTER TABLE public.file_access_logs
    DROP CONSTRAINT IF EXISTS file_access_logs_action_check;
ALTER TABLE public.file_access_logs
    ADD CONSTRAINT file_access_logs_action_check CHECK (
        action IN ('View', 'Download', 'Upload', 'Archive', 'Restore', 'Delete')
    );

CREATE TABLE public.file_retention_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_type TEXT NOT NULL CHECK (scope_type IN ('Default', 'Client', 'Account')),
    client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
    account_id UUID REFERENCES public.client_accounts(id) ON DELETE CASCADE,
    archive_after_months INTEGER NOT NULL DEFAULT 3
        CHECK (archive_after_months BETWEEN 1 AND 120),
    delete_after_months INTEGER NOT NULL DEFAULT 24
        CHECK (delete_after_months BETWEEN 1 AND 240),
    retention_hold BOOLEAN NOT NULL DEFAULT FALSE,
    hold_reason TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT file_retention_policy_scope_check CHECK (
        (scope_type = 'Default' AND client_id IS NULL AND account_id IS NULL)
        OR (scope_type = 'Client' AND client_id IS NOT NULL AND account_id IS NULL)
        OR (scope_type = 'Account' AND client_id IS NULL AND account_id IS NOT NULL)
    ),
    CONSTRAINT file_retention_hold_reason_check CHECK (
        NOT retention_hold OR NULLIF(btrim(COALESCE(hold_reason, '')), '') IS NOT NULL
    ),
    CONSTRAINT file_retention_delete_after_archive_check CHECK (
        delete_after_months > archive_after_months
    )
);

CREATE UNIQUE INDEX file_retention_default_unique_idx
    ON public.file_retention_policies(scope_type)
    WHERE scope_type = 'Default';
CREATE UNIQUE INDEX file_retention_client_unique_idx
    ON public.file_retention_policies(client_id)
    WHERE scope_type = 'Client';
CREATE UNIQUE INDEX file_retention_account_unique_idx
    ON public.file_retention_policies(account_id)
    WHERE scope_type = 'Account';

INSERT INTO public.file_retention_policies (
    scope_type, archive_after_months, delete_after_months
)
SELECT 'Default', 3, 24
WHERE NOT EXISTS (
    SELECT 1 FROM public.file_retention_policies WHERE scope_type = 'Default'
);

CREATE TABLE public.project_file_retention (
    project_id UUID PRIMARY KEY REFERENCES public.projects(id) ON DELETE CASCADE,
    last_approved_at TIMESTAMPTZ,
    last_restored_at TIMESTAMPTZ,
    archive_due_at TIMESTAMPTZ,
    retention_hold BOOLEAN NOT NULL DEFAULT FALSE,
    hold_reason TEXT,
    tracked_project_status TEXT,
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT project_file_retention_hold_reason_check CHECK (
        NOT retention_hold OR NULLIF(btrim(COALESCE(hold_reason, '')), '') IS NOT NULL
    )
);

CREATE TABLE public.job_file_archives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE RESTRICT,
    job_id UUID NOT NULL REFERENCES public.project_jobs(id) ON DELETE RESTRICT,
    strategy TEXT CHECK (strategy IN ('zip', 'infrequent')),
    state TEXT NOT NULL DEFAULT 'Queued' CHECK (
        state IN ('Queued', 'Archiving', 'Archived', 'Restoring', 'Restored', 'Failed', 'Deleted')
    ),
    archive_object_key TEXT,
    manifest JSONB,
    manifest_sha256 TEXT,
    archive_checksum_sha256 TEXT,
    original_size_bytes BIGINT,
    archive_size_bytes BIGINT,
    file_count INTEGER,
    delete_after_months INTEGER NOT NULL DEFAULT 24
        CHECK (delete_after_months BETWEEN 1 AND 240),
    archived_at TIMESTAMPTZ,
    delete_due_at TIMESTAMPTZ,
    restored_at TIMESTAMPTZ,
    archive_object_removed_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    failure_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX job_file_archives_one_live_idx
    ON public.job_file_archives(job_id)
    WHERE state IN ('Queued', 'Archiving', 'Archived', 'Restoring');
CREATE INDEX job_file_archives_delete_due_idx
    ON public.job_file_archives(delete_due_at)
    WHERE state = 'Archived';

ALTER TABLE public.file_records
    ADD COLUMN IF NOT EXISTS archive_id UUID
        REFERENCES public.job_file_archives(id) ON DELETE SET NULL;

CREATE INDEX file_records_r2_job_state_idx
    ON public.file_records(job_id, upload_status, created_at DESC)
    WHERE storage_provider = 'Cloudflare R2';
CREATE INDEX file_records_archive_id_idx
    ON public.file_records(archive_id)
    WHERE archive_id IS NOT NULL;

CREATE TABLE public.file_lifecycle_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_id UUID NOT NULL REFERENCES public.job_file_archives(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE RESTRICT,
    job_id UUID NOT NULL REFERENCES public.project_jobs(id) ON DELETE RESTRICT,
    action TEXT NOT NULL CHECK (
        action IN ('Archive', 'Restore', 'Delete', 'CleanupSources', 'CleanupArchive')
    ),
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (
        status IN ('Pending', 'Processing', 'Completed', 'Failed', 'Cancelled')
    ),
    requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 20),
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX file_lifecycle_tasks_one_active_idx
    ON public.file_lifecycle_tasks(job_id)
    WHERE status IN ('Pending', 'Processing');
CREATE INDEX file_lifecycle_tasks_claim_idx
    ON public.file_lifecycle_tasks(status, available_at, created_at);

-- These tables are company-readable for operational transparency, but have no
-- authenticated direct-write policy. Only guarded RPCs and the service worker
-- may mutate them. A Resource therefore receives no table row at all.
ALTER TABLE public.file_retention_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_file_retention ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_file_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_lifecycle_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY file_retention_policies_company_select
ON public.file_retention_policies FOR SELECT TO authenticated
USING (public.is_company_user());
CREATE POLICY project_file_retention_company_select
ON public.project_file_retention FOR SELECT TO authenticated
USING (public.is_company_user());
CREATE POLICY job_file_archives_company_select
ON public.job_file_archives FOR SELECT TO authenticated
USING (public.is_company_user());
CREATE POLICY file_lifecycle_tasks_company_select
ON public.file_lifecycle_tasks FOR SELECT TO authenticated
USING (public.is_company_user());

REVOKE ALL ON public.file_retention_policies, public.project_file_retention,
    public.job_file_archives, public.file_lifecycle_tasks FROM anon, authenticated;
GRANT SELECT ON public.file_retention_policies, public.project_file_retention,
    public.job_file_archives, public.file_lifecycle_tasks TO authenticated;

DROP TRIGGER IF EXISTS file_retention_policies_set_updated_at
    ON public.file_retention_policies;
CREATE TRIGGER file_retention_policies_set_updated_at
BEFORE UPDATE ON public.file_retention_policies
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS project_file_retention_set_updated_at
    ON public.project_file_retention;
CREATE TRIGGER project_file_retention_set_updated_at
BEFORE UPDATE ON public.project_file_retention
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS job_file_archives_set_updated_at
    ON public.job_file_archives;
CREATE TRIGGER job_file_archives_set_updated_at
BEFORE UPDATE ON public.job_file_archives
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS file_lifecycle_tasks_set_updated_at
    ON public.file_lifecycle_tasks;
CREATE TRIGGER file_lifecycle_tasks_set_updated_at
BEFORE UPDATE ON public.file_lifecycle_tasks
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.effective_file_retention_044(p_project_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_client_id UUID;
    v_account_id UUID;
    v_policy public.file_retention_policies%ROWTYPE;
BEGIN
    SELECT project.client_id, project.account_id
    INTO v_client_id, v_account_id
    FROM public.projects project
    WHERE project.id = p_project_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Project not found';
    END IF;

    SELECT policy.* INTO v_policy
    FROM public.file_retention_policies policy
    WHERE (policy.scope_type = 'Account' AND policy.account_id = v_account_id)
       OR (policy.scope_type = 'Client' AND policy.client_id = v_client_id)
       OR policy.scope_type = 'Default'
    ORDER BY CASE policy.scope_type
        WHEN 'Account' THEN 1 WHEN 'Client' THEN 2 ELSE 3 END
    LIMIT 1;

    RETURN jsonb_build_object(
        'policy_id', v_policy.id,
        'scope_type', COALESCE(v_policy.scope_type, 'Default'),
        'archive_after_months', COALESCE(v_policy.archive_after_months, 3),
        'delete_after_months', COALESCE(v_policy.delete_after_months, 24),
        'retention_hold', COALESCE(v_policy.retention_hold, FALSE),
        'hold_reason', v_policy.hold_reason
    );
END;
$$;

REVOKE ALL ON FUNCTION public.effective_file_retention_044(UUID)
    FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- Administrator retention settings and Project approval clock
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.file_retention_settings_044()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_company_user() THEN
        RAISE EXCEPTION 'Company access required';
    END IF;

    RETURN jsonb_build_object(
        'policies', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', policy.id,
                'scope_type', policy.scope_type,
                'scope_id', CASE
                    WHEN policy.scope_type = 'Client' THEN policy.client_id
                    WHEN policy.scope_type = 'Account' THEN policy.account_id
                    ELSE NULL
                END,
                'scope_name', CASE
                    WHEN policy.scope_type = 'Client' THEN client.name
                    WHEN policy.scope_type = 'Account' THEN
                        COALESCE(account_client.name || ' — ', '') || account.name
                    ELSE 'All Clients (default)'
                END,
                'archive_after_months', policy.archive_after_months,
                'delete_after_months', policy.delete_after_months,
                'retention_hold', policy.retention_hold,
                'hold_reason', policy.hold_reason,
                'updated_at', policy.updated_at
            ) ORDER BY
                CASE policy.scope_type WHEN 'Default' THEN 1 WHEN 'Client' THEN 2 ELSE 3 END,
                CASE
                    WHEN policy.scope_type = 'Client' THEN client.name
                    WHEN policy.scope_type = 'Account' THEN account_client.name || ' — ' || account.name
                    ELSE ''
                END
            FROM public.file_retention_policies policy
            LEFT JOIN public.clients client ON client.id = policy.client_id
            LEFT JOIN public.client_accounts account ON account.id = policy.account_id
            LEFT JOIN public.clients account_client ON account_client.id = account.client_id
        ), '[]'::JSONB),
        'clients', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('id', client.id, 'name', client.name)
                ORDER BY client.name)
            FROM public.clients client
        ), '[]'::JSONB),
        'accounts', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', account.id,
                'client_id', account.client_id,
                'name', client.name || ' — ' || account.name
            ) ORDER BY client.name, account.name)
            FROM public.client_accounts account
            JOIN public.clients client ON client.id = account.client_id
        ), '[]'::JSONB)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_project_file_due_044(p_project_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_project_status TEXT;
    v_policy JSONB;
    v_project_hold BOOLEAN;
    v_anchor TIMESTAMPTZ;
BEGIN
    SELECT project.status INTO v_project_status
    FROM public.projects project WHERE project.id = p_project_id;
    IF NOT FOUND THEN RETURN; END IF;

    INSERT INTO public.project_file_retention(project_id, tracked_project_status)
    VALUES (p_project_id, v_project_status)
    ON CONFLICT (project_id) DO NOTHING;

    v_policy := public.effective_file_retention_044(p_project_id);
    SELECT retention.retention_hold,
           GREATEST(retention.last_approved_at, retention.last_restored_at)
    INTO v_project_hold, v_anchor
    FROM public.project_file_retention retention
    WHERE retention.project_id = p_project_id;

    UPDATE public.project_file_retention
    SET tracked_project_status = v_project_status,
        archive_due_at = CASE
            WHEN v_project_status = 'Approved'
             AND NOT COALESCE(v_project_hold, FALSE)
             AND NOT COALESCE((v_policy->>'retention_hold')::BOOLEAN, FALSE)
             AND v_anchor IS NOT NULL
            THEN v_anchor + make_interval(
                months => COALESCE((v_policy->>'archive_after_months')::INTEGER, 3)
            )
            ELSE NULL
        END
    WHERE project_id = p_project_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_save_file_retention_policy_044(
    p_scope_type TEXT,
    p_scope_id UUID,
    p_archive_after_months INTEGER,
    p_delete_after_months INTEGER,
    p_retention_hold BOOLEAN DEFAULT FALSE,
    p_hold_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_policy_id UUID;
    v_reason TEXT := NULLIF(btrim(COALESCE(p_hold_reason, '')), '');
    v_project RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Administrator access required';
    END IF;
    IF p_scope_type NOT IN ('Default', 'Client', 'Account') THEN
        RAISE EXCEPTION 'Unsupported retention-policy scope';
    END IF;
    IF (p_scope_type = 'Default' AND p_scope_id IS NOT NULL)
       OR (p_scope_type <> 'Default' AND p_scope_id IS NULL) THEN
        RAISE EXCEPTION 'Retention-policy scope is incomplete';
    END IF;
    IF p_archive_after_months NOT BETWEEN 1 AND 120
       OR p_delete_after_months NOT BETWEEN 1 AND 240
       OR p_delete_after_months <= p_archive_after_months THEN
        RAISE EXCEPTION 'Permanent deletion must be later than archive and both periods must be valid';
    END IF;
    IF COALESCE(p_retention_hold, FALSE) AND v_reason IS NULL THEN
        RAISE EXCEPTION 'A reason is required for Retention Hold';
    END IF;
    IF p_scope_type = 'Client'
       AND NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_scope_id) THEN
        RAISE EXCEPTION 'Client not found';
    END IF;
    IF p_scope_type = 'Account'
       AND NOT EXISTS (SELECT 1 FROM public.client_accounts WHERE id = p_scope_id) THEN
        RAISE EXCEPTION 'Account not found';
    END IF;

    SELECT policy.id INTO v_policy_id
    FROM public.file_retention_policies policy
    WHERE (p_scope_type = 'Default' AND policy.scope_type = 'Default')
       OR (p_scope_type = 'Client' AND policy.scope_type = 'Client' AND policy.client_id = p_scope_id)
       OR (p_scope_type = 'Account' AND policy.scope_type = 'Account' AND policy.account_id = p_scope_id)
    FOR UPDATE;

    IF v_policy_id IS NULL THEN
        INSERT INTO public.file_retention_policies (
            scope_type, client_id, account_id, archive_after_months,
            delete_after_months, retention_hold, hold_reason,
            created_by, updated_by
        ) VALUES (
            p_scope_type,
            CASE WHEN p_scope_type = 'Client' THEN p_scope_id END,
            CASE WHEN p_scope_type = 'Account' THEN p_scope_id END,
            p_archive_after_months, p_delete_after_months,
            COALESCE(p_retention_hold, FALSE), v_reason, auth.uid(), auth.uid()
        ) RETURNING id INTO v_policy_id;
    ELSE
        UPDATE public.file_retention_policies
        SET archive_after_months = p_archive_after_months,
            delete_after_months = p_delete_after_months,
            retention_hold = COALESCE(p_retention_hold, FALSE),
            hold_reason = v_reason,
            updated_by = auth.uid()
        WHERE id = v_policy_id;
    END IF;

    FOR v_project IN
        SELECT project.id
        FROM public.projects project
        LEFT JOIN public.client_accounts account ON account.id = project.account_id
        WHERE p_scope_type = 'Default'
           OR (p_scope_type = 'Client' AND project.client_id = p_scope_id)
           OR (p_scope_type = 'Account' AND project.account_id = p_scope_id)
    LOOP
        PERFORM public.recalculate_project_file_due_044(v_project.id);
    END LOOP;

    IF COALESCE(p_retention_hold, FALSE) THEN
        UPDATE public.file_lifecycle_tasks task
        SET status = 'Cancelled',
            completed_at = NOW(),
            last_error = 'Automatic archive cancelled by Retention Hold'
        FROM public.projects project
        WHERE task.project_id = project.id
          AND task.action = 'Archive'
          AND task.status = 'Pending'
          AND task.requested_by IS NULL
          AND (
              p_scope_type = 'Default'
              OR (p_scope_type = 'Client' AND project.client_id = p_scope_id)
              OR (p_scope_type = 'Account' AND project.account_id = p_scope_id)
          );
        UPDATE public.job_file_archives archive
        SET state = 'Failed',
            failure_message = 'Automatic archive cancelled by Retention Hold'
        WHERE archive.state = 'Queued'
          AND EXISTS (
              SELECT 1 FROM public.file_lifecycle_tasks task
              WHERE task.archive_id = archive.id
                AND task.action = 'Archive' AND task.status = 'Cancelled'
          );
    END IF;

    PERFORM public.append_trusted_tms_audit_event(
        'File retention policy', v_policy_id, 'Retention policy saved',
        NULL,
        jsonb_build_object(
            'scope_type', p_scope_type,
            'archive_after_months', p_archive_after_months,
            'delete_after_months', p_delete_after_months,
            'retention_hold', COALESCE(p_retention_hold, FALSE)
        ),
        v_reason
    );
    RETURN v_policy_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_file_retention_policy_044(
    p_policy_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_policy public.file_retention_policies%ROWTYPE;
    v_project RECORD;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator access required'; END IF;
    SELECT * INTO v_policy
    FROM public.file_retention_policies
    WHERE id = p_policy_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Retention policy not found'; END IF;
    IF v_policy.scope_type = 'Default' THEN
        RAISE EXCEPTION 'The default retention policy cannot be deleted';
    END IF;

    DELETE FROM public.file_retention_policies WHERE id = p_policy_id;
    FOR v_project IN
        SELECT project.id
        FROM public.projects project
        WHERE (v_policy.scope_type = 'Client' AND project.client_id = v_policy.client_id)
           OR (v_policy.scope_type = 'Account' AND project.account_id = v_policy.account_id)
    LOOP
        PERFORM public.recalculate_project_file_due_044(v_project.id);
    END LOOP;
    RETURN p_policy_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_project_file_hold_044(
    p_project_id UUID,
    p_retention_hold BOOLEAN,
    p_hold_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reason TEXT := NULLIF(btrim(COALESCE(p_hold_reason, '')), '');
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator access required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
        RAISE EXCEPTION 'Project not found';
    END IF;
    IF COALESCE(p_retention_hold, FALSE) AND v_reason IS NULL THEN
        RAISE EXCEPTION 'A reason is required for Retention Hold';
    END IF;

    INSERT INTO public.project_file_retention (
        project_id, retention_hold, hold_reason, updated_by
    ) VALUES (
        p_project_id, COALESCE(p_retention_hold, FALSE), v_reason, auth.uid()
    )
    ON CONFLICT (project_id) DO UPDATE
    SET retention_hold = EXCLUDED.retention_hold,
        hold_reason = EXCLUDED.hold_reason,
        updated_by = EXCLUDED.updated_by;

    IF COALESCE(p_retention_hold, FALSE) THEN
        UPDATE public.file_lifecycle_tasks
        SET status = 'Cancelled', completed_at = NOW(),
            last_error = 'Automatic archive cancelled by Project Retention Hold'
        WHERE project_id = p_project_id
          AND action = 'Archive' AND status = 'Pending'
          AND requested_by IS NULL;
        UPDATE public.job_file_archives archive
        SET state = 'Failed',
            failure_message = 'Automatic archive cancelled by Project Retention Hold'
        WHERE archive.project_id = p_project_id AND archive.state = 'Queued'
          AND EXISTS (
              SELECT 1 FROM public.file_lifecycle_tasks task
              WHERE task.archive_id = archive.id
                AND task.action = 'Archive' AND task.status = 'Cancelled'
          );
    END IF;
    PERFORM public.recalculate_project_file_due_044(p_project_id);
    PERFORM public.append_trusted_tms_audit_event(
        'Project', p_project_id,
        CASE WHEN COALESCE(p_retention_hold, FALSE)
             THEN 'File Retention Hold enabled' ELSE 'File Retention Hold removed' END,
        NULL,
        jsonb_build_object('retention_hold', COALESCE(p_retention_hold, FALSE)),
        v_reason
    );
    RETURN p_project_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.track_project_file_retention_044()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.project_file_retention (
            project_id, last_approved_at, tracked_project_status
        ) VALUES (
            NEW.id, CASE WHEN NEW.status = 'Approved' THEN NOW() END, NEW.status
        )
        ON CONFLICT (project_id) DO UPDATE
        SET last_approved_at = CASE
                WHEN NEW.status = 'Approved'
                 AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Approved')
                THEN NOW()
                ELSE public.project_file_retention.last_approved_at
            END,
            tracked_project_status = NEW.status;

        IF NEW.status IS DISTINCT FROM 'Approved' THEN
            UPDATE public.file_lifecycle_tasks
            SET status = 'Cancelled', completed_at = NOW(),
                last_error = 'Automatic archive cancelled because Project left Approved'
            WHERE project_id = NEW.id
              AND action = 'Archive' AND status = 'Pending'
              AND requested_by IS NULL;
            UPDATE public.job_file_archives archive
            SET state = 'Failed',
                failure_message = 'Automatic archive cancelled because Project left Approved'
            WHERE archive.project_id = NEW.id AND archive.state = 'Queued'
              AND EXISTS (
                  SELECT 1 FROM public.file_lifecycle_tasks task
                  WHERE task.archive_id = archive.id
                    AND task.action = 'Archive' AND task.status = 'Cancelled'
              );
        END IF;
        PERFORM public.recalculate_project_file_due_044(NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS projects_track_file_retention_044 ON public.projects;
CREATE TRIGGER projects_track_file_retention_044
AFTER INSERT OR UPDATE OF status ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.track_project_file_retention_044();

INSERT INTO public.project_file_retention (
    project_id, last_approved_at, tracked_project_status
)
SELECT project.id,
       CASE WHEN project.status = 'Approved' THEN COALESCE((
           SELECT max(event.occurred_at)
           FROM public.audit_events event
           WHERE event.entity_type = 'Project'
             AND event.entity_id = project.id
             AND event.after_values->>'status' = 'Approved'
       ), project.updated_at, project.created_at, NOW()) END,
       project.status
FROM public.projects project
ON CONFLICT (project_id) DO NOTHING;

DO $$
DECLARE v_project RECORD;
BEGIN
    FOR v_project IN SELECT id FROM public.projects LOOP
        PERFORM public.recalculate_project_file_due_044(v_project.id);
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.file_retention_settings_044()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.recalculate_project_file_due_044(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_save_file_retention_policy_044(
    TEXT, UUID, INTEGER, INTEGER, BOOLEAN, TEXT
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_delete_file_retention_policy_044(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_project_file_hold_044(UUID, BOOLEAN, TEXT)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.track_project_file_retention_044()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.file_retention_settings_044()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_save_file_retention_policy_044(
    TEXT, UUID, INTEGER, INTEGER, BOOLEAN, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_file_retention_policy_044(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_project_file_hold_044(UUID, BOOLEAN, TEXT)
    TO authenticated;

-- -------------------------------------------------------------------------
-- Server-only R2 authorization dispatcher
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.r2_file_dispatch_044(
    p_action TEXT,
    p_actor_id UUID,
    p_file_id UUID DEFAULT NULL,
    p_job_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_resource_id UUID;
    v_file public.file_records%ROWTYPE;
    v_job public.project_jobs%ROWTYPE;
    v_file_id UUID;
    v_archive_id UUID;
    v_archive public.job_file_archives%ROWTYPE;
    v_policy JSONB;
    v_filename TEXT;
    v_safe_filename TEXT;
    v_checksum TEXT;
    v_size BIGINT;
    v_bucket TEXT;
    v_file_role TEXT;
    v_object_key TEXT;
    v_action TEXT := lower(btrim(COALESCE(p_action, '')));
    v_download_action TEXT;
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', TRUE), '') <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;
    IF p_actor_id IS NULL THEN RAISE EXCEPTION 'Verified actor is required'; END IF;

    SELECT profile.role INTO v_role
    FROM public.profiles profile
    WHERE profile.id = p_actor_id;
    IF v_role IS NULL THEN RAISE EXCEPTION 'Active TMS profile required'; END IF;

    SELECT resource.id INTO v_resource_id
    FROM public.resources resource
    JOIN auth.users app_user ON app_user.id = resource.profile_id
    WHERE resource.profile_id = p_actor_id
      AND v_role = 'resource'
      AND lower(app_user.email) = lower(NULLIF(btrim(resource.email), ''))
      AND resource.resource_type IN ('Freelancer', 'Company')
      AND resource.portal_status IN ('Active', 'Read-only')
      AND resource.lifecycle_status IN ('Active', 'On leave')
    LIMIT 1;

    IF v_action = 'prepare_upload' THEN
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
            RAISE EXCEPTION 'Operational access required';
        END IF;
        SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id;
        IF NOT FOUND OR v_job.resource_id IS NULL THEN
            RAISE EXCEPTION 'An External Resource must be assigned before adding a Job file';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.resources resource
            WHERE resource.id = v_job.resource_id
              AND resource.resource_type IN ('Freelancer', 'Company')
        ) THEN
            RAISE EXCEPTION 'The assigned Resource is not an External Resource';
        END IF;
        IF EXISTS (
            SELECT 1 FROM public.job_file_archives archive
            WHERE archive.job_id = p_job_id
              AND archive.state IN ('Queued', 'Archiving', 'Archived', 'Restoring')
        ) THEN
            RAISE EXCEPTION 'Restore this Job archive before adding another file';
        END IF;

        v_filename := btrim(COALESCE(p_payload->>'original_filename', ''));
        v_checksum := lower(btrim(COALESCE(p_payload->>'checksum_sha256', '')));
        v_size := NULLIF(p_payload->>'size_bytes', '')::BIGINT;
        v_bucket := btrim(COALESCE(p_payload->>'bucket_name', ''));
        v_file_role := btrim(COALESCE(p_payload->>'file_role', ''));
        IF v_filename = '' OR length(v_filename) > 255 THEN
            RAISE EXCEPTION 'A filename between 1 and 255 characters is required';
        END IF;
        IF v_checksum !~ '^[0-9a-f]{64}$' THEN
            RAISE EXCEPTION 'A SHA-256 checksum is required';
        END IF;
        IF v_size IS NULL OR v_size < 0 OR v_size > 5363466240 THEN
            RAISE EXCEPTION 'File size exceeds the supported R2 single-upload limit';
        END IF;
        IF v_bucket = '' OR length(v_bucket) > 128 THEN
            RAISE EXCEPTION 'Private R2 bucket is not configured';
        END IF;
        IF v_file_role NOT IN ('Source', 'Reference', 'Instructions', 'Delivery', 'Other') THEN
            RAISE EXCEPTION 'Unsupported Job file role';
        END IF;

        v_file_id := gen_random_uuid();
        v_safe_filename := regexp_replace(v_filename, '[^A-Za-z0-9._-]+', '_', 'g');
        v_safe_filename := regexp_replace(v_safe_filename, '^\.+', '');
        IF v_safe_filename = '' THEN v_safe_filename := 'file'; END IF;
        v_object_key := format(
            'active/projects/%s/jobs/%s/%s/%s',
            v_job.project_id, v_job.id, v_file_id, v_safe_filename
        );

        INSERT INTO public.file_records (
            id, project_id, job_id, resource_id, storage_provider,
            bucket_name, object_key, original_filename, mime_type,
            size_bytes, file_role, checksum_sha256, archived_at,
            uploaded_by, upload_status, storage_class
        ) VALUES (
            v_file_id, v_job.project_id, v_job.id, v_job.resource_id,
            'Cloudflare R2', v_bucket, v_object_key, v_filename,
            NULLIF(btrim(COALESCE(p_payload->>'mime_type', '')), ''),
            v_size, v_file_role, v_checksum, NOW(), p_actor_id,
            'Pending', 'STANDARD'
        );
        RETURN jsonb_build_object(
            'file_id', v_file_id,
            'object_key', v_object_key,
            'checksum_sha256', v_checksum,
            'mime_type', COALESCE(NULLIF(btrim(p_payload->>'mime_type'), ''), 'application/octet-stream')
        );
    END IF;

    IF v_action IN ('inspect_upload', 'publish_upload', 'fail_upload', 'discard_upload') THEN
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
            RAISE EXCEPTION 'Operational access required';
        END IF;
        SELECT * INTO v_file
        FROM public.file_records file
        WHERE file.id = p_file_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.upload_status = 'Pending'
        FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Pending Job file not found'; END IF;

        IF v_action = 'inspect_upload' THEN
            RETURN jsonb_build_object(
                'file_id', v_file.id,
                'object_key', v_file.object_key,
                'size_bytes', v_file.size_bytes,
                'checksum_sha256', v_file.checksum_sha256
            );
        ELSIF v_action = 'publish_upload' THEN
            IF NULLIF(p_payload->>'verified_size_bytes', '')::BIGINT IS DISTINCT FROM v_file.size_bytes
               OR lower(COALESCE(p_payload->>'verified_checksum_sha256', ''))
                    IS DISTINCT FROM lower(COALESCE(v_file.checksum_sha256, '')) THEN
                RAISE EXCEPTION 'R2 upload verification does not match the file record';
            END IF;
            UPDATE public.file_records
            SET upload_status = 'Ready', archived_at = NULL,
                verified_at = NOW(), storage_error = NULL,
                r2_etag = NULLIF(p_payload->>'r2_etag', ''),
                r2_version_id = NULLIF(p_payload->>'r2_version_id', ''),
                storage_class = COALESCE(NULLIF(p_payload->>'storage_class', ''), 'STANDARD')
            WHERE id = v_file.id;
            INSERT INTO public.file_access_logs(
                file_record_id, profile_id, resource_id, action
            ) VALUES (v_file.id, p_actor_id, v_file.resource_id, 'Upload');
            RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Ready');
        ELSE
            UPDATE public.file_records
            SET upload_status = 'Failed', archived_at = COALESCE(archived_at, NOW()),
                storage_error = left(COALESCE(NULLIF(p_payload->>'reason', ''),
                    'Pending upload discarded'), 500)
            WHERE id = v_file.id;
            RETURN jsonb_build_object('file_id', v_file.id, 'status', 'Failed');
        END IF;
    END IF;

    IF v_action = 'authorize_download' THEN
        SELECT * INTO v_file
        FROM public.file_records file
        WHERE file.id = p_file_id
          AND file.storage_provider = 'Cloudflare R2'
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL;
        IF NOT FOUND THEN RAISE EXCEPTION 'Job file not found'; END IF;

        IF v_role IN ('admin', 'pm', 'qa', 'client_relations') THEN
            NULL;
        ELSIF v_role = 'resource'
          AND v_resource_id IS NOT NULL
          AND (v_file.resource_id IS NULL OR v_file.resource_id = v_resource_id)
          AND EXISTS (
              SELECT 1 FROM public.project_jobs job
              WHERE job.id = v_file.job_id AND job.resource_id = v_resource_id
          ) THEN
            NULL;
        ELSE
            RAISE EXCEPTION 'Job file not found';
        END IF;

        v_download_action := CASE
            WHEN p_payload->>'file_action' = 'Download' THEN 'Download' ELSE 'View' END;
        INSERT INTO public.file_access_logs(
            file_record_id, profile_id, resource_id, action
        ) VALUES (
            v_file.id, p_actor_id,
            CASE WHEN v_role = 'resource' THEN v_resource_id ELSE v_file.resource_id END,
            v_download_action
        );
        RETURN jsonb_build_object(
            'file_id', v_file.id,
            'storage_provider', v_file.storage_provider,
            'bucket_name', v_file.bucket_name,
            'object_key', v_file.object_key,
            'original_filename', v_file.original_filename,
            'mime_type', v_file.mime_type
        );
    END IF;

    IF v_action = 'queue_archive' THEN
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
            RAISE EXCEPTION 'Operational access required';
        END IF;
        SELECT * INTO v_job FROM public.project_jobs WHERE id = p_job_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
        IF EXISTS (
            SELECT 1 FROM public.job_file_archives archive
            WHERE archive.job_id = p_job_id
              AND archive.state IN ('Queued', 'Archiving', 'Archived', 'Restoring')
        ) THEN RAISE EXCEPTION 'This Job already has a live file archive'; END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.file_records file
            WHERE file.job_id = p_job_id
              AND file.storage_provider = 'Cloudflare R2'
              AND file.upload_status = 'Ready' AND file.archived_at IS NULL
        ) THEN RAISE EXCEPTION 'This Job has no active R2 files to archive'; END IF;
        v_policy := public.effective_file_retention_044(v_job.project_id);
        IF COALESCE((v_policy->>'retention_hold')::BOOLEAN, FALSE)
           OR COALESCE((SELECT retention_hold FROM public.project_file_retention
                        WHERE project_id = v_job.project_id), FALSE) THEN
            RAISE EXCEPTION 'Retention Hold must be removed before archiving';
        END IF;

        v_archive_id := gen_random_uuid();
        INSERT INTO public.job_file_archives(
            id, project_id, job_id, archive_object_key,
            delete_after_months, requested_by
        ) VALUES (
            v_archive_id, v_job.project_id, v_job.id,
            format('archives/projects/%s/jobs/%s/%s.zip',
                v_job.project_id, v_job.id, v_archive_id),
            COALESCE((v_policy->>'delete_after_months')::INTEGER, 24),
            p_actor_id
        );
        INSERT INTO public.file_lifecycle_tasks(
            archive_id, project_id, job_id, action, requested_by
        ) VALUES (v_archive_id, v_job.project_id, v_job.id, 'Archive', p_actor_id);
        RETURN jsonb_build_object(
            'archive_id', v_archive_id, 'status', 'Queued', 'action', 'Archive'
        );
    END IF;

    IF v_action = 'queue_restore' THEN
        IF v_role NOT IN ('admin', 'pm', 'client_relations') THEN
            RAISE EXCEPTION 'Operational access required';
        END IF;
        SELECT archive.* INTO v_archive
        FROM public.job_file_archives archive
        WHERE archive.job_id = p_job_id AND archive.state = 'Archived'
        ORDER BY archive.archived_at DESC
        LIMIT 1 FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Restorable Job archive not found'; END IF;

        IF EXISTS (
            SELECT 1 FROM public.file_lifecycle_tasks task
            WHERE task.job_id = v_archive.job_id
              AND task.action = 'CleanupSources'
              AND task.status = 'Processing'
        ) THEN
            RAISE EXCEPTION 'Verified ZIP cleanup is in progress; retry restore shortly';
        END IF;
        UPDATE public.file_lifecycle_tasks
        SET status = 'Cancelled', completed_at = NOW(),
            last_error = 'Source cleanup cancelled by restore request'
        WHERE job_id = v_archive.job_id
          AND action = 'CleanupSources' AND status = 'Pending';

        UPDATE public.job_file_archives SET state = 'Restoring', failure_message = NULL
        WHERE id = v_archive.id;
        UPDATE public.file_records SET upload_status = 'Restoring', storage_error = NULL
        WHERE archive_id = v_archive.id AND upload_status = 'Archived';
        INSERT INTO public.file_lifecycle_tasks(
            archive_id, project_id, job_id, action, requested_by
        ) VALUES (v_archive.id, v_archive.project_id, v_archive.job_id, 'Restore', p_actor_id);
        RETURN jsonb_build_object(
            'archive_id', v_archive.id, 'status', 'Queued', 'action', 'Restore'
        );
    END IF;

    RAISE EXCEPTION 'Unsupported R2 file action';
END;
$$;

REVOKE ALL ON FUNCTION public.r2_file_dispatch_044(
    TEXT, UUID, UUID, UUID, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.r2_file_dispatch_044(
    TEXT, UUID, UUID, UUID, JSONB
) TO service_role;

-- -------------------------------------------------------------------------
-- Least-privilege Resource projections and staff lifecycle summary
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resource_portal_jobs()
RETURNS TABLE (
    job_id UUID,
    job_number TEXT,
    project_number TEXT,
    scoop_number TEXT,
    job_status TEXT,
    service_type TEXT,
    source_language TEXT,
    target_language TEXT,
    specialization_name TEXT,
    deadline TIMESTAMPTZ,
    quantity NUMERIC,
    unit TEXT,
    instructions TEXT,
    purchase_order_id UUID,
    purchase_order_number TEXT,
    purchase_order_status TEXT,
    purchase_order_version INTEGER,
    purchase_order_total NUMERIC,
    purchase_order_currency TEXT,
    issue_count BIGINT,
    file_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;

    RETURN QUERY
    SELECT
        job.id, job.job_number, project.project_number, scoop.scoop_number,
        job.status, job.service_type, job.source_language, job.target_language,
        specialization.name, job.deadline, job.quantity, job.unit,
        COALESCE(NULLIF(btrim(job.assignment_notes), ''), NULLIF(btrim(job.notes), '')),
        po.id, po.po_number, po.status, po.current_version, po.total, po.currency,
        (SELECT count(*) FROM public.job_issues issue WHERE issue.job_id = job.id),
        (
            SELECT count(*) FROM public.file_records file
            WHERE file.job_id = job.id
              AND file.upload_status = 'Ready'
              AND file.archived_at IS NULL
              AND (file.resource_id IS NULL OR file.resource_id = v_resource_id)
        )
    FROM public.project_jobs job
    JOIN public.projects project ON project.id = job.project_id
    JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    LEFT JOIN public.specializations specialization ON specialization.id = job.specialization_id
    LEFT JOIN LATERAL (
        SELECT purchase_order.id, purchase_order.po_number, purchase_order.status,
               immutable.version_number AS current_version,
               COALESCE(NULLIF(immutable.snapshot->>'total', '')::NUMERIC,
                        purchase_order.total) AS total,
               COALESCE(NULLIF(immutable.snapshot->>'currency', ''),
                        purchase_order.currency) AS currency
        FROM public.supplier_purchase_orders purchase_order
        JOIN LATERAL (
            SELECT version.version_number, version.snapshot
            FROM public.supplier_po_versions version
            WHERE version.purchase_order_id = purchase_order.id
            ORDER BY version.version_number DESC LIMIT 1
        ) immutable ON TRUE
        WHERE purchase_order.job_id = job.id
          AND purchase_order.resource_id = v_resource_id
          AND purchase_order.status IN ('Issued', 'Acknowledged')
        ORDER BY COALESCE(purchase_order.issued_at, purchase_order.created_at) DESC
        LIMIT 1
    ) po ON TRUE
    WHERE job.resource_id = v_resource_id
    ORDER BY job.deadline NULLS LAST, job.job_number;
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_job(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_job public.project_jobs%ROWTYPE;
    v_project_number TEXT;
    v_scoop_number TEXT;
    v_specialization_name TEXT;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    SELECT job.* INTO v_job
    FROM public.project_jobs job
    WHERE job.id = p_job_id AND job.resource_id = v_resource_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assigned Job not found'; END IF;

    SELECT project.project_number, scoop.scoop_number, specialization.name
    INTO v_project_number, v_scoop_number, v_specialization_name
    FROM public.projects project
    JOIN public.project_scoops scoop ON scoop.id = v_job.project_scoop_id
    LEFT JOIN public.specializations specialization ON specialization.id = v_job.specialization_id
    WHERE project.id = v_job.project_id;

    RETURN jsonb_build_object(
        'job', jsonb_build_object(
            'id', v_job.id,
            'job_number', v_job.job_number,
            'project_number', v_project_number,
            'scoop_number', v_scoop_number,
            'status', v_job.status,
            'service_type', v_job.service_type,
            'source_language', v_job.source_language,
            'target_language', v_job.target_language,
            'specialization', v_specialization_name,
            'deadline', v_job.deadline,
            'quantity', v_job.quantity,
            'unit', v_job.unit,
            'instructions', COALESCE(
                NULLIF(btrim(v_job.assignment_notes), ''),
                NULLIF(btrim(v_job.notes), '')
            )
        ),
        'purchase_orders', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', po.id,
                'po_number', po.po_number,
                'status', po.status,
                'current_version', immutable.version_number,
                'currency', COALESCE(NULLIF(immutable.snapshot->>'currency', ''), po.currency),
                'total', COALESCE(NULLIF(immutable.snapshot->>'total', '')::NUMERIC, po.total),
                'issued_at', po.issued_at,
                'acknowledged_at', po.acknowledged_at
            ) ORDER BY COALESCE(po.issued_at, po.created_at) DESC)
            FROM public.supplier_purchase_orders po
            JOIN LATERAL (
                SELECT version.version_number, version.snapshot
                FROM public.supplier_po_versions version
                WHERE version.purchase_order_id = po.id
                ORDER BY version.version_number DESC LIMIT 1
            ) immutable ON TRUE
            WHERE po.job_id = v_job.id
              AND po.resource_id = v_resource_id
              AND po.status IN ('Issued', 'Acknowledged')
        ), '[]'::JSONB),
        'files', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', file.id,
                'filename', file.original_filename,
                'file_role', file.file_role,
                'mime_type', file.mime_type,
                'size_bytes', file.size_bytes,
                'storage_provider', file.storage_provider,
                'bucket_name', CASE WHEN file.storage_provider = 'Supabase'
                                    THEN file.bucket_name END,
                'object_key', CASE WHEN file.storage_provider = 'Supabase'
                                   THEN file.object_key END,
                'external_url', CASE WHEN file.storage_provider NOT IN ('Supabase', 'Cloudflare R2')
                                     THEN file.external_url END,
                'created_at', file.created_at
            ) ORDER BY file.created_at DESC)
            FROM public.file_records file
            WHERE file.job_id = v_job.id
              AND file.upload_status = 'Ready'
              AND file.archived_at IS NULL
              AND (file.resource_id IS NULL OR file.resource_id = v_resource_id)
        ), '[]'::JSONB),
        'issues', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', issue.id,
                'status', issue.status,
                'severity', issue.severity,
                'description', issue.description,
                'resolution', issue.resolution,
                'reported_at', issue.reported_at,
                'resolved_at', issue.resolved_at
            ) ORDER BY issue.reported_at DESC)
            FROM public.job_issues issue
            WHERE issue.job_id = v_job.id
        ), '[]'::JSONB)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_can_access_file(p_file_record_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.file_records file
        JOIN public.project_jobs job ON job.id = file.job_id
        WHERE file.id = p_file_record_id
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND job.resource_id = public.current_external_resource_id()
          AND (file.resource_id IS NULL
               OR file.resource_id = public.current_external_resource_id())
    ), FALSE)
$$;

CREATE OR REPLACE FUNCTION public.resource_can_access_storage_object(
    p_bucket_name TEXT,
    p_object_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.file_records file
        JOIN public.project_jobs job ON job.id = file.job_id
        WHERE file.storage_provider = 'Supabase'
          AND file.bucket_name = p_bucket_name
          AND file.object_key = p_object_key
          AND file.upload_status = 'Ready'
          AND file.archived_at IS NULL
          AND job.resource_id = public.current_external_resource_id()
          AND (file.resource_id IS NULL
               OR file.resource_id = public.current_external_resource_id())
    ), FALSE)
$$;

CREATE OR REPLACE FUNCTION public.staff_job_file_lifecycle_044(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_project_id UUID;
    v_policy JSONB;
    v_retention public.project_file_retention%ROWTYPE;
    v_archive public.job_file_archives%ROWTYPE;
BEGIN
    IF NOT public.is_company_user() THEN RAISE EXCEPTION 'Company access required'; END IF;
    SELECT project_id INTO v_project_id FROM public.project_jobs WHERE id = p_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
    v_policy := public.effective_file_retention_044(v_project_id);
    SELECT * INTO v_retention FROM public.project_file_retention
    WHERE project_id = v_project_id;
    SELECT * INTO v_archive FROM public.job_file_archives
    WHERE job_id = p_job_id
    ORDER BY created_at DESC LIMIT 1;

    RETURN jsonb_build_object(
        'job_id', p_job_id,
        'project_id', v_project_id,
        'archive_after_months', COALESCE((v_policy->>'archive_after_months')::INTEGER, 3),
        'delete_after_months', COALESCE((v_policy->>'delete_after_months')::INTEGER, 24),
        'retention_hold', COALESCE(v_retention.retention_hold, FALSE)
            OR COALESCE((v_policy->>'retention_hold')::BOOLEAN, FALSE),
        'hold_reason', COALESCE(v_retention.hold_reason, v_policy->>'hold_reason'),
        'archive_due_at', v_retention.archive_due_at,
        'archive', CASE WHEN v_archive.id IS NULL THEN NULL ELSE jsonb_build_object(
            'id', v_archive.id,
            'state', v_archive.state,
            'strategy', v_archive.strategy,
            'file_count', v_archive.file_count,
            'original_size_bytes', v_archive.original_size_bytes,
            'archive_size_bytes', v_archive.archive_size_bytes,
            'archived_at', v_archive.archived_at,
            'delete_due_at', v_archive.delete_due_at,
            'restored_at', v_archive.restored_at,
            'failure_message', v_archive.failure_message
        ) END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_jobs() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_job(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_can_access_file(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_can_access_storage_object(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.staff_job_file_lifecycle_044(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_jobs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_job(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_can_access_file(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_can_access_storage_object(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_job_file_lifecycle_044(UUID) TO authenticated;

-- New uploads no longer enter Supabase Storage directly. Legacy objects remain
-- private/readable under their existing exact-object policies until migrated.
DO $$
BEGIN
    IF to_regclass('storage.objects') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS tms_job_files_operations_insert ON storage.objects';
    END IF;
END;
$$;

COMMIT;
