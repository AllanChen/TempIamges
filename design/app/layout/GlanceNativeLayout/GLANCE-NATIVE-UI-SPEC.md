# Glance Native macOS UI Specification

## 1. Product Direction

Glance 是内容检查工具，不是网页仪表盘。新版界面采用原生 macOS 工作台结构：内容面积最大、工具固定可见、信息与任务放在稳定侧栏，状态反馈靠位置、文字、图标和颜色共同表达。

设计强度：

- Layout variance: 6/10，允许不对称内容区，但生产窗口保持可预测。
- Motion intensity: 6/10，仅对状态、插入、展开和选择变化使用动画。
- Visual density: 7/10，信息紧凑但不使用驾驶舱式小字堆叠。
- 唯一品牌强调色为暖琥珀色；绿色、红色、蓝色只承担语义状态。
- 不使用营销页 Hero、网页导航、滚动叙事、装饰性大标题和无意义动效。

## 2. Design Tokens

### Color

| Token | Value | Usage |
|---|---:|---|
| Background | `#09090B` | 全局背景、画布外围 |
| Sidebar | `#0D0D10` | 页面切换器、次级导航 |
| Surface | `#111114` | toolbar、inspector、固定底栏 |
| Raised | `#17171C` | 弹层、分组面板、skeleton |
| Control | `#201F25` | 次级按钮、segment 选中态 |
| Text primary | `#F3EEE8` | 标题、正文、主要数据 |
| Text secondary | `#AAA4A0` | 描述、文件信息 |
| Text tertiary | `#726D69` | 标签、时间、辅助说明 |
| Accent | `#E8A87C` | 主操作、选择、处理中 |
| Success | `#8FD0AF` | 完成、安装、权限通过 |
| Failure | `#F18B86` | 错误、失败、取消 |
| Information | `#A9C5EF` | 非阻断提示 |
| Hairline | `white 10%` | 分隔线、默认边框 |
| Strong line | `white 16%` | 浮层和重要边界 |

正常正文与背景对比度必须达到 4.5:1；状态边界和图标达到 3:1。低对比文字不得承载唯一信息。

### Typography

- UI font: SF Pro Text / macOS system font。
- Numeric and code: SF Mono / monospaced system font。
- Window title: 14 pt semibold。
- Page title: 20–24 pt semibold，仅用于设置、Base64、Widget 详情等内容页。
- Primary row label: 11–12 pt semibold。
- Body: 11–12 pt regular。
- Metadata: 9–10 pt medium。
- 不使用负字距，不以超大字号制造层级。

### Geometry

- Spacing scale: 4, 8, 12, 16, 20, 24, 32。
- Control height: 32 pt。
- Icon visual size: 12–17 pt；可点击区域不小于 30×30 pt。
- Radius: 8 pt controls, 12 pt panels, 16 pt floating windows。
- Toolbar: 52 pt。
- Filmstrip: 88 pt。
- Inspector: 276 pt。
- Hairline: 1 pt。

## 3. Global Window Architecture

每个生产窗口遵循以下层级：

```text
macOS title bar
fixed application toolbar
content region
optional fixed bottom controls / filmstrip
```

规则：

- toolbar、filmstrip 和 inspector 不悬浮覆盖主内容。
- 面板展开时重新分配布局，不压在图片上。
- 只有临时 toast、菜单、popover 可以覆盖内容。
- Inspector 固定在右侧，标题、metadata、任务状态、主操作自上而下。
- 非媒体内容不显示旋转、翻转、比较和缩放工具。
- 所有窗口定义 preferred size 和 minimum size；不能依赖随机硬编码 frame。

## 4. Motion System

### Timing

| Motion | Duration | Curve |
|---|---:|---|
| Hover / press feedback | 90–140 ms | ease out |
| Selection change | 160–200 ms | ease out |
| Inspector show/hide | 280 ms | spring, damping 0.86 |
| Result thumbnail insertion | 340 ms | spring, damping 0.82 |
| Popover / menu enter | 180 ms | ease out |
| Popover / menu exit | 120 ms | ease in |
| Skeleton sweep | 1250 ms | linear, repeating |
| Task breathing cycle | 820 ms each direction | ease in-out |

动画必须可打断。状态正确性不能依赖 animation completion callback。

### Reduced Motion

启用 Reduce Motion 后：

- 禁止 spring、scale、位移动画。
- Inspector 使用立即切换或 120 ms opacity。
- 结果缩略图直接出现，并保留绿色完成标记。
- 处理中缩略图停止呼吸，改为静态 2 pt 琥珀边框和状态圆点。
- skeleton 变为静态占位面，不持续扫光。

## 5. Loading and Feedback

### Less Than 300 ms

不显示 loading，避免闪烁。

### 300 ms to 1 s

- 按钮内部使用小型 `ProgressView`。
- 按钮禁用，但窗口其他操作保持可用。
- 保持按钮宽度不变。

### More Than 1 s

- 列表、详情和 Web 内容使用与最终布局等高的 skeleton。
- 媒体画布保持原内容，不使用大面积 spinner 遮盖图片。
- 必须显示当前动作，例如“正在解码”“Worker processing”。

### Error

- 错误靠近触发位置。
- 说明发生了什么，并提供 Retry、Copy diagnostics 或 Open Settings。
- 错误状态保留用户输入和当前主图。

## 6. Quick Preview

Preferred: 720×520。Minimum: 560×400。

```text
48 toolbar
┌──────────────────────┬───────────┐
│ preview canvas       │ quick info│
└──────────────────────┴───────────┘
```

- 作为 transient panel，不展示完整 Widget 与 Task 工具。
- toolbar：文件类型、文件名、pin、Open Inspector、close。
- Return 打开 Image Inspect；Space release 关闭，pin 后保持。
- 图片居中等比显示，最长边不超过内容区 76%。
- 加载超过 300 ms 时画布显示低对比占位，但不变成白底。

## 7. Image Inspect

Preferred: 1180×760。Minimum: 900×600。

```text
52 toolbar
┌──────────────────────────────┬────────────┐
│ image canvas                 │ inspector  │
│                              │ 276        │
├──────────────────────────────┴────────────┤
│ filmstrip 88                              │
└───────────────────────────────────────────┘
```

### Toolbar

- 左：Focus / Side by side / Slider segmented control。
- 中：rotate left、rotate right、flip、fit。
- 右：任务状态、Widget Market、Task Center、Information、More。
- 任务存在时 Task Center 图标右上角显示 7 pt 红点。
- 信息栏按钮使用 selected state，不用“打开/关闭”文字。

### Canvas

- 图片最大占画布宽 56%、高 76%，保持原比例。
- 文件名和焦点编号位于左上角，不建立额外 identity bar。
- Compare side-by-side 中间使用 1 pt 分隔线。
- Slider 比较线 1 pt；拖拽区域应扩展到 24 pt，但视觉线不变粗。
- Processing 不遮住主图；右上角最多出现 42 pt 高的紧凑状态条。

### Inspector

- Filename、Dimensions、Color、Source。
- 存在任务时增加 Active Task：Widget、百分比、progress、说明。
- 主操作固定在底部：Run Widget、Cancel Task 或 Show Result。

### Filmstrip

- 左侧显示 item count。
- 缩略图 60×52；标签位于下方。
- 当前项使用 2 pt 琥珀边框。
- 结果必须插入源图的右侧，不追加到不相关项后方。
- 结果插入不得改变当前主图选中项。

### Widget Submission Sequence

1. 用户点击 Run Widget。
2. 按钮立即进入 loading，创建本地 task record。
3. Task Center toolbar icon 出现红点。
4. 源图缩略图进入呼吸状态。
5. Inspector 显示 Widget 名称、进度和 Cancel。
6. 完成后，源图呼吸结束。
7. 结果缩略图从源图右侧插入，显示绿色 check。
8. toolbar 状态变为 Result ready。
9. 主图仍显示提交前用户正在查看的 item。

### Thumbnail Breathing Animation

- Border: 1.4 pt → 2.4 pt → 1.4 pt。
- Shadow radius: 2 → 10 → 2。
- Shadow opacity: 0.08 → 0.44 → 0.08。
- Accent: `#E8A87C`。
- Duration: 820 ms each direction, auto reverse。
- 右上角固定 8 pt 琥珀圆点，外有 2 pt surface stroke。
- 动画只施加在对应源图缩略图，不影响整条 filmstrip。
- Failed 改用红色静态边框；Completed 改用绿色 check，不继续呼吸。

## 8. Video Inspect

Preferred: 1180×760。Minimum: 900×620。

- 顶部媒体工具与 Image Inspect 同层级。
- 视频播放控制单独固定在画布下方，不混入全局 toolbar。
- 播放控制：play/pause、mute、timeline、current/duration、fullscreen。
- Buffering：视频画面仍可见，中间显示紧凑状态容器。
- Decoder error：显示原因、Retry，保留文件信息。
- Compare 支持 side-by-side 和 slider；两侧播放位置同步。
- 信息栏：Filename、Dimensions、Codec、Duration、Frame rate。

## 9. Content Viewer

Preferred: 1050×720。Minimum: 760×520。

- Code、Markdown、PDF 使用相同窗口结构。
- toolbar 仅保留内容类型、搜索、share、more。
- 右侧 inspector 宽 276 pt，保持文档 metadata。
- Code 使用 SF Mono 12 pt，可编辑时显示插入点和行选择。
- Markdown 正文最大宽 620 pt。
- PDF 页面居中，提供页码和缩放；页面背景为暖白，不改变整个窗口主题。
- 不显示图片旋转、Widget 快捷工具和视频播放控件。

## 10. Widget Market

Preferred: 980×650。Minimum: 760×520。

```text
52 toolbar
┌──────────── 340 ────────────┬──────────────────┐
│ search + widget list        │ widget detail    │
└─────────────────────────────┴──────────────────┘
```

- toolbar 右侧只放 reload icon 和 close icon。
- card click 只选择并打开详情；不会直接安装或执行。
- 列表项 72 pt，高亮使用 accent 14% fill 和 38% border。
- 安装状态来自本地 registry，不以网络列表推断。
- 详情包含 icon、name、summary、version、runtime、privacy、commands。
- 一个 command：详情直接显示该 command，安装后显示 Run Widget。
- 多 command：Run Widget 后展示 command menu。
- reload 时列表使用 4 行等高 skeleton，详情保持当前内容直到新数据成功。
- 安装按钮在执行中保持原宽度并显示 ProgressView。

## 11. Task Center

Preferred: 1040×680。Minimum: 780×520。

- 左侧列表约 58%，右侧 detail 固定 360 pt。
- 筛选：All、Processing、Completed、Failed。
- 每行包含输入缩略图、Widget、文件名、时间、状态和进度/输出信息。
- 当前行仅使用低透明度 accent surface，不用高亮大色块。
- detail：task id、输入、timeline、底部操作。
- Processing：Cancel、Show Input。
- Completed：Reveal Result、Show Input。
- Failed：Retry、Show Input，并显示具体错误阶段。
- 状态变化不得导致列表行高度变化。

## 12. Base64

Preferred: 980×650。Minimum: 760×520。

- 左输入、右预览双栏；右栏 360 pt。
- 输入必须是 multiline TextEditor，SF Mono 12 pt。
- label 位于输入上方，不能只使用 placeholder。
- 支持 data URL、纯 Base64、换行和空白。
- Empty：右侧说明结果会出现的位置。
- Loading：右侧图片和 metadata 使用 skeleton。
- Success：图片预览及 type、dimensions、size。
- Error：输入边框变红，错误显示在输入下方，输入不清空。

## 13. History

Preferred: 1100×720。Minimum: 780×520。

- toolbar：search、Grid/List、Clear History。
- 内容按 Today、Yesterday 等日期分组。
- Grid 使用 adaptive 150–220 pt，不固定三列。
- List 保留相同信息层级和 48 pt 缩略图。
- 右侧 inspector 展示所选历史项并提供 Open Again。
- Empty state 明确说明如何创建历史记录，不使用空白列表。

## 14. Settings

Preferred: 820×600。Minimum: 680×500。

- 左侧分类 178 pt：General、Preview、Widgets、Account。
- 右侧内容最大宽 680 pt。
- Toggle 使用原生 switch；选择器使用原生 Picker。
- General：enable、clipboard、launch at login、language。
- Preview：reduce motion、canvas、inspector position、shortcut。
- Widgets：installed registry、结果插入和焦点行为。
- Account：登录信息和 Sign Out。
- 每个 setting 必须有 label；复杂选项带一行说明。

## 15. Onboarding

Preferred: 620×600。Minimum: fixed 620×600。

- 单一深色磨砂容器，不能出现白底系统网页。
- 顶部 icon、title、简短说明。
- 权限行高 78 pt：Input Monitoring、Accessibility、Full Disk Access。
- 每行显示 required/optional、说明和 Granted/Open Settings。
- Continue 固定在底部右侧；必需权限缺失时原生 disabled。
- 权限变化后 200 ms opacity/颜色过渡，不移动行位置。

## 16. Widget Web

Preferred: 1080×720。Minimum: 820×560。

- 保留原生 browser chrome：back、forward、reload、secure URL、状态切换。
- Web 内容不能出现白色 loading 页面。
- Ready：输入预览、command options、privacy、Submit Widget。
- Loading：使用与最终内容相同尺寸的 skeleton。
- Error：说明服务不可用，提供 Retry；关闭页面不是唯一恢复方式。
- 提交后沿用 Image Inspect 的 task record、红点、呼吸缩略图和结果插入规则。

## 17. Accessibility and Keyboard

- 所有 icon button 提供 accessibility label 和 tooltip。
- Selected、pressed、expanded、disabled 状态必须暴露给辅助功能。
- Tab 顺序与视觉顺序一致：toolbar → main content → inspector → bottom controls。
- 拖入、缩略图重排和 slider drag 必须提供菜单或键盘替代操作。
- 默认焦点不自动跳到异步结果。
- 状态更新使用完整语句，例如“Remove Background completed, result added after selected-image.jpg”。
- 对纯图标状态同时提供文字或 VoiceOver 描述。

## 18. Production Migration Order

1. 将共享 token 和组件从原型映射到 `PanelStyle.swift` 或新的 SwiftUI theme。
2. 完整替换 Image Inspect 视图树并接回现有图片/任务逻辑。
3. 完成 Release 截图验收后再迁移 Video Inspect。
4. 迁移 Task Center 与 Widget Market。
5. 迁移 Base64、Content Viewer、History、Settings、Onboarding、Widget Web。
6. 补齐中英文本地化、VoiceOver、键盘和 Reduce Motion。
7. 每页使用固定数据做 Release 截图对比，不以 Build Succeeded 作为视觉验收。
