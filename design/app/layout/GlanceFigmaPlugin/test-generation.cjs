const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

let nextNodeID = 0;
function node(type) {
  return {
    id: 'mock:' + (++nextNodeID),
    type,
    name: '',
    x: 0,
    y: 0,
    width: 0,
    height: type === 'TEXT' ? 16 : 0,
    children: [],
    resize(width, height) { this.width = width; this.height = height; },
    appendChild(child) {
      assert.ok(['PAGE', 'FRAME', 'GROUP', 'COMPONENT', 'BOOLEAN_OPERATION'].includes(this.type),
        `${this.type} cannot contain child layers`);
      if (child.parent) child.parent.children.splice(child.parent.children.indexOf(child), 1);
      this.children.push(child);
      child.parent = this;
    },
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

function booleanOp(operation, nodes, parent) {
  const result = node('BOOLEAN_OPERATION');
  result.booleanOperation = operation;
  for (const child of nodes) { child.remove(); result.appendChild(child); }
  parent.appendChild(result);
  return result;
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
  createComponent: () => node('COMPONENT'),
  createRectangle: () => node('RECTANGLE'),
  createEllipse: () => node('ELLIPSE'),
  createText: () => node('TEXT'),
  createVector: () => node('VECTOR'),
  createNodeFromSvg: () => node('SVG'),
  union: (nodes, parent) => booleanOp('UNION', nodes, parent),
  subtract: (nodes, parent) => booleanOp('SUBTRACT', nodes, parent),
  createImage: bytes => ({
    hash: 'test-image-' + Array.from(bytes || []).join('-'),
    getSizeAsync: async () => ({ width: 1920, height: 1080 })
  }),
  widget: {
    register: () => {}
  }
};

const source = fs.readFileSync(__dirname + '/code.js', 'utf8');
const uiSource = fs.readFileSync(__dirname + '/ui.html', 'utf8');
assert.ok(uiSource.indexOf('<button id="generate-widget-flow"') < uiSource.indexOf('<label for="reference">'),
  'Widget flow action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-widget-oss-result"') < uiSource.indexOf('<label for="reference">'),
  'OSS result action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-widget-task-running-study"') < uiSource.indexOf('<label for="reference">'),
  'Widget task running study action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-widget-text-result-window"') < uiSource.indexOf('<label for="reference">'),
  'Widget text result side-window action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-pro-options"') < uiSource.indexOf('<label for="reference">'),
  'Pro entry layout options action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-pro-upgrade-entry"') < uiSource.indexOf('<label for="reference">'),
  'Pro upgrade entry action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-mask-draw-only"') < uiSource.indexOf('<label for="reference">'),
  'Draw-only mask pages action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-top-bar-height-study"') < uiSource.indexOf('<label for="reference">'),
  'Top bar height study action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-window-placement-study"') < uiSource.indexOf('<label for="reference">'),
  'Window placement study action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-widget-multi-image-input"') < uiSource.indexOf('<label for="reference">'),
  'Multi-image Widget input action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-home-folder-scroll-study"') < uiSource.indexOf('<label for="reference">'),
  'Home folder scroll study action must be visible near the top of the plugin');
assert.ok(uiSource.indexOf('<button id="generate-glance-scrollbar-system"') < uiSource.indexOf('<label for="reference">'),
  'Glance scrollbar system action must be visible near the top of the plugin');
assert.ok(uiSource.includes('<button id="replace-viewer-brand-images"'),
  'two-photo replacement action must be available in the plugin');
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
  const beforePhoto = node('RECTANGLE');
  beforePhoto.id = '38:3354';
  beforePhoto.name = 'input-09672AEE-FC4D-4116-B8F9-20E27300A34F 1';
  beforePhoto.fills = [{ type: 'IMAGE', imageHash: 'girl-a', scaleMode: 'CROP', opacity: .75 }];
  page.appendChild(beforePhoto);
  const afterPhoto = node('RECTANGLE');
  afterPhoto.id = '38:3356';
  afterPhoto.name = 'input-4146ACDB-17EC-42B8-98CE-E7BF4297D9D9 1';
  afterPhoto.fills = [{ type: 'IMAGE', imageHash: 'girl-b', scaleMode: 'FILL' }];
  page.appendChild(afterPhoto);
  const focusReuse = node('RECTANGLE');
  focusReuse.id = '49:3';
  focusReuse.fills = [{ type: 'IMAGE', imageHash: 'girl-b', scaleMode: 'CROP' }];
  page.appendChild(focusReuse);
  const unrelatedImage = node('RECTANGLE');
  unrelatedImage.fills = [{ type: 'IMAGE', imageHash: 'unrelated', scaleMode: 'FILL' }];
  page.appendChild(unrelatedImage);
  await figma.ui.onmessage({ type: 'replace-viewer-brand-images',
    beforeBytes: [1, 2], afterBytes: [3, 4] });
  assert.equal(beforePhoto.fills[0].imageHash, 'test-image-1-2');
  assert.equal(afterPhoto.fills[0].imageHash, 'test-image-3-4');
  assert.equal(focusReuse.fills[0].imageHash, 'test-image-3-4', 'Focus must reuse the edited landscape');
  assert.equal(beforePhoto.fills[0].scaleMode, 'CROP', 'existing image crop must survive replacement');
  assert.equal(beforePhoto.fills[0].opacity, .75, 'existing image opacity must survive replacement');
  assert.equal(unrelatedImage.fills[0].imageHash, 'unrelated', 'other images must stay unchanged');
  assert.equal(beforePhoto.name, 'Landscape / Natural Morning');
  assert.equal(afterPhoto.name, 'Landscape / Warm Sunrise');
  beforePhoto.remove();
  afterPhoto.remove();
  focusReuse.remove();
  unrelatedImage.remove();

  await figma.ui.onmessage({ type: 'generate-glance-scrollbar-system' });
  const scrollbarBoard = page.children.find(child => child.name === 'Glance / Scrollbar System');
  assert.ok(scrollbarBoard, 'shared scrollbar board should be created');
  const scrollbarComponents = scrollbarBoard.findAll(child => child.type === 'COMPONENT');
  assert.equal(scrollbarComponents.length, 4, 'both axes need idle and active reusable components');
  assert.ok(scrollbarBoard.findOne(child => child.name === 'Account / Scrollbar Application'));
  assert.equal(scrollbarBoard.findOne(child => child.name === 'Account Scroll Thumb / 4px').width, 4);
  const scrollbarCount = page.children.length;
  scrollbarBoard.findOne(child => child.name === 'Rules Title').characters = 'User-edited usage';
  await figma.ui.onmessage({ type: 'generate-glance-scrollbar-system' });
  assert.equal(page.children.length, scrollbarCount, 'rerun must preserve the existing scrollbar board');
  assert.equal(scrollbarBoard.findOne(child => child.name === 'Rules Title').characters, 'User-edited usage');
  scrollbarBoard.remove();

  await figma.ui.onmessage({ type: 'generate-result-badge-study' });
  const badgeStudy = page.children.find(child => child.name === 'Widget Result Badge Study');
  assert.ok(badgeStudy, 'result badge study should be created');
  const originalThumb = badgeStudy.findOne(child => child.name === 'Original Thumbnail / 96');
  const resultThumb = badgeStudy.findOne(child => child.name === 'Widget Result Thumbnail / 96');
  const badge = resultThumb.findOne(child => child.name === 'NEW Corner Badge / separate layer');
  const image = resultThumb.findOne(child => child.name === 'Image / no baked-in label');
  assert.equal(originalThumb.findOne(child => child.name === 'NEW Corner Badge / separate layer'), null);
  assert.equal(resultThumb.width, 96);
  assert.equal(badge.parent, resultThumb, 'NEW badge must be separate from image');
  assert.equal(image.type, 'RECTANGLE');
  assert.equal(badge.x + badge.width, resultThumb.width, 'badge must reach the top-right corner');
  assert.equal(badge.y, 0);
  assert.equal(badge.fills[0].color.r, 0x8F / 255);
  assert.ok(badgeStudy.findOne(child => child.name === 'Widget Result Thumbnail / 2x detail'));
  badgeStudy.remove();

  await figma.ui.onmessage({ type: 'generate-widget-multi-image-input', bytes: [1, 2, 3] });
  const multiAdd = page.children.find(child => child.name === 'Widget Input / 04 / Multi Image + Text / Add Image');
  const multiFull = page.children.find(child => child.name === 'Widget Input / 04 / Multi Image + Text / Four Images');
  assert.ok(multiAdd && multiFull, 'both multi-image input states must be created');
  assert.equal(multiAdd.width, 1554);
  assert.equal(multiFull.width, 1554);
  assert.equal(multiAdd.findOne(child => child.name === 'Image Count').characters, '3 / 4');
  assert.equal(multiFull.findOne(child => child.name === 'Image Count').characters, '4 / 4');
  assert.ok(multiAdd.findOne(child => child.name === 'Add Image / fourth slot'));
  assert.equal(multiFull.findOne(child => child.name === 'Add Image / fourth slot'), null,
    'the add control disappears when four images are selected');
  assert.equal(multiAdd.findAll(child => child.name.startsWith('Remove Image ')).length, 3);
  assert.equal(multiFull.findAll(child => child.name.startsWith('Remove Image ')).length, 4);
  assert.ok(multiAdd.findOne(child => child.name === 'Prompt Field'));
  assert.ok(multiFull.findOne(child => child.name === 'Run Widget Action'));
  multiAdd.findOne(child => child.name === 'Prompt Text').characters = 'User-edited prompt';
  const multiCount = page.children.length;
  await figma.ui.onmessage({ type: 'generate-widget-multi-image-input', bytes: null });
  assert.equal(page.children.length, multiCount, 'rerun must not duplicate multi-image frames');
  assert.equal(multiAdd.findOne(child => child.name === 'Prompt Text').characters, 'User-edited prompt',
    'rerun must preserve edited prompt text');
  multiAdd.remove();
  multiFull.remove();

  await figma.ui.onmessage({ type: 'generate-widget-task-running-study', bytes: [1, 2, 3] });
  const focusedRunning = page.children.find(child => child.name === 'Image Inspect / Widget Task Running / Focused Source');
  const browsingRunning = page.children.find(child => child.name === 'Image Inspect / Widget Task Running / Browsing Another Image');
  assert.ok(focusedRunning && browsingRunning, 'both task-running states must be created');
  assert.equal(focusedRunning.width, 1554);
  assert.equal(focusedRunning.height, 1012);
  assert.equal(focusedRunning.fills[0].type, 'IMAGE', 'focused state uses the selected photo');
  assert.equal(focusedRunning.findOne(child => child.name === 'Task running text').characters, 'Task running');
  const mainRing = focusedRunning.findOne(child => child.name === 'Main Image / breathing border / pulse peak');
  assert.equal(mainRing.x, 8);
  assert.equal(mainRing.y, 12);
  assert.equal(mainRing.strokeWeight, 2);
  assert.equal(mainRing.strokes[0].opacity, .80);
  assert.equal(focusedRunning.findOne(child => child.name === 'Filmstrip / existing 61.44px thumbnails'), null,
    'the focused preview demonstrates that the main cue remains visible with the filmstrip hidden');
  assert.equal(browsingRunning.findOne(child => child.name === 'Task running text'), null);
  const runningStrip = browsingRunning.findOne(child => child.name === 'Filmstrip / existing 61.44px thumbnails');
  assert.ok(runningStrip);
  const runningSource = runningStrip.findOne(child => child.name === 'Source / task breathing');
  const selectedOther = runningStrip.findOne(child => child.name === 'Other image / selected');
  assert.equal(runningSource.width, 96 * .8 * .8, 'task source retains the existing thumbnail size');
  assert.equal(selectedOther.width, runningSource.width);
  assert.ok(runningSource.effects.length > 0, 'running thumbnail shows its breathing glow');
  const runningFrameCount = page.children.length;
  focusedRunning.findOne(child => child.name === 'Task running text').characters = 'User edited label';
  await figma.ui.onmessage({ type: 'generate-widget-task-running-study', bytes: null });
  assert.equal(page.children.length, runningFrameCount, 'rerun must not duplicate task-running states');
  assert.equal(focusedRunning.findOne(child => child.name === 'Task running text').characters, 'User edited label',
    'rerun must preserve manual Figma edits');
  focusedRunning.remove();
  browsingRunning.remove();

  await figma.ui.onmessage({ type: 'generate-pro-options' });
  const optionsBoard = page.children.find(child => child.name === 'Home / Pro Entry / Layout Options');
  assert.ok(optionsBoard, 'the layout options board must be created');
  const optionWindows = ['A · Card in the content column', 'B · In the action row', 'C · Pill in the titlebar',
    'D · Card in the Recent column', 'E · Footer bar'].map(name => optionsBoard.findOne(child => child.name === 'Home / Option ' + name));
  assert.ok(optionWindows.every(Boolean), 'all five options are drawn');
  for (const win of optionWindows) {
    assert.equal(win.width, 1080);
    assert.equal(win.height, 720);
    assert.ok(win.findOne(child => child.name === 'Drop Zone') && win.findOne(child => child.name === 'Recent Title'), win.name + ': the same Home window');
    assert.ok(win.findOne(child => child.name === 'Open Files… Action'), win.name + ': the open actions stay');
  }
  const actionsBottom = optionWindows[0].findOne(child => child.name === 'Open Files… Action').y + 36;
  const [windowA, windowB, windowC, windowD, windowE] = optionWindows;
  const cardA = windowA.findOne(child => child.name === 'Pro Card');
  assert.equal(cardA.x, 40, 'A lines up with the 40 pt content edge');
  assert.equal(cardA.x + cardA.width, 660, 'A ends at the drop zone right edge');
  assert.ok(cardA.y >= actionsBottom + 16, 'A sits below the actions with room');
  assert.ok(cardA.y + cardA.height <= 690 - 16, 'A stays above the status bar');
  assert.ok(cardA.findOne(child => child.name === 'Price').findOne(child => child.name === 'Price').characters === '$9.99');
  const buttonB = windowB.findOne(child => child.name === 'Upgrade to Pro Button');
  assert.equal(buttonB.x + buttonB.width, 660, 'B is right-aligned to the drop zone');
  assert.ok(buttonB.x >= windowB.findOne(child => child.name === 'Open Folder… Action').x + 150 + 12, 'B does not touch Open Folder');
  assert.ok(windowC.findOne(child => child.name === 'Pro Pill'), 'C has the titlebar pill');
  assert.equal(windowC.findOne(child => child.name === 'Pro Card'), null, 'C adds nothing to the body');
  assert.equal(windowC.findOne(child => child.name === 'Pro Pill').parent, windowC);
  const cardD = windowD.findOne(child => child.name === 'Pro Card');
  assert.ok(cardD.x >= 700, 'D is in the Recent column');
  const tilesBottom = Math.max(...windowD.findAll(child => child.name.startsWith('Recent Tile ')).map(tile => tile.y + tile.height));
  assert.ok(cardD.y >= tilesBottom + 16 || cardD.y >= 136 + 164 + 148 + 16, 'D does not cover the recent tiles');
  assert.ok(cardD.x + cardD.width <= 1080 - 24);
  const barE = windowE.findOne(child => child.name === 'Pro Footer Bar');
  assert.equal(barE.y + barE.height, 690, 'E sits right above the status bar');
  assert.equal(barE.width, 700, 'E spans the open surface');
  const optionsCount = page.children.length;
  await figma.ui.onmessage({ type: 'generate-pro-options' });
  assert.equal(page.children.length, optionsCount, 'rerun must not duplicate the layout options');
  optionsBoard.remove();

  await figma.ui.onmessage({ type: 'generate-pro-upgrade-entry' });
  const proBoard = page.children.find(child => child.name === 'Home / Pro Upgrade Entry / Redesign');
  assert.ok(proBoard, 'the Pro upgrade entry board must be created');
  const oldPro = proBoard.findOne(child => child.name === 'Upgrade to Pro Button (current)');
  assert.equal(oldPro.height, 36);
  const proButtons = proBoard.findAll(child => child.name === 'Upgrade to Pro Button');
  assert.equal(proButtons.length, 9, 'the proposal, the four states, the narrow window, the launch price and the two flame versions');
  const defaultPro = proButtons.find(button => button.parent.name === 'After / Home cut');
  assert.ok(defaultPro, 'the proposed block is in the Home cut');
  assert.equal(defaultPro.height, 44, 'the button is 44 pt high');
  assert.equal(defaultPro.width, 288);
  assert.equal(defaultPro.cornerRadius, 12);
  assert.equal(Math.round(defaultPro.fills[0].color.r * 255), 0xE8, 'accent fill');
  const caption = defaultPro.parent.findOne(child => child.name === 'Caption');
  assert.equal(caption.textAlignHorizontal, 'CENTER', 'the caption is centered');
  assert.equal(caption.x + caption.width / 2, defaultPro.x + defaultPro.width / 2, 'the caption is centered on the button');
  assert.equal(defaultPro.parent.width / 2, defaultPro.x + defaultPro.width / 2, 'the block is centered in the Home cut');
  const labelNode = defaultPro.findOne(child => child.name === 'Label');
  assert.equal(labelNode.fontSize, 15, 'the label is 15 pt');
  assert.equal(labelNode.fontName.style, 'Semi Bold', 'the label is semibold');
  const pricePill = defaultPro.findOne(child => child.name === 'Price Pill');
  assert.ok(pricePill, 'the price sits in its own pill');
  assert.equal(pricePill.findOne(child => child.name === 'Price').characters, '$9.99');
  assert.equal(pricePill.findOne(child => child.name === 'Price').fontSize, 17, 'the price is 17 pt, larger than the label');
  assert.equal(pricePill.findOne(child => child.name === 'Price Prefix').characters, 'from');
  assert.equal(Math.round(pricePill.fills[0].color.r * 255), 0x21, 'the pill is dark ink so the accent price pops');
  assert.ok(pricePill.height >= 28 && pricePill.height < defaultPro.height, 'the pill sits inside the button');
  const launchCard = proBoard.findOne(child => child.name === 'Launch / Home cut');
  const launchTag = launchCard.findOne(child => child.name === 'Launch Tag');
  assert.ok(launchTag && launchTag.findOne(child => child.name === 'Flame').type === 'VECTOR', 'the launch tag has a vector flame');
  assert.equal(launchTag.findOne(child => child.name === 'Launch Text').characters, 'Launch price');
  assert.ok(pricePill.findOne(child => child.name === 'Flame').type === 'VECTOR', 'the main button shows a vector flame next to the price');
  const emojiButton = proBoard.findOne(child => child.name === 'Flame / Emoji').findOne(child => child.name === 'Upgrade to Pro Button');
  assert.equal(emojiButton.findOne(child => child.name === 'Flame Emoji').characters, '🔥', 'the emoji version uses the system fire emoji');
  assert.equal(emojiButton.findOne(child => child.name === 'Label').characters, '✨ Upgrade to Pro');
  assert.equal(emojiButton.findOne(child => child.name === 'Flame'), null, 'the emoji version has no vector flame');
  const vectorButton = proBoard.findOne(child => child.name === 'Flame / Vector').findOne(child => child.name === 'Upgrade to Pro Button');
  assert.ok(vectorButton.findOne(child => child.name === 'Flame'), 'the vector version has the flame');
  const fireTexts = proBoard.findAll(child => child.type === 'TEXT' && /\u{1F525}/u.test(child.characters)).map(child => child.name);
  assert.ok(fireTexts.length > 0 && fireTexts.every(name => ['Flame Emoji', 'Emoji Label', 'Spec Text 2'].includes(name)),
    'the fire emoji appears only in the emoji version and its labels, got ' + fireTexts.join(', '));
  const byState = name => proBoard.findOne(child => child.name === 'State / ' + name);
  assert.ok(byState('Keyboard focus').findOne(child => child.name === 'Upgrade to Pro Button / focus ring'), 'focus shows a ring');
  const pressedButton = byState('Pressed').findOne(child => child.name === 'Upgrade to Pro Button');
  assert.ok(pressedButton.width < 288 && pressedButton.height < 44, 'pressed scales the button down');
  assert.equal((pressedButton.effects || []).length, 0, 'pressed has no glow');
  assert.notEqual(Math.round(byState('Hover').findOne(child => child.name === 'Upgrade to Pro Button').fills[0].color.g * 255),
    Math.round(defaultPro.fills[0].color.g * 255), 'hover has its own fill');
  assert.ok(proBoard.findOne(child => child.name === 'Compact / Home cut').findOne(child => child.name === 'Caption'),
    'the caption stays in a narrow window');
  const proCount = page.children.length;
  await figma.ui.onmessage({ type: 'generate-pro-upgrade-entry' });
  assert.equal(page.children.length, proCount, 'rerun must not duplicate the Pro upgrade entry board');
  proBoard.remove();

  await figma.ui.onmessage({ type: 'generate-mask-draw-only', bytes: [4, 4] });
  const drawNames = ['Widget Input / 03 / Image + Text + Mask / Draw Only', 'Widget Input / 03B / Image + Mask Only / Draw Only',
    'Widget Input / Draw Mask / Brush Only'];
  const [drawWithText, drawMaskOnly, brushEditor] = drawNames.map(name => page.children.find(child => child.name === name));
  assert.ok(drawWithText && drawMaskOnly && brushEditor, 'all three draw-only mask pages must be created');
  const drawActionNames = frameNode => frameNode.findAll(child => child.name.endsWith(' Action')).map(child => child.name);
  for (const input of [drawWithText, drawMaskOnly]) {
    assert.ok(drawActionNames(input).includes('Draw mask Action'), input.name + ': Draw mask is offered');
    assert.ok(!drawActionNames(input).includes('Upload mask Action'), input.name + ': no upload option');
    assert.ok(!input.findOne(child => child.name === 'Mask File'), input.name + ': no uploaded-file line');
    const preview = input.findOne(child => child.name === 'Selected Image');
    assert.equal(preview.fills[0].imageHash, 'test-image-4-4', input.name + ': real photo');
  }
  assert.ok(drawWithText.findOne(child => child.name === 'Prompt Field'), 'a Widget with a prompt shows the prompt field');
  assert.equal(drawMaskOnly.findOne(child => child.name === 'Prompt Field'), null, 'a Widget without a prompt shows no prompt field');
  assert.equal(drawMaskOnly.findOne(child => child.name === 'Prompt Field / disabled'), null, 'not even a disabled one');
  assert.equal(drawMaskOnly.findOne(child => child.name === 'Prompt Label'), null);
  const maskFieldOnly = drawMaskOnly.findOne(child => child.name === 'Mask Field');
  assert.equal(maskFieldOnly.y, 137, 'the mask moves up into the space the prompt would take');
  assert.equal(brushEditor.findOne(child => child.name === 'Mask Tools').findAll(child => child.name.endsWith(' Action')
    && ['Brush Action', 'Erase Action'].includes(child.name)).map(child => child.name).join(','), 'Brush Action',
    'the tools panel has only the brush');
  assert.equal(brushEditor.findOne(child => child.name === 'Erase Action'), null, 'no eraser');
  const brushAction = brushEditor.findOne(child => child.name === 'Brush Action');
  assert.equal(brushAction.width, 261, 'the single Brush button fills the tools panel');
  assert.equal(Math.round(brushAction.fills[0].color.r * 255), 0xE8, 'the Brush tool is selected by default (accent fill)');
  const strokes = brushEditor.findAll(child => child.name === 'Mask Brush Stroke');
  assert.ok(strokes.length > 0);
  for (const stroke of strokes) {
    const color = stroke.fills[0].color;
    assert.equal([color.r, color.g, color.b].map(value => Math.round(value * 255)).join(','), '232,168,124',
      'brush strokes use the Glance accent color');
  }
  const cursorRing = brushEditor.findOne(child => child.name.startsWith('Brush Cursor'));
  assert.ok(cursorRing && cursorRing.width === cursorRing.height, 'the pointer is a circle');
  assert.equal(cursorRing.fills.length, 0, 'the circle is an outline, not a filled dot');
  const drawCount = page.children.length;
  await figma.ui.onmessage({ type: 'generate-mask-draw-only', bytes: [4, 4] });
  assert.equal(page.children.length, drawCount, 'rerun must not duplicate the draw-only pages');
  drawWithText.remove(); drawMaskOnly.remove(); brushEditor.remove();

  await figma.ui.onmessage({ type: 'generate-top-bar-height-study', landscape: [1, 1] });
  const heightStudy = page.children.find(child => child.name === 'Window Placement / Top Bar Height Study');
  assert.ok(heightStudy, 'the top bar height study must be created');
  const heightWindows = heightStudy.findAll(child => child.name.startsWith('Window / Top Bar '));
  assert.deepEqual(Array.from(heightWindows.map(win => win.name)),
    ['Window / Top Bar 56 pt', 'Window / Top Bar 44 pt', 'Window / Top Bar 36 pt', 'Window / Top Bar 28 pt']);
  for (const win of heightWindows) {
    const barHeight = Number(win.name.match(/(\d+) pt/)[1]);
    const bar = win.findOne(child => child.name === '00 / Titlebar');
    assert.equal(bar.height, barHeight);
    const photo = win.findOne(child => child.name === 'Photo');
    assert.equal(photo.y, barHeight, win.name + ': the photo starts under the bar');
    assert.equal(photo.height, 384, win.name + ': the media area is identical in every variant');
    assert.equal(win.height, 384 + barHeight, win.name + ': the window grows by the bar height');
    assert.equal(win.findOne(child => child.name === '01 / Floating Toolbar').y, barHeight + 24);
    assert.equal(bar.findOne(child => child.name === 'Close').y, Math.round((barHeight - 12) / 2), win.name + ': controls centered');
    assert.equal(photo.fills[0].type, 'IMAGE', win.name + ': real photo');
    assert.equal(bar.findOne(child => child.name === 'Window Title'), null, win.name + ': no title prefix, just the filename');
    assert.equal(bar.findOne(child => child.name === 'Separator'), null);
    assert.equal(bar.findOne(child => child.name === 'Filename').characters, 'alpine-lake.jpg');
  }
  const heightCount = page.children.length;
  await figma.ui.onmessage({ type: 'generate-top-bar-height-study', landscape: [1, 1] });
  assert.equal(page.children.length, heightCount, 'rerun must not duplicate the height study');
  heightStudy.remove();

  await figma.ui.onmessage({ type: 'generate-window-placement-study', landscape: [1, 1], portrait: [2, 2] });
  const placementPrefix = 'Window Placement / ';
  const placementNames = {
    imageLandscape: 'Image Inspect / Landscape',
    imagePortrait: 'Image Inspect / Portrait',
    videoLandscape: 'Video Inspect / Landscape',
    videoPortrait: 'Video Inspect / Portrait',
    imageLandscapeBar: 'Image Inspect / Landscape / Top Bar',
    imagePortraitBar: 'Image Inspect / Portrait / Top Bar',
    videoLandscapeBar: 'Video Inspect / Landscape / Top Bar',
    videoPortraitBar: 'Video Inspect / Portrait / Top Bar',
    imageLandscapeBarHidden: 'Image Inspect / Landscape / Top Bar / Toolbar hidden',
    imagePortraitBarHidden: 'Image Inspect / Portrait / Top Bar / Toolbar hidden',
    imageLandscapeBarRunning: 'Image Inspect / Landscape / Top Bar / Task running',
    imagePortraitBarRunning: 'Image Inspect / Portrait / Top Bar / Task running'
  };
  const placementDesktops = {};
  for (const [key, name] of Object.entries(placementNames)) {
    placementDesktops[key] = page.children.find(child => child.name === placementPrefix + name);
    assert.ok(placementDesktops[key], name + ' must be created');
  }
  const placementSpec = page.children.find(child => child.name === 'Window Placement / Spec');
  assert.ok(placementSpec, 'the spec card must be created');
  for (const [key, desktop] of Object.entries(placementDesktops)) {
    const hasBar = key.includes('Bar');
    const isPortrait = key.includes('Portrait');
    const win = desktop.findOne(child => child.name.startsWith('Window / '));
    assert.ok(win, key + ' must contain its window');
    assert.equal(win.parent, desktop);
    const usable = desktop.findOne(child => child.name === 'Usable screen area (visibleFrame)');
    const topGap = win.y - usable.y;
    const bottomGap = usable.y + usable.height - (win.y + win.height);
    assert.equal(topGap, bottomGap, key + ': top and bottom gaps must be equal');
    assert.ok(win.height / usable.height <= 0.88 + 0.005, key + ': window height stays within 88% of the usable area');
    assert.ok(topGap / usable.height >= 0.05, key + ': the window must leave a visible gap below the menu bar');
    assert.equal(win.x * 2 + win.width, desktop.width, key + ': window is centered horizontally');
    assert.equal(usable.y, desktop.findOne(child => child.name === 'Menu Bar').height, 'usable area starts below the menu bar');
    const ghost = desktop.findOne(child => child.name === 'Current window ceiling (96%)');
    assert.ok(ghost.y - usable.y < topGap, key + ': the current 96% ceiling leaves a smaller gap');
    assert.ok(desktop.findOne(child => child.name === 'Proposed top gap / label'));
    assert.ok(desktop.findOne(child => child.name === 'Dock'));
    const photoNode = win.findOne(child => child.name === 'Photo') || win;
    const photoFill = (photoNode.fills || []).find(paint => paint.type === 'IMAGE');
    assert.ok(photoFill, key + ': the window must show a real photo');
    assert.equal(photoFill.imageHash, isPortrait ? 'test-image-2-2' : 'test-image-1-1',
      key + ': landscape scenes use the landscape photo, portrait scenes the portrait photo');
    assert.equal(win.width < win.height, isPortrait, key + ': orientation');
    assert.equal(!!win.findOne(child => child.name === '02 / Floating Playback Controls'), key.startsWith('video'),
      key + ': only video windows carry the playback bar');
    if (key.startsWith('video') && isPortrait) {
      assert.ok(win.findOne(child => child.name === '02 / Floating Playback Controls').width <= 570 - 48,
        'the playback bar fits inside the portrait window');
    }
    const expectedLabel = key.endsWith('BarHidden') ? 'B  ·  Top bar  ·  toolbar hidden'
      : key.endsWith('BarRunning') ? 'B  ·  Top bar  ·  task running'
      : hasBar ? 'B  ·  With top bar (always shown)' : 'A  ·  Floating window controls (current)';
    assert.equal(desktop.findOne(child => child.name === 'Style Label').characters, expectedLabel);
    const toolbar = win.findOne(child => child.name === '01 / Floating Toolbar');
    assert.ok(toolbar, key + ': every window has the floating toolbar');
    const bar = win.findOne(child => child.name === '00 / Titlebar');
    if (!hasBar) {
      if (key !== 'imageLandscape') assert.ok(win.findOne(child => child.name === 'System / Window Controls'), key + ': floating controls');
      assert.equal(bar, null, key + ': no top bar in the A scenes');
      continue;
    }
    assert.equal(win.findOne(child => child.name === 'System / Window Controls'), null, key + ': no floating controls pill');
    assert.ok(bar, key + ': the B scenes have a top bar');
    assert.equal(bar.height, 28, key + ': the top bar is 28 pt high (the standard macOS title bar)');
    assert.equal(bar.width, win.width);
    const chromeFill = bar.fills[0].color;
    assert.equal(Math.round(chromeFill.r * 255), 0x17, key + ': solid chrome fill (red)');
    assert.equal(Math.round(chromeFill.g * 255), 0x18, key + ': solid chrome fill (green)');
    assert.equal(Math.round(chromeFill.b * 255), 0x1D, key + ': solid chrome fill (blue)');
    assert.equal(['Close', 'Minimize', 'Zoom'].map(name => bar.findOne(child => child.name === name).x).join(','), '24,44,64');
    assert.equal(bar.findOne(child => child.name === 'Close').y, 8, key + ': controls centered in 28 pt');
    assert.equal(bar.findOne(child => child.name === 'Window Title'), null, key + ': no "Image Inspect" / "Video Inspect" prefix');
    assert.equal(bar.findOne(child => child.name === 'Separator'), null);
    const filename = bar.findOne(child => child.name === 'Filename');
    assert.equal(filename.characters, key.startsWith('video') ? 'clip.mov' : (isPortrait ? 'portrait.jpg' : 'alpine-lake.jpg'));
    assert.equal(filename.textAlignHorizontal, 'CENTER', key + ': the filename is centered');
    assert.equal(filename.width, win.width);
    assert.equal(filename.y, 6);
    assert.equal(filename.fontSize, 12);
    assert.equal(bar.findOne(child => child.name === 'Titlebar Divider').y, 27);
    assert.equal(photoNode.y, 28, key + ': the photo starts directly below the title bar');
    assert.equal(photoNode.height, win.height - 28);
    assert.equal(toolbar.y, 28 + 24, key + ': the toolbar floats 24 pt below the top bar');
    assert.notEqual(bar.opacity, 0, key + ': the top bar is always shown');
    if (key.endsWith('BarHidden')) {
      assert.equal(toolbar.opacity, 0, key + ': only the toolbar fades out');
      assert.ok(win.findOne(child => child.name === 'Auto-hide message'));
      assert.equal(win.height, 1012, key + ': the window keeps its size, the bar stays');
    } else {
      assert.notEqual(toolbar.opacity, 0);
      assert.equal(win.findOne(child => child.name === 'Auto-hide message'), null);
    }
    if (key.endsWith('BarRunning')) {
      const indicator = win.findOne(child => child.name === 'Task running indicator');
      assert.ok(indicator, key + ': running indicator');
      assert.equal(indicator.x + indicator.width + 24, win.width, key + ': indicator at the row\'s right end');
      assert.equal(indicator.y, 28 + 24 + (54 - 34) / 2, key + ': indicator centered on the toolbar row');
      if (!isPortrait) assert.ok(toolbar.x + toolbar.width + 12 <= indicator.x, key + ': toolbar leaves room for the indicator');
      assert.ok(win.findOne(child => child.name === 'Main Image / breathing border'));
      assert.equal(win.findOne(child => child.name === 'Task running text').characters, 'Remove Background  ·  Task running');
    } else {
      assert.equal(win.findOne(child => child.name === 'Task running indicator'), null);
    }
  }
  assert.ok(placementDesktops.videoLandscape.y > placementDesktops.imageLandscape.y, 'video scenes sit on the second row');
  assert.ok(placementDesktops.imageLandscapeBar.y > placementDesktops.videoLandscape.y + placementDesktops.videoLandscape.height,
    'top bar scenes sit below the floating-controls scenes');
  assert.ok(placementDesktops.imageLandscapeBarHidden.y > placementDesktops.videoLandscapeBar.y + placementDesktops.videoLandscapeBar.height,
    'state scenes sit below the top bar scenes');
  assert.ok(placementDesktops.imagePortrait.x > placementDesktops.imageLandscape.x + placementDesktops.imageLandscape.width,
    'portrait scenes sit in the second column without overlapping');
  assert.ok(placementSpec.y > placementDesktops.imagePortraitBarRunning.y + placementDesktops.imagePortraitBarRunning.height, 'spec card sits below all scenes');
  const placementCount = page.children.length;
  await figma.ui.onmessage({ type: 'generate-window-placement-study', landscape: [1, 1], portrait: [2, 2] });
  assert.equal(page.children.length, placementCount, 'rerun must not duplicate the placement frames');

  // A user who already generated the first four scenes (and the spec) gets only the new scenes added,
  // below everything that exists, and the existing frames are untouched.
  const newKeys = Object.keys(placementNames).filter(key => key.includes('Bar'));
  newKeys.forEach(key => placementDesktops[key].remove());
  placementSpec.y = placementDesktops.videoPortrait.y + placementDesktops.videoPortrait.height + 160;
  const before = ['imageLandscape', 'videoPortrait'].map(key => [placementDesktops[key].x, placementDesktops[key].y]);
  await figma.ui.onmessage({ type: 'generate-window-placement-study', landscape: [1, 1], portrait: [2, 2] });
  const regeneratedBarScenes = newKeys.map(key => page.children.find(child => child.name === placementPrefix + placementNames[key]));
  assert.ok(regeneratedBarScenes.every(Boolean), 'missing top bar scenes are created');
  assert.deepEqual(['imageLandscape', 'videoPortrait'].map(key => [placementDesktops[key].x, placementDesktops[key].y]), before,
    'existing scenes must not move');
  for (const desktop of regeneratedBarScenes) {
    assert.ok(desktop.y >= placementSpec.y + placementSpec.height, 'new scenes start below the existing spec card');
  }
  assert.equal(page.children.filter(child => child.name === 'Window Placement / Spec').length, 1, 'the spec card is not duplicated');
  Object.values(placementDesktops).forEach(desktop => desktop.remove());
  regeneratedBarScenes.forEach(desktop => desktop.remove());
  placementSpec.remove();

  await figma.ui.onmessage({ type: 'generate-widget-text-result-window', bytes: [1, 2, 3] });
  const textResultMain = page.children.find(child => child.name === 'Image Inspect / Widget Text Result / Main Image');
  const textResultWindow = page.children.find(child => child.name === 'Widget Output / Text / Side Window');
  assert.ok(textResultMain && textResultWindow, 'main image and text result must be separate windows');
  assert.equal(textResultMain.width, 1554);
  assert.equal(textResultMain.height, 1012);
  assert.equal(textResultWindow.width, 456);
  assert.equal(textResultWindow.height, 720);
  assert.equal(textResultWindow.x, textResultMain.x + textResultMain.width + 16);
  assert.equal(textResultWindow.y, textResultMain.y + 84);
  assert.equal(textResultWindow.findOne(child => child.name === 'Result Type').characters, 'TEXT RESULT');
  assert.ok(textResultWindow.findOne(child => child.name === 'Result Text / direct content'));
  const inputPreview = textResultWindow.findOne(child => child.name === 'Input Image Preview');
  assert.ok(inputPreview, 'the result window must show the input image');
  assert.equal(inputPreview.width, 128);
  assert.equal(inputPreview.height, 96);
  assert.equal(inputPreview.fills[0].type, 'IMAGE');
  assert.equal(textResultWindow.findOne(child => child.name === 'Input Filename').characters, 'portrait.jpg');
  assert.equal(textResultWindow.findOne(child => child.name === 'Content Divider').y, 250);
  assert.equal(textResultWindow.findOne(child => child.name === 'Result Text / direct content').y, 280);
  assert.equal(textResultWindow.findOne(child => child.name === 'Output Text Preview'), null,
    'text must be direct window content rather than an embedded preview card');
  const textResultCount = page.children.length;
  textResultWindow.findOne(child => child.name === 'Result Text / direct content').characters = 'User edited result';
  inputPreview.remove();
  await figma.ui.onmessage({ type: 'generate-widget-text-result-window', bytes: null });
  assert.equal(page.children.length, textResultCount, 'rerun must not duplicate text result windows');
  assert.ok(textResultWindow.findOne(child => child.name === 'Input Image Preview'),
    'rerun upgrades an existing result window that lacks the input preview');
  assert.equal(textResultWindow.findOne(child => child.name === 'Result Text / direct content').characters, 'User edited result',
    'rerun must preserve manual Figma edits');
  textResultMain.remove();
  textResultWindow.remove();

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

  await figma.ui.onmessage({ type: 'generate-home-folder-scroll-study' });
  const folderStudy = page.children.find(child => child.name === 'Home / Folder Scroll / Thin Track Study');
  assert.ok(folderStudy, 'Home folder scroll study should be created');
  assert.equal(folderStudy.width, 1080);
  assert.equal(folderStudy.height, 720);
  const folderStrip = folderStudy.findOne(child => child.name === 'Folder Thumbnails / Clipped');
  assert.ok(folderStrip && folderStrip.clipsContent);
  assert.ok(folderStrip.findOne(child => child.name === 'Scroll Track'));
  assert.ok(folderStrip.findOne(child => child.name === 'Draggable Thumb / 6 of 12 visible'));
  assert.ok(folderStrip.findOne(child => child.name === 'Next Images'));
  assert.equal(folderStrip.children.filter(child => child.name.startsWith('Image ')).length, 7);
  await figma.ui.onmessage({ type: 'generate-home-folder-scroll-study' });
  assert.equal(page.children.filter(child => child.name === folderStudy.name).length, 1);
  folderStudy.remove();

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
  assert.ok(redesigned.findOne(child => child.name === '01 / Widget Marketplace Window'));
  assert.ok(redesigned.findOne(child => child.name === '02 / Search and Widget List'));
  assert.ok(redesigned.findOne(child => child.name === '05 / Selected Widget Detail'));
  const marketList = redesigned.findOne(child => child.name === '04 / Scroll Content / 50 Widgets');
  assert.ok(marketList, 'Widget Market needs a dedicated scrolling list container');
  assert.equal(redesigned.findOne(child => child.name === '03 / Scroll Viewport / 7 of 50 visible').overflowDirection,
    'VERTICAL_SCROLLING');
  assert.equal(marketList.children.filter(child => child.name.startsWith('Widget ')).length, 50);
  assert.equal(marketList.children[0].name, 'Widget 01 / Remove Background');
  assert.equal(marketList.children[49].name, 'Widget 50 / OSS Publisher');
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
  const beforePlacement = page.children.length;
  await figma.ui.onmessage({ type: 'generate-task-running-placement' });
  const placement = page.children.find(child => child.name === 'Task Running Placement');
  assert.ok(placement, 'Task Running Placement must be generated');
  assert.equal(page.children.length, beforePlacement + 1);
  for (const scene of ['A / Small window 320 × 240', 'B / Compact window 480 × 360', 'C / Standard window 1554 × 1012', 'D / Task Center rows']) {
    assert.ok(placement.findOne(child => child.name === scene), `placement scene ${scene}`);
  }
  assert.ok(placement.findOne(child => child.name === 'Running Chip / full'), 'full chip in the standard window');
  assert.ok(placement.findOne(child => child.name === 'Running Chip / compact'), 'compact chip in the compact window');
  const smallWindow = placement.findOne(child => child.name === 'A / Small window 320 × 240');
  assert.equal(smallWindow.findAll(child => child.name.startsWith('Running Chip')).length, 0, 'no chip in the small window');
  assert.ok(smallWindow.findOne(child => child.name === 'Running Badge'), 'badge in the small window');
  assert.equal(placement.findAll(child => child.name === 'Running Badge').length, 3, 'badge in every window');
  assert.ok(placement.findAll(child => child.name.endsWith('/ running') && child.name.startsWith('Tile')).length === 3, 'one running tile per window');
  await figma.ui.onmessage({ type: 'generate-task-running-placement' });
  assert.equal(page.children.length, beforePlacement + 1, 'placement regeneration is idempotent');

  const beforeTaskCenter = page.children.length;
  await figma.ui.onmessage({ type: 'generate-task-center-redesign' });
  const taskCenter = page.children.find(child => child.name === 'Task Center Redesign');
  assert.ok(taskCenter, 'Task Center Redesign must be generated');
  assert.equal(page.children.length, beforeTaskCenter + 1);
  const tcScene = name => taskCenter.findOne(child => child.name === name);
  for (const scene of ['01 / Task Center / Running', '02 / Task Center / Done', '03 / Task Center / Failed', '04 / Task Center / Empty']) {
    assert.ok(tcScene(scene), `task center scene ${scene}`);
  }
  const actionNames = scene => scene.findAll(child => child.name.startsWith('Action / ')).map(child => child.name);
  assert.deepEqual(actionNames(tcScene('01 / Task Center / Running')).sort(), ['Action / Cancel', 'Action / Show Source']);
  assert.equal(actionNames(tcScene('01 / Task Center / Running')).length, 2);
  assert.equal(actionNames(tcScene('02 / Task Center / Done')).length, 4);
  assert.equal(actionNames(tcScene('03 / Task Center / Failed')).length, 2);
  assert.equal(actionNames(tcScene('04 / Task Center / Empty')).length, 0);
  for (const scene of ['01 / Task Center / Running', '02 / Task Center / Done', '03 / Task Center / Failed', '04 / Task Center / Empty']) {
    const node = tcScene(scene);
    assert.equal(node.findOne(child => child.name === '02 / Icon Toolbar'), null, 'grey toolbar band removed');
    assert.equal(node.findAll(child => child.name === 'Task Information' || child.name === 'Info').length, 0, 'Info button removed');
    assert.equal(node.findAll(child => child.name === 'Clear Finished').length, 1, 'clear finished lives once, in the list');
  }
  await figma.ui.onmessage({ type: 'generate-task-center-redesign' });
  assert.equal(page.children.length, beforeTaskCenter + 1, 'task center regeneration is idempotent');

  const beforeMarket = page.children.length;
  await figma.ui.onmessage({ type: 'generate-widget-market-redesign' });
  const market = page.children.find(child => child.name === 'Widget Market Redesign');
  assert.ok(market, 'Widget Market Redesign must be generated');
  assert.equal(page.children.length, beforeMarket + 1);
  const wmScene = name => market.findOne(child => child.name === name);
  for (const scene of ['01 / Widget Market / Marketplace', '02 / Widget Market / Installed', '03 / Widget Market / Updates', '04 / Widget Market / Search · Empty']) {
    assert.ok(wmScene(scene), `widget market scene ${scene}`);
    assert.equal(wmScene(scene).width, 448, 'panel width matches WidgetMarketPanel.designSize');
    assert.equal(wmScene(scene).height, 824, 'panel height matches WidgetMarketPanel.designSize');
  }
  const wmRows = scene => wmScene(scene).findAll(child => child.name.startsWith('Widget / '));
  const wmActions = row => row.findAll(child => child.name.startsWith('Action / ')).map(child => child.name);
  assert.equal(wmRows('01 / Widget Market / Marketplace').length, 6, 'six rows fit above the footer');
  for (const row of wmRows('01 / Widget Market / Marketplace')) {
    assert.equal(wmActions(row).length, 1, 'exactly one action per row');
    const action = row.findOne(child => child.name.startsWith('Action / '));
    assert.equal(row.findOne(child => child.name === 'Meta'), null, 'row has no version metadata');
    for (const label of ['Name', 'Summary']) {
      const node = row.findOne(child => child.name === label);
      assert.ok(node.x + node.width <= action.x, `${label} stops before the action`);
    }
  }
  assert.ok(wmRows('02 / Widget Market / Installed').every(row => wmActions(row)[0] !== 'Action / Install'), 'installed filter hides Install');
  assert.ok(wmRows('02 / Widget Market / Installed').every(row => wmActions(row)[0] !== 'Action / Remove'), 'hover never exposes Remove in the list');
  assert.ok(wmRows('03 / Widget Market / Updates').every(row => wmActions(row)[0] === 'Action / Update'), 'updates filter shows only Update');
  assert.equal(wmRows('04 / Widget Market / Search · Empty').length, 0);
  assert.ok(wmScene('04 / Widget Market / Search · Empty').findOne(child => child.name === 'Empty Title'), 'empty search state');
  assert.ok(market.findOne(child => child.name === 'Row States'), 'row state spec strip');
  await figma.ui.onmessage({ type: 'generate-widget-market-redesign' });
  assert.equal(page.children.length, beforeMarket + 1, 'widget market regeneration is idempotent');

  const beforeDetails = page.children.length;
  await figma.ui.onmessage({ type: 'generate-widget-market-details' });
  const details = page.children.find(child => child.name === 'Widget Market / Details + Loading');
  assert.ok(details, 'Widget detail and loading board must be generated');
  const scene = name => details.findOne(child => child.name === name);
  const browse = scene('01 / Widget Market / Browse');
  const installedDetail = scene('02 / Widget Details / Installed');
  const availableDetail = scene('03 / Widget Details / Not Installed');
  const updateDetail = scene('04 / Widget Details / Update Available');
  const freeDetail = scene('05 / Widget Details / Free');
  const loading = scene('06 / Widget Market / Loading');
  for (const panel of [browse, installedDetail, availableDetail, updateDetail, freeDetail, loading]) {
    assert.ok(panel);
    assert.equal(panel.width, 448);
    assert.equal(panel.height, 824);
  }
  assert.equal(browse.findAll(child => child.name === 'Action / Remove').length, 0, 'Remove is reserved for details');
  const firstRow = browse.findOne(child => child.name === 'Widget / Background Remover Pro');
  assert.equal(firstRow.reactions[0].actions[0].destinationId, installedDetail.id, 'card opens details');
  assert.equal(installedDetail.findOne(child => child.name === 'Action / Remove').reactions[0].actions[0].destinationId,
    availableDetail.id, 'Remove changes the detail page to the uninstalled state');
  assert.equal(availableDetail.findAll(child => child.name === 'Action / Remove').length, 0);
  assert.ok(availableDetail.findOne(child => child.name === 'Action / Install'));
  assert.ok(updateDetail.findOne(child => child.name === 'Action / Update'));
  assert.ok(updateDetail.findOne(child => child.name === 'Action / Remove'));
  for (const panel of [installedDetail, availableDetail, updateDetail, freeDetail]) {
    assert.equal(panel.findOne(child => child.name === 'Back to widgets').reactions[0].actions[0].destinationId, browse.id);
    assert.ok(panel.findOne(child => child.name === 'Task Price'));
    assert.ok(panel.findOne(child => child.name === 'Privacy Notice'));
  }
  assert.equal(freeDetail.findOne(child => child.name === 'Credit Cost').characters, 'Free');
  assert.equal(details.findOne(child => child.name === 'Publisher and Version'), null, 'details have no publisher/version line');
  assert.ok(loading.findOne(child => child.name === 'Loading Label'));
  assert.equal(loading.findAll(child => child.name.startsWith('Widget / ') || child.name === 'Empty Title').length, 0,
    'loading has neither fabricated results nor an empty state');
  await figma.ui.onmessage({ type: 'generate-widget-market-details' });
  assert.equal(page.children.length, beforeDetails + 1, 'detail regeneration preserves existing frames');

  // Existing Figma boards can be updated without recreating edited artwork.
  const legacyMeta = node('TEXT'); legacyMeta.name = 'Meta';
  legacyMeta.characters = 'Glance · v1.0.1 · 1 command'; firstRow.appendChild(legacyMeta);
  const legacyPublisher = node('TEXT'); legacyPublisher.name = 'Publisher and Version';
  installedDetail.findOne(child => child.name === 'Scrollable Details').appendChild(legacyPublisher);
  const editedSummary = firstRow.findOne(child => child.name === 'Summary');
  editedSummary.characters = 'Keep my edited description'; editedSummary.y = 43;
  await figma.ui.onmessage({ type: 'hide-widget-market-version-info' });
  assert.equal(firstRow.findOne(child => child.name === 'Meta'), null);
  assert.equal(installedDetail.findOne(child => child.name === 'Publisher and Version'), null);
  assert.equal(editedSummary.characters, 'Keep my edited description');
  assert.equal(editedSummary.y, 43, 'manual positioning is preserved');
  assert.equal(page.children.length, beforeDetails + 1, 'cleanup does not duplicate boards');

  const beforeCompactMenu = page.children.length;
  await figma.ui.onmessage({ type: 'generate-widget-context-credits' });
  const compactMenu = page.children.find(child => child.name === 'Widget Context Menu / Compact Credits');
  assert.ok(compactMenu, 'compact Widget menu design is generated');
  assert.equal(page.children.length, beforeCompactMenu + 1);
  assert.ok(compactMenu.findOne(child => child.name === 'Context Menu'));
  assert.ok(compactMenu.findOne(child => child.name === 'Full Name Tooltip / Hover or Focus'));
  const submenus = compactMenu.findAll(child => child.name === 'Widget Submenu');
  assert.equal(submenus.length, 3, 'cascade, long names and price states');
  for (const menu of submenus) {
    assert.equal(menu.width, 280, 'submenu has a bounded width');
    assert.equal(menu.findAll(child => child.name === 'Cost Unit').length, 1, 'units appear once in the header');
    const rows = menu.children.filter(child => child.name.startsWith('Widget Item / '));
    for (const row of rows) {
      const name = row.findOne(child => child.name === 'Widget Name');
      const badge = row.findOne(child => child.name === 'Credit Badge');
      const value = badge.findOne(child => child.name === 'Credit Value');
      assert.equal(row.height, 28, 'row remains compact');
      assert.equal(name.maxLines, 1);
      assert.equal(name.textTruncation, 'ENDING');
      assert.ok(name.x + name.width + 10 <= badge.x, 'name never overlaps the separate cost');
      assert.equal(badge.x + badge.width, row.width - 10, 'prices align at the right edge');
      assert.ok(/^(\d+|免费|Free)$/.test(value.characters), 'badge contains a complete short price only');
    }
  }
  assert.ok(compactMenu.findOne(child => child.name === 'Credit Value' && child.characters === '1000000'), 'large prices are not shortened or clipped');
  assert.ok(compactMenu.findOne(child => child.name === 'Credit Value' && child.characters === '免费'));
  assert.ok(compactMenu.findOne(child => child.name === 'Credit Value' && child.characters === 'Free'));
  const editedName = compactMenu.findOne(child => child.name === 'Widget Name');
  editedName.characters = 'Manual label edit';
  await figma.ui.onmessage({ type: 'generate-widget-context-credits' });
  assert.equal(page.children.length, beforeCompactMenu + 1, 'regeneration does not duplicate the design');
  assert.equal(editedName.characters, 'Manual label edit', 'regeneration preserves edits');

  const beforeMotion = page.children.length;
  const previousPricing = node('FRAME');
  previousPricing.name = 'Pricing & Credits / Purchase + Usage Flow';
  previousPricing.resize(2704, 19114); page.appendChild(previousPricing);
  const beforePricing = page.children.length;
  await figma.ui.onmessage({ type: 'generate-pricing-flows' });
  assert.ok(!figma.ui.lastMessage.message.includes('failed'), figma.ui.lastMessage.message);
  const pricing = page.children.find(child => child.name === 'Pricing & Credits / Purchase + Usage Flow / Refined');
  assert.ok(pricing, 'pricing review board is generated');
  const pricingScreens = pricing.children.filter(child => child.name.startsWith('Screen / '));
  assert.ok(pricingScreens.length >= 25, 'purchase, credits, task and recovery states are covered');
  const pricingScreenIDs = new Set(pricingScreens.map(screen => screen.id));
  const pricingScreen = id => pricingScreens.find(screen => screen.name.startsWith('Screen / ' + id + ' / '));
  const actionDestination = (screenID, label) => pricingScreen(screenID)
    .findOne(child => child.name === 'Action / ' + label).reactions[0].actions[0].destinationId;
  const hasText = (screenID, value) => pricingScreen(screenID).findOne(child => child.type === 'TEXT' && child.characters === value);
  for (const screen of pricingScreens) {
    assert.equal(screen.width, 640, 'billing uses ordinary, compact desktop windows');
    assert.equal(screen.height, 600);
    for (const layer of screen.findAll(child => child.type === 'TEXT')) {
      assert.equal(layer.fontName.family, 'Inter', 'reuse the established Glance design font');
    }
  }
  let pricingLinkCount = 0;
  for (const layer of pricing.findAll(child => !!child.reactions)) {
    for (const reaction of layer.reactions) for (const action of reaction.actions || []) {
      assert.ok(pricingScreenIDs.has(action.destinationId), 'all prototype destinations exist on this board');
      assert.equal(action.type, 'NODE', 'prototype cannot initiate real payments');
      pricingLinkCount++;
    }
  }
  assert.ok(pricingLinkCount > 50);
  assert.equal(actionDestination('orderPro', '前往浏览器支付 ¥99'), pricingScreen('checkoutPro').id);
  assert.equal(actionDestination('paidPro', '打开 Glance'), pricingScreen('pro').id);
  assert.equal(actionDestination('plans', '¥99 买断 Pro'), pricingScreen('loginPro').id,
    'a buyer without a session authenticates before confirming an order');
  assert.equal(actionDestination('loginPro', '使用 Google 继续'), pricingScreen('orderPro').id,
    'purchase login returns to the intended order instead of dropping into trial');
  assert.equal(actionDestination('running', '取消任务'), pricingScreen('cancelTask420').id);
  assert.ok(hasText('cancelledTask420', '412 点'), 'cancelling after execution starts does not refund');
  assert.ok(hasText('renewOrder', '¥59'));
  for (const before of [2, 20, 120]) for (const pack of [100, 300, 1000]) {
    const suffix = before + '_' + pack;
    assert.ok(hasText('topup' + suffix, (before + pack) + ' 点'));
    assert.equal(actionDestination('topup' + suffix, '前往浏览器支付 ¥' + pack / 10), pricingScreen('creditsCheckout' + suffix).id);
    assert.ok(hasText('creditsPaid' + suffix, (before + pack) + ' 点'), 'checkout credits match selected package and starting balance');
  }
  assert.ok(hasText('quote420', '412 点'));
  assert.ok(hasText('taskRefund', '420 点'));
  assert.ok(hasText('resume300', '294 点'), 'recovered input requires a fresh confirmation before debit');
  for (const id of ['free', 'login', 'plans', 'paidPro', 'wallet120', 'topup120_300', 'taskRefund']) {
    assert.equal(pricingScreen(id).findOne(child => child.name === 'Heading').textAlignHorizontal, 'CENTER', `${id} has a centered composition`);
    const content = pricingScreen(id).findOne(child => child.name === 'Content');
    assert.equal(content.x + content.width / 2, 320, `${id} has a genuinely centered content column`);
  }
  for (const id of ['pro', 'ledger', 'quote420']) {
    assert.equal(pricingScreen(id).findOne(child => child.name === 'Heading').textAlignHorizontal, 'LEFT', `${id} retains a clear reading edge`);
  }
  for (const id of ['topup120_100', 'topup120_300', 'topup120_1000']) {
    const packs = pricingScreen(id).findOne(child => child.name === 'Recharge Packages');
    for (const option of packs.children) assert.equal(option.findOne(child => child.name === 'Points').textAlignHorizontal, 'CENTER');
    assert.ok(packs.children.reduce((sum, option) => sum + option.width, 24) <= packs.width + .01);
  }
  assert.ok(hasText('plans', '¥99'), 'price is isolated as the central visual anchor');
  assert.ok(pricingScreen('paidPro').findOne(child => child.name === 'Status Mark'));
  assert.equal(pricingScreen('login').findOne(child => child.name === 'Email Label').textAlignHorizontal, 'LEFT');
  assert.equal(pricingScreen('plans').findOne(child => child.name === 'Footer Divider'), null,
    'do not force every screen into the same bottom-bar form template');
  assert.equal(pricingScreen('quote420').findOne(child => child.name === 'Value').textAlignHorizontal, 'RIGHT');
  const pricingHeading = pricingScreen('plans').findOne(child => child.name === 'Heading');
  pricingHeading.characters = 'User-edited pricing title';
  await figma.ui.onmessage({ type: 'generate-pricing-flows' });
  assert.equal(page.children.length, beforePricing + 1, 'rerun must not duplicate pricing boards');
  assert.equal(pricingHeading.characters, 'User-edited pricing title', 'rerun preserves design edits');
  pricingHeading.characters = '一次购买，长期使用';

  // Approximate text metrics and native auto-layout to catch clipped content in
  // the local generator without launching Figma or the Glance app.
  function layoutBillingNode(layer) {
    if (layer.type === 'TEXT' && layer.textAutoResize === 'HEIGHT') {
      const size = layer.fontSize;
      const width = layer.width || 1;
      let lines = 1, used = 0;
      for (const char of layer.characters) {
        if (char === '\n') { lines++; used = 0; continue; }
        const advance = size * (char.codePointAt(0) > 255 ? 1 : .58);
        if (used + advance > width) { lines++; used = 0; }
        used += advance;
      }
      layer.height = lines * (layer.lineHeight?.value || Math.ceil(size * 1.55));
    }
    layer.children.forEach(layoutBillingNode);
    if (layer.layoutMode === 'VERTICAL') {
      let y = layer.paddingTop || 0;
      layer.children.filter(child => child.visible !== false).forEach((child, index) => {
        if (index) y += layer.itemSpacing || 0;
        child.x = layer.paddingLeft || 0; child.y = y; y += child.height;
      });
      if (layer.primaryAxisSizingMode === 'AUTO') layer.height = y + (layer.paddingBottom || 0);
    }
  }
  layoutBillingNode(pricing);
  const luminance = color => {
    const linear = value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
    return .2126 * linear(color.r) + .7152 * linear(color.g) + .0722 * linear(color.b);
  };
  function backgroundFor(layer) {
    for (let ancestor = layer.parent; ancestor; ancestor = ancestor.parent) {
      const paint = ancestor.fills?.find(paint => paint.type === 'SOLID' && (paint.opacity ?? 1) === 1);
      if (paint) return paint.color;
    }
    throw new Error('Missing billing text background');
  }
  for (const screen of pricingScreens) {
    const content = screen.findOne(child => child.name === 'Content');
    assert.ok(content.y + content.height <= 492,
      `${screen.name}: content bottom ${content.y + content.height} must precede footer`);
    for (const layer of screen.findAll(child => child.type === 'TEXT')) {
      const foreground = luminance(layer.fills[0].color);
      const background = luminance(backgroundFor(layer));
      const contrast = (Math.max(foreground, background) + .05) / (Math.min(foreground, background) + .05);
      assert.ok(contrast >= 4.5, `${screen.name}/${layer.name} contrast ${contrast.toFixed(2)} must pass AA`);
      if (layer.name === 'Label' && layer.parent.name.startsWith('Action /')) {
        assert.ok(layer.height <= layer.lineHeight.value, `${screen.name}: button label must stay on one line`);
      }
      assert.ok(!/[—–]/.test(layer.characters), 'avoid decorative dashes in billing copy');
    }
  }
  assert.ok(uiSource.indexOf('id="generate-pricing-flows"') < uiSource.indexOf('<label for="reference">'));
  pricing.remove();
  assert.equal(page.children.length, beforePricing);
  assert.equal(previousPricing.name, 'Pricing & Credits / Purchase + Usage Flow', 'redesign preserves the old review board');
  previousPricing.remove();

  // PRD v0.4 pricing board: every state reachable, every link resolvable,
  // content clear of the footer, and amounts consistent along each flow.
  const beforePrd = page.children.length;
  await figma.ui.onmessage({ type: 'generate-pricing-prd-flows' });
  assert.ok(!figma.ui.lastMessage.message.includes('failed'), figma.ui.lastMessage.message);
  const prd = page.children.find(child => child.name === 'Pricing & Credits / PRD v0.4 Flow');
  assert.ok(prd, 'PRD v0.4 pricing board is generated');
  assert.equal(page.children.length, beforePrd + 1);
  const prdScreens = prd.children.filter(child => child.name.startsWith('Screen / '));
  const prdScreen = id => {
    const found = prdScreens.find(screen => screen.name.startsWith('Screen / ' + id + ' / '));
    assert.ok(found, 'missing PRD state ' + id);
    return found;
  };
  const prdIDByNode = new Map(prdScreens.map(screen => [screen.id, screen.name.split(' / ')[1]]));
  const incoming = new Map(prdScreens.map(screen => [screen.id, 0]));
  const outgoing = new Map(prdScreens.map(screen => [screen.id, 0]));
  const screenOf = layer => { let n = layer; while (n && !prdIDByNode.has(n.id)) n = n.parent; return n; };
  for (const layer of prd.findAll(child => !!child.reactions)) {
    for (const reaction of layer.reactions) for (const action of reaction.actions || []) {
      assert.equal(action.type, 'NODE', 'prototype cannot initiate real payments');
      assert.ok(incoming.has(action.destinationId), 'all PRD destinations exist on this board');
      incoming.set(action.destinationId, incoming.get(action.destinationId) + 1);
      const from = screenOf(layer);
      if (from) outgoing.set(from.id, outgoing.get(from.id) + 1);
    }
  }
  const entryStates = new Set(['freeSubmitted', 'highCostConfirm', 'priceChanged', 'trialEnding', 'offlineExpired', 'updateLocked']);
  for (const screen of prdScreens) {
    const id = prdIDByNode.get(screen.id);
    if (!entryStates.has(id)) assert.ok(incoming.get(screen.id) > 0, `${id} must be reachable from another state or a route`);
  }
  const prdDest = (id, label) => {
    const action = prdScreen(id).findOne(child => child.name === 'Action / ' + label);
    assert.ok(action, `${id} has action ${label}`);
    return prdIDByNode.get(action.reactions[0].actions[0].destinationId);
  };
  const prdText = (id, value) => !!prdScreen(id).findOne(child => child.type === 'TEXT' && child.characters === value);
  // Trial and free tier.
  assert.equal(prdDest('trialEnded', '继续使用免费版'), 'freeLocked');
  assert.equal(prdDest('freeLocked', '了解 Pro'), 'proOffer');
  assert.ok(!prdScreen('launchTrial').findOne(child => child.name === 'Input / Email'), 'first launch never asks for an account');
  // Sign-in returns to the interrupted action, and only new accounts get the gift.
  assert.equal(prdDest('login', '使用 Google 登录'), 'loginDone');
  assert.equal(prdDest('login', '发送验证码'), 'codeSent');
  assert.equal(prdDest('codeSent', '验证并登录'), 'loginDone');
  assert.equal(prdDest('loginDone', '继续'), 'firstPaidNotice');
  assert.equal(prdDest('loginReturning', '继续'), 'taskSubmitted', 'returning accounts skip the one-time notice');
  assert.equal(prdDest('loginPurchase', '使用 Google 继续'), 'proOfferSignedIn', 'purchase login returns to the offer, not a checkout');
  assert.equal(prdDest('proOffer', '购买 Pro · ¥99'), 'loginPurchase', 'signed-out buyers authenticate first');
  assert.equal(prdDest('proOfferSignedIn', '购买 Pro · ¥99'), 'awaitPro');
  // Charging, undo and refunds keep balances consistent: 100 gift, 8 per run.
  assert.ok(prdText('loginDone', '100 点'));
  assert.ok(prdText('taskSubmitted', '已扣 8 点，当前余额 92 点。'));
  assert.equal(prdDest('taskSubmitted', '撤销'), 'taskUndone');
  assert.ok(prdText('taskUndone', '100 点'), 'undo refunds the full charge');
  assert.ok(prdText('taskFailedRefund', '100 点'), 'system failure refunds the full charge');
  assert.ok(prdText('taskExpiredRefund', '100 点'));
  assert.ok(prdText('taskCancelled', '92 点'), 'cancelling after processing starts does not refund');
  assert.equal(prdDest('taskQueued', '取消并退回 8 点'), 'taskUndone');
  assert.equal(prdDest('taskRunning', '取消任务'), 'cancelRunningConfirm');
  assert.equal(prdDest('cancelRunningConfirm', '继续等待'), 'taskRunning');
  assert.ok(prdText('highCostConfirm', '52 点') && prdText('highCostSubmitted', '已扣 40 点，当前余额 52 点。'));
  assert.ok(prdText('priceChanged', '82 点') && prdText('priceChangedSubmitted', '已扣 10 点，当前余额 82 点。'));
  // Insufficient balance: nothing is charged before payment; 2 + 330 - 8.
  assert.equal(prdDest('insufficient', '前往支付 ¥30'), 'awaitTask');
  assert.equal(prdDest('insufficientUSD', '前往支付 $4.99'), 'awaitTask');
  assert.ok(prdText('insufficient', '332 点') && prdText('creditedManual', '332 点'));
  assert.ok(prdText('creditedAutoSubmit', '324 点') && prdText('resumedSubmitted', '已扣 8 点，当前余额 324 点。'));
  for (const id of ['insufficient', 'insufficientUSD', 'insufficientManual', 'topup', 'topupUSD']) {
    const packs = prdScreen(id).findOne(child => child.name === 'Recharge Packages');
    assert.equal(packs.children.length, 3, `${id} offers the three Admin packs`);
    assert.ok(packs.children.reduce((sum, option) => sum + option.width, 24) <= packs.width + .01);
    assert.ok(prdScreen(id).findOne(child => child.name === 'Segmented / Payment'), `${id} lets the buyer switch currency`);
  }
  assert.ok(prdScreen('insufficient').findOne(child => child.name === 'Checkbox / 到账后自动提交本次任务'));
  // Every payment context runs the same verified chain.
  for (const ctx of ['Task', 'Wallet', 'Pro', 'Renew']) {
    assert.equal(prdDest('await' + ctx, '我已完成支付'), 'confirming' + ctx);
    assert.equal(prdDest('await' + ctx, '放弃本次支付'), 'abandon' + ctx);
    assert.equal(prdDest('abandon' + ctx, '我已付款，查询结果'), 'confirming' + ctx, 'abandoning never invites a second payment');
    assert.equal(prdScreen('pancake' + ctx).findOne(child => child.name === 'Window Title').characters, 'Pancake 收银台 · 第三方页面');
    const pay = prdScreen('pancake' + ctx).findOne(child => child.name.startsWith('Action / 支付 '));
    assert.equal(prdIDByNode.get(pay.reactions[0].actions[0].destinationId), 'return' + ctx);
    assert.equal(prdDest('return' + ctx, '打开 Glance'), 'confirming' + ctx, 'the return page never grants credits or Pro itself');
  }
  assert.ok(prdText('pancakeTask', '¥30') && prdText('pancakePro', '¥99') && prdText('pancakeRenew', '¥59'));
  assert.ok(prdText('walletCredited', '422 点') && prdText('walletAfter', '422 点'));
  // Pro activation, devices and refunds.
  assert.ok(prdText('proActivated', '192 点'), '92 + 100 purchase gift');
  assert.equal(prdDest('devicesFull', '释放 Mac mini'), 'deviceReleased');
  assert.ok(prdText('refundedPro', '92 点'), 'refund claws back the 100-credit purchase gift');
  assert.equal(prdDest('refundedPro', '完成'), 'accountFree');
  assert.equal(prdDest('refundSubmitted', '完成'), 'account', 'nothing changes until Pancake confirms the refund');
  assert.equal(prdDest('wechatLimit', '改用美元支付'), 'proOfferUSD');
  assert.equal(prdDest('proPriceChanged', '按新价格购买 · ¥149'), 'awaitPro', 'a changed price is confirmed before checkout');
  assert.equal(prdDest('pendingOrder', '继续支付'), 'awaitWallet', 'a second click resumes the pending order');
  assert.ok(prdText('loginNoGift', '0 点'), 'the new-user gift is granted once per Mac');
  assert.ok(prdScreen('releaseLimit'), 'device releases are rate limited');
  assert.ok(!prd.findAll(child => child.type === 'TEXT').some(layer => layer.characters.includes('支付宝')),
    'Pancake buyers cannot pay with Alipay');
  layoutBillingNode(prd);
  for (const screen of prdScreens) {
    assert.equal(screen.width, 640); assert.equal(screen.height, 600);
    const content = screen.findOne(child => child.name === 'Content');
    assert.ok(content.y + content.height <= 492, `${screen.name}: content bottom ${content.y + content.height} must precede footer`);
    const subtitle = screen.findOne(child => child.name === 'Subtitle');
    assert.ok(subtitle.characters.length <= 38, `${screen.name}: subtitle stays on one line`);
    for (const layer of screen.findAll(child => child.type === 'TEXT')) {
      assert.equal(layer.fontName.family, 'Inter');
      const foreground = luminance(layer.fills[0].color);
      const background = luminance(backgroundFor(layer));
      const contrast = (Math.max(foreground, background) + .05) / (Math.min(foreground, background) + .05);
      assert.ok(contrast >= 4.5, `${screen.name}/${layer.name} contrast ${contrast.toFixed(2)} must pass AA`);
      if (layer.name === 'Label' && layer.parent.name.startsWith('Action /')) {
        assert.ok(layer.height <= layer.lineHeight.value, `${screen.name}: button label must stay on one line`);
      }
      assert.ok(!/[—–]/.test(layer.characters), 'avoid decorative dashes in billing copy');
    }
  }
  const prdHeading = prdScreen('proOffer').findOne(child => child.name === 'Heading');
  prdHeading.characters = 'User-edited PRD title';
  await figma.ui.onmessage({ type: 'generate-pricing-prd-flows' });
  assert.equal(page.children.length, beforePrd + 1, 'rerun must not duplicate the PRD board');
  assert.equal(prdHeading.characters, 'User-edited PRD title', 'rerun preserves design edits');
  assert.ok(uiSource.indexOf('id="generate-pricing-prd-flows"') < uiSource.indexOf('<label for="reference">'));
  prd.remove();

  const beforeProEntry = page.children.length;
  await figma.ui.onmessage({ type: 'generate-pro-purchase-entry' });
  const proEntry = page.children.find(node => node.name === 'Glance Pro / Discover & Purchase / Review');
  assert.ok(proEntry, 'pro purchase review board is generated');
  assert.equal(page.children.length, beforeProEntry + 1);
  assert.equal(proEntry.findAll(node => node.name.startsWith('Pro Purchase / ')).length, 6);
  const discoverPro = proEntry.findOne(node => node.name === 'Action / Discover Pro');
  assert.ok(discoverPro.reactions.length, 'Home entry navigates to the offer');
  for (const price of ['¥29.90', '¥79.90']) {
    assert.ok(proEntry.findOne(node => node.type === 'TEXT' && node.characters === price), 'current price ' + price);
  }
  assert.ok(proEntry.findOne(node => node.name === 'Credit Separation' && node.characters.includes('另按积分计费')));
  const reviewHeading = proEntry.findOne(node => node.name === 'Review Title');
  reviewHeading.characters = 'Owner review edits';
  await figma.ui.onmessage({ type: 'generate-pro-purchase-entry' });
  assert.equal(page.children.length, beforeProEntry + 1);
  assert.equal(reviewHeading.characters, 'Owner review edits');
  assert.ok(uiSource.includes('id="generate-pro-purchase-entry"'));
  proEntry.remove();

  await figma.ui.onmessage({ type: 'generate-task-running-motion' });
  const motion = page.children.find(child => child.name === 'Task Running Motion');
  assert.ok(motion, 'Task Running Motion must be generated');
  assert.equal(page.children.length, beforeMotion + 1);
  const motionStages = motion.findAll(child => child.name.startsWith('Task Running Motion / '));
  assert.equal(motionStages.length, 7, 'six loop frames plus the done frame');
  for (const stage of motionStages) {
    for (const layer of ['Eye L', 'Eye R', 'Hand L', 'Hand R', 'Spark A', 'Spark B', 'Spark C', 'Dot 1', 'Dot 2', 'Dot 3', 'Shimmer', 'Bar Fill', 'Check', 'Title']) {
      assert.ok(stage.findOne(child => child.name === layer), `${stage.name} has ${layer} (Smart Animate matches by name)`);
    }
  }
  const eyeX = motionStages.slice(0, 3).map(stage => stage.findOne(child => child.name === 'Eye L').x);
  assert.ok(eyeX[0] < eyeX[1] && eyeX[1] < eyeX[2], 'eyes glance left to right across the first three frames');
  assert.ok(motionStages[0].reactions && motionStages[0].reactions.length === 2, 'loop + click-through reactions');
  await figma.ui.onmessage({ type: 'generate-task-running-motion' });
  assert.equal(page.children.length, beforeMotion + 1, 'motion regeneration is idempotent');
  const beforeToast = page.children.length;
  await figma.ui.onmessage({ type: 'generate-toast' });
  const toastBoard = page.children.find(child => child.name === 'Toast');
  assert.ok(toastBoard, 'Toast board must be generated');
  assert.equal(page.children.length, beforeToast + 1);
  for (const scene of ['01 / Toast / Variants', '02 / Toast / In Context']) {
    assert.ok(toastBoard.findOne(child => child.name === scene), `scene ${scene}`);
  }
  assert.ok(toastBoard.findOne(child => child.name === 'Toast / Shortcuts'), 'shortcuts toast');
  assert.ok(toastBoard.findAll(child => child.name.startsWith('Toast / error')).length >= 1, 'error toast');
  const detailToast = toastBoard.findOne(child => child.name === 'Toast / success / detail');
  assert.equal(detailToast.height, 64, 'detail toast is 64 high');
  const compactToast = toastBoard.findOne(child => child.name === 'Toast / success / compact');
  assert.equal(compactToast.height, 48, 'compact toast is 48 high');
  assert.ok(toastBoard.findAll(child => child.name === 'Title').every(node => node.fontSize >= 14), 'toast titles are 14 pt or larger');
  await figma.ui.onmessage({ type: 'generate-toast' });
  assert.equal(page.children.length, beforeToast + 1, 'toast regeneration is idempotent');
  const beforeHistory = page.children.length;
  await figma.ui.onmessage({ type: 'generate-preview-history-redesign' });
  const history = page.children.find(child => child.name === 'Preview History Redesign');
  assert.ok(history, 'Preview History Redesign board must be generated');
  assert.equal(page.children.length, beforeHistory + 1);
  for (const scene of ['01 / Preview History / Populated', '02 / Preview History / Search', '03 / Preview History / Empty']) {
    assert.ok(history.findOne(child => child.name === scene), `scene ${scene}`);
  }
  const populated = history.findOne(child => child.name === '01 / Preview History / Populated');
  assert.equal(populated.findAll(child => child.name === 'Section Title').length, 3, 'Today / Yesterday / Earlier groups');
  assert.equal(populated.findAll(child => child.name.startsWith('History Card / ')).length, 15, 'three rows of five cards');
  assert.equal(populated.findAll(child => child.name === 'Action / Reveal in Finder').length, 1, 'only the hovered card shows actions');
  assert.equal(populated.findAll(child => child.name === 'Filter / Videos').length, 1);
  assert.equal(populated.findAll(child => child.name === 'Caption Bar').length, 0, 'no caption bar over thumbnails');
  const searchScene = history.findOne(child => child.name === '02 / Preview History / Search');
  assert.equal(searchScene.findAll(child => child.name.startsWith('History Card / ')).length, 4);
  assert.ok(searchScene.findOne(child => child.name === 'Filename / semibold'), 'search match is highlighted');
  const emptyScene = history.findOne(child => child.name === '03 / Preview History / Empty');
  assert.equal(emptyScene.findAll(child => child.name.startsWith('History Card / ')).length, 0);
  assert.equal(emptyScene.findOne(child => child.name === 'Clear History'), null, 'nothing to clear when empty');
  await figma.ui.onmessage({ type: 'generate-preview-history-redesign' });
  assert.equal(page.children.length, beforeHistory + 1, 'regeneration is idempotent');
  const beforeCapture = page.children.length;
  await figma.ui.onmessage({ type: 'generate-capture-editor' });
  const capture = page.children.find(child => child.name === 'Capture Editor');
  assert.ok(capture, 'Capture Editor board must be generated');
  assert.equal(page.children.length, beforeCapture + 1);
  for (const scene of ['01 / Image Inspect / Toolbar 6', '02 / Capture Editor / Image / Free',
                       '03 / Capture Editor / Image / 3:4', '04 / Capture Editor / Video']) {
    assert.ok(capture.findOne(child => child.name === scene), `scene ${scene}`);
  }
  const toolbar6 = capture.findOne(child => child.name === '01 / Floating Toolbar (6)');
  assert.equal(toolbar6.children.length, 6, 'toolbar has six buttons');
  assert.ok(toolbar6.findOne(child => child.name === 'Capture'));
  assert.ok(capture.findOne(child => child.name === '05 / Capture Result / New Window'), 'result window scene');
  assert.equal(capture.findAll(child => child.name === 'Ratio Dropdown').length, 3, 'one dropdown per editor scene');
  assert.equal(capture.findAll(child => child.name === 'Ratio Segment').length, 0, 'segmented control is gone');
  const menu = capture.findOne(child => child.name === 'Ratio Menu');
  assert.equal(menu.children.length, 6, 'open dropdown lists six ratios');
  assert.equal(capture.findAll(child => child.name === 'Ratio Menu').length, 1, 'only the 3:4 scene shows the open list');
  assert.equal(capture.findAll(child => child.name === 'Action / Cancel').length, 3, 'one Cancel button per editor scene');
  for (const gone of ['Action / Copy', 'Action / Save…', 'Action / Open in Image Inspect']) {
    assert.equal(capture.findOne(child => child.name === gone), null, `${gone} removed`);
  }
  assert.equal(capture.findAll(child => child.name === 'Action / Capture').length, 3, 'one Capture button per editor scene');
  const crop34 = capture.findOne(child => child.name === '03 / Capture Editor / Image / 3:4').findOne(child => child.name === 'Crop Box');
  assert.ok(Math.abs(crop34.width / crop34.height - 3 / 4) < 0.01, '3:4 crop box keeps its ratio');
  assert.equal(crop34.findAll(child => child.name.startsWith('Handle ')).length, 8);
  assert.ok(capture.findOne(child => child.name === 'Toast / Saved'), 'result window confirms the save');
  await figma.ui.onmessage({ type: 'generate-capture-editor' });
  assert.equal(page.children.filter(child => child.name === 'Capture Editor').length, 1, 'Capture Editor must be idempotent');

  const beforeCharacterTray = page.children.length;
  await figma.ui.onmessage({ type: 'generate-menu-bar-icon-character' });
  const characterTray = page.children.find(child => child.name === 'Menu Bar Icon / Character');
  assert.ok(characterTray, 'Menu Bar Icon / Character board must be generated');
  assert.equal(page.children.length, beforeCharacterTray + 1);
  assert.ok(characterTray.findOne(child => child.name === 'State / Default'));
  assert.ok(characterTray.findOne(child => child.name === 'State / Peek off'), 'Peek-off state exists');
  const peekOff = characterTray.findOne(child => child.name === 'State / Peek off');
  assert.equal(peekOff.findAll(child => child.name.startsWith('Hand / ')).length, 2, 'hands cover the eyes');
  assert.equal(peekOff.findAll(child => child.name === 'Eye').length, 0, 'no eye holes when covered');
  for (let i = 1; i <= 4; i++) assert.ok(characterTray.findOne(child => child.name === `Frame ${i}`), `running animation frame ${i}`);
  assert.ok(characterTray.findOne(child => child.name === 'Menu Bar / Light'));
  assert.ok(characterTray.findOne(child => child.booleanOperation === 'SUBTRACT'), 'eyes are knocked out with a boolean');
  await figma.ui.onmessage({ type: 'generate-menu-bar-icon-character' });
  assert.equal(page.children.filter(child => child.name === 'Menu Bar Icon / Character').length, 1, 'character tray board must be idempotent');

  const beforeTangible = page.children.length;
  await figma.ui.onmessage({ type: 'generate-app-logo-tangible' });
  const tangible = page.children.find(child => child.name === 'App Logo / Tangible');
  assert.ok(tangible, 'App Logo / Tangible board must be generated');
  assert.equal(page.children.length, beforeTangible + 1);
  const objectIcon = tangible.findOne(child => child.name === 'Tangible A / Object / 1024');
  assert.equal(objectIcon.width, 1024);
  assert.ok(objectIcon.findOne(child => child.name === 'Knob'), 'object concept has the slider knob');
  assert.ok(objectIcon.findOne(child => child.name === 'Photo / developed'));
  const characterIcon = tangible.findOne(child => child.name === 'Tangible B / Character / 1024');
  assert.ok(characterIcon.findOne(child => child.name === 'Head'));
  assert.equal(characterIcon.findAll(child => child.name.startsWith('Eye / ') && !child.name.includes('/ pupil') && !child.name.includes('/ glint')).length, 2);
  assert.equal(characterIcon.findAll(child => child.name.startsWith('Hand / ') && !child.name.includes('/ finger')).length, 2);
  assert.equal(characterIcon.findOne(child => child.name.startsWith('Beret')), null, 'character has no hat');
  assert.ok(characterIcon.findOne(child => child.name === 'Mouth'));
  assert.equal(characterIcon.findAll(child => child.name.startsWith('Blush / ')).length, 2);
  for (const size of [256, 128, 64, 32]) {
    assert.ok(tangible.findOne(child => child.name === `Tangible A / ${size}`));
    assert.ok(tangible.findOne(child => child.name === `Tangible B / ${size}`));
  }
  await figma.ui.onmessage({ type: 'generate-app-logo-tangible' });
  assert.equal(page.children.filter(child => child.name === 'App Logo / Tangible').length, 1, 'Tangible board must be idempotent');

  const beforeAppLogo = page.children.length;
  await figma.ui.onmessage({ type: 'generate-app-logo' });
  const appLogo = page.children.find(child => child.name === 'App Logo');
  assert.ok(appLogo, 'App Logo board must be generated');
  assert.equal(page.children.length, beforeAppLogo + 1);
  const icon1024 = appLogo.findOne(child => child.name === 'App Icon / 1024');
  assert.equal(icon1024.width, 1024);
  assert.equal(icon1024.cornerRadius, 1024 * 0.2237, 'macOS squircle radius');
  const glyph = icon1024.findOne(child => child.name === 'Glyph');
  assert.equal(glyph.width, 1024 * 824 / 1024, 'Glyph fills the 824/1024 safe area');
  assert.ok(icon1024.findOne(child => child.name === 'Handle Ring'));
  for (const size of [512, 256, 128, 64, 32, 16]) {
    assert.ok(appLogo.findOne(child => child.name === `App Icon / ${size}`), `ladder has ${size}`);
  }
  assert.ok(appLogo.findOne(child => child.name === 'Lockup / Dark'));
  assert.ok(appLogo.findOne(child => child.name === 'Lockup / Light'));
  assert.equal(appLogo.findAll(child => child.name.startsWith('Mono / ')).length, 3);
  await figma.ui.onmessage({ type: 'generate-app-logo' });
  assert.equal(page.children.filter(child => child.name === 'App Logo').length, 1, 'App Logo must be idempotent');

  const beforeMenuBarIcon = page.children.length;
  await figma.ui.onmessage({ type: 'generate-menu-bar-icon' });
  const menuBarIcon = page.children.find(child => child.name === 'Menu Bar Icon');
  assert.ok(menuBarIcon, 'Menu Bar Icon board must be generated');
  assert.equal(page.children.length, beforeMenuBarIcon + 1);
  const construction = menuBarIcon.findOne(child => child.name === 'Construction / 8x');
  assert.equal(construction.width, 144, 'Construction tile shows the 18pt canvas at 8×');
  assert.ok(menuBarIcon.findOne(child => child.name === 'Menu Bar / Light'));
  assert.ok(menuBarIcon.findOne(child => child.name === 'Menu Bar / Dark'));
  assert.ok(menuBarIcon.findOne(child => child.name === 'Task Running Dot / 4pt'), 'Running state carries the 4pt dot');
  assert.equal(menuBarIcon.findAll(child => child.name === 'Glance / 18pt').length, 2, 'One actual-size glyph per menu bar sample');
  await figma.ui.onmessage({ type: 'generate-menu-bar-icon' });
  assert.equal(page.children.filter(child => child.name === 'Menu Bar Icon').length, 1, 'Menu Bar Icon must be idempotent');
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
  const oldWidgetNames = [
    'Widget Flow v1 / 01 / Image + Prompt + Mask',
    'Widget Flow v1 / 02 / Paint Mask',
    'Widget Flow v1 / 03 / Prompt Only',
    'Widget Flow v1 / 04 / Video + Audio Inputs',
    'Widget Flow v1 / 05 / Mixed Results'
  ];
  for (const name of oldWidgetNames) {
    const prior = node('FRAME');
    prior.name = name;
    prior.x = 30000 + page.children.length * 100;
    prior.resize(1554, 1012);
    page.appendChild(prior);
  }
  const overview = node('FRAME');
  overview.name = 'Widget / Simple Input + Output / Clean Editable';
  overview.x = 40000;
  overview.resize(1554, 1012);
  page.appendChild(overview);
  for (const name of [
    'Widget Input / 01 / Image',
    'Widget Input / 02 / Image + Text',
    'Widget Input / 03 / Image + Text + Mask',
    'Widget Input / 04 / Video',
    'Widget Output / 01 / Image',
    'Widget Output / 02 / Text',
    'Widget Output / 03 / Video',
    'Widget Output / 04 / Audio'
  ]) {
    const prior = node('FRAME');
    prior.name = name;
    prior.x = 42000 + page.children.length * 100;
    prior.resize(1554, 1012);
    page.appendChild(prior);
  }
  const beforeWidgetFlow = page.children.length;
  figma.editorType = 'dev';
  await figma.ui.onmessage({ type: 'get-editor-mode' });
  assert.equal(figma.ui.lastMessage.editorType, 'dev');
  await figma.ui.onmessage({ type: 'generate-widget-flow', bytes: null });
  assert.equal(page.children.length, beforeWidgetFlow, 'Dev Mode must not write to the Figma canvas');
  assert.match(figma.ui.lastMessage.message, /Switch to Design Mode/);
  figma.editorType = 'figma';
  await figma.ui.onmessage({ type: 'generate-widget-flow', bytes: null });
  const widgetPageNames = [
    'Widget Input / 02 / Image + Text / Revised',
    'Widget Input / 03 / Image + Text + Mask / Revised',
    'Widget Input / 03B / Image + Mask Only',
    'Widget Input / Draw Mask',
    'Widget Output / 02 / Text in Preview',
    'Widget Output / 03 / Video URL Preview',
    'Widget Output / 04 / Audio URL Player'
  ];
  const boards = widgetPageNames.map(name => page.children.find(child => child.name === name));
  assert.ok(boards.every(Boolean), 'Four input and three output pages must be generated: ' +
    figma.ui.lastMessage.message + ' / missing ' +
    widgetPageNames.filter((_, index) => !boards[index]).join(', '));
  assert.equal(page.children.length, beforeWidgetFlow + 7);
  assert.equal(page.selection.length, 1);
  assert.equal(page.selection[0], boards[0]);
  assert.equal(overview.visible, false, 'Old one-page overview is hidden');
  assert.equal(overview.name, 'Widget / Archived / Simple Input + Output');
  assert.equal(page.children.filter(child => child.name.startsWith('Widget Flow v1 / Archived / ')).length, 5);
  const archivedWidgetPages = page.children.filter(child => child.name.startsWith('Widget / Archived / v1 / '));
  assert.equal(archivedWidgetPages.length, 8);
  assert.ok(archivedWidgetPages.every(child => !child.visible), 'Old Widget pages must remain hidden');
  for (const [index, board] of boards.entries()) {
    assert.equal(board.width, 1554);
    assert.equal(board.height, 1012);
    assert.equal(board.y, index < 4 ? 0 : 1160);
    assert.equal(board.x, boards[0].x + (index % 4) * 1750);
    function assertContained(parent) {
      for (const child of parent.children) {
        assert.ok(child.x >= -0.001 && child.y >= -0.001, board.name + ': ' + child.name + ' starts outside parent');
        assert.ok(child.x + child.width <= parent.width + 0.001, board.name + ': ' + child.name + ' clips horizontally');
        assert.ok(child.y + child.height <= parent.height + 0.001, board.name + ': ' + child.name + ' clips vertically');
        assertContained(child);
      }
    }
    assertContained(board);
  }
  assert.ok(boards[0].findOne(child => child.name === 'Selected Image'));
  assert.ok(boards[1].findOne(child => child.name === 'Prompt Field'));
  assert.ok(boards[2].findOne(child => child.name === 'Mask Field'));
  assert.ok(boards[2].findOne(child => child.name === 'Prompt Field / disabled'));
  assert.ok(boards[3].findOne(child => child.name === 'Painted Mask Overlay'));
  assert.ok(boards[3].findOne(child => child.name === 'Brush Action'));
  assert.ok(boards[4].findOne(child => child.name === 'Output Text Preview'));
  assert.ok(boards[4].findOne(child => child.name === 'Copy text Action'));
  assert.ok(boards[5].findOne(child => child.name === 'Output Video Preview'));
  assert.ok(boards[5].findOne(child => child.name === 'Copy URL Action'));
  assert.ok(boards[6].findOne(child => child.name === 'Audio Player'));
  assert.ok(boards[6].findOne(child => child.name === 'Copy URL Action'));
  const title = boards[0].findOne(child => child.name === '04 / Widget Panel').findOne(child => child.name === 'Title');
  title.characters = 'User edited input title';
  await figma.ui.onmessage({ type: 'generate-widget-flow', bytes: null });
  assert.equal(page.children.length, beforeWidgetFlow + 7, 'Rerun must preserve the seven pages');
  assert.equal(title.characters, 'User edited input title');
  boards[5].remove();
  await figma.ui.onmessage({ type: 'generate-widget-flow', bytes: [1, 2, 3] });
  const regenerated = page.children.find(child => child.name === 'Widget Output / 03 / Video URL Preview');
  assert.equal(regenerated.findOne(child => child.name === 'Source Image').fills[0].type, 'IMAGE',
    'Optional reference image should fill the newly generated source preview');
  assert.equal(page.children.length, beforeWidgetFlow + 7);
  assert.equal(regenerated.x, boards[0].x + 1750, 'Missing output should return to its original grid position');
  const beforeOSSResult = page.children.length;
  await figma.ui.onmessage({ type: 'generate-widget-oss-result', bytes: [1, 2, 3] });
  assert.equal(page.children.length, beforeOSSResult + 1, 'OSS result action creates one page');
  const ossResult = page.children.find(child => child.name === 'Widget Output / Image URL / OSS Result / Refined');
  assert.equal(page.selection[0], ossResult);
  assert.equal(ossResult.width, 1554);
  assert.equal(ossResult.height, 1012);
  assert.ok(ossResult.findOne(child => child.name === '01 / Titlebar'));
  assert.equal(ossResult.findOne(child => child.name === '02 / Icon Toolbar'), null);
  assert.equal(ossResult.findOne(child => child.name === '04 / Result Identity Banner'), null);
  assert.equal(ossResult.findOne(child => child.name === '05 / Returned OSS URL'), null);
  assert.equal(ossResult.findOne(child => child.name === '06 / Statusbar'), null);
  const ossCanvas = ossResult.findOne(child => child.name === '03 / Widget Canvas');
  assert.equal(ossCanvas.y, 58);
  assert.equal(ossCanvas.height, 954);
  const ossStage = ossResult.findOne(child => child.name === '06 / Generated Image Stage');
  assert.equal(ossStage.y, -47, 'Stage matches the user-edited Figma position');
  assert.equal(ossStage.width, 1522);
  assert.equal(ossStage.height, 868);
  assert.equal(ossResult.findOne(child => child.name === 'Preview Result Badge'), null);
  assert.equal(ossResult.findOne(child => child.name === 'OSS Result Label').characters, 'OSS RESULT');
  const compactCopy = ossResult.findOne(child => child.name === 'Copy Result URL Action');
  assert.equal(compactCopy.width, 148);
  assert.equal(compactCopy.height, 34);
  assert.equal(compactCopy.findOne(child => child.name === 'Copy Result URL Label').characters, 'Copy URL');
  const ossStrip = ossResult.findOne(child => child.name === '07 / Original and Result Filmstrip');
  assert.equal(ossStrip.x, 669);
  assert.equal(ossStrip.y, 831);
  assert.ok(ossStrip.findOne(child => child.name === 'Original Thumbnail'));
  assert.ok(ossStrip.findOne(child => child.name === 'Generated Result Thumbnail / selected'));
  assert.equal(ossResult.findOne(child => child.name === 'Generated Image Preview').fills[0].type, 'IMAGE');
  const copyLabel = ossResult.findOne(child => child.name === 'Copy Result URL Label');
  copyLabel.characters = 'User edited URL action';
  await figma.ui.onmessage({ type: 'generate-widget-oss-result', bytes: null });
  assert.equal(page.children.length, beforeOSSResult + 1, 'Rerun must not duplicate OSS result page');
  assert.equal(copyLabel.characters, 'User edited URL action');
  const existingStrip = ossResult.findOne(child => child.name === '07 / Original and Result Filmstrip');
  ossResult.findOne(child => child.name === 'OSS Result Label').remove();
  const existingBadge = node('FRAME');
  existingBadge.name = 'Preview Result Badge';
  existingBadge.resize(151, 30);
  ossStage.appendChild(existingBadge);
  compactCopy.resize(107, 52);
  const existingCopyText = compactCopy.findOne(child => child.name === 'Copy Result URL Label');
  existingCopyText.remove();
  ossStage.appendChild(existingCopyText);
  await figma.ui.onmessage({ type: 'generate-widget-oss-result', bytes: null });
  assert.equal(page.children.length, beforeOSSResult + 1, 'Existing refined frame is updated in place');
  assert.equal(ossResult.findOne(child => child.name === '07 / Original and Result Filmstrip'), existingStrip,
    'Updating the controls must leave the thumbnail strip untouched');
  assert.equal(ossResult.findOne(child => child.name === 'Preview Result Badge'), null);
  assert.equal(ossResult.findOne(child => child.name === 'OSS Result Label').characters, 'OSS RESULT');
  assert.equal(compactCopy.width, 148);
  assert.equal(compactCopy.height, 34);
  assert.equal(compactCopy.findOne(child => child.name === 'Copy Result URL Label').characters, 'Copy URL');
  const userEditedSource = ossResult.clone();
  userEditedSource.name = 'Widget Output / Image URL / OSS Result';
  userEditedSource.x += 1750;
  userEditedSource.findOne(child => child.name === 'Original Label').characters = 'USER ORIGINAL';
  const sourceStage = userEditedSource.findOne(child => child.name === '06 / Generated Image Stage');
  sourceStage.findOne(child => child.name === 'OSS Result Label').remove();
  const oldBadge = node('FRAME');
  oldBadge.name = 'Preview Result Badge';
  oldBadge.x = 31;
  oldBadge.y = 52;
  oldBadge.resize(151, 30);
  sourceStage.appendChild(oldBadge);
  const oldCopy = sourceStage.findOne(child => child.name === 'Copy Result URL Action');
  oldCopy.x = 1353;
  oldCopy.resize(107, 52);
  const detachedText = oldCopy.findOne(child => child.name === 'Copy Result URL Label');
  detachedText.remove();
  detachedText.characters = 'Copy result URL';
  sourceStage.appendChild(detachedText);
  ossResult.remove();
  const beforeClone = page.children.length;
  await figma.ui.onmessage({ type: 'generate-widget-oss-result', bytes: null });
  const refinedClone = page.children.find(child => child.name === 'Widget Output / Image URL / OSS Result / Refined');
  assert.equal(page.children.length, beforeClone + 1, 'Edited source creates one separate refined frame');
  assert.notEqual(refinedClone, userEditedSource, 'The edited source must remain available');
  assert.equal(refinedClone.findOne(child => child.name === 'Original Label').characters, 'USER ORIGINAL');
  assert.ok(userEditedSource.findOne(child => child.name === 'Preview Result Badge'),
    'The source frame remains untouched');
  assert.equal(refinedClone.findOne(child => child.name === 'Preview Result Badge'), null);
  assert.equal(refinedClone.findOne(child => child.name === 'OSS Result Label').characters, 'OSS RESULT');
  const refinedCopy = refinedClone.findOne(child => child.name === 'Copy Result URL Action');
  assert.equal(refinedCopy.width, 148);
  assert.equal(refinedCopy.height, 34);
  assert.equal(refinedCopy.findOne(child => child.name === 'Copy Result URL Label').characters, 'Copy URL');
  assert.equal(refinedClone.findAll(child => child.name === 'Copy Result URL Label').length, 1,
    'The detached old copy label must be removed');
  assert.equal(refinedClone.findOne(child => child.name === '07 / Original and Result Filmstrip').children.length,
    userEditedSource.findOne(child => child.name === '07 / Original and Result Filmstrip').children.length,
    'Cloning preserves the thumbnail hierarchy exactly');
  console.log('All screen generators pass, including seven revised Widget pages and the refined OSS result page');
})().catch(error => { console.error(error); process.exitCode = 1; });
