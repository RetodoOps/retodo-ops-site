'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('Update 055 binds Compliance unlock to the Retodo Agreement signature', () => {
  const migration = read('tms/migrations/051_update_055_compliance_unlock_retodo_signature.sql');
  const fn = read('netlify/functions/resource-compliance.js');
  assert.match(migration, /resource_framework_agreement_issuances/);
  assert.match(migration, /resource_compliance_workflow_dispatch_055/);
  assert.match(migration, /Framework agreement signed by Retodo/);
  assert.match(migration, /unlock_actor_profile_id/);
  assert.match(migration, /Awaiting Service Provider signature/);
  assert.match(migration, /Framework agreement fully signed/);
  assert.match(fn, /resource_compliance_workflow_dispatch_055/);
});

test('Agreement 1.1 and both HTML copies contain the electronic-signature equivalence clause', () => {
  const expectedHash = '9886350a460367dcd0b2f64a76e4e1535bb9f5d7a3930f60c9545fbcb487294c';
  const docx = fs.readFileSync(path.join(root, 'tms/agreements/03_Retodo_Ops_Freelancer_Framework_Agreement.docx'));
  assert.equal(crypto.createHash('sha256').update(docx).digest('hex'), expectedHash);
  for (const file of ['tms/resource.html', 'tms/resource-dashboard.html']) {
    const html = read(file);
    assert.match(html, /unlocks the Compliance phase/);
    assert.match(html, /Article 13\(4\) of the Bulgarian Electronic Document and Electronic Trust Services Act/);
    assert.match(html, /equivalent to that Party's handwritten signature/);
    assert.match(html, /retodo-tms-build" content="056"/);
  }
  assert.match(read('tms/resource-dashboard.html'), />Accept and sign</);
});

test('final PDF contains both Retodo and Service Provider signature records', () => {
  const pdf = read('tms/agreement-pdf.js');
  assert.match(pdf, /Retodo electronic signature/);
  assert.match(pdf, /Service Provider electronic signature/);
  assert.match(pdf, /unlocked the Compliance phase/);
  assert.match(pdf, /selecting Accept and sign/);
  assert.match(pdf, /retodo\.signed_at/);
  assert.match(pdf, /Both Parties must sign/);
});

test('build, migration and audit sequence is forward-only', () => {
  const build = JSON.parse(read('tms/build.json'));
  assert.equal(build.build, '056');
  assert.equal(build.source_baseline, 'Update 055');
  assert.ok(fs.existsSync(path.join(root, 'tms/migrations/051_update_055_compliance_unlock_retodo_signature.sql')));
  assert.ok(fs.existsSync(path.join(root, 'tms/audits/013_update_055_compliance_unlock_retodo_signature_audit.sql')));
});
