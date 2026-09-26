const test=require('node:test');
const assert=require('node:assert/strict');
const ui=require('../tms/reports.js');
test('CSV neutralizes spreadsheet formulas including whitespace prefixes and quotes',()=>{
 for(const value of ['=SUM(A1:A2)','+cmd','-1+2','@SUM(1)','  =1','\t=1','\r=1','\n=1']) assert.equal(ui.csvCell(value).startsWith('"\''),true);
 assert.equal(ui.csvCell('normal "quoted",\ntext'),'"normal ""quoted"",\ntext"');
});
test('HTML escapes hostile record names',()=>{assert.equal(ui.escape('<img src=x onerror="x">'), '&lt;img src=x onerror=&quot;x&quot;&gt;');});
test('CSV retains report metadata, raw IDs, currency buckets and warnings',()=>{
 const csv=ui.csv({report_type:'margin',generated_at:'2026-09-24',date_basis:'Project date',filters:{scope:'active'},total_count:1,rows:[{id:'id-1',project_id:'p-1',name:'=1',costs:{EUR:3,USD:4},currency_warning_count:1,estimate_count:1}],summary_by_currency:[]});
 assert.ok(csv.includes('"id-1","p-1"'));assert.ok(csv.includes("\"'=1\""));assert.ok(csv.includes('supplier_cost_USD'));assert.ok(csv.includes('Incompatible or missing currency'));assert.ok(csv.includes('source_language'));assert.ok(csv.includes('target_language'));assert.ok(csv.includes('Project date'));
});
test('Unknown costs, empty Scoops and unallocated Jobs are visible warnings',()=>{const value=ui.warnings({unknown_cost_count:1,empty_scoop_count:1,unallocated_job_count:1},'projects');for(const word of ['unknown','Scoop without Jobs','Jobs without a Scoop']) assert.ok(value.includes(word));});
test('Null amounts stay unavailable and currencies stay separate',()=>{assert.equal(ui.number(null),'—');assert.equal(ui.costs({costs:{EUR:10,USD:20}}),'EUR 10.00; USD 20.00');});

test('CSV keeps signed numeric values numeric while protecting negative text',()=>{assert.equal(ui.csvCell(-123.45),'-123.45');assert.equal(ui.csvCell(0),'0');assert.equal(ui.csvCell('-123.45'),'"\'-123.45"');});
