// Browser fixture. All external mail/AI/database requests are intercepted.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const ROOT=path.join(__dirname,'../tms'),OUTPUT=process.env.SALES_TEST_OUTPUT||'/tmp/retodo-sales-ui';
const signature=require('../tms/sales-signature'),defaults=signature.DEFAULTS;
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
  const messages=[0,1,2].map((step)=>({id:id(20+step),conversation_id:convo.id,kind:step?'followup':'initial',direction:'outbound',step,subject:'Nordic language support',body:step?'A short follow-up to the proposed partnership.':'Hello Alex,\n\nCould we discuss support for your Nordic localization projects?\n\nIf this is not relevant, reply and I will stop following up.',signature:step<2?{...defaults}:{},attachments:[],delay_days:[0,5,12][step],due_at:now,state:'draft',version:1,company:prospect.name,recipient:contact.email,sender:convo.sender,reply_to:convo.reply_to,verified_at:now,outreach_basis:contact.outreach_basis,created_at:now}));
  const material={id:id(40),title:'Nordic language support',content:'## Working together\nSupport for your Nordic localization work.\nA proposed discussion of requirements and the first project.\n\n## Next step\nDiscuss the brief with Eli Stoyanova.\neli.s@retodo-ops.com',version:1,updated_at:now};
  const data={settings:{email_signature:{...defaults},signature_enabled:true,sending_enabled:false,research_enabled:false,monthly_cap:30,reserve_eur:5,recurring_eur:5,daily_limit:10,approved_facts:'Test facts only.',target_brief:'LSPs with Nordic vendor requirements.',research_interval_days:7},runtime:{mailbox_ok:false},counts:{prospects:1,review:3,queued:0,sent:0,replies:0,attention:0},prospect_count:1,prospects:[prospect],conversations:[convo],review:messages,materials:[material],tasks:[],attention:[],jobs:[],events:[],budget:{charged:.12,reserved:0}};
  await page.exposeFunction('fixtureRpc',async(name,args)=>{
   if(name==='current_app_role')return {data:role};if(name==='current_user_access_enabled')return {data:true};if(name==='tms_search_062')return {data:[]};
   if(name==='sales_workspace_063'){lastQuery=args.p_query;return {data:structuredClone({...data,prospects:args.p_query==='empty'?[]:data.prospects,prospect_count:args.p_query==='empty'?0:1})};}
   if(name==='sales_detail_063')return {data:structuredClone({prospect,contacts:[contact],conversations:[convo],messages,client_matches:[]})};
   if(name==='sales_command_063'){
    lastCommand=structuredClone(args);
    if(args.p_action==='approve'&&failedApproval)return {error:{message:'A selected draft changed. Refresh and review the whole batch'}};
    if(args.p_action==='approve'){data.review=data.review.filter(m=>!args.p_data.messages.some(x=>x.id===m.id));data.counts.review=data.review.length;data.counts.queued=args.p_data.messages.length;}
    if(args.p_action==='settings')Object.assign(data.settings,args.p_data);
    if(args.p_action==='message'){const m=messages.find(m=>m.id===args.p_data.id);Object.assign(m,{body:args.p_data.body,subject:args.p_data.subject,signature:args.p_data.signature_mode==='current'?structuredClone(data.settings.email_signature):args.p_data.signature_mode==='none'?{}:m.signature,state:'draft',approval_id:null,version:m.version+1});}
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
  const initialPreview=page.locator('[data-body-field="initial"]');await initialPreview.locator('summary').click();
  assert.match(await initialPreview.innerText(),/A complete initial message/);assert.match(await initialPreview.innerText(),/Best Regards,/);assert.equal(await initialPreview.locator('img').getAttribute('width'),'48');
  await page.locator('[name="include_followup_two_signature"]').uncheck();assert.equal(await page.locator('[data-body-field="followup_two"] img').count(),0);
  await page.locator('#salesDialog').screenshot({path:path.join(OUTPUT,'sales-signature-compose.png')});
  await page.locator('[name="files"]').setInputFiles({name:'Capabilities.txt',mimeType:'text/plain',buffer:Buffer.from('Approved facts')});
  await page.getByRole('button',{name:'Save for batch review',exact:true}).click();await page.locator('#salesSelectAll').waitFor();
  assert.equal(lastCommand.p_action,'sequence');assert.equal(lastCommand.p_data.messages.length,3);assert.equal(lastCommand.p_data.messages[0].attachments[0].name,'Capabilities.txt');assert.equal(lastCommand.p_data.messages[1].delay_days,5);assert.equal(lastCommand.p_data.messages[0].include_signature,true);assert.equal(lastCommand.p_data.messages[1].include_signature,true);assert.equal(lastCommand.p_data.messages[2].include_signature,false);
  await page.locator('[data-select]').nth(0).check();await page.locator('[data-select]').nth(1).check();await page.getByRole('button',{name:'Review selected batch'}).click();
  await page.getByRole('heading',{name:'Review 2 messages'}).waitFor();assert.equal(await page.locator('#salesDialog .sales-pre').count(),2);assert.equal(await page.locator('#salesDialog .sales-email-preview img').count(),2);assert.equal(await page.locator('#salesDialog a[href="'+defaults.linkedin_url+'"]').count(),2);await page.locator('#salesDialog').screenshot({path:path.join(OUTPUT,'sales-signature-review.png')});assert.match(await page.locator('#salesDialog').innerText(),/eli.s@retodo-ops.com/);
  failedApproval=true;await page.locator('[name="confirmed"]').check();await page.getByRole('button',{name:'Approve 2 messages'}).click();await page.getByText('A selected draft changed. Refresh and review the whole batch',{exact:true}).waitFor();
  assert.deepEqual(lastCommand.p_data.messages,[{id:messages[0].id,version:1},{id:messages[1].id,version:1}]);assert.equal(lastCommand.p_data.signature_preview_version,2);
  failedApproval=false;await page.getByRole('button',{name:'Approve 2 messages'}).click();await page.waitForFunction(()=>!document.getElementById('salesDialog').open);assert.equal(data.review.length,1);
  await page.screenshot({path:path.join(OUTPUT,'sales-review.png'),fullPage:true});
  await page.locator('[data-tab="conversations"]').click();await page.getByRole('button',{name:'Open',exact:true}).click();await page.getByRole('heading',{name:'Conversation · '+prospect.name}).waitFor();assert.match(await page.locator('#salesDialog').innerText(),/Eli Stoyanova/);await page.locator('[data-action="close-dialog"]').click();
  await page.locator('[data-tab="materials"]').click();await page.getByRole('button',{name:'Edit & preview'}).click();await page.getByRole('button',{name:'Preview slides'}).click();assert.equal(await page.locator('.sales-material-preview').count(),2);await page.locator('[data-action="close-dialog"]').click();
  const downloaded=page.waitForEvent('download');await page.getByRole('button',{name:'PowerPoint',exact:true}).click();const file=await downloaded.catch(async e=>{console.error('Export status:',await page.locator('#salesNotice').innerText());throw e;});await file.saveAs(path.join(OUTPUT,file.suggestedFilename()));assert.ok(file.suggestedFilename().endsWith('.pptx'));
  await page.locator('[data-tab="settings"]').click();await page.locator('[name="daily_limit"]').fill('7');await page.getByRole('button',{name:'Check mailbox connection'}).click();await page.getByText('Mailbox check passed: ops@retodo-ops.com. Sales sender: eli.s@retodo-ops.com.',{exact:true}).waitFor();assert.equal(await page.locator('[name="daily_limit"]').inputValue(),'7');await page.getByRole('button',{name:'Save Sales settings'}).click();await page.getByText('Sales settings saved.',{exact:true}).waitFor();assert.equal(lastCommand.p_data.daily_limit,'7');assert.equal(lastCommand.p_data.sending_enabled,false);
  assert.equal(await page.locator('[name="signature_position"]').inputValue(),defaults.position);assert.equal(await page.locator('[name="signature_enabled"]').isChecked(),true);
  await page.locator('#salesSignatureSettings').screenshot({path:path.join(OUTPUT,'sales-signature-settings.png')});
  await page.locator('[name="signature_position"]').fill('<img src=x onerror=alert(1)> & Sales');assert.match(await page.locator('#salesSignaturePreview').innerText(),/<img src=x onerror=alert\(1\)> & Sales/);assert.equal(await page.locator('#salesSignaturePreview img').count(),1);
  await page.locator('[name="signature_linkedin"]').fill('https://linkedin.com.evil.invalid/in/eli/');assert.match(await page.locator('#salesSignatureError').innerText(),/LinkedIn/);assert.equal(await page.locator('#salesSignaturePreview a').count(),0);
  await page.locator('[name="signature_linkedin"]').fill(defaults.linkedin_url);await page.locator('[name="signature_position"]').fill('Client Partnerships');
  await page.getByRole('button',{name:'Refresh connection status'}).click();assert.equal(await page.locator('[name="signature_position"]').inputValue(),'Client Partnerships');
  await page.getByRole('button',{name:'Save signature',exact:true}).click();await page.getByText('Sales settings saved.',{exact:true}).waitFor();assert.equal(lastCommand.p_data.email_signature.position,'Client Partnerships');assert.equal(lastCommand.p_data.signature_enabled,true);
  await page.locator('[data-tab="conversations"]').click();await page.getByRole('button',{name:'Open',exact:true}).click();assert.match(await page.locator('#salesDialog').innerText(),new RegExp(defaults.position));assert.doesNotMatch(await page.locator('#salesDialog').innerText(),/Client Partnerships/);
  await page.locator('[data-action="close-dialog"]').click();await page.locator('[data-tab="review"]').click();await page.getByRole('button',{name:'Edit draft',exact:true}).click();
  assert.equal(await page.locator('[name="signature_mode"]').inputValue(),'keep');assert.equal(await page.locator('[data-message-preview] img').count(),0);
  await page.locator('[name="signature_mode"]').selectOption('current');await page.locator('[data-message-preview] summary').click();assert.match(await page.locator('[data-message-preview]').innerText(),/Client Partnerships/);await page.getByRole('button',{name:'Save draft',exact:true}).click();await page.waitForFunction(()=>!document.getElementById('salesDialog').open);assert.equal(lastCommand.p_data.signature_mode,'current');assert.equal(messages[2].signature.position,'Client Partnerships');
  await page.getByRole('button',{name:'Edit draft',exact:true}).click();await page.locator('[name="signature_mode"]').selectOption('none');assert.equal(await page.locator('[data-message-preview] img').count(),0);await page.getByRole('button',{name:'Save draft',exact:true}).click();await page.waitForFunction(()=>!document.getElementById('salesDialog').open);assert.deepEqual(messages[2].signature,{});
  convo.thread_id='signature-thread';convo.state='replied';await page.locator('[data-tab="conversations"]').click();await page.getByRole('button',{name:'Open',exact:true}).click();await page.getByRole('button',{name:'Draft reply',exact:true}).click();await page.locator('[name="body"]').fill('A reply with a reviewed signature.');assert.equal(await page.locator('[name="include_signature"]').isChecked(),true);await page.getByRole('button',{name:'Save for batch review',exact:true}).click();await page.waitForFunction(()=>!document.getElementById('salesDialog').open);assert.equal(lastCommand.p_action,'reply');assert.equal(lastCommand.p_data.include_signature,true);
  await page.setViewportSize({width:390,height:844});await page.locator('[data-tab="settings"]').click();await page.getByRole('button',{name:'Save signature',exact:true}).scrollIntoViewIfNeeded();await page.screenshot({path:path.join(OUTPUT,'sales-signature-mobile.png')});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.setViewportSize({width:1440,height:1050});

  await page.locator('[data-tab="prospects"]').click();await page.locator('#salesSearch').fill('empty');await page.getByRole('button',{name:'Search',exact:true}).click();await page.getByText('Your prospect pipeline starts here',{exact:true}).waitFor();assert.equal(lastQuery,'empty');
  data.prospects=[{...prospect,name:'<img src=x onerror=alert(1)>',source_url:'javascript:alert(1)'}];await page.getByRole('button',{name:'Clear',exact:true}).click();await page.getByText('<img src=x onerror=alert(1)>',{exact:true}).waitFor();assert.equal(await page.locator('#salesView img').count(),0);assert.equal(await page.locator('a[href^="javascript:"]').count(),0);
  data.prospects=[prospect];await page.setViewportSize({width:390,height:844});await page.locator('[data-tab="today"]').click();await page.screenshot({path:path.join(OUTPUT,'sales-mobile.png'),fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  role='qa';await page.goto(base+'sales.html');await page.getByText('Sales is available to administrators during the pilot.',{exact:true}).waitFor();assert.equal(await page.locator('.sidebar a[href="sales.html"]').count(),0);
  assert.deepEqual(errors,[]);console.log('PASS browser: navigation, sequence and attachment payloads, exact batch approval, stale-review error, conversations, materials/PPTX export, signature snapshots/preview/edit choices/reply controls/settings validation, search, XSS, mobile and QA access');
 }finally{if(browser)await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
