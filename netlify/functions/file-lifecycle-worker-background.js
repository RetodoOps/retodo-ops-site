'use strict';

const crypto = require('node:crypto');
const {Transform} = require('node:stream');
const unzipper = require('unzipper');
const {
  r2Config,
  r2Client,
  headObject,
  getObject,
  copyStorageClass,
  uploadStream,
  deleteKeys,
  deleteKey,
  cleanFilename,
} = require('./_shared/r2');
const {serviceRpc} = require('./_shared/supabase');

const ALREADY_COMPRESSED_EXTENSIONS = new Set([
  '7z', 'avi', 'bz2', 'docx', 'epub', 'flac', 'gif', 'gz', 'jpeg', 'jpg', 'm4a',
  'mkv', 'mov', 'mp3', 'mp4', 'odp', 'ods', 'odt', 'ogg', 'pdf', 'png', 'pptx',
  'rar', 'svgz', 'tgz', 'webm', 'webp', 'xlsx', 'xz', 'zip',
]);
const ALREADY_COMPRESSED_MIME = /^(audio|image|video)\/|application\/(zip|gzip|pdf|x-7z-compressed|x-rar-compressed|vnd\.openxmlformats)/i;

function timingSafeSecret(provided, expected) {
  if (!provided || !expected) return false;
  const left = Buffer.from(String(provided));
  const right = Buffer.from(String(expected));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function extension(filename) {
  const match = String(filename || '').toLowerCase().match(/\.([a-z0-9]+)$/);
  return match?.[1] || '';
}

function likelyCompressible(file) {
  return !ALREADY_COMPRESSED_EXTENSIONS.has(extension(file.original_filename))
    && !ALREADY_COMPRESSED_MIME.test(String(file.mime_type || ''));
}

function chooseArchiveStrategy(files, zipMaxBytes) {
  const total = files.reduce((sum, file) => sum + Number(file.size_bytes || 0), 0);
  if (!files.length || total < 64 * 1024 || total > zipMaxBytes) return 'infrequent';
  const compressible = files.filter(likelyCompressible)
    .reduce((sum, file) => sum + Number(file.size_bytes || 0), 0);
  const estimatedSaved = compressible * 0.5;
  return estimatedSaved >= Math.max(1024 * 1024, total * 0.10) ? 'zip' : 'infrequent';
}

function manifestFor(task) {
  const files = [...(task.files || [])].sort((a, b) => String(a.file_id).localeCompare(String(b.file_id))).map(file => ({
    file_id: file.file_id,
    entry_path: `files/${file.file_id}/${cleanFilename(file.original_filename)}`,
    object_key: file.object_key,
    original_filename: file.original_filename,
    mime_type: file.mime_type || 'application/octet-stream',
    size_bytes: Number(file.size_bytes || 0),
    checksum_sha256: String(file.checksum_sha256 || '').toLowerCase(),
  }));
  return {
    format: 'retodo-job-archive-v1',
    project_id: task.project_id,
    job_id: task.job_id,
    archive_id: task.archive_id,
    files,
  };
}

function stableJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

async function verifySourceFiles(files, ops) {
  for (const file of files) {
    const observed = await ops.headObject(file.object_key);
    if (observed.size !== Number(file.size_bytes)
        || observed.checksum !== String(file.checksum_sha256 || '').toLowerCase()
        || observed.fileId !== String(file.file_id)) {
      throw new Error('A source object failed size or checksum verification.');
    }
  }
}

async function archiveAsInfrequent(task, manifest, ops) {
  await verifySourceFiles(manifest.files, ops);
  for (const file of manifest.files) {
    const observed = await ops.copyStorageClass(file.object_key, 'STANDARD_IA');
    if (observed.storageClass !== 'STANDARD_IA'
        || observed.size !== file.size_bytes
        || observed.checksum !== file.checksum_sha256) {
      throw new Error('An archived object failed Infrequent Access verification.');
    }
  }
  const manifestText = stableJson(manifest);
  return {
    strategy: 'infrequent',
    manifest,
    manifest_sha256: sha256(manifestText),
    archive_object_key: null,
    archive_checksum_sha256: null,
    original_size_bytes: manifest.files.reduce((sum, file) => sum + file.size_bytes, 0),
    archive_size_bytes: manifest.files.reduce((sum, file) => sum + file.size_bytes, 0),
    file_count: manifest.files.length,
    storage_class: 'STANDARD_IA',
  };
}

async function archiveAsZip(task, manifest, ops) {
  await verifySourceFiles(manifest.files, ops);
  const manifestText = stableJson(manifest);
  const manifestHash = sha256(manifestText);
  const {ZipArchive} = await import('archiver');
  const archive = new ZipArchive({zlib: {level: 9}, forceZip64: true});
  const hash = crypto.createHash('sha256');
  let bytes = 0;
  const hashTap = new Transform({
    transform(chunk, encoding, callback) {
      hash.update(chunk); bytes += chunk.length; callback(null, chunk);
    },
  });
  archive.on('warning', error => { if (error.code !== 'ENOENT') hashTap.destroy(error); });
  archive.on('error', error => hashTap.destroy(error));
  archive.pipe(hashTap);
  const uploadPromise = ops.uploadStream({
    key: task.archive_object_key,
    body: hashTap,
    contentType: 'application/zip',
    metadata: {manifestsha256: manifestHash, archiveid: String(task.archive_id)},
    storageClass: 'STANDARD_IA',
  });
  for (const file of manifest.files) {
    const source = await ops.getObject(file.object_key);
    if (!source.Body) throw new Error('R2 returned an empty source stream.');
    archive.append(source.Body, {name: file.entry_path, date: new Date(0)});
  }
  archive.append(manifestText, {name: 'manifest.json', date: new Date(0)});
  await archive.finalize();
  await uploadPromise;
  const archiveHash = hash.digest('hex');
  const observed = await ops.headObject(task.archive_object_key);
  if (observed.size !== bytes || observed.metadata?.manifestsha256 !== manifestHash) {
    throw new Error('The ZIP archive failed post-upload verification.');
  }
  return {
    strategy: 'zip',
    manifest,
    manifest_sha256: manifestHash,
    archive_object_key: task.archive_object_key,
    archive_checksum_sha256: archiveHash,
    original_size_bytes: manifest.files.reduce((sum, file) => sum + file.size_bytes, 0),
    archive_size_bytes: bytes,
    file_count: manifest.files.length,
    storage_class: 'STANDARD_IA',
  };
}

async function restoreInfrequent(task, manifest, ops) {
  for (const file of manifest.files) {
    const observed = await ops.copyStorageClass(file.object_key, 'STANDARD');
    if (observed.size !== file.size_bytes || observed.checksum !== file.checksum_sha256) {
      throw new Error('A restored object failed size or checksum verification.');
    }
  }
  return {strategy: 'infrequent', restored_file_count: manifest.files.length, storage_class: 'STANDARD'};
}

async function restoreZip(task, manifest, ops) {
  const source = await ops.getObject(task.archive_object_key);
  if (!source.Body) throw new Error('The archived ZIP stream is unavailable.');
  const expected = new Map(manifest.files.map(file => [file.entry_path, file]));
  const restored = new Set();
  const parser = source.Body.pipe(unzipper.Parse({forceStream: true}));
  for await (const entry of parser) {
    const file = expected.get(entry.path);
    if (!file || entry.type !== 'File') { entry.autodrain(); continue; }
    const hash = crypto.createHash('sha256');
    let bytes = 0;
    const hashTap = new Transform({
      transform(chunk, encoding, callback) {
        hash.update(chunk); bytes += chunk.length; callback(null, chunk);
      },
    });
    entry.pipe(hashTap);
    await ops.uploadStream({
      key: file.object_key,
      body: hashTap,
      contentType: file.mime_type,
      metadata: {sha256: file.checksum_sha256, fileid: String(file.file_id)},
      storageClass: 'STANDARD',
    });
    const observedHash = hash.digest('hex');
    const observed = await ops.headObject(file.object_key);
    if (bytes !== file.size_bytes || observedHash !== file.checksum_sha256
        || observed.size !== file.size_bytes || observed.checksum !== file.checksum_sha256) {
      throw new Error('A restored ZIP entry failed size or checksum verification.');
    }
    restored.add(file.file_id);
  }
  if (restored.size !== manifest.files.length) throw new Error('The ZIP archive did not contain every expected Job file.');
  return {strategy: 'zip', restored_file_count: restored.size, storage_class: 'STANDARD'};
}

async function cleanupZipSources(task, manifest, ops) {
  const observed = await ops.headObject(task.archive_object_key);
  if (observed.size !== Number(task.archive_size_bytes)
      || observed.metadata?.manifestsha256 !== String(task.manifest_sha256 || '')) {
    throw new Error('The verified ZIP archive is unavailable; active source objects were retained.');
  }
  await ops.deleteKeys(manifest.files.map(file => file.object_key));
  return {strategy: 'zip', cleaned_file_count: manifest.files.length};
}

async function cleanupRestoredZip(task, manifest, ops) {
  await verifySourceFiles(manifest.files, ops);
  await ops.deleteKey(task.archive_object_key);
  return {strategy: 'zip', cleaned_archive_count: 1};
}

async function deleteArchive(task, manifest, ops) {
  if (task.strategy === 'zip') await ops.deleteKey(task.archive_object_key);
  else await ops.deleteKeys(manifest.files.map(file => file.object_key));
  return {strategy: task.strategy, deleted_file_count: manifest.files.length};
}

function defaultOperations(config = r2Config(), client = r2Client(config)) {
  return {
    config,
    headObject: key => headObject(key, config, client),
    getObject: key => getObject(key, config, client),
    copyStorageClass: (key, storageClass) => copyStorageClass(key, storageClass, config, client),
    uploadStream: options => uploadStream(options, config, client),
    deleteKeys: keys => deleteKeys(keys, config, client),
    deleteKey: key => deleteKey(key, config, client),
  };
}

async function processTask(task, ops = defaultOperations()) {
  const manifest = task.manifest?.files ? task.manifest : manifestFor(task);
  if (!manifest.files.length) throw new Error('The lifecycle task contains no Job files.');
  if (task.action === 'Archive') {
    const strategy = chooseArchiveStrategy(manifest.files, ops.config.zipMaxBytes);
    return strategy === 'zip'
      ? archiveAsZip(task, manifest, ops)
      : archiveAsInfrequent(task, manifest, ops);
  }
  if (task.action === 'Restore') {
    return task.strategy === 'zip'
      ? restoreZip(task, manifest, ops)
      : restoreInfrequent(task, manifest, ops);
  }
  if (task.action === 'CleanupSources') return cleanupZipSources(task, manifest, ops);
  if (task.action === 'CleanupArchive') return cleanupRestoredZip(task, manifest, ops);
  if (task.action === 'Delete') return deleteArchive(task, manifest, ops);
  throw new Error('Unsupported lifecycle task action.');
}

async function runQueue() {
  const started = Date.now();
  let completed = 0;
  while (Date.now() - started < 12 * 60 * 1000 && completed < 20) {
    const task = await serviceRpc('system_claim_file_lifecycle_044');
    if (!task?.task_id) break;
    try {
      const result = await processTask(task);
      await serviceRpc('system_complete_file_lifecycle_044', {p_task_id: task.task_id, p_result: result}, 30000);
    } catch (error) {
      await serviceRpc('system_fail_file_lifecycle_044', {
        p_task_id: task.task_id,
        p_error: String(error?.message || 'Lifecycle processing failed').slice(0, 500),
      }).catch(() => {});
    }
    completed += 1;
  }
  return completed;
}

exports.handler = async event => {
  const headers = Object.fromEntries(Object.entries(event.headers || {}).map(([key, value]) => [key.toLowerCase(), value]));
  if (event.httpMethod !== 'POST'
      || !timingSafeSecret(headers['x-retodo-worker-key'], process.env.FILE_LIFECYCLE_WORKER_SECRET)) {
    return {statusCode: 404};
  }
  try {
    const body = JSON.parse(event.body || '{}');
    if (body.action !== 'run') return {statusCode: 400};
    const completed = await runQueue();
    console.log('Retodo file lifecycle worker complete', {completed});
    return {statusCode: 204};
  } catch (error) {
    console.error('Retodo file lifecycle worker failed', {message: String(error?.message || error).slice(0, 300)});
    return {statusCode: 500};
  }
};

exports.__test = {
  likelyCompressible,
  chooseArchiveStrategy,
  manifestFor,
  stableJson,
  sha256,
  timingSafeSecret,
  archiveAsInfrequent,
  archiveAsZip,
  restoreInfrequent,
  restoreZip,
  cleanupZipSources,
  cleanupRestoredZip,
  deleteArchive,
  processTask,
};
