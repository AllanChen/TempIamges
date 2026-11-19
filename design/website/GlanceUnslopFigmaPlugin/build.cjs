'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { createDesign, ASSET_PATHS } = require('./design.cjs');

function normalizeSvgUnicode(svg) {
  // Some SVG_STRING exports encode UTF-8 bytes as consecutive numeric entities.
  return svg.replace(/(?:&#(?:x[0-9a-fA-F]+|\d+);){2,}/g, run => {
    const values = [...run.matchAll(/&#(x[0-9a-fA-F]+|\d+);/g)].map(m => m[1][0] === 'x' ? parseInt(m[1].slice(1), 16) : Number(m[1]));
    if (values.some(v => v > 255)) return run;
    const decoded = Buffer.from(values).toString('utf8');
    return decoded.includes('\uFFFD') ? run : decoded;
  });
}

function readPortableSources() {
  const dir = path.join(__dirname, 'portable');
  const app = JSON.parse(fs.readFileSync(path.join(dir, 'app-views.json'), 'utf8'));
  const photos = JSON.parse(fs.readFileSync(path.join(dir, 'photo-views.json'), 'utf8'));
  const portraitFile = path.join(dir, 'website-portrait-views.json');
  const portrait = fs.existsSync(portraitFile) ? JSON.parse(fs.readFileSync(portraitFile, 'utf8')) : { views: {} };
  const images = {};
  for (const file of fs.readdirSync(path.join(dir, 'photos')).filter(f => /\.(jpg|png)$/.test(f))) {
    const bytes = fs.readFileSync(path.join(dir, 'photos', file));
    if (!bytes.length) throw new Error('Empty photo asset: ' + file);
    const mime = bytes[0] === 0xFF && bytes[1] === 0xD8 ? 'image/jpeg' : 'image/png';
    images[path.parse(file).name] = 'data:' + mime + ';base64,' + bytes.toString('base64');
  }
  const views = {};
  for (const [key, view] of Object.entries({ ...app.views, ...photos.views, ...portrait.views })) {
    const refs = view.images.map(fingerprint => {
      const found = Object.entries(images).find(([, data]) => data.length === fingerprint.length && data.startsWith(fingerprint.prefix) && data.endsWith(fingerprint.suffix));
      if (!found) throw new Error('Missing exact source image for ' + key);
      return found[0];
    });
    views[key] = { svg: normalizeSvgUnicode(view.svg), images: refs, w: view.w, h: view.h };
  }
  const used = new Set(Object.values(views).flatMap(view => view.images));
  return { sourceFileKey: app.sourceFileKey, views, images: Object.fromEntries(Object.entries(images).filter(([name]) => used.has(name))) };
}

function readAssets() {
  return Object.fromEntries(Object.entries(ASSET_PATHS).map(([key, relative]) => {
    const file = path.resolve(__dirname, relative);
    return [key, { base64: fs.readFileSync(file).toString('base64'), mime: file.endsWith('.png') ? 'image/png' : 'image/jpeg' }];
  }));
}

if (require.main === module) {
  const design = createDesign();
  const assets = readAssets();
  const portable = readPortableSources();
  const template = fs.readFileSync(path.join(__dirname, 'plugin.template.js'), 'utf8');
  const bundle = template.replace('// __DESIGN_AND_ASSETS__',
    'const DESIGN = ' + JSON.stringify(design) + ';\nconst ASSETS = ' + JSON.stringify(assets) + ';\nconst PORTABLE = ' + JSON.stringify(portable) + ';');
  fs.writeFileSync(path.join(__dirname, 'code.js'), bundle);
  console.log('Bundled ' + design.frames.length + ' boards, ' + Object.keys(portable.views).length + ' portable SVG references, and ' + Object.keys(portable.images).length + ' exact photos');
}

module.exports = { readAssets, readPortableSources, normalizeSvgUnicode };
