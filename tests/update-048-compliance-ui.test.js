'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('tms/resource.html');
const source = read('tms/resource.js');
const migration = read('tms/migrations/047_compliance_evidence_iso_eligibility.sql');

test('education, experience, evidence and read-only ISO panels reuse Resource Compliance', () => {
  for (const id of [
    'pane-qualifications', 'educationEvidenceCard', 'edu-degree', 'edu-degree-type',
    'edu-field', 'edu-institution', 'edu-country', 'edu-graduation',
    'edu-graduation-year',
    'complianceFileInput', 'r-translation-since', 'r-revision-since',
    'r-mtpe-since', 'complianceCvFiles', 'isoTranslatorEligibility',
    'isoReviserEligibility', 'isoPostEditorEligibility',
  ]) assert.match(html, new RegExp(`id="${id}"`), id);
  assert.match(html, /type="month"/);
  assert.match(html, /Evidence type/);
  assert.match(html, /<strong>CV<\/strong>/);
  assert.doesNotMatch(html, /<input[^>]*id="(?:isoTranslatorEligibility|isoReviserEligibility|isoPostEditorEligibility)"/);
  assert.match(source, /await refreshComplianceSummary\(\)/);
  assert.match(source, /nextUtcMidnight/);
  assert.match(source, /reviewComplianceEvidence/);
  assert.doesNotMatch(source, /end_year\}-01/);
});

test('Blind CV preview and both exports use current calculated service durations', () => {
  const linesFunction = source.slice(
    source.indexOf('function blindCvExperienceLines()'),
    source.indexOf('function renderBlindCvPreview()'),
  );
  const cvData = {professional_experience: {
    translation: {display: '8 years 4 months'},
    revision: {display: '6 years 2 months'},
    mtpe: {display: '5 years 7 months'},
  }};
  const lines = vm.runInNewContext(`${linesFunction}\nblindCvExperienceLines()`, {cvData});
  assert.deepEqual(Array.from(lines), [
    'Translation experience: 8 years 4 months',
    'Revision experience: 6 years 2 months',
    'MTPE experience: 5 years 7 months',
  ]);
  assert.match(source, /function renderBlindCvPreview\(\)[\s\S]*blindCvExperienceLines\(\)/);
  assert.match(source, /function cvLines\(\)[\s\S]*blindCvExperienceLines\(\)/);
  assert.match(source, /async function downloadBlindCvDocx\(\)[\s\S]*cvLines\(\)/);
  assert.match(source, /async function downloadBlindCvPdf\(\)[\s\S]*blindCvPreview/);
  assert.match(source, /async function downloadBlindCvDocx\(\)\{if\(!cvData\)return;try\{await refreshBlindCvData\(\)/);
  assert.match(source, /async function downloadBlindCvPdf\(\)\{if\(!cvData\)return;try\{await refreshBlindCvData\(\)/);
  assert.doesNotMatch(linesFunction, /iso_eligibility|file_record|email|legal_name/);
});

test('ISO is internal-only: portal pages lack data and SQL rejects resource callers', () => {
  for (const portal of [
    'tms/resource-dashboard.html', 'tms/resource-dashboard.js',
    'tms/resource-job.html', 'tms/resource-job.js',
    'tms/resource-portal.js', 'tms/resource-po.html', 'tms/resource-po.js',
  ]) assert.doesNotMatch(read(portal), /iso_eligibility|isoEligibility|ISO Eligibility/);
  assert.match(migration, /IF NOT public\.is_company_user\(\) THEN\s+RAISE EXCEPTION 'Company access required'/);
  assert.match(migration, /auth\.role\(\) IS DISTINCT FROM 'service_role'/);
  assert.match(migration, /document\.status = 'Valid'/);
  assert.match(source, /\['admin','pm','qa','client_relations'\]\.includes\(appRole\)/);
  assert.match(read('tms/style.css'), /\.internal-resource-mode \.resource-tabs/);
});

test('discarded Job files stay in audit but are not listed as active attachments', () => {
  const job = read('tms/job.js');
  assert.match(job, /const visibleFiles=jobFiles\.filter\(file=>/);
  assert.match(job, /upload_status[^;]*'Failed'/);
  assert.match(job, /const readyCount=jobFiles\.filter/);
  assert.match(read('tms/job.html'), /job\.js\?v=048/);
});

test('Compliance file endpoint rejects invalid methods and origins before privileged access', async () => {
  const api = require('../netlify/functions/resource-compliance-files');
  let result = await api.handler({httpMethod: 'GET', headers: {}, body: ''});
  assert.equal(result.statusCode, 405);
  assert.equal(result.headers['Cache-Control'], 'no-store');
  result = await api.handler({
    httpMethod: 'POST', headers: {origin: 'https://attacker.invalid'},
    body: JSON.stringify({action: 'download'}),
  });
  assert.equal(result.statusCode, 403);
  result = await api.handler({
    httpMethod: 'POST', headers: {origin: 'https://tms.retodo-ops.com'},
    body: JSON.stringify({action: 'override_iso'}),
  });
  assert.equal(result.statusCode, 400);
  assert.match(JSON.parse(result.body).error, /Unknown Compliance file action/);
  assert.throws(() => api.__test.requireUuid('wrong', 'File ID'), /File ID is required/);
  assert.throws(() => api.__test.parseBody({body: '[]'}), /Invalid request/);
});
