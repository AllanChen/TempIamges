const COLORS = {
  bg: '#06070A',
  chrome: '#17181D',
  toolbar: '#15171B',
  canvas: '#090A0D',
  surface: '#17181D',
  raised: '#2C2D31',
  line: '#34353A',
  text: '#F3EEE8',
  secondary: '#AAA4A0',
  muted: '#726D69',
  accent: '#E8A87C',
  accentSoft: '#3A2C26',
  success: '#8FD0AF',
  danger: '#F18B86'
};

let fontRegular = { family: 'Inter', style: 'Regular' };
let fontMedium = { family: 'Inter', style: 'Medium' };
let fontSemibold = { family: 'Inter', style: 'Semi Bold' };

figma.showUI(__html__, { width: 390, height: 730, themeColors: true });

const ICONS = {
  rotate: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M14.7 6.2A6.2 6.2 0 1 0 15 10" stroke="CURRENT" stroke-width="1.6" stroke-linecap="round"/><path d="M11.5 3.5h3.7v3.7" stroke="CURRENT" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  flip: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2.5 9h13M5.5 5.5 2 9l3.5 3.5M12.5 5.5 16 9l-3.5 3.5" stroke="CURRENT" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  focus: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="3" y="4" width="12" height="10" rx="2" stroke="CURRENT" stroke-width="1.5"/><circle cx="7" cy="7.5" r="1.2" fill="CURRENT"/><path d="m4.5 12 3-3 2.2 2 1.8-1.6 2 2.6" stroke="CURRENT" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  videoFocus: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2" y="3.5" width="14" height="11" rx="2" stroke="CURRENT" stroke-width="1.5"/><path d="m7.25 6 4.5 3-4.5 3V6Z" fill="CURRENT"/></svg>',
  more: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="4" cy="9" r="1.25" fill="CURRENT"/><circle cx="9" cy="9" r="1.25" fill="CURRENT"/><circle cx="14" cy="9" r="1.25" fill="CURRENT"/></svg>',
  compare: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2.5" y="3.5" width="13" height="11" rx="2" stroke="CURRENT" stroke-width="1.5"/><path d="M9 4v10" stroke="CURRENT" stroke-width="1.5"/></svg>',
  slider: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 5h12M3 9h12M3 13h12" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/><circle cx="7" cy="5" r="1.6" fill="CURRENT"/><circle cx="11" cy="9" r="1.6" fill="CURRENT"/><circle cx="6" cy="13" r="1.6" fill="CURRENT"/></svg>',
  fit: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 7V3h4M11 3h4v4M15 11v4h-4M7 15H3v-4" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  tasks: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 3.5h10v11H4z" stroke="CURRENT" stroke-width="1.5"/><path d="M6.5 7h5M6.5 10h5" stroke="CURRENT" stroke-width="1.4" stroke-linecap="round"/></svg>',
  grid: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="3" y="3" width="4.5" height="4.5" rx="1" stroke="CURRENT" stroke-width="1.4"/><rect x="10.5" y="3" width="4.5" height="4.5" rx="1" stroke="CURRENT" stroke-width="1.4"/><rect x="3" y="10.5" width="4.5" height="4.5" rx="1" stroke="CURRENT" stroke-width="1.4"/><rect x="10.5" y="10.5" width="4.5" height="4.5" rx="1" stroke="CURRENT" stroke-width="1.4"/></svg>',
  info: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="9" cy="9" r="6" stroke="CURRENT" stroke-width="1.5"/><path d="M9 8v4" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/><circle cx="9" cy="5.5" r="1" fill="CURRENT"/></svg>',
  play: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m6 4 8 5-8 5V4Z" fill="CURRENT"/></svg>',
  pause: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6 4v10M12 4v10" stroke="CURRENT" stroke-width="2" stroke-linecap="round"/></svg>',
  capture: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 6h3l1-2h4l1 2h3v8H3V6Z" stroke="CURRENT" stroke-width="1.5" stroke-linejoin="round"/><circle cx="9" cy="10" r="2.5" stroke="CURRENT" stroke-width="1.5"/></svg>',
  refresh: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M14.5 7A6 6 0 1 0 15 10" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/><path d="M11.5 4h3.5v3.5" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  search: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="4.5" stroke="CURRENT" stroke-width="1.5"/><path d="m11.5 11.5 3 3" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/></svg>',
  clear: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 5h8l-.7 10H5.7L5 5ZM3.5 5h11M7 3h4" stroke="CURRENT" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  install: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9 3v8M5.5 7.5 9 11l3.5-3.5M4 14h10" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  uninstall: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 9h10" stroke="CURRENT" stroke-width="1.7" stroke-linecap="round"/></svg>',
  retry: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M14 6a5.5 5.5 0 1 0 .5 5" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/><path d="M11 3.5h3.5V7" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  file: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 2.5h6l4 4v9H4v-13Z M10 2.5v4h4 M6.5 10h5 M6.5 12.5h4" stroke="CURRENT" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round"/></svg>',
  copy: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="5.5" y="5.5" width="9" height="10" rx="1.5" stroke="CURRENT" stroke-width="1.4"/><path d="M11.5 5.5V4A1.5 1.5 0 0 0 10 2.5H4A1.5 1.5 0 0 0 2.5 4v7c0 .8.7 1.5 1.5 1.5h1.5" stroke="CURRENT" stroke-width="1.4"/></svg>',
  folder: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2.5 4h5l1.5 2h6.5v8.5h-13V4Z" stroke="CURRENT" stroke-width="1.4" stroke-linejoin="round"/></svg>',
  shield: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9 2.5 14.5 5v4c0 3-2.2 5.4-5.5 6.5C5.7 14.4 3.5 12 3.5 9V5L9 2.5Z" stroke="CURRENT" stroke-width="1.4"/><path d="m6.5 9 1.7 1.7 3.3-3.4" stroke="CURRENT" stroke-width="1.4" stroke-linecap="round"/></svg>',
  settings: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 5.5h12M3 12.5h12" stroke="CURRENT" stroke-width="1.4" stroke-linecap="round"/><circle cx="7" cy="5.5" r="2" fill="#17181D" stroke="CURRENT" stroke-width="1.4"/><circle cx="11" cy="12.5" r="2" fill="#17181D" stroke="CURRENT" stroke-width="1.4"/></svg>',
  chevron: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m7 4 5 5-5 5" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  check: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m3.5 9 3.5 3.5L14.5 5" stroke="CURRENT" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  warning: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9 2 16 15H2L9 2Z" stroke="CURRENT" stroke-width="1.4" stroke-linejoin="round"/><path d="M9 7v3.5M9 13v.2" stroke="CURRENT" stroke-width="1.4" stroke-linecap="round"/></svg>'
  ,close: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m4 4 10 10M14 4 4 14" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/></svg>'
  ,back: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m11 4-5 5 5 5" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
  ,sidebar: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2.5" y="3.5" width="13" height="11" rx="2" stroke="CURRENT" stroke-width="1.5"/><path d="M7 3.5v11" stroke="CURRENT" stroke-width="1.5"/></svg>'
  ,share: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9 11.5V3M6 5.5 9 2.5l3 3" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 8.5H3.5v6.5h11V8.5H13" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
  ,markup: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M11.5 3.5 14.5 6.5 6.5 14.5 3 15l.5-3.5 8-8Z" stroke="CURRENT" stroke-width="1.4" stroke-linejoin="round"/></svg>'
  ,zoomout: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="4.5" stroke="CURRENT" stroke-width="1.5"/><path d="M6 8h4M11.5 11.5l3 3" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/></svg>'
  ,zoomin: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="4.5" stroke="CURRENT" stroke-width="1.5"/><path d="M8 6v4M6 8h4M11.5 11.5l3 3" stroke="CURRENT" stroke-width="1.5" stroke-linecap="round"/></svg>'
};

function rgb(hex) {
  const value = hex.replace('#', '');
  return {
    r: parseInt(value.slice(0, 2), 16) / 255,
    g: parseInt(value.slice(2, 4), 16) / 255,
    b: parseInt(value.slice(4, 6), 16) / 255
  };
}

function fill(hex, opacity = 1) {
  return { type: 'SOLID', color: rgb(hex), opacity };
}

function frame(name, x, y, width, height, color, radius = 0) {
  const node = figma.createFrame();
  node.name = name;
  node.x = x;
  node.y = y;
  node.resize(width, height);
  node.fills = color ? [fill(color)] : [];
  node.cornerRadius = radius;
  node.clipsContent = true;
  return node;
}

function rect(name, parent, x, y, width, height, color, radius = 0, stroke = null) {
  const node = figma.createRectangle();
  node.name = name;
  node.x = x;
  node.y = y;
  node.resize(width, height);
  node.fills = color ? [fill(color)] : [];
  node.cornerRadius = radius;
  if (stroke) {
    node.strokes = [fill(stroke)];
    node.strokeWeight = 1;
  }
  parent.appendChild(node);
  return node;
}

function ellipse(name, parent, x, y, size, color) {
  const node = figma.createEllipse();
  node.name = name;
  node.x = x;
  node.y = y;
  node.resize(size, size);
  node.fills = [fill(color)];
  parent.appendChild(node);
  return node;
}

function text(name, parent, value, x, y, size = 14, color = COLORS.text, weight = 'regular', width = null, align = 'LEFT') {
  const node = figma.createText();
  node.name = name;
  node.fontName = weight === 'semibold' ? fontSemibold : weight === 'medium' ? fontMedium : fontRegular;
  node.fontSize = size;
  node.characters = value;
  node.fills = [fill(color)];
  node.x = x;
  node.y = y;
  if (width) {
    node.resize(width, node.height);
    node.textAlignHorizontal = align;
  }
  parent.appendChild(node);
  return node;
}

function button(parent, name, label, x, y, width, active = false) {
  const node = frame(name, x, y, width, 38, COLORS.raised, 8);
  node.strokes = [fill(active ? COLORS.accent : COLORS.line, active ? .58 : 1)];
  node.strokeWeight = 1;
  parent.appendChild(node);
  text('Label', node, label, 0, 10, 12, active ? COLORS.accent : COLORS.text, active ? 'semibold' : 'medium', width, 'CENTER');
  return node;
}

function iconButton(parent, name, iconName, x, y, active = false, tint = null) {
  const node = frame(name, x, y, 38, 38, COLORS.raised, 8);
  node.strokes = [fill(active ? COLORS.accent : COLORS.line, active ? .58 : 1)];
  node.strokeWeight = 1;
  parent.appendChild(node);
  const color = tint || (active ? COLORS.accent : COLORS.text);
  const svg = figma.createNodeFromSvg(ICONS[iconName].replaceAll('CURRENT', color));
  svg.name = 'Icon / ' + iconName;
  svg.resize(18, 18);
  svg.x = 10;
  svg.y = 10;
  node.appendChild(svg);
  return node;
}

function createScreenShell(name, x, title, subtitle = '') {
  const screen = frame(name, x, 0, 1554, 1012, COLORS.bg, 16);
  screen.strokes = [fill(COLORS.line)];
  screen.strokeWeight = 1;
  figma.currentPage.appendChild(screen);

  const root = frame('Editable Content', 0, 0, 1554, 1012, null, 0);
  root.fills = [];
  screen.appendChild(root);

  const titlebar = frame('01 / Titlebar', 0, 0, 1554, 58, COLORS.chrome);
  root.appendChild(titlebar);
  ellipse('Close', titlebar, 24, 23, 12, '#ED6A5E');
  ellipse('Minimize', titlebar, 44, 23, 12, '#F4BF4F');
  ellipse('Zoom', titlebar, 64, 23, 12, '#61C554');
  text('Window Title', titlebar, title, 0, subtitle ? 14 : 20, 15, COLORS.text, 'semibold', 1554, 'CENTER');
  if (subtitle) text('Subtitle', titlebar, subtitle, 0, 38, 11, COLORS.muted, 'regular', 1554, 'CENTER');

  const toolbar = frame('02 / Icon Toolbar', 0, 58, 1554, 70, COLORS.raised);
  toolbar.strokes = [fill(COLORS.line)];
  toolbar.strokeWeight = 1;
  root.appendChild(toolbar);

  return { screen, root, titlebar, toolbar };
}

function createStatusbar(root, left, center, right = '', rightColor = COLORS.accent) {
  const status = frame('06 / Statusbar', 0, 975, 1554, 37, '#1A1B20');
  status.strokes = [fill(COLORS.line)];
  status.strokeWeight = 1;
  root.appendChild(status);
  text('Left Status', status, left, 38, 11, 12, COLORS.secondary, 'regular', 480, 'LEFT');
  text('Center Hint', status, center, 0, 11, 12, COLORS.secondary, 'regular', 1554, 'CENTER');
  if (right) {
    ellipse('Status Dot', status, 1394, 15, 8, rightColor);
    text('Right Status', status, right, 1414, 11, 12, rightColor, 'medium');
  }
  return status;
}

function createVideoInspectScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Video Inspect / Clean Editable', x, 'Video Inspect', 'clip.mov');
  iconButton(toolbar, 'Capture Frame', 'capture', 40, 14);
  iconButton(toolbar, 'Focus', 'videoFocus', 686, 14, true);
  iconButton(toolbar, 'Compare', 'compare', 734, 14);
  iconButton(toolbar, 'Widget', 'grid', 1426, 14);
  iconButton(toolbar, 'Video Information', 'info', 1474, 14);

  const canvas = frame('03 / Video Canvas', 0, 128, 1554, 847, COLORS.canvas);
  root.appendChild(canvas);
  const video = rect('Video / clip.mov', canvas, 48, 20, 1458, 807, '#182027', 6, COLORS.line);
  artworkFill(video, ['#121C27', '#715041', '#1C2E28']);
  const play = frame('Playback Controls', 124, 722, 1306, 64, '#111217', 12);
  play.strokes = [fill(COLORS.line)]; play.strokeWeight = 1; canvas.appendChild(play);
  iconButton(play, 'Play', 'play', 16, 13, true);
  rect('Timeline Track', play, 76, 30, 1070, 4, '#34353A', 2);
  rect('Timeline Progress', play, 76, 30, 416, 4, COLORS.accent, 2);
  ellipse('Timeline Knob', play, 486, 25, 14, COLORS.accent);
  text('Current Time', play, '00:37', 1168, 24, 12, COLORS.secondary, 'medium');
  text('Duration', play, '01:42', 1224, 24, 12, COLORS.muted, 'regular');

  const info = panel(root, 'Video Information / hidden by default', 1120, 128, 434, 847, COLORS.surface);
  info.visible = false;
  text('Title', info, 'Video Information', 36, 24, 17, COLORS.text, 'semibold');
  metadataRow(info, 'Dimensions', '3840 × 2160', 84);
  metadataRow(info, 'Duration', '01:42', 122);
  metadataRow(info, 'Codec', 'H.265', 160);
  metadataRow(info, 'Frame rate', '30 fps', 198);
  metadataRow(info, 'Audio', 'AAC · 48 kHz', 236);
  metadataRow(info, 'Bitrate', '28.4 Mbps', 274);

  createStatusbar(root, 'H.265  •  3840 × 2160  •  30 fps', 'Space to play or pause');
  return screen;
}

function taskListRow(parent, y, title, detail, state, stateColor, selected = false) {
  const row = frame('Task / ' + title, 14, y, 332, 82, selected ? '#242229' : COLORS.surface, 9);
  row.strokes = [fill(selected ? COLORS.accent : COLORS.line, selected ? .42 : 1)];
  row.strokeWeight = 1;
  parent.appendChild(row);
  const thumb = rect('Thumbnail', row, 12, 13, 56, 56, '#263039', 7, COLORS.line);
  artworkFill(thumb);
  text('Title', row, title, 82, 17, 13, COLORS.text, 'semibold', 170, 'LEFT');
  text('Detail', row, detail, 82, 43, 11, COLORS.muted, 'regular', 190, 'LEFT');
  statusBadge(row, 'State', state, 250, 28, stateColor, 70);
  return row;
}

function timelineRow(parent, y, title, detail, time, color, current = false) {
  ellipse('Timeline Mark', parent, 28, y + 3, 14, color);
  if (current) {
    const halo = ellipse('Current Halo', parent, 23, y - 2, 24, color);
    halo.opacity = .14;
  }
  text('Title', parent, title, 58, y, 13, COLORS.text, 'medium');
  text('Detail', parent, detail, 58, y + 22, 11, COLORS.muted, 'regular');
  text('Time', parent, time, 430, y + 3, 11, COLORS.muted, 'regular', 110, 'RIGHT');
  if (y < 260) rect('Connector', parent, 34, y + 18, 1, 52, COLORS.line);
}

function createTaskCenterScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Task Center / Clean Editable', x, 'Task Center', '3 tasks');
  iconButton(toolbar, 'Refresh', 'refresh', 40, 14);
  iconButton(toolbar, 'Search', 'search', 88, 14);
  iconButton(toolbar, 'Open in Inspect', 'focus', 1378, 14);
  iconButton(toolbar, 'Clear Finished', 'clear', 1426, 14, false, COLORS.danger);
  iconButton(toolbar, 'Task Information', 'info', 1474, 14);

  const sidebar = panel(root, '03 / Task List', 0, 128, 360, 847, '#111217');
  text('Heading', sidebar, 'Tasks', 24, 22, 17, COLORS.text, 'semibold');
  text('Caption', sidebar, 'Local and polling Widget tasks', 24, 49, 11, COLORS.muted, 'regular');
  button(sidebar, 'All Filter', 'All', 20, 82, 72, true);
  button(sidebar, 'Running Filter', 'Running', 100, 82, 80);
  button(sidebar, 'Completed Filter', 'Done', 188, 82, 72);
  button(sidebar, 'Failed Filter', 'Failed', 268, 82, 72);
  taskListRow(sidebar, 140, 'Remove Background', 'Just now · input.png', 'Running', COLORS.accent, true);
  taskListRow(sidebar, 232, 'Upscale 2×', '12 min ago · portrait.jpg', 'Done', COLORS.success);
  taskListRow(sidebar, 324, 'Image Caption', 'Yesterday · product.webp', 'Failed', COLORS.danger);

  const detail = panel(root, '04 / Task Detail', 360, 128, 1194, 847, COLORS.surface);
  text('Task Title', detail, 'Remove Background', 32, 25, 18, COLORS.text, 'semibold');
  text('Task Metadata', detail, 'Task 81C4  •  Running', 32, 53, 12, COLORS.accent, 'medium');
  iconButton(detail, 'Show in Inspect', 'focus', 1084, 22);
  iconButton(detail, 'Cancel Task', 'uninstall', 1132, 22, false, COLORS.danger);

  const source = panel(detail, 'Source Preview', 32, 104, 528, 304, COLORS.canvas, 10);
  const sourceArt = rect('Source Image', source, 12, 12, 504, 280, '#263039', 7);
  artworkFill(sourceArt);
  const result = panel(detail, 'Result Preview', 578, 104, 528, 304, COLORS.canvas, 10);
  ellipse('Waiting Indicator', result, 240, 118, 48, COLORS.accentSoft);
  text('Waiting Label', result, 'Waiting for result', 0, 178, 12, COLORS.muted, 'medium', 528, 'CENTER');

  const timeline = panel(detail, 'Timeline', 32, 440, 560, 330, '#141519', 10);
  text('Timeline Heading', timeline, 'Timeline', 24, 20, 13, COLORS.text, 'semibold');
  timelineRow(timeline, 60, 'Task submitted', 'Client uploaded the source image', '14:32:06', COLORS.success);
  timelineRow(timeline, 132, 'Worker claimed', 'GPU worker eu-02', '14:32:08', COLORS.success);
  timelineRow(timeline, 204, 'Processing', 'Polling every 2 seconds', 'Now', COLORS.accent, true);
  timelineRow(timeline, 276, 'Download result', 'Waiting for output file', 'Pending', COLORS.muted);

  const diagnostics = panel(detail, 'Task Details', 612, 440, 494, 330, '#141519', 10);
  text('Heading', diagnostics, 'Task Details', 24, 20, 13, COLORS.text, 'semibold');
  metadataRow(diagnostics, 'Widget', 'Remove Background', 60);
  metadataRow(diagnostics, 'Input', 'input.png', 98);
  metadataRow(diagnostics, 'Worker', 'eu-02', 136);
  metadataRow(diagnostics, 'Progress', '64%', 174);
  metadataRow(diagnostics, 'Polling', '2 seconds', 212);

  createStatusbar(root, '3 tasks  •  1 running', 'Select a task to inspect details', '1 task running');
  return screen;
}

function marketBadge(parent, label, x, y, width = 50) {
  const badge = frame('Widget Badge / ' + label, x, y, width, 19, COLORS.accentSoft, 4);
  parent.appendChild(badge);
  text('Badge Label', badge, label, 0, 4, 9, COLORS.accent, 'semibold', width, 'CENTER');
  return badge;
}

function marketButton(parent, title, x, y, installed = false, width = null) {
  width = width || (installed ? 91 : 76);
  const action = frame(installed ? 'Installed / local registry' : 'Install Widget', x, y,
                       width, 31, installed ? '#1B3029' : COLORS.accent, 8);
  action.strokes = [fill(installed ? COLORS.success : COLORS.accent, .5)];
  action.strokeWeight = 1;
  parent.appendChild(action);
  text('Action Label', action, title, 0, 8, 11,
       installed ? COLORS.success : '#21130D', 'semibold', width, 'CENTER');
  return action;
}

const WIDGET_MARKET_CATALOG = [
  ['RB', 'Remove Background', 'Image', 'Remove backgrounds while preserving fine subject edges.'],
  ['IC', 'Image Caption', 'AI', 'Turn an image into a clear natural-language description.'],
  ['2×', 'Upscale 2×', 'Enhance', 'Increase resolution while recovering texture and detail.'],
  ['FR', 'Face Restore', 'Enhance', 'Repair soft or damaged faces in old photographs.'],
  ['SC', 'Smart Crop', 'Image', 'Create balanced crops for common aspect ratios.'],
  ['OE', 'Object Eraser', 'Image', 'Remove selected objects and reconstruct the background.'],
  ['PR', 'Portrait Relight', 'Enhance', 'Adjust portrait lighting with natural skin tones.'],
  ['PS', 'Product Shadow', 'Commerce', 'Add clean studio shadows beneath product photos.'],
  ['CZ', 'Colorize Photo', 'Enhance', 'Colorize monochrome photographs with restrained color.'],
  ['ST', 'Style Transfer', 'Creative', 'Apply a visual style while preserving composition.'],
  ['TX', 'OCR Extract', 'Text', 'Extract selectable text from images and screenshots.'],
  ['TR', 'Translate Image', 'Text', 'Translate detected text and preserve the source layout.'],
  ['QR', 'QR Reader', 'Utility', 'Read QR codes directly from the current image.'],
  ['BC', 'Barcode Scanner', 'Utility', 'Detect common product and inventory barcodes.'],
  ['EX', 'EXIF Cleaner', 'Privacy', 'Remove private camera and location metadata.'],
  ['FC', 'Format Converter', 'Utility', 'Convert images between modern file formats.'],
  ['BR', 'Batch Rename', 'Workflow', 'Rename a set of media files with reusable patterns.'],
  ['CM', 'Image Compressor', 'Optimize', 'Reduce image size with a visual quality target.'],
  ['PO', 'PNG Optimizer', 'Optimize', 'Shrink PNG files without changing visible pixels.'],
  ['WP', 'WebP Converter', 'Optimize', 'Create efficient WebP copies for web delivery.'],
  ['HC', 'HEIC Converter', 'Utility', 'Convert HEIC photos into broadly compatible formats.'],
  ['64', 'Base64 Toolkit', 'Developer', 'Encode images to Base64 or restore encoded images.'],
  ['PE', 'Palette Extractor', 'Color', 'Build a usable palette from the current image.'],
  ['DC', 'Dominant Color', 'Color', 'Find dominant colors and copy their values.'],
  ['BF', 'Blur Faces', 'Privacy', 'Detect and blur faces before sharing an image.'],
  ['WM', 'Watermark', 'Commerce', 'Apply a reusable text or logo watermark.'],
  ['MC', 'Meme Caption', 'Creative', 'Add readable captions with safe image margins.'],
  ['CS', 'Contact Sheet', 'Workflow', 'Arrange selected images into a contact sheet.'],
  ['PI', 'PDF to Images', 'Document', 'Render PDF pages into individual images.'],
  ['IP', 'Images to PDF', 'Document', 'Combine selected images into one PDF document.'],
  ['KF', 'Video Keyframes', 'Video', 'Extract representative frames from a video.'],
  ['VC', 'Video Caption', 'Video', 'Generate a concise description of a video clip.'],
  ['VS', 'Video Stabilize', 'Video', 'Reduce camera shake in handheld footage.'],
  ['VZ', 'Video Compress', 'Video', 'Reduce video size with a quality target.'],
  ['AT', 'Audio Transcribe', 'Audio', 'Transcribe spoken audio into editable text.'],
  ['SU', 'Subtitle Translate', 'Audio', 'Translate subtitle files while preserving timing.'],
  ['SD', 'Scene Detector', 'Video', 'Split footage into scenes at visual cuts.'],
  ['GM', 'GIF Maker', 'Creative', 'Create a looping GIF from images or video.'],
  ['GO', 'GIF Optimizer', 'Optimize', 'Reduce GIF size and preserve smooth playback.'],
  ['BB', 'Background Blur', 'Image', 'Create a natural lens blur behind the subject.'],
  ['DM', 'Depth Map', '3D', 'Estimate a grayscale depth map from one image.'],
  ['NM', 'Normal Map', '3D', 'Generate a normal map for texture workflows.'],
  ['LA', 'Line Art', 'Creative', 'Convert a photograph into clean line art.'],
  ['SR', 'Sketch Render', 'Creative', 'Render an image with a restrained pencil style.'],
  ['PX', 'Pixel Art', 'Creative', 'Create crisp pixel-art variants at selected scales.'],
  ['MI', 'Metadata Inspector', 'Developer', 'Inspect embedded media metadata in one place.'],
  ['DF', 'Duplicate Finder', 'Workflow', 'Find visually similar and duplicate images.'],
  ['SS', 'Screenshot Stitch', 'Workflow', 'Join overlapping screenshots into one image.'],
  ['CU', 'Cloud Upload', 'Cloud', 'Upload a result and copy a temporary share link.'],
  ['OS', 'OSS Publisher', 'Cloud', 'Publish generated files to configured OSS storage.']
].map((item, index) => ({
  icon: item[0], name: item[1], category: item[2], summary: item[3],
  publisher: index < 12 ? 'Glance Labs' : index % 4 === 0 ? 'Pixel Forge' : 'Glance Community',
  runs: index === 0 ? '12.4K' : ((49 - index) * 0.37 + 1.2).toFixed(1) + 'K',
  rating: index % 7 === 0 ? '4.9' : index % 5 === 0 ? '4.8' : '4.7',
  installed: [0, 2, 10, 17, 21, 45].includes(index),
  update: [2, 17, 31].includes(index),
  selected: index === 0
}));

function marketDenseRow(parent, y, widget, index) {
  const row = frame('Widget ' + String(index + 1).padStart(2, '0') + ' / ' + widget.name,
                    0, y, 444, 84, widget.selected ? '#211C1A' : COLORS.canvas);
  parent.appendChild(row);
  if (widget.selected) rect('Selected Accent', row, 0, 0, 3, 84, COLORS.accent);
  rect('Row Divider', row, 16, 83, 412, 1, COLORS.line);
  const iconColors = ['#342522', '#22312D', '#202C38', '#32273A', '#303022', '#26313A'];
  const icon = frame('Widget Icon', 16, 14, 48, 48, iconColors[index % iconColors.length], 10);
  icon.strokes = [fill(widget.selected ? COLORS.accent : COLORS.line, widget.selected ? .52 : 1)];
  icon.strokeWeight = 1;
  row.appendChild(icon);
  text('Icon Letter', icon, widget.icon, 0, 14, 14,
       widget.selected ? COLORS.accent : COLORS.secondary, 'semibold', 48, 'CENTER');
  text('Widget Name', row, widget.name, 78, 10, 13, COLORS.text, 'semibold', 248);
  if (widget.publisher === 'Glance Labs') ellipse('Verified Publisher', row, 78, 33, 7, COLORS.success);
  text('Publisher', row, widget.publisher, widget.publisher === 'Glance Labs' ? 91 : 78,
       29, 10, COLORS.muted, 'regular', 220);
  text('Summary', row, widget.summary, 78, 47, 10, COLORS.secondary, 'regular', 252);
  text('Usage and Rating', row, '↓ ' + widget.runs + '   ★ ' + widget.rating,
       78, 66, 9, COLORS.muted, 'regular', 174);
  if (widget.update) {
    marketBadge(row, 'UPDATE', 275, 63, 54);
  }
  const actionWidth = widget.installed ? 82 : 68;
  marketButton(row, widget.installed ? 'Installed' : 'Install',
               344, 26, widget.installed, actionWidth);
  return row;
}

function marketFilter(parent, label, count, x, width, selected) {
  const item = frame('Filter / ' + label, x, 0, width, 30,
                     selected ? COLORS.accentSoft : null, 7);
  item.strokes = [fill(selected ? COLORS.accent : COLORS.line, selected ? .44 : 1)];
  item.strokeWeight = 1;
  parent.appendChild(item);
  text('Filter Label', item, label, 10, 8, 10,
       selected ? COLORS.accent : COLORS.secondary, selected ? 'semibold' : 'medium');
  text('Filter Count', item, String(count), width - 31, 8, 10, COLORS.muted,
       'regular', 21, 'RIGHT');
  return item;
}

function createWidgetMarketScreen(x) {
  const board = frame('Widget Market / Install / Clean Editable', x, 0, 1554, 1012, COLORS.bg, 16);
  board.strokes = [fill(COLORS.line)]; board.strokeWeight = 1;
  figma.currentPage.appendChild(board);
  text('Review Heading', board, 'Widget Market  /  50-widget catalog', 92, 43,
       18, COLORS.text, 'semibold');
  text('Review Note', board, 'VS Code-inspired search, filters, dense results, and a persistent detail view.',
       92, 70, 11, COLORS.muted);

  const market = panel(board, '01 / Widget Marketplace Window', 92, 104, 1370, 824,
                       COLORS.surface, 16);
  market.effects = [{
    type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: .42 },
    offset: { x: 0, y: 20 }, radius: 44, spread: 0,
    visible: true, blendMode: 'NORMAL'
  }];
  const titlebar = frame('Titlebar', 0, 0, 1370, 48, COLORS.chrome);
  market.appendChild(titlebar);
  ellipse('Close', titlebar, 18, 18, 12, '#ED6A5E');
  ellipse('Minimize', titlebar, 38, 18, 12, '#F4BF4F');
  ellipse('Zoom', titlebar, 58, 18, 12, '#61C554');
  text('Window Title', titlebar, 'Widget Market', 0, 16, 13,
       COLORS.text, 'semibold', 1370, 'CENTER');
  iconButton(titlebar, 'Refresh Catalog', 'refresh', 1274, 5);
  iconButton(titlebar, 'Close Market', 'close', 1318, 5);
  rect('Titlebar Divider', titlebar, 0, 47, 1370, 1, COLORS.line);

  const catalog = frame('02 / Search and Widget List', 0, 48, 448, 776, COLORS.canvas);
  catalog.strokes = [fill(COLORS.line)]; catalog.strokeWeight = 1;
  market.appendChild(catalog);
  text('Catalog Heading', catalog, 'Widgets', 20, 17, 18, COLORS.text, 'semibold');
  text('Catalog Count', catalog, '50 available', 312, 22, 10,
       COLORS.muted, 'medium', 116, 'RIGHT');

  const search = frame('Search Widgets', 16, 53, 416, 38, COLORS.raised, 8);
  search.strokes = [fill(COLORS.accent, .52)]; search.strokeWeight = 1;
  catalog.appendChild(search);
  const searchIcon = figma.createNodeFromSvg(ICONS.search.replaceAll('CURRENT', COLORS.secondary));
  searchIcon.name = 'Search Icon'; searchIcon.resize(18, 18);
  searchIcon.x = 11; searchIcon.y = 10; search.appendChild(searchIcon);
  text('Search Placeholder', search, 'Search 50 widgets', 39, 11, 12, COLORS.secondary);
  text('Search Shortcut', search, '⌘F', 366, 11, 10, COLORS.muted, 'medium', 34, 'RIGHT');

  const filters = frame('Catalog Filters', 16, 103, 416, 30, null);
  catalog.appendChild(filters);
  marketFilter(filters, 'Marketplace', 50, 0, 132, true);
  marketFilter(filters, 'Installed', 6, 140, 116, false);
  marketFilter(filters, 'Updates', 3, 264, 104, false);
  iconButton(filters, 'Sort and Filter', 'settings', 378, -4);
  rect('List Header Divider', catalog, 0, 145, 448, 1, COLORS.line);

  const viewport = frame('03 / Scroll Viewport / 7 of 50 visible', 0, 146, 448, 600, COLORS.canvas);
  viewport.clipsContent = true;
  viewport.overflowDirection = 'VERTICAL_SCROLLING';
  catalog.appendChild(viewport);
  const list = frame('04 / Scroll Content / 50 Widgets', 0, 0, 444,
                     WIDGET_MARKET_CATALOG.length * 84, COLORS.canvas);
  list.clipsContent = false;
  viewport.appendChild(list);
  WIDGET_MARKET_CATALOG.forEach((widget, index) => {
    marketDenseRow(list, index * 84, widget, index);
  });
  rect('Scrollbar Track', viewport, 441, 8, 3, 584, '#34353A', 2).opacity = .72;
  rect('Scrollbar Thumb / top of 50', viewport, 441, 8, 3, 84, COLORS.accent, 2).opacity = .9;
  const listFooter = frame('Catalog Footer', 0, 746, 448, 30, COLORS.chrome);
  listFooter.strokes = [fill(COLORS.line)]; listFooter.strokeWeight = 1;
  catalog.appendChild(listFooter);
  text('Footer Count', listFooter, '50 widgets  •  Marketplace', 16, 9, 10, COLORS.muted);
  text('Footer Hint', listFooter, 'Scroll for more', 316, 9, 10,
       COLORS.muted, 'regular', 116, 'RIGHT');

  const detail = frame('05 / Selected Widget Detail', 448, 48, 922, 776, COLORS.surface);
  market.appendChild(detail);
  const detailIcon = frame('Selected Widget Icon', 32, 30, 72, 72, '#342522', 14);
  detailIcon.strokes = [fill(COLORS.accent, .52)]; detailIcon.strokeWeight = 1;
  detail.appendChild(detailIcon);
  text('Icon Letter', detailIcon, 'RB', 0, 23, 20, COLORS.accent, 'semibold', 72, 'CENTER');
  text('Widget Name', detail, 'Remove Background', 128, 29, 24, COLORS.text, 'semibold');
  ellipse('Verified Publisher', detail, 129, 66, 8, COLORS.success);
  text('Publisher', detail, 'Glance Labs  ·  Verified publisher', 144, 62, 11,
       COLORS.secondary, 'medium');
  text('Version', detail, 'v1.4.2', 128, 84, 10, COLORS.muted);
  marketButton(detail, 'Installed', 778, 32, true, 110);
  text('Selected Summary', detail,
       'Remove image backgrounds while preserving hair, soft edges, and transparent detail.',
       32, 122, 13, COLORS.secondary, 'regular', 720);
  text('Selected Metrics', detail, '↓ 12.4K runs    ★ 4.9    Updated 2 days ago',
       32, 153, 11, COLORS.muted);
  marketBadge(detail, 'IMAGE', 720, 147, 58);
  marketBadge(detail, 'CLOUD', 786, 147, 58);
  marketBadge(detail, 'OFFICIAL', 852, 147, 66);

  const tabs = frame('Detail Tabs', 0, 190, 922, 44, COLORS.chrome);
  tabs.strokes = [fill(COLORS.line)]; tabs.strokeWeight = 1;
  detail.appendChild(tabs);
  text('Overview Tab', tabs, 'Overview', 32, 14, 11, COLORS.accent, 'semibold');
  text('Commands Tab', tabs, 'Commands', 122, 14, 11, COLORS.secondary, 'medium');
  text('Changelog Tab', tabs, 'Changelog', 218, 14, 11, COLORS.secondary, 'medium');
  text('Permissions Tab', tabs, 'Permissions', 318, 14, 11, COLORS.secondary, 'medium');
  rect('Selected Tab Indicator', tabs, 32, 41, 53, 2, COLORS.accent, 1);

  const overview = frame('06 / Overview Content', 0, 234, 922, 542, COLORS.surface);
  detail.appendChild(overview);
  text('About Heading', overview, 'Remove backgrounds without leaving Glance',
       32, 30, 19, COLORS.text, 'semibold');
  paragraph('About Copy', overview,
            'Run the Widget from Image Inspect. The source image stays visible while the result is added beside it with a clear NEW badge.',
            32, 67, 568, 12, COLORS.secondary);
  rect('About Divider', overview, 32, 129, 568, 1, COLORS.line);
  text('Workflow Heading', overview, 'WORKFLOW', 32, 151, 10, COLORS.muted, 'semibold');
  const steps = [
    ['01', 'Choose an image', 'Run from the Widget menu in Image Inspect.'],
    ['02', 'Process securely', 'The source is uploaded to the configured worker.'],
    ['03', 'Review the result', 'A transparent PNG appears beside the source.']
  ];
  steps.forEach((step, index) => {
    const y = 181 + index * 76;
    const number = frame('Step ' + step[0], 32, y, 34, 34, COLORS.raised, 8);
    number.strokes = [fill(COLORS.line)]; number.strokeWeight = 1;
    overview.appendChild(number);
    text('Step Number', number, step[0], 0, 10, 10, COLORS.accent, 'semibold', 34, 'CENTER');
    text('Step Title', overview, step[1], 82, y, 13, COLORS.text, 'semibold');
    text('Step Detail', overview, step[2], 82, y + 24, 11, COLORS.secondary, 'regular', 470);
  });
  rect('Commands Divider', overview, 32, 420, 568, 1, COLORS.line);
  text('Command Heading', overview, 'AVAILABLE COMMAND', 32, 444, 10, COLORS.muted, 'semibold');
  text('Command Name', overview, 'Remove Background', 32, 470, 13, COLORS.text, 'semibold');
  text('Command IO', overview, 'Image  →  PNG with transparency', 32, 494, 11, COLORS.secondary);

  const facts = frame('Widget Information', 634, 30, 256, 482, COLORS.canvas, 10);
  facts.strokes = [fill(COLORS.line)]; facts.strokeWeight = 1;
  overview.appendChild(facts);
  text('Facts Heading', facts, 'Widget information', 20, 18, 13, COLORS.text, 'semibold');
  const factRows = [
    ['Publisher', 'Glance Labs'], ['Version', '1.4.2'], ['Released', 'Aug 18, 2026'],
    ['Category', 'Image'], ['Execution', 'Cloud'], ['Input', 'Image'], ['Output', 'PNG']
  ];
  factRows.forEach((fact, index) => {
    const y = 58 + index * 45;
    text('Fact Label / ' + fact[0], facts, fact[0], 20, y, 10, COLORS.muted);
    text('Fact Value / ' + fact[0], facts, fact[1], 112, y, 11,
         COLORS.secondary, 'medium', 124, 'RIGHT');
    if (index < factRows.length - 1) rect('Fact Divider / ' + fact[0], facts, 20, y + 27, 216, 1, COLORS.line);
  });
  const privacy = frame('Privacy Notice', 20, 389, 216, 69, '#17221F', 8);
  privacy.strokes = [fill(COLORS.success, .32)]; privacy.strokeWeight = 1;
  facts.appendChild(privacy);
  const shield = figma.createNodeFromSvg(ICONS.shield.replaceAll('CURRENT', COLORS.success));
  shield.name = 'Privacy Icon'; shield.resize(18, 18); shield.x = 12; shield.y = 12;
  privacy.appendChild(shield);
  text('Privacy Title', privacy, 'Reviewed permissions', 40, 12, 11,
       COLORS.success, 'semibold');
  text('Privacy Copy', privacy, 'Uploads only the selected image.', 12, 39, 10, COLORS.secondary);
  return board;
}

function trayRow(parent, y, icon, title, opts) {
  opts = opts || {};
  const row = frame('Row / ' + title, 12, y, 276, 40, opts.active ? COLORS.accentSoft : COLORS.surface, 8);
  if (opts.active) { row.strokes = [fill(COLORS.accent, .45)]; row.strokeWeight = 1; }
  parent.appendChild(row);
  const svg = figma.createNodeFromSvg(ICONS[icon].replaceAll('CURRENT', opts.tint || (opts.active ? COLORS.accent : COLORS.secondary)));
  svg.name = 'Icon / ' + icon; svg.resize(18, 18); svg.x = 12; svg.y = 11; row.appendChild(svg);
  text('Label', row, title, 42, 12, 13, opts.tint || (opts.active ? COLORS.accent : COLORS.text), opts.active ? 'semibold' : 'medium');
  if (opts.badge) {
    const badge = frame('Badge', 232, 10, 32, 20, COLORS.accent, 10);
    row.appendChild(badge);
    text('Badge Label', badge, opts.badge, 0, 4, 10, '#21130D', 'semibold', 32, 'CENTER');
  } else if (opts.trailing) {
    text('Trailing', row, opts.trailing, 150, 13, 11, COLORS.muted, 'regular', 114, 'RIGHT');
  }
  return row;
}

function createTrayPopoverScreen(x) {
  const board = frame('Tray Popover / Clean Editable', x, 0, 1554, 1012, COLORS.bg, 16);
  board.strokes = [fill(COLORS.line)]; board.strokeWeight = 1;
  figma.currentPage.appendChild(board);

  // Faux menu bar hint at the very top.
  const menubar = rect('macOS Menu Bar', board, 0, 0, 1554, 28, '#0C0D11');
  const eye = figma.createNodeFromSvg(ICONS.focus.replaceAll('CURRENT', COLORS.accent));
  eye.name = 'Tray Icon'; eye.resize(16, 16); eye.x = 1430; eye.y = 6; board.appendChild(eye);

  text('Note', board, 'Tray popover — replaces the native gray NSMenu with a Glance-themed panel',
       42, 44, 12, COLORS.muted, 'regular', 900);

  // The popover, anchored under the tray icon.
  const pop = panel(board, '01 / Tray Popover', 1150, 40, 300, 452, COLORS.surface, 16);
  const tint = rect('Warm Glass Tint', pop, 0, 0, 300, 452, '#2B211D'); tint.opacity = .18;

  // Header: brand + preview toggle
  const mark = frame('Glance Mark', 16, 16, 34, 34, COLORS.accentSoft, 9); pop.appendChild(mark);
  const glyph = figma.createNodeFromSvg(ICONS.focus.replaceAll('CURRENT', COLORS.accent));
  glyph.name = 'Icon / focus'; glyph.resize(18, 18); glyph.x = 8; glyph.y = 8; mark.appendChild(glyph);
  text('Brand', pop, 'Glance', 60, 18, 15, COLORS.text, 'semibold');
  text('Brand Sub', pop, 'Preview is on', 60, 38, 10, COLORS.success, 'medium');
  const toggle = frame('Preview Toggle', 250, 22, 38, 21, COLORS.accent, 11); pop.appendChild(toggle);
  ellipse('Knob', toggle, 19, 2, 17, '#21130D');
  rect('Header Divider', pop, 12, 66, 276, 1, COLORS.line);

  // Primary: Open Home
  const home = frame('Open Home', 12, 80, 276, 44, COLORS.accent, 10); pop.appendChild(home);
  const hsvg = figma.createNodeFromSvg(ICONS.focus.replaceAll('CURRENT', '#21130D'));
  hsvg.name = 'Icon / focus'; hsvg.resize(18, 18); hsvg.x = 16; hsvg.y = 13; home.appendChild(hsvg);
  text('Label', home, 'Open Glance Home', 44, 14, 13, '#21130D', 'semibold');

  // Navigation rows
  trayRow(pop, 138, 'tasks', 'Tasks', { badge: '2' });
  trayRow(pop, 182, 'refresh', 'Preview History');
  trayRow(pop, 226, 'settings', 'Preferences', { trailing: '⌘,' });
  rect('Divider 2', pop, 12, 278, 276, 1, COLORS.line);

  // Status rows
  trayRow(pop, 290, 'shield', 'Permissions', { trailing: 'All set' });
  trayRow(pop, 334, 'grid', 'Account', { trailing: 'Signed in' });
  rect('Divider 3', pop, 12, 386, 276, 1, COLORS.line);

  // Footer secondary actions
  text('About', pop, 'About Glance', 24, 400, 12, COLORS.muted, 'regular');
  text('Quit', pop, 'Quit', 0, 400, 12, COLORS.muted, 'regular', 276, 'RIGHT');

  return board;
}

async function generateTrayPopover() {
  await loadFonts();
  await createStyles();
  const name = 'Tray Popover / Clean Editable';
  const existing = figma.currentPage.children.find(child => child.name === name);
  if (existing) {
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Tray Popover already exists — nothing changed.' });
    return;
  }
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const board = createTrayPopoverScreen(maxX + 196);
  figma.currentPage.selection = [board];
  figma.viewport.scrollAndZoomIntoView([board]);
  figma.ui.postMessage({ message: 'Created the Tray Popover screen.' });
  figma.notify('Tray Popover created');
}

async function generateHomeScreen() {
  await loadFonts();
  await createStyles();
  const name = 'Home / Launcher / Clean Editable';
  const existing = figma.currentPage.children.find(child => child.name === name);
  if (existing) {
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Home / Launcher already exists — nothing changed.' });
    return;
  }
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const home = createHomeScreen(maxX + 196);
  figma.currentPage.selection = [home];
  figma.viewport.scrollAndZoomIntoView([home]);
  figma.ui.postMessage({ message: 'Created the Home / Launcher screen.' });
  figma.notify('Home / Launcher created');
}

async function generateHomeFolderScrollStudy() {
  await loadFonts();
  await createStyles();
  const name = 'Home / Folder Scroll / Thin Track Study';
  const existing = figma.currentPage.children.find(child => child.name === name);
  if (existing) {
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Selected the existing Home folder scroll study.' });
    return;
  }
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const board = createHomeFolderScrollStudy(maxX + 196);
  figma.currentPage.selection = [board];
  figma.viewport.scrollAndZoomIntoView([board]);
  figma.ui.postMessage({ message: 'Created Home / Folder Scroll / Thin Track Study.' });
  figma.notify('Home folder scroll study created');
}

function createHomeFolderScrollStudy(x) {
  const board = frame('Home / Folder Scroll / Thin Track Study', x, 0, 1080, 720, COLORS.bg, 12);
  board.strokes = [fill(COLORS.line)];
  board.strokeWeight = 1;
  figma.currentPage.appendChild(board);

  const titlebar = frame('Titlebar', 0, 0, 1080, 52, COLORS.chrome);
  board.appendChild(titlebar);
  ellipse('Close', titlebar, 20, 20, 12, '#ED6A5E');
  ellipse('Minimize', titlebar, 40, 20, 12, '#F4BF4F');
  ellipse('Zoom', titlebar, 60, 20, 12, '#61C554');
  text('Title', titlebar, 'Glance', 100, 12, 15, COLORS.text, 'semibold', 880, 'CENTER');
  text('Subtitle', titlebar, 'Open media to inspect', 100, 32, 11, COLORS.muted, 'regular', 880, 'CENTER');

  const open = frame('Open Surface', 0, 52, 700, 638, COLORS.canvas);
  board.appendChild(open);
  text('Welcome', open, 'Open something to inspect', 40, 40, 22, COLORS.text, 'semibold');
  text('Welcome Sub', open, 'Drop images or videos here, or choose files and folders.', 40, 82, 13, COLORS.secondary, 'regular', 620);
  const drop = frame('Drop Zone', 40, 128, 620, 222, '#0C0D11', 12);
  drop.strokes = [fill(COLORS.accent, .42)];
  drop.strokeWeight = 1;
  drop.dashPattern = [7, 6];
  open.appendChild(drop);
  const dropIcon = figma.createNodeFromSvg(ICONS.focus.replaceAll('CURRENT', COLORS.accent));
  dropIcon.name = 'Image Icon';
  dropIcon.resize(40, 40);
  dropIcon.x = 290;
  dropIcon.y = 62;
  drop.appendChild(dropIcon);
  text('Drop Title', drop, 'Drag images, videos or a folder here', 0, 140, 16, COLORS.text, 'semibold', 620, 'CENTER');
  text('Drop Hint', drop, 'PNG · JPEG · HEIC · WebP · MP4 · MOV · WebM', 0, 170, 11, COLORS.muted, 'regular', 620, 'CENTER');
  const openFiles = button(open, 'Open Files', 'Open Files…', 40, 370, 150, true);
  openFiles.fills = [fill(COLORS.accent)];
  openFiles.findOne(node => node.type === 'TEXT').fills = [fill('#21130D')];
  button(open, 'Open Folder', 'Open Folder…', 202, 370, 150);

  text('Folder Path', open, 'FOLDER  ·  ~/Pictures/Iceland', 40, 436, 11, COLORS.muted, 'semibold', 440);
  text('Folder Count', open, '12 images found', 500, 436, 11, COLORS.secondary, 'regular', 160, 'RIGHT');
  const strip = panel(open, 'Folder Thumbnails / Clipped', 40, 462, 620, 108, COLORS.surface, 12);
  strip.clipsContent = true;
  const palettes = [
    ['#24313B', '#8A5F4E', '#26352D'], ['#2E323D', '#A77B72', '#1A2633'],
    ['#24312D', '#7DA67D', '#26352D'], ['#363539', '#926A58', '#26332A'],
    ['#273032', '#B08565', '#36463C'], ['#323644', '#95718A', '#282A34'],
    ['#1B1D24', '#5B7C93', '#181A20']
  ];
  palettes.forEach((palette, index) => {
    const thumbnail = frame('Image ' + (index + 1), 12 + index * 96, 12, 84, 84, COLORS.raised, 6);
    thumbnail.strokes = [fill(COLORS.line)];
    thumbnail.strokeWeight = 1;
    strip.appendChild(thumbnail);
    artworkFill(rect('Preview', thumbnail, 3, 3, 78, 78, null, 4), palette);
  });
  // A slim in-panel track indicates the remaining images without adding
  // AppKit's full-height native scrollbar chrome to the thumbnail row.
  rect('Scroll Track', strip, 12, 102, 596, 3, '#34353A', 2).opacity = .8;
  rect('Draggable Thumb / 6 of 12 visible', strip, 12, 102, 286, 3, COLORS.accent, 2).opacity = .86;
  const next = frame('Next Images', 570, 39, 32, 32, COLORS.chrome, 16);
  next.strokes = [fill(COLORS.line)];
  next.strokeWeight = 1;
  strip.appendChild(next);
  const chevron = figma.createNodeFromSvg(ICONS.chevron.replaceAll('CURRENT', COLORS.text));
  chevron.name = 'Right Chevron';
  chevron.resize(18, 18);
  chevron.x = 7;
  chevron.y = 7;
  next.appendChild(chevron);
  const inspect = button(open, 'Inspect All', 'Inspect all 12 images', 40, 586, 220, true);
  inspect.fills = [fill(COLORS.accent)];
  inspect.findOne(node => node.type === 'TEXT').fills = [fill('#21130D')];

  const recent = frame('Recent Column', 700, 52, 380, 638, COLORS.surface);
  recent.strokes = [fill(COLORS.line)];
  recent.strokeWeight = 1;
  board.appendChild(recent);
  text('Recent Heading', recent, 'Recent', 40, 40, 19, COLORS.text, 'semibold');
  text('Recent Sub', recent, 'Reopen what you inspected before.', 40, 72, 11, COLORS.muted);
  const names = ['input.png', 'portrait.jpg', 'result.png', 'capture.heic'];
  names.forEach((name, index) => {
    const col = index % 2;
    const row = Math.floor(index / 2);
    const card = frame('Recent / ' + name, 20 + col * 176, 116 + row * 164, 164, 148, COLORS.raised, 9);
    recent.appendChild(card);
    artworkFill(rect('Preview', card, 5, 5, 154, 106, null, 6), palettes[index]);
    text('Filename', card, name, 10, 120, 11, COLORS.text, 'medium', 144);
  });
  const status = frame('Statusbar', 0, 690, 1080, 30, COLORS.chrome);
  status.strokes = [fill(COLORS.line)];
  status.strokeWeight = 1;
  board.appendChild(status);
  text('Status', status, '12 images ready', 20, 8, 12, COLORS.secondary);
  return board;
}

async function redesignWidgetMarket() {
  await loadFonts();
  await createStyles();
  const name = 'Widget Market / Install / Clean Editable';
  const old = figma.currentPage.children.find(child => child.name === name);
  if (old && old.findOne(node => node.name === '04 / Scroll Content / 50 Widgets')) {
    figma.currentPage.selection = [old];
    figma.viewport.scrollAndZoomIntoView([old]);
    figma.ui.postMessage({ message: 'Widget Market already contains the 50-widget scalable catalog.' });
    return;
  }
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const targetX = old ? old.x : maxX + 196;
  const updated = createWidgetMarketScreen(targetX);
  if (old) {
    old.name = 'Widget Market / Install / Previous';
    old.x = Math.max(maxX, targetX + updated.width) + 196;
  }
  figma.currentPage.selection = [updated];
  figma.viewport.scrollAndZoomIntoView([updated]);
  figma.ui.postMessage({ message: 'Updated Widget Market for 50 Widgets. Previous frame kept to the right.' });
  figma.notify('50-widget Market design created');
}

function createCompactShell(name, x, title, windowWidth, windowHeight) {
  const board = frame(name, x, 0, 1554, 1012, COLORS.bg, 16);
  board.strokes = [fill(COLORS.line)];
  board.strokeWeight = 1;
  figma.currentPage.appendChild(board);
  const wx = Math.round((1554 - windowWidth) / 2);
  const wy = Math.round((1012 - windowHeight) / 2);
  const windowFrame = panel(board, '01 / Glance Window', wx, wy, windowWidth, windowHeight, COLORS.surface, 16);
  const titlebar = frame('Titlebar', 0, 0, windowWidth, 44, COLORS.chrome);
  windowFrame.appendChild(titlebar);
  ellipse('Close', titlebar, 16, 17, 11, '#ED6A5E');
  ellipse('Minimize', titlebar, 34, 17, 11, '#F4BF4F');
  ellipse('Zoom', titlebar, 52, 17, 11, '#61C554');
  text('Window Title', titlebar, title, 0, 13, 12, COLORS.text, 'semibold', windowWidth, 'CENTER');
  return { board, windowFrame, titlebar };
}

function createQuickPreviewScreen(x) {
  const { board, windowFrame, titlebar } = createCompactShell('Quick Preview / Clean Editable', x, 'Glance Preview', 900, 630);
  iconButton(titlebar, 'Pin Preview', 'focus', 850, 4);
  const media = frame('02 / Mixed Media Preview', 0, 44, 522, 532, COLORS.canvas);
  windowFrame.appendChild(media);
  const tiles = [
    { x: 14, y: 14, name: 'input.png', palette: ['#24313B', '#946C58', '#29362F'] },
    { x: 264, y: 14, name: 'portrait.jpg', palette: ['#21302B', '#6B826F', '#2D3B3E'] },
    { x: 14, y: 266, name: 'README.md', palette: ['#1B1C22', '#3C3940', '#20212A'] },
    { x: 264, y: 266, name: 'clip.mov', palette: ['#242C3B', '#766174', '#302D39'] }
  ];
  for (const item of tiles) {
    const tile = panel(media, 'Media / ' + item.name, item.x, item.y, 244, 244, COLORS.raised, 12);
    artworkFill(rect('Preview', tile, 5, 5, 234, 234, null, 8), item.palette);
    rect('Filename Scrim', tile, 5, 205, 234, 34, '#141518', 6).opacity = .72;
    text('Filename', tile, item.name, 14, 214, 11, COLORS.text, 'medium');
  }
  const textPane = panel(windowFrame, '03 / Current Selection', 522, 44, 378, 532, COLORS.surface);
  text('Heading', textPane, 'Current Selection', 22, 23, 16, COLORS.text, 'semibold');
  text('Section Label', textPane, 'MIXED CONTENT', 22, 58, 10, COLORS.muted, 'semibold');
  const lines = ['~/Desktop/project/input.png', 'https://temp.himarts.com/result.png', 'README.md', 'clip.mov'];
  lines.forEach((line, index) => text('Selection / ' + line, textPane, line, 22, 94 + index * 32, 11, COLORS.secondary, 'regular', 330));
  paragraph('Summary', textPane, '2 images, 1 video and 1 document detected. Open the selection to inspect each item in context.', 22, 254, 326, 12);
  text('Shortcut Label', textPane, 'RETURN  Open    SPACE  Inspect', 22, 343, 11, COLORS.muted, 'medium');
  button(textPane, 'Open in Image Inspect', 'Open in Image Inspect', 22, 402, 334);
  iconButton(textPane, 'Copy Resolved URL', 'copy', 22, 454);
  text('Copy Action', textPane, 'Copy resolved URL', 72, 466, 12, COLORS.secondary, 'medium');
  const footer = frame('04 / Actions', 0, 576, 900, 54, COLORS.chrome);
  windowFrame.appendChild(footer);
  text('Item Count', footer, '4 items  •  mixed content', 16, 19, 11, COLORS.muted);
  button(footer, 'Copy', 'Copy', 638, 10, 82);
  const open = button(footer, 'Open Selected', 'Open Selected', 730, 10, 154, true);
  open.fills = [fill(COLORS.accent)];
  open.findOne(n => n.type === 'TEXT').fills = [fill('#21130D')];
  return board;
}

function homeTile(parent, x, y, name, type, palette, selected = false) {
  const card = panel(parent, 'Recent / ' + name, x, y, 214, 176, COLORS.raised, 12);
  if (selected) { card.strokes = [fill(COLORS.accent, .6)]; card.strokeWeight = 2; }
  artworkFill(rect('Preview', card, 6, 6, 202, 128, null, 8), palette);
  text('Filename', card, name, 14, 142, 12, COLORS.text, 'medium', 150);
  text('Type', card, type, 150, 143, 10, COLORS.muted, 'regular', 52, 'RIGHT');
  return card;
}

function homeFolderThumb(parent, x, palette) {
  const item = frame('Folder Image', x, 40, 92, 92, COLORS.raised, 8);
  item.strokes = [fill(COLORS.line)]; item.strokeWeight = 1;
  artworkFill(rect('Preview', item, 5, 5, 82, 82, null, 5), palette);
  parent.appendChild(item);
  return item;
}

function createHomeScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Home / Launcher / Clean Editable', x, 'Glance', 'Open images to inspect');
  iconButton(toolbar, 'Open Files', 'file', 40, 14, true);
  iconButton(toolbar, 'Open Folder', 'folder', 88, 14);
  iconButton(toolbar, 'Tasks', 'tasks', 1378, 14);
  iconButton(toolbar, 'Preferences', 'settings', 1426, 14);
  iconButton(toolbar, 'Information', 'info', 1474, 14);

  // ---- Left: primary open surface ----
  const open = frame('03 / Open Surface', 0, 128, 1000, 847, COLORS.canvas);
  root.appendChild(open);
  text('Welcome', open, 'Open something to inspect', 56, 48, 24, COLORS.text, 'semibold');
  text('Welcome Sub', open, 'Glance works from a file. Drop images here, or pick files and folders — Glance reads every image inside a folder.', 56, 84, 13, COLORS.secondary, 'regular', 700);

  // Drop zone (dashed)
  const drop = frame('Drop Zone', 56, 140, 888, 300, '#0C0D11', 16);
  drop.strokes = [fill(COLORS.accent, .5)]; drop.strokeWeight = 2;
  drop.dashPattern = [8, 6];
  open.appendChild(drop);
  const dropIcon = frame('Drop Icon', 411, 60, 66, 66, COLORS.accentSoft, 16);
  drop.appendChild(dropIcon);
  const dsvg = figma.createNodeFromSvg(ICONS.focus.replaceAll('CURRENT', COLORS.accent));
  dsvg.name = 'Icon / focus'; dsvg.resize(30, 30); dsvg.x = 18; dsvg.y = 18; dropIcon.appendChild(dsvg);
  text('Drop Title', drop, 'Drag images or a folder here', 0, 170, 16, COLORS.text, 'semibold', 888, 'CENTER');
  text('Drop Hint', drop, 'PNG · JPEG · HEIC · WebP · TIFF · RAW  and more', 0, 200, 11, COLORS.muted, 'regular', 888, 'CENTER');
  const openFiles = button(open, 'Open Files Button', 'Open Files…', 274, 456, 150, true);
  openFiles.fills = [fill(COLORS.accent)];
  openFiles.findOne(n => n.type === 'TEXT').fills = [fill('#21130D')];
  button(open, 'Open Folder Button', 'Open Folder…', 440, 456, 150);

  // Folder-loaded state: images read from a chosen folder
  text('Folder Group', open, 'FOLDER  ·  ~/Pictures/Iceland', 56, 528, 11, COLORS.muted, 'semibold');
  text('Folder Count', open, '24 images found', 730, 528, 11, COLORS.secondary, 'regular', 158, 'RIGHT');
  const strip = frame('Folder Images', 56, 556, 888, 132, COLORS.surface, 12);
  strip.strokes = [fill(COLORS.line)]; strip.strokeWeight = 1;
  open.appendChild(strip);
  const palettes = [
    ['#24313B', '#8A5F4E', '#26352D'], ['#2E323D', '#A77B72', '#1A2633'],
    ['#24312D', '#7DA67D', '#26352D'], ['#363539', '#926A58', '#26332A'],
    ['#273032', '#B08565', '#36463C'], ['#323644', '#95718A', '#282A34'],
    ['#1B1D24', '#5B7C93', '#181A20'], ['#2A2320', '#C09A6B', '#2E2A22']
  ];
  palettes.forEach((p, i) => homeFolderThumb(strip, 16 + i * 108, p));
  const more = frame('More Count', 880, 40, 92, 92, COLORS.raised, 8);
  more.strokes = [fill(COLORS.line)]; more.strokeWeight = 1;
  strip.appendChild(more);
  text('More Label', more, '+16', 0, 36, 15, COLORS.secondary, 'semibold', 92, 'CENTER');
  button(open, 'Inspect All Button', 'Inspect all 24 images', 56, 708, 210);

  // ---- Right: recent ----
  const recent = panel(root, '04 / Recent', 1000, 128, 554, 847, COLORS.surface);
  text('Recent Heading', recent, 'Recent', 40, 40, 19, COLORS.text, 'semibold');
  text('Recent Sub', recent, 'Reopen what you inspected before.', 40, 70, 11, COLORS.muted);
  iconButton(recent, 'Search Recent', 'search', 470, 34);
  const recents = [
    ['input.png', 'PNG', ['#24313B', '#8A5F4E', '#26352D'], true],
    ['portrait.jpg', 'JPEG', ['#2E323D', '#A77B72', '#1A2633'], false],
    ['result-remove-bg.png', 'PNG', ['#24312D', '#7DA67D', '#26352D'], false],
    ['product.webp', 'WebP', ['#363539', '#926A58', '#26332A'], false],
    ['capture.heic', 'HEIC', ['#273032', '#B08565', '#36463C'], false],
    ['design.png', 'PNG', ['#323644', '#95718A', '#282A34'], false]
  ];
  recents.forEach(([name, type, palette, sel], i) => {
    homeTile(recent, 40 + (i % 2) * 238, 110 + Math.floor(i / 2) * 200, name, type, palette, sel);
  });
  text('Recent Folder Group', recent, 'RECENT FOLDERS', 40, 716, 11, COLORS.muted, 'semibold');
  const folderRow = frame('Recent Folder', 40, 744, 474, 60, COLORS.raised, 10);
  folderRow.strokes = [fill(COLORS.line)]; folderRow.strokeWeight = 1;
  recent.appendChild(folderRow);
  const fsvg = figma.createNodeFromSvg(ICONS.folder.replaceAll('CURRENT', COLORS.accent));
  fsvg.name = 'Icon / folder'; fsvg.resize(20, 20); fsvg.x = 18; fsvg.y = 20; folderRow.appendChild(fsvg);
  text('Folder Name', folderRow, 'Iceland', 52, 12, 13, COLORS.text, 'medium');
  text('Folder Meta', folderRow, '~/Pictures/Iceland  ·  24 images', 52, 32, 10, COLORS.muted);
  text('Folder Open', folderRow, 'Open', 420, 22, 11, COLORS.accent, 'semibold', 40, 'RIGHT');

  createStatusbar(root, 'No file open  •  Open images to begin', 'Drop files anywhere  •  ⌘O to open  •  ⌘⇧O for a folder');
  return screen;
}

function createContentViewerScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Content Viewer / Clean Editable', x, 'Content Viewer', 'README.md');
  iconButton(toolbar, 'Plain Text', 'file', 40, 14, true);
  iconButton(toolbar, 'Markdown Preview', 'focus', 88, 14);
  iconButton(toolbar, 'Find', 'search', 1366, 14);
  iconButton(toolbar, 'Copy', 'copy', 1414, 14);
  iconButton(toolbar, 'Reveal in Finder', 'folder', 1462, 14);
  const code = frame('03 / Document Content', 0, 128, 1090, 847, COLORS.canvas);
  root.appendChild(code);
  text('Content Type', code, 'MARKDOWN  /  UTF-8', 32, 26, 11, COLORS.muted, 'semibold');
  const source = [
    ['1', '# Widget Worker', COLORS.text], ['2', '', COLORS.text],
    ['3', 'This document opens in the Content Viewer.', COLORS.secondary],
    ['4', 'Media rotation, zoom, and comparison do not appear here.', COLORS.secondary],
    ['5', '', COLORS.text], ['6', '```python', COLORS.accent],
    ['7', 'def process(task):', '#A9C5EF'],
    ['8', '    return {"status": "completed"}', COLORS.success],
    ['9', '```', COLORS.accent]
  ];
  for (const [number, value, color] of source) {
    const rowY = 96 + (Number(number) - 1) * 43;
    text('Line Number ' + number, code, number, 38, rowY, 12, COLORS.muted, 'regular', 32, 'RIGHT');
    if (value) text('Line ' + number, code, value, 92, rowY, 16, color, 'regular', 930);
  }
  const info = panel(root, '04 / Document Information', 1090, 128, 464, 847, COLORS.surface);
  const card = panel(info, 'Content Information / 3:4', 44, 52, 376, 502, COLORS.raised, 12);
  text('Heading', card, 'Content Information', 22, 23, 17, COLORS.text, 'semibold');
  paragraph('Description', card, 'Documents use a dedicated content viewer. File type, encoding, line count and source remain separate from media controls.', 22, 62, 330, 12);
  const infoRows = [['Type', 'Markdown'], ['Encoding', 'UTF-8'], ['Lines', '18'], ['Source', '~/Desktop/project'], ['Modified', 'Today at 14:32']];
  infoRows.forEach(([key, value], index) => {
    const y = 173 + index * 54;
    text('Key / ' + key, card, key, 22, y, 12, COLORS.muted, 'medium');
    text('Value / ' + key, card, value, 136, y, 12, COLORS.text, 'regular', 210, 'RIGHT');
    rect('Divider', card, 22, y + 34, 332, 1, COLORS.line);
  });
  createStatusbar(root, 'README.md  •  UTF-8  •  18 lines', 'Line 1, Column 1');
  return screen;
}

function webStateCard(parent, x, state, title, description, iconName, color, action = '') {
  const card = panel(parent, 'Widget Web / ' + state, x, 225, 450, 397, COLORS.surface, 16);
  ellipse('State Halo', card, 192, 54, 66, color).opacity = .13;
  iconButton(card, 'State Icon', iconName, 206, 68, false, color);
  text('Heading', card, title, 0, 155, 18, COLORS.text, 'semibold', 450, 'CENTER');
  const body = paragraph('Explanation', card, description, 42, 206, 366, 12, COLORS.secondary);
  body.textAlignHorizontal = 'CENTER';
  if (action) button(card, 'Recovery Action', action, 121, 313, 208, state === 'Success');
  return card;
}

function createWidgetWebScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Widget Web / States / Clean Editable', x, 'Widget Result', 'Loading  /  Success  /  Error');
  iconButton(toolbar, 'Reload Widget', 'refresh', 40, 14);
  iconButton(toolbar, 'Tasks', 'tasks', 1378, 14);
  iconButton(toolbar, 'Widget Market', 'grid', 1426, 14);
  iconButton(toolbar, 'Information', 'info', 1474, 14);
  const canvas = frame('03 / Web States', 0, 128, 1554, 847, COLORS.canvas);
  root.appendChild(canvas);
  text('Section Heading', canvas, 'One container. Three clear outcomes.', 56, 68, 22, COLORS.text, 'semibold');
  text('Section Subtitle', canvas, 'Keep the same frosted-dark frame from request through recovery.', 56, 108, 12, COLORS.muted);
  webStateCard(canvas, 39, 'Loading', 'Opening Widget', 'Loading appears only when the request lasts more than 300 ms. The page never flashes white.', 'refresh', COLORS.accent);
  webStateCard(canvas, 552, 'Success', 'Processing complete', 'The result was added beside its source in Image Inspect. Focus stays on the current image.', 'check', COLORS.success, 'View result');
  webStateCard(canvas, 1065, 'Error', 'Widget unavailable', 'The request timed out. Your input is preserved and you can try again without losing context.', 'warning', COLORS.danger, 'Retry loading');
  createStatusbar(root, 'Widget Web  •  transparent dark surface', 'Loading, success and error always include text');
  return screen;
}

function createBase64Screen(x) {
  const { screen, root, toolbar } = createScreenShell('Base64 Toolkit / Clean Editable', x, 'Base64 Toolkit', 'Text to image');
  iconButton(toolbar, 'Paste Base64', 'copy', 40, 14);
  iconButton(toolbar, 'Clear Input', 'clear', 88, 14);
  iconButton(toolbar, 'Information', 'info', 1474, 14);
  const editor = frame('03 / Input Editor', 0, 128, 1100, 847, '#0E0E11');
  root.appendChild(editor);
  text('Heading', editor, 'Base64 to Image', 36, 28, 20, COLORS.text, 'semibold');
  text('Instructions', editor, 'Paste a complete Data URL or a plain Base64 image string.', 36, 65, 12, COLORS.secondary);
  text('Field Label', editor, 'BASE64 CONTENT', 36, 115, 11, COLORS.muted, 'semibold');
  const textarea = panel(editor, 'Multiline Base64 Field', 36, 147, 1028, 560, COLORS.canvas, 12);
  text('Placeholder', textarea, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg...', 22, 22, 13, COLORS.muted, 'regular', 962);
  const codeLines = [
    'iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAYAAAB7GkOtAAAB',
    'Y0lEQVR4nO3BAQ0AAADCoPdPbQ43oAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  ];
  codeLines.forEach((line, index) => text('Example Base64 ' + (index + 1), textarea, line, 22, 79 + index * 29, 12, COLORS.secondary, 'regular', 962));
  text('Accepted Formats', editor, 'PNG  •  JPEG  •  WebP  •  GIF', 36, 734, 11, COLORS.muted, 'medium');
  button(editor, 'Clear', 'Clear', 746, 720, 92);
  const decode = button(editor, 'Decode and Preview', 'Decode and Preview', 852, 720, 212, true);
  decode.fills = [fill(COLORS.accent)];
  decode.findOne(n => n.type === 'TEXT').fills = [fill('#21130D')];

  const result = panel(root, '04 / Result Preview', 1100, 128, 454, 847, COLORS.surface);
  text('Heading', result, 'Result Preview', 28, 30, 17, COLORS.text, 'semibold');
  const preview = panel(result, 'Image Frame / 3:4', 42, 100, 370, 494, COLORS.canvas, 12);
  const placeholder = frame('Waiting Placeholder', 131, 178, 108, 108, COLORS.raised, 24);
  preview.appendChild(placeholder);
  iconButton(placeholder, 'Image Icon', 'focus', 35, 35);
  text('Waiting Label', result, 'Waiting for input', 0, 623, 12, COLORS.muted, 'medium', 454, 'CENTER');
  text('Detected Format', result, 'Detected format', 42, 694, 11, COLORS.muted, 'medium');
  text('Detected Value', result, 'Not detected', 266, 694, 11, COLORS.secondary, 'regular', 146, 'RIGHT');
  rect('Metadata Divider', result, 42, 720, 370, 1, COLORS.line);
  text('Estimated Size', result, 'Estimated size', 42, 739, 11, COLORS.muted, 'medium');
  text('Size Value', result, '0 KB', 266, 739, 11, COLORS.secondary, 'regular', 146, 'RIGHT');
  createStatusbar(root, 'Base64 Toolkit  •  UTF-8 input', 'Paste, validate and preview without leaving the window');
  return screen;
}

function historyCard(parent, x, y, name, subtitle, palette) {
  const card = panel(parent, 'History / ' + name, x, y, 348, 218, COLORS.raised, 12);
  artworkFill(rect('Preview', card, 6, 6, 336, 171, null, 8), palette);
  text('Filename', card, name, 14, 184, 12, COLORS.text, 'medium', 220);
  text('Type', card, subtitle, 246, 184, 11, COLORS.muted, 'regular', 88, 'RIGHT');
  return card;
}

function createHistoryScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Preview History / Clean Editable', x, 'Preview History', '8 items today');
  iconButton(toolbar, 'Search History', 'search', 40, 14);
  iconButton(toolbar, 'Open in Inspect', 'focus', 1378, 14);
  iconButton(toolbar, 'Clear History', 'clear', 1426, 14, false, COLORS.danger);
  iconButton(toolbar, 'History Information', 'info', 1474, 14);
  const catalog = frame('03 / History Grid', 0, 128, 1554, 847, '#0D0E11');
  root.appendChild(catalog);
  text('Section Title', catalog, 'Today', 32, 26, 19, COLORS.text, 'semibold');
  text('Count', catalog, '8 items', 32, 58, 11, COLORS.muted);
  const search = panel(catalog, 'Search Field', 1196, 24, 322, 40, COLORS.surface, 8);
  iconButton(search, 'Search Icon', 'search', 4, 1);
  text('Placeholder', search, 'Search filename', 54, 12, 12, COLORS.muted);
  const entries = [
    ['input.png', 'PNG', ['#24313B', '#9B705C', '#29382E']],
    ['result-remove-bg.png', 'PNG', ['#24312D', '#7DA67D', '#26352D']],
    ['portrait.jpg', 'JPEG', ['#2E323D', '#A77B72', '#1A2633']],
    ['product.webp', 'WebP', ['#363539', '#926A58', '#26332A']],
    ['clip.mov', 'MOV', ['#171F29', '#766051', '#222F2B']],
    ['README.md', 'Markdown', ['#1B1D24', '#484451', '#181A20']],
    ['design.png', 'PNG', ['#323644', '#95718A', '#282A34']],
    ['capture.jpg', 'JPEG', ['#273032', '#B08565', '#36463C']]
  ];
  entries.forEach(([name, type, palette], index) => {
    historyCard(catalog, 32 + (index % 4) * 374, 110 + Math.floor(index / 4) * 248, name, type, palette);
  });
  text('Keyboard Hint', catalog, 'Select a preview to reopen it  •  Delete history without touching downloaded files', 32, 665, 12, COLORS.muted);
  createStatusbar(root, 'Preview History  •  8 items', 'Search by filename, inspect again with one click');
  return screen;
}

function preferenceRow(parent, x, y, titleValue, subtitle, value = 'on') {
  text('Setting / ' + titleValue, parent, titleValue, x, y, 13, COLORS.text, 'medium');
  text('Explanation', parent, subtitle, x, y + 25, 11, COLORS.muted, 'regular', 644);
  if (value === 'on' || value === 'off') {
    const track = frame('Toggle / ' + titleValue, x + 678, y + 7, 38, 21, value === 'on' ? COLORS.accent : COLORS.raised, 11);
    parent.appendChild(track);
    ellipse('Knob', track, value === 'on' ? 19 : 2, 2, 17, value === 'on' ? '#21130D' : COLORS.secondary);
  } else {
    const dropdown = panel(parent, 'Selection / ' + titleValue, x + 581, y + 1, 135, 32, COLORS.raised, 8);
    text('Value', dropdown, value, 12, 9, 11, COLORS.text, 'medium', 108);
  }
  rect('Row Divider', parent, x, y + 62, 716, 1, COLORS.line);
}

function createPreferencesScreen(x) {
  const { screen, root, toolbar } = createScreenShell('Preferences / Clean Editable', x, 'Glance Preferences', 'General');
  iconButton(toolbar, 'General', 'settings', 40, 14, true);
  iconButton(toolbar, 'Appearance', 'grid', 88, 14);
  iconButton(toolbar, 'Privacy', 'shield', 1366, 14);
  iconButton(toolbar, 'Information', 'info', 1474, 14);
  const nav = panel(root, '03 / Settings Navigation', 0, 128, 286, 847, '#111217');
  const pages = [['General', 'settings'], ['Preview', 'focus'], ['Widgets', 'grid'], ['Privacy & Permissions', 'shield']];
  pages.forEach(([name, icon], index) => {
    const selected = index === 0;
    const row = frame('Tab / ' + name, 16, 27 + index * 58, 254, 44, selected ? COLORS.accentSoft : '#111217', 8);
    if (selected) { row.strokes = [fill(COLORS.accent, .45)]; row.strokeWeight = 1; }
    nav.appendChild(row);
    const svg = figma.createNodeFromSvg(ICONS[icon].replaceAll('CURRENT', selected ? COLORS.accent : COLORS.secondary));
    svg.name = 'Icon / ' + icon; svg.resize(18, 18); svg.x = 13; svg.y = 13; row.appendChild(svg);
    text('Tab Label', row, name, 43, 13, 12, selected ? COLORS.accent : COLORS.secondary, selected ? 'semibold' : 'medium');
  });
  const form = frame('04 / General Settings', 286, 128, 1268, 847, COLORS.surface);
  root.appendChild(form);
  text('Heading', form, 'General', 80, 51, 22, COLORS.text, 'semibold');
  text('Description', form, 'Control startup, language, previews, and the way Glance works in the background.', 80, 92, 12, COLORS.muted);
  text('Startup Group', form, 'STARTUP', 80, 154, 11, COLORS.muted, 'semibold');
  preferenceRow(form, 80, 192, 'Launch Glance at login', 'Keep the menu bar companion ready when macOS starts.');
  preferenceRow(form, 80, 275, 'Remember window position', 'Restore your inspect workspace across displays.');
  text('Language & Appearance Group', form, 'LANGUAGE & APPEARANCE', 80, 372, 11, COLORS.muted, 'semibold');
  preferenceRow(form, 80, 410, 'Interface language', 'Reopen windows to apply the new language.', 'English');
  preferenceRow(form, 80, 493, 'Reduce motion', 'Follow macOS accessibility preferences.', 'off');
  text('Clipboard Group', form, 'CLIPBOARD', 80, 590, 11, COLORS.muted, 'semibold');
  preferenceRow(form, 80, 628, 'Prefer copied images', 'When the clipboard contains both an image and a URL, use the image.');
  createStatusbar(root, 'Glance Preferences', 'Changes are saved automatically');
  return screen;
}

function permissionRow(parent, y, icon, titleValue, description, state, granted = false) {
  const row = frame('Permission / ' + titleValue, 0, y, 468, 70, COLORS.surface);
  parent.appendChild(row);
  const mark = frame('Symbol', 0, 15, 40, 40, COLORS.raised, 10); row.appendChild(mark);
  text('Glyph', mark, icon, 0, 12, 13, COLORS.secondary, 'semibold', 40, 'CENTER');
  text('Permission', row, titleValue, 54, 12, 13, COLORS.text, 'semibold');
  text('Description', row, description, 54, 37, 11, COLORS.muted);
  const action = frame('Status / ' + state, 354, 18, 114, 34, granted ? '#173027' : COLORS.raised, 8);
  row.appendChild(action);
  text('Status Text', action, state, 0, 10, 11, granted ? COLORS.success : COLORS.accent, 'medium', 114, 'CENTER');
  rect('Separator', row, 0, 69, 468, 1, COLORS.line);
}

function createOnboardingScreen(x) {
  const { board, windowFrame } = createCompactShell('Onboarding / Permissions / Clean Editable', x, 'Welcome to Glance', 580, 650);
  const body = frame('02 / Permission Setup', 0, 44, 580, 606, '#0B0C0F');
  windowFrame.appendChild(body);
  const icon = frame('Glance Mark', 256, 32, 68, 68, COLORS.accentSoft, 16);
  body.appendChild(icon);
  iconButton(icon, 'Product Icon', 'focus', 15, 15, true);
  text('Heading', body, 'Set up essential permissions', 0, 125, 20, COLORS.text, 'semibold', 580, 'CENTER');
  const subtitle = paragraph('Explanation', body, 'Glance needs permission to read the current selection and respond to your keyboard shortcut. You can change these settings later.', 75, 164, 430, 12, COLORS.secondary);
  subtitle.textAlignHorizontal = 'CENTER';
  const permissions = frame('Permission List', 56, 230, 468, 240, COLORS.surface);
  body.appendChild(permissions);
  permissionRow(permissions, 0, 'A', 'Accessibility', 'Read the current selection', 'Allowed', true);
  permissionRow(permissions, 80, 'I', 'Input Monitoring', 'Recognize the global shortcut', 'Open Settings');
  permissionRow(permissions, 160, 'F', 'Full Disk Access', 'Preview files in protected locations', 'Optional');
  const continueButton = button(body, 'Continue', 'Continue', 76, 512, 428, true);
  continueButton.fills = [fill(COLORS.accent)];
  continueButton.findOne(n => n.type === 'TEXT').fills = [fill('#21130D')];
  text('Footnote', body, 'Permissions stay under your control in macOS System Settings.', 0, 565, 10, COLORS.muted, 'regular', 580, 'CENTER');
  return board;
}

async function generateProductionScreens() {
  await loadFonts();
  await createStyles();
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const startX = maxX + 196;
  const video = createVideoInspectScreen(startX);
  const tasks = createTaskCenterScreen(startX + 1750);
  const market = createWidgetMarketScreen(startX + 3500);
  figma.currentPage.selection = [video, tasks, market];
  figma.viewport.scrollAndZoomIntoView([video, tasks, market]);
  figma.ui.postMessage({ message: 'Created Video Inspect, Task Center, and Widget Market.' });
  figma.notify('Three Glance production screens created');
}

async function generateRemainingScreens() {
  await loadFonts();
  await createStyles();
  const screens = [
    ['Home / Launcher / Clean Editable', createHomeScreen],
    ['Content Viewer / Clean Editable', createContentViewerScreen],
    ['Widget Web / States / Clean Editable', createWidgetWebScreen],
    ['Base64 Toolkit / Clean Editable', createBase64Screen],
    ['Preview History / Clean Editable', createHistoryScreen],
    ['Preferences / Clean Editable', createPreferencesScreen],
    ['Onboarding / Permissions / Clean Editable', createOnboardingScreen]
  ];
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const created = [];
  const skipped = [];
  for (const [name, create] of screens) {
    if (figma.currentPage.children.some(child => child.name === name)) {
      skipped.push(name);
      continue;
    }
    const node = create(maxX + 196);
    created.push(node);
    maxX = node.x + node.width;
  }
  if (created.length) {
    figma.currentPage.selection = created;
    figma.viewport.scrollAndZoomIntoView(created);
  }
  figma.ui.postMessage({ message: `Created ${created.length} screens; ${skipped.length} already existed.` });
  figma.notify(`${created.length} remaining Glance screens created`);
}

function panel(parent, name, x, y, width, height, color = COLORS.surface, radius = 0) {
  const node = frame(name, x, y, width, height, color, radius);
  node.strokes = [fill(COLORS.line)];
  node.strokeWeight = 1;
  parent.appendChild(node);
  return node;
}

function statusBadge(parent, name, label, x, y, color, width = 76) {
  const badge = frame(name, x, y, width, 26, color, 6);
  badge.opacity = .16;
  parent.appendChild(badge);
  const t = text('Label', parent, label, x, y + 6, 11, color, 'semibold', width, 'CENTER');
  t.opacity = 1;
  return badge;
}

function paragraph(name, parent, value, x, y, width, size = 12, color = COLORS.secondary, weight = 'regular') {
  const node = text(name, parent, value, x, y, size, color, weight, width, 'LEFT');
  node.textAutoResize = 'HEIGHT';
  node.resize(width, node.height);
  return node;
}

function artworkFill(node, colors = ['#24313B', '#8A5F4E', '#26352D']) {
  node.fills = [{
    type: 'GRADIENT_LINEAR',
    gradientTransform: [[0.72, 0.28, 0], [-0.28, 0.72, 0.28]],
    gradientStops: [
      { position: 0, color: { ...rgb(colors[0]), a: 1 } },
      { position: .52, color: { ...rgb(colors[1]), a: 1 } },
      { position: 1, color: { ...rgb(colors[2]), a: 1 } }
    ]
  }];
  return node;
}

function lightIconButton(parent, name, iconName, x, active = false) {
  const node = frame(name, x, 8, 38, 38, active ? '#34251F' : '#1D1E22', 9);
  node.fills = [fill(active ? '#34251F' : '#1D1E22', active ? .96 : .72)];
  node.strokes = [fill(active ? COLORS.accent : '#FFFFFF', active ? .78 : .12)];
  node.strokeWeight = 1;
  parent.appendChild(node);
  const color = active ? COLORS.accent : '#F3F3F3';
  const svg = figma.createNodeFromSvg(ICONS[iconName].replaceAll('CURRENT', color));
  svg.name = 'Icon / ' + iconName;
  svg.resize(18, 18);
  svg.x = 10;
  svg.y = 10;
  node.appendChild(svg);
  return node;
}

function createFloatingSystemControls(parent) {
  const controls = frame('System / Window Controls', 24, 24, 112, 54, null, 15);
  controls.fills = [fill('#161719', .90)];
  controls.strokes = [fill('#FFFFFF', .12)];
  controls.strokeWeight = 1;
  controls.effects = [{ type: 'BACKGROUND_BLUR', radius: 18, visible: true }];
  parent.appendChild(controls);
  ellipse('Close', controls, 20, 21, 12, '#ED6A5E');
  ellipse('Minimize', controls, 50, 21, 12, '#F4BF4F');
  ellipse('Fullscreen', controls, 80, 21, 12, '#61C554');
  return controls;
}

function createBareSystemControls(parent) {
  const dragRegion = frame('System / Transparent Drag Region', 0, 0, parent.width, 44, null, 0);
  dragRegion.fills = [];
  parent.appendChild(dragRegion);
  const controls = frame('System / Window Controls / Bare', 20, 16, 64, 16, null, 0);
  controls.fills = [];
  parent.appendChild(controls);
  const specs = [
    ['Close', 0, '#ED6A5E'],
    ['Minimize', 26, '#F4BF4F'],
    ['Fullscreen', 52, '#61C554']
  ];
  for (const [name, x, color] of specs) {
    const control = ellipse(name, controls, x, 2, 12, color);
    control.strokes = [fill('#000000', .18)];
    control.strokeWeight = 1;
    control.effects = [{
      type: 'DROP_SHADOW',
      color: { r: 0, g: 0, b: 0, a: .52 },
      offset: { x: 0, y: 1 },
      radius: 4,
      spread: 0,
      visible: true,
      blendMode: 'NORMAL'
    }];
  }
  return controls;
}

function createFloatingInspectToolbar(parent, width, activeName = 'Focus', focusIcon = 'focus') {
  const toolbar = frame('01 / Floating Toolbar', Math.round((width - 274) / 2), 24, 274, 54, null, 15);
  toolbar.fills = [fill('#161719', .90)];
  toolbar.strokes = [fill('#FFFFFF', .12)];
  toolbar.strokeWeight = 1;
  toolbar.effects = [{
    type: 'BACKGROUND_BLUR',
    radius: 18,
    visible: true
  }, {
    type: 'DROP_SHADOW',
    color: { r: .08, g: .09, b: .10, a: .24 },
    offset: { x: 0, y: 8 },
    radius: 24,
    spread: 0,
    visible: true,
    blendMode: 'NORMAL'
  }];
  parent.appendChild(toolbar);
  lightIconButton(toolbar, 'Focus', focusIcon, 14, activeName === 'Focus');
  lightIconButton(toolbar, 'Compare', 'compare', 66, activeName === 'Compare');
  lightIconButton(toolbar, 'Slider', 'slider', 118, activeName === 'Slider');
  lightIconButton(toolbar, 'Widget', 'grid', 170, activeName === 'Widget');
  lightIconButton(toolbar, 'Information', 'info', 222, activeName === 'Information');
  return toolbar;
}

function createSimpleImageViewerScreen(x, imageHash = null, imageSize = null) {
  const width = imageSize && imageSize.width ? imageSize.width : 1554;
  const height = imageSize && imageSize.height ? imageSize.height : 1012;
  const board = frame('Image Viewer / Simple Operation', x, 0, width, height, null, 16);
  board.strokes = [fill('#D8D1CA')];
  board.strokeWeight = 1;
  if (imageHash) {
    board.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  } else {
    artworkFill(board, ['#D9E2E4', '#C89B7D', '#48685C']);
  }
  figma.currentPage.appendChild(board);
  createFloatingSystemControls(board);
  createFloatingInspectToolbar(board, width);
  return board;
}

function createSimpleVideoViewerScreen(x) {
  const width = 1554;
  const height = 1012;
  const board = frame('Video Inspect / Simple Operation', x, 0, width, height, null, 16);
  board.strokes = [fill(COLORS.line)];
  board.strokeWeight = 1;
  artworkFill(board, ['#121C27', '#715041', '#1C2E28']);
  figma.currentPage.appendChild(board);

  const content = frame('03 / Video Content', 0, 0, width, height, null, 16);
  content.fills = [];
  board.appendChild(content);
  createFloatingSystemControls(board);
  createFloatingInspectToolbar(board, width, 'Focus', 'videoFocus');

  const playback = frame('02 / Floating Playback Controls', Math.round((width - 800) / 2), height - 80, 800, 56, null, 15);
  playback.fills = [fill('#161719', .90)];
  playback.strokes = [fill('#FFFFFF', .12)];
  playback.strokeWeight = 1;
  playback.effects = [
    { type: 'BACKGROUND_BLUR', radius: 18, visible: true },
    {
      type: 'DROP_SHADOW', color: { r: .08, g: .09, b: .10, a: .28 },
      offset: { x: 0, y: 8 }, radius: 24, spread: 0, visible: true, blendMode: 'NORMAL'
    }
  ];
  board.appendChild(playback);
  lightIconButton(playback, 'Play', 'play', 8, true);
  rect('Timeline Track', playback, 62, 26, 610, 4, '#4A4B50', 2);
  rect('Timeline Progress', playback, 62, 26, 238, 4, COLORS.accent, 2);
  ellipse('Timeline Knob', playback, 294, 21, 14, COLORS.accent);
  text('Time', playback, '00:37 / 01:42', 688, 20, 11, '#F3F3F3', 'medium', 92, 'RIGHT');
  return board;
}

// Video chrome uses fixed logical sizes in every mode. Only the timeline's
// width flexes; scaling the window must never scale controls or text.
const VIDEO_INSPECT_METRICS = {
  inset: 24, playbackHeight: 64, playbackMaxWidth: 1306,
  captureWidth: 220, captureHeight: 125, captureFooter: 25,
  filmstripSize: 96, filmstripGap: 10
};

function videoStudyGlass(parent, name, x, y, width, height, radius = 15) {
  const node = frame(name, x, y, width, height, null, radius);
  node.fills = [fill('#161719', .90)];
  node.strokes = [fill('#FFFFFF', .12)];
  node.strokeWeight = 1;
  node.effects = [{ type: 'BACKGROUND_BLUR', radius: 18, visible: true }, {
    type: 'DROP_SHADOW', color: { r: .08, g: .09, b: .10, a: .24 },
    offset: { x: 0, y: 8 }, radius: 24, spread: 0, visible: true, blendMode: 'NORMAL'
  }];
  parent.appendChild(node);
  return node;
}

function videoStudyText(parent, name, value, x, y, width, height = 16) {
  const label = text(name, parent, value, x, y, 12, COLORS.text, 'medium', width, 'CENTER');
  label.textAutoResize = 'NONE';
  label.resize(width, height);
  label.textAlignVertical = 'CENTER';
  return label;
}

function videoStudyArtwork(parent, name, x, y, width, height, aspect, imageHash, alternate = false) {
  const container = frame(name, x, y, width, height, COLORS.canvas);
  parent.appendChild(container);
  const fittedWidth = Math.min(width, height * aspect);
  const fittedHeight = fittedWidth / aspect;
  const media = rect('Full frame / aspect fit', container,
    (width - fittedWidth) / 2, (height - fittedHeight) / 2, fittedWidth, fittedHeight, null);
  if (imageHash) media.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FIT' }];
  else artworkFill(media, alternate ? ['#252C28', '#546C59', '#141C1A'] : ['#121C27', '#715041', '#1C2E28']);
  return container;
}

function createVideoInspectControlsStudy(x, spec, imageHash) {
  const m = VIDEO_INSPECT_METRICS;
  const { width, height, compare, aspect } = spec;
  const board = frame(spec.name, x, 0, width, height, COLORS.canvas, 16);
  board.strokes = [fill('#FFFFFF', .22)];
  board.strokeWeight = 1;
  figma.currentPage.appendChild(board);
  if (compare) {
    const half = (width - 2) / 2;
    videoStudyArtwork(board, 'Compare / A', 0, 0, half, height, aspect, imageHash);
    videoStudyArtwork(board, 'Compare / B', half + 2, 0, half, height, aspect, imageHash, true);
    rect('Compare / Divider', board, half, 0, 2, height, COLORS.canvas);
  } else {
    videoStudyArtwork(board, 'Focus / Video', 0, 0, width, height, aspect, imageHash);
  }
  createBareSystemControls(board);
  // On a narrow window, place the toolbar below the traffic lights.
  const toolbar = videoStudyGlass(board, '01 / Floating Toolbar',
    (width - 274) / 2, width < 520 ? 56 : 24, 274, 54);
  const tools = [
    ['Capture Frame', 'capture'], ['Focus', 'videoFocus'], ['Compare', 'compare'],
    ['Widget', 'grid'], ['More', 'more']
  ];
  tools.forEach(([name, icon], index) => {
    const tile = lightIconButton(toolbar, name, icon, 14 + index * 52,
      name === (compare ? 'Compare' : 'Focus'));
    tile.strokes = [];
  });

  const barWidth = Math.min(m.playbackMaxWidth, width - m.inset * 2);
  const playback = videoStudyGlass(board, '02 / Floating Playback Controls',
    (width - barWidth) / 2, height - m.inset - m.playbackHeight, barWidth, m.playbackHeight);
  const play = lightIconButton(playback, 'Play / Pause', 'pause', 16, true);
  play.y = 13;
  play.strokes = [];
  const currentX = barWidth - 126;
  const timeline = frame('Timeline / hit area', 70, 20, currentX - 86, 24, null);
  playback.appendChild(timeline);
  const trackWidth = timeline.width - 14;
  rect('Timeline Track', timeline, 7, 10, trackWidth, 4, '#34353A', 2);
  rect('Timeline Progress', timeline, 7, 10, trackWidth * .37, 4, COLORS.accent, 2);
  ellipse('Timeline Knob', timeline, trackWidth * .37, 5, 14, COLORS.accent);
  videoStudyText(playback, 'Current Time', '00:37', currentX, 24, 42);
  videoStudyText(playback, 'Time Separator', '/', currentX + 44, 24, 12);
  videoStudyText(playback, 'Duration', '01:42', barWidth - 68, 24, 52);

  const capture = videoStudyGlass(board, '03 / Captured Frame / fixed 220 × 125',
    width - m.inset - m.captureWidth, playback.y - m.inset - m.captureHeight,
    m.captureWidth, m.captureHeight, 12);
  const imageHeight = m.captureHeight - m.captureFooter;
  if (compare) {
    // Fit the complete side-by-side capture inside the same preview card.
    const fullWidth = Math.min(m.captureWidth, imageHeight * aspect * 2 + 2);
    const paneWidth = (fullWidth - 2) / 2;
    const paneHeight = paneWidth / aspect;
    const left = (m.captureWidth - fullWidth) / 2;
    const top = (imageHeight - paneHeight) / 2;
    videoStudyArtwork(capture, 'Capture / A', left, top, paneWidth, paneHeight, aspect, imageHash);
    videoStudyArtwork(capture, 'Capture / B', left + paneWidth + 2, top,
      paneWidth, paneHeight, aspect, imageHash, true);
  } else {
    videoStudyArtwork(capture, 'Capture / Full Video', 0, 0,
      m.captureWidth, imageHeight, aspect, imageHash);
  }
  const footer = frame('Timecode Footer', 0, imageHeight, m.captureWidth, m.captureFooter, COLORS.chrome);
  capture.appendChild(footer);
  const timecode = videoStudyText(footer, 'Capture Timecode', '00:37', 10, 5, m.captureWidth - 20, 15);
  timecode.textAlignHorizontal = 'LEFT';

  ensureVideoStudyFilmstrip(board, spec, imageHash);
  return board;
}

function ensureVideoStudyFilmstrip(board, spec, imageHash) {
  const name = '04 / Video Filmstrip / fixed 96 × 96';
  if (board.findOne(child => child.name === name)) return;
  const m = VIDEO_INSPECT_METRICS;
  const playback = board.findOne(child => child.name === '02 / Floating Playback Controls');
  const stripWidth = m.filmstripSize * 2 + m.filmstripGap;
  const strip = frame(name, (board.width - stripWidth) / 2,
    playback.y - 20 - m.filmstripSize, stripWidth, m.filmstripSize, null);
  board.appendChild(strip);
  const focusedVideo = board.findOne(child => child.name === 'Focus / Video');
  const focusedArtwork = focusedVideo && focusedVideo.findOne(child => child.name === 'Full frame / aspect fit');
  for (let index = 0; index < 2; index++) {
    const tile = videoStudyArtwork(strip, 'Video ' + (index + 1),
      index * (m.filmstripSize + m.filmstripGap), 0,
      m.filmstripSize, m.filmstripSize, spec.aspect, imageHash, index === 1);
    if (index === 0 && focusedArtwork) {
      tile.findOne(child => child.name === 'Full frame / aspect fit').fills = focusedArtwork.fills;
    }
    const selected = index === (spec.compare ? 1 : 0);
    tile.cornerRadius = 9;
    tile.strokes = [fill(selected ? COLORS.accent : '#FFFFFF', selected ? .8 : .16)];
    tile.strokeWeight = 1;
  }
  // Narrow Focus layouts stack the captured-frame preview above the filmstrip.
  const capture = board.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125');
  if (capture && capture.x < strip.x + strip.width && capture.x + capture.width > strip.x &&
      capture.y < strip.y + strip.height && capture.y + capture.height > strip.y) {
    capture.y = strip.y - m.inset - capture.height;
  }
}

async function generateVideoInspectControlsStudy(bytes) {
  await loadFonts();
  const specs = [
    { name: 'Video Inspect v4 / Focus / Landscape', width: 1120, height: 700, aspect: 16 / 9 },
    { name: 'Video Inspect v4 / Focus / Portrait', width: 560, height: 900, aspect: 9 / 16 },
    { name: 'Video Inspect v4 / Focus / Narrow', width: 320, height: 568, aspect: 9 / 16 },
    { name: 'Video Inspect v4 / Compare', width: 1554, height: 1012, aspect: 9 / 16, compare: true }
  ];
  const { imageHash } = await resolveStudyImage(bytes, ['Video Inspect / Simple Operation', 'Dark Refresh v2 / Video Inspect']);
  let x = figma.currentPage.children.reduce((right, child) => Math.max(right, child.x + child.width), 0) + 196;
  const boards = [];
  for (const spec of specs) {
    const existing = figma.currentPage.children.find(child => child.name === spec.name);
    const board = existing || createVideoInspectControlsStudy(x, spec, imageHash);
    if (existing) ensureVideoStudyFilmstrip(board, spec, imageHash);
    boards.push(board);
    if (!existing) x += spec.width + 120;
  }
  const noCaptureName = 'Video Inspect v4 / Focus / No Capture';
  let noCapture = figma.currentPage.children.find(child => child.name === noCaptureName);
  if (!noCapture) {
    // Derive the default state from the existing review frame, preserving
    // its artwork and any user edits to the toolbar or playback controls.
    noCapture = boards[0].clone();
    noCapture.name = noCaptureName;
    noCapture.x = x;
    noCapture.y = boards[0].y;
    const preview = noCapture.findOne(child => child.name === '03 / Captured Frame / fixed 220 × 125');
    if (preview) preview.remove();
  }
  ensureVideoStudyFilmstrip(noCapture, specs[0], imageHash);
  boards.push(noCapture);
  figma.currentPage.selection = boards;
  figma.viewport.scrollAndZoomIntoView(boards);
  figma.ui.postMessage({ message: 'Video Inspect v4 ready: Focus filmstrips added, including No Capture. Existing review frames updated in place.' });
}

function createViewerChromeStudyScreen(x, imageHash = null, imageSize = null) {
  const width = imageSize && imageSize.width ? imageSize.width : 1554;
  const height = imageSize && imageSize.height ? imageSize.height : 1012;
  const board = frame('Dark Refresh v3 / Image Viewer / Simple Operation', x, 0, width, height, null, 16);
  board.strokes = [fill(COLORS.line)];
  board.strokeWeight = 1;
  if (imageHash) {
    board.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  } else {
    artworkFill(board, ['#D9E2E4', '#C89B7D', '#48685C']);
  }
  figma.currentPage.appendChild(board);
  createBareSystemControls(board);
  createFloatingInspectToolbar(board, width);
  return board;
}

// Compare-mode study: same v3 chrome as Simple Operation (bare traffic controls
// + floating toolbar, Compare active), two images side by side split by a thin
// divider, and — unlike Simple Operation — a VISIBLE window border/frame.
function createCompareChromeStudyScreen(x, imageHash = null, imageSize = null) {
  const width = imageSize && imageSize.width ? imageSize.width : 1554;
  const height = imageSize && imageSize.height ? imageSize.height : 1012;
  const board = frame('Dark Refresh v3 / Image Viewer / Compare Mode', x, 0, width, height, null, 16);
  // The requested window border: a clearly visible 2px framed edge (vs. the
  // borderless Simple Operation), plus a soft outer shadow to read as a window.
  board.fills = [fill('#060709', 1)];
  board.strokes = [fill('#5A5B62', 1)];
  board.strokeWeight = 2;
  board.effects = [{
    type: 'DROP_SHADOW',
    color: { r: 0, g: 0, b: 0, a: .45 },
    offset: { x: 0, y: 18 },
    radius: 48,
    spread: 0,
    visible: true,
    blendMode: 'NORMAL'
  }];
  figma.currentPage.appendChild(board);

  const gap = 2;
  const halfW = (width - gap) / 2;
  const leftImg = rect('Compare / A', board, 0, 0, halfW, height, null, 0);
  const rightImg = rect('Compare / B', board, halfW + gap, 0, halfW, height, null, 0);
  if (imageHash) {
    leftImg.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    rightImg.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  } else {
    leftImg.fills = [{ type: 'GRADIENT_LINEAR',
      gradientTransform: [[1, 0, 0], [0, 1, 0]],
      gradientStops: [
        { position: 0, color: { ...rgb('#D9E2E4'), a: 1 } },
        { position: 1, color: { ...rgb('#48685C'), a: 1 } }
      ] }];
    rightImg.fills = [{ type: 'GRADIENT_LINEAR',
      gradientTransform: [[1, 0, 0], [0, 1, 0]],
      gradientStops: [
        { position: 0, color: { ...rgb('#E7C9A6'), a: 1 } },
        { position: 1, color: { ...rgb('#8A5F4E'), a: 1 } }
      ] }];
  }
  // Center divider between the two panes.
  rect('Compare / Divider', board, halfW, 0, gap, height, '#0B0C0E');

  // A / B corner chips so the two-up read is unmistakable.
  const chipA = frame('Chip / A', 20, height - 52, 32, 32, null, 8);
  chipA.fills = [fill('#161719', .82)];
  chipA.strokes = [fill('#FFFFFF', .14)]; chipA.strokeWeight = 1;
  chipA.effects = [{ type: 'BACKGROUND_BLUR', radius: 12, visible: true }];
  board.appendChild(chipA);
  text('A', chipA, 'A', 0, 8, 14, '#F3F3F3', 'semibold', 32, 'CENTER');
  const chipB = frame('Chip / B', halfW + gap + 20, height - 52, 32, 32, null, 8);
  chipB.fills = [fill('#161719', .82)];
  chipB.strokes = [fill('#FFFFFF', .14)]; chipB.strokeWeight = 1;
  chipB.effects = [{ type: 'BACKGROUND_BLUR', radius: 12, visible: true }];
  board.appendChild(chipB);
  text('B', chipB, 'B', 0, 8, 14, '#F3F3F3', 'semibold', 32, 'CENTER');

  createBareSystemControls(board);
  createFloatingInspectToolbar(board, width, 'Compare');
  return board;
}

// ---------------------------------------------------------------------------
// Image Compression Flow
// ---------------------------------------------------------------------------

function compressionMenuRow(parent, y, iconName, label, active = false) {
  const row = frame('Row / ' + label, 12, y, 192, 34, active ? COLORS.accentSoft : COLORS.surface, 8);
  if (active) {
    row.strokes = [fill(COLORS.accent, .45)];
    row.strokeWeight = 1;
  }
  parent.appendChild(row);
  const color = active ? COLORS.accent : COLORS.secondary;
  const svg = figma.createNodeFromSvg(ICONS[iconName].replaceAll('CURRENT', color));
  svg.name = 'Icon / ' + iconName; svg.resize(18, 18); svg.x = 12; svg.y = 8; row.appendChild(svg);
  text('Label', row, label, 42, 9, 13, active ? COLORS.accent : COLORS.text, active ? 'semibold' : 'medium');
  return row;
}

function compressionMoreMenu(parent, x, y) {
  const menu = panel(parent, 'More menu', x, y, 216, 160, COLORS.surface, 10);
  menu.effects = [{
    type: 'DROP_SHADOW',
    color: { r: 0, g: 0, b: 0, a: .45 },
    offset: { x: 0, y: 18 },
    radius: 48,
    spread: 0,
    visible: true,
    blendMode: 'NORMAL'
  }];
  compressionMenuRow(menu, 10, 'copy', 'Copy Image');
  compressionMenuRow(menu, 50, 'folder', 'Save to Documents');
  compressionMenuRow(menu, 90, 'settings', 'Compress Image', true);
  rect('Menu Divider', menu, 12, 128, 192, 1, COLORS.line);
  compressionMenuRow(menu, 132, 'uninstall', 'Delete');
  return menu;
}

function compressionDialog(parent, x, y) {
  const dialog = panel(parent, 'Compression Dialog', x, y, 350, 280, COLORS.surface, 14);
  dialog.effects = [{
    type: 'DROP_SHADOW',
    color: { r: 0, g: 0, b: 0, a: .45 },
    offset: { x: 0, y: 18 },
    radius: 48,
    spread: 0,
    visible: true,
    blendMode: 'NORMAL'
  }];

  text('Title', dialog, 'Compress Image', 20, 20, 15, COLORS.text, 'semibold');
  text('Caption', dialog, 'Lower quality means a smaller file.', 20, 44, 12, COLORS.secondary, 'regular', 310);

  text('Quality Label', dialog, 'Quality', 20, 78, 12, COLORS.text, 'medium');
  text('Quality Value / updates with slider', dialog, '70%', 268, 78, 12, COLORS.accent, 'semibold', 62, 'RIGHT');
  rect('Slider Track', dialog, 20, 102, 310, 4, COLORS.line, 2);
  rect('Slider Fill / 70%', dialog, 20, 102, 217, 4, COLORS.accent, 2);
  const knob = ellipse('Slider Knob / draggable', dialog, 20 + 217 - 7, 97, 14, '#F3EEE8');
  knob.effects = [{
    type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: .35 },
    offset: { x: 0, y: 2 }, radius: 4, spread: 0, visible: true, blendMode: 'NORMAL'
  }];
  text('Slider Hint', dialog, '10% – 100%', 20, 114, 11, COLORS.muted, 'regular');

  const keepSize = frame('Keep original dimensions / checked', 20, 142, 310, 20, null, 0);
  keepSize.fills = [];
  dialog.appendChild(keepSize);
  const checkbox = frame('Checkbox / checked', 0, 2, 16, 16, COLORS.accent, 4);
  checkbox.strokes = [fill(COLORS.accent)]; checkbox.strokeWeight = 1;
  keepSize.appendChild(checkbox);
  const check = figma.createNodeFromSvg(ICONS.check.replaceAll('CURRENT', '#21130D'));
  check.name = 'Icon / check'; check.resize(12, 12); check.x = 2; check.y = 2; checkbox.appendChild(check);
  text('Checkbox Label', keepSize, 'Keep original dimensions', 26, 2, 12, COLORS.text, 'medium', 284);

  const result = panel(dialog, 'Compressed size / updates with slider', 20, 176, 310, 38, '#111217', 8);
  text('Result Label', result, 'Compressed size', 12, 11, 12, COLORS.secondary, 'medium');
  text('Result Value', result, '2.1 MB', 212, 9, 15, COLORS.text, 'semibold', 86, 'RIGHT');

  const cancel = frame('Cancel Button', 170, 236, 80, 32, '#17181D', 8);
  cancel.strokes = [fill(COLORS.line)]; cancel.strokeWeight = 1; dialog.appendChild(cancel);
  text('Cancel Label', cancel, 'Cancel', 0, 9, 12, COLORS.text, 'medium', 80, 'CENTER');

  const compress = frame('Compress Button', 260, 236, 90, 32, COLORS.accent, 8);
  dialog.appendChild(compress);
  text('Compress Label', compress, 'Compress', 0, 9, 12, '#21130D', 'semibold', 90, 'CENTER');

  return dialog;
}

function compressionSceneBase(name, x) {
  const board = frame(name, x, 0, 1554, 1012, '#060709', 16);
  board.strokes = [fill('#5A5B62')];
  board.strokeWeight = 2;
  board.effects = [{
    type: 'DROP_SHADOW',
    color: { r: 0, g: 0, b: 0, a: .45 },
    offset: { x: 0, y: 18 },
    radius: 48,
    spread: 0,
    visible: true,
    blendMode: 'NORMAL'
  }];

  const leftImg = rect('Image / original', board, 0, 0, 1554, 1012, null, 0);
  artworkFill(leftImg, ['#24313B', '#A77B72', '#26352D']);

  const shade = rect('Dim Shade', board, 0, 0, 1554, 1012, '#06070A', 0);
  shade.opacity = 0;

  createBareSystemControls(board);
  createFloatingInspectToolbar(board, 1554, 'Widget');
  return { board, shade };
}

function createCompressionFlowScreen(x, imageHash = null) {
  const flow = frame('Image Compression Flow', x, 0, 5054, 1012, null, 0);
  flow.fills = [];
  figma.currentPage.appendChild(flow);

  // Scene 1: Image Inspect with More menu open
  const scene1 = compressionSceneBase('01 / Image Inspect + More menu', 0);
  flow.appendChild(scene1.board);
  scene1.shade.opacity = 0;
  // More menu anchored below the toolbar right edge with 8 px gap.
  // Toolbar is 274 px wide centered in 1554: x=640, right edge=914.
  compressionMoreMenu(scene1.board, 914 - 216, 24 + 54 + 8);

  // Scene 2: Compression dialog
  const scene2 = compressionSceneBase('02 / Compression Dialog', 1750);
  flow.appendChild(scene2.board);
  scene2.shade.opacity = .48;
  compressionDialog(scene2.board, Math.round((1554 - 350) / 2), Math.round((1012 - 280) / 2));

  // Scene 3: Compare result
  const scene3 = frame('03 / Compare Result', 3500, 0, 1554, 1012, '#060709', 16);
  scene3.strokes = [fill('#5A5B62')]; scene3.strokeWeight = 2;
  scene3.effects = [{
    type: 'DROP_SHADOW',
    color: { r: 0, g: 0, b: 0, a: .45 },
    offset: { x: 0, y: 18 },
    radius: 48,
    spread: 0,
    visible: true,
    blendMode: 'NORMAL'
  }];
  flow.appendChild(scene3);

  const gap = 2;
  const halfW = (1554 - gap) / 2;
  const paneA = rect('Compare / A', scene3, 0, 0, halfW, 1012, null, 0);
  const paneB = rect('Compare / B', scene3, halfW + gap, 0, halfW, 1012, null, 0);
  if (imageHash) {
    paneA.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    paneB.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  } else {
    artworkFill(paneA, ['#D9E2E4', '#48685C']);
    artworkFill(paneB, ['#E7C9A6', '#8A5F4E']);
  }
  rect('Compare / Divider', scene3, halfW, 0, gap, 1012, '#0B0C0E');

  const chipA = frame('Chip / A', 20, 1012 - 52, 32, 32, null, 8);
  chipA.fills = [fill('#161719', .82)];
  chipA.strokes = [fill('#FFFFFF', .14)]; chipA.strokeWeight = 1;
  chipA.effects = [{ type: 'BACKGROUND_BLUR', radius: 12, visible: true }];
  scene3.appendChild(chipA);
  text('A', chipA, 'A', 0, 8, 14, '#F3F3F3', 'semibold', 32, 'CENTER');

  const chipB = frame('Chip / B', halfW + gap + 20, 1012 - 52, 32, 32, null, 8);
  chipB.fills = [fill('#161719', .82)];
  chipB.strokes = [fill('#FFFFFF', .14)]; chipB.strokeWeight = 1;
  chipB.effects = [{ type: 'BACKGROUND_BLUR', radius: 12, visible: true }];
  scene3.appendChild(chipB);
  text('B', chipB, 'B', 0, 8, 14, '#F3F3F3', 'semibold', 32, 'CENTER');

  createBareSystemControls(scene3);
  createFloatingInspectToolbar(scene3, 1554, 'Compare');

  // Filmstrip overlay
  const strip = frame('05 / Filmstrip Overlay', 16, 1012 - 117, 1522, 96, null, 0);
  strip.fills = [];
  scene3.appendChild(strip);
  const sourceThumb = frame('Source Thumbnail', 390, 0, 96, 96, COLORS.surface, 8);
  sourceThumb.strokes = [fill(COLORS.accent, .6)]; sourceThumb.strokeWeight = 2;
  strip.appendChild(sourceThumb);
  artworkFill(rect('Preview', sourceThumb, 5, 5, 86, 86, null, 6), ['#24313B', '#A77B72', '#26352D']);
  const compThumb = frame('Compressed Thumbnail', 496, 0, 96, 96, COLORS.surface, 8);
  compThumb.strokes = [fill(COLORS.accent, .6)]; compThumb.strokeWeight = 2;
  strip.appendChild(compThumb);
  artworkFill(rect('Preview', compThumb, 5, 5, 86, 86, null, 6), ['#E7C9A6', '#8A5F4E']);

  return flow;
}

async function generateImageCompressionFlow() {
  await loadFonts();
  await createStyles();
  const name = 'Image Compression Flow';
  const existing = figma.currentPage.children.find(child => child.name === name);
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const targetX = existing ? existing.x : maxX + 196;
  if (existing) existing.name = 'Image Compression Flow / Previous';
  const flow = createCompressionFlowScreen(targetX);
  if (existing) {
    existing.x = Math.max(maxX, targetX + flow.width) + 196;
  }
  figma.currentPage.selection = [flow];
  figma.viewport.scrollAndZoomIntoView([flow]);
  figma.ui.postMessage({ message: existing
    ? 'Updated Image Compression Flow. Previous frame kept to the right.'
    : 'Created Image Compression Flow (3 scenes).' });
  figma.notify('Image Compression Flow created');
}

// Seven focused Widget screens. The existing image/video input and image
// result flows stay in place; older studies are hidden so edits remain available.
const SIMPLE_WIDGET_NAME = 'Widget / Simple Input + Output / Clean Editable';
const OLD_WIDGET_FLOW_PREFIX = 'Widget Flow v1 / ';
const OLD_WIDGET_PAGE_NAMES = [
  'Widget Input / 01 / Image',
  'Widget Input / 02 / Image + Text',
  'Widget Input / 03 / Image + Text + Mask',
  'Widget Input / 04 / Video',
  'Widget Output / 01 / Image',
  'Widget Output / 02 / Text',
  'Widget Output / 03 / Video',
  'Widget Output / 04 / Audio'
];

function simpleWidgetArt(parent, name, x, y, width, height, imageHash, colors) {
  const art = rect(name, parent, x, y, width, height, null, 8, COLORS.line);
  if (imageHash) art.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  else artworkFill(art, colors);
  return art;
}

function simpleWidgetAction(parent, label, x, y, width, primary = false) {
  const action = frame(label + ' Action', x, y, width, 36,
                       primary ? COLORS.accent : COLORS.raised, 8);
  parent.appendChild(action);
  text('Action Label', action, label, 0, 10, 12,
       primary ? '#21130D' : COLORS.text, 'semibold', width, 'CENTER');
  return action;
}

const WIDGET_PAGE_NAMES = [
  'Widget Input / 02 / Image + Text / Revised',
  'Widget Input / 03 / Image + Text + Mask / Revised',
  'Widget Input / 03B / Image + Mask Only',
  'Widget Input / Draw Mask',
  'Widget Output / 02 / Text in Preview',
  'Widget Output / 03 / Video URL Preview',
  'Widget Output / 04 / Audio URL Player'
];

function widgetPageShell(name, x, y, section, hint) {
  const { screen, root, toolbar } = createScreenShell(name, x, 'Widget', section);
  screen.y = y;
  text('Section', toolbar, section.toUpperCase(), 44, 24, 12, COLORS.accent, 'semibold');
  text('Hint', toolbar, hint, 700, 24, 12, COLORS.secondary,
       'regular', 808, 'RIGHT');
  const body = frame('03 / Widget Canvas', 0, 128, 1554, 847, '#0C0D11');
  root.appendChild(body);
  return { screen, root, body };
}

function widgetPagePanel(body, title, subtitle, x, width) {
  const card = panel(body, '04 / Widget Panel', x, 42, width, 740, COLORS.surface, 14);
  text('Title', card, title, 32, 26, 24, COLORS.text, 'semibold');
  text('Subtitle', card, subtitle, 32, 63, 12, COLORS.secondary);
  rect('Header Divider', card, 32, 94, width - 64, 1, COLORS.line);
  return card;
}

function widgetPromptField(parent, x, y, width, height, value, disabled = false) {
  text('Prompt Label', parent, 'PROMPT', x, y, 11,
       disabled ? COLORS.muted : COLORS.secondary, 'semibold');
  const field = panel(parent, disabled ? 'Prompt Field / disabled' : 'Prompt Field',
                      x, y + 23, width, height,
                      disabled ? '#17181C' : '#101115', 9);
  field.strokes = [fill(disabled ? '#303137' : COLORS.line)];
  field.strokeWeight = 1;
  paragraph(disabled ? 'Prompt Text / disabled' : 'Prompt Text', field, value,
            17, 18, width - 34, 13,
            disabled ? COLORS.muted : COLORS.text);
  return field;
}

function widgetPageImageTextInput(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[0], x, y,
    'Input  ·  Image + text', 'Add a prompt to the selected image');
  const card = widgetPagePanel(body, 'Image and prompt',
    'The prompt tells the Widget what to make or change.', 350, 854);
  simpleWidgetArt(card, 'Selected Image', 32, 113, 790, 339, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  text('Image Filename', card, 'portrait.jpg  ·  6.8 MB', 32, 464, 12, COLORS.secondary);
  widgetPromptField(card, 32, 498, 790, 117,
    'Warm light, natural color, soft background');
  simpleWidgetAction(card, 'Change image', 32, 671, 150);
  simpleWidgetAction(card, 'Run Widget', 616, 671, 206, true);
  createStatusbar(root, 'Input  ·  image + text', 'Prompt and one picture');
  return screen;
}

function widgetPageImageMaskInput(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[1], x, y,
    'Input  ·  Image + text + mask', 'The mask selects the area to change');
  const card = widgetPagePanel(body, 'Image, prompt and mask',
    'Choose the image, describe the edit, then add a mask.', 250, 1054);
  simpleWidgetArt(card, 'Selected Image', 32, 113, 470, 488, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  text('Image Filename', card, 'portrait.jpg  ·  6.8 MB', 32, 616, 12, COLORS.secondary);
  widgetPromptField(card, 526, 113, 496, 145,
    'Replace the background with a garden');
  text('Mask Label', card, 'MASK', 526, 318, 11, COLORS.muted, 'semibold');
  const mask = panel(card, 'Mask Field', 526, 342, 496, 223, '#101115', 9);
  simpleWidgetArt(mask, 'Mask Preview', 17, 17, 169, 145, null,
                  ['#24252A', '#E8A87C', '#24252A']);
  text('Mask Help', mask, 'Select the area to change', 204, 31, 12, COLORS.text, 'medium');
  text('Mask File', mask, 'Transparent PNG', 204, 57, 11, COLORS.muted);
  simpleWidgetAction(mask, 'Upload mask', 17, 178, 220);
  simpleWidgetAction(mask, 'Draw mask', 254, 178, 225);
  simpleWidgetAction(card, 'Change image', 32, 671, 150);
  simpleWidgetAction(card, 'Run Widget', 816, 671, 206, true);
  createStatusbar(root, 'Input  ·  image + text + mask',
                  'The mask can be uploaded or drawn');
  return screen;
}

function widgetPageMaskOnlyInput(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[2], x, y,
    'Input  ·  Image + mask', 'This Widget does not accept a prompt');
  const card = widgetPagePanel(body, 'Image and mask',
    'Choose an image, then mark the area to change.', 250, 1054);
  simpleWidgetArt(card, 'Selected Image', 32, 113, 470, 488, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  text('Image Filename', card, 'portrait.jpg  ·  6.8 MB', 32, 616, 12, COLORS.secondary);
  widgetPromptField(card, 526, 113, 496, 98,
    'Prompt unavailable for this Widget', true);
  text('Mask Label', card, 'MASK', 526, 265, 11, COLORS.muted, 'semibold');
  const mask = panel(card, 'Mask Field', 526, 289, 496, 276, '#101115', 9);
  simpleWidgetArt(mask, 'Mask Preview', 17, 17, 169, 198, null,
                  ['#24252A', '#E8A87C', '#24252A']);
  text('Mask Help', mask, 'Select the area to change', 204, 31, 12, COLORS.text, 'medium');
  text('Mask File', mask, 'Transparent PNG', 204, 57, 11, COLORS.muted);
  simpleWidgetAction(mask, 'Upload mask', 17, 231, 220);
  simpleWidgetAction(mask, 'Draw mask', 254, 231, 225);
  simpleWidgetAction(card, 'Change image', 32, 671, 150);
  simpleWidgetAction(card, 'Run Widget', 816, 671, 206, true);
  createStatusbar(root, 'Input  ·  image + mask', 'Prompt disabled by Widget manifest');
  return screen;
}

function widgetPageDrawMask(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[3], x, y,
    'Input  ·  Draw mask', 'Paint the area the Widget should change');
  const editor = panel(body, '04 / Mask Editor', 172, 42, 1210, 740, COLORS.surface, 14);
  text('Title', editor, 'Draw mask', 32, 26, 24, COLORS.text, 'semibold');
  text('Subtitle', editor, 'Paint over the area you want to change.', 32, 63, 12, COLORS.secondary);
  rect('Header Divider', editor, 32, 94, 1146, 1, COLORS.line);
  const canvas = panel(editor, 'Image Canvas', 32, 113, 821, 537, '#101115', 9);
  simpleWidgetArt(canvas, 'Source Image', 10, 10, 801, 517, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  const painted = frame('Painted Mask Overlay', 296, 113, 306, 274, null, 0);
  painted.fills = [];
  canvas.appendChild(painted);
  for (let i = 0; i < 7; i++) {
    const stroke = ellipse('Mask Brush Stroke', painted,
      24 + (i % 3) * 72, 12 + i * 30, 76, '#F4B58E');
    stroke.opacity = .42;
  }
  const controls = panel(editor, 'Mask Tools', 877, 113, 301, 537, '#101115', 9);
  text('Tools Label', controls, 'TOOLS', 20, 22, 11, COLORS.muted, 'semibold');
  simpleWidgetAction(controls, 'Brush', 20, 55, 124, true);
  simpleWidgetAction(controls, 'Erase', 157, 55, 124);
  text('Brush Size Label', controls, 'BRUSH SIZE', 20, 119, 11, COLORS.muted, 'semibold');
  rect('Brush Size Track', controls, 20, 152, 261, 5, COLORS.line, 3);
  rect('Brush Size Fill', controls, 20, 152, 113, 5, COLORS.accent, 3);
  ellipse('Brush Size Knob', controls, 126, 146, 17, '#F3EEE8');
  text('Brush Size Value', controls, '32 px', 20, 173, 11, COLORS.secondary);
  rect('Tools Divider', controls, 20, 210, 261, 1, COLORS.line);
  simpleWidgetAction(controls, 'Undo', 20, 232, 124);
  simpleWidgetAction(controls, 'Clear mask', 157, 232, 124);
  text('Mask Guide', controls, 'Orange shows the selected area.', 20, 291, 12, COLORS.secondary);
  text('Source Guide', controls, 'The source image stays visible while you draw.',
       20, 318, 11, COLORS.muted, 'regular', 260);
  simpleWidgetAction(editor, 'Cancel', 902, 671, 124);
  simpleWidgetAction(editor, 'Use mask', 1038, 671, 140, true);
  text('Canvas Filename', editor, 'portrait.jpg  ·  mask preview', 32, 681, 12, COLORS.secondary);
  createStatusbar(root, 'Input  ·  draw mask', 'Brush · Erase · Undo · Clear');
  return screen;
}

function widgetPageTextOutput(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[4], x, y,
    'Output  ·  Text', 'Read the answer next to the source image');
  const card = widgetPagePanel(body, 'Widget result',
    'The Widget returned a prompt as plain text.', 244, 1066);
  simpleWidgetArt(card, 'Source Image', 32, 113, 380, 535, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  const result = panel(card, 'Output Text Preview', 436, 113, 598, 535, '#101115', 9);
  text('Result Type', result, 'TEXT RESULT', 24, 24, 11, COLORS.accent, 'semibold');
  text('Result Title', result, 'Generated prompt', 24, 56, 20, COLORS.text, 'semibold');
  rect('Result Divider', result, 24, 92, 550, 1, COLORS.line);
  paragraph('Result Text', result,
    'A cinematic portrait in warm afternoon light. Natural skin tones, soft depth of field, muted green background, and calm expression. Shot at eye level with gentle contrast and subtle film grain.',
    24, 121, 550, 15, COLORS.text);
  text('Plain Text Note', result, 'Plain text returned by this Widget',
       24, 468, 11, COLORS.muted);
  text('Source Filename', card, 'portrait.jpg', 32, 681, 12, COLORS.secondary);
  simpleWidgetAction(card, 'Copy text', 886, 671, 148, true);
  createStatusbar(root, 'Output  ·  text', 'Copy the generated prompt');
  return screen;
}

function widgetPageVideoOutput(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[5], x, y,
    'Output  ·  Video URL', 'The video loads from its returned URL');
  const card = widgetPagePanel(body, 'Widget result',
    'Preview the video and keep the link.', 244, 1066);
  simpleWidgetArt(card, 'Source Image', 32, 113, 312, 535, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  const result = panel(card, 'Output Video Preview', 368, 113, 666, 535, '#101115', 9);
  text('Result Type', result, 'VIDEO RESULT  ·  URL', 20, 21, 11, COLORS.accent, 'semibold');
  simpleWidgetArt(result, 'Video Frame', 20, 54, 626, 327, null,
                  ['#182532', '#73584F', '#23312E']);
  iconButton(result, 'Play Output Video', 'play', 311, 197, true);
  iconButton(result, 'Play Control', 'play', 20, 399);
  rect('Timeline Track', result, 76, 418, 444, 4, COLORS.line, 2);
  rect('Timeline Progress', result, 76, 418, 171, 4, COLORS.accent, 2);
  text('Duration', result, '00:05 / 00:12', 536, 410, 11, COLORS.secondary);
  rect('URL Divider', result, 20, 456, 626, 1, COLORS.line);
  text('URL Label', result, 'SOURCE URL', 20, 475, 11, COLORS.muted, 'semibold');
  text('URL Value', result, 'https://cdn.example.com/video/result.mp4',
       20, 497, 12, COLORS.secondary, 'regular', 626);
  text('Source Filename', card, 'portrait.jpg', 32, 681, 12, COLORS.secondary);
  simpleWidgetAction(card, 'Copy URL', 748, 671, 132);
  simpleWidgetAction(card, 'Save video', 892, 671, 142, true);
  createStatusbar(root, 'Output  ·  video URL', 'Play the video or copy its URL');
  return screen;
}

function widgetPageAudioOutput(x, y, imageHash) {
  const { screen, root, body } = widgetPageShell(WIDGET_PAGE_NAMES[6], x, y,
    'Output  ·  Audio URL', 'Listen without reading a raw OSS link');
  const card = widgetPagePanel(body, 'Widget result',
    'Play the audio and keep the link.', 244, 1066);
  simpleWidgetArt(card, 'Source Image', 32, 113, 312, 535, imageHash,
                  ['#25323A', '#A47761', '#293B33']);
  const player = panel(card, 'Audio Player', 368, 113, 666, 535, '#101115', 9);
  text('Result Type', player, 'AUDIO RESULT  ·  URL', 24, 24, 11, COLORS.accent, 'semibold');
  text('Audio Filename', player, 'result.m4a', 24, 57, 20, COLORS.text, 'semibold');
  text('Audio Length', player, '00:18  ·  stereo', 24, 91, 12, COLORS.muted);
  for (let i = 0; i < 26; i++) {
    const height = 25 + ((i * 37) % 105);
    rect('Waveform Bar', player, 36 + i * 23, 237 - height / 2,
         9, height, COLORS.accent, 4);
  }
  iconButton(player, 'Play Audio', 'play', 24, 336, true);
  rect('Audio Track', player, 80, 353, 433, 4, COLORS.line, 2);
  rect('Audio Progress', player, 80, 353, 146, 4, COLORS.accent, 2);
  text('Audio Time', player, '00:07 / 00:18', 526, 346, 11, COLORS.secondary);
  rect('URL Divider', player, 24, 425, 618, 1, COLORS.line);
  text('URL Label', player, 'SOURCE URL', 24, 446, 11, COLORS.muted, 'semibold');
  text('URL Value', player, 'https://cdn.example.com/audio/result.m4a',
       24, 470, 12, COLORS.secondary, 'regular', 618);
  text('Source Filename', card, 'portrait.jpg', 32, 681, 12, COLORS.secondary);
  simpleWidgetAction(card, 'Copy URL', 748, 671, 132);
  simpleWidgetAction(card, 'Save audio', 892, 671, 142, true);
  createStatusbar(root, 'Output  ·  audio URL', 'Play the audio or copy its URL');
  return screen;
}

async function generateWidgetFlow(bytes) {
  await loadFonts();
  await createStyles();
  const page = figma.currentPage;
  for (const old of page.children.filter(node =>
    node.name.startsWith(OLD_WIDGET_FLOW_PREFIX) &&
    !node.name.startsWith(OLD_WIDGET_FLOW_PREFIX + 'Archived / '))) {
    old.name = OLD_WIDGET_FLOW_PREFIX + 'Archived / ' +
      old.name.slice(OLD_WIDGET_FLOW_PREFIX.length);
    old.visible = false;
  }
  const onePage = page.children.find(node => node.name === SIMPLE_WIDGET_NAME);
  if (onePage) {
    onePage.name = 'Widget / Archived / Simple Input + Output';
    onePage.visible = false;
  }
  for (const oldName of OLD_WIDGET_PAGE_NAMES) {
    const old = page.children.find(node => node.name === oldName);
    if (!old) continue;
    old.name = 'Widget / Archived / v1 / ' + oldName;
    old.visible = false;
  }
  const present = WIDGET_PAGE_NAMES.map(name =>
    page.children.find(node => node.name === name));
  if (present.every(Boolean)) {
    page.selection = [present[0]];
    figma.viewport.scrollAndZoomIntoView([present[0]]);
    figma.ui.postMessage({ message: 'All 7 revised Widget pages already exist. Showing the first input page.' });
    return;
  }
  const firstIndex = present.findIndex(Boolean);
  let startX;
  if (firstIndex >= 0) {
    startX = present[firstIndex].x - (firstIndex % 4) * 1750;
  } else {
    let maxX = 0;
    for (const child of page.children) maxX = Math.max(maxX, child.x + child.width);
    startX = maxX + 196;
  }
  const imageHash = bytes && bytes.length ? figma.createImage(new Uint8Array(bytes)).hash : null;
  const creators = [widgetPageImageTextInput, widgetPageImageMaskInput,
    widgetPageMaskOnlyInput, widgetPageDrawMask, widgetPageTextOutput,
    widgetPageVideoOutput, widgetPageAudioOutput];
  let created = 0;
  for (let index = 0; index < WIDGET_PAGE_NAMES.length; index++) {
    if (present[index]) continue;
    const x = startX + (index % 4) * 1750;
    const y = index < 4 ? 0 : 1160;
    creators[index](x, y, imageHash);
    created++;
  }
  const first = page.children.find(node => node.name === WIDGET_PAGE_NAMES[0]);
  page.selection = [first];
  figma.viewport.scrollAndZoomIntoView([first]);
  figma.ui.postMessage({ message: 'Created ' + created +
    ' revised Widget pages. Four inputs are above three outputs; showing the first input.' });
  figma.notify('Revised Widget input and output pages created');
}

const WIDGET_OSS_RESULT_SOURCE_NAME = 'Widget Output / Image URL / OSS Result';
const WIDGET_OSS_RESULT_NAME = 'Widget Output / Image URL / OSS Result / Refined';

function createWidgetOSSResultPage(x, imageHash) {
  const screen = frame(WIDGET_OSS_RESULT_NAME, x, 0, 1554, 1012, COLORS.bg, 16);
  screen.strokes = [fill(COLORS.line)];
  screen.strokeWeight = 1;
  figma.currentPage.appendChild(screen);
  const root = frame('Editable Content', 0, 0, 1554, 1012, null, 0);
  root.fills = [];
  screen.appendChild(root);
  const titlebar = frame('01 / Titlebar', 0, 0, 1554, 58, COLORS.chrome);
  root.appendChild(titlebar);
  ellipse('Close', titlebar, 24, 23, 12, '#ED6A5E');
  ellipse('Minimize', titlebar, 44, 23, 12, '#F4BF4F');
  ellipse('Zoom', titlebar, 64, 23, 12, '#61C554');
  text('Window Title', titlebar, 'Widget', 0, 14, 15,
       COLORS.text, 'semibold', 1554, 'CENTER');
  text('Subtitle', titlebar, 'Widget result  ·  Image', 0, 38, 11,
       COLORS.muted, 'regular', 1554, 'CENTER');
  const body = frame('03 / Widget Canvas', 0, 58, 1554, 954, '#0C0D11');
  root.appendChild(body);

  // The source frame intentionally clips the top of the stage and the bottom
  // of the image. These coordinates match the user's edited Figma layout.
  const stage = panel(body, '06 / Generated Image Stage', 32, -47, 1522, 868,
                      COLORS.canvas, 9);
  const preview = rect('Generated Image Preview', stage, 208, 52, 1073, 942,
                       null, 8, COLORS.line);
  if (imageHash) {
    preview.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FIT' }];
  } else {
    artworkFill(preview, ['#2C3440', '#B27D61', '#2C4136']);
  }
  text('OSS Result Label', stage, 'OSS RESULT',
       20, 58, 12, COLORS.accent, 'semibold');

  const copy = frame('Copy Result URL Action', 1350, 56, 148, 34,
                     COLORS.raised, 8);
  copy.strokes = [fill(COLORS.accent, .72)];
  copy.strokeWeight = 1;
  stage.appendChild(copy);
  const copyIcon = figma.createNodeFromSvg(ICONS.copy.replaceAll('CURRENT', COLORS.accent));
  copyIcon.name = 'Copy URL Icon';
  copyIcon.resize(16, 16);
  copyIcon.x = 14;
  copyIcon.y = 9;
  copy.appendChild(copyIcon);
  text('Copy Result URL Label', copy, 'Copy URL',
       36, 9, 12, COLORS.accent, 'semibold', 100, 'CENTER');

  const strip = frame('07 / Original and Result Filmstrip', 669, 831, 216, 106,
                      null, 0);
  strip.fills = [];
  body.appendChild(strip);
  const original = frame('Original Thumbnail', 0, 0, 96, 96,
                         COLORS.surface, 8);
  original.strokes = [fill(COLORS.line)];
  original.strokeWeight = 1;
  strip.appendChild(original);
  simpleWidgetArt(original, 'Original Image', 4, 4, 88, 88, null,
                  ['#25323A', '#A47761', '#293B33']);
  const originalLabel = frame('Original Label Background', 4, 69, 88, 23,
                              '#101115', 5);
  original.appendChild(originalLabel);
  text('Original Label', originalLabel, 'ORIGINAL',
       0, 6, 10, COLORS.text, 'semibold', 88, 'CENTER');

  const result = frame('Generated Result Thumbnail / selected', 120, 0, 96, 96,
                       COLORS.surface, 8);
  result.strokes = [fill(COLORS.accent)];
  result.strokeWeight = 2;
  strip.appendChild(result);
  simpleWidgetArt(result, 'Result Image', 4, 4, 88, 88, imageHash,
                  ['#2C3440', '#B27D61', '#2C4136']);
  const resultLabel = frame('Result Label Background', 4, 69, 88, 23,
                            '#30231F', 5);
  result.appendChild(resultLabel);
  text('Result Label', resultLabel, 'RESULT · OSS',
       0, 6, 10, COLORS.accent, 'semibold', 88, 'CENTER');
  return screen;
}

function refineWidgetOSSResultControls(screen) {
  const stage = screen.findOne(node => node.name === '06 / Generated Image Stage');
  if (!stage) throw new Error('OSS result page has no generated image stage');
  let copy = stage.findOne(node => node.name === 'Copy Result URL Action');
  const existingLabel = stage.findOne(node => node.name === 'OSS Result Label');
  const copyText = copy && copy.findOne(node => node.name === 'Copy Result URL Label');
  if (existingLabel && copy && copy.width === 148 && copy.height === 34 && copyText) {
    return false;
  }

  const oldBadge = stage.findOne(node => node.name === 'Preview Result Badge');
  if (oldBadge) oldBadge.remove();
  if (!existingLabel) {
    text('OSS Result Label', stage, 'OSS RESULT',
         20, 58, 12, COLORS.accent, 'semibold');
  }

  if (!copy) {
    copy = frame('Copy Result URL Action', 1350, 56, 148, 34,
                 COLORS.raised, 8);
    stage.appendChild(copy);
  }
  copy.x = 1350;
  copy.y = 56;
  copy.resize(148, 34);
  copy.cornerRadius = 8;
  copy.fills = [fill(COLORS.raised)];
  copy.strokes = [fill(COLORS.accent, .72)];
  copy.strokeWeight = 1;
  for (const oldText of stage.findAll(node => node.name === 'Copy Result URL Label')) {
    oldText.remove();
  }
  for (const oldIcon of copy.findAll(node => node.name === 'Copy URL Icon')) {
    oldIcon.remove();
  }
  const copyIcon = figma.createNodeFromSvg(ICONS.copy.replaceAll('CURRENT', COLORS.accent));
  copyIcon.name = 'Copy URL Icon';
  copyIcon.resize(16, 16);
  copyIcon.x = 14;
  copyIcon.y = 9;
  copy.appendChild(copyIcon);
  text('Copy Result URL Label', copy, 'Copy URL',
       36, 9, 12, COLORS.accent, 'semibold', 100, 'CENTER');
  return true;
}

async function generateWidgetOSSResult(bytes) {
  await loadFonts();
  await createStyles();
  const page = figma.currentPage;
  const existing = page.children.find(child => child.name === WIDGET_OSS_RESULT_NAME);
  if (existing) {
    const updated = refineWidgetOSSResultControls(existing);
    page.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: updated
      ? 'Updated OSS result label and compact Copy URL button. Thumbnails left unchanged.'
      : 'Refined OSS result page already exists. Showing it without changing edits.' });
    return;
  }
  let maxX = 0;
  for (const child of page.children) maxX = Math.max(maxX, child.x + child.width);
  const source = page.children.find(child => child.name === WIDGET_OSS_RESULT_SOURCE_NAME);
  let screen;
  if (source) {
    screen = source.clone();
    screen.name = WIDGET_OSS_RESULT_NAME;
    screen.x = maxX + 196;
    screen.y = source.y;
    refineWidgetOSSResultControls(screen);
  } else {
    const imageHash = bytes && bytes.length
      ? figma.createImage(new Uint8Array(bytes)).hash : null;
    screen = createWidgetOSSResultPage(maxX + 196, imageHash);
  }
  page.selection = [screen];
  figma.viewport.scrollAndZoomIntoView([screen]);
  figma.ui.postMessage({ message: source
    ? 'Created refined OSS result page from your edited Figma frame; thumbnails preserved.'
    : 'Created refined OSS result page.' });
  figma.notify('Refined Widget OSS result page created');
}

// A single round icon button used in the Preview-style top chrome bar.
function previewRoundButton(parent, name, iconName, x, y, tint = '#F3F3F3', fillHex = '#2A2B2F') {
  const node = frame(name, x, y, 28, 28, null, 14);
  node.fills = [fill(fillHex, 0.9)];
  node.strokes = [fill('#FFFFFF', 0.1)];
  node.strokeWeight = 1;
  parent.appendChild(node);
  const svg = figma.createNodeFromSvg(ICONS[iconName].replaceAll('CURRENT', tint));
  svg.name = 'Icon / ' + iconName;
  svg.resize(15, 15);
  svg.x = 6.5;
  svg.y = 6.5;
  node.appendChild(svg);
  return node;
}

// A borderless icon slot (no chip), for the flat action icons in the top bar.
function previewFlatIcon(parent, name, iconName, x, y, size = 18, tint = '#C7C7CC') {
  const svg = figma.createNodeFromSvg(ICONS[iconName].replaceAll('CURRENT', tint));
  svg.name = name;
  svg.resize(size, size);
  svg.x = x;
  svg.y = y;
  parent.appendChild(svg);
  return svg;
}

// Preview-style build: a single compact top chrome bar (traffic-adjacent round
// controls on the left, filename in the middle, action icons + "Open with"
// pill on the right), with the image flush to every edge underneath it.
function createPreviewChromeStudyScreen(x, imageHash = null, imageSize = null) {
  const width = imageSize && imageSize.width ? imageSize.width : 654;
  const height = imageSize && imageSize.height ? imageSize.height : 1012;
  const board = frame('Dark Refresh v3 / Image Viewer / Preview Chrome', x, 0, width, height, null, 12);
  board.strokes = [fill('#000000', 0.55)];
  board.strokeWeight = 1;
  if (imageHash) {
    board.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  } else {
    artworkFill(board, ['#C9B39C', '#8C7A66', '#4A4036']);
  }
  figma.currentPage.appendChild(board);

  const barH = 52;
  const bar = frame('01 / Preview Top Bar', 0, 0, width, barH, null, 0);
  bar.fills = [fill('#1B1C1E', 0.94)];
  bar.effects = [{ type: 'BACKGROUND_BLUR', radius: 24, visible: true }];
  board.appendChild(bar);
  // Hairline separating the bar from the image.
  rect('Bar Divider', bar, 0, barH - 1, width, 1, '#000000').opacity = 0.5;

  // Left cluster: close + markup round buttons.
  previewRoundButton(bar, 'Close', 'close', 14, 12, '#F3F3F3', '#3A3B3F');
  previewRoundButton(bar, 'Markup', 'markup', 48, 12, '#F3F3F3', '#2A2B2F');

  // Center-left: info + check status icons, then the filename.
  previewFlatIcon(bar, 'Icon / info', 'info', 92, 17, 18, '#8E8E93');
  previewFlatIcon(bar, 'Icon / check', 'check', 116, 17, 18, '#8E8E93');
  text('Filename', bar, 'input-09672AEE-FC4D-4116-B8F9-20E27300A34F.jpg',
    142, 18, 13, '#F3F3F3', 'semibold');

  // Right cluster (anchored to the right edge): "Open with" pill, share, sidebar.
  const pill = frame('Open with Preview', width - 148, 12, 132, 28, null, 8);
  pill.fills = [fill('#2A2B2F', 0.9)];
  pill.strokes = [fill('#FFFFFF', 0.1)];
  pill.strokeWeight = 1;
  bar.appendChild(pill);
  text('Pill Label', pill, 'Open with Preview', 0, 7, 12, '#F3F3F3', 'medium', 132, 'CENTER');
  previewFlatIcon(bar, 'Icon / share', 'share', width - 182, 17, 18, '#C7C7CC');
  previewFlatIcon(bar, 'Icon / sidebar', 'sidebar', width - 214, 17, 18, '#C7C7CC');

  return board;
}

function createImageInspectChromeStudyScreen(x, imageHash = null) {
  const width = 1554;
  const height = 1012;
  const board = frame('Dark Refresh v3 / Image Inspect / Clean Editable', x, 0, width, height, null, 16);
  board.strokes = [fill(COLORS.line)];
  board.strokeWeight = 1;
  if (imageHash) {
    board.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  } else {
    artworkFill(board, ['#24313B', '#A77B72', '#26352D']);
  }
  figma.currentPage.appendChild(board);

  const imageShade = rect('Image / readability shade', board, 0, 0, width, height, '#07080A', 16);
  imageShade.opacity = .08;
  createBareSystemControls(board);
  createFloatingInspectToolbar(board, width, 'Information');

  const info = frame('04 / Image Information / active preview', width - 412, 112, 372, 684, null, 16);
  info.fills = [fill('#161719', .92)];
  info.strokes = [fill('#FFFFFF', .12)];
  info.strokeWeight = 1;
  info.effects = [
    { type: 'BACKGROUND_BLUR', radius: 22, visible: true },
    {
      type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: .32 },
      offset: { x: 0, y: 12 }, radius: 28, spread: 0, visible: true, blendMode: 'NORMAL'
    }
  ];
  board.appendChild(info);
  text('Heading', info, 'Image information', 24, 24, 17, '#F3F3F3', 'semibold');
  text('Hint', info, 'Visible when Information is selected', 24, 52, 11, '#B8B8BD', 'regular');
  rect('Header Divider', info, 24, 82, 324, 1, '#FFFFFF').opacity = .12;
  metadataRow(info, 'Name', 'alpine-lake.jpg', 112);
  metadataRow(info, 'Dimensions', '3840 × 2560', 158);
  metadataRow(info, 'Format', 'JPEG', 204);
  metadataRow(info, 'File size', '6.8 MB', 250);
  metadataRow(info, 'Color profile', 'sRGB', 296);
  metadataRow(info, 'Created', 'Mar 14, 2024', 342);
  text('Quick Actions', info, 'QUICK ACTIONS', 24, 414, 10, '#B8B8BD', 'semibold');
  const remove = frame('Remove Background', 24, 442, 324, 42, '#1D1E22', 10);
  remove.strokes = [fill('#FFFFFF', .12)]; remove.strokeWeight = 1; info.appendChild(remove);
  text('Label', remove, 'Remove Background', 16, 13, 12, '#F3F3F3', 'medium');
  const upscale = frame('Upscale 2×', 24, 494, 324, 42, '#1D1E22', 10);
  upscale.strokes = [fill('#FFFFFF', .12)]; upscale.strokeWeight = 1; info.appendChild(upscale);
  text('Label', upscale, 'Upscale 2×', 16, 13, 12, '#F3F3F3', 'medium');

  const task = frame('05 / Processing Toast', 40, height - 112, 404, 64, null, 14);
  task.fills = [fill('#161719', .90)];
  task.strokes = [fill('#FFFFFF', .12)]; task.strokeWeight = 1;
  task.effects = [{ type: 'BACKGROUND_BLUR', radius: 18, visible: true }];
  board.appendChild(task);
  ellipse('Status', task, 18, 27, 10, COLORS.accent);
  text('Task', task, 'Remove Background', 44, 15, 13, '#F3F3F3', 'semibold');
  text('Progress', task, 'Processing · 64%', 44, 35, 11, '#B8B8BD', 'regular');
  return board;
}

function filmstripStudyThumbnail(parent, index, x, selected = false) {
  const palettes = [
    ['#24313B', '#A77B72', '#26352D'], ['#342A32', '#8C6671', '#28343B'],
    ['#24382F', '#6F9B7A', '#28302D'], ['#302A26', '#B08565', '#3B3930'],
    ['#27323C', '#7890A4', '#3A4A42'], ['#352C3A', '#966E8B', '#30333E'],
    ['#293128', '#97A66E', '#3B382B']
  ];
  const item = frame('Thumbnail ' + (index + 1), x, 0, 96, 96, COLORS.raised, 9);
  item.strokes = [fill(selected ? COLORS.accent : COLORS.line, selected ? .9 : 1)];
  item.strokeWeight = selected ? 3 : 2;
  parent.appendChild(item);
  artworkFill(rect('Preview', item, selected ? 2 : 3, selected ? 2 : 3,
                   selected ? 92 : 90, selected ? 92 : 90, null, 6), palettes[index]);
  return item;
}

function createImageFilmstripScrollStudyScreen(x) {
  const board = frame('Image Inspect / Filmstrip Scroll / Review', x, 0, 1554, 1012, COLORS.bg, 16);
  board.strokes = [fill(COLORS.line)]; board.strokeWeight = 1;
  figma.currentPage.appendChild(board);
  text('Review Heading', board, 'Image Inspect  /  filmstrip after six images', 40, 38,
       18, COLORS.text, 'semibold');
  text('Review Note', board,
       'Six thumbnails stay at 96 × 96. Additional images scroll horizontally without shrinking.',
       40, 68, 12, COLORS.secondary, 'regular', 900);

  const canvas = frame('01 / Image Canvas', 40, 112, 1474, 650, COLORS.canvas, 12);
  canvas.strokes = [fill(COLORS.line)]; canvas.strokeWeight = 1; board.appendChild(canvas);
  artworkFill(rect('Image / full bleed', canvas, 0, 0, 1474, 650, null, 12),
              ['#24313B', '#A77B72', '#26352D']);
  createFloatingInspectToolbar(canvas, 1474, 'Focus');

  const viewportWidth = 6 * 96 + 5 * 10;
  const viewport = frame('02 / Filmstrip Viewport / six visible',
                         Math.round((1554 - viewportWidth) / 2), 794,
                         viewportWidth, 118, '#111217', 12);
  viewport.strokes = [fill(COLORS.line)]; viewport.strokeWeight = 1;
  board.appendChild(viewport);
  const content = frame('Scrollable Thumbnail Content / seven images', 0, 0,
                        7 * 96 + 6 * 10, 96, null, 0);
  content.fills = []; viewport.appendChild(content);
  for (let i = 0; i < 7; i++) filmstripStudyThumbnail(content, i, i * 106, i === 0);

  const scrollbar = frame('03 / Themed Scrollbar', 0, 104, viewportWidth, 6, null, 3);
  scrollbar.fills = []; viewport.appendChild(scrollbar);
  rect('Scrollbar Track', scrollbar, 0, 1.5, viewportWidth, 3, '#34353A', 1.5);
  const thumbWidth = Math.round(viewportWidth * 6 / 7);
  const thumb = rect('Scrollbar Thumb / warm cue', scrollbar, 0, 1, thumbWidth, 4, COLORS.accent, 2);
  thumb.opacity = .82;

  text('Visible Capacity', board, '6 visible', 40, 938, 11, COLORS.accent, 'semibold');
  text('Scroll Behavior', board, 'Trackpad, mouse wheel, or drag the warm thumb', 132, 938,
       11, COLORS.muted, 'regular');
  return board;
}

async function generateImageFilmstripScrollStudy() {
  await loadFonts();
  await createStyles();
  const name = 'Image Inspect / Filmstrip Scroll / Review';
  const existing = figma.currentPage.children.find(child => child.name === name);
  if (existing) {
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Image Filmstrip Scroll Study already exists.' });
    return;
  }
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const board = createImageFilmstripScrollStudyScreen(maxX + 196);
  figma.currentPage.selection = [board];
  figma.viewport.scrollAndZoomIntoView([board]);
  figma.ui.postMessage({ message: 'Created Image Filmstrip Scroll Study.' });
  figma.notify('Image Filmstrip Scroll Study created');
}

// Resolve the photo to fill a study with. Prefer freshly-uploaded bytes (so the
// user can drop in a real picture), otherwise reuse an IMAGE fill already on one
// of the named source frames. Returns { imageHash, imageSize } or nulls.
async function resolveStudyImage(bytes, sourceNames) {
  if (bytes && bytes.length) {
    const image = figma.createImage(new Uint8Array(bytes));
    let imageSize = null;
    if (image.getSizeAsync) {
      try { imageSize = await image.getSizeAsync(); } catch (e) { imageSize = null; }
    }
    return { imageHash: image.hash, imageSize };
  }
  const source = sourceNames
    .map(sourceName => figma.currentPage.children.find(child => child.name === sourceName))
    .find(Boolean);
  const sourceFill = source && Array.isArray(source.fills)
    ? source.fills.find(paint => paint.type === 'IMAGE')
    : null;
  return {
    imageHash: sourceFill ? sourceFill.imageHash : null,
    imageSize: source ? { width: source.width, height: source.height } : null
  };
}

// Match the Focus/Simple-Operation frame under any of the names it may carry.
// The user renamed it to "fouce Mode" and added their own layers, so we match
// on both spellings and NEVER rebuild children.
const FOCUS_FRAME_NAMES = [
  'Dark Refresh v3 / Image Viewer / fouce Mode',
  'Dark Refresh v3 / Image Viewer / Focus Mode',
  'Dark Refresh v3 / Image Viewer / Simple Operation'
];
const COMPARE_FRAME_NAMES = [
  'Dark Refresh v3 / Image Viewer / Compare Mode'
];

function findFrameByNames(names) {
  return names
    .map(n => figma.currentPage.children.find(child => child.name === n))
    .find(Boolean) || null;
}

// Replace ONLY the color-block fill(s) with a real image, preserving every
// other layer and style the user has edited. Non-destructive: no child is
// removed, moved, or restyled.
async function replaceStudyImages(bytes) {
  await loadFonts();
  await createStyles();

  const focus = findFrameByNames(FOCUS_FRAME_NAMES);
  const compare = findFrameByNames(COMPARE_FRAME_NAMES);
  if (!focus && !compare) {
    figma.ui.postMessage({ message: 'Neither the Focus/fouce Mode nor Compare Mode frame was found on this page.' });
    figma.notify('Nothing to update', { error: true });
    return;
  }

  // Determine the image hash. Prefer uploaded bytes; else reuse whatever image
  // one of the frames already carries so the other can be synced to it.
  let imageHash = null;
  if (bytes && bytes.length) {
    imageHash = figma.createImage(new Uint8Array(bytes)).hash;
  } else {
    const carrier = [focus, compare].filter(Boolean);
    for (const frameNode of carrier) {
      const boardFill = Array.isArray(frameNode.fills)
        ? frameNode.fills.find(p => p.type === 'IMAGE') : null;
      if (boardFill) { imageHash = boardFill.imageHash; break; }
      const paneWithImage = frameNode.findOne(n =>
        Array.isArray(n.fills) && n.fills.some(p => p.type === 'IMAGE'));
      if (paneWithImage) {
        imageHash = paneWithImage.fills.find(p => p.type === 'IMAGE').imageHash;
        break;
      }
    }
  }
  if (!imageHash) {
    figma.ui.postMessage({ message: 'No image provided. Choose a Reference image first, then click again.' });
    figma.notify('Pick a reference image', { error: true });
    return;
  }

  const updated = [];
  // Focus frame: the color block is the board's own fill.
  if (focus) {
    focus.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    updated.push(focus);
  }
  // Compare frame: the color blocks are the A / B panes (fall back to the board
  // fill if the panes aren't present because of user restructuring).
  if (compare) {
    const paneA = compare.findOne(n => n.name === 'Compare / A');
    const paneB = compare.findOne(n => n.name === 'Compare / B');
    if (paneA || paneB) {
      if (paneA) paneA.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
      if (paneB) paneB.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    } else {
      compare.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    }
    updated.push(compare);
  }

  figma.currentPage.selection = updated;
  figma.viewport.scrollAndZoomIntoView(updated);
  figma.ui.postMessage({ message: 'Replaced the color blocks with your image (styles untouched): ' +
    updated.map(f => f.name).join(', ') });
  figma.notify('Image applied to ' + updated.length + ' frame(s)');
}

async function generateViewerChromeStudy(bytes) {
  await loadFonts();
  await createStyles();
  const name = 'Dark Refresh v3 / Image Viewer / Simple Operation';
  const sourceNames = [
    'Dark Refresh v2 / Image Viewer / Simple Operation',
    'Dark Refresh / Image Viewer / Simple Operation',
    'Image Viewer / Simple Operation'
  ];
  const { imageHash, imageSize } = await resolveStudyImage(bytes, sourceNames);

  const existing = findFrameByNames(FOCUS_FRAME_NAMES);
  if (existing) {
    // NON-DESTRUCTIVE: only swap the board's color-block fill. Do not rebuild
    // the toolbar/controls or touch any layer the user added or restyled.
    if (imageHash) {
      existing.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    }
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: imageHash
      ? 'Replaced the color block with your image (' + existing.name + '); styles untouched.'
      : 'Frame already exists — pick a Reference image to replace the color block.' });
    figma.notify('Focus frame updated');
    return;
  }

  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const study = createViewerChromeStudyScreen(maxX + 196, imageHash, imageSize);
  figma.currentPage.selection = [study];
  figma.viewport.scrollAndZoomIntoView([study]);
  figma.ui.postMessage({ message: imageHash
    ? 'Created Simple Operation with your image.'
    : 'Created Viewer Chrome Study with bare macOS window controls.' });
  figma.notify('Viewer Chrome Study created');
}

async function generateCompareChromeStudy(bytes) {
  await loadFonts();
  await createStyles();
  const name = 'Dark Refresh v3 / Image Viewer / Compare Mode';

  // Prefer an uploaded image; else reuse the Simple Operation study's image.
  const sourceNames = [
    'Dark Refresh v3 / Image Viewer / Simple Operation',
    'Dark Refresh v2 / Image Viewer / Simple Operation',
    'Image Viewer / Simple Operation'
  ];
  const { imageHash, imageSize } = await resolveStudyImage(bytes, sourceNames);

  const existing = findFrameByNames(COMPARE_FRAME_NAMES);
  if (existing) {
    // NON-DESTRUCTIVE: only swap the A / B pane color blocks. Never remove or
    // rebuild the frame, so the user's style edits are preserved.
    if (imageHash) {
      const paneA = existing.findOne(n => n.name === 'Compare / A');
      const paneB = existing.findOne(n => n.name === 'Compare / B');
      if (paneA) paneA.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
      if (paneB) paneB.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
      if (!paneA && !paneB) {
        existing.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
      }
    }
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: imageHash
      ? 'Replaced the Compare color blocks with your image; styles untouched.'
      : 'Compare Mode exists — pick a Reference image to replace the color blocks.' });
    figma.notify('Compare Mode updated');
    return;
  }

  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const study = createCompareChromeStudyScreen(maxX + 196, imageHash, imageSize);
  figma.currentPage.selection = [study];
  figma.viewport.scrollAndZoomIntoView([study]);
  figma.ui.postMessage({ message: 'Created Compare Mode study (bordered window, side-by-side).' });
  figma.notify('Compare Mode study created');
}

async function generatePreviewChromeStudy() {
  await loadFonts();
  await createStyles();
  const name = 'Dark Refresh v3 / Image Viewer / Preview Chrome';
  const existing = figma.currentPage.children.find(child => child.name === name);

  // Reuse whatever image the other viewers already carry so the study renders
  // over a real photo at its native aspect ratio.
  const sourceNames = [
    'Dark Refresh v3 / Image Viewer / Simple Operation',
    'Dark Refresh v2 / Image Viewer / Simple Operation',
    'Image Viewer / Simple Operation'
  ];
  const source = sourceNames
    .map(sourceName => figma.currentPage.children.find(child => child.name === sourceName))
    .find(Boolean);
  const sourceFill = source && Array.isArray(source.fills)
    ? source.fills.find(paint => paint.type === 'IMAGE')
    : null;
  const imageHash = sourceFill ? sourceFill.imageHash : null;
  const imageSize = source ? { width: source.width, height: source.height } : null;

  if (existing) {
    // Rebuild the top bar in place so re-running reflects the latest spec.
    for (const child of existing.children.slice()) {
      if (child.name === '01 / Preview Top Bar') child.remove();
    }
    const barH = 52;
    const width = existing.width;
    const bar = frame('01 / Preview Top Bar', 0, 0, width, barH, null, 0);
    bar.fills = [fill('#1B1C1E', 0.94)];
    bar.effects = [{ type: 'BACKGROUND_BLUR', radius: 24, visible: true }];
    existing.appendChild(bar);
    rect('Bar Divider', bar, 0, barH - 1, width, 1, '#000000').opacity = 0.5;
    previewRoundButton(bar, 'Close', 'close', 14, 12, '#F3F3F3', '#3A3B3F');
    previewRoundButton(bar, 'Markup', 'markup', 48, 12, '#F3F3F3', '#2A2B2F');
    previewFlatIcon(bar, 'Icon / info', 'info', 92, 17, 18, '#8E8E93');
    previewFlatIcon(bar, 'Icon / check', 'check', 116, 17, 18, '#8E8E93');
    text('Filename', bar, 'input-09672AEE-FC4D-4116-B8F9-20E27300A34F.jpg',
      142, 18, 13, '#F3F3F3', 'semibold');
    const pill = frame('Open with Preview', width - 148, 12, 132, 28, null, 8);
    pill.fills = [fill('#2A2B2F', 0.9)];
    pill.strokes = [fill('#FFFFFF', 0.1)]; pill.strokeWeight = 1;
    bar.appendChild(pill);
    text('Pill Label', pill, 'Open with Preview', 0, 7, 12, '#F3F3F3', 'medium', 132, 'CENTER');
    previewFlatIcon(bar, 'Icon / share', 'share', width - 182, 17, 18, '#C7C7CC');
    previewFlatIcon(bar, 'Icon / sidebar', 'sidebar', width - 214, 17, 18, '#C7C7CC');
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Refreshed the Preview Chrome top bar.' });
    figma.notify('Preview Chrome refreshed');
    return;
  }

  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const study = createPreviewChromeStudyScreen(maxX + 196, imageHash, imageSize);
  figma.currentPage.selection = [study];
  figma.viewport.scrollAndZoomIntoView([study]);
  figma.ui.postMessage({ message: 'Created Preview Chrome study (macOS Preview-style top bar, tight padding).' });
  figma.notify('Preview Chrome study created');
}

async function generateImageInspectChromeStudy() {
  await loadFonts();
  await createStyles();
  const name = 'Dark Refresh v3 / Image Inspect / Clean Editable';
  const existing = figma.currentPage.children.find(child => child.name === name);
  if (existing) {
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Image Inspect Chrome Study already exists — nothing changed.' });
    return;
  }
  const sources = [
    'Dark Refresh v3 / Image Viewer / Simple Operation',
    'Dark Refresh v2 / Image Viewer / Simple Operation',
    'Image Viewer / Simple Operation'
  ];
  const source = sources.map(sourceName => figma.currentPage.children.find(child => child.name === sourceName)).find(Boolean);
  const imageFill = source && Array.isArray(source.fills)
    ? source.fills.find(paint => paint.type === 'IMAGE')
    : null;
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const study = createImageInspectChromeStudyScreen(maxX + 196, imageFill ? imageFill.imageHash : null);
  figma.currentPage.selection = [study];
  figma.viewport.scrollAndZoomIntoView([study]);
  figma.ui.postMessage({ message: 'Created v3 Image Inspect with bare window controls and floating information.' });
  figma.notify('Image Inspect Chrome Study created');
}

function applyDarkRefreshTreatment(screen, sourceName) {
  screen.name = 'Dark Refresh v2 / ' + sourceName;
  const chromeNodes = screen.findAll(node =>
    node.type === 'FRAME' && (
      node.name.includes('Toolbar') ||
      node.name === 'Titlebar' ||
      node.name.includes('Titlebar') ||
      node.name === '04 / Actions'
    )
  );
  for (const node of chromeNodes) {
    node.fills = [fill('#161719', .94)];
    node.strokes = [fill('#FFFFFF', .10)];
    node.strokeWeight = 1;
  }
  return screen;
}

async function generateDarkRefreshScreens(bytes) {
  await loadFonts();
  await createStyles();
  const specs = [
    ['Image Viewer / Simple Operation', null],
    ['Video Inspect', createSimpleVideoViewerScreen],
    ['Task Center', createTaskCenterScreen],
    ['Widget Market / Install', createWidgetMarketScreen],
    ['Quick Preview', createQuickPreviewScreen],
    ['Home / Launcher', createHomeScreen],
    ['Content Viewer', createContentViewerScreen],
    ['Widget Web / States', createWidgetWebScreen],
    ['Base64 Toolkit', createBase64Screen],
    ['Preview History', createHistoryScreen],
    ['Preferences', createPreferencesScreen],
    ['Onboarding / Permissions', createOnboardingScreen],
    ['Tray Popover', createTrayPopoverScreen]
  ];
  const existing = new Map(figma.currentPage.children.map(child => [child.name, child]));
  const alreadyGenerated = specs
    .map(([name]) => existing.get('Dark Refresh v2 / ' + name))
    .filter(Boolean);
  if (alreadyGenerated.length === specs.length) {
    figma.currentPage.selection = alreadyGenerated;
    figma.viewport.scrollAndZoomIntoView(alreadyGenerated);
    figma.ui.postMessage({ message: 'All 13 Dark Refresh screens already exist — nothing changed.' });
    return;
  }

  const image = bytes && bytes.length ? figma.createImage(new Uint8Array(bytes)) : null;
  const imageSize = image ? await image.getSizeAsync() : null;
  let maxY = 0;
  for (const child of figma.currentPage.children) maxY = Math.max(maxY, child.y + child.height);
  const startY = maxY + 240;
  const startX = 0;
  const columnWidth = 1750;
  const rowHeight = 1250;
  const created = [];
  const selected = [];

  specs.forEach(([sourceName, create], index) => {
    const targetName = 'Dark Refresh v2 / ' + sourceName;
    const prior = existing.get(targetName);
    if (prior) {
      selected.push(prior);
      return;
    }
    const x = startX + (index % 4) * columnWidth;
    const y = startY + Math.floor(index / 4) * rowHeight;
    const screen = create
      ? create(x)
      : createSimpleImageViewerScreen(x, image ? image.hash : null, imageSize);
    screen.y = y;
    applyDarkRefreshTreatment(screen, sourceName);
    created.push(screen);
    selected.push(screen);
  });

  figma.currentPage.selection = selected;
  figma.viewport.scrollAndZoomIntoView(selected);
  figma.ui.postMessage({ message: `Created ${created.length} Dark Refresh screens; ${13 - created.length} already existed.` });
  figma.notify(`${created.length} Dark Refresh screens created`);
}

async function generateSimpleImageViewer(bytes) {
  await loadFonts();
  await createStyles();
  const name = 'Image Viewer / Simple Operation';
  const existing = figma.currentPage.children.find(child => child.name === name);
  if (existing) {
    if (bytes && bytes.length && 'fills' in existing) {
      const image = figma.createImage(new Uint8Array(bytes));
      const imageSize = await image.getSizeAsync();
      existing.resize(imageSize.width, imageSize.height);
      existing.fills = [{ type: 'IMAGE', imageHash: image.hash, scaleMode: 'FILL' }];
      const toolbar = existing.findOne(child => child.name === '01 / Floating Toolbar');
      if (toolbar) toolbar.x = Math.round((imageSize.width - toolbar.width) / 2);
      figma.currentPage.selection = [existing];
      figma.viewport.scrollAndZoomIntoView([existing]);
      figma.ui.postMessage({ message: 'Updated the Simple Image Viewer image without replacing its layers.' });
      return;
    }
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Simple Image Viewer already exists — nothing changed.' });
    return;
  }
  const image = bytes && bytes.length
    ? figma.createImage(new Uint8Array(bytes))
    : null;
  const imageSize = image ? await image.getSizeAsync() : null;
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const viewer = createSimpleImageViewerScreen(maxX + 196, image ? image.hash : null, imageSize);
  figma.currentPage.selection = [viewer];
  figma.viewport.scrollAndZoomIntoView([viewer]);
  figma.ui.postMessage({
    message: image
      ? 'Created Simple Image Viewer with the selected image.'
      : 'Created Simple Image Viewer with the built-in preview artwork.'
  });
  figma.notify('Simple Image Viewer created');
}

function metadataRow(parent, key, value, y) {
  text('Key / ' + key, parent, key, 36, y, 13, COLORS.muted, 'medium');
  text('Value / ' + key, parent, value, 174, y, 13, COLORS.text, 'regular', 220, 'LEFT');
  rect('Divider', parent, 36, y + 30, 362, 1, COLORS.line);
}

function thumbnail(parent, name, x, selected = false, tag = null) {
  const item = frame(name, x, 96, 96, 96, COLORS.raised, 9);
  item.strokes = [fill(selected ? COLORS.accent : COLORS.line)];
  item.strokeWeight = selected ? 2 : 1;
  parent.appendChild(item);
  const art = rect('Preview', item, 5, 5, 86, 86, '#30383F', 6);
  art.fills = [{
    type: 'GRADIENT_LINEAR',
    gradientTransform: [[0.72, 0.28, 0], [-0.28, 0.72, 0.28]],
    gradientStops: [
      { position: 0, color: { ...rgb('#24313B'), a: 1 } },
      { position: .52, color: { ...rgb('#8A5F4E'), a: 1 } },
      { position: 1, color: { ...rgb('#26352D'), a: 1 } }
    ]
  }];
  if (tag) {
    rect('Tag', item, 50, 68, 40, 20, '#102018', 5);
    text('Tag Label', item, tag, 51, 71, 9, COLORS.success, 'semibold', 38, 'CENTER');
  }
  return item;
}

async function loadFonts() {
  try {
    const candidates = [
      { regular: { family: 'Inter', style: 'Regular' }, medium: { family: 'Inter', style: 'Medium' }, semibold: { family: 'Inter', style: 'Semi Bold' } },
      { regular: { family: 'SF Pro Text', style: 'Regular' }, medium: { family: 'SF Pro Text', style: 'Medium' }, semibold: { family: 'SF Pro Text', style: 'Semibold' } }
    ];
    for (const candidate of candidates) {
      try {
        await Promise.all([figma.loadFontAsync(candidate.regular), figma.loadFontAsync(candidate.medium), figma.loadFontAsync(candidate.semibold)]);
        fontRegular = candidate.regular;
        fontMedium = candidate.medium;
        fontSemibold = candidate.semibold;
        return;
      } catch (_) {}
    }
  } catch (_) {}
}

async function createStyles() {
  const styles = [
    ['Glance/Color/Canvas', COLORS.canvas],
    ['Glance/Color/Chrome', COLORS.chrome],
    ['Glance/Color/Surface', COLORS.surface],
    ['Glance/Color/Accent', COLORS.accent],
    ['Glance/Color/Text Primary', COLORS.text],
    ['Glance/Color/Text Secondary', COLORS.secondary]
  ];
  const existingStyles = await figma.getLocalPaintStylesAsync();
  for (const [name, color] of styles) {
    const existing = existingStyles.find(s => s.name === name);
    const style = existing || figma.createPaintStyle();
    style.name = name;
    style.paints = [fill(color)];
  }
}

function createScreen(name, x, imageHash = null, pixelMatch = false) {
  const screen = frame(name, x, 0, 1554, 1012, COLORS.bg, 16);
  screen.strokes = [fill(COLORS.line)];
  screen.strokeWeight = 1;
  figma.currentPage.appendChild(screen);

  if (imageHash && pixelMatch) {
    const base = rect('Pixel Reference / Base', screen, 0, 0, 1554, 1012, null, 16);
    base.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FIT' }];
    base.locked = true;
  }

  const editableRoot = frame('Editable Overlay / toggle visibility', 0, 0, 1554, 1012, null, 0);
  editableRoot.fills = [];
  editableRoot.visible = !pixelMatch;
  screen.appendChild(editableRoot);

  const titlebar = frame('01 / Titlebar', 0, 0, 1554, 58, COLORS.chrome);
  editableRoot.appendChild(titlebar);
  ellipse('Close', titlebar, 24, 23, 12, '#ED6A5E');
  ellipse('Minimize', titlebar, 44, 23, 12, '#F4BF4F');
  ellipse('Zoom', titlebar, 64, 23, 12, '#61C554');
  text('Window Title', titlebar, 'Image Inspect', 0, 14, 15, COLORS.text, 'semibold', 1554, 'CENTER');
  text('Filename', titlebar, 'alpine-lake.jpg', 0, 38, 11, COLORS.muted, 'regular', 1554, 'CENTER');

  const toolbar = frame('02 / Toolbar', 0, 58, 1554, 70, COLORS.raised);
  toolbar.strokes = [fill(COLORS.line)];
  toolbar.strokeWeight = 1;
  editableRoot.appendChild(toolbar);
  button(toolbar, 'Back', '‹', 24, 14, 54);
  button(toolbar, 'Rotate', 'Rotate', 172, 14, 88);
  button(toolbar, 'Flip', 'A  Flip ▾', 286, 14, 128);
  button(toolbar, 'Focus', 'Focus', 578, 14, 96, true);
  button(toolbar, 'Compare', 'Compare', 682, 14, 112);
  button(toolbar, 'Slider', 'Slider', 802, 14, 94);
  button(toolbar, 'Zoom Out', '−', 964, 14, 52);
  text('Zoom Value', toolbar, '100%', 1018, 24, 12, COLORS.secondary, 'medium', 76, 'CENTER');
  button(toolbar, 'Zoom In', '+', 1092, 14, 52);
  button(toolbar, 'Fit', 'Fit', 1152, 14, 76);
  button(toolbar, 'Tasks', '•  Tasks', 1278, 14, 112);
  button(toolbar, 'Widget', 'Widget', 1400, 14, 126);

  const canvas = frame('03 / Canvas', 0, 128, 1120, 808, COLORS.canvas);
  editableRoot.appendChild(canvas);
  const artwork = rect('Image / alpine-lake.jpg', canvas, 16, 0, 1088, 792, '#25313A', 4, COLORS.line);
  artwork.fills = [{
    type: 'GRADIENT_LINEAR',
    gradientTransform: [[0.77, 0.26, 0], [-0.26, 0.77, 0.25]],
    gradientStops: [
      { position: 0, color: { ...rgb('#16212C'), a: 1 } },
      { position: .45, color: { ...rgb('#8A6354'), a: 1 } },
      { position: 1, color: { ...rgb('#20362D'), a: 1 } }
    ]
  }];
  const imageShade = rect('Image Shade', canvas, 16, 526, 1088, 266, '#07080A', 0);
  imageShade.opacity = .34;

  const inspector = frame('04 / Inspector', 1120, 128, 434, 808, COLORS.surface);
  inspector.strokes = [fill(COLORS.line)];
  inspector.strokeWeight = 1;
  editableRoot.appendChild(inspector);
  text('Inspector Title', inspector, 'Image Information', 36, 24, 17, COLORS.text, 'semibold');
  metadataRow(inspector, 'Name', 'alpine-lake.jpg', 84);
  metadataRow(inspector, 'Dimensions', '3840 × 2560', 122);
  metadataRow(inspector, 'Format', 'JPEG', 160);
  metadataRow(inspector, 'File size', '6.8 MB', 198);
  metadataRow(inspector, 'Color profile', 'sRGB IEC61966-2.1', 236);
  metadataRow(inspector, 'Alpha', 'No', 274);
  metadataRow(inspector, 'Created', 'Mar 14, 2024 at 9:41 AM', 312);
  text('Quick Actions Title', inspector, 'QUICK ACTIONS', 36, 386, 11, COLORS.muted, 'semibold');
  button(inspector, 'Remove Background', 'Remove Background', 36, 424, 362);
  button(inspector, 'Upscale 2x', 'Upscale 2x', 36, 488, 362);
  const add = frame('Add Image', 282, 650, 112, 112, COLORS.raised, 9);
  add.strokes = [fill(COLORS.line)]; add.strokeWeight = 1; inspector.appendChild(add);
  text('Plus', add, '+', 0, 20, 34, COLORS.text, 'regular', 112, 'CENTER');
  text('Add Label', add, 'Add', 0, 70, 12, COLORS.secondary, 'medium', 112, 'CENTER');

  const overlay = frame('05 / Task and Filmstrip Overlay', 16, 526, 1088, 266, null, 0);
  overlay.fills = [];
  canvas.appendChild(overlay);
  text('Task Summary', overlay, 'Remove Background  •  Processing', 58, 14, 13, COLORS.text, 'medium');
  ellipse('Task Status', overlay, 26, 17, 10, COLORS.accent);
  const taskCard = frame('Processing Toast', 314, 150, 460, 76, '#1B1D20', 12);
  taskCard.strokes = [fill(COLORS.accent)]; taskCard.strokeWeight = 1; overlay.appendChild(taskCard);
  ellipse('Spinner', taskCard, 20, 22, 30, COLORS.accentSoft);
  text('Processing Title', taskCard, 'Processing...', 66, 18, 14, COLORS.text, 'semibold');
  text('Processing Subtitle', taskCard, 'The source image remains available while the task runs.', 66, 42, 11, COLORS.secondary);
  const source = thumbnail(overlay, 'Source Thumbnail', 54, true);
  source.y = 40;
  const result = thumbnail(overlay, 'Result Thumbnail', 160, false, 'NEW');
  result.y = 40;
  const third = thumbnail(overlay, 'Thumbnail 3', 266);
  third.y = 40;

  const status = frame('06 / Statusbar', 0, 936, 1554, 76, '#1A1B20');
  status.strokes = [fill(COLORS.line)]; status.strokeWeight = 1; editableRoot.appendChild(status);
  text('File Summary', status, '3840 × 2560  •  JPEG  •  6.8 MB', 36, 27, 12, COLORS.secondary);
  text('Interaction Hint', status, 'Scroll to zoom  •  Drag to pan', 0, 27, 12, COLORS.secondary, 'regular', 1554, 'CENTER');
  ellipse('Running Dot', status, 1394, 31, 8, COLORS.accent);
  text('Task Count', status, '1 task running', 1414, 27, 12, COLORS.accent, 'medium');

  if (imageHash) {
    const calibration = rect('Calibration Overlay / toggle visibility', screen, 0, 0, 1554, 1012, null, 16);
    calibration.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FIT' }];
    calibration.opacity = .35;
    calibration.visible = false;
    calibration.locked = true;
  }

  return screen;
}

async function createReference(bytes) {
  if (!bytes || !bytes.length) return null;
  const image = figma.createImage(new Uint8Array(bytes));
  const reference = frame('Reference / image-inspect-ui.png', 0, 0, 1554, 1012, COLORS.bg, 16);
  reference.fills = [{ type: 'IMAGE', imageHash: image.hash, scaleMode: 'FIT' }];
  reference.locked = true;
  figma.currentPage.appendChild(reference);
  return { reference, imageHash: image.hash };
}

async function generate(bytes) {
  await loadFonts();
  await createStyles();
  figma.currentPage.name = 'Glance Production UI';
  const referenceResult = await createReference(bytes);
  const imageHash = referenceResult ? referenceResult.imageHash : null;
  const pixelMatch = createScreen('Image Inspect / Pixel Match', referenceResult ? 1750 : 0, imageHash, true);
  const clean = createScreen('Image Inspect / Clean Editable', referenceResult ? 3500 : 1750, imageHash, false);
  figma.currentPage.selection = [clean];
  figma.viewport.scrollAndZoomIntoView(referenceResult ? [referenceResult.reference, pixelMatch, clean] : [pixelMatch, clean]);
  figma.ui.postMessage({ message: 'Created Pixel Match and Clean Editable designs.' });
  figma.notify('Glance Image Inspect created');
}

function cleanName(value) {
  const result = value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return result || 'figma-frame';
}

function serializablePaint(paint) {
  if (!paint || paint === figma.mixed) return null;
  const result = { type: paint.type, visible: paint.visible !== false, opacity: paint.opacity == null ? 1 : paint.opacity };
  if ('color' in paint && paint.color) result.color = paint.color;
  if ('blendMode' in paint) result.blendMode = paint.blendMode;
  if (paint.type === 'GRADIENT_LINEAR' || paint.type === 'GRADIENT_RADIAL' || paint.type === 'GRADIENT_ANGULAR' || paint.type === 'GRADIENT_DIAMOND') {
    result.gradientStops = paint.gradientStops;
    result.gradientTransform = paint.gradientTransform;
  }
  if (paint.type === 'IMAGE') {
    result.imageHash = paint.imageHash;
    result.scaleMode = paint.scaleMode;
    result.imageTransform = paint.imageTransform;
    result.scalingFactor = paint.scalingFactor;
    result.rotation = paint.rotation;
    result.filters = paint.filters;
  }
  return result;
}

function serializableEffect(effect) {
  if (!effect) return null;
  const result = { type: effect.type, visible: effect.visible !== false, radius: effect.radius };
  if ('color' in effect) result.color = effect.color;
  if ('offset' in effect) result.offset = effect.offset;
  if ('spread' in effect) result.spread = effect.spread;
  if ('blendMode' in effect) result.blendMode = effect.blendMode;
  if ('showShadowBehindNode' in effect) result.showShadowBehindNode = effect.showShadowBehindNode;
  return result;
}

function mixedValue(value) {
  return value === figma.mixed ? 'MIXED' : value;
}

function serializeNode(node, rootX, rootY) {
  const absolute = node.absoluteBoundingBox || { x: node.x || 0, y: node.y || 0, width: node.width || 0, height: node.height || 0 };
  const data = {
    id: node.id,
    name: node.name,
    type: node.type,
    visible: node.visible,
    locked: node.locked,
    opacity: 'opacity' in node ? node.opacity : 1,
    blendMode: 'blendMode' in node ? node.blendMode : null,
    x: 'x' in node ? node.x : 0,
    y: 'y' in node ? node.y : 0,
    absoluteX: absolute.x - rootX,
    absoluteY: absolute.y - rootY,
    width: 'width' in node ? node.width : 0,
    height: 'height' in node ? node.height : 0,
    rotation: 'rotation' in node ? node.rotation : 0
  };

  if ('fills' in node) data.fills = mixedValue(node.fills) === 'MIXED' ? 'MIXED' : node.fills.map(serializablePaint).filter(Boolean);
  if ('strokes' in node) data.strokes = mixedValue(node.strokes) === 'MIXED' ? 'MIXED' : node.strokes.map(serializablePaint).filter(Boolean);
  if ('strokeWeight' in node) data.strokeWeight = mixedValue(node.strokeWeight);
  if ('strokeAlign' in node) data.strokeAlign = node.strokeAlign;
  if ('dashPattern' in node) data.dashPattern = node.dashPattern;
  if ('cornerRadius' in node) data.cornerRadius = mixedValue(node.cornerRadius);
  if ('topLeftRadius' in node) {
    data.cornerRadii = [node.topLeftRadius, node.topRightRadius, node.bottomRightRadius, node.bottomLeftRadius].map(mixedValue);
  }
  if ('effects' in node) data.effects = node.effects.map(serializableEffect).filter(Boolean);
  if ('clipsContent' in node) data.clipsContent = node.clipsContent;
  if ('constraints' in node) data.constraints = node.constraints;
  if ('layoutMode' in node) {
    data.autoLayout = {
      layoutMode: node.layoutMode,
      primaryAxisSizingMode: node.primaryAxisSizingMode,
      counterAxisSizingMode: node.counterAxisSizingMode,
      primaryAxisAlignItems: node.primaryAxisAlignItems,
      counterAxisAlignItems: node.counterAxisAlignItems,
      itemSpacing: node.itemSpacing,
      counterAxisSpacing: node.counterAxisSpacing,
      paddingTop: node.paddingTop,
      paddingRight: node.paddingRight,
      paddingBottom: node.paddingBottom,
      paddingLeft: node.paddingLeft,
      layoutWrap: node.layoutWrap
    };
  }
  if (node.type === 'TEXT') {
    data.text = {
      characters: node.characters,
      fontName: mixedValue(node.fontName),
      fontSize: mixedValue(node.fontSize),
      lineHeight: mixedValue(node.lineHeight),
      letterSpacing: mixedValue(node.letterSpacing),
      textAlignHorizontal: node.textAlignHorizontal,
      textAlignVertical: node.textAlignVertical,
      textAutoResize: node.textAutoResize,
      textCase: mixedValue(node.textCase),
      textDecoration: mixedValue(node.textDecoration)
    };
  }
  if ('componentProperties' in node && node.componentProperties) data.componentProperties = node.componentProperties;
  if ('children' in node) data.children = node.children.map(child => serializeNode(child, rootX, rootY));
  return data;
}

async function exportSelection() {
  const selection = figma.currentPage.selection;
  if (selection.length !== 1 || !('exportAsync' in selection[0])) {
    figma.ui.postMessage({ message: 'Select exactly one frame before exporting.' });
    figma.notify('Select exactly one frame', { error: true });
    return;
  }
  const root = selection[0];
  const bounds = root.absoluteBoundingBox || { x: root.x, y: root.y };
  const document = {
    schemaVersion: 1,
    exportedAt: new Date().toISOString(),
    source: 'Glance UI Builder',
    frame: serializeNode(root, bounds.x, bounds.y)
  };
  const png = await root.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 1 } });
  figma.ui.postMessage({
    type: 'export-ready',
    basename: cleanName(root.name),
    json: JSON.stringify(document, null, 2),
    png: Array.from(png)
  });
  figma.notify('Selected frame exported');
}

async function generateResultBadgeStudy() {
  await loadFonts();
  const studyName = 'Widget Result Badge Study';
  const existing = figma.currentPage.children.find(child => child.name === studyName);
  if (existing) existing.remove();

  const board = frame(studyName, 0, 0, 760, 440, COLORS.bg, 16);
  board.strokes = [fill(COLORS.line)];
  board.strokeWeight = 1;
  figma.currentPage.appendChild(board);

  text('Title', board, 'Widget Result Badge Study', 40, 32, 24, COLORS.text, 'semibold');
  text('Subtitle', board, 'Mint result marker at actual filmstrip size',
       40, 68, 13, COLORS.secondary, 'regular');

  const panel = frame('Image Inspect / Filmstrip Context', 40, 112, 680, 278,
                      COLORS.chrome, 12);
  panel.strokes = [fill(COLORS.line)];
  panel.strokeWeight = 1;
  board.appendChild(panel);
  text('Context Title', panel, 'WIDGET OUTPUT', 24, 22, 11,
       COLORS.secondary, 'semibold');
  text('Size Note', panel, '96 × 96 filmstrip thumbnails', 24, 45, 11,
       COLORS.muted, 'regular');

  function addThumbnail(name, x, y, size, isResult) {
    const scale = size / 96;
    const thumb = frame(name, x, y, size, size, COLORS.surface, 9 * scale);
    thumb.strokes = [fill(COLORS.line)];
    thumb.strokeWeight = scale;
    panel.appendChild(thumb);

    const image = rect('Image / no baked-in label', thumb,
                       3 * scale, 3 * scale, 90 * scale, 90 * scale,
                       null, 6 * scale);
    artworkFill(image, ['#2C3440', '#B27D61', '#2C4136']);

    if (isResult) {
      const badge = frame('NEW Corner Badge / separate layer',
                          48 * scale, 0, 48 * scale, 22 * scale,
                          COLORS.success, 4 * scale);
      thumb.appendChild(badge);
      text('NEW Label', badge, 'NEW', 0, 5 * scale, 10 * scale,
           '#21130D', 'semibold', 48 * scale, 'CENTER');
    }
    return thumb;
  }

  addThumbnail('Original Thumbnail / 96', 24, 88, 96, false);
  addThumbnail('Widget Result Thumbnail / 96', 166, 88, 96, true);
  addThumbnail('Widget Result Thumbnail / 2x detail', 404, 55, 192, true);
  text('Original Caption', panel, 'ORIGINAL', 24, 196, 10,
       COLORS.muted, 'semibold', 96, 'CENTER');
  text('Result Caption', panel, 'WIDGET RESULT', 166, 196, 10,
       COLORS.success, 'semibold', 96, 'CENTER');
  rect('Detail Divider', panel, 338, 69, 1, 170, COLORS.line);
  text('Detail Caption', panel, '2× DETAIL', 404, 254, 10,
       COLORS.muted, 'semibold', 192, 'CENTER');

  figma.viewport.scrollAndZoomIntoView([board]);
  figma.ui.postMessage({ message: 'Created Widget Result Badge Study' });
  figma.notify('Widget Result Badge Study created');
}

const WIDGET_TASK_RUNNING_FOCUSED = 'Image Inspect / Widget Task Running / Focused Source';
const WIDGET_TASK_RUNNING_BROWSING = 'Image Inspect / Widget Task Running / Browsing Another Image';
const WIDGET_TEXT_RESULT_MAIN = 'Image Inspect / Widget Text Result / Main Image';
const WIDGET_TEXT_RESULT_WINDOW = 'Widget Output / Text / Side Window';

function widgetTaskRunningThumbnail(strip, name, x, imageHash, active, selected, colors) {
  const size = 96 * .8 * .8; // ImageInspectWindow.layoutContent's shared tile size.
  const tile = frame(name, x, 0, size, size, COLORS.raised, 9 * size / 96);
  tile.strokes = [fill(COLORS.accent, active ? .85 : selected ? 1 : .24)];
  tile.strokeWeight = active || selected ? 2 : 1;
  if (active) {
    tile.effects = [{
      type: 'DROP_SHADOW', color: { ...rgb(COLORS.accent), a: .32 },
      offset: { x: 0, y: 0 }, radius: 10, spread: 0,
      visible: true, blendMode: 'NORMAL'
    }];
  }
  strip.appendChild(tile);
  const preview = rect('Image / no status text', tile, 3, 3, size - 6, size - 6, null, 5);
  if (imageHash) preview.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  else artworkFill(preview, colors);
  return tile;
}

function addWidgetTaskRunningFilmstrip(board, imageHash) {
  const barHeight = 117 * .8;
  const bar = frame('Filmstrip Scrim / existing geometry', 8,
                    board.height - 12 - barHeight, board.width - 16, barHeight, null);
  bar.fills = [fill('#07080A', .34)];
  board.appendChild(bar);
  const tile = 96 * .8 * .8;
  const gap = 8;
  const stripWidth = 3 * tile + 2 * gap;
  const strip = frame('Filmstrip / existing 61.44px thumbnails',
                      (board.width - stripWidth) / 2,
                      bar.y + (barHeight - tile) / 2,
                      stripWidth, tile, null);
  strip.fills = [];
  board.appendChild(strip);
  widgetTaskRunningThumbnail(strip, 'Source / task breathing', 0,
                             imageHash, true, false,
                             ['#24313B', '#A77B72', '#26352D']);
  widgetTaskRunningThumbnail(strip, 'Other image / selected', tile + gap,
                             null, false, true,
                             ['#2F3747', '#9F8C78', '#35444B']);
  widgetTaskRunningThumbnail(strip, 'Other image / idle', 2 * (tile + gap),
                             null, false, false,
                             ['#33372C', '#918167', '#273D36']);
}

function createWidgetTaskRunningScreen(x, name, imageHash, isFocusedSource) {
  const board = createViewerChromeStudyScreen(x,
    isFocusedSource ? imageHash : null, { width: 1554, height: 1012 });
  board.name = name;
  if (!isFocusedSource) {
    artworkFill(board, ['#2F3747', '#9F8C78', '#35444B']);
  } else {
    // The artwork stays fully visible. These two independent layers preview
    // the bright phase of a border that animates between .35 and .80 opacity.
    const ring = rect('Main Image / breathing border / pulse peak', board,
                      8, 12, board.width - 16, board.height - 24, null, 12);
    ring.strokes = [fill(COLORS.accent, .80)];
    ring.strokeWeight = 2;
    ring.effects = [{
      type: 'DROP_SHADOW', color: { ...rgb(COLORS.accent), a: .28 },
      offset: { x: 0, y: 0 }, radius: 16, spread: 0,
      visible: true, blendMode: 'NORMAL'
    }];
    const label = frame('Task running / persistent image label',
                        board.width - 24 - 160, 67, 160, 34, COLORS.raised, 8);
    label.strokes = [fill(COLORS.accent, .72)];
    label.strokeWeight = 1;
    board.appendChild(label);
    ellipse('Running Dot / warm apricot', label, 14, 13, 8, COLORS.accent);
    text('Task running text', label, 'Task running', 30, 9, 12,
         COLORS.accent, 'semibold', 118, 'CENTER');
  }
  if (!isFocusedSource) addWidgetTaskRunningFilmstrip(board, imageHash);
  return board;
}

async function generateWidgetTaskRunningStudy(bytes) {
  await loadFonts();
  await createStyles();
  const names = [WIDGET_TASK_RUNNING_FOCUSED, WIDGET_TASK_RUNNING_BROWSING];
  const existing = names.map(name => figma.currentPage.children.find(child => child.name === name));
  if (existing.every(Boolean)) {
    figma.currentPage.selection = existing;
    figma.viewport.scrollAndZoomIntoView(existing);
    figma.ui.postMessage({ message: 'Widget Task Running study already exists. Showing both frames without changing your edits.' });
    return;
  }
  const { imageHash } = await resolveStudyImage(bytes, [...FOCUS_FRAME_NAMES, 'Image Viewer / Simple Operation']);
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const boards = [];
  for (let index = 0; index < names.length; index++) {
    if (existing[index]) { boards.push(existing[index]); continue; }
    const board = createWidgetTaskRunningScreen(maxX + 196, names[index], imageHash, index === 0);
    boards.push(board);
    maxX = board.x + board.width;
  }
  figma.currentPage.selection = boards;
  figma.viewport.scrollAndZoomIntoView(boards);
  figma.ui.postMessage({ message: 'Created Widget Task Running study: focused source with persistent main-image cue, and another image with the source thumbnail breathing.' });
  figma.notify('Widget Task Running study created');
}

function ensureWidgetTextResultInputPreview(result, imageHash) {
  let preview = result.findOne(node => node.name === 'Input Image Preview');
  const added = !preview;
  if (!preview) {
    preview = rect('Input Image Preview', result, 28, 126, 128, 96, null, 9, COLORS.line);
    if (imageHash) preview.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
    else artworkFill(preview, ['#25323A', '#A47761', '#293B33']);
  } else if (imageHash) {
    preview.fills = [{ type: 'IMAGE', imageHash, scaleMode: 'FILL' }];
  }

  if (!result.findOne(node => node.name === 'Input Image Label')) {
    text('Input Image Label', result, 'INPUT IMAGE', 176, 132, 10,
         COLORS.muted, 'semibold');
  }
  let filename = result.findOne(node =>
    node.name === 'Input Filename' || node.name === 'Source Context');
  if (filename) {
    filename.name = 'Input Filename';
    filename.characters = 'portrait.jpg';
    filename.x = 176;
    filename.y = 157;
    filename.fontSize = 13;
    filename.fontName = fontMedium;
    filename.fills = [fill(COLORS.text)];
  } else {
    filename = text('Input Filename', result, 'portrait.jpg', 176, 157, 13,
                    COLORS.text, 'medium');
  }
  if (!result.findOne(node => node.name === 'Input Image Metadata')) {
    text('Input Image Metadata', result, '2048 × 1365  ·  JPEG',
         176, 183, 11, COLORS.muted);
  }

  const divider = result.findOne(node => node.name === 'Content Divider');
  if (divider) divider.y = 250;
  const body = result.findOne(node => node.name === 'Result Text / direct content');
  if (body) body.y = 280;
  return added;
}

function createWidgetTextResultWindow(x, y, imageHash) {
  const width = 456;
  const height = 720;
  const result = frame(WIDGET_TEXT_RESULT_WINDOW, x, y, width, height, COLORS.surface, 16);
  result.strokes = [fill('#FFFFFF', .14)];
  result.strokeWeight = 1;
  result.effects = [{
    type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: .42 },
    offset: { x: 0, y: 18 }, radius: 42, spread: 0,
    visible: true, blendMode: 'NORMAL'
  }];
  figma.currentPage.appendChild(result);

  const titlebar = frame('01 / Result Window Titlebar', 0, 0, width, 58, COLORS.chrome, 0);
  result.appendChild(titlebar);
  ellipse('Close', titlebar, 18, 23, 12, '#ED6A5E');
  ellipse('Minimize', titlebar, 38, 23, 12, '#F4BF4F');
  ellipse('Zoom', titlebar, 58, 23, 12, '#61C554');
  text('Window Title', titlebar, 'Widget Result', 0, 20, 13,
       COLORS.text, 'semibold', width, 'CENTER');
  const copy = frame('Copy Text', 354, 13, 82, 32, COLORS.raised, 8);
  copy.strokes = [fill(COLORS.line)];
  copy.strokeWeight = 1;
  titlebar.appendChild(copy);
  const copyIcon = figma.createNodeFromSvg(ICONS.copy.replaceAll('CURRENT', COLORS.accent));
  copyIcon.name = 'Icon / copy';
  copyIcon.resize(15, 15);
  copyIcon.x = 11;
  copyIcon.y = 8.5;
  copy.appendChild(copyIcon);
  text('Copy Label', copy, 'Copy', 28, 9, 11, COLORS.accent, 'semibold');
  rect('Titlebar Divider', titlebar, 0, 57, width, 1, '#000000').opacity = .5;

  text('Widget Name', result, '图片反推文字', 28, 82, 17, COLORS.text, 'semibold');
  text('Source Context', result, 'portrait.jpg', 28, 111, 11, COLORS.muted);
  ellipse('Text Result Status', result, 351, 88, 8, COLORS.success);
  text('Result Type', result, 'TEXT RESULT', 367, 84, 10,
       COLORS.success, 'semibold', 61, 'RIGHT');
  rect('Content Divider', result, 28, 143, width - 56, 1, COLORS.line);

  const body = paragraph('Result Text / direct content', result,
    'A cinematic portrait in warm afternoon light. Natural skin tones, soft depth of field, and a muted green background create a calm, intimate mood. The subject is photographed at eye level with gentle contrast, clean facial detail, and subtle film grain. The composition feels editorial while remaining natural and understated.',
    28, 174, width - 56, 15, COLORS.text, 'regular');
  body.lineHeight = { unit: 'PIXELS', value: 24 };

  rect('Footer Divider', result, 28, height - 67, width - 56, 1, COLORS.line);
  text('Output Format', result, 'Plain text', 28, height - 43, 11, COLORS.muted);
  text('Character Count', result, '326 characters', 286, height - 43, 11,
       COLORS.muted, 'regular', 142, 'RIGHT');
  ensureWidgetTextResultInputPreview(result, imageHash);
  return result;
}

async function generateWidgetTextResultWindow(bytes) {
  await loadFonts();
  await createStyles();
  const page = figma.currentPage;
  const existingMain = page.children.find(child => child.name === WIDGET_TEXT_RESULT_MAIN);
  const existingResult = page.children.find(child => child.name === WIDGET_TEXT_RESULT_WINDOW);
  const { imageHash } = await resolveStudyImage(bytes,
    [WIDGET_TEXT_RESULT_MAIN, ...FOCUS_FRAME_NAMES,
     WIDGET_TASK_RUNNING_FOCUSED, 'Image Viewer / Simple Operation']);
  if (existingMain && existingResult) {
    const addedInputPreview = ensureWidgetTextResultInputPreview(existingResult, imageHash);
    page.selection = [existingMain, existingResult];
    figma.viewport.scrollAndZoomIntoView([existingMain, existingResult]);
    figma.ui.postMessage({ message: addedInputPreview
      ? 'Updated the existing text result window with its input image preview.'
      : 'Widget text result side-window study already includes the input image. Showing both windows.' });
    return;
  }

  let maxX = 0;
  for (const child of page.children) maxX = Math.max(maxX, child.x + child.width);
  const startX = existingMain ? existingMain.x : existingResult
    ? existingResult.x - 1554 - 16 : maxX + 196;
  const main = existingMain || createViewerChromeStudyScreen(
    startX, imageHash, { width: 1554, height: 1012 });
  main.name = WIDGET_TEXT_RESULT_MAIN;
  const result = existingResult || createWidgetTextResultWindow(
    main.x + main.width + 16, main.y + 84, imageHash);
  if (existingResult) ensureWidgetTextResultInputPreview(existingResult, imageHash);

  page.selection = [main, result];
  figma.viewport.scrollAndZoomIntoView([main, result]);
  figma.ui.postMessage({ message: 'Created Widget text result study: the source image keeps its full window, and the right window shows both the input image and direct plain-text output.' });
  figma.notify('Widget text result side window created');
}

figma.ui.onmessage = async message => {
  if (message.type === 'close') {
    figma.closePlugin();
    return;
  }
  if (message.type === 'get-editor-mode') {
    figma.ui.postMessage({ type: 'editor-mode', editorType: figma.editorType || 'figma' });
    return;
  }
  if (figma.editorType === 'dev') {
    figma.ui.postMessage({ message: 'Plugin imported. Switch to Design Mode before generating editable screens.' });
    return;
  }
  if (message.type === 'generate') {
    try {
      await generate(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Generation failed', { error: true });
    }
  }
  if (message.type === 'generate-simple-image-viewer') {
    try {
      await generateSimpleImageViewer(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Simple viewer generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Simple viewer generation failed', { error: true });
    }
  }
  if (message.type === 'generate-dark-refresh-screens') {
    try {
      await generateDarkRefreshScreens(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Dark Refresh generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Dark Refresh generation failed', { error: true });
    }
  }
  if (message.type === 'generate-viewer-chrome-study') {
    try {
      await generateViewerChromeStudy(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Viewer Chrome Study failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Viewer Chrome Study failed', { error: true });
    }
  }
  if (message.type === 'generate-preview-chrome-study') {
    try {
      await generatePreviewChromeStudy();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Preview Chrome Study failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Preview Chrome Study failed', { error: true });
    }
  }
  if (message.type === 'generate-compare-chrome-study') {
    try {
      await generateCompareChromeStudy(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Compare Mode Study failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Compare Mode Study failed', { error: true });
    }
  }
  if (message.type === 'replace-study-images') {
    try {
      await replaceStudyImages(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Image replace failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Image replace failed', { error: true });
    }
  }
  if (message.type === 'generate-image-inspect-chrome-study') {
    try {
      await generateImageInspectChromeStudy();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Image Inspect Chrome Study failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Image Inspect Chrome Study failed', { error: true });
    }
  }
  if (message.type === 'generate-image-filmstrip-scroll-study') {
    try {
      await generateImageFilmstripScrollStudy();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Image Filmstrip Scroll Study failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Image Filmstrip Scroll Study failed', { error: true });
    }
  }
  if (message.type === 'generate-video-inspect-controls-study') {
    try {
      await generateVideoInspectControlsStudy(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Video Inspect study failed: ' + (error && error.message ? error.message : String(error)) });
    }
  }
  if (message.type === 'generate-production-screens') {
    try {
      await generateProductionScreens();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Screen generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Screen generation failed', { error: true });
    }
  }
  if (message.type === 'generate-remaining-screens') {
    try {
      await generateRemainingScreens();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Remaining screens failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Remaining screens failed', { error: true });
    }
  }
  if (message.type === 'generate-home') {
    try {
      await generateHomeScreen();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Home generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Home generation failed', { error: true });
    }
  }
  if (message.type === 'generate-home-folder-scroll-study') {
    try {
      await generateHomeFolderScrollStudy();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Home folder scroll study failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Home folder scroll study failed', { error: true });
    }
  }
  if (message.type === 'generate-tray') {
    try {
      await generateTrayPopover();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Tray popover generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Tray popover generation failed', { error: true });
    }
  }
  if (message.type === 'redesign-widget-market') {
    try {
      await redesignWidgetMarket();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Market redesign failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Market redesign failed', { error: true });
    }
  }
  if (message.type === 'generate-image-compression-flow') {
    try {
      await generateImageCompressionFlow();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Image Compression Flow failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Image Compression Flow failed', { error: true });
    }
  }
  if (message.type === 'generate-widget-flow') {
    try {
      await generateWidgetFlow(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Widget flow generation failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Widget flow generation failed', { error: true });
    }
  }
  if (message.type === 'generate-widget-oss-result') {
    try {
      await generateWidgetOSSResult(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Widget OSS result generation failed: ' +
        (error && error.message ? error.message : String(error)) });
      figma.notify('Widget OSS result generation failed', { error: true });
    }
  }
  if (message.type === 'generate-result-badge-study') {
    try {
      await generateResultBadgeStudy();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Result badge study failed: ' +
        (error && error.message ? error.message : String(error)) });
      figma.notify('Result badge study failed', { error: true });
    }
  }
  if (message.type === 'generate-widget-task-running-study') {
    try {
      await generateWidgetTaskRunningStudy(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Widget Task Running study failed: ' +
        (error && error.message ? error.message : String(error)) });
      figma.notify('Widget Task Running study failed', { error: true });
    }
  }
  if (message.type === 'generate-widget-text-result-window') {
    try {
      await generateWidgetTextResultWindow(message.bytes);
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Widget text result side window failed: ' +
        (error && error.message ? error.message : String(error)) });
      figma.notify('Widget text result side window failed', { error: true });
    }
  }
  if (message.type === 'export-selection') {
    try {
      await exportSelection();
    } catch (error) {
      console.error(error);
      figma.ui.postMessage({ message: 'Export failed: ' + (error && error.message ? error.message : String(error)) });
      figma.notify('Export failed', { error: true });
    }
  }
};
