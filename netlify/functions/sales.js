'use strict';
const {request,verifyUser,requireSameOrigin,jsonResponse,publicError}=require('./_shared/supabase');
const worker=require('./_shared/sales-worker');
const ai=require('./_shared/sales-ai');
const {diagnostic}=require('./_shared/sales-diagnostics');

exports.handler=async event=>{
  try {
    if(event.httpMethod!=='POST') return jsonResponse(405,{error:'Use POST'});
    const {headers}=requireSameOrigin(event);
    const bearer=headers.authorization;
    const user=await verifyUser(bearer);
    const admin=await request('/rest/v1/rpc/sales_is_admin_063',{method:'POST',bearer,body:{}});
    if(admin!==true) return jsonResponse(403,{error:'Sales administrator access required'});
    if(typeof event.body!=='string' || Buffer.byteLength(event.body)>30000) return jsonResponse(400,{error:'Invalid request size'});
    let input; try {input=JSON.parse(event.body);} catch {return jsonResponse(400,{error:'Invalid JSON'});}
    if(input.action==='status') {
      let estimate=null,aiHold=null;
      try {estimate={research:ai.estimate('research'),writing:ai.estimate('draft')};} catch(e) {aiHold=e.message;}
      return jsonResponse(200,{ai_ready:!!estimate,ai_hold:aiHold,estimate,worker_ready:(process.env.SALES_WORKER_SECRET||'').length>=32});
    }
    if(input.action==='check_mailbox') {
      const info=await worker.checkMailbox();
      return jsonResponse(200,{account:info.account,alias:info.alias,reply_to:info.reply_to});
    }
    if(input.action==='run') {await worker.invokeWorker();return jsonResponse(202,{queued:true});}
    if(input.action==='ai') {
      if(!/^[a-f0-9-]{36}$/.test(input.id||'') || !['research','draft','materials'].includes(input.kind)) return jsonResponse(400,{error:'Invalid AI request'});
      const settings=await worker.rpc('config');
      const payload={brief:input.brief};
      if(input.prospect_id) {
        // Resolve context through the same authenticated, role-protected read path as the page.
        const detail=await request('/rest/v1/rpc/sales_detail_063',{method:'POST',bearer,body:{p_id:input.prospect_id}});
        const p=detail.prospect;
        payload.prospect={id:p.id,name:p.name,domain:p.domain,sector:p.sector,fit_note:p.fit_note,source_url:p.source_url};
        if(input.contact_id) {
          const k=detail.contacts.find(c=>c.id===input.contact_id);
          if(!k) return jsonResponse(400,{error:'Contact does not belong to this prospect'});
          payload.contact={id:k.id,name:k.name,role_title:k.role_title};
        }
      }
      const cost=ai.pricing();
      const job=await worker.rpc('reserve_ai',{id:input.id,kind:input.kind,payload:ai.prepare(input.kind,payload,settings),reserved_eur:ai.estimate(input.kind,cost),cost_config:cost,created_by:user.id});
      let wake_error=null;try{await worker.invokeWorker();}catch(e){wake_error=e.message;}
      return jsonResponse(202,{id:job.id,state:job.state,wake_error});
    }
    return jsonResponse(400,{error:'Unknown Sales request'});
  } catch(error) {
    // Render only reviewed, static connection messages; never return Google's
    // raw error descriptions or weaken the shared operational error redactor.
    const detail=diagnostic(error.salesConnectionCode);
    return jsonResponse(error.status || 400,detail || {error:publicError(error,'The Sales request could not be completed. Check configuration and try again')});
  }
};
