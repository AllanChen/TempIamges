/* Native Figma MCP renderer. Unslop method: Damir Sokolovsky, CC BY 4.0.
 * The caller supplies DESIGN and FOUNDATION. Only the independent website file
 * is writable. Layout groups preserve the approved composition as auto-layout.
 */
if (figma.fileKey !== 'kWvE51F9IfI3oSN6ZoxeKw') throw new Error('Wrong target file');
const page = await figma.getNodeByIdAsync('0:1');
await figma.setCurrentPageAsync(page);
const fontNames = [
  ['Inter', 'Regular'], ['Inter', 'Medium'], ['Geist Mono', 'Regular'],
  ['Shippori Mincho', 'Regular'], ['Noto Serif SC', 'Regular'],
  ['Noto Sans SC', 'Regular'], ['Noto Sans SC', 'Medium']
];
await Promise.all(fontNames.map(([family, style]) => figma.loadFontAsync({ family, style })));
const colorCollection = await figma.variables.getVariableCollectionByIdAsync(FOUNDATION.collections.color);
const variables = {}, components = {}, sources = {}, floats = {};
for (const [key, id] of Object.entries(FOUNDATION.variables)) variables[key] = await figma.variables.getVariableByIdAsync(id);
for (const [key, id] of Object.entries(FOUNDATION.floats)) floats[key] = await figma.variables.getVariableByIdAsync(id);
for (const [key, value] of Object.entries(FOUNDATION.buttons)) components[key] = await figma.getNodeByIdAsync(value.id);
for (const [key, id] of Object.entries(FOUNDATION.sources)) sources[key] = await figma.getNodeByIdAsync(id);
const created = [], overflows = [], boards = [], drift = [], externalLinks = [];
let autoLayouts = 0, textCount = 0, instanceCount = 0, photoSlots = 0;
const rgb = h => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255 });
function paint(hex, theme) {
  const p = { type: 'SOLID', color: rgb(hex) };
  const role = Object.keys(DESIGN.themes[theme]).find(k => DESIGN.themes[theme][k] === hex);
  return role ? figma.variables.setBoundVariableForPaint(p, 'color', variables[role]) : p;
}
function track(n) { created.push(n.id); return n; }
function rect(spec, parent) {
  const n = track(figma.createRectangle()); parent.appendChild(n);
  n.name = spec.name; n.resize(Math.max(0.01, spec.w), Math.max(0.01, spec.h));
  n.fills = spec.fill ? [paint(spec.fill, spec.theme)] : [];
  if (spec.stroke) { n.strokes = [paint(spec.stroke, spec.theme)]; n.strokeWeight = 1; }
  n.cornerRadius = spec.radius || 0;
  return n;
}
function clusters(items, axis) {
  const size = axis === 'x' ? 'w' : 'h';
  const sorted = [...items].sort((a, b) => a[axis] - b[axis]);
  const groups = [];
  for (const item of sorted) {
    const last = groups[groups.length - 1];
    if (!last || item[axis] >= last.end - 0.01) groups.push({ start: item[axis], end: item[axis] + item[size], items: [item] });
    else { last.items.push(item); last.end = Math.max(last.end, item[axis] + item[size]); }
  }
  return groups;
}
function frameBase(spec, parent, direction) {
  const n = track(direction ? figma.createAutoLayout(direction) : figma.createFrame());
  if (direction) autoLayouts++;
  parent.appendChild(n); n.name = spec.name; n.resize(spec.w, spec.h);
  n.fills = spec.fill ? [paint(spec.fill, spec.theme)] : []; n.clipsContent = false;
  if (spec.stroke) { n.strokes = [paint(spec.stroke, spec.theme)]; n.strokeWeight = 1; }
  n.cornerRadius = spec.radius || 0;
  if (spec.radius && floats['radius/' + spec.radius]) for (const c of ['topLeftRadius', 'topRightRadius', 'bottomLeftRadius', 'bottomRightRadius']) n.setBoundVariable(c, floats['radius/' + spec.radius]);
  if (direction) { n.primaryAxisSizingMode = 'FIXED'; n.counterAxisSizingMode = 'FIXED'; n.itemSpacing = 0; }
  return n;
}
async function compose(spec, parent, ctx) {
  const items = spec.children || [];
  let axis = null, groups;
  if (items.length > 1) {
    const ys = clusters(items, 'y'), xs = clusters(items, 'x');
    if (ys.length > 1) { axis = 'y'; groups = ys; }
    else if (xs.length > 1) { axis = 'x'; groups = xs; }
  } else if (items.length === 1 && items[0].x >= 0 && items[0].y >= 0 && items[0].x + items[0].w <= spec.w + 0.01 && items[0].y + items[0].h <= spec.h + 0.01) {
    axis = 'y'; groups = [{ start: items[0].y, end: items[0].y + items[0].h, items }];
  }
  const n = frameBase(spec, parent, axis ? axis === 'y' ? 'VERTICAL' : 'HORIZONTAL' : null);
  if (/Result half|Comparison image/.test(spec.name)) n.clipsContent = true;
  if (!axis) {
    for (const child of items) { const out = await render(child, n, ctx); out.x = child.x; out.y = child.y; }
    return n;
  }
  const vertical = axis === 'y', max = vertical ? spec.h : spec.w;
  n[vertical ? 'paddingTop' : 'paddingLeft'] = Math.max(0, groups[0].start);
  n[vertical ? 'paddingBottom' : 'paddingRight'] = Math.max(0, max - groups[groups.length - 1].end);
  for (let i = 0; i < groups.length; i++) {
    const g = groups[i];
    // Groups preserve independent columns and rows without flattening content.
    const chunk = {
      type: 'FRAME', name: (vertical ? 'Row / ' : 'Column / ') + g.items[0].name,
      theme: spec.theme, x: 0, y: 0, w: vertical ? spec.w : g.end - g.start,
      h: vertical ? g.end - g.start : spec.h,
      children: g.items.map(c => ({ ...c, x: c.x - (vertical ? 0 : g.start), y: c.y - (vertical ? g.start : 0) }))
    };
    let out;
    if (g.items.length === 1) {
      const only = chunk.children[0];
      const holder = frameBase({ ...chunk, children: [] }, n, vertical ? 'HORIZONTAL' : 'VERTICAL');
      holder.paddingLeft = Math.max(0, only.x); holder.paddingTop = Math.max(0, only.y);
      holder.paddingRight = Math.max(0, chunk.w - only.x - only.w);
      holder.paddingBottom = Math.max(0, chunk.h - only.y - only.h);
      await render(only, holder, ctx); out = holder;
    } else out = await compose(chunk, n, ctx);
    if (vertical) out.layoutSizingHorizontal = 'FILL'; else out.layoutSizingVertical = 'FILL';
    const gap = i < groups.length - 1 ? groups[i + 1].start - g.end : 0;
    if (gap > 0.01) {
      const spacer = frameBase({ name: 'Spacing / ' + gap, theme: spec.theme, w: vertical ? spec.w : gap, h: vertical ? gap : spec.h }, n);
      if (vertical) spacer.layoutSizingHorizontal = 'FILL'; else spacer.layoutSizingVertical = 'FILL';
    }
  }
  return n;
}
async function render(spec, parent, ctx) {
  let n;
  if (spec.type === 'TEXT') {
    n = track(figma.createText()); parent.appendChild(n); textCount++;
    const zh = /[\u2E80-\uFFFF]/u.test(spec.text);
    const family = spec.fontRole === 'display' ? zh ? 'Noto Serif SC' : 'Shippori Mincho' : spec.fontRole === 'mono' && !zh ? 'Geist Mono' : zh ? 'Noto Sans SC' : 'Inter';
    const style = spec.weight === 500 && spec.fontRole !== 'display' ? 'Medium' : 'Regular';
    n.fontName = { family, style }; n.fontSize = spec.size;
    n.lineHeight = { unit: 'PIXELS', value: spec.lineHeight };
    n.letterSpacing = { unit: 'PIXELS', value: spec.tracking || 0 };
    n.characters = spec.text; n.textAutoResize = 'HEIGHT'; n.resize(spec.w, spec.h);
    n.textAlignHorizontal = spec.align || 'LEFT'; n.fills = [paint(spec.color, spec.theme)];
    const key = [family, spec.size, style, spec.lineHeight].join('/');
    if (FOUNDATION.styles[key]) await n.setTextStyleIdAsync(FOUNDATION.styles[key]);
    if (n.height > spec.h + 1) overflows.push({ id: n.id, name: spec.name, text: spec.text, width: n.width, expectedHeight: spec.h, actualHeight: n.height, family, size: spec.size });
  } else if (spec.type === 'ICON') {
    const path = spec.icon === 'menu' ? '<path d="M2 5h12M2 11h12"/>' : '<rect x="2" y="3" width="12" height="10" rx="2"/><path d="M8 3v10"/>';
    n = track(figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" stroke="' + spec.color + '" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' + path + '</svg>'));
    parent.appendChild(n); n.resize(16, 16); created.push(...n.findAll().map(x => x.id));
  } else if (spec.layout && spec.children?.[0]?.name === 'Label') {
    const child = spec.children[0], lang = /[\u2E80-\uFFFF]/u.test(child.text) ? 'zh' : 'en';
    const intent = spec.stroke ? 'Secondary' : 'Primary';
    const state = /Hover/.test(spec.name) ? 'Hover' : /Pressed/.test(spec.name) ? 'Pressed' : /Keyboard focus/.test(spec.name) ? 'Focus' : 'Default';
    const key = lang + '/' + intent + '/' + state;
    n = track(components[key].createInstance()); parent.appendChild(n); n.resize(spec.w, spec.h);
    n.setProperties({ [FOUNDATION.buttons[key].labelKey]: child.text });
    instanceCount++; created.push(...n.findAll().map(x => x.id));
  } else if (spec.sourceRef) {
    n = frameBase(spec, parent); n.clipsContent = true;
    const key = ['focus', 'compare'].includes(spec.sourceRef) ? spec.theme + '/' + spec.sourceRef : spec.sourceRef;
    const source = sources[key]; if (!source) throw new Error('Missing product component ' + key);
    const copy = track(source.createInstance()); n.appendChild(copy);
    const scale = ['focus', 'compare'].includes(spec.sourceRef)
      ? Math.min(spec.w / source.width, spec.h / source.height)
      : Math.max(spec.w / source.width, spec.h / source.height);
    copy.rescale(scale);
    copy.x = (spec.w - copy.width) / 2; copy.y = (spec.h - copy.height) / 2;
    copy.name = 'Product view / ' + key; instanceCount++; photoSlots++;
    created.push(...copy.findAll().map(x => x.id));
  } else if (!spec.children?.length) n = rect(spec, parent);
  else n = await compose(spec, parent, ctx);
  n.name = spec.name;
  if (spec.anchor) ctx.anchors[spec.anchor] = n;
  if (spec.target) ctx.links.push({ node: n, target: spec.target });
  return n;
}
for (const spec of DESIGN.frames) {
  if (page.children.some(n => n.name === spec.name)) { boards.push({ name: spec.name, reused: true }); continue; }
  const ctx = { anchors: {}, links: [] };
  const board = await render(spec, page, ctx); board.x = spec.x + 160; board.y = spec.y + 160;
  board.setExplicitVariableModeForCollection(colorCollection, FOUNDATION.modes[spec.theme]);
  board.clipsContent = true;
  if (spec.lang) {
    board.overflowDirection = 'VERTICAL'; board.resize(spec.w, spec.h);
  }
  for (const { node, target } of ctx.links) {
    let action;
    if (target.startsWith('#')) {
      const destination = ctx.anchors[target.slice(1)]; if (!destination) throw new Error('Missing anchor ' + target);
      action = { type: 'NODE', destinationId: destination.id, navigation: 'SCROLL_TO', transition: null };
    } else {
      const url = target.startsWith('/') ? 'https://glancepreview.com' + (spec.lang === 'en' && target !== '/en/' && target !== '/' ? '/en' : '') + target : target;
      action = { type: 'URL', url, openInNewTab: true }; externalLinks.push(url);
    }
    await node.setReactionsAsync([{ trigger: { type: 'ON_CLICK' }, actions: [action] }]);
  }
  board.placeholder = false;
  boards.push({ id: board.id, name: board.name, width: board.width, height: board.height, sectionCount: spec.lang ? spec.children.length : 0, links: ctx.links.length, children: board.children.map(n => ({ id: n.id, name: n.name, x: n.x, y: n.y, width: n.width, height: n.height })) });
}
page.selection = boards.filter(b => b.id).slice(0, 1).map(b => page.children.find(n => n.id === b.id));
if (page.selection.length) figma.viewport.scrollAndZoomIntoView(page.selection);
// Preserve every created ID without exceeding the MCP's 48 KB return limit.
// Reconstruct an ID by concatenating its prefix and each comma-separated suffix.
const ids = {};
for (const id of new Set(created)) {
  const at = id.lastIndexOf(':') + 1, prefix = id.slice(0, at);
  (ids[prefix] ??= []).push(id.slice(at));
}
return {
  createdNodeIdsByPrefix: Object.fromEntries(Object.entries(ids).map(([prefix, values]) => [prefix, values.join(',')])),
  boards: boards.map(({ children, ...board }) => board), overflows,
  counts: { autoLayouts, text: textCount, instances: instanceCount, photoSlots },
  externalLinks: [...new Set(externalLinks)]
};
