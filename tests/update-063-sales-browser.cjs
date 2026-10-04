// Browser fixture. All external mail/AI/database requests are intercepted.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const ROOT=path.join(__dirname,'../tms'),OUTPUT=process.env.SALES_TEST_OUTPUT||'/tmp/retodo-sales-ui';
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
(async()=>{
 fs.mkdirSync(OUTPUT,{recursive:true});
 const server=http.createServer((req,res)=>{const file=path.join(ROOT,decodeURIComponent(req.url.split('?')[0]));if(!file.startsWith(ROOT+path.sep)){res.writeHead(404).end();return;}try{const bytes=fs.readFileSync(file);res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':file.endsWith('.png')?'image/png':'text/html');res.end(bytes);}catch{res.writeHead(404).end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 let browser;
 try{
  const binary=require(process.env.CHROMIUM_MODULE||'@sparticuz/chromium');
  browser=await chromium.launch({headless:true,executablePath:await binary.executablePath(),args:binary.args});
  const page=await browser.newPage({viewport:{width:1440,height:1050},acceptDownloads:true});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
  const now=new Date().toISOString();let role='admin',lastCommand=null,failedApproval=false,lastQuery='';
  const prospect={id:id(10),name:'Northline Localization',domain:'northline.invalid',country:'Sweden',sector:'Language services',fit_note:'Public vendor registration with a Nordic language requirement.',source_url:'https://northline.invalid/vendors',researched_at:now,stage:'qualified',notes:'Evidence is a test fixture.',version:1};
  const contact={id:id(11),prospect_id:prospect.id,name:'Alex Example',role_title:'Vendor Manager',email:'alex@northline.invalid',linkedin_url:'https://www.linkedin.com/in/example',source_url:'https://northline.invalid/vendors',outreach_basis:'Public vendor program',verified_at:now,version:1};
  const convo={id:id(12),prospect_id:prospect.id,contact_id:contact.id,recipient:contact.email,sender:'eli.s@retodo-ops.com',reply_to:'eli.s@retodo-ops.com',state:'active',thread_id:null,synced_at:null,company:prospect.name,contact_name:contact.name,created_at:now,updated_at:now};
  const messages=[0,1,2].map((step)=>({id:id(20+step),conversation_id:convo.id,kind:step?'followup':'initial',direction:'outbound',step,subject:'Nordic language support',body:step?'A short follow-up to the proposed partnership.\n\nEli Stoyanova':'Hello Alex,\n\nCould we discuss support for your Nordic localization projects?\n\nEli Stoyanova\nRetodo Ops\n\nIf this is not relevant, reply and I will stop following up.',attachments:[],delay_days:[0,5,12][step],due_at:now,state:'draft',version:1,company:prospect.name,recipient:contact.email,sender:convo.sender,reply_to:convo.reply_to,verified_at:now,outreach_basis:contact.outreach_basis,created_at:now}));
  const material={id:id(40),title:'Nordic language support',content:'## Working together\nSupport for your Nordic localization work.\nA proposed discussion of requirements and the first project.\n\n## Next step\nDiscuss the brief with Eli Stoyanova.\neli.s@retodo-ops.com',version:1,updated_at:now};
  const data={settings:{sending_enabled:false,research_enabled:false,monthly_cap:30,reserve_eur:5,recurring_eur:5,daily_limit:10,approved_facts:'Test facts only.',target_brief:'LSPs with Nordic vendor requirements.',research_interval_days:7},runtime:{mailbox_ok:false},counts:{prospects:1,review:3,queued:0,sent:0,replies:0,attention:0},prospect_count:1,prospects:[prospect],conversations:[convo],review:messages,materials:[material],tasks:[],attention:[],jobs:[],events:[],budget:{charged:.12,reserved:0}};
  await page.exposeFunction('fixtureRpc',async(name,args)=>{
   if(name==='current_app_role')return {data:role};if(name==='current_user_access_enabled')return {data:true};if(name==='tms_search_062')return {data:[]};
   if(name==='sales_workspace_063'){lastQuery=args.p_query;return {data:structuredClone({...data,prospects:args.p_query==='empty'?[]:data.prospects,prospect_count:args.p_query==='empty'?0:1})};}
   if(name==='sales_detail_063')return {data:structuredClone({prospect,contacts:[contact],conversations:[convo],messages,client_matches:[]})};
   if(name==='sales_command_063'){
    lastCommand=structuredClone(args);
    if(args.p_action==='approve'&&failedApproval)return {error:{message:'A selected draft changed. Refresh and review the whole batch'}};
    if(args.p_action==='approve'){data.review=data.review.filter(m=>!args.p_data.messages.some(x=>x.id===m.id));data.counts.review=data.review.length;data.counts.queued=args.p_data.messages.length;}
    if(args.p_action==='settings')Object.assign(data.settings,args.p_data);
    if(args.p_action==='material')data.materials.push({...args.p_data,id:id(41),version:1,updated_at:now});
    return {data:{id:id(90),ok:true}};
   }
   throw new Error('Unexpected RPC '+name);
  });
  await page.addInitScript(()=>{window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:{user:{id:'fixture'},access_token:'fixture-only'}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signOut:async()=>({})},rpc:(name,args)=>window.fixtureRpc(name,args)})};});
  await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'text/javascript',body:''}));
  await page.route('https://*.supabase.co/**',r=>r.abort());
  await page.route('**/.netlify/functions/sales',async route=>{const body=route.request().postDataJSON();assert.ok(['status','run','check_mailbox','ai'].includes(body.action));await route.fulfill({contentType:'application/json',body:JSON.stringify(body.action==='status'?{ai_ready:false,ai_hold:'AI is not configured.',worker_ready:false}:body.action==='check_mailbox'?{account:'ops@retodo-ops.com',alias:'eli.s@retodo-ops.com'}:{queued:true})});});
  const base=`http://127.0.0.1:${server.address().port}/`;
  await page.goto(base+'sales.html');await page.getByText('Next actions',{exact:true}).waitFor();
  assert.equal(await page.locator('.sidebar a[href="sales.html"]').count(),1);assert.equal(await page.locator('.sidebar a[href^="invoice.html"]').count(),2);
  await page.screenshot({path:path.join(OUTPUT,'sales-today.png'),fullPage:true});
  await page.locator('[data-tab="prospects"]').click();await page.getByRole('button',{name:'Open',exact:true}).click();await page.getByRole('heading',{name:prospect.name,exact:true}).waitFor();
  assert.equal(await page.getByRole('link',{name:'LinkedIn profile'}).getAttribute('rel'),'noopener noreferrer');
  await page.getByRole('button',{name:'Prepare outreach',exact:true}).click();await page.locator('[name="subject"]').fill('Sequence subject');await page.locator('[name="initial"]').fill('A complete initial message');await page.locator('[name="followup_one"]').fill('Follow-up 1');await page.locator('[name="followup_two"]').fill('Follow-up 2');
  await page.locator('[name="files"]').setInputFiles({name:'Capabilities.txt',mimeType:'text/plain',buffer:Buffer.from('Approved facts')});
  await page.getByRole('button',{name:'Save for batch review',exact:true}).click();await page.locator('#salesSelectAll').waitFor();
  assert.equal(lastCommand.p_action,'sequence');assert.equal(lastCommand.p_data.messages.length,3);assert.equal(lastCommand.p_data.messages[0].attachments[0].name,'Capabilities.txt');assert.equal(lastCommand.p_data.messages[1].delay_days,5);
  await page.locator('[data-select]').nth(0).check();await page.locator('[data-select]').nth(1).check();await page.getByRole('button',{name:'Review selected batch'}).click();
  await page.getByRole('heading',{name:'Review 2 messages'}).waitFor();assert.equal(await page.locator('#salesDialog .sales-pre').count(),2);assert.match(await page.locator('#salesDialog').innerText(),/eli.s@retodo-ops.com/);
  failedApproval=true;await page.locator('[name="confirmed"]').check();await page.getByRole('button',{name:'Approve 2 messages'}).click();await page.getByText('A selected draft changed. Refresh and review the whole batch',{exact:true}).waitFor();
  assert.deepEqual(lastCommand.p_data.messages,[{id:messages[0].id,version:1},{id:messages[1].id,version:1}]);
  failedApproval=false;await page.getByRole('button',{name:'Approve 2 messages'}).click();await page.waitForFunction(()=>!document.getElementById('salesDialog').open);assert.equal(data.review.length,1);
  await page.screenshot({path:path.join(OUTPUT,'sales-review.png'),fullPage:true});
  await page.locator('[data-tab="conversations"]').click();await page.getByRole('button',{name:'Open',exact:true}).click();await page.getByRole('heading',{name:'Conversation · '+prospect.name}).waitFor();assert.match(await page.locator('#salesDialog').innerText(),/Eli Stoyanova/);await page.locator('[data-action="close-dialog"]').click();
  await page.locator('[data-tab="materials"]').click();await page.getByRole('button',{name:'Edit & preview'}).click();await page.getByRole('button',{name:'Preview slides'}).click();assert.equal(await page.locator('.sales-material-preview').count(),2);await page.locator('[data-action="close-dialog"]').click();
  const downloaded=page.waitForEvent('download');await page.getByRole('button',{name:'PowerPoint',exact:true}).click();const file=await downloaded.catch(async e=>{console.error('Export status:',await page.locator('#salesNotice').innerText());throw e;});await file.saveAs(path.join(OUTPUT,file.suggestedFilename()));assert.ok(file.suggestedFilename().endsWith('.pptx'));
  await page.locator('[data-tab="settings"]').click();await page.locator('[name="daily_limit"]').fill('7');await page.getByRole('button',{name:'Check mailbox connection'}).click();await page.getByText('Mailbox check passed: ops@retodo-ops.com. Sales sender: eli.s@retodo-ops.com.',{exact:true}).waitFor();assert.equal(await page.locator('[name="daily_limit"]').inputValue(),'7');await page.getByRole('button',{name:'Save Sales settings'}).click();await page.getByText('Sales settings saved.',{exact:true}).waitFor();assert.equal(lastCommand.p_data.daily_limit,'7');assert.equal(lastCommand.p_data.sending_enabled,false);
  await page.locator('[data-tab="prospects"]').click();await page.locator('#salesSearch').fill('empty');await page.getByRole('button',{name:'Search',exact:true}).click();await page.getByText('Your prospect pipeline starts here',{exact:true}).waitFor();assert.equal(lastQuery,'empty');
  data.prospects=[{...prospect,name:'<img src=x onerror=alert(1)>',source_url:'javascript:alert(1)'}];await page.getByRole('button',{name:'Clear',exact:true}).click();await page.getByText('<img src=x onerror=alert(1)>',{exact:true}).waitFor();assert.equal(await page.locator('#salesView img').count(),0);assert.equal(await page.locator('a[href^="javascript:"]').count(),0);
  data.prospects=[prospect];await page.setViewportSize({width:390,height:844});await page.locator('[data-tab="today"]').click();await page.screenshot({path:path.join(OUTPUT,'sales-mobile.png'),fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  role='qa';await page.goto(base+'sales.html');await page.getByText('Sales is available to administrators during the pilot.',{exact:true}).waitFor();assert.equal(await page.locator('.sidebar a[href="sales.html"]').count(),0);
  assert.deepEqual(errors,[]);console.log('PASS browser: navigation, sequence and attachment payloads, exact batch approval, stale-review error, conversations, materials/PPTX export, settings, search, XSS, mobile and QA access');
 }finally{if(browser)await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
