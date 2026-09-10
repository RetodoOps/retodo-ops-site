'use strict';

const {serviceRpc} = require('./_shared/supabase');

async function invokeWorker() {
  const secret = process.env.FILE_LIFECYCLE_WORKER_SECRET;
  const site = process.env.TMS_SITE_URL || 'https://tms.retodo-ops.com';
  if (!secret) throw new Error('FILE_LIFECYCLE_WORKER_SECRET is not configured');
  const url = new URL('/.netlify/functions/file-lifecycle-worker-background', site);
  if (url.protocol !== 'https:') throw new Error('TMS_SITE_URL must use HTTPS');
  const response = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'X-Retodo-Worker-Key': secret},
    body: JSON.stringify({action: 'run'}),
    signal: AbortSignal.timeout(10000),
  });
  if (response.status !== 202 && !response.ok) throw new Error(`Lifecycle worker returned HTTP ${response.status}`);
}

exports.handler = async () => {
  try {
    const queued = await serviceRpc('system_enqueue_due_file_lifecycle_044');
    await invokeWorker();
    console.log('Retodo file lifecycle scheduled', {queued});
    return {statusCode: 200};
  } catch (error) {
    console.error('Retodo file lifecycle schedule failed', {message: String(error?.message || error).slice(0, 300)});
    return {statusCode: 500};
  }
};

exports.__test = {invokeWorker};
