'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('Update 053 registration recovery keeps an existing Auth account usable', () => {
  const build = JSON.parse(read('tms/build.json'));
  assert.equal(build.build, '053');
  assert.equal(build.source_baseline, 'Update 052');
  const html = read('tms/register.html');
  const source = read('tms/register.js');
  const reset = read('tms/reset-password.html');
  const auth = read('tms/auth.js');

  assert.match(html, /retodo-tms-build" content="053"/);
  assert.match(html, /id="registrationReset"/);
  assert.match(html, /Forgot password \/ send setup link/);
  assert.match(html, /register\.js\?v=053/);
  assert.match(source, /isExistingAccountError/);
  assert.match(source, /identities\.length === 0/);
  assert.match(source, /requestPasswordReset\(email\)/);
  assert.match(source, /Invalid login credentials[\s\S]*existing account password/);
  assert.match(source, /password_reset.*complete/);
  assert.match(source, /rememberedRegistrationName/);
  assert.match(auth, /function requestPasswordReset\(email, redirectPath = 'reset-password\.html'\)/);
  assert.match(reset, /tms-registration-reset-return/);
  assert.match(reset, /register\.html\?password_reset=complete/);
});

test('Update 053 signed Agreement PDFs contain terms and are available to internal users', () => {
  const helper = read('tms/agreement-pdf.js');
  const portal = read('tms/resource-dashboard.js');
  const resource = read('tms/resource.js');
  const resourceHtml = read('tms/resource.html');
  const portalHtml = read('tms/resource-dashboard.html');
  const css = read('tms/style.css');

  assert.match(helper, /agreement-pdf-terms/);
  assert.match(helper, /agreement-pdf-signature/);
  assert.match(helper, /Retodo EOOD/);
  assert.match(helper, /208524462/);
  assert.match(helper, /agreement-pdf-rendering/);
  assert.match(helper, /windowWidth/);
  assert.match(portal, /tmsDownloadSignedAgreementPdf/);
  assert.match(resource, /Download signed PDF/);
  assert.match(resource, /frameworkAgreementLegalText/);
  assert.match(resource, /tmsDownloadSignedAgreementPdf/);
  assert.match(resourceHtml, /agreement-pdf\.js\?v=053/);
  assert.match(portalHtml, /agreement-pdf\.js\?v=053/);
  assert.match(css, /agreement-pdf-sheet\.agreement-pdf-rendering[\s\S]*left: 0/);
  for (let clause = 1; clause <= 15; clause += 1) {
    assert.match(resourceHtml, new RegExp(`<h4>${clause}\\.`), `Admin Agreement clause ${clause}`);
  }
});
