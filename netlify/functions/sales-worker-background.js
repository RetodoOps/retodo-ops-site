'use strict';
const {normalizedHeaders}=require('./_shared/supabase');
const {validWorkerKey,runWorker}=require('./_shared/sales-worker');
exports.handler=async event=>{
  if(event.httpMethod!=='POST' || !validWorkerKey(normalizedHeaders(event)['x-retodo-sales-key'])) return {statusCode:403};
  try { const result=await runWorker(); console.log('Sales worker completed',result); return {statusCode:200}; }
  catch { console.error('Sales worker failed; inspect Sales status in the TMS'); return {statusCode:500}; }
};
