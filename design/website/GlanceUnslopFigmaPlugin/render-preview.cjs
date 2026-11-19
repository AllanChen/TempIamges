/* Static composition proofs. Does not open a browser, Glance, or Figma. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createDesign } = require('./design.cjs');
const { readPortableSources } = require('./build.cjs');

const esc = v => String(v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
function renderSVG(frame, assets, cropHeight = null) {
  const sources = createDesign().sources;
  let id = 0;
  function node(n) {
    const clipId = 'clip' + (++id);
    let body = '';
    if (n.type === 'TEXT') {
      const anchor = n.align === 'CENTER' ? 'middle' : n.align === 'RIGHT' ? 'end' : 'start';
      const x = n.align === 'CENTER' ? n.w / 2 : n.align === 'RIGHT' ? n.w : 0;
      const family = n.fontRole === 'display' ? 'Shippori Mincho, Noto Serif SC, Hiragino Mincho ProN, serif' : n.fontRole === 'mono' ? 'Geist Mono, PingFang SC, monospace' : 'Inter, PingFang SC, sans-serif';
      body = '<text font-family="' + family + '" font-size="' + n.size + '" font-weight="' + n.weight + '" fill="' + n.color + '" letter-spacing="' + (n.tracking || 0) + '" text-anchor="' + anchor + '">' + n.text.split('\n').map((line, i) => '<tspan x="' + x + '" y="' + (n.size + i * n.lineHeight) + '">' + esc(line) + '</tspan>').join('') + '</text>';
    } else if (n.type === 'ICON') {
      const paths = n.icon === 'menu' ? '<path d="M2 5h12M2 11h12"/>' : '<rect x="2" y="3" width="12" height="10" rx="2"/><path d="M8 3v10"/>';
      body = '<g fill="none" stroke="' + n.color + '" stroke-width="1.5" stroke-linecap="round">' + paths + '</g>';
    } else {
      body = '<defs><clipPath id="' + clipId + '"><rect width="' + n.w + '" height="' + n.h + '" rx="' + n.radius + '"/></clipPath></defs>';
      body += '<rect width="' + n.w + '" height="' + n.h + '" rx="' + n.radius + '" fill="' + (n.fill || 'none') + '" stroke="' + (n.stroke || 'none') + '"/>';
      let content = '';
      if (n.sourceRef) {
        const key = ['focus', 'compare'].includes(n.sourceRef) ? n.theme + '/' + n.sourceRef : n.sourceRef;
        const a = assets[key], src = a.bounds || sources[key];
        const scale = ['focus', 'compare'].includes(n.sourceRef)
          ? Math.min(n.w / src.w, n.h / src.h)
          : Math.max(n.w / src.w, n.h / src.h);
        const [left, top, fullW, fullH] = src.padding || [0, 0, src.w, src.h];
        const ix = (n.w - src.w * scale) / 2 - left * scale, iy = (n.h - src.h * scale) / 2 - top * scale;
        content += '<image x="' + ix + '" y="' + iy + '" width="' + fullW * scale + '" height="' + fullH * scale + '" preserveAspectRatio="xMidYMid meet" href="data:' + a.mime + ';base64,' + a.base64 + '"/>';
      }
      for (const child of n.children || []) {
        if (n.layout) {
          content += node({ ...child, x: (n.w - child.w) / 2, y: (n.h - child.h) / 2 });
        } else content += node(child);
      }
      body += '<g clip-path="url(#' + clipId + ')">' + content + '</g>';
    }
    return '<g transform="translate(' + (n.x || 0) + ' ' + (n.y || 0) + ')">' + body + '</g>';
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="' + frame.w + '" height="' + (cropHeight || frame.h) + '" viewBox="0 0 ' + frame.w + ' ' + (cropHeight || frame.h) + '">' + node({ ...frame, x: 0, y: 0 }) + '</svg>';
}

async function main() {
  const config = path.join(os.tmpdir(), 'glance-shizuka-fonts.conf');
  fs.writeFileSync(config, '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>' + esc(path.join(__dirname, 'reference/fonts')) + '</dir><dir>/System/Library/Fonts</dir><dir>/Library/Fonts</dir><cachedir>' + esc(path.join(os.tmpdir(), 'glance-shizuka-font-cache')) + '</cachedir></fontconfig>');
  process.env.FONTCONFIG_FILE = config;
  const sharp = require('sharp');
  const design = createDesign(), portable = readPortableSources(), assets = {};
  for (const [key, view] of Object.entries(portable.views)) {
    const svg = view.svg.replace(/__GLANCE_IMAGE_(\d+)__/g, (_, index) => portable.images[view.images[Number(index)]]);
    assets[key] = { base64: Buffer.from(svg).toString('base64'), mime: 'image/svg+xml', bounds: { w: view.w, h: view.h } };
  }
  const dir = path.join(__dirname, 'preview');
  fs.mkdirSync(dir, { recursive: true });
  for (const [i, name] of [[0, 'desktop-en'], [1, 'mobile-en'], [2, 'desktop-zh'], [3, 'mobile-zh'], [4, 'design-notes'], [5, 'washi-desktop-en'], [6, 'washi-mobile-en'], [7, 'washi-desktop-zh'], [8, 'washi-mobile-zh'], [9, 'washi-design-notes']]) {
    const svg = Buffer.from(renderSVG(design.frames[i], assets));
    await sharp(svg, { limitInputPixels: false }).resize({ width: design.frames[i].w === 390 ? 390 : 960 }).png().toFile(path.join(dir, name + '.png'));
  }
  await sharp(Buffer.from(renderSVG(design.frames[0], assets, 1120))).png().toFile(path.join(dir, 'desktop-hero.png'));
  await sharp(Buffer.from(renderSVG(design.frames[5], assets, 1120))).png().toFile(path.join(dir, 'washi-desktop-hero.png'));
  console.log('Rendered eight static page proofs, two design notes, and two desktop heroes');
}
if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
module.exports = { renderSVG };
