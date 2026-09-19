const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const css = read('tms/style.css');
const auth = read('tms/auth.js');
const build = JSON.parse(read('tms/build.json'));
const htmlFiles = fs.readdirSync(path.join(root, 'tms')).filter(name => name.endsWith('.html'));

test('every TMS screen loads the same visual-system and UI-enhancement cache key', () => {
  assert.equal(htmlFiles.length, 17);
  for (const file of htmlFiles) {
    const html = read(`tms/${file}`);
    assert.match(html, /style\.css\?v=056/, `${file} style cache key`);
    assert.match(html, /auth\.js\?v=056/, `${file} auth cache key`);
  }
});

test('global CSS defines hierarchy, darker work fields and compact bubbles', () => {
  assert.match(css, /Update 056 — global visual system refresh/);
  assert.match(css, /--surface-field:\s*#e9edf4/);
  assert.match(css, /\.module-header h1,[\s\S]*font-size:\s*22px/);
  assert.match(css, /\.section-card-heading h2,[\s\S]*font-size:\s*18px/);
  assert.match(css, /\.section-title,[\s\S]*text-transform:\s*uppercase/);
  assert.match(css, /\.pill,[\s\S]*font-size:\s*10\.5px/);
  assert.match(css, /\.action-prominent[\s\S]*background:\s*#f5f3ff/);
  assert.match(css, /input\[type="file"\]::file-selector-button/);
});

test('explanatory help and operational actions are progressively enhanced', () => {
  assert.match(auth, /function collapseHelpText\(element\)/);
  assert.match(auth, /tip\.className = 'help-tip'/);
  assert.match(auth, /\^upload\\b/i);
  assert.match(auth, /\^\(open\|download\|view\|print\|export\)\\b/i);
  assert.match(auth, /MutationObserver/);
});

test('stale cross-profile tabs are redirected to the active role workspace', () => {
  assert.match(auth, /function installRoleDriftGuard\(\)/);
  assert.match(auth, /if \(role && !routeMatchesRole\(role\)\) location\.replace\(homeForRole\(role\)\)/);
});

test('build marker is forward-only from Update 055', () => {
  assert.equal(build.build, '056');
  assert.equal(build.source_baseline, 'Update 055');
  assert.match(build.release, /Global visual system refresh/);
});

