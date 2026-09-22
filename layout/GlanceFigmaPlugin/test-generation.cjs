const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function node(type) {
  return {
    type,
    name: '',
    x: 0,
    y: 0,
    width: 0,
    height: type === 'TEXT' ? 16 : 0,
    children: [],
    resize(width, height) { this.width = width; this.height = height; },
    appendChild(child) { this.children.push(child); child.parent = this; },
    findOne(predicate) {
      for (const child of this.children) {
        if (predicate(child)) return child;
        const found = child.findOne(predicate);
        if (found) return found;
      }
      return null;
    },
    findAll(predicate) {
      const matches = [];
      for (const child of this.children) {
        if (predicate(child)) matches.push(child);
        matches.push(...child.findAll(predicate));
      }
      return matches;
    }
  };
}

const page = node('PAGE');
const figma = {
  currentPage: page,
  ui: { postMessage(message) { this.lastMessage = message; }, onmessage: null },
  viewport: { scrollAndZoomIntoView() {} },
  showUI() {},
  notify() {},
  loadFontAsync: async () => {},
  getLocalPaintStylesAsync: async () => [],
  createPaintStyle: () => node('PAINT_STYLE'),
  createFrame: () => node('FRAME'),
  createRectangle: () => node('RECTANGLE'),
  createEllipse: () => node('ELLIPSE'),
  createText: () => node('TEXT'),
  createNodeFromSvg: () => node('SVG'),
  createImage: () => ({
    hash: 'test-image-hash',
    getSizeAsync: async () => ({ width: 1920, height: 1080 })
  })
};

const source = fs.readFileSync(__dirname + '/code.js', 'utf8');
vm.runInNewContext(source, { figma, __html__: '' }, { filename: 'code.js' });

const names = [
  'Home / Launcher / Clean Editable',
  'Content Viewer / Clean Editable',
  'Widget Web / States / Clean Editable',
  'Base64 Toolkit / Clean Editable',
  'Preview History / Clean Editable',
  'Preferences / Clean Editable',
  'Onboarding / Permissions / Clean Editable'
];

(async () => {
  await figma.ui.onmessage({ type: 'generate-remaining-screens' });
  assert.equal(page.children.length, 7);
  for (const [index, child] of page.children.entries()) {
    assert.equal(child.name, names[index]);
    assert.equal(child.width, 1554);
    assert.equal(child.height, 1012);
    assert.ok(child.children.length >= 1, child.name + ' is empty');
    assert.ok(child.x >= (page.children[index - 1]?.x ?? -1750) + 1750);
  }
  assert.match(figma.ui.lastMessage.message, /Created 7 screens/);
  await figma.ui.onmessage({ type: 'generate-remaining-screens' });
  assert.equal(page.children.length, 7, 'Second run must not replace edited screens');
  assert.match(figma.ui.lastMessage.message, /0 screens; 7 already existed/);

  // Home screen: real open surface with folder + recent tiles
  const home = page.children.find(child => child.name === 'Home / Launcher / Clean Editable');
  assert.ok(home.findOne(child => child.name === '03 / Open Surface'), 'Home needs open surface');
  assert.ok(home.findOne(child => child.name === 'Drop Zone'), 'Home needs a drop zone');
  assert.ok(home.findOne(child => child.name === 'Open Files Button'));
  assert.ok(home.findOne(child => child.name === 'Open Folder Button'));
  assert.ok(home.findOne(child => child.name === 'Folder Images'), 'Home shows folder image strip');
  assert.ok(home.findOne(child => child.name === '04 / Recent'), 'Home needs recent column');

  // Dedicated Home button is idempotent
  await figma.ui.onmessage({ type: 'generate-home' });
  assert.equal(page.children.length, 7, 'generate-home must not duplicate existing Home');
  assert.match(figma.ui.lastMessage.message, /already exists/);

  await figma.ui.onmessage({ type: 'generate-simple-image-viewer', bytes: [1, 2, 3] });
  assert.equal(page.children.length, 8);
  const viewer = page.children.find(child => child.name === 'Image Viewer / Simple Operation');
  assert.ok(viewer, 'Simple Image Viewer must be generated');
  assert.equal(viewer.width, 1920);
  assert.equal(viewer.height, 1080);
  assert.equal(viewer.fills[0].type, 'IMAGE');
  const viewerToolbar = viewer.findOne(child => child.name === '01 / Floating Toolbar');
  assert.ok(viewerToolbar, 'Simple Image Viewer needs a floating toolbar');
  assert.equal(viewerToolbar.x, 845, 'Toolbar must remain centered at the image native width');
  assert.deepEqual(viewerToolbar.children.map(child => child.name),
    ['Focus', 'Compare', 'Slider', 'Widget', 'Information']);
  await figma.ui.onmessage({ type: 'generate-simple-image-viewer', bytes: [1, 2, 3] });
  assert.equal(page.children.length, 8, 'Second viewer generation must preserve the existing frame');
  assert.match(figma.ui.lastMessage.message, /Updated/);
  await figma.ui.onmessage({ type: 'generate-simple-image-viewer', bytes: null });
  assert.equal(page.children.length, 8, 'Viewer generation without an image must preserve the existing frame');
  assert.match(figma.ui.lastMessage.message, /already exists/);

  const previous = node('FRAME');
  previous.name = 'Widget Market / Install / Clean Editable';
  previous.x = 11000;
  previous.resize(1554, 1012);
  page.appendChild(previous);
  await figma.ui.onmessage({ type: 'redesign-widget-market' });
  assert.equal(page.children.length, 10);
  assert.equal(previous.name, 'Widget Market / Install / Previous');
  const redesigned = page.children.find(child => child.name === 'Widget Market / Install / Clean Editable');
  assert.equal(redesigned.x, 11000);
  assert.equal(redesigned.width, 1554);
  assert.ok(redesigned.findOne(child => child.name === '01 / Attached Market Catalog'));
  assert.ok(redesigned.findOne(child => child.name === '02 / Selected Widget Detail Drawer'));
  assert.deepEqual(redesigned.findOne(child => child.name === '01 / Attached Market Catalog').children.filter(child => child.name.startsWith('Widget / ')).map(child => child.name),
    ['Widget / Remove Background', 'Widget / 超分', 'Widget / RemoveBG 高级']);
  await figma.ui.onmessage({ type: 'redesign-widget-market' });
  assert.equal(page.children.length, 10, 'Second redesign must keep edited market intact');
  const beforeRefresh = page.children.length;
  await figma.ui.onmessage({ type: 'generate-dark-refresh-screens', bytes: [1, 2, 3] });
  const refreshed = page.children.filter(child => child.name.startsWith('Dark Refresh v2 / '));
  assert.equal(refreshed.length, 13, 'Dark Refresh must generate exactly 13 review screens: ' + figma.ui.lastMessage.message);
  assert.equal(page.children.length, beforeRefresh + 13);
  const refreshedViewer = page.children.find(child => child.name === 'Dark Refresh v2 / Image Viewer / Simple Operation');
  assert.equal(refreshedViewer.width, 1920);
  assert.equal(refreshedViewer.height, 1080);
  const refreshedToolbar = refreshedViewer.findOne(child => child.name === '01 / Floating Toolbar');
  assert.ok(refreshedToolbar.effects.some(effect => effect.type === 'BACKGROUND_BLUR'));
  assert.deepEqual(refreshedToolbar.children.map(child => child.name),
    ['Focus', 'Compare', 'Slider', 'Widget', 'Information']);
  const systemControls = refreshedViewer.findOne(child => child.name === 'System / Window Controls');
  assert.deepEqual(systemControls.children.map(child => child.name),
    ['Close', 'Minimize', 'Fullscreen']);
  const refreshedVideo = page.children.find(child => child.name === 'Dark Refresh v2 / Video Inspect');
  const videoToolbar = refreshedVideo.findOne(child => child.name === '01 / Floating Toolbar');
  assert.deepEqual(videoToolbar.children.map(child => child.name),
    ['Focus', 'Compare', 'Slider', 'Widget', 'Information']);
  assert.ok(refreshedVideo.findOne(child => child.name === 'System / Window Controls'));
  assert.ok(refreshedVideo.findOne(child => child.name === '02 / Floating Playback Controls'));
  const videoContent = refreshedVideo.findOne(child => child.name === '03 / Video Content');
  assert.equal(videoContent.width, 1554);
  assert.equal(videoContent.height, 1012);
  await figma.ui.onmessage({ type: 'generate-dark-refresh-screens', bytes: [1, 2, 3] });
  assert.equal(page.children.length, beforeRefresh + 13, 'Dark Refresh generation must be idempotent');
  const beforeStudy = page.children.length;
  await figma.ui.onmessage({ type: 'generate-viewer-chrome-study' });
  const study = page.children.find(child => child.name === 'Dark Refresh v3 / Image Viewer / Simple Operation');
  assert.ok(study, 'Viewer Chrome Study must be generated');
  assert.equal(page.children.length, beforeStudy + 1);
  const bareControls = study.findOne(child => child.name === 'System / Window Controls / Bare');
  assert.ok(bareControls);
  assert.equal(bareControls.fills.length, 0, 'Bare controls must not have a capsule fill');
  assert.deepEqual(bareControls.children.map(child => child.name), ['Close', 'Minimize', 'Fullscreen']);
  assert.ok(study.findOne(child => child.name === 'System / Transparent Drag Region'));
  await figma.ui.onmessage({ type: 'generate-viewer-chrome-study' });
  assert.equal(page.children.length, beforeStudy + 1, 'Viewer Chrome Study must be idempotent');
  console.log('Production screens, Simple Image Viewer, Widget Market, 13-screen Dark Refresh, and Viewer Chrome Study generate idempotently');
})().catch(error => { console.error(error); process.exitCode = 1; });
