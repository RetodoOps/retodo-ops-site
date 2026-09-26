const test=require('node:test');
const assert=require('node:assert/strict');
const ui=require('../tms/reports.js');
test('CSV neutralizes spreadsheet formulas including whitespace prefixes and quotes',()=>{
 for(const value of ['=SUM(A1:A2)','+cmd','-1+2','@SUM(1)','  =1','\t=1','\r=1','\n=1']) assert.equal(ui.csvCell(value).startsWith('"\''),true);
 assert.equal(ui.csvCell('normal "quoted",\ntext'),'"normal ""quoted"",\ntext"');
});
test('HTML escapes hostile record names',()=>{assert.equal(ui.escape('<img src=x onerror="x">'), '&lt;img src=x onerror=&quot;x&quot;&gt;');});
test('CSV has explicit Margin languages, flat costs, numeric negatives and separate metadata',()=>{
 const csv=ui.csv({report_type:'margin',generated_at:'2026-09-24',date_basis:'Project date',filters:{scope:'active'},total_count:1,rows:[{id:'id-1',project_id:'p-1',name:'=1',source_language:'English',target_language:'Bulgarian',profit:-12.34,margin:-5,costs:{EUR:3,USD:4},issue_codes:['currency_mismatch'],info_codes:['estimate']}],summary_by_currency:[]});
 assert.ok(csv.includes('"id-1","p-1"'));assert.ok(csv.includes("\"'=1\""));assert.ok(csv.includes('supplier_cost_USD'));assert.ok(csv.includes('"Bulgarian"'));assert.ok(csv.includes(',-12.34,-5,3,4,'));assert.ok(csv.includes('"REPORT METADATA"'));assert.ok(csv.includes('currency_mismatch'));
});
test('Finite numeric values preserve signed numbers and quantity precision',()=>{
 for(const n of [-12.34,0,42,0.123456789,-0.123456789])assert.equal(ui.csvCell(n),String(n));
 assert.equal(ui.csvCell(Infinity),'');assert.equal(ui.csvCell('-12.34'),'"\'-12.34"');
});
test('Distinct backend failures never masquerade as empty results',()=>{
 for(const [code,state] of [['PGRST202','unavailable'],['VERSION','unavailable'],['42501','denied'],['TIMEOUT','timeout']])assert.equal(ui.errorState({code})[0],state);
 assert.equal(ui.errorState(new TypeError('Failed to fetch'))[0],'network');assert.equal(ui.errorState({code:'42703'})[0],'query');
});
test('Unknown costs, empty Scoops and unallocated Jobs are visible warnings',()=>{const value=ui.warnings({unknown_cost_count:1,empty_scoop_count:1,unallocated_job_count:1},'projects');for(const word of ['unknown','Scoop without Jobs','Jobs without a Scoop']) assert.ok(value.includes(word));});
test('Null amounts stay unavailable and currencies stay separate',()=>{assert.equal(ui.number(null),'—');assert.equal(ui.costs({costs:{EUR:10,USD:20}}),'EUR 10.00; USD 20.00');});
