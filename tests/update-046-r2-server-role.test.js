'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const migration = read('tms/migrations/045_r2_server_role_claim_compatibility.sql');
const audit = read('tms/audits/007_update_046_r2_server_role_audit.sql');

const signatures = [
  'public.r2_file_dispatch_044(text,uuid,uuid,uuid,jsonb)',
  'public.system_enqueue_due_file_lifecycle_044()',
  'public.system_claim_file_lifecycle_044()',
  'public.system_complete_file_lifecycle_044(uuid,jsonb)',
  'public.system_fail_file_lifecycle_044(uuid,text)',
];

test('Update 046 is a forward-only role-claim compatibility migration', () => {
  assert.match(migration, /Forward-only migration/i);
  assert.match(migration, /BEGIN;/);
  assert.match(migration, /COMMIT;/);
  assert.match(migration, /auth\.role\(\) IS DISTINCT FROM ''service_role''/);
  assert.match(migration, /pg_get_functiondef/);
  assert.match(migration, /CREATE OR\s+-- REPLACE preserves existing privileges/);
  assert.doesNotMatch(migration, /\b(?:ALTER|DROP|TRUNCATE)\s+TABLE\b/i);
  assert.doesNotMatch(migration, /\b(?:CREATE|ALTER|DROP)\s+POLICY\b/i);
});

test('all five Update 045 server entrypoints are patched and remain service-only', () => {
  for (const signature of signatures) {
    const escaped = signature.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(migration, new RegExp(escaped));
  }
  assert.equal((migration.match(/FROM PUBLIC, anon, authenticated/g) || []).length, 5);
  assert.equal((migration.match(/TO service_role;/g) || []).length, 5);
});

test('audit verifies the new guard, legacy removal and unchanged authorization semantics', () => {
  assert.match(audit, /auth\.role\(\) guard missing/);
  assert.match(audit, /legacy per-claim role read remains/);
  assert.match(audit, /own-Job Resource boundary missing/);
  assert.match(audit, /Ready-only download boundary missing/);
  assert.match(audit, /no direct Resource file-table write policy/);
  assert.doesNotMatch(`${migration}\n${audit}`, /(?:R2_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY)\s*[=:]\s*["'][^"']{8,}["']/);
});
