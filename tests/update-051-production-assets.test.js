'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const jobJs = read('tms/job.js');
const dashboardJs = read('tms/dashboard.js');

test('Update 051 recovery remains present under the current deployment marker', () => {
  const build = JSON.parse(read('tms/build.json'));
  assert.deepEqual(build, {
    product: 'Retodo Ops TMS',
    build: '052',
    release: 'Update 052 - interface completion',
    source_baseline: 'Update 051',
    built_on: '2026-09-14',
  });
  for (const file of [
    'tms/job.html', 'tms/dashboard.html',
    'tms/resource.html', 'tms/resource-dashboard.html',
  ]) {
    const html = read(file);
    assert.match(html, /<meta name="retodo-tms-build" content="052">/);
    assert.match(html, /style\.css\?v=052/);
  }
  assert.match(read('tms/job.html'), /job\.js\?v=052/);
  assert.match(read('tms/dashboard.html'), /dashboard\.js\?v=052/);
  assert.match(read('tms/resource.html'), /resource\.js\?v=052/);
  assert.match(read('tms/resource-dashboard.html'), /resource-dashboard\.js\?v=052/);
});

test('Job save compares the displayed deadline fields, not a timezone reparse', () => {
  assert.match(jobJs, /loadedDeadlineFields=deadlineFieldSnapshot\(\)/);
  assert.match(jobJs, /deadlineChanged=deadlineFieldSnapshot\(\)!==loadedDeadlineFields/);
  assert.match(jobJs, /deadline=deadlineChanged\?combineDateTime/);
  assert.doesNotMatch(jobJs, /sameMinute\(/);
});

test('Dashboard mapper preserves the real Job resource id and renders identity fields', () => {
  const start = dashboardJs.indexOf('function dashboardResourceAssignments(');
  const end = dashboardJs.indexOf('\n// ── Date helpers', start);
  assert.ok(start >= 0 && end > start, 'dashboard resource mapper is extractable');
  const sandbox = {
    jobs: [{id:'job-1',job_number:'260905_TEST_NB_NOREF-S02-MTP_J01',resource_id:'resource-1'}],
    resources: new Map([['resource-1', {
      id:'resource-1', internal_number:'RO-LNG-00001', legal_name:'Test Test',
      company_name:null, resource_type:'Freelancer',
    }]]),
  };
  vm.createContext(sandbox);
  vm.runInContext(`${dashboardJs.slice(start, end)}\nresult = dashboardResourceAssignments(jobs, resources);`, sandbox);
  assert.deepEqual(JSON.parse(JSON.stringify(sandbox.result)), [{
    job_id:'job-1',
    job_number:'260905_TEST_NB_NOREF-S02-MTP_J01',
    resource_id:'resource-1',
    resource_number:'RO-LNG-00001',
    resource_name:'Test Test',
    resource_type:'Freelancer',
  }]);
  assert.match(dashboardJs, /resource_assignments: assignments/);
  assert.match(dashboardJs, /href="resource\.html\?id=/);
});

test('Netlify disables stale HTML and JavaScript caching', () => {
  const config = read('netlify.toml');
  assert.match(config, /for = "\/\*\.html"[\s\S]*Cache-Control = "no-cache, no-store, must-revalidate"/);
  assert.match(config, /for = "\/\*\.js"[\s\S]*Cache-Control = "no-cache, must-revalidate"/);
});
