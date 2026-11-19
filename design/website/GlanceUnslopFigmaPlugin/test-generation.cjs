'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createDesign } = require('./design.cjs');
const { readPortableSources, normalizeSvgUnicode } = require('./build.cjs');

const source = fs.readFileSync(__dirname + '/code.js', 'utf8');
const portable = readPortableSources();
function environment(options = {}) {
  let serial = 0, lookupCalls = 0;
  const made = [], svgImports = [], loadedFonts = new Set();
  function node(type) {
    const data = {}, n = {
      id: 'test:' + (++serial), type, children: [], name: '', x: 0, y: 0,
      width: 100, height: 100, parent: null,
      resize(w, h) { assert.ok(w > 0 && h > 0); this.width = w; this.height = h; },
      appendChild(child) {
        if (child.parent) child.remove();
        child.parent = this; this.children.push(child);
      },
      remove() {
        if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1);
        this.parent = null;
      },
      clone() {
        const copy = node(this.type);
        for (const [key, value] of Object.entries(this)) if (typeof value !== 'function' && !['id', 'parent', 'children'].includes(key)) copy[key] = structuredClone(value);
        for (const child of this.children) copy.appendChild(child.clone());
        return copy;
      },
      rescale(scale) {
        this.width *= scale; this.height *= scale;
        for (const child of this.children) { child.x *= scale; child.y *= scale; child.rescale(scale); }
      },
      setPluginData(key, value) { data[key] = value; },
      getPluginData(key) { return data[key] || ''; },
      async setReactionsAsync(reactions) { this.reactions = reactions; }
    };
    made.push(n); return n;
  }
  const design = createDesign();
  const root = node('DOCUMENT'), original = node('PAGE'), oldWebsite = node('PAGE');
  root.name = options.appReference ? 'macOS App UI' : 'Glance — Website / Unslop';
  original.name = options.appReference ? 'Sumi · Dark' : 'Page 1';
  oldWebsite.name = options.appReference ? 'Washi · Light' : 'Glance / Website / Unslop';
  root.appendChild(original); root.appendChild(oldWebsite);
  const keep = node('FRAME'); keep.name = 'User artwork'; original.appendChild(keep);
  const figma = {
    editorType: options.dev ? 'dev' : 'figma',
    fileKey: options.noFileKey ? undefined : options.appReference ? design.sourceFileKey : 'kWvE51F9IfI3oSN6ZoxeKw',
    root, currentPage: original,
    ui: { messages: [], postMessage(m) { this.messages.push(m); } },
    viewport: { scrollAndZoomIntoView() {} }, showUI() {},
    listAvailableFontsAsync: async () => options.noFonts ? [] :
      ['Inter', 'Noto Sans SC', 'Noto Serif SC', 'Shippori Mincho', 'Geist Mono'].flatMap(family => ['Regular', 'Medium'].map(style => ({ fontName: { family, style } }))),
    getNodeByIdAsync() { lookupCalls++; throw new Error('No App source nodes exist in the website file'); },
    loadFontAsync: async font => {
      if (options.fontFailure) throw new Error('font load failure');
      loadedFonts.add(font.family);
    },
    createPage() { const p = node('PAGE'); root.appendChild(p); return p; },
    async setCurrentPageAsync(p) { this.currentPage = p; },
    createFrame() {
      if (options.failMidway && made.length > 100) throw new Error('injected render failure');
      return node('FRAME');
    },
    createText: () => node('TEXT'),
    createNodeFromSvg(svg) {
      if (options.importFailure && svg.includes('data:image')) throw new Error('injected SVG import failure');
      assert.ok(!/__GLANCE_IMAGE_\d+__/.test(svg), 'All photo references must be resolved before SVG import');
      assert.ok(!/(?:href|xlink:href)=["']https?:/i.test(svg), 'SVG must be self-contained');
      for (const match of svg.matchAll(/font-family="([^"]+)"/g)) assert.ok(loadedFonts.has(match[1]), 'SVG font must be loaded: ' + match[1]);
      const n = node('FRAME');
      const size = svg.match(/<svg[^>]*\bwidth="([\d.]+)"[^>]*\bheight="([\d.]+)"/);
      assert.ok(size, 'SVG import must retain its root dimensions');
      n.resize(Number(size[1]), Number(size[2]));
      if (svg.includes('data:image')) svgImports.push({ w: n.width, h: n.height });
      return n;
    }
  };
  vm.runInNewContext(source, { figma, __html__: '' });
  return { figma, original, oldWebsite, keep, svgImports, get lookupCalls() { return lookupCalls; }, generate: () => figma.ui.onmessage({ type: 'generate' }) };
}
function all(n) { return [n, ...n.children.flatMap(all)]; }

(async () => {
  const d = createDesign();
  assert.equal(d.frames.length, 10);
  assert.match(d.fileUrl, /kWvE51F9IfI3oSN6ZoxeKw/);
  assert.match(d.referenceFileUrl, /3oIkv5jBJpRUORxliJZdHl/);
  assert.equal(Object.keys(portable.views).length, 7);
  assert.deepEqual(Object.keys(portable.images).sort(), ['paris-balcony', 'paris-selfie', 'portrait-handbag-removed', 'portrait-original']);
  assert.equal(normalizeSvgUnicode('4032 &#195;&#151; 3024'), '4032 × 3024');
  for (const [key, view] of Object.entries(portable.views)) {
    assert.ok(view.w > 0 && view.h > 0);
    assert.match(view.svg, new RegExp('width="' + view.w + '"'));
    for (const name of view.images) assert.match(portable.images[name], /^data:image\/(jpeg|png);base64,/);
    assert.ok(!/(?:href|xlink:href)=["']https?:/i.test(view.svg), key + ' must not use temporary URLs');
  }
  function geometry(n, parent) {
    assert.ok(n.w > 0 && n.h > 0, n.name + ' must have real bounds');
    if (parent && !n.intentionalCrop && n.x >= 0) assert.ok(n.x + n.w <= parent.w + 1, n.name + ' must fit horizontally');
    if (parent && !n.intentionalCrop) assert.ok(n.y >= 0 && n.y + n.h <= parent.h + 1, n.name + ' must fit vertically');
    if (n.type === 'TEXT') {
      assert.ok([400, 500].includes(n.weight));
      assert.ok(!/!!|✨|🚀|🔥/.test(n.text));
      assert.ok(n.size >= 11); assert.ok(n.size >= 40 || n.tracking >= 0);
      assert.ok(!/\n[，。、：；！？）】」』]/u.test(n.text));
    }
    const texts = (n.children || []).filter(c => c.type === 'TEXT');
    for (let i = 0; i < texts.length; i++) for (let j = i + 1; j < texts.length; j++) {
      const a = texts[i], b = texts[j];
      const intersects = Math.min(a.x + a.w, b.x + b.w) > Math.max(a.x, b.x) + 2
        && Math.min(a.y + a.h, b.y + b.h) > Math.max(a.y, b.y) + 2;
      assert.ok(!intersects, n.name + ': overlapping ' + a.name + ' / ' + b.name);
    }
    for (const child of n.children || []) geometry(child, n);
  }
  for (const f of d.frames) for (const child of f.children) geometry(child, f);
  for (const opts of [{}, { noFileKey: true }]) {
    const env = environment(opts);
    assert.equal(env.figma.root.children.length, 2, 'Opening plugin must not write to canvas');
    await Promise.all([env.generate(), env.generate()]);
    assert.equal(env.figma.ui.messages.at(-1).type, 'done', env.figma.ui.messages.at(-1).message);
    assert.equal(env.lookupCalls, 0, 'Independent website file must never query App node IDs');
    assert.equal(env.figma.root.children.length, 3);
    assert.equal(env.svgImports.length, 7, 'Each portable reference should import once and then be cloned');
    const page = env.figma.currentPage;
    assert.equal(page.children.length, 10);
    assert.ok(all(page).filter(n => n.name.startsWith('App reference / ')).length >= 20);
    assert.ok(env.original.children.includes(env.keep));
    assert.ok(env.figma.root.children.includes(env.oldWebsite));
    const text = all(page).find(n => n.type === 'TEXT' && n.characters === 'Glance');
    text.characters = 'My manual edit';
    await env.generate();
    assert.equal(env.figma.root.children.length, 3);
    assert.equal(text.characters, 'My manual edit');
    assert.ok(env.figma.ui.messages.at(-1).result.reused);
    const links = all(page).filter(n => n.reactions);
    function targets(n) { return (n.target ? 1 : 0) + (n.children || []).reduce((sum, c) => sum + targets(c), 0); }
    assert.equal(links.length, d.frames.reduce((sum, f) => sum + targets(f), 0));
    for (const n of links) {
      const action = n.reactions[0].actions[0];
      if (action.type === 'NODE') assert.ok(all(page).some(n => n.id === action.destinationId));
      else assert.match(action.url, /^(https:\/\/glancepreview\.com|mailto:)/);
    }
  }
  for (const opts of [{ dev: true }, { appReference: true }, { appReference: true, noFileKey: true }, { noFonts: true }, { fontFailure: true }, { failMidway: true }, { importFailure: true }]) {
    const env = environment(opts);
    await env.generate();
    assert.equal(env.figma.root.children.length, 2, 'Failure must leave no partial page: ' + JSON.stringify(opts));
    assert.equal(env.figma.currentPage, env.original);
    assert.ok(env.original.children.includes(env.keep));
    assert.equal(env.figma.ui.messages.at(-1).type, 'error');
    assert.equal(env.lookupCalls, 0);
    if (opts.appReference) assert.match(env.figma.ui.messages.at(-1).message, /独立网站文件/);
  }
  console.log('PASS: independent website generation without App nodes, seven portable SVGs and four portrait assets, loaded fonts, App-file protection, geometry, links, preserved edits, duplicate clicks, and rollback');
})().catch(error => { console.error(error); process.exitCode = 1; });
