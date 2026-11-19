/* Glance website concept. Unslop method by Damir Sokolovsky, CC BY 4.0.
 * https://github.com/heydamir/unslop
 * This file defines native, editable Figma layers. Photos remain image fills.
 */
'use strict';

const THEMES = {
  sumi: { bg: '#151514', surface: '#1B1B1A', raised: '#242422', line: '#34342F',
    ink: '#EAE7E0', secondary: '#A19D94', muted: '#A19D94', dim: '#6B6862',
    accent: '#C65A40', accentInk: '#0F0F0E', focus: '#EAE7E0', canvas: '#0F0F0E' },
  washi: { bg: '#FAF9F5', surface: '#F3F1EB', raised: '#EAE7DF', line: '#D5D1C6',
    ink: '#1C1B19', secondary: '#5C5952', muted: '#5C5952', dim: '#8D897F',
    accent: '#B5462E', accentInk: '#FAF9F5', focus: '#1C1B19', canvas: '#EFEDE6' }
};
const C = THEMES.sumi;
const SOURCE = 'https://github.com/heydamir/unslop';
const REFERENCE_FILE_URL = 'https://www.figma.com/design/3oIkv5jBJpRUORxliJZdHl/Untitled';
const FILE_URL = 'https://www.figma.com/design/kWvE51F9IfI3oSN6ZoxeKw';
const ASSET_PATHS = {};
const FIGMA_SOURCES = {
  'sumi/focus': { id: '13:130', fileKey: 'kWvE51F9IfI3oSN6ZoxeKw', name: 'Website / Portrait Focus', w: 1440, h: 900 },
  'sumi/compare': { id: '13:131', fileKey: 'kWvE51F9IfI3oSN6ZoxeKw', name: 'Website / Portrait Compare', w: 1440, h: 900 },
  'washi/focus': { id: '13:132', fileKey: 'kWvE51F9IfI3oSN6ZoxeKw', name: 'Website / Portrait Focus', w: 1440, h: 900 },
  'washi/compare': { id: '13:133', fileKey: 'kWvE51F9IfI3oSN6ZoxeKw', name: 'Website / Portrait Compare', w: 1440, h: 900 },
  // Internal asset keys stay stable; the photo contents are now all portraits.
  landscape: { name: 'photo/portrait-original', sourcePath: 'portable/photos/portrait-original.png', w: 941, h: 1672 },
  warm: { name: 'photo/portrait-handbag-removed', sourcePath: 'portable/photos/portrait-handbag-removed.png', w: 941, h: 1672 },
  sakura: { name: 'photo/portrait-selfie', sourcePath: 'portable/photos/paris-selfie.jpg', w: 1216, h: 1600 }
};

function estimate(str, size) {
  let units = 0;
  for (const ch of str) {
    units += /[\u2E80-\uFFFF]/u.test(ch) ? 1 : /[ilI.,' :;!|]/.test(ch) ? .29 : /[MW@%]/.test(ch) ? .88 : /[A-Z]/.test(ch) ? .69 : .54;
  }
  return units * size;
}
function wrap(value, width, size) {
  return value.split('\n').flatMap(paragraph => {
    const chunks = paragraph.match(/[\u2E80-\uFFFF]|[^\u2E80-\uFFFF\s]+\s*|\s+/gu) || [''];
    const lines = [];
    let line = '';
    for (const chunk of chunks) {
      if (line && estimate(line + chunk, size) > width - 8 && !/^[，。、：；！？）】」』]/u.test(chunk)) {
        lines.push(line.trim()); line = chunk.trimStart();
      } else line += chunk;
    }
    if (line || !lines.length) lines.push(line.trim());
    return lines;
  });
}
function box(parent, name, x, y, w, h, fill = null, radius = 0, stroke = null) {
  const n = { type: 'FRAME', name, x, y, w, h, fill, radius, stroke, children: [] };
  if (parent) parent.children.push(n);
  return n;
}
function txt(parent, name, value, x, y, w, size = 16, color = C.ink, weight = 400, leading = null) {
  const lines = wrap(value, w, size);
  const lineHeight = leading || (size >= 40 ? Math.ceil(size * 1.08 / 4) * 4 : Math.ceil(size * 1.45 / 4) * 4);
  const n = { type: 'TEXT', name, x, y, w, h: lines.length * lineHeight + 4,
    text: lines.join('\n'), size, color, weight, lineHeight, tracking: 0,
    fontRole: size >= 28 ? 'display' : 'body' };
  parent.children.push(n);
  return n;
}
function rule(parent, name, x, y, w, color = C.line, h = 1) {
  return box(parent, name, x, y, w, h, color);
}
function photo(parent, name, asset, x, y, w, h, radius = 12) {
  const n = box(parent, name, x, y, w, h, null, radius);
  n.sourceRef = asset === 'natural' ? 'landscape' : asset;
  return n;
}
function icon(parent, name, x, y, color = C.secondary) {
  const n = { type: 'ICON', name, icon: name, x, y, w: 16, h: 16, color };
  parent.children.push(n); return n;
}
function button(parent, label, x, y, w, kind = 'primary', h = 48, target = null) {
  const n = box(parent, 'Button / ' + label, x, y, w, h,
    kind === 'primary' || kind === 'accent' ? C.ink : C.surface,
    6, kind === 'secondary' ? C.line : null);
  n.target = target;
  n.layout = { direction: 'HORIZONTAL', padding: 16, gap: 8, align: 'CENTER' };
  const t = txt(n, 'Label', label, 0, 0, w - 32, 14,
    kind === 'secondary' ? C.ink : C.accentInk, 500, 20);
  t.h = 20; t.align = 'CENTER';
  return n;
}
function link(parent, label, x, y, w, target) {
  const n = txt(parent, 'Link / ' + label, label, x, y, w, 14, C.secondary, 500, 20);
  n.target = target;
  return n;
}
function label(parent, value, x, y, w) {
  const n = txt(parent, 'Section label', value, x, y, w, 12, C.muted, 400, 20);
  n.fontRole = 'mono';
  return n;
}

const copy = {
  en: {
    tag: 'Glance · Image & video viewer for Mac', title: 'A quiet place\nfor your images',
    intro: 'Inspect an image. Make a change with AI. Compare it with the original, all in one Mac app.',
    download: 'Download for Mac', compareLink: 'See image comparison',
    heroCaption: 'Original on the left. Handbag removed on the right',
    focusCaption: 'Original on the left. Handbag removed on the right',
    facts: ['No account to start', '14-day full trial, no card', 'Viewing, compare, capture and OCR stay free'],
    loopLabel: 'One window, start to finish', loopTitle: 'Look at the details\nKeep the whole picture',
    loopIntro: 'From opening a file to checking the result, the next step stays close to the image.',
    loop: [
      ['View', 'A place for every\nimage and video', 'Zoom into the details, browse a folder, or grab a frame from a video. Open straight from Finder or make Glance your default viewer.', 'PNG · JPEG · HEIC · WebP · AVIF · GIF · SVG · TIFF\nMP4 · MOV · M4V · WebM · MKV · AVI'],
      ['Fix in place', 'The next tool is\na right-click away', 'Upscale, extend the canvas, remove a background, and more. Pick a cloud Widget from the menu and keep browsing while it works.', 'Cloud Widgets require sign-in and upload the media you submit. Cost is shown before each run. Results save to Downloads/Glance.'],
      ['Compare', 'See what changed\nbefore you use it', 'Put the original beside the result, or move a slider between them. Check the details with both versions in view.', 'All failed tasks refund credits in full automatically.']
    ],
    moreLabel: 'And more', moreTitle: 'The small jobs, handled',
    ocrTitle: 'Copy the text. Keep your image',
    ocrBody: 'Recognize text on your Mac, select what you need, and copy it. No Pro, credits, or upload needed.',
    free: 'Free forever', ocrSteps: ['Open an image', 'Select its text', 'Copy with'],
    features: [
      ['Video preview & capture', 'Play a video, capture any frame, crop it, then save or copy it.'],
      ['Cloud AI Widgets', 'New accounts get 100 credits. Only cloud runs use credits.'],
      ['Local toolbox', 'Convert, compress, export, rotate, crop, and use Base64 tools on your Mac.'],
      ['Peek, when you want it', 'Select an image link or file path and press Option + Space. Optional, off by default.'],
      ['Task Center', 'Follow queued, running, and finished tasks. Cancel a queued task and get its credits back.'],
      ['Start without permissions', 'Open Glance and view a file. No account or system permissions needed to start.']
    ],
    widgetLabel: 'AI Widgets', widgetTitle: 'Choose a tool\nStay with your image',
    widgetIntro: 'Cloud tools live in the context menu. Check the cost before you run one.',
    widgets: ['Edit Area', 'Upscale', 'Background Remover Pro', 'Remove Objects', 'Video Watermark Remover', 'Free Image Host'],
    widgetNote: 'Cloud processing uploads your selected media. Failed tasks refund credits in full. Check the current cost in the app before running a Widget.',
    allWidgets: 'All Widgets and model details',
    pricingLabel: 'Pricing', pricingTitle: 'Free to view\nPro once. AI as you go',
    pricingIntro: 'No subscription. No automatic renewals.',
    plans: [
      ['Free', '$0', 'Forever', 'View images and video, compare, capture frames, and copy text from images.', 'Download free'],
      ['Glance Pro', '$9.99', 'One-time · Personal · 1 Mac', 'The full local toolbox, lifetime updates, and 100 bonus credits. Team: $19.99 for 5 independent accounts.', 'See Pro plans'],
      ['Credits', '$2.99', '600 credits · pay as you go', 'Only cloud Widgets use credits. Credits never expire. Available on Free and Pro.', 'See credit packs']
    ],
    pricingNote: 'USD prices include tax · Cloud Widgets use separate credits · 14-day full trial starts on first launch',
    downloadLabel: 'Download', downloadTitle: 'Your next image\nhas a home',
    downloadBody: 'Start with the free viewer. Try the full local toolbox for 14 days, with no account or payment method.',
    version: 'Glance 1.0.4 · macOS 12.3+ · Apple silicon', install: 'Install guide',
    faqLabel: 'FAQ', faqTitle: 'A few things to know',
    faqs: [
      ['Do I need an account?', 'No account is needed for viewing, compare, capture, or OCR. Sign in for cloud Widgets or purchases.'],
      ['Are my files uploaded?', 'Viewing and local tools run on your Mac. Only the media you submit to a cloud Widget is uploaded.'],
      ['Is Pro a subscription?', 'No. Pro is a one-time purchase with lifetime free updates and no automatic renewals.'],
      ['What if a task fails?', 'All failed Widget tasks refund credits in full automatically, including provider, network, and invalid-input failures.'],
      ['What stays free after the trial?', 'Viewing, compare, capture, OCR, and credit-based cloud Widgets. The remaining local tools require Pro.'],
      ['How do I pay?', 'Choose a product in the app. The checkout shows available payment methods for your currency.']
    ],
    footer: 'An image and video viewer for Mac', privacy: 'Privacy', terms: 'Terms', refunds: 'Refunds', support: 'Support'
  },
  zh: {
    tag: 'Glance · Mac 图片与视频查看器', title: '让图片说话\n让下一步更近',
    intro: '打开图片，看清细节。右键用 AI 修改，再和原图对比。看、改、比，一个窗口。',
    download: '下载 Mac 版', compareLink: '看看图片对比', heroCaption: '左边是原图，右边是移除手包后的结果', focusCaption: '左边是原图，右边是移除手包后的结果',
    facts: ['无需账户，即刻开始', '14 天完整试用，无需绑卡', '看图、对比、截图和文字识别永久免费'],
    loopLabel: '一个窗口，从开始到完成', loopTitle: '看得仔细\n也看得完整', loopIntro: '从打开文件到确认结果，下一步始终就在图片旁边。',
    loop: [
      ['查看', '每张图片，每段视频\n都有合适的位置', '放大细节、浏览文件夹、截取视频帧。从 Finder 直接打开，也可以把 Glance 设为默认查看器。', 'PNG · JPEG · HEIC · WebP · AVIF · GIF · SVG · TIFF\nMP4 · MOV · M4V · WebM · MKV · AVI'],
      ['就地修改', '下一个工具\n就在右键菜单里', '高清放大、智能扩图、人物背景分离，以及更多工具。从右键菜单选择云端 Widget，任务在后台运行，你可以继续浏览。', '云端 Widget 需要登录，并上传你提交的媒体。运行前显示点数，结果保存到「下载/Glance」。'],
      ['对比', '先看清变化\n再决定使用', '原图与结果并排放，或拖动滑杆切换。两份图片始终在眼前，逐处确认修改效果。', '所有失败任务都会自动全额退点。']
    ],
    moreLabel: '还有这些', moreTitle: '顺手解决那些小事', ocrTitle: '复制文字，保留图片',
    ocrBody: '在 Mac 上识别图片文字，选中需要的部分，直接复制。无需 Pro、不扣点，也不用上传。', free: '永久免费', ocrSteps: ['打开图片', '选中文字', '复制文字'],
    features: [
      ['视频预览与截图', '播放视频，截取任意一帧，裁剪后保存或复制。'],
      ['云端 AI Widget', '新账户赠送 100 点。只有云端运行使用点数。'],
      ['本地工具箱', '转换、压缩、导出、旋转、裁剪和 Base64 工具，都在 Mac 上运行。'],
      ['需要时，再用 Peek', '选中图片链接或文件路径，按 Option + Space 预览。可选功能，默认关闭。'],
      ['任务中心', '跟踪排队、运行和已完成任务。取消排队任务会退还点数。'],
      ['无需权限，即刻开始', '打开 Glance 就能看图。首次使用无需账户，也无需系统权限。']
    ],
    widgetLabel: 'AI Widget', widgetTitle: '选好工具\n继续看图', widgetIntro: '云端工具就在右键菜单里。每次运行前，先看清点数。',
    widgets: ['局部编辑', '高清放大', '人物背景分离', '移除物体', '视频去水印', '免费图床'],
    widgetNote: '云端处理会上传你选中的媒体，失败任务全额退点。运行前，请在应用内确认当前点数。', allWidgets: '全部 Widget 与模型说明',
    pricingLabel: '价格', pricingTitle: '免费看，Pro 买断\nAI 用多少付多少', pricingIntro: '没有订阅，没有自动续费。',
    plans: [
      ['免费版', '¥0', '永久免费', '看图、看视频、图片对比、视频截图，以及图片文字识别和复制。', '免费下载'],
      ['Glance Pro', '¥29.90', '一次买断 · 个人版 · 1 台 Mac', '完整本地工具箱、终身免费更新，附赠 100 点。多人版 ¥79.90，包含 5 个独立账号。', '查看 Pro 方案'],
      ['点数', '¥12', '600 点 · 按需充值', '只用于云端 Widget，长期有效。免费版和 Pro 都可以使用。', '查看点数包']
    ],
    pricingNote: '人民币含税价格 · 云端 Widget 另按点数计费 · 首次启动开始 14 天完整试用',
    downloadLabel: '下载', downloadTitle: '下一张图片\n在这里打开', downloadBody: '从免费查看器开始。完整本地工具箱试用 14 天，无需账户，无需绑定支付方式。',
    version: 'Glance 1.0.4 · macOS 12.3+ · Apple 芯片', install: '安装指南', faqLabel: '常见问题', faqTitle: '开始前，你可能想知道',
    faqs: [
      ['需要注册账户吗？', '看图、对比、截图和文字识别无需账户。使用云端 Widget 或购买时才需要登录。'],
      ['文件会被上传吗？', '查看和本地工具都在 Mac 上运行。只有提交给云端 Widget 的媒体会被上传。'],
      ['Pro 是订阅吗？', '不是。Pro 一次买断，终身免费更新，没有自动续费。'],
      ['任务失败会扣点吗？', '所有失败的 Widget 任务都会自动全额退点，包括外部服务、网络和无效输入导致的失败。'],
      ['试用结束后还能用什么？', '看图、对比、截图、文字识别，以及按点数使用云端 Widget。其他本地工具需要 Pro。'],
      ['如何付款？', '在应用内选择商品，收银台会展示当前币种可用的付款方式。']
    ], footer: 'Mac 图片与视频查看器', privacy: '隐私', terms: '条款', refunds: '退款', support: '支持'
  }
};

function mobilePreview(parent, x, y, w, lang) {
  const p = box(parent, 'Product / Mobile compare detail', x, y, w, 384, C.canvas, 12, C.line);
  txt(p, 'Filename', 'portrait-compare.png', 64, 4, w - 128, 11, C.secondary, 400, 20).align = 'CENTER';
  const image = box(p, 'Comparison image', 0, 28, w, 316);
  photo(image, 'Portrait / Original', 'natural', 0, 0, (w - 8) / 2, 316, 0);
  photo(image, 'Portrait / Handbag removed', 'warm', (w + 8) / 2, 0, (w - 8) / 2, 316, 0);
  txt(p, 'Original label', lang === 'zh' ? '原图' : 'Original', 16, 352, 100, 12, C.secondary, 400, 20);
  txt(p, 'Result label', lang === 'zh' ? '移除手包' : 'Bag removed', w - 116, 352, 100, 12, C.secondary, 400, 20).align = 'RIGHT';
  return p;
}

function widgetMoment(parent, x, y, w, h, lang) {
  const mobile = w < 500;
  const f = box(parent, 'Widget menu / Latest design language', x, y, w, h, C.canvas, 12, C.line);
  const artW = mobile ? w : 432;
  photo(f, 'Native sample / sakura', 'sakura', mobile ? 0 : 32, mobile ? 24 : 88, artW, artW * .75, 3);
  const mw = mobile ? 236 : 288, mx = w - mw - 24, my = mobile ? 48 : 112;
  const menu = box(f, 'Widget menu', mx, my, mw, mobile ? 232 : 272, C.surface, 6, C.line);
  label(menu, 'AI Widgets', 16, 16, mw - 32);
  const names = lang === 'zh' ? ['移除物体', '高清放大'] : ['Remove Objects', 'Upscale'];
  const costs = lang === 'zh' ? ['30 点', '30 点'] : ['30 credits', '30 credits'];
  names.forEach((name, i) => {
    const ry = 52 + i * 64;
    rule(menu, 'Widget item line / ' + i, 16, ry, mw - 32);
    txt(menu, 'Widget menu title / ' + i, name, 16, ry + 16, mw - 144, 14, C.ink, 500, 20);
    const cost = txt(menu, 'Widget menu cost / ' + i, costs[i], mw - 108, ry + 20, 92, 11, C.secondary, 400, 16);
    cost.align = 'RIGHT'; cost.fontRole = 'mono';
  });
  txt(menu, 'Widget menu action', lang === 'zh' ? '查看全部工具 →' : 'All Widgets →', 16, 196, mw - 32, 12, C.secondary, 400, 20);
  if (!mobile) txt(f, 'Widget moment caption', lang === 'zh' ? '图片留在眼前，工具就在旁边' : 'The image stays in view. The tools stay close.', 32, h - 48, w - 64, 12, C.secondary, 400, 20);
  return f;
}

function homepage(lang, mobile) {
  const t = copy[lang], w = mobile ? 390 : 1440, p = mobile ? 24 : 96, cw = w - p * 2;
  const root = box(null, 'Home / ' + (lang === 'zh' ? '中文' : 'English') + ' / ' + (mobile ? 'Mobile 390' : 'Desktop 1440'), 0, 0, w, 1, C.bg);
  const section = (name, y, h, fill = null) => box(root, name, 0, y, w, h, fill);
  const nav = section('01 / Navigation', 0, 72);
  txt(nav, 'Glance wordmark', 'Glance', p, 16, 120, 28, C.ink, 400, 36);
  box(nav, 'Shu / Quiet brand mark', p + 116, 36, 4, 4, C.accent, 2);
  if (mobile) {
    link(nav, lang === 'zh' ? 'EN' : '中文', 264, 28, 44, lang === 'zh' ? '/en/' : '/');
    icon(nav, 'menu', 342, 28);
  } else {
    [['Features', '功能', '#loop'], ['AI Widgets', 'AI Widget', '#widgets'], ['Pricing', '价格', '#pricing'], ['Install', '安装', '/install/']].forEach((v, i) => link(nav, v[lang === 'zh' ? 1 : 0], 744 + i * 112, 28, 104, v[2]));
    link(nav, lang === 'zh' ? 'EN' : '中文', 1208, 28, 44, lang === 'zh' ? '/en/' : '/');
    button(nav, lang === 'zh' ? '下载' : 'Download', 1252, 20, 92, 'secondary', 32, '#download');
  }
  rule(nav, 'Navigation hairline', p, 71, cw);

  const heroH = mobile ? 992 : 720;
  const hero = section('02 / Hero', 72, heroH);
  label(hero, t.tag, p, mobile ? 40 : 88, mobile ? cw : 488);
  txt(hero, 'Hero headline', t.title, p, mobile ? 80 : 128, mobile ? cw : 472, mobile ? 40 : 60, C.ink, 400, mobile ? 48 : 76);
  txt(hero, 'Hero description', t.intro, p, mobile ? 204 : 316, mobile ? cw : 448, mobile ? 17 : 18, C.secondary, 400, 28);
  const actionY = mobile ? 348 : 448;
  button(hero, t.download, p, actionY, mobile ? cw : 192, 'primary', 48, '#download');
  link(hero, t.compareLink + ' →', mobile ? p : p + 216, mobile ? 416 : 464, mobile ? cw : 248, '#compare');
  if (mobile) mobilePreview(hero, p, 472, cw, lang);
  else photo(hero, 'Product / Native latest Image Inspect', 'compare', 608, 128, 736, 460, 12);
  txt(hero, 'Product caption', mobile ? t.heroCaption : t.focusCaption, mobile ? p : 608, mobile ? 872 : 608, mobile ? cw : 736, 12, C.muted, 400, 20);
  if (mobile) {
    txt(hero, 'Free start facts', t.facts.join('\n'), p, 916, cw, 12, C.secondary, 400, 20);
  } else {
    rule(hero, 'Hero facts divider', p, 660, cw);
    t.facts.forEach((s, i) => txt(hero, 'Free start fact ' + (i + 1), s, p + [0, 336, 696][i], 684, [312, 336, 552][i], 13, C.secondary, 400, 20));
  }
  let y = 72 + heroH;

  const loopHeadH = mobile ? 300 : 280;
  const loop = section('03 / Workflow introduction', y, loopHeadH);
  loop.anchor = 'loop';
  label(loop, t.loopLabel, p, mobile ? 48 : 88, cw);
  txt(loop, 'Workflow headline', t.loopTitle, p, mobile ? 88 : 128, mobile ? cw : 720, mobile ? 32 : 48, C.ink, 400, mobile ? 36 : 52);
  txt(loop, 'Workflow introduction', t.loopIntro, mobile ? p : 944, mobile ? 216 : 148, mobile ? cw : 400, 16, C.secondary, 400, 24);
  y += loopHeadH;
  const assets = ['focus', null, 'compare'];
  for (let i = 0; i < 3; i++) {
    const rowH = mobile ? 760 : 576, s = section('04.' + (i + 1) + ' / ' + t.loop[i][0], y, rowH);
    if (i === 2) s.anchor = 'compare';
    rule(s, 'Step hairline', p, 0, cw);
    const tx = mobile || i !== 1 ? p : 912, tw = mobile ? cw : 432;
    label(s, String(i + 1).padStart(2, '0') + ' / ' + t.loop[i][0], tx, mobile ? 32 : 104, tw);
    txt(s, 'Step headline', t.loop[i][1], tx, mobile ? 72 : 144, tw, mobile ? 32 : 36, C.ink, 400, 40);
    const body = txt(s, 'Step description', t.loop[i][2], tx, mobile ? 172 : 252, tw, 16, C.secondary, 400, 24);
    const metaY = Math.max(mobile ? 292 : 368, body.y + body.h + 24);
    txt(s, 'Step note', t.loop[i][3], tx, metaY, tw, 12, C.muted, 400, 20);
    if (mobile) {
      if (i === 2) mobilePreview(s, p, 368, cw, lang);
      else {
        if (i === 0) photo(s, 'Native sample / landscape', 'natural', p, 392, cw, 316, 3);
        else widgetMoment(s, p, 392, cw, 316, lang);
        txt(s, 'Mobile product caption', i === 0 ? (lang === 'zh' ? '放大、浏览、看清细节' : 'Zoom, browse, and inspect the details') : (lang === 'zh' ? '任务在后台运行，你可以继续浏览' : 'Tasks run while you keep browsing'), p, 724, cw, 12, C.muted, 400, 20);
      }
    } else if (i === 1) widgetMoment(s, p, 56, 768, 480, lang);
    else photo(s, 'Product / Native latest Figma frame', assets[i], 576, 56, 768, 480, 12);
    y += rowH;
  }

  const moreH = mobile ? 1468 : 928;
  const more = section('05 / More local tools', y, moreH); y += moreH;
  label(more, t.moreLabel, p, 80, cw);
  txt(more, 'More tools headline', t.moreTitle, p, 120, cw, mobile ? 32 : 48, C.ink, 400, mobile ? 36 : 52);
  const ocrY = mobile ? 216 : 224, ocrH = mobile ? 392 : 240;
  const ocr = box(more, 'OCR / Feature', p, ocrY, cw, ocrH);
  rule(ocr, 'OCR / Hairline', 0, 0, cw);
  label(ocr, t.free, 24, 24, mobile ? cw - 48 : 600);
  txt(ocr, 'OCR headline', t.ocrTitle, 24, 60, mobile ? cw - 48 : 640, mobile ? 24 : 28, C.ink, 400, 32);
  txt(ocr, 'OCR description', t.ocrBody, 24, mobile ? 144 : 116, mobile ? cw - 48 : 600, 16, C.secondary, 400, 24);
  const sx = mobile ? 24 : 832, sy = mobile ? 272 : 32;
  t.ocrSteps.forEach((s, i) => {
    txt(ocr, 'OCR step ' + (i + 1), String(i + 1).padStart(2, '0'), sx, sy + i * 32, 32, 12, C.muted, 400, 20);
    txt(ocr, 'OCR instruction ' + (i + 1), s, sx + 40, sy + i * 32, mobile ? 192 : 248, 14, C.secondary, 400, 20);
    if (i === 2) {
      const key = box(ocr, 'Copy shortcut', mobile ? 244 : 1048, sy + i * 32 - 4, 48, 28, C.raised, 4, C.line);
      txt(key, 'Keycap label', '⌘C', 0, 4, 48, 12, C.ink, 400, 20).align = 'CENTER';
    }
  });
  const fy = ocrY + ocrH + 48, rowH = mobile ? 120 : 128;
  t.features.forEach((f, i) => {
    const col = mobile ? 0 : i % 2, row = mobile ? i : Math.floor(i / 2);
    const fx = p + col * 656, fw = mobile ? cw : 592, top = fy + row * rowH;
    rule(more, 'Tool divider ' + i, fx, top, fw);
    txt(more, 'Tool name / ' + f[0], f[0], fx, top + 20, fw, 18, C.ink, 500, 24);
    txt(more, 'Tool description / ' + f[0], f[1], fx, top + 56, fw, 14, C.secondary, 400, 20);
  });

  const widgetsH = mobile ? 1024 : 784;
  const widgets = section('06 / AI Widgets', y, widgetsH); widgets.anchor = 'widgets'; y += widgetsH;
  label(widgets, t.widgetLabel, p, 64, cw);
  txt(widgets, 'Widget headline', t.widgetTitle, p, 104, mobile ? cw : 640, mobile ? 32 : 48, C.ink, 400, mobile ? 36 : 52);
  txt(widgets, 'Widget introduction', t.widgetIntro, mobile ? p : 944, mobile ? 204 : 128, mobile ? cw : 400, 16, C.secondary, 400, 24);
  const costs = lang === 'zh' ? ['1 点 / 次', '30 点 / 次', '20 点 / 次', '30 点 / 次', '100 点 / 10 秒', '29 点 / 次'] : ['1 credit / run', '30 credits / run', '20 credits / run', '30 credits / run', '100 credits / 10s', '29 credits / run'];
  const descriptions = lang === 'zh' ? ['涂抹区域，描述想要的修改', '提高分辨率，保留细节', '保留头发等精细边缘', '描述不想保留的物体', '按时长计费，不足 10 秒按一份计', '上传图片或视频，获得分享链接'] : ['Paint an area and describe the change', 'Higher resolution, sharper detail', 'Keep fine edges such as hair', 'Describe unwanted objects in English', 'Duration billing, rounded up to 10 seconds', 'Upload media and get a shareable link'];
  const listY = mobile ? 292 : 264, rh = mobile ? 88 : 60;
  for (let i = 0; i < 6; i++) {
    const top = listY + i * rh;
    rule(widgets, 'Widget row divider ' + i, p, top, cw);
    txt(widgets, 'Widget / ' + t.widgets[i], t.widgets[i], p, top + 16, mobile ? 220 : 400, mobile ? 16 : 18, C.ink, 400, 24);
    txt(widgets, 'Widget cost / ' + i, costs[i], mobile ? 244 : 1104, top + 20, mobile ? 122 : 240, 12, C.secondary, 400, 20).align = 'RIGHT';
    txt(widgets, 'Widget purpose / ' + i, descriptions[i], mobile ? p : 528, top + (mobile ? 52 : 20), mobile ? cw : 552, 13, C.muted, 400, 20);
  }
  link(widgets, t.allWidgets + ' →', p, listY + rh * 6 + 24, cw, '/widgets/');
  txt(widgets, 'Cloud and price disclosure', t.widgetNote, p, listY + rh * 6 + 72, cw, 12, C.muted, 400, 20);

  const pricingH = mobile ? 1208 : 720;
  const pricing = section('07 / Pricing', y, pricingH); pricing.anchor = 'pricing'; y += pricingH;
  label(pricing, t.pricingLabel, p, 64, cw);
  txt(pricing, 'Pricing headline', t.pricingTitle, p, 104, mobile ? cw : 848, mobile ? 32 : 48, C.ink, 400, mobile ? 36 : 52);
  txt(pricing, 'Pricing introduction', t.pricingIntro, mobile ? p : 944, mobile ? 240 : 128, mobile ? cw : 400, 16, C.secondary, 400, 24);
  t.plans.forEach((plan, i) => {
    const px = mobile ? p : p + i * 432, py = mobile ? 312 + i * 276 : 288, pw = mobile ? cw : 384;
    rule(pricing, 'Plan top hairline ' + i, px, py, pw, i === 1 ? C.accent : C.line);
    txt(pricing, 'Plan name / ' + plan[0], plan[0], px, py + 24, pw, 18, C.ink, 500, 24);
    txt(pricing, 'Plan price / ' + i, plan[1], px, py + 64, pw, 40, C.ink, 400, 44).fontRole = 'display';
    txt(pricing, 'Plan term / ' + i, plan[2], px, py + 120, pw, 12, C.muted, 400, 20);
    txt(pricing, 'Plan description / ' + i, plan[3], px, py + 160, pw, 14, C.secondary, 400, 20);
    link(pricing, plan[4] + ' →', px, py + (mobile ? 240 : 288), pw, i === 0 ? '#download' : '/pricing/');
  });
  txt(pricing, 'Pricing disclosure', t.pricingNote, p, mobile ? 1164 : 652, cw, 12, C.muted, 400, 20);

  const downloadH = mobile ? 608 : 480;
  const download = section('08 / Download', y, downloadH, C.surface); download.anchor = 'download'; y += downloadH;
  label(download, t.downloadLabel, p, 64, cw);
  txt(download, 'Download headline', t.downloadTitle, p, 104, mobile ? cw : 720, mobile ? 40 : 56, C.ink, 400, mobile ? 44 : 60);
  const dx = mobile ? p : 944, dy = mobile ? 240 : 112;
  txt(download, 'Download description', t.downloadBody, dx, dy, mobile ? cw : 400, 16, C.secondary, 400, 24);
  button(download, t.download, dx, mobile ? 372 : 248, mobile ? cw : 224, 'accent', 48, 'https://glancepreview.com/download/Glance-1.0.4.dmg');
  link(download, t.install + ' →', dx, mobile ? 444 : 320, mobile ? cw : 400, '/install/');
  txt(download, 'Download system requirements', t.version, p, mobile ? 516 : 392, cw, 12, C.muted, 400, 20);

  const faqH = mobile ? 1152 : 784;
  const faq = section('09 / FAQ', y, faqH); y += faqH;
  label(faq, t.faqLabel, p, 80, cw);
  txt(faq, 'FAQ headline', t.faqTitle, p, 120, cw, mobile ? 32 : 48, C.ink, 400, mobile ? 36 : 52);
  t.faqs.forEach((f, i) => {
    const top = (mobile ? 224 : 240) + (mobile ? i : Math.floor(i / 2)) * (mobile ? 144 : 160), col = mobile ? 0 : i % 2;
    const fx = p + col * 656, fw = mobile ? cw : 592;
    rule(faq, 'FAQ divider ' + i, fx, top, fw);
    txt(faq, 'Question / ' + f[0], f[0], fx, top + 20, fw, 16, C.ink, 500, 24);
    txt(faq, 'Answer / ' + i, f[1], fx, top + 60, fw, 14, C.secondary, 400, 20);
  });

  const footerH = mobile ? 336 : 240;
  const footer = section('10 / Footer', y, footerH); y += footerH;
  rule(footer, 'Footer top hairline', p, 0, cw);
  txt(footer, 'Footer wordmark', 'Glance', p, 44, 160, 32, C.ink, 400, 40);
  txt(footer, 'Footer description', t.footer, p, 104, mobile ? cw : 576, 14, C.muted, 400, 20);
  [[t.privacy, '/privacy/'], [t.terms, '/terms/'], [t.refunds, '/refunds/'], [t.support, 'mailto:support@glancepreview.com']].forEach((f, i) => link(footer, f[0], mobile ? p + (i % 2) * 176 : 864 + i * 120, mobile ? 164 + Math.floor(i / 2) * 44 : 56, mobile ? 160 : 112, f[1]));
  txt(footer, 'Copyright', '© 2026 Glance', p, mobile ? 284 : 180, cw, 12, C.muted, 400, 20);
  root.h = y;
  root.lang = lang; root.mobile = mobile;
  return root;
}

function foundations() {
  const f = box(null, 'Design notes / Unslop direction & states', 0, 0, 1440, 1480, C.bg);
  label(f, 'Glance / Website / Latest Figma reference', 64, 64, 1200);
  txt(f, 'Title', 'Shizuka · Let the picture speak', 64, 112, 1280, 48, C.ink, 400, 52);
  const lines = [
    'Product · A Mac image and video viewer with in-place AI and comparison',
    'Character · Quiet, spacious, exact',
    'World · Sumi ink and Washi paper; the image carries the richness',
    'Moments · Native Focus and Compare frames from the latest Figma file',
    'Signature · Ma (space), Sen (hairline), Shu (a small vermilion mark)'
  ];
  lines.forEach((v, i) => txt(f, 'Direction / ' + i, v, 64, 204 + i * 36, 1280, 16, C.secondary, 400, 24));
  Object.entries(C).slice(0, 10).forEach(([name, color], i) => {
    const x = 64 + (i % 5) * 264, y = 448 + Math.floor(i / 5) * 120;
    box(f, 'Swatch / ' + name, x, y, 232, 56, color, 8, C.line);
    txt(f, 'Swatch label / ' + name, name + ' · ' + color, x, y + 68, 244, 12, C.secondary, 400, 20);
  });
  txt(f, 'Control states title', 'Primary action states', 64, 740, 1200, 28, C.ink, 400, 32);
  ['Default', 'Hover', 'Pressed', 'Keyboard focus'].forEach((state, i) => {
    const b = button(f, 'Download for Mac', 64 + i * 320, 804, 256);
    b.name = 'Primary button / ' + state;
    if (i === 1) b.fill = '#FFFFFF';
    if (i === 2) b.fill = '#D9D4CE';
    if (i === 3) box(f, 'Keyboard focus ring', b.x - 4, b.y - 4, b.w + 8, b.h + 8, null, 10, C.focus);
    label(f, state, b.x, 868, 256);
  });
  txt(f, 'Type and layout notes', 'Shippori Mincho · display / Inter · interface / Geist Mono · metadata\nChinese display: Noto Serif SC; Chinese interface: Noto Sans SC\n4 px spacing rhythm · 6 px controls · 12 px windows\nWebsite metadata uses text/2 for readability; original app layers retain their tokens', 64, 948, 1248, 18, C.secondary, 400, 32);
  txt(f, 'Motion notes', 'Motion · Hover 140 ms; press 160 ms; menu 180 ms\nEase-out cubic-bezier(0.22, 1, 0.36, 1)\nNo parallax, looping decoration, or animated layout', 64, 1124, 1248, 16, C.secondary, 400, 28);
  txt(f, 'Evidence and attribution', 'Reference: 3oIkv5jBJpRUORxliJZdHl / Sumi · Dark and Washi · Light\nProduct views: portable SVG reference groups; the App file stays read-only\nUnslop method by Damir Sokolovsky · CC BY 4.0\nhttps://github.com/heydamir/unslop', 64, 1272, 1280, 14, C.muted, 400, 24);
  return f;
}

function applyTheme(node, theme) {
  const palette = THEMES[theme];
  for (const field of ['fill', 'stroke', 'color']) {
    let role = Object.keys(C).find(k => C[k] === node[field]);
    if (role === 'accentInk' && field !== 'color') role = 'canvas';
    if (role) node[field] = palette[role];
  }
  if (theme === 'washi' && node.name === 'Primary button / Hover') node.fill = '#34342F';
  if (theme === 'washi' && node.name === 'Primary button / Pressed') node.fill = '#47453F';
  node.theme = theme;
  for (const child of node.children || []) applyTheme(child, theme);
}
function createDesign() {
  const frames = [], positions = [[0, 0], [1536, 0], [2080, 0], [3616, 0], [4160, 0]];
  for (const [row, theme] of ['sumi', 'washi'].entries()) {
    const group = [homepage('en', false), homepage('en', true), homepage('zh', false), homepage('zh', true), foundations()];
    group.forEach((f, i) => {
      applyTheme(f, theme); f.name = (theme === 'sumi' ? 'Sumi · ' : 'Washi · ') + f.name;
      f.x = positions[i][0]; f.y = row * 9728;
      frames.push(f);
    });
  }
  return { version: 3, pageName: 'Glance / Website / Shizuka · Latest', sourceFileKey: '3oIkv5jBJpRUORxliJZdHl',
    fileUrl: FILE_URL, referenceFileUrl: REFERENCE_FILE_URL, sources: FIGMA_SOURCES,
    credit: { author: 'Damir Sokolovsky', url: SOURCE, license: 'CC BY 4.0' }, colors: C, themes: THEMES, frames };
}

if (typeof module !== 'undefined') module.exports = { createDesign, ASSET_PATHS, estimate, wrap };
