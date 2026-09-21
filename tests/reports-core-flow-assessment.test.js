// Assessment of actual repository functions; no network, database or production writes.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = name => fs.readFileSync(path.join(__dirname, '../tms', name), 'utf8');
function between(file, start, end) {
  const text = source(file), first = text.indexOf(start), last = text.indexOf(end, first);
  assert.ok(first >= 0 && last > first, 'source boundary must exist');
  return text.slice(first, last);
}
function projectFixture(currency = 'EUR') {
  const ctx = vm.createContext({
    project: {currency:'EUR'}, roundMoney: x => Math.round(Number(x)*100)/100,
    TMS_REF: {scoopStatus: () => 'Ongoing'},
    jobs: [{id:'j', project_scoop_id:'s', status:'Assigned', supplier_amount:99, supplier_currency:currency}],
    purchaseOrders: [{job_id:'j', status:'Cancelled', total:999, currency}, {job_id:'j', status:'Issued', total:10.68, currency}]
  });
  vm.runInContext(between('project.js','function jobSupplierCost(', 'function renderScoopJobRow('), ctx);
  return ctx;
}
test('same-currency Scoop uses current PO, not cancelled PO or saved estimate', () => {
  const ctx = projectFixture();
  const result = vm.runInContext("scoopMetrics({id:'s',price:31})",ctx);
  assert.equal(result.expense,10.68); assert.equal(result.profit,20.32);
  assert.equal(result.margin.toFixed(2),'65.55');
});
test('cancelled Job is excluded from Scoop cost', () => {
  const ctx=projectFixture(); ctx.jobs[0].status='Cancelled';
  assert.equal(vm.runInContext("scoopMetrics({id:'s',price:31}).expense",ctx),0);
});
test('Job without active PO falls back to saved supplier amount', () => {
  const ctx=projectFixture(); ctx.purchaseOrders=[];
  assert.equal(vm.runInContext('jobSupplierCost(jobs[0]).amount',ctx),99);
});
test('zero client price returns finite margin (current behavior, not a proposed report policy)', () => {
  assert.equal(vm.runInContext("scoopMetrics({id:'s',price:0}).margin",projectFixture()),0);
});
test('KNOWN DEFECT: mixed-currency Scoop must not publish an unconverted numeric profit', {todo:'RPT-01: current Scoop code sums amounts without currency validation'}, () => {
  assert.equal(vm.runInContext("scoopMetrics({id:'s',price:31}).profit",projectFixture('USD')),null);
});
test('derived Scoop statuses exclude cancelled work and retain explicit stored state', () => {
  const ctx=vm.createContext({});
  vm.runInContext(between('reference-data.js','  function scoopStatus(', '  function installSettingsNav('),ctx);
  assert.equal(vm.runInContext("scoopStatus([{status:'Delivered'},{status:'Approved'},{status:'Cancelled'}])",ctx),'Ready for QA');
  assert.equal(vm.runInContext("scoopStatus([{status:'Approved'}])",ctx),'Approved');
  assert.equal(vm.runInContext("scoopStatus({status:'Waiting'},[{status:'Approved'}])",ctx),'Waiting');
});
test('Dashboard status filters run against actual functions', () => {
  const ctx=vm.createContext({isToday:()=>false,isTomorrow:()=>false});
  vm.runInContext(between('dashboard.js','function filterByTab(', 'function filterBySearch('),ctx);
  assert.equal(vm.runInContext("filterByTab([{status:'Approved'},{status:'Cancelled'}],'cancelled').length",ctx),1);
  assert.equal(vm.runInContext("filterByTab([{missing_po:true},{missing_po:false}],'missing_po').length",ctx),1);
});
test('bulk status partial failure is surfaced but first successful write is not rolled back', async () => {
  const writes=[], errorEl={textContent:'',classList:{remove(){}}};
  const ctx=vm.createContext({
    selectedDashboardRows:()=>[{scoopId:'s',projectId:'p'}],
    document:{getElementById:id=>id==='bulkStatusError'?errorEl:{value:id==='bulk-status'?'Approved':''}},
    combineDateTime:()=>null, closeBulkStatus:()=>assert.fail('must not close on failure'),
    _sb:{from:table=>({update:payload=>({in:async()=>{writes.push({table,payload});return {error:table==='projects'?{message:'denied'}:null};}})})}
  });
  vm.runInContext(between('dashboard.js','async function applyBulkStatus(', "document.getElementById('changeStatusBtn')"),ctx);
  await vm.runInContext('applyBulkStatus()',ctx);
  assert.equal(writes.length,2); assert.equal(errorEl.textContent,'denied');
  // RPT-02: this proves a partial-write window, not database transaction rollback.
});
