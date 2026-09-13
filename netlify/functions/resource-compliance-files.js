'use strict';

const {
  r2Config,
  r2Client,
  signedUpload,
  signedDownload,
  headObject,
  deleteKey,
} = require('./_shared/r2');
const {
  verifyUser,
  serviceRpc,
  requireSameOrigin,
  jsonResponse,
  publicError,
} = require('./_shared/supabase');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/i;
const MAX_SINGLE_UPLOAD_BYTES = 5 * 1024 ** 3 - 5 * 1024 ** 2;
const EVIDENCE_TYPES = new Set(['Diploma / certificate', 'CV']);

function parseBody(event) {
  if (Buffer.byteLength(event.body || '', 'utf8') > 64 * 1024) {
    throw Object.assign(new Error('Request is too large.'), {status: 413});
  }
  let body;
  try { body = JSON.parse(event.body || '{}'); } catch {
    throw Object.assign(new Error('Invalid request.'), {status: 400});
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw Object.assign(new Error('Invalid request.'), {status: 400});
  }
  return body;
}

function requireUuid(value, label) {
  if (!UUID.test(String(value || ''))) {
    throw Object.assign(new Error(`${label} is required.`), {status: 400});
  }
  return value;
}

function optionalUuid(value, label) {
  if (value === null || value === undefined || value === '') return null;
  return requireUuid(value, label);
}

async function dispatch(action, actorId, {
  fileId = null,
  resourceId = null,
  payload = {},
} = {}) {
  return serviceRpc('resource_compliance_file_dispatch_047', {
    p_action: action,
    p_actor_id: actorId,
    p_file_id: fileId,
    p_resource_id: resourceId,
    p_payload: payload,
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
  if (!['prepare_upload', 'complete_upload', 'discard_upload', 'review_evidence', 'download'].includes(body.action)) {
    return jsonResponse(400, {error: 'Unknown Compliance file action.'});
  }

  try {
    const user = await verifyUser(headers.authorization || '');
    const config = r2Config();
    const client = r2Client(config);

    if (body.action === 'prepare_upload') {
      const resourceId = requireUuid(body.resource_id, 'Resource ID');
      const evidenceType = String(body.evidence_type || '');
      const educationId = optionalUuid(body.education_id, 'Education ID');
      const size = Number(body.size_bytes);
      const checksum = String(body.checksum_sha256 || '').toLowerCase();
      if (!EVIDENCE_TYPES.has(evidenceType)) {
        throw Object.assign(new Error('Unsupported Compliance evidence type.'), {status: 400});
      }
      if (evidenceType === 'Diploma / certificate' && !educationId) {
        throw Object.assign(new Error('Education ID is required for diploma evidence.'), {status: 400});
      }
      if (!Number.isSafeInteger(size) || size < 0 || size > MAX_SINGLE_UPLOAD_BYTES) {
        throw Object.assign(new Error('The file exceeds the 4.995 GiB single-upload limit.'), {status: 400});
      }
      if (!SHA256.test(checksum)) {
        throw Object.assign(new Error('A valid SHA-256 checksum is required.'), {status: 400});
      }

      const ticket = await dispatch('prepare_upload', user.id, {
        resourceId,
        payload: {
          original_filename: String(body.original_filename || '').slice(0, 255),
          mime_type: String(body.mime_type || 'application/octet-stream').slice(0, 255),
          size_bytes: size,
          evidence_type: evidenceType,
          education_id: educationId,
          checksum_sha256: checksum,
          bucket_name: config.bucket,
        },
      });
      try {
        const signed = await signedUpload(ticket, config, client);
        return jsonResponse(200, {
          file_id: ticket.file_id,
          document_id: ticket.document_id,
          upload_url: signed.url,
          upload_headers: signed.headers,
          expires_in: signed.expires_in,
        });
      } catch (error) {
        await dispatch('fail_upload', user.id, {
          fileId: ticket.file_id,
          payload: {reason: 'R2 Compliance upload URL could not be created'},
        }).catch(() => {});
        throw error;
      }
    }

    if (body.action === 'complete_upload') {
      const fileId = requireUuid(body.file_id, 'File ID');
      const ticket = await dispatch('inspect_upload', user.id, {fileId});
      const stored = await headObject(ticket.object_key, config, client);
      if (stored.size !== Number(ticket.size_bytes)
          || stored.checksum !== String(ticket.checksum_sha256 || '').toLowerCase()
          || stored.fileId !== String(ticket.file_id)) {
        throw Object.assign(
          new Error('The uploaded object did not pass size and checksum verification.'),
          {status: 409},
        );
      }
      await dispatch('publish_upload', user.id, {
        fileId,
        payload: {
          verified_size_bytes: stored.size,
          verified_checksum_sha256: stored.checksum,
          r2_etag: stored.etag,
          r2_version_id: stored.versionId,
          storage_class: stored.storageClass,
        },
      });
      return jsonResponse(200, {file_id: fileId, status: 'Ready'});
    }

    if (body.action === 'discard_upload') {
      const fileId = requireUuid(body.file_id, 'File ID');
      const ticket = await dispatch('inspect_upload', user.id, {fileId});
      await deleteKey(ticket.object_key, config, client).catch(error => {
        if (error?.$metadata?.httpStatusCode !== 404 && error?.name !== 'NoSuchKey') throw error;
      });
      await dispatch('discard_upload', user.id, {fileId});
      return jsonResponse(200, {file_id: fileId, status: 'Failed'});
    }

    if (body.action === 'review_evidence') {
      const fileId = requireUuid(body.file_id, 'File ID');
      await dispatch('review_evidence', user.id, {fileId});
      return jsonResponse(200, {file_id: fileId, status: 'Valid'});
    }

    const fileId = requireUuid(body.file_id, 'File ID');
    const fileAction = body.file_action === 'Download' ? 'Download' : 'View';
    const ticket = await dispatch('authorize_download', user.id, {
      fileId,
      payload: {file_action: fileAction},
    });
    if (ticket.storage_provider !== 'Cloudflare R2' || ticket.bucket_name !== config.bucket) {
      throw Object.assign(new Error('This file uses a legacy storage provider.'), {status: 409});
    }
    const signed = await signedDownload(ticket, fileAction, config, client);
    return jsonResponse(200, {
      file_id: fileId,
      download_url: signed.url,
      expires_in: signed.expires_in,
      filename: ticket.original_filename,
    });
  } catch (error) {
    const status = [400, 401, 403, 404, 409, 413].includes(error?.status)
      ? error.status
      : 400;
    return jsonResponse(status, {
      error: publicError(error, 'The Compliance file request could not be completed.'),
    });
  }
};

exports.__test = {
  parseBody,
  requireUuid,
  optionalUuid,
  dispatch,
  MAX_SINGLE_UPLOAD_BYTES,
  EVIDENCE_TYPES,
};
