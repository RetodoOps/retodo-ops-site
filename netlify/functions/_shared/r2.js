'use strict';

const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  CopyObjectCommand,
  DeleteObjectsCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const {Upload} = require('@aws-sdk/lib-storage');
const {getSignedUrl} = require('@aws-sdk/s3-request-presigner');

const DEFAULT_LINK_TTL_SECONDS = 30 * 60;
const MAX_LINK_TTL_SECONDS = 7 * 24 * 60 * 60;
const DEFAULT_ZIP_MAX_BYTES = 512 * 1024 * 1024;

function integerSetting(name, fallback, minimum, maximum) {
  const value = Number(process.env[name]);
  if (!Number.isInteger(value)) return fallback;
  return Math.min(maximum, Math.max(minimum, value));
}

function cleanFilename(value) {
  return String(value || 'file')
    .replace(/[\r\n]/g, ' ')
    .replace(/[\\/\0]/g, '_')
    .trim()
    .slice(0, 255) || 'file';
}

function contentDisposition(filename, download) {
  const safe = cleanFilename(filename).replace(/["\\]/g, '_');
  const encoded = encodeURIComponent(cleanFilename(filename))
    .replace(/['()]/g, character => `%${character.charCodeAt(0).toString(16).toUpperCase()}`)
    .replace(/\*/g, '%2A');
  return `${download ? 'attachment' : 'inline'}; filename="${safe}"; filename*=UTF-8''${encoded}`;
}

function encodeCopySource(bucket, key) {
  return `/${encodeURIComponent(bucket)}/${String(key).split('/').map(encodeURIComponent).join('/')}`;
}

function r2Config() {
  const endpoint = String(process.env.R2_ENDPOINT || '').replace(/\/$/, '');
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  const bucket = process.env.R2_BUCKET_NAME;
  if (!endpoint || !accessKeyId || !secretAccessKey || !bucket) {
    throw new Error('R2 file storage is not configured. Contact the Administrator.');
  }
  let parsed;
  try { parsed = new URL(endpoint); } catch { throw new Error('R2 endpoint configuration is invalid.'); }
  if (parsed.protocol !== 'https:' || parsed.pathname !== '/' || parsed.search || parsed.hash) {
    throw new Error('R2 endpoint configuration is invalid.');
  }
  if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/i.test(bucket)) {
    throw new Error('R2 bucket configuration is invalid.');
  }
  return {
    endpoint,
    bucket,
    accessKeyId,
    secretAccessKey,
    linkTtlSeconds: integerSetting('R2_SIGNED_URL_TTL_SECONDS', DEFAULT_LINK_TTL_SECONDS, 60, MAX_LINK_TTL_SECONDS),
    uploadTtlSeconds: integerSetting('R2_UPLOAD_URL_TTL_SECONDS', DEFAULT_LINK_TTL_SECONDS, 60, MAX_LINK_TTL_SECONDS),
    zipMaxBytes: integerSetting('R2_ARCHIVE_ZIP_MAX_BYTES', DEFAULT_ZIP_MAX_BYTES, 16 * 1024 * 1024, 4 * 1024 * 1024 * 1024),
  };
}

let cachedClient;
let cachedKey;
function r2Client(config = r2Config()) {
  const key = `${config.endpoint}|${config.accessKeyId}`;
  if (!cachedClient || cachedKey !== key) {
    cachedClient = new S3Client({
      region: 'auto',
      endpoint: config.endpoint,
      forcePathStyle: true,
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
      credentials: {
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
      },
    });
    cachedKey = key;
  }
  return cachedClient;
}

async function signedUpload(ticket, config = r2Config(), client = r2Client(config)) {
  const metadata = {
    sha256: String(ticket.checksum_sha256 || '').toLowerCase(),
    fileid: String(ticket.file_id),
  };
  const command = new PutObjectCommand({
    Bucket: config.bucket,
    Key: ticket.object_key,
    ContentType: ticket.mime_type || 'application/octet-stream',
    Metadata: metadata,
    StorageClass: 'STANDARD',
  });
  const url = await getSignedUrl(client, command, {
    expiresIn: config.uploadTtlSeconds,
    unhoistableHeaders: new Set(['x-amz-meta-sha256', 'x-amz-meta-fileid']),
  });
  return {
    url,
    expires_in: config.uploadTtlSeconds,
    headers: {
      'Content-Type': ticket.mime_type || 'application/octet-stream',
      'x-amz-meta-sha256': metadata.sha256,
      'x-amz-meta-fileid': metadata.fileid,
    },
  };
}

async function signedDownload(ticket, action, config = r2Config(), client = r2Client(config)) {
  const command = new GetObjectCommand({
    Bucket: config.bucket,
    Key: ticket.object_key,
    ResponseContentType: ticket.mime_type || 'application/octet-stream',
    ResponseContentDisposition: contentDisposition(ticket.original_filename, action === 'Download'),
  });
  return {
    url: await getSignedUrl(client, command, {expiresIn: config.linkTtlSeconds}),
    expires_in: config.linkTtlSeconds,
  };
}

async function headObject(key, config = r2Config(), client = r2Client(config)) {
  const result = await client.send(new HeadObjectCommand({Bucket: config.bucket, Key: key}));
  return {
    size: Number(result.ContentLength || 0),
    etag: String(result.ETag || '').replace(/^"|"$/g, '') || null,
    versionId: result.VersionId || null,
    checksum: String(result.Metadata?.sha256 || '').toLowerCase() || null,
    fileId: result.Metadata?.fileid || null,
    storageClass: result.StorageClass || 'STANDARD',
    metadata: result.Metadata || {},
  };
}

async function getObject(key, config = r2Config(), client = r2Client(config)) {
  return client.send(new GetObjectCommand({Bucket: config.bucket, Key: key}));
}

async function copyStorageClass(key, storageClass, config = r2Config(), client = r2Client(config)) {
  await client.send(new CopyObjectCommand({
    Bucket: config.bucket,
    Key: key,
    CopySource: encodeCopySource(config.bucket, key),
    MetadataDirective: 'COPY',
    StorageClass: storageClass,
  }));
  return headObject(key, config, client);
}

async function uploadStream({key, body, contentType, metadata, storageClass = 'STANDARD'}, config = r2Config(), client = r2Client(config)) {
  const upload = new Upload({
    client,
    leavePartsOnError: false,
    params: {
      Bucket: config.bucket,
      Key: key,
      Body: body,
      ContentType: contentType || 'application/octet-stream',
      Metadata: metadata || {},
      StorageClass: storageClass,
    },
  });
  return upload.done();
}

async function deleteKeys(keys, config = r2Config(), client = r2Client(config)) {
  const unique = [...new Set((keys || []).filter(Boolean))];
  for (let index = 0; index < unique.length; index += 1000) {
    const batch = unique.slice(index, index + 1000);
    const result = await client.send(new DeleteObjectsCommand({
      Bucket: config.bucket,
      Delete: {Objects: batch.map(Key => ({Key})), Quiet: true},
    }));
    if (result.Errors?.length) throw new Error(`R2 rejected ${result.Errors.length} object deletion(s).`);
  }
}

async function deleteKey(key, config = r2Config(), client = r2Client(config)) {
  if (!key) return;
  await client.send(new DeleteObjectCommand({Bucket: config.bucket, Key: key}));
}

module.exports = {
  DEFAULT_LINK_TTL_SECONDS,
  MAX_LINK_TTL_SECONDS,
  cleanFilename,
  contentDisposition,
  encodeCopySource,
  r2Config,
  r2Client,
  signedUpload,
  signedDownload,
  headObject,
  getObject,
  copyStorageClass,
  uploadStream,
  deleteKeys,
  deleteKey,
};
