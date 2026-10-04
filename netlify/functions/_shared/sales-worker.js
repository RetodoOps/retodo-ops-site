'use strict';
const {randomUUID,timingSafeEqual}=require('node:crypto');
const {serviceRpc}=require('./supabase');
const gmail=require('./sales-gmail');
const ai=require('./sales-ai');
const rpc=(action,data={})=>serviceRpc('sales_system_063',{p_action:action,p_data:data});

function validWorkerKey(value) {
  const expected=process.env.SALES_WORKER_SECRET || '';
  if (expected.length<32 || typeof value!=='string') return false;
  const a=Buffer.from(expected),b=Buffer.from(value);
  return a.length===b.length && timingSafeEqual(a,b);
}

async function invokeWorker() {
  if ((process.env.SALES_WORKER_SECRET || '').length<32) throw new Error('Sales background processing is not configured');
  const url=new URL('/.netlify/functions/sales-worker-background',process.env.TMS_SITE_URL || 'https://tms.retodo-ops.com');
  if (url.protocol!=='https:') throw new Error('The Sales site URL must use HTTPS');
  const res=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','X-Retodo-Sales-Key':process.env.SALES_WORKER_SECRET},body:'{}',signal:AbortSignal.timeout(10000)});
  if (res.status!==202 && !res.ok) throw new Error('Sales worker could not be started. The saved queue will be picked up by its next scheduled run');
}

async function checkMailbox() {
  try {
    const token=await gmail.accessToken();
    const info=await gmail.verifyMailbox(token);
    await rpc('mailbox',{ok:true});
    return {token,...info};
  } catch(error) {
    await rpc('mailbox',{ok:false,error:error.message});
    throw error;
  }
}

async function syncThread(mailbox,conversation) {
  try {
    const data=await gmail.readThread(mailbox.token,conversation,mailbox.account);
    await rpc('sync',{conversation_id:conversation.id,messages:data.messages});
    return data.reference;
  } catch(error) {
    await rpc('sync',{conversation_id:conversation.id,error:error.message});
    throw error;
  }
}

async function runWorker() {
  const lock=await rpc('lock');
  if (!lock) return {busy:true};
  const deadline=Date.now()+150000;
  const summary={sent:0,reconciled:0,synced:0,ai:0};
  let failure;
  try {
    const settings=await rpc('config');
    // Read-only research may run while sending remains switched off.
    if (settings.research_enabled && (!settings.next_research_at || new Date(settings.next_research_at)<=new Date())) {
      try {
        const cost=ai.pricing();
        await rpc('reserve_ai',{id:randomUUID(),kind:'research',payload:ai.prepare('research',{},settings),reserved_eur:ai.estimate('research',cost),cost_config:cost,scheduled:true});
      } catch(error) { summary.research_hold=error.message; }
    }
    const job=await rpc('claim_ai');
    if (job) {
      const result=await ai.run(job);
      // A settlement failure leaves the reservation intact and is never retried as a new request.
      await rpc('finish_ai',{id:job.id,...result});
      summary.ai++;
    }
    // Do not require a configured Google account for manual or research-only use.
    if (!process.env.GOOGLE_REFRESH_TOKEN) return summary;
    const mailbox=await checkMailbox();
    for (const message of await rpc('uncertain')) {
      if (Date.now()>deadline-40000) break;
      const found=await gmail.findSent(mailbox.token,message,message.recipient);
      if (found) { await rpc('finish_send',{id:message.id,lease_id:message.lease_id,...found}); summary.reconciled++; }
    }
    const threads=await rpc('threads');
    for (const thread of threads.slice(0,5)) {
      if (Date.now()>deadline-60000) break;
      try { await syncThread(mailbox,thread); summary.synced++; } catch { /* Recorded in the conversation; sending stays blocked. */ }
    }
    for(let i=0;i<3 && Date.now()<deadline-60000;i++) {
      const claimed=await rpc('claim');
      if (!claimed) break;
      const {message,conversation}=claimed;
      try {
        let reference=null;
        // Every threaded send gets a fresh check, even if the scheduled inbox pass skipped it.
        if (conversation.thread_id) reference=await syncThread(mailbox,conversation);
        const raw=gmail.buildMime(message,conversation,reference);
        const ready=await rpc('begin_send',{id:message.id,lease_id:message.lease_id});
        if (!ready) continue; // A reply, suppression or pause invalidated this claim.
        const sent=await gmail.send(mailbox.token,raw,conversation.thread_id);
        await rpc('finish_send',{id:message.id,lease_id:message.lease_id,...sent});
        summary.sent++;
      } catch(error) {
        await rpc('send_error',{id:message.id,lease_id:message.lease_id,error:error.message});
        // Once POST began, even an error response is ambiguous. Reconciliation alone can confirm it.
      }
    }
    return summary;
  } catch(error) { failure=error; throw error; }
  finally { await rpc('unlock',{lease_id:lock.lease_id,error:failure?.message || summary.research_hold || null}); }
}

module.exports={rpc,validWorkerKey,invokeWorker,checkMailbox,runWorker};
