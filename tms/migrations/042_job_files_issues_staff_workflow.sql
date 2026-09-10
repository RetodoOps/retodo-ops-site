-- RetodoOps TMS — Update 044 / staff Job files and issues workflow
-- Forward-only migration. Do not edit migrations 036–041.
-- External Resources retain read/download-only access through the narrow
-- Update 038 projections; no direct company-table Resource policy is added.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.file_records') IS NULL
       OR to_regclass('public.file_access_logs') IS NULL
       OR to_regclass('public.job_issues') IS NULL
       OR to_regclass('public.project_jobs') IS NULL
       OR to_regclass('public.resources') IS NULL
       OR to_regclass('public.supplier_purchase_orders') IS NULL
       OR to_regclass('public.supplier_po_versions') IS NULL
       OR to_regprocedure('public.current_external_resource_id()') IS NULL
       OR to_regprocedure('public.current_external_financial_resource_id()') IS NULL
       OR to_regprocedure('public.can_manage_operations()') IS NULL
       OR to_regprocedure('public.is_company_user()') IS NULL THEN
        RAISE EXCEPTION
            'Migration 042 requires the operational core and migrations 036–041';
    END IF;
END;
$$;

-- Existing active/archived rows remain semantically unchanged. Pending is used
-- only while a private Storage upload is being completed.
ALTER TABLE public.file_records
    ADD COLUMN IF NOT EXISTS upload_status TEXT;

UPDATE public.file_records
SET upload_status = CASE
    WHEN archived_at IS NULL THEN 'Ready'
    ELSE 'Archived'
END
WHERE upload_status IS NULL;

ALTER TABLE public.file_records
    ALTER COLUMN upload_status SET DEFAULT 'Ready',
    ALTER COLUMN upload_status SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.file_records'::regclass
          AND conname = 'file_records_upload_status_check'
    ) THEN
        ALTER TABLE public.file_records
            ADD CONSTRAINT file_records_upload_status_check
            CHECK (upload_status IN ('Pending', 'Ready', 'Archived'));
    END IF;
END;
$$;

-- A single private bucket is used for staff-provided Job files. No public URL
-- is enabled and no Resource INSERT/UPDATE/DELETE policy is created.
DO $$
BEGIN
    IF to_regclass('storage.buckets') IS NOT NULL THEN
        INSERT INTO storage.buckets (id, name, public)
        VALUES ('tms-job-files', 'tms-job-files', FALSE)
        ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name,
            public = FALSE;
    END IF;
END;
$$;

-- Keep every Resource-dashboard surface aligned: the summary count, the PO
-- linked from My Jobs and the PO table include active POs only. Earlier
-- immutable versions remain available inside the secure PO detail page.
CREATE OR REPLACE FUNCTION public.resource_portal_context()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_financial_resource_id();
    v_work_resource_id UUID := public.current_external_resource_id();
    v_result JSONB;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'External Resource portal access required';
    END IF;

    SELECT jsonb_build_object(
        'resource_number', resource.internal_number,
        'display_name', COALESCE(
            NULLIF(btrim(resource.legal_name), ''),
            NULLIF(btrim(resource.company_name), ''),
            resource.internal_number
        ),
        'portal_status', resource.portal_status,
        'can_view_jobs', v_work_resource_id IS NOT NULL,
        'can_view_financials', TRUE,
        'job_count', CASE WHEN v_work_resource_id IS NULL THEN 0 ELSE (
            SELECT count(*)
            FROM public.project_jobs job
            WHERE job.resource_id = v_work_resource_id
        ) END,
        'purchase_order_count', (
            SELECT count(*)
            FROM public.supplier_purchase_orders po
            WHERE po.resource_id = v_resource_id
              AND po.status IN ('Issued', 'Acknowledged')
              AND EXISTS (
                  SELECT 1
                  FROM public.supplier_po_versions version
                  WHERE version.purchase_order_id = po.id
              )
        )
    ) INTO v_result
    FROM public.resources resource
    WHERE resource.id = v_resource_id;

    RETURN v_result;
END;
$$;

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
        job.id,
        job.job_number,
        project.project_number,
        scoop.scoop_number,
        job.status,
        job.service_type,
        job.source_language,
        job.target_language,
        specialization.name,
        job.deadline,
        job.quantity,
        job.unit,
        COALESCE(
            NULLIF(btrim(job.assignment_notes), ''),
            NULLIF(btrim(job.notes), '')
        ),
        po.id,
        po.po_number,
        po.status,
        po.current_version,
        po.total,
        po.currency,
        (
            SELECT count(*)
            FROM public.job_issues issue
            WHERE issue.job_id = job.id
        ),
        (
            SELECT count(*)
            FROM public.file_records file
            WHERE file.job_id = job.id
              AND file.archived_at IS NULL
              AND (file.resource_id IS NULL OR file.resource_id = v_resource_id)
        )
    FROM public.project_jobs job
    JOIN public.projects project ON project.id = job.project_id
    JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    LEFT JOIN public.specializations specialization
        ON specialization.id = job.specialization_id
    LEFT JOIN LATERAL (
        SELECT
            purchase_order.id,
            purchase_order.po_number,
            purchase_order.status,
            immutable.version_number AS current_version,
            COALESCE(
                NULLIF(immutable.snapshot->>'total', '')::NUMERIC,
                purchase_order.total
            ) AS total,
            COALESCE(
                NULLIF(immutable.snapshot->>'currency', ''),
                purchase_order.currency
            ) AS currency
        FROM public.supplier_purchase_orders purchase_order
        JOIN LATERAL (
            SELECT version.version_number, version.snapshot
            FROM public.supplier_po_versions version
            WHERE version.purchase_order_id = purchase_order.id
            ORDER BY version.version_number DESC
            LIMIT 1
        ) immutable ON TRUE
        WHERE purchase_order.job_id = job.id
          AND purchase_order.resource_id = v_resource_id
          AND purchase_order.status IN ('Issued', 'Acknowledged')
        ORDER BY COALESCE(
            purchase_order.issued_at,
            purchase_order.created_at
        ) DESC
        LIMIT 1
    ) po ON TRUE
    WHERE job.resource_id = v_resource_id
    ORDER BY job.deadline NULLS LAST, job.job_number;
END;
$$;

CREATE OR REPLACE FUNCTION public.resource_portal_purchase_orders()
RETURNS TABLE (
    purchase_order_id UUID,
    purchase_order_number TEXT,
    purchase_order_status TEXT,
    current_version INTEGER,
    currency TEXT,
    total NUMERIC,
    issued_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    job_number TEXT,
    project_number TEXT,
    scoop_number TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_id UUID := public.current_external_financial_resource_id();
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'External Resource financial access required';
    END IF;

    RETURN QUERY
    SELECT
        po.id,
        po.po_number,
        po.status,
        version.version_number,
        COALESCE(NULLIF(version.snapshot->>'currency', ''), po.currency),
        COALESCE(NULLIF(version.snapshot->>'total', '')::NUMERIC, po.total),
        po.issued_at,
        po.acknowledged_at,
        COALESCE(version.snapshot->'job'->>'job_number', job.job_number),
        project.project_number,
        scoop.scoop_number
    FROM public.supplier_purchase_orders po
    JOIN LATERAL (
        SELECT immutable.version_number, immutable.snapshot
        FROM public.supplier_po_versions immutable
        WHERE immutable.purchase_order_id = po.id
        ORDER BY immutable.version_number DESC
        LIMIT 1
    ) version ON TRUE
    LEFT JOIN public.project_jobs job ON job.id = po.job_id
    LEFT JOIN public.projects project ON project.id = po.project_id
    LEFT JOIN public.project_scoops scoop ON scoop.id = job.project_scoop_id
    WHERE po.resource_id = v_resource_id
      AND po.status IN ('Issued', 'Acknowledged')
    ORDER BY COALESCE(po.issued_at, po.created_at) DESC, po.po_number DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.resource_portal_context()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_jobs()
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_portal_purchase_orders()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_portal_context()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_jobs()
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_portal_purchase_orders()
    TO authenticated;

CREATE OR REPLACE FUNCTION public.staff_prepare_job_file_upload(
    p_job_id UUID,
    p_original_filename TEXT,
    p_mime_type TEXT,
    p_size_bytes BIGINT,
    p_file_role TEXT,
    p_checksum_sha256 TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_project_id UUID;
    v_resource_id UUID;
    v_file_id UUID := gen_random_uuid();
    v_filename TEXT := btrim(COALESCE(p_original_filename, ''));
    v_safe_filename TEXT;
    v_object_key TEXT;
    v_checksum TEXT := lower(NULLIF(btrim(COALESCE(p_checksum_sha256, '')), ''));
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;

    IF v_filename = '' OR length(v_filename) > 255 THEN
        RAISE EXCEPTION 'A filename between 1 and 255 characters is required';
    END IF;
    IF p_size_bytes IS NULL OR p_size_bytes < 0 THEN
        RAISE EXCEPTION 'File size is invalid';
    END IF;
    IF p_file_role NOT IN ('Source', 'Reference', 'Instructions', 'Delivery', 'Other') THEN
        RAISE EXCEPTION 'Unsupported Job file role';
    END IF;
    IF v_checksum IS NOT NULL AND v_checksum !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'File checksum must be SHA-256';
    END IF;

    SELECT job.project_id, job.resource_id
    INTO v_project_id, v_resource_id
    FROM public.project_jobs job
    JOIN public.resources resource ON resource.id = job.resource_id
    WHERE job.id = p_job_id
      AND resource.resource_type IN ('Freelancer', 'Company');

    IF NOT FOUND OR v_resource_id IS NULL THEN
        RAISE EXCEPTION 'An External Resource must be assigned before adding a Job file';
    END IF;

    v_safe_filename := regexp_replace(v_filename, '[^A-Za-z0-9._-]+', '_', 'g');
    v_safe_filename := regexp_replace(v_safe_filename, '^\.+', '');
    IF v_safe_filename = '' THEN
        v_safe_filename := 'file';
    END IF;
    v_object_key := format(
        'jobs/%s/%s/%s/%s',
        p_job_id,
        v_resource_id,
        v_file_id,
        v_safe_filename
    );

    INSERT INTO public.file_records (
        id,
        project_id,
        job_id,
        resource_id,
        storage_provider,
        bucket_name,
        object_key,
        original_filename,
        mime_type,
        size_bytes,
        file_role,
        checksum_sha256,
        archived_at,
        uploaded_by,
        upload_status
    ) VALUES (
        v_file_id,
        v_project_id,
        p_job_id,
        v_resource_id,
        'Supabase',
        'tms-job-files',
        v_object_key,
        v_filename,
        NULLIF(btrim(COALESCE(p_mime_type, '')), ''),
        p_size_bytes,
        p_file_role,
        v_checksum,
        NOW(),
        auth.uid(),
        'Pending'
    );

    RETURN jsonb_build_object(
        'file_id', v_file_id,
        'bucket_name', 'tms-job-files',
        'object_key', v_object_key
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_publish_job_file_upload(
    p_file_record_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_file public.file_records%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;

    SELECT *
    INTO v_file
    FROM public.file_records
    WHERE id = p_file_record_id
      AND storage_provider = 'Supabase'
      AND upload_status = 'Pending'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pending Job file not found';
    END IF;
    IF to_regclass('storage.objects') IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM storage.objects object
           WHERE object.bucket_id = v_file.bucket_name
             AND object.name = v_file.object_key
       ) THEN
        RAISE EXCEPTION 'The private file upload is not present';
    END IF;

    UPDATE public.file_records
    SET upload_status = 'Ready',
        archived_at = NULL
    WHERE id = v_file.id;

    INSERT INTO public.file_access_logs (
        file_record_id,
        profile_id,
        resource_id,
        action
    ) VALUES (
        v_file.id,
        auth.uid(),
        v_file.resource_id,
        'Upload'
    );

    RETURN v_file.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_archive_job_file(
    p_file_record_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_file public.file_records%ROWTYPE;
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;

    SELECT *
    INTO v_file
    FROM public.file_records
    WHERE id = p_file_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job file not found';
    END IF;
    IF v_file.upload_status = 'Archived' THEN
        RETURN v_file.id;
    END IF;

    UPDATE public.file_records
    SET upload_status = 'Archived',
        archived_at = COALESCE(archived_at, NOW())
    WHERE id = v_file.id;

    INSERT INTO public.file_access_logs (
        file_record_id,
        profile_id,
        resource_id,
        action
    ) VALUES (
        v_file.id,
        auth.uid(),
        v_file.resource_id,
        'Archive'
    );

    RETURN v_file.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_create_job_issue(
    p_job_id UUID,
    p_severity TEXT,
    p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_issue_id UUID;
    v_description TEXT := btrim(COALESCE(p_description, ''));
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;
    IF p_severity NOT IN ('Low', 'Medium', 'High', 'Critical') THEN
        RAISE EXCEPTION 'Unsupported issue severity';
    END IF;
    IF v_description = '' OR length(v_description) > 4000 THEN
        RAISE EXCEPTION 'Issue description must contain 1 to 4000 characters';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.project_jobs WHERE id = p_job_id
    ) THEN
        RAISE EXCEPTION 'Job not found';
    END IF;

    INSERT INTO public.job_issues (
        job_id,
        status,
        severity,
        description,
        reported_by
    ) VALUES (
        p_job_id,
        'Issue Reported',
        p_severity,
        v_description,
        auth.uid()
    )
    RETURNING id INTO v_issue_id;

    RETURN v_issue_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_update_job_issue(
    p_issue_id UUID,
    p_status TEXT,
    p_severity TEXT,
    p_description TEXT,
    p_resolution TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_issue_id UUID;
    v_description TEXT := btrim(COALESCE(p_description, ''));
    v_resolution TEXT := NULLIF(btrim(COALESCE(p_resolution, '')), '');
BEGIN
    IF NOT public.can_manage_operations() THEN
        RAISE EXCEPTION 'Operational access required';
    END IF;
    IF p_status NOT IN (
        'Issue Reported', 'Investigating', 'Correction Requested',
        'Corrected', 'Resolved'
    ) THEN
        RAISE EXCEPTION 'Unsupported issue status';
    END IF;
    IF p_severity NOT IN ('Low', 'Medium', 'High', 'Critical') THEN
        RAISE EXCEPTION 'Unsupported issue severity';
    END IF;
    IF v_description = '' OR length(v_description) > 4000 THEN
        RAISE EXCEPTION 'Issue description must contain 1 to 4000 characters';
    END IF;
    IF p_status = 'Resolved' AND v_resolution IS NULL THEN
        RAISE EXCEPTION 'A resolution is required when resolving an issue';
    END IF;

    UPDATE public.job_issues
    SET status = p_status,
        severity = p_severity,
        description = v_description,
        resolution = v_resolution,
        resolved_at = CASE
            WHEN p_status = 'Resolved' THEN COALESCE(resolved_at, NOW())
            ELSE NULL
        END
    WHERE id = p_issue_id
    RETURNING id INTO v_issue_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job issue not found';
    END IF;
    RETURN v_issue_id;
END;
$$;

REVOKE ALL ON FUNCTION public.staff_prepare_job_file_upload(
    UUID, TEXT, TEXT, BIGINT, TEXT, TEXT
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.staff_publish_job_file_upload(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.staff_archive_job_file(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.staff_create_job_issue(UUID, TEXT, TEXT)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.staff_update_job_issue(
    UUID, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.staff_prepare_job_file_upload(
    UUID, TEXT, TEXT, BIGINT, TEXT, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_publish_job_file_upload(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_archive_job_file(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_create_job_issue(UUID, TEXT, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_update_job_issue(
    UUID, TEXT, TEXT, TEXT, TEXT
) TO authenticated;

-- These company policies are tightly scoped to one private bucket. Existing
-- resource_portal_own_job_file_select remains the only Resource SELECT path.
DO $$
BEGIN
    IF to_regclass('storage.objects') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS tms_job_files_company_select ON storage.objects';
        EXECUTE 'DROP POLICY IF EXISTS tms_job_files_operations_insert ON storage.objects';

        EXECUTE $policy$
            CREATE POLICY tms_job_files_company_select
            ON storage.objects
            FOR SELECT TO authenticated
            USING (
                bucket_id = 'tms-job-files'
                AND public.is_company_user()
                AND EXISTS (
                    SELECT 1
                    FROM public.file_records file
                    WHERE file.bucket_name = bucket_id
                      AND file.object_key = name
                )
            )
        $policy$;

        EXECUTE $policy$
            CREATE POLICY tms_job_files_operations_insert
            ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'tms-job-files'
                AND public.can_manage_operations()
                AND EXISTS (
                    SELECT 1
                    FROM public.file_records file
                    WHERE file.bucket_name = bucket_id
                      AND file.object_key = name
                      AND file.upload_status = 'Pending'
                      AND file.uploaded_by = auth.uid()
                )
            )
        $policy$;
    END IF;
END;
$$;

COMMIT;
