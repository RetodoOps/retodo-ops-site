'use strict';

const {
  verifyUser,
  serviceRpc,
  requireSameOrigin,
  jsonResponse,
  publicError,
} = require('./_shared/supabase');
const {sendComplianceNotification} = require('./_shared/gmail');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACTIONS = new Set(['request', 'resend', 'request_changes', 'complete']);

function parseBody(event) {
  if (Buffer.byteLength(event.body || '', 'utf8') > 16 * 1024) {
    throw Object.assign(new Error('Request is too large.'), {status: 413});
  }
  let body;
  try { body = JSON.parse(event.body || '{}'); } catch {
    throw Object.assign(new Error('Invalid request.'), {status: 400});
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw Object.assign(new Error('Invalid request.'), {status: 400});
  }
  if (!ACTIONS.has(body.action)) {
    throw Object.assign(new Error('Unknown Compliance action.'), {status: 400});
  }
  if (!UUID.test(String(body.resource_id || ''))) {
    throw Object.assign(new Error('Resource ID is required.'), {status: 400});
  }
  const reason = String(body.reason || '').trim();
  if (reason.length > 2000) {
    throw Object.assign(new Error('The change request is too long.'), {status: 400});
  }
  return {...body, reason};
}

async function dispatch(action, actorId, resourceId, reason = null) {
  return serviceRpc('resource_compliance_workflow_dispatch_048', {
    p_action: action,
    p_actor_id: actorId,
    p_resource_id: resourceId,
    p_reason: reason,
  });
}

exports.handler = async event => {
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, {error: 'POST required.'});
  }

  let headers;
  try { ({headers} = requireSameOrigin(event)); } catch (error) {
    return jsonResponse(error.status || 403, {error: publicError(error)});
  }

  let body;
  try { body = parseBody(event); } catch (error) {
    return jsonResponse(error.status || 400, {error: publicError(error)});
  }

  try {
    const user = await verifyUser(headers.authorization || '');
    const ticket = await dispatch(body.action, user.id, body.resource_id, body.reason || null);
    let notificationSent = false;

    if (ticket.notification_kind) {
      let portalUrl;
      try {
        const configured = process.env.TMS_SITE_URL || 'https://tms.retodo-ops.com';
        const parsed = new URL(configured);
        if (parsed.protocol !== 'https:') throw new Error('HTTPS required');
        portalUrl = new URL('/resource-dashboard.html#myCompliance', parsed.origin).href;
      } catch {
        throw Object.assign(new Error('TMS site URL is invalid.'), {status: 503});
      }
      try {
        await sendComplianceNotification(ticket, portalUrl);
        await dispatch('notification_sent', user.id, body.resource_id);
        notificationSent = true;
      } catch (error) {
        await dispatch(
          'notification_failed', user.id, body.resource_id,
          'Compliance notification delivery failed',
        ).catch(() => {});
        error.workflowStatus = ticket.status;
        throw error;
      }
    }

    return jsonResponse(200, {
      resource_id: ticket.resource_id,
      status: ticket.status,
      notification_sent: notificationSent,
    });
  } catch (error) {
    const status = [400, 401, 403, 404, 409, 413, 503].includes(error?.status)
      ? error.status
      : 400;
    return jsonResponse(status, {
      error: publicError(error, 'The Compliance request could not be completed.'),
      ...(error.workflowStatus ? {workflow_status: error.workflowStatus} : {}),
    });
  }
};

exports.__test = {parseBody, dispatch, ACTIONS};
