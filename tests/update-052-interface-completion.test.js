'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('build 052 markers and published logo are complete', () => {
  const build = JSON.parse(read('tms/build.json'));
  assert.equal(build.build, '052');
  assert.equal(build.source_baseline, 'Update 051');
  for (const file of ['dashboard.html','job.html','register.html','resource.html','resource-dashboard.html']) {
    const html = read(`tms/${file}`);
    assert.match(html, /retodo-tms-build" content="052"/);
    assert.match(html, /style\.css\?v=052/);
  }
  assert.ok(fs.statSync(path.join(root, 'tms/Logo-440x140.png')).size > 1000);
  assert.match(read('tms/resource.js'), /src="Logo-440x140\.png"/);
  assert.match(read('tms/resource.js'), /fetch\('Logo-440x140\.png'\)/);
});

test('Dashboard bulk cancellation updates selected Scoops and Projects', () => {
  const html = read('tms/dashboard.html');
  const source = read('tms/dashboard.js');
  const migration = read('tms/migrations/050_update_052_dashboard_cancelled_status.sql');
  assert.match(html, /<option>Cancelled<\/option>/);
  assert.match(source, /key: 'cancelled',\s+label: 'Cancelled'/);
  assert.match(source, /data-project-id=/);
  assert.match(source, /data-scoop-id=/);
  assert.match(source, /from\('project_scoops'\)\.update\(\{status, status_manual:true\}\)/);
  assert.match(source, /from\('projects'\)\.update/);
  assert.match(migration, /projects_new_status_check[\s\S]*'Cancelled'/);
  assert.match(migration, /project_scoops_status_check[\s\S]*'Cancelled'/);
});

test('Job sidebar contains the complete Reports menu', () => {
  const html = read('tms/job.html');
  assert.match(html, />Reports<span class="nav-arrow">/);
  for (const type of ['projects','jobs','margin','invoices']) {
    assert.match(html, new RegExp(`reports\\.html\\?type=${type}`));
  }
});

test('self-registration is explicit, current and protects an existing company session', () => {
  const html = read('tms/register.html');
  const source = read('tms/register.js');
  assert.match(html, /register\.js\?v=052/);
  assert.match(html, /onboarding\.js\?v=052/);
  assert.match(html, /id="registerBtn" type="submit"/);
  assert.match(source, /Creating account…/);
  assert.match(source, /if \(existing\) await _sb\.auth\.signOut\(\)/);
  assert.match(source, /identities\.length === 0/);
  assert.match(source, /Confirmation sent to/);
});

test('agreement uses one combined ID field and produces the accepted PDF', () => {
  const html = read('tms/resource-dashboard.html');
  const source = read('tms/resource-dashboard.js');
  assert.match(html, /ID \/ Tax \/ VAT \*/);
  assert.doesNotMatch(html, /id="portal-agreement-tax"/);
  assert.match(source, /registration_or_id_number: portalValue\('portal-agreement-registration'\)/);
  assert.match(source, /tax_vat_number: portalValue\('portal-agreement-registration'\)/);
  assert.match(source, /Download signed PDF/);
  assert.match(source, /downloadPortalSignedAgreementPdf/);
  assert.match(source, /agreement-pdf-signature/);
  assert.match(source, /agreement_sha256/);
  assert.match(html, /html2pdf\.bundle\.min\.js/);
});
