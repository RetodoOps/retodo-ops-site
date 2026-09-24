// Run against a local static server only; Supabase/auth are mocked before page scripts.
const assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async()=>{
 const options={headless:true};
 if(process.env.CHROMIUM_MODULE){const imported=require(process.env.CHROMIUM_MODULE);const binary=imported.default||imported;options.executablePath=await binary.executablePath();options.args=binary.args;}
 const browser=await chromium.launch(options);
 const page=await browser.newPage({viewport:{width:1440,height:1000},acceptDownloads:true});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 let fail=false,oversize=false,role='admin',lastRequest;
 const rows=Array.from({length:55},(_,i)=>({id:'s'+i,project_id:'p'+i,name:i===0?'<img src=x onerror=alert(1)>':'Project '+(i+1),project_name:'Localization',client:'Example client',account:'European languages',pm:'Alex',status:'Ongoing',date:'2026-09-24',currency:'EUR',client_value:300,profit:237.66,margin:79.22,costs:{EUR:62.34},job_count:3,scoop_count:2,estimate_count:2,unknown_cost_count:0,currency_warning_count:0,po_warning_count:0,resource:'Resource one',service:'Translation',source_language:'English',target_language:'Bulgarian',deadline:'2026-09-24T16:00:00Z',quantity:123.456,unit:'Source words',cost_basis:'PO commitment',po_number:'PO-100',po_version:2}));
 await page.exposeFunction('fixtureRpc',async(name,args)=>{
  if(name==='current_app_role')return {data:role,error:null};
  if(name==='current_user_access_enabled')return {data:true,error:null};
  assert.equal(name,'tms_report');lastRequest=args;
  if(fail)return {data:null,error:{code:'PGRST202',message:'Missing migration'}};
  const matched=args.p_filters.search==='empty'?[]:rows;
  return {data:{rows:matched.slice(args.p_offset,args.p_offset+args.p_limit),total_count:oversize?10001:matched.length,project_count:matched.length,warning_rows:0,summary_by_currency:matched.length?[{currency:'EUR',client_value:16500,supplier_cost:3428.7,profit:13071.3,margin:79.22,estimate_count:110,incomplete_rows:0}]:[],generated_at:'2026-09-24T12:00:00Z',date_basis:args.p_type==='jobs'?'Job deadline (UTC)':'Project date',report_type:args.p_type,filters:args.p_filters,next_offset:args.p_offset+args.p_limit<matched.length?args.p_offset+args.p_limit:null},error:null};
 });
 await page.addInitScript(()=>{window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:{user:{id:'fixture'}}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signOut:async()=>({})},rpc:(name,args)=>window.fixtureRpc(name,args)})};});
 await page.route('https://cdn.jsdelivr.net/**',route=>route.fulfill({contentType:'text/javascript',body:''}));
 await page.route('https://*.supabase.co/**',route=>route.abort());
 const base=process.env.REPORT_BASE_URL||'http://127.0.0.1:8765/tms/';
 await page.goto(base+'reports.html?type=projects');await page.getByText('1–50 of 55',{exact:true}).waitFor();
 assert.equal(await page.locator('#reportTable tbody tr').count(),50);
 assert.equal(await page.locator('#reportTable img').count(),0);
 await page.locator('#nextPage').click();await page.getByText('51–55 of 55',{exact:true}).waitFor();assert.equal(lastRequest.p_offset,50);
 await page.locator('#previousPage').click();await page.getByText('1–50 of 55',{exact:true}).waitFor();
 await page.locator('#search').fill('empty');await page.getByRole('button',{name:'View report',exact:true}).click();await page.getByText('No matching results.',{exact:false}).waitFor();assert.equal(await page.locator('#exportReport').isDisabled(),true);
 await page.getByRole('button',{name:'Clear filters',exact:true}).click();await page.getByText('1–50 of 55',{exact:true}).waitFor();
 const download=page.waitForEvent('download');await page.locator('#exportReport').click();assert.match((await download).suggestedFilename(),/retodo-projects.*csv/);assert.equal(lastRequest.p_limit,10000);
 oversize=true;await page.locator('#exportReport').click();await page.getByText('Export is limited to 10,000 rows.',{exact:false}).waitFor();oversize=false;
 await page.locator('#reportTable').scrollIntoViewIfNeeded();assert.ok((await page.locator('#reportTable').boundingBox()).height>100);await page.screenshot({path:'/tmp/reports-projects-desktop.png',fullPage:true});
 await page.locator('.tabs-bar').getByText('Jobs',{exact:true}).click();await page.getByText('1–50 of 55',{exact:true}).waitFor();assert.equal(lastRequest.p_type,'jobs');await page.getByRole('columnheader',{name:'Supplier cost / PO',exact:true}).waitFor();
 role='qa';await page.goto(base+'reports.html?type=margin');await page.getByText('1–50 of 55',{exact:true}).waitFor();assert.equal(await page.locator('#exportReport').isEnabled(),true);assert.equal(await page.locator('#status').isEnabled(),true);
 await page.locator('.nav-item').filter({hasText:'Clients'}).click();await page.locator('#sub-cli').waitFor({state:'visible'});
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:'/tmp/reports-margin-mobile.png',fullPage:true});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 fail=true;await page.getByRole('button',{name:'View report',exact:true}).click();await page.getByText('Reports are not available yet.',{exact:false}).waitFor();assert.equal(await page.locator('#reportTable tbody tr').count(),0);assert.equal(await page.locator('#exportReport').isDisabled(),true);
 await page.goto(base+'reports.html?type=invoices');await page.getByText('Invoice reporting is not available',{exact:false}).waitFor();assert.equal(await page.locator('#reportFilters').isVisible(),false);
 assert.deepEqual(errors,[]);console.log('PASS browser fixture: tabs, pagination, filters, empty/error states, CSV, export cap, QA controls, sidebar, XSS and mobile overflow');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
