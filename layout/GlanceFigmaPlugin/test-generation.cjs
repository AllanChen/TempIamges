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
    clone() {
      function copy(original) {
        const duplicate = node(original.type);
        for (const [key, value] of Object.entries(original)) {
          if (key !== 'parent' && key !== 'children' && typeof value !== 'function') {
            duplicate[key] = structuredClone(value);
          }
        }
        original.children.forEach(child => duplicate.appendChild(copy(child)));
        return duplicate;
      }
      const duplicate = copy(this);
      if (this.parent) this.parent.appendChild(duplicate);
      return duplicate;
    },
    remove() {
      if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1);
      this.parent = null;
    },
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
  assert.equal(viewerToolbar.x, 823, 'Toolbar must remain centered at the image native width');
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

  const beforePreview = page.children.length;
  await figma.ui.onmessage({ type: 'generate-preview-chrome-study' });
  const preview = page.children.find(child => child.name === 'Dark Refresh v3 / Image Viewer / Preview Chrome');
  assert.ok(preview, 'Preview Chrome Study must be generated');
  assert.equal(page.children.length, beforePreview + 1);
  const previewBar = preview.findOne(child => child.name === '01 / Preview Top Bar');
  assert.ok(previewBar, 'Preview Chrome needs a single top bar');
  assert.ok(previewBar.findOne(child => child.name === 'Close'), 'Preview bar needs a close control');
  assert.ok(previewBar.findOne(child => child.name === 'Filename'), 'Preview bar needs the filename');
  assert.ok(previewBar.findOne(child => child.name === 'Open with Preview'), 'Preview bar needs the open-with pill');
  await figma.ui.onmessage({ type: 'generate-preview-chrome-study' });
  assert.equal(page.children.length, beforePreview + 1, 'Preview Chrome Study must be idempotent');

  const beforeCompare = page.children.length;
  await figma.ui.onmessage({ type: 'generate-compare-chrome-study' });
  const compare = page.children.find(child => child.name === 'Dark Refresh v3 / Image Viewer / Compare Mode');
  assert.ok(compare, 'Compare Mode Study must be generated');
  assert.equal(page.children.length, beforeCompare + 1);
  assert.equal(compare.strokeWeight, 2, 'Compare Mode window must have a visible border');
  assert.ok(compare.findOne(child => child.name === 'Compare / A'), 'Compare needs pane A');
  assert.ok(compare.findOne(child => child.name === 'Compare / B'), 'Compare needs pane B');
  assert.ok(compare.findOne(child => child.name === 'Compare / Divider'), 'Compare needs a center divider');
  const compareToolbar = compare.findOne(child => child.name === '01 / Floating Toolbar');
  assert.ok(compareToolbar, 'Compare needs the floating toolbar');
  const compareTile = compareToolbar.findOne(child => child.name === 'Compare');
  assert.ok(compareTile, 'Compare tile must exist');
  assert.equal(Math.round(compareTile.fills[0].opacity * 100), 96, 'Compare tile must render active (96% fill)');
  await figma.ui.onmessage({ type: 'generate-compare-chrome-study' });
  assert.equal(page.children.length, beforeCompare + 1, 'Compare Mode Study must be idempotent');

  // Non-destructive image replace: swaps fills only, never removes layers.
  const focusFrame = page.children.find(child =>
    child.name === 'Dark Refresh v3 / Image Viewer / Simple Operation' ||
    child.name === 'Dark Refresh v3 / Image Viewer / fouce Mode' ||
    child.name === 'Dark Refresh v3 / Image Viewer / Focus Mode');
  const focusChildrenBefore = focusFrame.children.length;
  const compareChildrenBefore = compare.children.length;
  const pageCountBeforeReplace = page.children.length;
  await figma.ui.onmessage({ type: 'replace-study-images', bytes: [1, 2, 3] });
  assert.equal(page.children.length, pageCountBeforeReplace, 'Replace must not add/remove frames');
  assert.equal(focusFrame.children.length, focusChildrenBefore, 'Replace must not remove Focus layers');
  assert.equal(compare.children.length, compareChildrenBefore, 'Replace must not remove Compare layers');
  assert.equal(focusFrame.fills[0].type, 'IMAGE', 'Focus board must now carry the image');
  assert.equal(compare.findOne(c => c.name === 'Compare / A').fills[0].type, 'IMAGE', 'Compare A must carry the image');
  assert.equal(compare.findOne(c => c.name === 'Compare / B').fills[0].type, 'IMAGE', 'Compare B must carry the image');

  const beforeInspectStudy = page.children.length;
  await figma.ui.onmessage({ type: 'generate-image-inspect-chrome-study' });
  const inspectStudy = page.children.find(child => child.name === 'Dark Refresh v3 / Image Inspect / Clean Editable');
  assert.ok(inspectStudy, 'Image Inspect Chrome Study must be generated');
  assert.equal(page.children.length, beforeInspectStudy + 1);
  assert.ok(inspectStudy.findOne(child => child.name === 'System / Window Controls / Bare'));
  assert.ok(inspectStudy.findOne(child => child.name === '04 / Image Information / active preview'));
  const inspectToolbar = inspectStudy.findOne(child => child.name === '01 / Floating Toolbar');
  assert.deepEqual(inspectToolbar.children.map(child => child.name),
    ['Focus', 'Compare', 'Slider', 'Widget', 'Information']);
  await figma.ui.onmessage({ type: 'generate-image-inspect-chrome-study' });
  assert.equal(page.children.length, beforeInspectStudy + 1, 'Image Inspect Chrome Study must be idempotent');

  const beforeFilmstripStudy = page.children.length;
  await figma.ui.onmessage({ type: 'generate-image-filmstrip-scroll-study' });
  const filmstripStudy = page.children.find(child => child.name === 'Image Inspect / Filmstrip Scroll / Review');
  assert.ok(filmstripStudy, 'Image Filmstrip Scroll Study must be generated');
  assert.equal(page.children.length, beforeFilmstripStudy + 1);
  const viewport = filmstripStudy.findOne(child => child.name === '02 / Filmstrip Viewport / six visible');
  const content = filmstripStudy.findOne(child => child.name === 'Scrollable Thumbnail Content / seven images');
  assert.equal(viewport.width, 626, 'Viewport must fit exactly six 96px tiles and five 10px gaps');
  assert.equal(content.findAll(child => child.name.startsWith('Thumbnail ')).length, 7);
  assert.ok(filmstripStudy.findOne(child => child.name === 'Scrollbar Track'));
  assert.ok(filmstripStudy.findOne(child => child.name === 'Scrollbar Thumb / warm cue'));
  await figma.ui.onmessage({ type: 'generate-image-filmstrip-scroll-study' });
  assert.equal(page.children.length, beforeFilmstripStudy + 1, 'Filmstrip study must be idempotent');

  const beforeCompressionFlow = page.children.length;
  await figma.ui.onmessage({ type: 'generate-image-compression-flow' });
  const compressionFlow = page.children.find(child => child.name === 'Image Compression Flow');
  assert.ok(compressionFlow, 'Image Compression Flow must be generated');
  assert.equal(page.children.length, beforeCompressionFlow + 1);
  const compressionDialog = compressionFlow.findOne(child => child.name === 'Compression Dialog');
  assert.ok(compressionDialog, 'Compression flow needs a dialog');
  assert.ok(compressionDialog.findOne(child => child.name === 'Quality Value / updates with slider'));
  assert.ok(compressionDialog.findOne(child => child.name === 'Keep original dimensions / checked'));
  assert.ok(compressionDialog.findOne(child => child.name === 'Checkbox / checked'));
  assert.ok(compressionDialog.findOne(child => child.name === 'Compressed size / updates with slider'));
  assert.equal(compressionDialog.findOne(child => child.name === 'Format Dropdown'), null,
    'Compression dialog must not offer format conversion');
  await figma.ui.onmessage({ type: 'generate-image-compression-flow' });
  assert.equal(page.children.filter(child => child.name === 'Image Compression Flow').length, 1,
    'Regeneration must leave exactly one current compression flow');
  assert.equal(page.children.filter(child => child.name === 'Image Compression Flow / Previous').length, 1,
    'Regeneration must preserve the previous compression flow for review');
  const beforeVideoStudy = page.children.length;
  await figma.ui.onmessage({ type: 'generate-video-inspect-controls-study', bytes: [1, 2, 3] });
  const videoStudies = page.children.filter(child => child.name.startsWith('Video Inspect v4 /'));
  assert.equal(videoStudies.length, 5, 'Include the default Focus state without a captured-frame preview');
  assert.equal(page.children.length, beforeVideoStudy + 5);
  for (const board of videoStudies) {
    const toolbar = board.findOne(child => child.name === '01 / Floating Toolbar');
    assert.deepEqual(toolbar.children.map(child => child.name),
      ['Capture Frame', 'Focus', 'Compare', 'Widget', 'More']);
    assert.ok(toolbar.findOne(child => child.name === 'Icon / videoFocus'), 'Focus uses the video-play icon');
    const capture = board.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125');
    if (board.name.endsWith('/ No Capture')) {
      assert.equal(capture, null, 'Default playback must have no screenshot preview');
      assert.equal(board.findOne(child => child.name === 'Capture Timecode'), null);
    } else {
      assert.equal(capture.width, 220, board.name + ': capture width must not scale');
      assert.equal(capture.height, 125, board.name + ': capture height must not scale');
    }
    const playback = board.findOne(child => child.name === '02 / Floating Playback Controls');
    assert.equal(playback.height, 64, board.name + ': playback height must not scale');
    const play = playback.findOne(child => child.name === 'Play / Pause');
    assert.equal(play.width, 38);
    assert.equal(play.height, 38);
    for (const name of ['Current Time', 'Duration']) {
      const label = playback.findOne(child => child.name === name);
      assert.equal(label.fontSize, 12, board.name + ': time text must remain readable');
      assert.equal(label.height, 16);
    }
    const timeline = playback.findOne(child => child.name === 'Timeline / hit area');
    assert.ok(timeline.width >= 60, 'The narrowest window still has a usable seek area');
    assert.equal(timeline.findOne(child => child.name === 'Timeline Track').height, 4);
    assert.equal(timeline.findOne(child => child.name === 'Timeline Knob').width, 14);
    if (capture) assert.ok(capture.y + capture.height <= playback.y - 24, 'Capture must clear playback controls');
    const strip = board.findOne(child => child.name === '04 / Video Filmstrip / fixed 96 × 96');
    assert.ok(strip, board.name + ': video navigation must exist in both Focus and Compare');
    assert.equal(strip.children.length, 2);
    for (const tile of strip.children) {
      assert.equal(tile.width, 96);
      assert.equal(tile.height, 96);
    }
    assert.ok(strip.y + strip.height <= playback.y - 20);
    if (capture) assert.ok(capture.x + capture.width <= strip.x ||
      strip.x + strip.width <= capture.x || capture.y + capture.height <= strip.y - 24,
    board.name + ': capture preview and video thumbnails must not overlap');
    const controls = board.findOne(child => child.name === 'System / Window Controls / Bare');
    if (board.width < 520) assert.ok(toolbar.y >= controls.y + controls.height, 'Narrow toolbar must clear traffic lights');
    function assertContained(parent) {
      for (const child of parent.children) {
        assert.ok(child.x >= -0.001 && child.y >= -0.001, board.name + ': ' + child.name + ' starts outside parent');
        assert.ok(child.x + child.width <= parent.width + 0.001, board.name + ': ' + child.name + ' clips horizontally');
        assert.ok(child.y + child.height <= parent.height + 0.001, board.name + ': ' + child.name + ' clips vertically');
        assertContained(child);
      }
    }
    assertContained(board);
    for (const artwork of board.findAll(child => child.name === 'Full frame / aspect fit')) {
      assert.equal(artwork.fills[0].scaleMode, 'FIT', 'Preview artwork must show the complete image');
    }
  }
  const comparison = videoStudies.find(child => child.name === 'Video Inspect v4 / Compare');
  const filmstrip = comparison.findOne(child => child.name === '04 / Video Filmstrip / fixed 96 × 96');
  for (const tile of filmstrip.children) {
    assert.equal(tile.width, 96);
    assert.equal(tile.height, 96);
  }
  await figma.ui.onmessage({ type: 'generate-video-inspect-controls-study' });
  assert.equal(page.children.length, beforeVideoStudy + 5, 'Video study rerun must preserve existing review frames');
  // Upgrade an existing four-frame review, including edits made in Figma.
  videoStudies.find(child => child.name.endsWith('/ No Capture')).remove();
  const landscape = videoStudies.find(child => child.name.endsWith('/ Landscape'));
  landscape.findOne(child => child.name === 'Current Time').characters = '00:38';
  await figma.ui.onmessage({ type: 'generate-video-inspect-controls-study' });
  const noCapture = page.children.find(child => child.name === 'Video Inspect v4 / Focus / No Capture');
  assert.ok(noCapture);
  assert.equal(page.children.length, beforeVideoStudy + 5, 'Existing four-frame review gains exactly one state');
  assert.equal(noCapture.findOne(child => child.name === 'Current Time').characters, '00:38',
    'Default state must preserve the reviewed source design');
  assert.equal(noCapture.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125'), null);
  assert.ok(landscape.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125'),
    'Original capture-state frame must remain intact');
  for (const original of videoStudies.filter(child => !child.name.endsWith('/ No Capture'))) {
    assert.ok(page.children.includes(original), 'Previously reviewed frames must not be replaced');
  }
  // Existing five-frame files need the missing Focus strips patched in place.
  const focusBoards = page.children.filter(child => child.name.startsWith('Video Inspect v4 / Focus /'));
  for (const board of focusBoards) {
    board.findOne(child => child.name === '04 / Video Filmstrip / fixed 96 × 96').remove();
    const capture = board.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125');
    if (capture) capture.y = board.height - 24 - 64 - 24 - 125;
  }
  const reviewedControls = landscape.findOne(child => child.name === '02 / Floating Playback Controls');
  await figma.ui.onmessage({ type: 'generate-video-inspect-controls-study' });
  assert.equal(page.children.length, beforeVideoStudy + 5, 'Fix existing Focus frames without duplicating boards');
  for (const board of focusBoards) {
    assert.ok(page.children.includes(board));
    const strip = board.findOne(child => child.name === '04 / Video Filmstrip / fixed 96 × 96');
    assert.ok(strip, board.name + ': existing frame gains the missing filmstrip');
    const capture = board.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125');
    if (capture && board.width <= 560) assert.ok(capture.y + capture.height <= strip.y - 24);
  }
  assert.equal(landscape.findOne(child => child.name === '02 / Floating Playback Controls'), reviewedControls);
  assert.equal(reviewedControls.findOne(child => child.name === 'Current Time').characters, '00:38');
  assert.equal(noCapture.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125'), null);
  await figma.ui.onmessage({ type: 'generate-video-inspect-controls-study' });
  for (const board of focusBoards) {
    assert.equal(board.findAll(child => child.name === '04 / Video Filmstrip / fixed 96 × 96').length, 1,
      'Rerunning must not duplicate the video filmstrip');
  }
  console.log('All screen generators pass, including Video Inspect v4: consistent Focus/Compare sizes, no clipped controls, and idempotent generation');
})().catch(error => { console.error(error); process.exitCode = 1; });
