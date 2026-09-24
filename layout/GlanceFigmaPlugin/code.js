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
  iconButton(toolbar, 'Focus', 'focus', 686, 14, true);
  iconButton(toolbar, 'Compare', 'compare', 734, 14);
  iconButton(toolbar, 'Fit', 'fit', 782, 14);
  iconButton(toolbar, 'Tasks', 'tasks', 1378, 14);
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
  const badge = frame('Cloud Badge', x, y, width, 19, COLORS.accentSoft, 4);
  parent.appendChild(badge);
  text('Badge Label', badge, label, 0, 4, 9, COLORS.accent, 'semibold', width, 'CENTER');
}

function marketButton(parent, title, x, y, installed = false) {
  const width = installed ? 91 : 76;
  const action = frame(installed ? 'Installed / local registry' : 'Install Widget', x, y,
                       width, 31, installed ? '#1B3029' : COLORS.accent, 8);
  action.strokes = [fill(installed ? COLORS.success : COLORS.accent, .5)];
  action.strokeWeight = 1;
  parent.appendChild(action);
  text('Action Label', action, title, 0, 8, 11,
       installed ? COLORS.success : '#21130D', 'semibold', width, 'CENTER');
  return action;
}

function marketRow(parent, y, widget) {
  const row = panel(parent, 'Widget / ' + widget.name, 16, y, 348, 132,
                    widget.selected ? '#211C1A' : COLORS.surface, 12);
  if (widget.selected) row.strokes = [fill(COLORS.accent, .45)];
  const icon = frame('48px Widget Icon', 14, 13, 48, 48, '#2A2423', 10);
  icon.strokes = [fill(COLORS.line)]; icon.strokeWeight = 1;
  row.appendChild(icon);
  text('Icon Letter', icon, widget.icon, 0, 14, 15, COLORS.accent, 'semibold', 48, 'CENTER');
  text('Name', row, widget.name, 74, 12, 13, COLORS.text, 'semibold', 215);
  text('Version', row, 'Official Widget  ·  v' + widget.version, 74, 32, 10, COLORS.muted);
  marketBadge(row, 'CLOUD', 278, 15, 55);
  text('Summary', row, widget.summary, 14, 68, 11, COLORS.secondary, 'regular', 316);
  rect('Footer Divider', row, 14, 92, 320, 1, COLORS.line);
  text('Commands', row, '1 command  ·  ' + widget.command, 14, 103, 10, COLORS.muted,
       'regular', widget.installed ? 218 : 234);
  marketButton(row, widget.installed ? 'Installed' : 'Install',
               widget.installed ? 243 : 258, 96, widget.installed);
  return row;
}

function marketPanel(parent, name, x) {
  const shell = panel(parent, name, x, 196, 380, 620, COLORS.canvas, 16);
  const tint = rect('Warm Glass Tint', shell, 0, 0, 380, 620, '#2B211D');
  tint.opacity = .24;
  return shell;
}

function createWidgetMarketScreen(x) {
  const board = frame('Widget Market / Install / Clean Editable', x, 0, 1554, 1012, COLORS.bg, 16);
  board.strokes = [fill(COLORS.line)]; board.strokeWeight = 1;
  figma.currentPage.appendChild(board);
  text('Review Heading', board, 'Widget Market  /  existing install flow', 42, 43,
       18, COLORS.text, 'semibold');
  text('Review Note', board, 'Compact VS Code-style list. Detail is a secondary state, not a permanent column.',
       42, 75, 11, COLORS.muted);

  const catalog = marketPanel(board, '01 / Attached Market Catalog', 337);
  text('Catalog Heading', catalog, 'Widget Market', 22, 20, 21, COLORS.text, 'semibold');
  iconButton(catalog, 'Close Market', 'close', 294, 16);
  iconButton(catalog, 'Reload Catalog', 'refresh', 334, 16);
  rect('Header Divider', catalog, 20, 69, 340, 1, COLORS.line);
  marketRow(catalog, 84, {
    icon: 'R', name: 'Remove Background', version: '1.0.0',
    summary: 'Remove an image background, preserving subject edges.',
    command: 'Remove Background', installed: true, selected: true
  });
  marketRow(catalog, 226, {
    icon: '2×', name: '超分', version: '1.0.0',
    summary: '图生图超分辨率，提升图片清晰度与细节。',
    command: '超分', installed: false
  });
  marketRow(catalog, 368, {
    icon: 'R+', name: 'RemoveBG 高级', version: '1.0.0',
    summary: '高级背景移除，保留精细主体边缘。',
    command: 'RemoveBG 高级', installed: false
  });
  text('Catalog Footer', catalog, 'OFFICIAL WIDGETS  ·  3 AVAILABLE', 20, 527,
       10, COLORS.muted, 'semibold');
  paragraph('Offline Helper', catalog,
            'Installed Widgets remain available when the catalog is offline.',
            20, 552, 338, 11, COLORS.secondary);

  const detail = marketPanel(board, '02 / Selected Widget Detail Drawer', 837);
  iconButton(detail, 'Back to Catalog', 'back', 20, 17);
  text('Detail Heading', detail, 'Widget details', 74, 26, 13, COLORS.secondary, 'medium');
  rect('Detail Header Divider', detail, 20, 69, 340, 1, COLORS.line);
  const icon = frame('48px Widget Icon', 22, 93, 48, 48, '#2A2423', 10);
  detail.appendChild(icon);
  text('Icon Letter', icon, 'R', 0, 14, 15, COLORS.accent, 'semibold', 48, 'CENTER');
  text('Widget Name', detail, 'Remove Background', 84, 96, 16, COLORS.text, 'semibold');
  text('Version', detail, 'Official Widget  ·  v1.0.0', 84, 123, 11, COLORS.muted);
  marketBadge(detail, 'CLOUD', 22, 160, 55);
  marketButton(detail, 'Installed', 269, 154, true);
  rect('Summary Divider', detail, 22, 199, 336, 1, COLORS.line);
  text('About Heading', detail, 'ABOUT', 22, 219, 10, COLORS.muted, 'semibold');
  paragraph('Summary', detail,
            'Remove an image background while preserving fine subject edges.',
            22, 243, 334, 12, COLORS.secondary);
  text('Command Heading', detail, 'COMMAND', 22, 312, 10, COLORS.muted, 'semibold');
  paragraph('Command', detail, 'Remove Background  ·  Image → PNG with transparency',
            22, 336, 334, 11, COLORS.secondary);
  text('Privacy Heading', detail, 'PRIVACY', 22, 391, 10, COLORS.muted, 'semibold');
  paragraph('Privacy Notice', detail,
            'The selected image is uploaded to Glance for cloud processing.',
            22, 415, 334, 11, COLORS.secondary);
  rect('Bottom Divider', detail, 22, 517, 336, 1, COLORS.line);
  const uninstall = frame('Uninstall / explicit action', 22, 538, 336, 38, '#231719', 8);
  uninstall.strokes = [fill(COLORS.danger, .42)]; uninstall.strokeWeight = 1;
  detail.appendChild(uninstall);
  text('Uninstall Label', uninstall, 'Uninstall Widget', 0, 12, 11,
       COLORS.danger, 'medium', 336, 'CENTER');
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

async function redesignWidgetMarket() {
  await loadFonts();
  await createStyles();
  const name = 'Widget Market / Install / Clean Editable';
  const old = figma.currentPage.children.find(child => child.name === name);
  if (old && old.findOne(node => node.name === '01 / Attached Market Catalog')) {
    figma.currentPage.selection = [old];
    figma.viewport.scrollAndZoomIntoView([old]);
    figma.ui.postMessage({ message: 'Widget Market already uses the compact catalog layout.' });
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
  figma.ui.postMessage({ message: 'Redesigned Widget Market. Previous frame kept to the right.' });
  figma.notify('Widget Market catalog redesigned');
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

function createFloatingInspectToolbar(parent, width, activeName = 'Focus') {
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
  lightIconButton(toolbar, 'Focus', 'focus', 14, activeName === 'Focus');
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
  createFloatingInspectToolbar(board, width);

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
  const dialog = panel(parent, 'Compression Dialog', x, y, 320, 236, COLORS.surface, 14);
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
  text('Caption', dialog, 'Lower quality means a smaller file.', 20, 44, 12, COLORS.secondary, 'regular', 280);

  text('Quality Label', dialog, 'Quality: 70%', 20, 78, 12, COLORS.text, 'medium');
  rect('Slider Track', dialog, 20, 102, 280, 4, COLORS.line, 2);
  rect('Slider Fill', dialog, 20, 102, 196, 4, COLORS.accent, 2);
  const knob = ellipse('Slider Knob', dialog, 20 + 196 - 7, 97, 14, '#F3EEE8');
  knob.effects = [{
    type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: .35 },
    offset: { x: 0, y: 2 }, radius: 4, spread: 0, visible: true, blendMode: 'NORMAL'
  }];
  text('Slider Hint', dialog, '10% – 100%', 20, 114, 11, COLORS.muted, 'regular');

  text('Format Label', dialog, 'Format:', 20, 144, 12, COLORS.text, 'medium');
  const dropdown = panel(dialog, 'Format Dropdown', 72, 140, 228, 30, '#17181D', 8);
  text('Dropdown Value', dropdown, 'Same as original', 12, 8, 12, COLORS.text, 'medium', 180);
  const chevron = figma.createNodeFromSvg(ICONS.chevron.replaceAll('CURRENT', COLORS.secondary));
  chevron.name = 'Icon / chevron'; chevron.resize(14, 14); chevron.x = 206; chevron.y = 8; dropdown.appendChild(chevron);

  const cancel = frame('Cancel Button', 150, 192, 80, 32, '#17181D', 8);
  cancel.strokes = [fill(COLORS.line)]; cancel.strokeWeight = 1; dialog.appendChild(cancel);
  text('Cancel Label', cancel, 'Cancel', 0, 9, 12, COLORS.text, 'medium', 80, 'CENTER');

  const compress = frame('Compress Button', 240, 192, 90, 32, COLORS.accent, 8);
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
  compressionDialog(scene2.board, Math.round((1554 - 320) / 2), Math.round((1012 - 236) / 2));

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
  if (existing) {
    figma.currentPage.selection = [existing];
    figma.viewport.scrollAndZoomIntoView([existing]);
    figma.ui.postMessage({ message: 'Image Compression Flow already exists — delete it to regenerate.' });
    return;
  }
  let maxX = 0;
  for (const child of figma.currentPage.children) maxX = Math.max(maxX, child.x + child.width);
  const flow = createCompressionFlowScreen(maxX + 196);
  figma.currentPage.selection = [flow];
  figma.viewport.scrollAndZoomIntoView([flow]);
  figma.ui.postMessage({ message: 'Created Image Compression Flow (3 scenes).' });
  figma.notify('Image Compression Flow created');
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

figma.ui.onmessage = async message => {
  if (message.type === 'close') {
    figma.closePlugin();
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
