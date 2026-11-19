/* Targeted website visual revision. Unslop: Damir Sokolovsky, CC BY 4.0.
 * Uses the exact user-provided portrait and actual handbag-removal result.
 * App reference file is never written. IDs come from direct-write-result.json.
 */
if (figma.fileKey !== 'kWvE51F9IfI3oSN6ZoxeKw') throw new Error('Wrong file');
const page = await figma.getNodeByIdAsync('0:1');
await figma.setCurrentPageAsync(page);
await Promise.all([
  ['Inter', 'Regular'], ['Inter', 'Medium'], ['Geist Mono', 'Regular'],
  ['Shippori Mincho', 'Regular'], ['Noto Sans SC', 'Regular'],
  ['Noto Sans SC', 'Medium'], ['Noto Serif SC', 'Regular']
].map(([family, style]) => figma.loadFontAsync({ family, style })));
const before = '64c03022c87e80a9cb74fcc2abfc5e0531b83af2';
const after = '3a68ce0c75a4d18a2a107fbf5c70b732df0bfae4';
const selfie = '3c477a707a25aad6a3bc57a56d834469938325bd';
const oldBefore = 'c1e59d8374c0ad63e9d64c8e65c7059df063d974';
const oldAfter = '2ce5d1f4957f7064c3e4d93c21c6ad9b3928dd0f';
const oldPortrait = 'ffb8e80405142f869ba9e59d086c8fae6e709aa9';
const hashMap = {
  [oldBefore]: before, [oldAfter]: after, [oldPortrait]: selfie,
  '8375d27a2f6c1bdfedb1a0b3054a941c6357894c': before,
  '1f255bdf84bf014bb676abb8e8827d71d9703faa': after
};
const created = [], mutated = [], deleted = [], result = {};
const vars = {};
for (const [role, id] of Object.entries({ canvas: 'VariableID:13:39', surface: 'VariableID:13:29', line: 'VariableID:13:31', ink: 'VariableID:13:32', secondary: 'VariableID:13:33' })) vars[role] = await figma.variables.getVariableByIdAsync(id);
function solid(role) { return figma.variables.setBoundVariableForPaint({ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars[role]); }
function made(n) { created.push(n.id); return n; }
function changed(n) { mutated.push(n.id); return n; }
function remove(n) { deleted.push(n.id, ...('findAll' in n ? n.findAll().map(c => c.id) : [])); n.remove(); }
function imageRect(parent, hash, width, height, name) {
  const n = made(figma.createRectangle()); parent.appendChild(n); n.name = name;
  n.resize(width, height); n.fills = [{ type: 'IMAGE', imageHash: hash, scaleMode: 'FILL' }];
  return n;
}
const componentIds = ['13:130', '13:131', '13:132', '13:133', '13:134', '13:135', '13:136'];
for (const id of componentIds) {
  const component = await figma.getNodeByIdAsync(id);
  if (!component) throw new Error('Missing existing product component ' + id);
  for (const n of component.findAll(c => 'fills' in c && Array.isArray(c.fills) && c.fills.some(p => p.type === 'IMAGE'))) {
    n.fills = n.fills.map(p => {
      if (p.type !== 'IMAGE' || !hashMap[p.imageHash]) return p;
      const hash = hashMap[p.imageHash];
      if (n.width > 200) return { type: 'IMAGE', imageHash: id === '13:130' || id === '13:132' ? selfie : hash, scaleMode: 'FIT' };
      if (n.width <= 48) return { type: 'IMAGE', imageHash: hash, scaleMode: 'CROP', imageTransform: [[1, 0, 0], [0, hash === selfie ? 0.76 : 0.5628, 0.06]] };
      return { type: 'IMAGE', imageHash: hash, scaleMode: 'CROP', imageTransform: [[1, 0, 0], [0, hash === selfie ? 0.57 : 0.4221, 0.06]] };
    }); changed(n);
    if (/alpine/.test(n.parent.name)) { n.parent.name = n.parent.name.replace('alpine-before', 'portrait-original').replace('alpine-after', 'portrait-handbag-removed'); changed(n.parent); }
  }
  for (const t of component.findAllWithCriteria({ types: ['TEXT'] })) {
    if (t.characters === 'kyoto-dawn.heic') { t.characters = 'portrait-original.png'; changed(t); }
    if (t.characters === 'kyoto-dawn-graded.heic') { t.characters = 'portrait-handbag-removed.png'; changed(t); }
    if (t.characters.includes('4032 × 3024')) { t.characters = '941 × 1672   PNG'; changed(t); }
  }
  if (id === '13:134') { component.name = 'Glance / Product / portrait-original'; changed(component); }
  if (id === '13:135') { component.name = 'Glance / Product / portrait-handbag-removed'; changed(component); }
  if (id === '13:136') { component.name = 'Glance / Product / portrait-selfie'; changed(component); }
}
// Replace only the comparison stage; keep the native App window chrome intact.
for (const id of ['13:131', '13:133']) {
  const component = await figma.getNodeByIdAsync(id);
  const old = component.findOne(n => n.name === 'compare stage');
  if (old) remove(old);
  const stage = made(figma.createAutoLayout('HORIZONTAL')); component.appendChild(stage);
  stage.name = 'compare stage'; stage.resize(840, 704); stage.x = 300; stage.y = 72;
  stage.primaryAxisSizingMode = 'FIXED'; stage.counterAxisSizingMode = 'FIXED'; stage.itemSpacing = 24; stage.fills = [];
  for (const [hash, label] of [[before, 'A · Original'], [after, 'B · Handbag removed']]) {
    const card = made(figma.createAutoLayout('VERTICAL')); stage.appendChild(card);
    card.name = label; card.resize(408, 704); card.primaryAxisSizingMode = 'FIXED'; card.counterAxisSizingMode = 'FIXED'; card.itemSpacing = 0;
    card.fills = [solid('canvas')]; card.clipsContent = true; card.cornerRadius = 4;
    imageRect(card, hash, 408, 664, label + ' / photo');
    const bar = made(figma.createAutoLayout('HORIZONTAL')); card.appendChild(bar); bar.name = label + ' / caption'; bar.resize(408, 40);
    bar.primaryAxisSizingMode = 'FIXED'; bar.counterAxisSizingMode = 'FIXED'; bar.primaryAxisAlignItems = 'CENTER'; bar.counterAxisAlignItems = 'CENTER'; bar.fills = [solid('surface')];
    const t = made(figma.createText()); t.fontName = { family: 'Inter', style: 'Regular' }; t.characters = label; t.fontSize = 16; t.lineHeight = { unit: 'PIXELS', value: 24 }; t.fills = [solid('ink')]; bar.appendChild(t);
  }
  for (const t of component.findAllWithCriteria({ types: ['TEXT'] })) if (t.characters === 'Slider' || t.characters === 'Side by side') { t.fills = [solid(t.characters === 'Side by side' ? 'ink' : 'secondary')]; changed(t); }
  component.description = 'Website product preview using the original Glance window chrome with a native side-by-side portrait stage. Exact user-supplied portrait-original.png and portrait-handbag-removed.png. Unslop by Damir Sokolovsky, CC BY 4.0.'; changed(component);
}
// The first screen shows the concrete transformation; View retains a full portrait.
for (const old of page.findAllWithCriteria({ types: ['INSTANCE'] }).filter(n => n.parent.name === 'Product / Native latest Image Inspect')) {
  const parent = old.parent, w = old.width, h = old.height;
  const component = await figma.getNodeByIdAsync(old.name.includes('washi') ? '13:133' : '13:131');
  const copy = made(component.createInstance()); parent.appendChild(copy); copy.rescale(Math.min(w / component.width, h / component.height)); copy.x = 0; copy.y = 0;
  copy.name = 'Product view / ' + (old.name.includes('washi') ? 'washi' : 'sumi') + '/compare'; created.push(...copy.findAll().map(n => n.id)); remove(old);
}
let mobileCount = 0;
for (const frame of page.findAllWithCriteria({ types: ['FRAME'] }).filter(n => n.name === 'Product / Mobile compare detail')) {
  const media = frame.findOne(n => n.name === 'Comparison image');
  if (!media) throw new Error('Missing known mobile image stage');
  for (const child of [...media.children]) remove(child);
  media.layoutMode = 'HORIZONTAL'; media.primaryAxisSizingMode = 'FIXED'; media.counterAxisSizingMode = 'FIXED'; media.itemSpacing = 8; media.paddingTop = 0; media.paddingBottom = 0; media.paddingLeft = 0; media.paddingRight = 0;
  media.fills = []; media.clipsContent = true; media.layoutSizingHorizontal = 'FILL'; changed(media);
  for (const [hash, name] of [[before, 'Portrait / Original'], [after, 'Portrait / Handbag removed']]) { const image = imageRect(media, hash, (media.width - 8) / 2, 316, name); image.layoutSizingHorizontal = 'FILL'; }
  for (const t of frame.findAllWithCriteria({ types: ['TEXT'] })) {
    if (t.name === 'Filename') { t.characters = 'portrait-compare.png'; changed(t); }
    if (t.name === 'Result label') { t.characters = /[\u2e80-\uffff]/u.test(t.characters) ? '移除手包' : 'Bag removed'; changed(t); }
  }
  mobileCount++;
}
for (const frame of page.children.filter(n => / · Home \//.test(n.name))) {
  const zh = frame.name.includes('中文');
  for (const t of frame.findAllWithCriteria({ types: ['TEXT'] })) {
    if (t.name === 'Product caption') { t.characters = zh ? '左边是原图，右边是移除手包后的结果' : 'Original on the left. Handbag removed on the right'; changed(t); }
    if (t.name === 'Widget menu title / 0') { t.characters = zh ? '移除物体' : 'Remove Objects'; changed(t); }
    if (t.name === 'Widget menu cost / 0') { t.characters = zh ? '30 点' : '30 credits'; changed(t); }
  }
}
for (const n of page.findAllWithCriteria({ types: ['FRAME', 'INSTANCE'] })) {
  if (n.name.includes('Native sample / landscape')) { n.name = 'Portrait sample / Original'; changed(n); }
  if (n.name === 'Native sample / sakura') { n.name = 'Portrait sample / Editorial selfie'; changed(n); }
  if (n.type === 'INSTANCE' && /Product view \/ (landscape|warm|sakura)$/.test(n.name)) { n.name = n.name.replace('landscape', 'portrait-original').replace('warm', 'portrait-handbag-removed').replace('sakura', 'portrait-selfie'); changed(n); }
}
// Uploaded raw photo frames were transfer assets; remove them after consuming fills.
for (const id of ['20:1590', '20:1591']) { const n = await figma.getNodeByIdAsync(id); if (n) remove(n); }
const homeIds = ['15:2', '15:969', '15:1545', '15:2512', '15:3216', '15:4183', '15:4759', '15:5726'];
const boards = [];
for (const id of homeIds) {
  const b = await figma.getNodeByIdAsync(id), all = b.findAll();
  const stale = all.filter(n => 'fills' in n && Array.isArray(n.fills) && n.fills.some(p => p.type === 'IMAGE' && [oldBefore, oldAfter, oldPortrait, '1f255bdf84bf014bb676abb8e8827d71d9703faa'].includes(p.imageHash)));
  boards.push({ id, name: b.name, remainingLandscapeOrOldPortrait: stale.map(n => n.id), heroId: b.findOne(n => n.name === '02 / Hero').id });
}
function pack(values) { const map = {}; for (const id of new Set(values)) { const at = id.lastIndexOf(':') + 1, prefix = id.slice(0, at); (map[prefix] ??= []).push(id.slice(at)); } return Object.fromEntries(Object.entries(map).map(([p, ids]) => [p, ids.join(',')])); }
return { createdNodeIdsByPrefix: pack(created), mutatedNodeIdsByPrefix: pack(mutated), removedNodeIdsByPrefix: pack(deleted), boards, mobileComparisons: mobileCount, sourceImages: { before, after, selfie }, generatedImages: 0 };
