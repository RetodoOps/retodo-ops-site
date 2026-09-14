'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const jobJs = read('tms/job.js');
const dashboardHtml = read('tms/dashboard.html');
const dashboardJs = read('tms/dashboard.js');
const resourceHtml = read('tms/resource.html');
const resourceJs = read('tms/resource.js');
const portalHtml = read('tms/resource-dashboard.html');
const portalJs = read('tms/resource-dashboard.js');
const migration = read('tms/migrations/049_job_approval_history_compliance_agreement.sql');
const audit = read('tms/audits/011_update_050_job_approval_history_compliance_agreement_audit.sql');

async function runStatusOnlySave({sameDeadline = true} = {}) {
  const start = jobJs.indexOf('async function saveJob(){');
  const end = jobJs.indexOf('\nfunction renderOffers', start);
  assert.ok(start >= 0 && end > start, 'saveJob function is extractable');
  const values = {
    'j-candidate': 'resource-1',
    'j-specialization': 'specialization-1',
    'j-status': 'Approved',
    'j-source': 'English (US)',
    'j-target': 'Norwegian (Bokmål)',
    'j-service': 'Translation',
    'j-rate-select': 'rate-1',
    'j-quantity': '1200',
    'j-notes': 'Keep existing instructions',
  };
  const calls = [];
  const errors = [];
  let pastChecks = 0;
  const context = {
    job: {
      resource_id: 'resource-1', resource_rate_id: 'rate-1',
      specialization_id: 'specialization-1', status: 'Delivered',
      source_language: 'English (US)', target_language: 'Norwegian (Bokmål)',
      service_type: 'Translation', quantity: 1200,
      deadline: '2026-09-10T01:54:00.000Z',
    },
    jobId: 'job-1',
    loadedDeadlineFields: '2026-09-10|04:54',
    clearError() {},
    showError(message) { errors.push(message); },
    val(id) { return values[id] || ''; },
    nullable(id) { return values[id] || null; },
    combineDateTime() { return sameDeadline ? '2026-09-10T01:54:00.000Z' : '2026-09-09T01:54:00.000Z'; },
    deadlineFieldSnapshot() { return sameDeadline ? '2026-09-10|04:54' : '2026-09-09|04:54'; },
    deadlineIsPast() { pastChecks += 1; return true; },
    TMS_REF: {languages: ['English (US)', 'Norwegian (Bokmål)']},
    MANUAL_FLAT_FEE_VALUE: 'manual-flat-fee',
    collectSupplierCatRows() { return []; },
    supplierCatRowsChanged() { return false; },
    document: {getElementById() { return {checked: true}; }},
    _sb: {async rpc(name, payload) { calls.push({name, payload}); return {data: 0, error: null}; }},
    async loadJob() {},
    setStatus() {},
  };
  await vm.runInNewContext(`${jobJs.slice(start, end)}\nsaveJob()`, context);
  return {calls, errors, pastChecks};
}

test('status-only approval ignores an unchanged historical deadline field snapshot and sends no PO-facing terms', async () => {
  const result = await runStatusOnlySave();
  assert.deepEqual(result.errors, []);
  assert.equal(result.pastChecks, 0);
  assert.equal(result.calls.length, 1);
  assert.equal(result.calls[0].name, 'save_job_overview_inherit_rate_unit');
  assert.deepEqual(JSON.parse(JSON.stringify(result.calls[0].payload.p_payload)), {
    status: 'Approved', po_required: true, notes: 'Keep existing instructions',
  });
});

test('a newly changed past deadline remains blocked before saving', async () => {
  const result = await runStatusOnlySave({sameDeadline: false});
  assert.equal(result.calls.length, 0);
  assert.equal(result.pastChecks, 1);
  assert.deepEqual(result.errors, ['Resource deadline cannot be in the past.']);
});

test('database audit rejects status-driven PO revisions', () => {
  assert.match(audit, /status-only Job save does not define a PO change/);
  assert.match(audit, /v_old\.status IS DISTINCT FROM v_new\.status[\s\S]*THEN 'FAIL'/);
  assert.match(audit, /v_po_changed := v_terms_changed/);
});

test('Dashboard exposes each linked Job and assigned External Resource', () => {
  assert.match(dashboardHtml, /data-sort="resource">External Resource/);
  assert.match(dashboardJs, /project_jobs'\)\.select\('id,project_id,project_scoop_id,job_number,resource_id,status,service_type/);
  assert.match(dashboardJs, /resourceIds[\s\S]*\.from\('resources'\)[\s\S]*\.in\('id',\s*resourceIds\)/);
  assert.match(dashboardJs, /resource_assignments: assignments/);
  assert.match(dashboardJs, /href="resource\.html\?id=/);
  assert.match(dashboardJs, /'Assigned Resource'/);
});

test('Approved Project History stores and renders approximate quantity/unit without money', () => {
  assert.match(migration, /ALTER TABLE public\.resource_project_history[\s\S]*ADD COLUMN IF NOT EXISTS quantity[\s\S]*ADD COLUMN IF NOT EXISTS unit/);
  assert.match(migration, /NEW\.quantity, NEW\.unit/);
  assert.doesNotMatch(migration.slice(
    migration.indexOf('CREATE OR REPLACE FUNCTION public.feed_approved_job_to_resource_history'),
    migration.indexOf('-- Blind CV retains'),
  ), /supplier_amount|supplier_rate|supplier_currency/);
  assert.match(resourceHtml, /<th>Approx\. size<\/th>/);
  assert.match(resourceJs, /jobQuantityLabel\(row\.quantity,row\.unit\)/);
  assert.match(resourceJs, /\['Flat rate','Fixed fee'\]\.includes\(unit\)\?'flat rate'/);
});

test('Blind CV adds Retodo identity/logo, one language pair per line and Project size', () => {
  assert.match(resourceJs, /BLIND_CV_COMPANY_LINES=\['Retodo EOOD · UIC 208524462'/);
  assert.match(resourceJs, /<img src="Logo-440x140\.png" alt="Retodo Ops">/);
  assert.match(resourceJs, /<ul class="cv-language-list">/);
  assert.match(resourceJs, /lp\.map\(x=>`<li>/);
  assert.match(resourceJs, /heading:'Language coverage',lines:\(cvData\.language_pairs\|\|\[\]\)\.map/);
  assert.match(resourceJs, /new ImageRun/);
  assert.match(resourceJs, /Approx\. size: \$\{jobQuantityLabel\(item\.quantity,item\.unit\)\}/);
  assert.doesNotMatch(resourceJs, /BLIND_CV_COMPANY_LINES[^;]*(?:resource\.legal_name|resource\.email)/);
});

test('portal and internal users can delete authorized duplicate Compliance evidence', () => {
  const api = read('netlify/functions/resource-compliance-files.js');
  assert.match(api, /'delete_file'/);
  assert.match(api, /deleteDispatch\('inspect'/);
  assert.match(api, /deleteKey\(ticket\.object_key/);
  assert.match(api, /deleteDispatch\([\s\S]*'commit'/);
  assert.match(portalJs, /portalCompliance\?\.editable[\s\S]*deletePortalComplianceFile/);
  assert.match(portalJs, /Permanently delete \$\{filename\} from private storage/);
  assert.match(resourceJs, /deleteComplianceFile/);
  assert.match(migration, /v_actor_resource_id = v_file\.resource_id/);
  assert.match(migration, /upload_status = 'Deleted', deleted_at = NOW\(\)/);
  assert.match(migration, /action\s*\) VALUES \(v_file\.id, p_actor_id, v_file\.resource_id, 'Delete'\)/);
});

test('supplied agreement asset is exact and the portal contains all clauses and prefilled parties', () => {
  const agreement = fs.readFileSync(path.join(root, 'tms/agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx'));
  assert.equal(crypto.createHash('sha256').update(agreement).digest('hex'),
    '0b4a2c86432dc0ac006c655c626705aedfa985329c4579ba43944a62dc1ce35a');
  assert.match(portalHtml, /Retodo EOOD/);
  assert.match(portalHtml, /UIC 208524462/);
  for (let clause = 1; clause <= 15; clause += 1) {
    assert.match(portalHtml, new RegExp(`<h4>${clause}\\.`), `Agreement clause ${clause}`);
  }
  for (const id of [
    'portal-agreement-provider-name', 'portal-agreement-registration',
    'portal-agreement-address',
    'portal-agreement-signatory', 'portal-agreement-email',
  ]) assert.match(portalHtml, new RegExp(`id="${id}"`), id);
  assert.match(migration, /v_resource\.company_name[\s\S]*v_resource\.legal_name/);
  assert.match(migration, /v_resource\.city[\s\S]*v_resource\.country_of_residence/);
  assert.match(migration, /v_resource\.tax_id/);
});

test('agreement acceptance is versioned, audited, private and required for submission', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.resource_framework_agreements/);
  assert.match(migration, /ALTER TABLE public\.resource_framework_agreements ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /REVOKE ALL ON TABLE public\.resource_framework_agreements[\s\S]*PUBLIC, anon, authenticated/);
  assert.match(migration, /agreement_version[\s\S]*agreement_sha256[\s\S]*accepted_by[\s\S]*accepted_at/);
  assert.match(migration, /Framework agreement accepted/);
  assert.match(migration, /Read and accept the Freelancer Framework Agreement before submitting Compliance/);
  assert.match(portalJs, /resource_portal_accept_framework_agreement_050/);
  assert.match(resourceHtml, /Electronic acceptance snapshot/);
  assert.match(resourceHtml, /Internal only/);
});

test('Compliance submission generates a durable internal email alert without ISO data', () => {
  const server = read('netlify/functions/resource-compliance.js');
  assert.match(portalJs, /resource_portal_submit_compliance_048[\s\S]*portalComplianceWorkflowApi\('notify_submission'\)/);
  assert.match(server, /resource_compliance_submission_notification_050/);
  assert.match(server, /\/resource\.html\?id=\$\{encodeURIComponent\(ticket\.resource_id\)\}#qualifications/);
  assert.match(migration, /compliance_submission_notification_sent_at/);
  assert.match(migration, /v_resource\.profile_id = p_actor_id/);

  const {complianceSubmissionMessage} = require('../netlify/functions/_shared/gmail');
  const previousEmail = process.env.GMAIL_FROM_EMAIL;
  const previousName = process.env.GMAIL_FROM_NAME;
  process.env.GMAIL_FROM_EMAIL = 'ops@retodo-ops.com';
  process.env.GMAIL_FROM_NAME = 'Retodo Ops';
  try {
    const raw = complianceSubmissionMessage({
      name: 'Example Linguist', internal_number: 'RO-LNG-00123',
      submitted_at: '2026-09-13T12:00:00Z',
    }, 'https://tms.retodo-ops.com/resource.html?id=abc#qualifications');
    const message = Buffer.from(raw.replaceAll('-', '+').replaceAll('_', '/'), 'base64').toString('utf8');
    assert.match(message, /To: ops@retodo-ops\.com/);
    assert.match(message, /Subject: =\?UTF-8\?B\?/);
    const plainPart = message.match(/Content-Type: text\/plain; charset="UTF-8"\r\nContent-Transfer-Encoding: base64\r\n\r\n([^\r\n]+)/);
    assert.ok(plainPart);
    const plain = Buffer.from(plainPart[1], 'base64').toString('utf8');
    assert.match(plain, /submitted Compliance for internal review/);
    assert.match(plain, /resource\.html\?id=abc#qualifications/);
    assert.doesNotMatch(plain, /ISO 17100|ISO 18587|Eligible|Not eligible/);
  } finally {
    if (previousEmail === undefined) delete process.env.GMAIL_FROM_EMAIL;
    else process.env.GMAIL_FROM_EMAIL = previousEmail;
    if (previousName === undefined) delete process.env.GMAIL_FROM_NAME;
    else process.env.GMAIL_FROM_NAME = previousName;
  }
});

test('Update 050 uses a forward-only migration and successor asset cache keys', () => {
  assert.match(migration, /^--[\s\S]*BEGIN;/);
  assert.match(migration, /Migration 049 requires the operational core and migration 048/);
  assert.match(migration, /COMMIT;\s*$/);
  for (const [html, script] of [
    [read('tms/job.html'), 'job'], [dashboardHtml, 'dashboard'],
    [resourceHtml, 'resource'], [portalHtml, 'resource-dashboard'],
  ]) {
    assert.match(html, /style\.css\?v=052/);
    assert.match(html, new RegExp(`${script}\\.js\\?v=052`));
  }
});
