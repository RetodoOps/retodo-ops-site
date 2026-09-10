const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = relativePath => fs.readFileSync(path.join(root, relativePath), 'utf8');
const migration = read('tms/migrations/042_job_files_issues_staff_workflow.sql');
const audit = read('tms/audits/005_update_044_job_files_issues_audit.sql');
const jobHtml = read('tms/job.html');
const jobJs = read('tms/job.js');
const dashboardHtml = read('tms/resource-dashboard.html');
const dashboardJs = read('tms/resource-dashboard.js');
const resourceJobJs = read('tms/resource-job.js');
const resourcePoJs = read('tms/resource-po.js');
const style = read('tms/style.css');

test('migration 042 is forward-only and leaves migrations 036-041 untouched', () => {
    assert.match(migration, /Forward-only migration\. Do not edit migrations 036–041\./);
    assert.match(migration, /^BEGIN;/m);
    assert.match(migration, /^COMMIT;/m);
    assert.doesNotMatch(migration, /\b(DROP TABLE|TRUNCATE)\b/i);
});

test('all Resource dashboard PO projections filter active POs and newest versions', () => {
    const activeFilters = migration.match(/status IN \('Issued', 'Acknowledged'\)/g) || [];
    assert.equal(activeFilters.length, 3);
    assert.match(migration, /CREATE OR REPLACE FUNCTION public\.resource_portal_context\(\)[\s\S]*purchase_order_count[\s\S]*status IN \('Issued', 'Acknowledged'\)/);
    assert.match(migration, /CREATE OR REPLACE FUNCTION public\.resource_portal_jobs\(\)[\s\S]*ORDER BY version\.version_number DESC[\s\S]*LIMIT 1/);
    assert.match(migration, /CREATE OR REPLACE FUNCTION public\.resource_portal_purchase_orders\(\)[\s\S]*ORDER BY immutable\.version_number DESC[\s\S]*LIMIT 1/);
    assert.match(dashboardHtml, /Only active POs and their current versions are shown/);
    assert.doesNotMatch(dashboardJs, /supplier_po_versions|\.from\(/);
});

test('old immutable PO versions render as Superseded without rewriting source status', () => {
    const cutoff = resourcePoJs.indexOf('function renderPortalPoVersion');
    assert.ok(cutoff > 0);
    const context = vm.createContext({});
    vm.runInContext(resourcePoJs.slice(0, cutoff), context);
    vm.runInContext(`portalPoData = {
        purchase_order: {status: 'Issued'},
        versions: [
            {version_number: 2, document_status: 'Revised'},
            {version_number: 1, document_status: 'Issued'}
        ]
    }`, context);
    assert.equal(vm.runInContext('portalPoVersionStatus(portalPoData.versions[0])', context), 'Revised');
    assert.equal(vm.runInContext('portalPoVersionStatus(portalPoData.versions[1])', context), 'Superseded');
    assert.match(jobJs, /function poVersionDisplayStatus[\s\S]*'Superseded'/);
    assert.doesNotMatch(migration, /UPDATE\s+public\.supplier_po_versions/i);
});

test('staff Job page retains the complete file UI while Update 045 routes new binaries to R2', () => {
    for (const id of ['addJobFileBtn', 'jobFileForm', 'jobFileRole', 'jobFileInput', 'uploadJobFileBtn', 'jobFilesTbody']) {
        assert.match(jobHtml, new RegExp(`id="${id}"`));
    }
    for (const role of ['Source', 'Reference', 'Instructions', 'Delivery', 'Other']) {
        assert.match(jobHtml, new RegExp(`<option>${role}</option>`));
    }
    assert.match(jobHtml, /file-hash\.js\?v=045/);
    assert.match(jobJs, /TMS_FILE_HASH\.sha256Hex/);
    assert.match(jobJs, /\/\.netlify\/functions\/job-files/);
    assert.match(jobJs, /fileApi\('prepare_upload'/);
    assert.match(jobJs, /method:'PUT'/);
    assert.match(jobJs, /fileApi\('complete_upload'/);
    assert.match(jobJs, /fileApi\('archive_job'/);
    assert.match(jobJs, /fileApi\('restore_job'/);
    assert.doesNotMatch(jobJs, /staff_prepare_job_file_upload|staff_publish_job_file_upload/);
    assert.match(jobJs, /Pending Job file discarded/);
});

test('staff Job page contains create and update issue workflow', () => {
    for (const id of ['addJobIssueBtn', 'jobIssueForm', 'jobIssueStatus', 'jobIssueSeverity', 'jobIssueDescription', 'jobIssueResolution', 'issuesTbody']) {
        assert.match(jobHtml, new RegExp(`id="${id}"`));
    }
    assert.match(jobJs, /staff_create_job_issue/);
    assert.match(jobJs, /staff_update_job_issue/);
    assert.match(jobJs, /openJobIssueForm\('\$\{issue\.id\}'\)/);
    assert.match(migration, /p_status = 'Resolved' AND v_resolution IS NULL/);
    assert.doesNotMatch(jobJs, /financial_impact/);
});

test('browser controls and trusted SQL enforce the same operational roles', () => {
    assert.match(jobJs, /\['admin','pm','client_relations'\]\.includes\(currentRole\)/);
    const staffFunctions = [
        'staff_prepare_job_file_upload',
        'staff_publish_job_file_upload',
        'staff_archive_job_file',
        'staff_create_job_issue',
        'staff_update_job_issue',
    ];
    for (const name of staffFunctions) {
        const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
        const next = migration.indexOf('CREATE OR REPLACE FUNCTION public.', start + 1);
        const definition = migration.slice(start, next < 0 ? migration.length : next);
        assert.ok(start >= 0, `${name} missing`);
        assert.match(definition, /IF NOT public\.can_manage_operations\(\) THEN/);
    }
});

test('storage remains private and Resource access has no mutation path', () => {
    assert.match(migration, /VALUES \('tms-job-files', 'tms-job-files', FALSE\)/);
    assert.match(migration, /CREATE POLICY tms_job_files_company_select[\s\S]*FOR SELECT[\s\S]*public\.is_company_user\(\)/);
    assert.match(migration, /CREATE POLICY tms_job_files_operations_insert[\s\S]*FOR INSERT[\s\S]*public\.can_manage_operations\(\)/);
    assert.doesNotMatch(migration, /CREATE POLICY[\s\S]{0,160}FOR (UPDATE|DELETE)/i);
    assert.doesNotMatch(resourceJobJs, /rpc\('staff_|\.upload\(|_sb\.storage[\s\S]{0,120}\.remove\(/);
    assert.match(resourceJobJs, /record_resource_file_access/);
    assert.match(resourceJobJs, /p_action: action/);
});

test('Resource JavaScript stays on narrow RPC projections and contains no Client data query', () => {
    for (const source of [dashboardJs, resourceJobJs, resourcePoJs]) {
        assert.doesNotMatch(source, /_sb\.from\(/);
        assert.doesNotMatch(source, /client_accounts|client_contacts|scope_items|client_price|profit|margin/i);
    }
    assert.match(resourceJobJs, /resource_portal_job/);
    assert.match(resourcePoJs, /resource_portal_purchase_order/);
});

test('successor UI assets use update 045 cache keys and retain responsive form styles', () => {
    assert.match(jobHtml, /style\.css\?v=045/);
    assert.match(jobHtml, /job\.js\?v=045/);
    assert.match(dashboardHtml, /style\.css\?v=044/);
    assert.match(read('tms/resource-po.html'), /resource-po\.js\?v=044/);
    assert.match(style, /\.job-operations-form/);
    assert.match(style, /\.job-issue-form/);
    assert.match(style, /@media \(max-width: 780px\)[\s\S]*\.job-operations-form \{ grid-template-columns: 1fr; \}/);
});

test('read-only audit covers functions, RLS, storage, active POs and lifecycle consistency', () => {
    assert.match(audit, /Every statement is read-only/);
    assert.match(audit, /resource_portal_own_job_file_select/);
    assert.match(audit, /tms_job_files_operations_insert/);
    assert.match(audit, /current_external_resource_id/);
    assert.match(audit, /status IN \(''Issued'', ''Acknowledged''\)/);
    assert.match(audit, /Lifecycle state\/data consistency/);
    const statements = audit.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean);
    assert.ok(statements.length >= 10);
    for (const statement of statements) assert.match(statement, /^(WITH|SELECT)\b/i);
});
