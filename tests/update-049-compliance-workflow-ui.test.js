'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const resourceHtml = read('tms/resource.html');
const resourceJs = read('tms/resource.js');
const portalHtml = read('tms/resource-dashboard.html');
const portalJs = read('tms/resource-dashboard.js');
const migration = read('tms/migrations/048_compliance_phase_tests_and_job_qualifications.sql');

test('pre-TMS test is an explicit pass with no date', () => {
  assert.match(resourceHtml, /id="test-pre-tms"/);
  assert.match(resourceHtml, /without a test date/);
  assert.match(resourceHtml, /id="test-result"[\s\S]*<option>Pass<\/option>[\s\S]*<option>Fail<\/option>/);
  assert.match(resourceJs, /legacy\?'Completed'/);
  assert.match(resourceJs, /legacy\?'Pass'/);
  assert.match(resourceJs, /assigned_at:legacy\?null/);
  assert.match(resourceJs, /completed_at:status==='Completed'&&!legacy\?new Date\(\)\.toISOString\(\):null/);
  assert.match(resourceJs, /No test date recorded/);
  assert.match(migration, /NEW\.assigned_at := NULL/);
  assert.match(migration, /NEW\.completed_at := NULL/);
  assert.match(migration, /NEW\.test_result := 'Pass'/);
});

test('Account qualifications derive Approved Job quantities without money', () => {
  assert.match(resourceHtml, /Account qualifications from Approved Jobs/);
  assert.match(resourceHtml, /Job volume/);
  assert.match(resourceHtml, /no financial value is included/i);
  assert.match(resourceJs, /accountQualificationVolume/);
  assert.match(resourceJs, /\['Flat rate','Fixed fee'\]\.includes\(unit\)\?'flat rate'/);
  assert.match(resourceJs, /job\.quantity,job\.unit/);
  const start = migration.indexOf('CREATE OR REPLACE FUNCTION public.resource_account_job_qualifications_048');
  const end = migration.indexOf('-- -------------------------------------------------------------------------', start + 100);
  const fn = migration.slice(start, end);
  assert.match(fn, /job\.status = 'Approved'/);
  assert.match(fn, /'quantity'/);
  assert.match(fn, /WHEN job\.unit = 'Fixed fee' THEN COALESCE\(job\.quantity, 1\)/);
  assert.match(fn, /THEN 'Flat rate'/);
  assert.doesNotMatch(fn, /supplier_amount|supplier_rate|supplier_currency|currency|EUR/);
});

test('prompted Compliance workflow is available internally and in the Resource portal', () => {
  for (const id of [
    'complianceWorkflowCard', 'requestComplianceBtn', 'resendComplianceBtn',
    'requestComplianceChangesBtn', 'completeComplianceBtn',
  ]) assert.match(resourceHtml, new RegExp(`id="${id}"`), id);
  for (const id of [
    'myCompliance', 'portal-degree-level', 'portal-degree-type',
    'portal-field-category', 'portal-field-other', 'portal-institution',
    'portal-education-country', 'portal-graduation-year',
    'portal-translation-since', 'portal-revision-since', 'portal-mtpe-since',
    'portalDiplomaFiles', 'portalCvFiles', 'portalSubmitComplianceBtn',
  ]) assert.match(portalHtml, new RegExp(`id="${id}"`), id);
  assert.match(portalJs, /resource_portal_compliance_048/);
  assert.match(portalJs, /resource_portal_save_compliance_048/);
  assert.match(portalJs, /resource_portal_submit_compliance_048/);
  assert.match(resourceJs, /\/\.netlify\/functions\/resource-compliance/);
  assert.match(portalHtml, /does not prevent you from working on assigned Jobs/);
});

test('portal duration preview calculates calendar months and handles missing/future values', () => {
  const start = portalJs.indexOf('function portalExperienceDuration');
  const end = portalJs.indexOf('function updatePortalExperiencePreview', start);
  const fn = portalJs.slice(start, end);
  const FakeDate = class extends Date {
    constructor(...args) { super(...(args.length ? args : ['2026-09-15T00:00:00Z'])); }
  };
  const duration = vm.runInNewContext(`${fn}\nportalExperienceDuration`, {Date: FakeDate});
  assert.equal(duration('2018-05'), '8 years 4 months');
  assert.equal(duration('2026-09'), '0 years 0 months');
  assert.equal(duration('2026-10'), null);
  assert.equal(duration(''), null);
  assert.equal(duration('wrong'), null);
});

test('Resource portal never contains internal ISO eligibility data or controls', () => {
  for (const source of [portalHtml, portalJs, read('tms/resource-portal.js')]) {
    assert.doesNotMatch(source, /iso_eligibility|ISO Eligibility|isoTranslator|isoReviser|isoPostEditor/);
  }
  assert.match(resourceHtml, /ISO Eligibility/);
  assert.match(resourceHtml, /Internal only/);
  assert.doesNotMatch(resourceHtml, /<input[^>]+id="iso(?:Translator|Reviser|PostEditor)/);
  const portalProjection = migration.slice(
    migration.indexOf('CREATE OR REPLACE FUNCTION public.resource_portal_compliance_048'),
    migration.indexOf('CREATE OR REPLACE FUNCTION public.resource_portal_save_compliance_048'),
  );
  assert.doesNotMatch(portalProjection, /iso_eligibility/);
});

test('Compliance server endpoints reject invalid methods/origins before privileged calls', async () => {
  const workflow = require('../netlify/functions/resource-compliance');
  let result = await workflow.handler({httpMethod: 'GET', headers: {}, body: ''});
  assert.equal(result.statusCode, 405);
  result = await workflow.handler({
    httpMethod: 'POST', headers: {origin: 'https://attacker.invalid'},
    body: JSON.stringify({action: 'request', resource_id: crypto.randomUUID()}),
  });
  assert.equal(result.statusCode, 403);
  assert.throws(() => workflow.__test.parseBody({body: JSON.stringify({
    action: 'override', resource_id: crypto.randomUUID(),
  })}), /Unknown Compliance action/);

  const files = require('../netlify/functions/resource-compliance-files');
  result = await files.handler({httpMethod: 'GET', headers: {}, body: ''});
  assert.equal(result.statusCode, 405);
  assert.match(read('netlify/functions/resource-compliance-files.js'),
    /resource_compliance_file_dispatch_048/);
});

test('Compliance notification is resource-facing and contains no internal ISO result', () => {
  const {complianceNotificationMessage} = require('../netlify/functions/_shared/gmail');
  const previous = {
    from: process.env.GMAIL_FROM_EMAIL,
    name: process.env.GMAIL_FROM_NAME,
  };
  process.env.GMAIL_FROM_EMAIL = 'ops@retodo-ops.com';
  process.env.GMAIL_FROM_NAME = 'Retodo Ops';
  try {
    const raw = complianceNotificationMessage({
      email: 'resource@example.com', name: 'Test Resource',
      notification_kind: 'compliance_requested',
    }, 'https://tms.retodo-ops.com/resource-dashboard.html#myCompliance');
    const message = Buffer.from(raw.replaceAll('-', '+').replaceAll('_', '/'), 'base64').toString('utf8');
    const plainPart = message.match(/Content-Type: text\/plain; charset="UTF-8"\r\nContent-Transfer-Encoding: base64\r\n\r\n([^\r\n]+)/);
    assert.ok(plainPart);
    const plain = Buffer.from(plainPart[1], 'base64').toString('utf8');
    assert.match(message, /To: resource@example\.com/);
    assert.match(plain, /resource-dashboard\.html#myCompliance/);
    assert.match(plain, /continue working on assigned Jobs/);
    assert.doesNotMatch(plain, /ISO 17100|ISO 18587|Eligible|Not eligible/);
  } finally {
    if (previous.from === undefined) delete process.env.GMAIL_FROM_EMAIL;
    else process.env.GMAIL_FROM_EMAIL = previous.from;
    if (previous.name === undefined) delete process.env.GMAIL_FROM_NAME;
    else process.env.GMAIL_FROM_NAME = previous.name;
  }
});

test('Update 049 uses only forward migration 048 and current UI cache keys', () => {
  assert.match(migration, /BEGIN;/);
  assert.match(migration, /COMMIT;/);
  assert.match(migration, /requires the operational core and migration 047/);
  assert.match(resourceHtml, /style\.css\?v=053/);
  assert.match(resourceHtml, /resource\.js\?v=053/);
  assert.match(portalHtml, /style\.css\?v=053/);
  assert.match(portalHtml, /resource-dashboard\.js\?v=053/);
});
