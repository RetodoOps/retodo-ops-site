'use strict';
const {invokeWorker}=require('./_shared/sales-worker');
// Netlify scheduled functions cannot be invoked through their public URL.
exports.handler=async()=>{
  if (!process.env.SALES_WORKER_SECRET) return {statusCode:200};
  try { await invokeWorker(); return {statusCode:200}; }
  catch { console.error('Sales scheduler failed; inspect worker configuration'); return {statusCode:500}; }
};
