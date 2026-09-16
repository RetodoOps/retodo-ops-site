'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('Update 054 uses vector jsPDF output instead of an HTML screenshot', () => {
  const build = JSON.parse(read('tms/build.json'));
  const helper = read('tms/agreement-pdf.js');
  assert.equal(build.build, '054');
  assert.equal(build.source_baseline, 'Update 053');
  assert.match(helper, /new JsPdf/);
  assert.match(helper, /doc\.text/);
  assert.match(helper, /doc\.splitTextToSize/);
  assert.match(helper, /doc\.addPage/);
  assert.match(helper, /Electronic signature \/ acceptance/);
  assert.match(helper, /Document SHA-256/);
  assert.doesNotMatch(helper, /html2pdf/);
  assert.doesNotMatch(helper, /html2canvas/);
});

test('Update 054 exposes jsPDF before the Agreement helper in both user interfaces', () => {
  for (const file of ['tms/resource.html', 'tms/resource-dashboard.html']) {
    const html = read(file);
    const jspdf = html.indexOf('jspdf.umd.min.js');
    const helper = html.indexOf('agreement-pdf.js?v=054');
    assert.ok(jspdf >= 0, `${file} loads jsPDF`);
    assert.ok(helper > jspdf, `${file} loads the Agreement helper after jsPDF`);
    assert.match(html, /retodo-tms-build" content="054"/);
  }
});

test('Update 054 sends agreement clauses and signature details into the PDF document', async () => {
  const written = [];
  let savedAs = '';
  class FakePdf {
    constructor() {
      this.internal = {pageSize: {getWidth: () => 210, getHeight: () => 297}};
    }
    setFont() {}
    setFontSize() {}
    setTextColor() {}
    setDrawColor() {}
    line() {}
    addPage() {}
    setPage() {}
    getNumberOfPages() { return 1; }
    splitTextToSize(value) { return [String(value)]; }
    text(value) { written.push(Array.isArray(value) ? value.join(' ') : String(value)); }
    save(value) { savedAs = value; }
  }
  const document = {
    createElement() {
      return {
        html: '',
        set innerHTML(value) { this.html = value; },
        querySelectorAll() {
          return [...this.html.matchAll(/<(h[1-4]|p|li)[^>]*>([\s\S]*?)<\/\1>/gi)]
            .map(match => ({tagName: match[1].toUpperCase(), textContent: match[2].replace(/<[^>]+>/g, '')}));
        },
      };
    },
  };
  const window = {jspdf: {jsPDF: FakePdf}};
  vm.runInNewContext(read('tms/agreement-pdf.js'), {window, document, fetch: async () => ({ok: false}), Intl, Date});
  await window.tmsDownloadSignedAgreementPdf({
    agreement: {status: 'Accepted', agreement_version: '1.0', accepted_at: '2026-09-16T10:00:00Z', agreement_sha256: 'abc123'},
    provider: {service_provider_name: 'Test Provider', registration_or_id_number: 'VAT-1', service_provider_address: 'Sofia', registration_email: 'test@example.com', signatory_name: 'Test Signer'},
    legalHtml: '<h4>1. Scope</h4><p>This Agreement governs the services.</p><h4>15. Entire agreement</h4><p>These are the complete terms.</p>',
  });
  const output = written.join('\n');
  assert.match(output, /1\. Scope/);
  assert.match(output, /This Agreement governs the services/);
  assert.match(output, /15\. Entire agreement/);
  assert.match(output, /Test Provider/);
  assert.match(output, /Test Signer/);
  assert.match(output, /abc123/);
  assert.equal(savedAs, 'Retodo_Ops_Freelancer_Agreement_Test_Signer.pdf');
});
