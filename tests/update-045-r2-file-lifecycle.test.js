const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Readable} = require('node:stream');

const root = path.resolve(__dirname, '..');
const read = relativePath => fs.readFileSync(path.join(root, relativePath), 'utf8');
const migration = read('tms/migrations/044_cloudflare_r2_file_lifecycle.sql');
const audit = read('tms/audits/006_update_045_r2_file_lifecycle_audit.sql');
const jobHtml = read('tms/job.html');
const jobJs = read('tms/job.js');
const resourceJobJs = read('tms/resource-job.js');
const settingsHtml = read('tms/settings.html');
const settingsJs = read('tms/settings.js');
const netlify = read('netlify.toml');

test('migration 044 is atomic, forward-only and preserves all earlier migrations', () => {
  assert.match(migration, /Forward-only migration\. Migrations 036–043 are immutable/);
  assert.equal((migration.match(/^BEGIN;$/gm) || []).length, 1);
  assert.equal((migration.match(/^COMMIT;$/gm) || []).length, 1);
  assert.doesNotMatch(migration, /\b(DROP TABLE|TRUNCATE)\b/i);
  assert.match(migration, /'Cloudflare R2'/);
  assert.match(migration, /archive_after_months[^;]+DEFAULT 3/s);
  assert.match(migration, /delete_after_months[^;]+DEFAULT 24/s);
});

test('R2 dispatcher and lifecycle worker RPCs are service-role only', () => {
  for (const name of [
    'r2_file_dispatch_044', 'system_enqueue_due_file_lifecycle_044',
    'system_claim_file_lifecycle_044', 'system_complete_file_lifecycle_044',
    'system_fail_file_lifecycle_044',
  ]) {
    const index = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
    assert.ok(index >= 0, `${name} missing`);
    const next = migration.indexOf('CREATE OR REPLACE FUNCTION public.', index + 1);
    const definition = migration.slice(index, next < 0 ? migration.length : next);
    assert.match(definition, /SECURITY DEFINER/);
    assert.match(definition, /SET search_path = public/);
    assert.match(definition, /request\.jwt\.claim\.role[\s\S]*service_role/);
  }
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.r2_file_dispatch_044[\s\S]*FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.r2_file_dispatch_044[\s\S]*TO service_role/);
});

test('Resource access remains own-Job, Ready-only and Client-blind', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.resource_portal_job[\s\S]*job\.resource_id = v_resource_id/);
  assert.match(migration, /file\.upload_status = 'Ready'/);
  assert.match(migration, /CASE WHEN file\.storage_provider = 'Supabase'[\s\S]*THEN file\.object_key END/);
  assert.doesNotMatch(resourceJobJs, /_sb\.from\(/);
  assert.doesNotMatch(resourceJobJs, /client_accounts|client_name|client_price|profit|margin/i);
  assert.match(resourceJobJs, /resourceFileApi\('download'/);
  assert.doesNotMatch(resourceJobJs, /R2_ACCESS_KEY|R2_SECRET|service.?role/i);
});

test('staff upload uses streaming SHA-256, presigned PUT and verified completion', () => {
  assert.match(jobHtml, /file-hash\.js\?v=045/);
  assert.match(jobJs, /TMS_FILE_HASH\.sha256Hex/);
  assert.match(jobJs, /fileApi\('prepare_upload'/);
  assert.match(jobJs, /fetch\(prepared\.upload_url/);
  assert.match(jobJs, /method:'PUT'/);
  assert.match(jobJs, /fileApi\('complete_upload'/);
  assert.match(jobJs, /fileApi\('discard_upload'/);
  assert.doesNotMatch(jobJs, /\.storage\.from\(ticket\.bucket_name\)\.upload/);
});

test('Job-file API rejects wrong methods, cross-origin calls and invalid actions before privileged access', async () => {
  const api = require('../netlify/functions/job-files');
  let response = await api.handler({httpMethod: 'GET', headers: {}, body: ''});
  assert.equal(response.statusCode, 405);
  assert.equal(response.headers['Cache-Control'], 'no-store');

  response = await api.handler({
    httpMethod: 'POST', headers: {origin: 'https://attacker.example'},
    body: JSON.stringify({action: 'download'}),
  });
  assert.equal(response.statusCode, 403);
  assert.doesNotMatch(response.headers['Content-Security-Policy'], /\*/);

  response = await api.handler({
    httpMethod: 'POST', headers: {origin: 'https://tms.retodo-ops.com'},
    body: JSON.stringify({action: 'delete_everything'}),
  });
  assert.equal(response.statusCode, 400);
  assert.match(JSON.parse(response.body).error, /Unknown file action/);
});

test('browser streaming SHA-256 matches standard vectors', async () => {
  delete globalThis.TMS_FILE_HASH;
  delete require.cache[require.resolve('../tms/file-hash.js')];
  require('../tms/file-hash.js');
  assert.equal(await globalThis.TMS_FILE_HASH.sha256Hex(new Blob([])),
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  assert.equal(await globalThis.TMS_FILE_HASH.sha256Hex(new Blob(['abc'])),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  const repeated = new Blob(['a'.repeat(1_000_000)]);
  assert.equal(await globalThis.TMS_FILE_HASH.sha256Hex(repeated),
    'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
});

test('R2 helpers clamp link life and sign required upload metadata without a false body checksum', async () => {
  const previous = {...process.env};
  Object.assign(process.env, {
    R2_ENDPOINT: 'https://example.eu.r2.cloudflarestorage.com',
    R2_ACCESS_KEY_ID: 'test-key-id', R2_SECRET_ACCESS_KEY: 'test-secret',
    R2_BUCKET_NAME: 'retodo-private-files', R2_SIGNED_URL_TTL_SECONDS: '9999999',
  });
  const helpers = require('../netlify/functions/_shared/r2');
  assert.equal(helpers.r2Config().linkTtlSeconds, 604800);
  assert.match(helpers.contentDisposition('safe\r\nname.txt', true), /^attachment;/);
  assert.doesNotMatch(helpers.contentDisposition('safe\r\nname.txt', true), /[\r\n]/);
  const signed = await helpers.signedUpload({
    file_id: '11111111-1111-1111-1111-111111111111', object_key: 'active/source.txt',
    checksum_sha256: 'ab'.repeat(32), mime_type: 'text/plain',
  });
  const signedUrl = new URL(signed.url);
  assert.equal(signedUrl.searchParams.has('x-amz-checksum-crc32'), false);
  assert.match(signedUrl.searchParams.get('X-Amz-SignedHeaders') || '', /x-amz-meta-fileid/);
  assert.match(signedUrl.searchParams.get('X-Amz-SignedHeaders') || '', /x-amz-meta-sha256/);
  assert.equal(signed.headers['x-amz-meta-sha256'], 'ab'.repeat(32));
  for (const key of Object.keys(process.env)) if (!(key in previous)) delete process.env[key];
  Object.assign(process.env, previous);
});

test('smart archive chooses IA for compressed files and ZIP only for meaningful savings', async () => {
  const worker = require('../netlify/functions/file-lifecycle-worker-background').__test;
  const compressed = [{file_id:'1', original_filename:'source.zip', mime_type:'application/zip', size_bytes:10_000_000}];
  const text = [{file_id:'1', original_filename:'source.txt', mime_type:'text/plain', size_bytes:10_000_000}];
  assert.equal(worker.chooseArchiveStrategy(compressed, 100_000_000), 'infrequent');
  assert.equal(worker.chooseArchiveStrategy(text, 100_000_000), 'zip');
  const observed = [];
  const task = {action:'Archive', project_id:'p', job_id:'j', archive_id:'a', files:compressed};
  const result = await worker.processTask(task, {
    config:{zipMaxBytes:100_000_000},
    headObject:async()=>({size:10_000_000,checksum:'',fileId:'1'}),
    copyStorageClass:async(key,storageClass)=>{observed.push(storageClass);return {size:10_000_000,checksum:'',storageClass}},
  });
  assert.equal(result.strategy, 'infrequent');
  assert.deepEqual(observed, ['STANDARD_IA']);
});

test('ZIP cleanup is a separate idempotent phase after durable metadata commit', async () => {
  const workerSource = read('netlify/functions/file-lifecycle-worker-background.js');
  const archiveBody = workerSource.slice(
    workerSource.indexOf('async function archiveAsZip'),
    workerSource.indexOf('async function restoreInfrequent'),
  );
  const restoreBody = workerSource.slice(
    workerSource.indexOf('async function restoreZip'),
    workerSource.indexOf('async function cleanupZipSources'),
  );
  assert.doesNotMatch(archiveBody, /deleteKeys\(/);
  assert.doesNotMatch(restoreBody, /deleteKey\(/);

  const worker = require('../netlify/functions/file-lifecycle-worker-background').__test;
  const file = {
    file_id: 'file-1', object_key: 'active/file-1', original_filename: 'source.txt',
    mime_type: 'text/plain', size_bytes: 2048, checksum_sha256: 'ab'.repeat(32),
  };
  const manifest = {format: 'retodo-job-archive-v1', files: [file]};
  const deleted = [];
  const base = {
    config: {zipMaxBytes: 10_000_000},
    headObject: async key => key === 'archive.zip'
      ? {size: 1024, metadata: {manifestsha256: 'cd'.repeat(32)}}
      : {size: 2048, checksum: file.checksum_sha256, fileId: file.file_id},
    deleteKeys: async keys => deleted.push(...keys),
    deleteKey: async key => deleted.push(key),
  };
  await worker.processTask({
    action: 'CleanupSources', strategy: 'zip', manifest,
    archive_object_key: 'archive.zip', archive_size_bytes: 1024,
    manifest_sha256: 'cd'.repeat(32),
  }, base);
  await worker.processTask({
    action: 'CleanupArchive', strategy: 'zip', manifest,
    archive_object_key: 'archive.zip',
  }, base);
  assert.deepEqual(deleted, ['active/file-1', 'archive.zip']);
});

test('real ZIP archive round-trip verifies bytes before each cleanup phase', async () => {
  const worker = require('../netlify/functions/file-lifecycle-worker-background').__test;
  const crypto = require('node:crypto');
  const digest = value => crypto.createHash('sha256').update(value).digest('hex');
  const contents = new Map([
    ['active/a.txt', Buffer.from('A translatable source file. '.repeat(200))],
    ['active/b.txt', Buffer.from('Reference instructions. '.repeat(120))],
  ]);
  const metadata = new Map();
  const files = [...contents].map(([object_key, bytes], index) => ({
    file_id: `file-${index + 1}`, object_key,
    original_filename: object_key.split('/').pop(), mime_type: 'text/plain',
    size_bytes: bytes.length, checksum_sha256: digest(bytes),
  }));
  files.forEach(file => metadata.set(file.object_key, {
    sha256: file.checksum_sha256, fileid: file.file_id,
  }));
  const ops = {
    config: {zipMaxBytes: 20_000_000},
    headObject: async key => {
      const bytes = contents.get(key); if (!bytes) throw new Error(`missing ${key}`);
      const meta = metadata.get(key) || {};
      return {
        size: bytes.length, checksum: meta.sha256 || null, fileId: meta.fileid || null,
        storageClass: meta.storageClass || 'STANDARD', metadata: meta,
      };
    },
    getObject: async key => ({Body: Readable.from([contents.get(key)])}),
    uploadStream: async ({key, body, metadata: meta, storageClass}) => {
      const chunks = []; for await (const chunk of body) chunks.push(Buffer.from(chunk));
      contents.set(key, Buffer.concat(chunks)); metadata.set(key, {...meta, storageClass});
    },
    deleteKeys: async keys => keys.forEach(key => {contents.delete(key); metadata.delete(key);}),
    deleteKey: async key => {contents.delete(key); metadata.delete(key);},
  };
  const task = {
    action: 'Archive', project_id: 'project', job_id: 'job', archive_id: 'archive',
    archive_object_key: 'archives/job.zip', files,
  };
  const archived = await worker.archiveAsZip(task, worker.manifestFor(task), ops);
  assert.ok(contents.has('archives/job.zip'));
  assert.ok(files.every(file => contents.has(file.object_key)), 'source deletion must wait for DB commit');

  await worker.cleanupZipSources({...task, ...archived}, archived.manifest, ops);
  assert.ok(files.every(file => !contents.has(file.object_key)));
  await worker.restoreZip({...task, ...archived}, archived.manifest, ops);
  files.forEach(file => assert.equal(digest(contents.get(file.object_key)), file.checksum_sha256));
  assert.ok(contents.has('archives/job.zip'), 'archive deletion must wait for restore DB commit');
  await worker.cleanupRestoredZip({...task, ...archived}, archived.manifest, ops);
  assert.equal(contents.has('archives/job.zip'), false);
});

test('Netlify schedules daily queueing and uses a background worker', () => {
  assert.match(netlify, /\[functions\."file-lifecycle-scheduler"\][\s\S]*schedule = "@daily"/);
  assert.match(netlify, /\[functions\."file-lifecycle-worker-background"\][\s\S]*background = true/);
  const scheduler = read('netlify/functions/file-lifecycle-scheduler.js');
  const worker = read('netlify/functions/file-lifecycle-worker-background.js');
  assert.match(scheduler, /system_enqueue_due_file_lifecycle_044/);
  assert.match(worker, /system_claim_file_lifecycle_044/);
  assert.match(worker, /system_complete_file_lifecycle_044/);
  assert.match(worker, /system_fail_file_lifecycle_044/);
  assert.match(worker, /verifySourceFiles/);
});

test('retention UI exposes 3/24 overrides and admin-only Hold mutations', () => {
  assert.match(settingsHtml, /id="file-retention"/);
  assert.match(settingsHtml, /id="rp-archive-months"[\s\S]*value="3"/);
  assert.match(settingsHtml, /id="rp-delete-months"[\s\S]*value="24"/);
  assert.match(settingsJs, /admin_save_file_retention_policy_044/);
  assert.match(settingsJs, /admin_delete_file_retention_policy_044/);
  assert.match(settingsJs, /canManageSetting\(\)/);
  assert.match(jobJs, /admin_set_project_file_hold_044/);
});

test('bucket policies are private-origin only and native lifecycle cannot bypass TMS retention', () => {
  const cors = JSON.parse(read('R2_CORS_POLICY.json'));
  const lifecycle = JSON.parse(read('R2_LIFECYCLE_POLICY.json'));
  assert.deepEqual(cors[0].AllowedOrigins, ['https://tms.retodo-ops.com']);
  assert.deepEqual(cors[0].AllowedMethods, ['GET', 'PUT', 'HEAD']);
  assert.equal(lifecycle.rules[0].abortMultipartUploadsTransition.condition.maxAge, 604800);
  assert.equal(JSON.stringify(lifecycle).includes('deleteObjectsTransition'), false);
  assert.equal(JSON.stringify(lifecycle).includes('storageClassTransitions'), false);
});

test('archive/audit contract is read-only and covers holds, states and RLS', () => {
  assert.match(audit, /Every statement is read-only/);
  assert.match(audit, /service_role/);
  assert.match(audit, /Resource projections remain own-Job/);
  assert.match(audit, /Retention Hold/);
  const statements = audit.replace(/^--.*$/gm, '').split(';').map(value => value.trim()).filter(Boolean);
  assert.ok(statements.length >= 12);
  for (const statement of statements) assert.match(statement, /^(WITH|SELECT)\b/i);
});

test('release files contain no credential values or private keys', () => {
  const candidates = [
    'UPDATE_045_R2_DEPLOYMENT.md', 'netlify/functions/_shared/r2.js',
    'netlify/functions/_shared/supabase.js', 'netlify/functions/job-files.js',
    'netlify/functions/file-lifecycle-scheduler.js',
    'netlify/functions/file-lifecycle-worker-background.js',
  ].map(read).join('\n');
  assert.doesNotMatch(candidates, /eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}/);
  assert.doesNotMatch(candidates, /-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----/);
  assert.doesNotMatch(candidates, /(?:R2_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY)\s*[=:]\s*["'][^"']{8,}["']/);
});
