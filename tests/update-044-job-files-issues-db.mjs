// Isolated PostgreSQL (PGlite) fixture. No live database or Storage calls.
// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite module.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const file = relativePath => readFileSync(new URL(`../${relativePath}`, import.meta.url), 'utf8');
const migration = file('tms/migrations/042_job_files_issues_staff_workflow.sql');
const audit = file('tms/audits/005_update_044_job_files_issues_audit.sql');

await db.exec(`
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE SCHEMA storage;

CREATE FUNCTION auth.uid() RETURNS UUID
LANGUAGE sql STABLE
AS $$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', TRUE), '')::UUID
$$;

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role TEXT NOT NULL
);

CREATE TABLE public.resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    internal_number TEXT NOT NULL UNIQUE,
    profile_id UUID UNIQUE REFERENCES public.profiles(id),
    resource_type TEXT NOT NULL,
    legal_name TEXT,
    company_name TEXT,
    portal_status TEXT NOT NULL DEFAULT 'Not invited',
    financial_access_until TIMESTAMPTZ
);

CREATE TABLE public.projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_number TEXT NOT NULL
);

CREATE TABLE public.project_scoops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id),
    scoop_number TEXT NOT NULL
);

CREATE TABLE public.specializations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL
);

CREATE TABLE public.project_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id),
    project_scoop_id UUID NOT NULL REFERENCES public.project_scoops(id),
    resource_id UUID REFERENCES public.resources(id),
    specialization_id UUID REFERENCES public.specializations(id),
    job_number TEXT NOT NULL,
    status TEXT NOT NULL,
    service_type TEXT,
    source_language TEXT,
    target_language TEXT,
    deadline TIMESTAMPTZ,
    quantity NUMERIC,
    unit TEXT,
    assignment_notes TEXT,
    notes TEXT
);

CREATE TABLE public.supplier_purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_number TEXT NOT NULL UNIQUE,
    job_id UUID REFERENCES public.project_jobs(id),
    project_id UUID NOT NULL REFERENCES public.projects(id),
    resource_id UUID NOT NULL REFERENCES public.resources(id),
    status TEXT NOT NULL,
    current_version INTEGER NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'EUR',
    total NUMERIC NOT NULL DEFAULT 0,
    issued_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.supplier_po_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES public.supplier_purchase_orders(id),
    version_number INTEGER NOT NULL,
    document_status TEXT,
    snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (purchase_order_id, version_number)
);

CREATE TABLE public.file_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES public.projects(id),
    job_id UUID REFERENCES public.project_jobs(id),
    resource_id UUID REFERENCES public.resources(id),
    storage_provider TEXT NOT NULL,
    bucket_name TEXT,
    object_key TEXT,
    external_url TEXT,
    original_filename TEXT NOT NULL,
    mime_type TEXT,
    size_bytes BIGINT,
    file_role TEXT,
    checksum_sha256 TEXT,
    retention_until DATE,
    archived_at TIMESTAMPTZ,
    uploaded_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.file_access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_record_id UUID NOT NULL REFERENCES public.file_records(id),
    profile_id UUID REFERENCES public.profiles(id),
    resource_id UUID REFERENCES public.resources(id),
    action TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.job_issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.project_jobs(id),
    status TEXT NOT NULL DEFAULT 'Issue Reported',
    severity TEXT,
    description TEXT NOT NULL,
    resolution TEXT,
    financial_impact NUMERIC,
    reported_by UUID REFERENCES public.profiles(id),
    assigned_to UUID REFERENCES public.profiles(id),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE storage.buckets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    public BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE storage.objects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id TEXT NOT NULL REFERENCES storage.buckets(id),
    name TEXT NOT NULL,
    owner_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (bucket_id, name)
);

CREATE FUNCTION public.current_app_role() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT profile.role FROM public.profiles profile WHERE profile.id = auth.uid()
$$;

CREATE FUNCTION public.can_manage_operations() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT COALESCE(public.current_app_role() IN ('admin', 'pm', 'client_relations'), FALSE)
$$;

CREATE FUNCTION public.is_company_user() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT COALESCE(public.current_app_role() IN ('admin', 'pm', 'qa', 'client_relations'), FALSE)
$$;

CREATE FUNCTION public.current_external_resource_id() RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT resource.id
    FROM public.resources resource
    WHERE resource.profile_id = auth.uid()
      AND resource.resource_type IN ('Freelancer', 'Company')
      AND resource.portal_status = 'Active'
    LIMIT 1
$$;

CREATE FUNCTION public.current_external_financial_resource_id() RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT resource.id
    FROM public.resources resource
    WHERE resource.profile_id = auth.uid()
      AND resource.resource_type IN ('Freelancer', 'Company')
      AND resource.portal_status IN ('Active', 'Read-only', 'Financial only')
    LIMIT 1
$$;

ALTER TABLE public.file_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_access_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

CREATE POLICY file_records_company_select ON public.file_records
FOR SELECT TO authenticated USING (public.is_company_user());
CREATE POLICY file_records_operations_write ON public.file_records
FOR ALL TO authenticated
USING (public.can_manage_operations()) WITH CHECK (public.can_manage_operations());
CREATE POLICY file_access_logs_company_select ON public.file_access_logs
FOR SELECT TO authenticated USING (public.is_company_user());
CREATE POLICY file_access_logs_operations_write ON public.file_access_logs
FOR ALL TO authenticated
USING (public.can_manage_operations()) WITH CHECK (public.can_manage_operations());
CREATE POLICY job_issues_company_select ON public.job_issues
FOR SELECT TO authenticated USING (public.is_company_user());
CREATE POLICY job_issues_operations_write ON public.job_issues
FOR ALL TO authenticated
USING (public.can_manage_operations()) WITH CHECK (public.can_manage_operations());

GRANT USAGE ON SCHEMA public, auth, storage TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.file_records,
    public.file_access_logs, public.job_issues TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
`);

await db.exec(`
CREATE OR REPLACE FUNCTION public.resource_can_access_file(
    p_file_record_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.file_records file
        JOIN public.project_jobs job ON job.id = file.job_id
        WHERE file.id = p_file_record_id
          AND file.archived_at IS NULL
          AND job.resource_id = public.current_external_resource_id()
          AND (
              file.resource_id IS NULL
              OR file.resource_id = public.current_external_resource_id()
          )
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
SET search_path = public
AS $$
    SELECT COALESCE(EXISTS (
        SELECT 1
        FROM public.file_records file
        JOIN public.project_jobs job ON job.id = file.job_id
        WHERE file.storage_provider = 'Supabase'
          AND file.bucket_name = p_bucket_name
          AND file.object_key = p_object_key
          AND file.archived_at IS NULL
          AND job.resource_id = public.current_external_resource_id()
          AND (
              file.resource_id IS NULL
              OR file.resource_id = public.current_external_resource_id()
          )
    ), FALSE)
$$;

CREATE OR REPLACE FUNCTION public.record_resource_file_access(
    p_file_record_id UUID,
    p_action TEXT DEFAULT 'View'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resource_id UUID := public.current_external_resource_id();
    v_log_id UUID;
BEGIN
    IF v_resource_id IS NULL THEN
        RAISE EXCEPTION 'Active External Resource portal access required';
    END IF;
    IF p_action NOT IN ('View', 'Download') THEN
        RAISE EXCEPTION 'External Resource file action must be View or Download';
    END IF;
    IF NOT public.resource_can_access_file(p_file_record_id) THEN
        RAISE EXCEPTION 'Job file not found';
    END IF;

    INSERT INTO public.file_access_logs (
        file_record_id, profile_id, resource_id, action
    ) VALUES (
        p_file_record_id, auth.uid(), v_resource_id, p_action
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resource_can_access_file(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resource_can_access_storage_object(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_resource_file_access(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resource_can_access_file(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resource_can_access_storage_object(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_resource_file_access(UUID, TEXT) TO authenticated;
CREATE POLICY resource_portal_own_job_file_select
ON storage.objects FOR SELECT TO authenticated
USING (public.resource_can_access_storage_object(bucket_id, name));
`);

// Applying twice validates forward-only idempotency without editing old migrations.
await db.exec(migration);
await db.exec(migration);

let passed = 0;
async function check(name, callback) {
    await callback();
    passed += 1;
    console.log(`PASS ${name}`);
}

async function addProfile(role) {
    const {rows: [profile]} = await db.query(
        'INSERT INTO public.profiles(role) VALUES($1) RETURNING id',
        [role],
    );
    return profile.id;
}

async function setActor(profileId, databaseRole = 'authenticated') {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub', $1, FALSE)", [profileId || '']);
    await db.exec(`SET ROLE ${databaseRole}`);
}

async function resetActor() {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub', '', FALSE)");
}

const admin = await addProfile('admin');
const pm = await addProfile('pm');
const clientRelations = await addProfile('client_relations');
const qa = await addProfile('qa');
const externalProfile = await addProfile('resource');
const otherExternalProfile = await addProfile('resource');

const {rows: [external]} = await db.query(`
    INSERT INTO public.resources(
        internal_number, profile_id, resource_type, legal_name, portal_status
    ) VALUES ('RO-EXT-001', $1, 'Freelancer', 'External One', 'Active')
    RETURNING id
`, [externalProfile]);
const {rows: [otherExternal]} = await db.query(`
    INSERT INTO public.resources(
        internal_number, profile_id, resource_type, legal_name, portal_status
    ) VALUES ('RO-EXT-002', $1, 'Freelancer', 'External Two', 'Active')
    RETURNING id
`, [otherExternalProfile]);
const {rows: [project]} = await db.query(
    "INSERT INTO public.projects(project_number) VALUES('260909_TEST') RETURNING id",
);
const {rows: [scoop]} = await db.query(
    "INSERT INTO public.project_scoops(project_id,scoop_number) VALUES($1,'260909_TEST-S01') RETURNING id",
    [project.id],
);
const {rows: [specialization]} = await db.query(
    "INSERT INTO public.specializations(name) VALUES('General') RETURNING id",
);
const {rows: [job]} = await db.query(`
    INSERT INTO public.project_jobs(
        project_id, project_scoop_id, resource_id, specialization_id,
        job_number, status, service_type, source_language, target_language,
        deadline, quantity, unit, assignment_notes
    ) VALUES (
        $1, $2, $3, $4, '260909_TEST-S01-TRA_J01', 'Assigned',
        'Translation', 'English (UK)', 'Swedish', '2026-09-12T12:00:00Z',
        100, 'Source words', 'Translate the supplied file.'
    ) RETURNING id
`, [project.id, scoop.id, external.id, specialization.id]);

async function addPurchaseOrder(number, status, issuedAt, versions) {
    const {rows: [po]} = await db.query(`
        INSERT INTO public.supplier_purchase_orders(
            po_number, job_id, project_id, resource_id, status,
            current_version, currency, total, issued_at, acknowledged_at
        ) VALUES ($1,$2,$3,$4,$5,$6,'EUR',$7,$8,$9)
        RETURNING id
    `, [
        number, job.id, project.id, external.id, status, versions.length,
        versions.at(-1).total, issuedAt,
        status === 'Acknowledged' ? issuedAt : null,
    ]);
    for (const version of versions) {
        await db.query(`
            INSERT INTO public.supplier_po_versions(
                purchase_order_id, version_number, document_status, snapshot, created_at
            ) VALUES ($1,$2,$3,$4,$5)
        `, [
            po.id,
            version.number,
            version.status,
            JSON.stringify({
                currency: 'EUR',
                total: version.total,
                job: {job_number: '260909_TEST-S01-TRA_J01'},
            }),
            version.createdAt,
        ]);
    }
    return po.id;
}

const issuedPo = await addPurchaseOrder('PO-ACTIVE-ISSUED', 'Issued', '2026-09-09T08:00:00Z', [
    {number: 1, status: 'Issued', total: 10, createdAt: '2026-09-09T08:00:00Z'},
    {number: 2, status: 'Revised', total: 12, createdAt: '2026-09-09T09:00:00Z'},
]);
const acknowledgedPo = await addPurchaseOrder('PO-ACTIVE-ACK', 'Acknowledged', '2026-09-09T10:00:00Z', [
    {number: 1, status: 'Issued', total: 15, createdAt: '2026-09-09T10:00:00Z'},
]);
await addPurchaseOrder('PO-CANCELLED', 'Cancelled', '2026-09-09T11:00:00Z', [
    {number: 1, status: 'Issued', total: 99, createdAt: '2026-09-09T11:00:00Z'},
]);
await addPurchaseOrder('PO-DRAFT', 'Draft', null, [
    {number: 1, status: 'Draft', total: 77, createdAt: '2026-09-09T12:00:00Z'},
]);

await check('migration keeps bucket private and staff functions unavailable to anon', async () => {
    const {rows: [bucket]} = await db.query(
        "SELECT public FROM storage.buckets WHERE id='tms-job-files'",
    );
    assert.equal(bucket.public, false);
    for (const signature of [
        'staff_prepare_job_file_upload(uuid,text,text,bigint,text,text)',
        'staff_publish_job_file_upload(uuid)',
        'staff_archive_job_file(uuid)',
        'staff_create_job_issue(uuid,text,text)',
        'staff_update_job_issue(uuid,text,text,text,text)',
    ]) {
        const {rows: [privilege]} = await db.query(
            "SELECT has_function_privilege('anon',$1,'EXECUTE') AS allowed",
            [signature],
        );
        assert.equal(privilege.allowed, false);
    }
});

await check('QA and External Resource are rejected by trusted staff functions', async () => {
    await setActor(qa);
    await assert.rejects(() => db.query(
        "SELECT public.staff_prepare_job_file_upload($1,'qa.txt','text/plain',2,'Reference',NULL)",
        [job.id],
    ), /Operational access required/);
    await setActor(externalProfile);
    await assert.rejects(() => db.query(
        "SELECT public.staff_create_job_issue($1,'Low','Not allowed')",
        [job.id],
    ), /Operational access required/);
});

let fileId;
let objectKey;
await check('Admin prepares an exact Job/Resource-bound pending private file', async () => {
    await setActor(admin);
    const checksum = 'ab'.repeat(32);
    const {rows: [result]} = await db.query(`
        SELECT public.staff_prepare_job_file_upload(
            $1, 'Source file #1.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            4096, 'Source', $2
        ) AS ticket
    `, [job.id, checksum]);
    fileId = result.ticket.file_id;
    objectKey = result.ticket.object_key;
    assert.equal(result.ticket.bucket_name, 'tms-job-files');
    assert.match(objectKey, new RegExp(`^jobs/${job.id}/${external.id}/${fileId}/Source_file_1\\.docx$`));
    const {rows: [record]} = await db.query(
        'SELECT * FROM public.file_records WHERE id=$1',
        [fileId],
    );
    assert.equal(record.resource_id, external.id);
    assert.equal(record.uploaded_by, admin);
    assert.equal(record.upload_status, 'Pending');
    assert.ok(record.archived_at);
    assert.equal(record.checksum_sha256, checksum);
});

await check('prepare rejects unsupported roles and invalid checksums', async () => {
    await setActor(pm);
    await assert.rejects(() => db.query(`
        SELECT public.staff_prepare_job_file_upload(
            $1, 'bad.txt', 'text/plain', 1, 'Client source', NULL
        )
    `, [job.id]), /Unsupported Job file role/);
    await assert.rejects(() => db.query(`
        SELECT public.staff_prepare_job_file_upload(
            $1, 'bad.txt', 'text/plain', 1, 'Reference', 'not-sha256'
        )
    `, [job.id]), /File checksum must be SHA-256/);
});

await check('publication requires the matching private Storage object', async () => {
    await setActor(admin);
    await assert.rejects(() => db.query(
        'SELECT public.staff_publish_job_file_upload($1)',
        [fileId],
    ), /private file upload is not present/);
    await db.query(
        'INSERT INTO storage.objects(bucket_id,name,owner_id) VALUES($1,$2,$3)',
        ['tms-job-files', objectKey, admin],
    );
    const {rows: [published]} = await db.query(
        'SELECT public.staff_publish_job_file_upload($1) AS id',
        [fileId],
    );
    assert.equal(published.id, fileId);
    const {rows: [record]} = await db.query(
        'SELECT upload_status,archived_at FROM public.file_records WHERE id=$1',
        [fileId],
    );
    assert.equal(record.upload_status, 'Ready');
    assert.equal(record.archived_at, null);
    const {rows: logs} = await db.query(
        "SELECT action FROM public.file_access_logs WHERE file_record_id=$1 AND action='Upload'",
        [fileId],
    );
    assert.equal(logs.length, 1);
});

await check('Resource can select only its own ready object and cannot mutate Storage', async () => {
    await setActor(externalProfile);
    const {rows: ownRows} = await db.query(
        'SELECT name FROM storage.objects WHERE bucket_id=$1',
        ['tms-job-files'],
    );
    assert.deepEqual(ownRows.map(row => row.name), [objectKey]);
    const {rows: [ownAccess]} = await db.query(
        'SELECT public.resource_can_access_file($1) AS allowed',
        [fileId],
    );
    assert.equal(ownAccess.allowed, true);
    await assert.rejects(() => db.query(
        "INSERT INTO storage.objects(bucket_id,name) VALUES('tms-job-files','forbidden')",
    ), /row-level security policy/);
    const {rows: updated} = await db.query(
        'UPDATE storage.objects SET name=name WHERE id IS NOT NULL RETURNING id',
    );
    assert.equal(updated.length, 0);
    const {rows: deleted} = await db.query(
        'DELETE FROM storage.objects WHERE id IS NOT NULL RETURNING id',
    );
    assert.equal(deleted.length, 0);

    await setActor(otherExternalProfile);
    const {rows: otherRows} = await db.query(
        'SELECT name FROM storage.objects WHERE bucket_id=$1',
        ['tms-job-files'],
    );
    assert.equal(otherRows.length, 0);
    const {rows: [otherAccess]} = await db.query(
        'SELECT public.resource_can_access_file($1) AS allowed',
        [fileId],
    );
    assert.equal(otherAccess.allowed, false);
});

await check('Resource access logging accepts View/Download only', async () => {
    await setActor(externalProfile);
    await db.query(
        "SELECT public.record_resource_file_access($1,'View')",
        [fileId],
    );
    await db.query(
        "SELECT public.record_resource_file_access($1,'Download')",
        [fileId],
    );
    await assert.rejects(() => db.query(
        "SELECT public.record_resource_file_access($1,'Delete')",
        [fileId],
    ), /must be View or Download/);
    await resetActor();
    const {rows: [count]} = await db.query(`
        SELECT count(*)::INTEGER AS count
        FROM public.file_access_logs
        WHERE file_record_id=$1 AND action IN ('View','Download')
    `, [fileId]);
    assert.equal(count.count, 2);
});

await check('archive hides the object from Resource while retaining staff audit history', async () => {
    await setActor(pm);
    await db.query('SELECT public.staff_archive_job_file($1)', [fileId]);
    await db.query('SELECT public.staff_archive_job_file($1)', [fileId]);
    const {rows: [record]} = await db.query(
        'SELECT upload_status,archived_at FROM public.file_records WHERE id=$1',
        [fileId],
    );
    assert.equal(record.upload_status, 'Archived');
    assert.ok(record.archived_at);
    const {rows: [count]} = await db.query(`
        SELECT count(*)::INTEGER AS count
        FROM public.file_access_logs
        WHERE file_record_id=$1 AND action='Archive'
    `, [fileId]);
    assert.equal(count.count, 1);

    await setActor(externalProfile);
    const {rows: resourceRows} = await db.query(
        'SELECT name FROM storage.objects WHERE bucket_id=$1',
        ['tms-job-files'],
    );
    assert.equal(resourceRows.length, 0);
    await setActor(admin);
    const {rows: staffRows} = await db.query(
        'SELECT name FROM storage.objects WHERE bucket_id=$1',
        ['tms-job-files'],
    );
    assert.equal(staffRows.length, 1);
});

await check('pending uploads can be safely discarded without a Storage object', async () => {
    await setActor(clientRelations);
    const {rows: [result]} = await db.query(`
        SELECT public.staff_prepare_job_file_upload(
            $1, 'retry.txt', 'text/plain', 5, 'Other', NULL
        ) AS ticket
    `, [job.id]);
    await db.query(
        'SELECT public.staff_archive_job_file($1)',
        [result.ticket.file_id],
    );
    const {rows: [record]} = await db.query(
        'SELECT upload_status,archived_at FROM public.file_records WHERE id=$1',
        [result.ticket.file_id],
    );
    assert.equal(record.upload_status, 'Archived');
    assert.ok(record.archived_at);
});

let issueId;
await check('operations roles create and update issues without financial impact', async () => {
    await setActor(admin);
    const {rows: [created]} = await db.query(
        "SELECT public.staff_create_job_issue($1,'High','Delivery package is incomplete') AS id",
        [job.id],
    );
    issueId = created.id;
    const {rows: [initial]} = await db.query(
        'SELECT * FROM public.job_issues WHERE id=$1',
        [issueId],
    );
    assert.equal(initial.status, 'Issue Reported');
    assert.equal(initial.financial_impact, null);

    await setActor(pm);
    await db.query(`
        SELECT public.staff_update_job_issue(
            $1,'Investigating','High','Delivery package is incomplete',NULL
        )
    `, [issueId]);
    await assert.rejects(() => db.query(`
        SELECT public.staff_update_job_issue(
            $1,'Resolved','High','Delivery package is incomplete',NULL
        )
    `, [issueId]), /resolution is required/);

    await setActor(clientRelations);
    await db.query(`
        SELECT public.staff_update_job_issue(
            $1,'Resolved','High','Delivery package is incomplete','Missing file supplied'
        )
    `, [issueId]);
    const {rows: [resolved]} = await db.query(
        'SELECT * FROM public.job_issues WHERE id=$1',
        [issueId],
    );
    assert.equal(resolved.status, 'Resolved');
    assert.equal(resolved.resolution, 'Missing file supplied');
    assert.ok(resolved.resolved_at);
    assert.equal(resolved.financial_impact, null);
});

await check('QA cannot edit issues', async () => {
    await setActor(qa);
    await assert.rejects(() => db.query(`
        SELECT public.staff_update_job_issue(
            $1,'Corrected','Low','Attempted change','No'
        )
    `, [issueId]), /Operational access required/);
});

await check('dashboard RPCs show active POs only and newest immutable versions', async () => {
    await setActor(externalProfile);
    const {rows: purchaseOrders} = await db.query(
        'SELECT * FROM public.resource_portal_purchase_orders()',
    );
    assert.deepEqual(
        new Set(purchaseOrders.map(po => po.purchase_order_number)),
        new Set(['PO-ACTIVE-ISSUED', 'PO-ACTIVE-ACK']),
    );
    const issued = purchaseOrders.find(po => po.purchase_order_id === issuedPo);
    assert.equal(issued.current_version, 2);
    assert.equal(Number(issued.total), 12);
    const acknowledged = purchaseOrders.find(po => po.purchase_order_id === acknowledgedPo);
    assert.equal(acknowledged.purchase_order_status, 'Acknowledged');

    const {rows: [context]} = await db.query(
        'SELECT public.resource_portal_context() AS context',
    );
    assert.equal(context.context.purchase_order_count, 2);

    const {rows: [jobProjection]} = await db.query(
        'SELECT * FROM public.resource_portal_jobs()',
    );
    assert.equal(jobProjection.purchase_order_status, 'Acknowledged');
    assert.equal(jobProjection.purchase_order_version, 1);
});

await check('operational tables retain RLS and no direct Resource policies', async () => {
    await resetActor();
    const {rows: tables} = await db.query(`
        SELECT relname, relrowsecurity
        FROM pg_class
        WHERE relnamespace='public'::regnamespace
          AND relname IN ('file_records','file_access_logs','job_issues')
        ORDER BY relname
    `);
    assert.equal(tables.length, 3);
    assert.ok(tables.every(row => row.relrowsecurity));
    const {rows: unsafePolicies} = await db.query(`
        SELECT policyname
        FROM pg_policies
        WHERE schemaname='public'
          AND tablename IN ('file_records','file_access_logs','job_issues')
          AND (
              COALESCE(qual,'') ILIKE '%current_external_resource_id%'
              OR COALESCE(with_check,'') ILIKE '%current_external_resource_id%'
          )
    `);
    assert.equal(unsafePolicies.length, 0);
});

await check('read-only Update 044 database audit returns only PASS/empty sets', async () => {
    await resetActor();
    const results = await db.exec(audit);
    assert.ok(results.length >= 10);
    for (const result of results) {
        const rows = result.rows || [];
        if (rows.some(row => Object.hasOwn(row, 'result'))) {
            for (const row of rows) assert.equal(row.result, 'PASS');
        } else {
            assert.equal(rows.length, 0);
        }
    }
});

await resetActor();
console.log(`${passed} PostgreSQL fixture checks passed`);
await db.close();
