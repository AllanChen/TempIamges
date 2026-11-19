/* Bundled by build.cjs. Unslop method: Damir Sokolovsky, CC BY 4.0.
 * All canvas writes happen only when the user presses Generate in Design Mode.
 */
'use strict';

// __DESIGN_AND_ASSETS__

const MARKER = 'glance-website-shizuka-portable-v3';
const BUILD_LABEL = 'Shizuka 3.0';
let busy = false;
figma.showUI(__html__, { width: 360, height: 360, themeColors: true });

function paint(hex) {
  return { type: 'SOLID', color: {
    r: parseInt(hex.slice(1, 3), 16) / 255,
    g: parseInt(hex.slice(3, 5), 16) / 255,
    b: parseInt(hex.slice(5, 7), 16) / 255
  } };
}

function normalizedName(value) {
  return String(value || '').normalize('NFKC').toLowerCase()
    .replace(/[\u200B-\u200D\uFEFF]/g, '')
    .replace(/^\s*\d+\s*[·.、\-–—:]?\s*/, '')
    .replace(/[·•・]/g, ' ').replace(/\s*\/\s*/g, '/')
    .replace(/\s+/g, ' ').trim();
}

function isAppReferenceFile() {
  return figma.fileKey === DESIGN.sourceFileKey || figma.root.children.some(page =>
    ['sumi dark', 'washi light'].includes(normalizedName(page.name)));
}

function validatePortableSources() {
  for (const key of Object.keys(DESIGN.sources)) {
    const view = PORTABLE.views[key];
    if (!view || !view.svg || view.images.some(name => !PORTABLE.images[name])) throw new Error('参考素材包不完整，请重新载入插件。');
  }
}

function sourceSvg(key) {
  const view = PORTABLE.views[key];
  return view.svg.replace(/__GLANCE_IMAGE_(\d+)__/g, (_, index) => PORTABLE.images[view.images[Number(index)]]);
}

async function fontsForDesign() {
  const list = (await figma.listAvailableFontsAsync()).map(v => v.fontName);
  function pair(families) {
    for (const family of families) {
      const regular = list.find(f => f.family === family && f.style === 'Regular');
      const medium = list.find(f => f.family === family && f.style === 'Medium');
      if (regular && medium) return { regular, medium };
    }
    throw new Error('A required font is unavailable. Enable Inter and Noto Sans SC, then run Generate again.');
  }
  function regular(families) {
    for (const family of families) {
      const font = list.find(f => f.family === family && f.style === 'Regular');
      if (font) return font;
    }
    throw new Error('请启用设计稿中的字体：' + families[0]);
  }
  const latin = pair(['Inter']);
  const chinese = pair(['Noto Sans SC', 'Noto Sans CJK SC', 'PingFang SC']);
  const display = regular(['Shippori Mincho']);
  const chineseDisplay = regular(['Noto Serif SC', 'Source Han Serif SC', 'Songti SC']);
  const mono = regular(['Geist Mono']);
  const unique = new Map();
  for (const font of [latin.regular, latin.medium, chinese.regular, chinese.medium, display, chineseDisplay, mono]) unique.set(JSON.stringify(font), font);
  await Promise.all([...unique.values()].map(f => figma.loadFontAsync(f)));
  return { latin, chinese, display, chineseDisplay, mono };
}

const PATHS = {
  menu: '<path d="M2 5h12M2 11h12"/>',
  compare: '<rect x="2" y="3" width="12" height="10" rx="2"/><path d="M8 3v10"/>'
};

function renderNode(spec, parent, ctx) {
  let n;
  if (spec.type === 'TEXT') {
    n = figma.createText();
    const chinese = /[\u2E80-\uFFFF]/u.test(spec.text);
    const set = chinese ? ctx.fonts.chinese : ctx.fonts.latin;
    n.fontName = spec.fontRole === 'display'
      ? (chinese ? ctx.fonts.chineseDisplay : ctx.fonts.display)
      : spec.fontRole === 'mono' && !chinese ? ctx.fonts.mono : spec.weight === 500 ? set.medium : set.regular;
    n.fontSize = spec.size;
    n.lineHeight = { unit: 'PIXELS', value: spec.lineHeight };
    n.letterSpacing = { unit: 'PIXELS', value: spec.tracking || 0 };
    n.characters = spec.text;
    n.textAutoResize = 'NONE';
    n.textAlignHorizontal = spec.align || 'LEFT';
    n.fills = [paint(spec.color)];
    n.resize(spec.w, spec.h);
  } else if (spec.type === 'ICON') {
    n = figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="' + spec.color + '" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' + PATHS[spec.icon] + '</svg>');
    n.resize(16, 16);
  } else {
    n = figma.createFrame();
    n.resize(spec.w, spec.h);
    n.fills = spec.fill ? [paint(spec.fill)] : [];
    n.clipsContent = true;
    n.cornerRadius = spec.radius || 0;
    if (spec.stroke) { n.strokes = [paint(spec.stroke)]; n.strokeWeight = 1; }
    if (spec.asset) n.fills = [{ type: 'IMAGE', imageHash: ctx.images[spec.asset], scaleMode: ['focus', 'compare', 'editEn', 'editZh'].includes(spec.asset) ? 'FIT' : 'FILL' }];
  }
  n.name = spec.name;
  parent.appendChild(n);
  n.x = spec.x; n.y = spec.y;
  if (spec.sourceRef) {
    const key = ['focus', 'compare'].includes(spec.sourceRef) ? spec.theme + '/' + spec.sourceRef : spec.sourceRef;
    const cached = ctx.sourceCache[key];
    const copy = cached ? cached.clone() : figma.createNodeFromSvg(sourceSvg(key));
    n.appendChild(copy);
    const scale = ['focus', 'compare'].includes(spec.sourceRef)
      ? Math.min(spec.w / copy.width, spec.h / copy.height)
      : Math.max(spec.w / copy.width, spec.h / copy.height);
    copy.rescale(scale);
    copy.x = (spec.w - copy.width) / 2;
    copy.y = (spec.h - copy.height) / 2;
    copy.name = 'App reference / ' + key;
    if (!cached) ctx.sourceCache[key] = copy;
  }
  if (spec.anchor) ctx.anchors[spec.anchor] = n;
  if (spec.target) ctx.links.push({ node: n, target: spec.target });
  for (const child of spec.children || []) renderNode(child, n, ctx);
  if (spec.layout) {
    n.layoutMode = spec.layout.direction;
    n.primaryAxisSizingMode = 'FIXED';
    n.counterAxisSizingMode = 'FIXED';
    n.primaryAxisAlignItems = 'CENTER';
    n.counterAxisAlignItems = 'CENTER';
    n.paddingLeft = spec.layout.padding; n.paddingRight = spec.layout.padding;
    n.itemSpacing = spec.layout.gap;
  }
  return n;
}

async function generate() {
  if (figma.editorType !== 'figma') throw new Error('Press Shift+D to switch to Figma Design Mode, then run this plugin again.');
  if (isAppReferenceFile()) throw new Error('这是 macOS App UI 参考文件。请在独立网站文件中运行：' + DESIGN.fileUrl);
  const existing = figma.root.children.find(p => p.getPluginData(MARKER) === 'complete');
  if (existing) {
    await figma.setCurrentPageAsync(existing);
    const frames = existing.children.filter(n => n.getPluginData(MARKER) === 'frame');
    existing.selection = frames;
    figma.viewport.scrollAndZoomIntoView(frames.slice(0, 2));
    return { reused: true, frames: frames.length, pageId: existing.id };
  }
  // Validate fonts and decode assets before creating any page or layers.
  validatePortableSources();
  const fonts = await fontsForDesign();
  const images = {};
  for (const key of Object.keys(ASSETS)) images[key] = figma.createImage(figma.base64Decode(ASSETS[key].base64)).hash;
  const previous = figma.currentPage;
  const page = figma.createPage();
  page.name = DESIGN.pageName;
  page.setPluginData(MARKER, 'building');
  try {
    await figma.setCurrentPageAsync(page);
    page.backgrounds = [paint('#27282C')];
    const frames = [];
    const sourceCache = {};
    for (const spec of DESIGN.frames) {
      const ctx = { fonts, images, sourceCache, links: [], anchors: {} };
      const frame = renderNode(spec, page, ctx);
      frame.setPluginData(MARKER, 'frame');
      frame.setPluginData('unslop-credit', 'Damir Sokolovsky · CC BY 4.0 · https://github.com/heydamir/unslop');
      for (const { node, target } of ctx.links) {
        const action = target.startsWith('#')
          ? { type: 'NODE', destinationId: ctx.anchors[target.slice(1)].id, navigation: 'SCROLL_TO', transition: null }
          : { type: 'URL', url: target.startsWith('/') ? 'https://glancepreview.com' + (spec.lang === 'en' && target !== '/en/' && target !== '/' ? '/en' : '') + target : target, openInNewTab: true };
        await node.setReactionsAsync([{ trigger: { type: 'ON_CLICK' }, actions: [action] }]);
      }
      frames.push(frame);
    }
    page.selection = frames.slice(0, 2);
    figma.viewport.scrollAndZoomIntoView(frames.slice(0, 2));
    page.setPluginData(MARKER, 'complete');
    return { reused: false, frames: frames.length, pageId: page.id };
  } catch (error) {
    await figma.setCurrentPageAsync(previous);
    page.remove();
    throw error;
  }
}

figma.ui.onmessage = async message => {
  if (message.type === 'mode') {
    figma.ui.postMessage({ type: 'mode', editorType: figma.editorType, documentName: figma.root.name, isAppReference: isAppReferenceFile() }); return;
  }
  if (message.type !== 'generate' || busy) return;
  busy = true;
  try {
    const result = await generate();
    figma.ui.postMessage({ type: 'done', result, message: result.reused
      ? 'Showing the existing design. Your manual edits are preserved.'
      : '已在独立网站文件中创建 8 张首页和 2 张规范板。App 界面使用随插件打包的 SVG 参考组，无需源文件图层。' });
  } catch (error) {
    figma.ui.postMessage({ type: 'error', message: BUILD_LABEL + ' · ' + (error && error.message ? error.message : String(error)) });
  } finally { busy = false; }
};
