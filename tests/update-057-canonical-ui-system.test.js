const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('all TMS screens load the Update 057 visual and behavior cache key', () => {
  const screens = fs.readdirSync(path.join(root, 'tms')).filter(file => file.endsWith('.html'));
  assert.equal(screens.length, 17);
  for (const screen of screens) {
    const html = read(`tms/${screen}`);
    assert.match(html, /style\.css\?v=057/, `${screen} style cache key`);
    assert.match(html, /auth\.js\?v=057/, `${screen} behavior cache key`);
  }
});

test('canonical tokens, alignment grid and control grammar are present', () => {
  const css = read('tms/style.css');
  assert.match(css, /Update 057 final cascade/);
  assert.match(css, /--space-5:24px/);
  assert.match(css, /--control-h:36px/);
  assert.match(css, /\.record-pane\.active \{ display:grid; \}/);
  assert.match(css, /\.btn-primary,.btn-secondary,.btn-danger,.table-action,.action-prominent,.btn-icon/);
  assert.match(css, /\.data-card \{ min-height:72px/);
});

test('help text is anchored beside the nearest heading or label', () => {
  const auth = read('tms/auth.js');
  assert.match(auth, /const anchor = card\?\.querySelector/);
  assert.match(auth, /anchor\.classList\.add\('heading-with-help'\)/);
  assert.match(auth, /anchor\.append\(tip\)/);
});

test('resource profile uses the normalized page header', () => {
  const html = read('tms/resource.html');
  assert.match(html, /module-header resource-profile-header/);
  assert.match(html, /pane-toolbar qualification-toolbar/);
});

test('build marker is Update 057', () => {
  assert.equal(JSON.parse(read('tms/build.json')).build, '057');
});
