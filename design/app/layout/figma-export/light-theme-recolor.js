// Glance dark → light recolor pass (run through Figma MCP use_figma).
// Replace __ROOT_IDS__ with the node IDs to recolor. Layout is never touched:
// only fills, strokes, text fills and effect colors change.
const ROOT_IDS = __ROOT_IDS__;
await figma.setCurrentPageAsync(await figma.getNodeByIdAsync('353:2'));

const H = h => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255 });
const L = {
  bg: H('#F4F1ED'), sidebar: H('#EEEAE5'), surface: H('#FFFFFF'), raised: H('#F1EDE8'), well: H('#E6E0D9'),
  ink: H('#1F1B17'), icon: H('#3A342F'), secondary: H('#6B635C'), muted: H('#8A8179'),
  accentText: H('#A8572A'), success: H('#2E7D57'), danger: H('#C2413A'), info: H('#3567AE')
};
const lum = c => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
const chroma = c => Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b);
const near = (c, h, t = 0.03) => { const d = H(h); return Math.abs(c.r - d.r) < t && Math.abs(c.g - d.g) < t && Math.abs(c.b - d.b) < t; };
const isAccent = c => near(c, '#E8A87C', 0.05) || near(c, '#F0B58E', 0.04);
const isSuccess = c => near(c, '#8FD0AF', 0.05);
const isDanger = c => near(c, '#F18B86', 0.05);
const isInfo = c => near(c, '#A9C5EF', 0.05);

function hue(c) {
  const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b), d = max - min;
  if (!d) return 0;
  let h = max === c.r ? ((c.g - c.b) / d) % 6 : max === c.g ? (c.b - c.r) / d + 2 : (c.r - c.g) / d + 4;
  return (h * 60 + 360) % 360;
}
function hsl(h, s, l) {
  const k = n => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return { r: f(0), g: f(8), b: f(4) };
}
const pastel = c => hsl(hue(c), 0.5, 0.93);

// Text and icon ink.
function inkColor(c) {
  if (isAccent(c)) return L.accentText;
  if (isSuccess(c)) return L.success;
  if (isDanger(c)) return L.danger;
  if (isInfo(c)) return L.info;
  const l = lum(c), ch = chroma(c);
  if (ch < 0.08) {
    if (l > 0.78) return L.ink;
    if (l > 0.5) return L.secondary;
    if (l > 0.28) return L.muted;
    return c; // dark ink (e.g. #21130D on apricot) stays
  }
  if (l > 0.55) return { r: c.r * 0.55, g: c.g * 0.55, b: c.b * 0.55 };
  return c;
}

// Shape fill. Returns [color, opacityMultiplier].
function surfaceColor(c, alpha, onMedia) {
  if (isAccent(c) || isSuccess(c) || isDanger(c) || isInfo(c)) return [c, 1];
  const l = lum(c), ch = chroma(c);
  if (l < 0.03 && alpha < 0.95) return onMedia ? [c, 1] : [L.ink, 0.5];      // scrim
  if (ch >= 0.04 && l < 0.25) return [pastel(c), 1];                            // tinted dark → pastel
  if (ch < 0.06 && l < 0.3) {                                                   // neutral dark ramp
    if (alpha < 0.95 && alpha >= 0.5) return [L.surface, 1];                    // dark glass → white glass
    if (l <= 0.05) return [L.bg, 1];
    if (l <= 0.062) return [L.sidebar, 1];
    if (l <= 0.13) return [L.surface, 1];
    if (l <= 0.19) return [L.raised, 1];
    return [L.well, 1];
  }
  if (ch < 0.06 && l > 0.85 && alpha < 0.35) return [L.ink, 0.7];              // white hairline / control fill
  if (ch < 0.06 && l >= 0.3 && l <= 0.85) return [H('#C9C2BA'), 1];           // mid grey
  return [c, 1];
}

function strokeColor(c, alpha, isIcon, onMedia) {
  if (isIcon && !onMedia) return [inkColor(c), 1];
  if (isAccent(c) || isSuccess(c) || isDanger(c) || isInfo(c)) return [c, 1];
  const l = lum(c), ch = chroma(c);
  if (ch < 0.06 && l > 0.85) return [L.ink, alpha < 0.35 ? 0.75 : 0.12 / Math.max(alpha, 0.01)];
  if (ch < 0.06 && l < 0.3 && l > 0.02) return [L.ink, 0.10 / Math.max(alpha, 0.01)];
  if (ch >= 0.04 && l < 0.25) return [pastel(c), 1];
  return [c, 1];
}

function mapStops(p, fn) {
  return Object.assign({}, p, { gradientStops: p.gradientStops.map(s => {
    const [col] = fn({ r: s.color.r, g: s.color.g, b: s.color.b }, s.color.a);
    return Object.assign({}, s, { color: { r: col.r, g: col.g, b: col.b, a: s.color.a } });
  }) });
}
const isUIGradient = p => p.type.startsWith('GRADIENT') && p.gradientStops.every(s => chroma(s.color) < 0.05 && lum(s.color) < 0.2);
const isMediaPaint = p => p.visible !== false && (p.type === 'IMAGE' || p.type === 'VIDEO' || (p.type.startsWith('GRADIENT') && !isUIGradient(p)));

function mapPaints(paints, nodeOpacity, mode, onMedia) {
  if (!Array.isArray(paints)) return null;
  let changed = false;
  const out = paints.map(p => {
    if (p.type === 'SOLID') {
      const a = (p.opacity ?? 1) * nodeOpacity;
      const [col, mul] = mode === 'ink' ? [onMedia ? p.color : inkColor(p.color), 1]
        : mode === 'stroke' ? strokeColor(p.color, a, false, onMedia)
        : mode === 'iconStroke' ? strokeColor(p.color, a, true, onMedia)
        : surfaceColor(p.color, a, onMedia);
      let op = Math.min(1, (p.opacity ?? 1) * mul);
      if (mode === 'fill' && a >= 0.5 && a < 0.95 && lum(p.color) < 0.3 && chroma(p.color) < 0.06) op = Math.max(op, 0.84);
      changed = true;
      return { type: 'SOLID', color: col, opacity: op, visible: p.visible !== false, blendMode: p.blendMode || 'NORMAL' };
    }
    if (isUIGradient(p)) { changed = true; return mapStops(p, c => surfaceColor(c, 1, false)); }
    return p;
  });
  return changed ? out : null;
}

function mapEffects(effects) {
  if (!effects || !effects.length) return null;
  return effects.map(e => {
    if ((e.type === 'DROP_SHADOW' || e.type === 'INNER_SHADOW') && chroma(e.color) < 0.08 && lum(e.color) < 0.2) {
      return Object.assign({}, e, { color: { r: 0.2, g: 0.13, b: 0.08, a: Math.min(e.color.a * 0.4, 0.16) } });
    }
    return e;
  });
}

const ICON_TYPES = new Set(['VECTOR', 'BOOLEAN_OPERATION', 'LINE', 'STAR', 'POLYGON']);
const fonts = new Map();
const texts = [];
let count = 0;

function visit(node, onMedia, parentArea, inIcon = false) {
  count++;
  const op = 'opacity' in node ? node.opacity : 1;
  const fills = 'fills' in node && Array.isArray(node.fills) ? node.fills : [];
  const ownMedia = fills.some(isMediaPaint);
  const ownSolid = fills.some(p => p.type === 'SOLID' && p.visible !== false && (p.opacity ?? 1) * op >= 0.5);
  if (node.type === 'TEXT') { texts.push([node, onMedia]); return false; }
  const iconFrame = node.name.startsWith('Icon');
  const icon = ICON_TYPES.has(node.type) || (inIcon && node.type !== 'FRAME');
  if (fills.length) {
    const f = mapPaints(fills, op, icon ? 'ink' : 'fill', onMedia && (icon || true));
    if (f) node.fills = f;
  }
  if ('strokes' in node && node.strokes.length) {
    const s = mapPaints(node.strokes, op, icon ? 'iconStroke' : 'stroke', onMedia);
    if (s) node.strokes = s;
  }
  if ('effects' in node) { const e = mapEffects(node.effects); if (e) node.effects = e; }
  let childMedia = ownMedia ? true : ownSolid ? false : onMedia;
  if ('children' in node) {
    const area = node.width * node.height;
    let behind = childMedia;
    for (const child of node.children) {
      const coversMedia = visit(child, behind, area, inIcon || iconFrame);
      if (coversMedia) behind = true;
    }
  }
  // Report whether this node is a large media backdrop for later siblings.
  return ownMedia && parentArea > 0 && node.width * node.height >= parentArea * 0.4;
}

for (const id of ROOT_IDS) {
  const root = await figma.getNodeByIdAsync(id);
  if (root) visit(root, false, 0);
}

// Text: load every font in use, then remap each fill segment.
for (const [t] of texts) {
  if (t.characters.length === 0) continue;
  for (const seg of t.getStyledTextSegments(['fontName'])) fonts.set(seg.fontName.family + '|' + seg.fontName.style, seg.fontName);
}
await Promise.all([...fonts.values()].map(f => figma.loadFontAsync(f).catch(() => null)));
let textCount = 0;
for (const [t, onMedia] of texts) {
  if (onMedia || t.characters.length === 0) continue;
  const op = t.opacity;
  for (const seg of t.getStyledTextSegments(['fills'])) {
    const f = mapPaints(seg.fills, op, 'ink', false);
    if (f) { try { t.setRangeFills(seg.start, seg.end, f); textCount++; } catch (e) {} }
  }
}
return { nodes: count, texts: texts.length, textSegmentsChanged: textCount, fonts: fonts.size };
