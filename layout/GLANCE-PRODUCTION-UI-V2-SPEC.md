# Glance Production UI V2

这份方案是对现有 Glance AppKit 界面的可落地重排，不是独立产品概念，也不要求把 HTML 放进生产应用。

## 查看方式

打开 `glance-production-ui-v2.html`。左侧仅是设计评审导航，不属于生产 App。稿件内可操作的部分包括：

- 切换全部核心页面。
- 图片检查中收起 Information、提交 Widget 任务、观察缩略图呼吸灯和完成结果插入。
- Widget Market 中切换安装和卸载，并点击右上角 reload。
- Widget Web 切换加载、成功和错误状态。
- Base64 输入、空值校验和结果反馈。
- 偏好设置中的开关状态。

## 设计判断

- 产品定位：面向创作者和 Widget 开发者的原生 macOS 媒体检查工具。
- 设计语言：内容优先的深色工作台，强调精确、稳定和低干扰。
- 视觉参数：`DESIGN_VARIANCE 5`、`MOTION_INTENSITY 4`、`VISUAL_DENSITY 7`。
- 主题：全局只使用深色主题，暖杏色是唯一品牌强调色。
- 材质：普通窗口以不透明层级为主。只有附着面板、Widget Web 和暂态反馈使用磨砂，避免全屏玻璃化。
- 圆角：窗口 16、容器 12、控件 8。按钮不使用全胶囊造型。
- 字体：生产实现继续使用 macOS 系统字体和 SF Mono，不引入 Web 字体依赖。

## 全局尺寸与 token

| 项目 | 建议值 | 生产映射 |
| --- | ---: | --- |
| 顶部 titlebar | 44 pt | 原生 `NSWindow` titlebar 或统一自定义 chrome |
| 工作台 toolbar | 48 pt | `NSView` 固定高度，不随 hover 隐藏 |
| 右侧 inspector | 280 pt | 可收起，宽度保持稳定 |
| 底部 filmstrip | 92 pt | 固定存在，横向滚动 |
| 状态栏 | 26 pt | 文件摘要与任务轮询状态 |
| 基础间距 | 8 pt | 4、8、12、16、24、32 六档 |
| 普通控件高度 | 32 pt | 点击区域至少 32 pt，关键图标按钮扩大命中区 |
| 表面 | `#111114` | `PanelStyle.surface` |
| 次级表面 | `#17171c` | `PanelStyle.surfaceRaised` |
| 主文字 | `#F3EEE8` | `PanelStyle.textPrimary` |
| 次级文字 | `#B8B0AA` | `PanelStyle.textSecondary` |
| 品牌强调 | `#E8A87C` | `PanelStyle.accent` |
| 成功 | `#8FD0AF` | 任务完成和已安装 |
| 错误 | `#F18B86` | 失败、危险操作 |

## 页面与现有代码映射

| 设计页面 | 当前生产入口 | 落地方式 |
| --- | --- | --- |
| 快速预览 | `PreviewPanel.swift`、`ContentPanel.swift` | 保留轻量浮层，混合输入先分类，再进入图片、视频或内容窗口 |
| 图片检查 | `ImageInspectWindow.swift` | 重建为 toolbar、canvas、inspector、filmstrip、statusbar 五个稳定区域 |
| 视频检查 | `VideoCompareWindow.swift` | 复用图片工作台结构，中央区域替换为 AVPlayer 和上下文播放栏 |
| 内容查看 | `ContentViewerWindow.swift` | 隐藏媒体操作，右侧信息框按 3:4 排版 |
| 任务中心 | `WidgetTaskCenterWindow.swift` | 左侧筛选列表，右侧预览和时间线，不使用卡片瀑布流 |
| Widget Market | `WidgetMarketPanel.swift` | 保持贴右侧和可关闭，Web 内容改为列表加固定详情列 |
| Widget Web | 当前 Widget WebView 容器 | WebView 背景透明，外层提供 loading、error 和 success 状态 |
| Base64 | 当前 Alert 或 command 入口 | 提升为独立窗口，使用 `NSTextView`，不能使用单行 `NSTextField` |
| 历史 | `HistoryWindow.swift` | 搜索头部加自适应网格，保留现有历史数据模型 |
| 设置 | `PreferencesWindow.swift` | 左侧类别加右侧表单，继续使用系统控件和 UserDefaults |
| 首次启动 | `OnboardingWindow.swift` | 保留现有 580 pt 权限流程，只统一间距和状态表达 |

## 核心交互规格

### 图片任务

1. 用户在 Inspector 或右键一级菜单运行单 command Widget。
2. 提交成功后，任务按钮显示语义红点，源图缩略图出现暖杏色呼吸边框。
3. 主图不显示阻断式蒙层，只在左下角显示可自动消退的任务提示。
4. 用户可以继续缩放、查看信息或切换图片。
5. 完成后停止呼吸灯，把结果插入源图缩略图右侧并标记“刚完成”。
6. 不自动切换当前主图。用户点击结果缩略图后才切换。
7. 失败时缩略图保留错误标记，任务中心提供原因和重试。

### Widget Market

1. 点击卡片主体更新右侧详情，不执行安装。
2. 安装和卸载只能通过详情区明确按钮执行。
3. 本地 registry 是已安装状态的第一来源，Market 加载后再与远端 manifest 对齐。
4. 一个 command 的 Widget 直接出现在一级右键菜单。两个及以上 command 才展示二级菜单。
5. reload 只显示图标，位于 titlebar 右侧，与 Widget Market 标题区域对齐。

### 非媒体内容

1. 文件分类完成后先决定使用媒体工作台还是 Content Viewer。
2. 代码、Markdown 和普通文本不创建缩放、方向、比较等媒体按钮。
3. 右侧内容框使用 3:4，展示类型、编码、行数和来源。

## Loading、空态和错误态

- 小于约 300 ms 的操作不闪现 Loading。
- 远端媒体和 Widget Web 复用项目现有 `ModularImageLoadingView`。
- 加载超过 1 秒时保留最终布局尺寸，避免窗口内容跳动。
- 错误必须包含原因和恢复动作，不能只有红色文字。
- Task Center 空态提供“回到图片检查”动作。
- Widget Market 离线时保留本地已安装列表，并标明远端内容暂不可用。
- 所有状态必须有文本，不能只依赖颜色或小圆点。

## 动画

- 侧栏开合：160 ms，透明度加轻微位移，动画可中断。
- hover 和 pressed：120 到 160 ms，只改变背景、边框和透明度，不改变布局尺寸。
- 任务缩略图呼吸：1.5 秒，只表达活跃轮询。Reduce Motion 下改成静态强调边框。
- 结果插入：180 ms 淡入，不自动滚动主画布，不抢焦点。
- WebView reload：图标单次旋转，Reduce Motion 下只改变透明度。

## 本地化与可访问性

- 设计稿中的中文只是默认语言示例。新增文案全部进入 `zh-Hans.lproj` 和 `en.lproj`。
- 图标按钮必须同时拥有 tooltip 和 accessibility label。
- 键盘焦点顺序按 toolbar、canvas、inspector、filmstrip、statusbar 排列。
- 拖放必须有“添加”按钮和粘贴快捷键作为替代。
- 正文对比度至少 4.5:1，边界和状态图标至少 3:1。
- URL、Widget ID 和 Base64 等长 token 使用可换行或横向滚动，不能压坏布局。

## 推荐实现顺序

1. 只扩充 `PanelStyle.swift` 的语义 token 和通用控件，不移动业务逻辑。
2. 完成 Image Inspect 五区结构，并接回现有缩放、方向、拖放和 Widget 操作。
3. 抽出共享 workbench chrome，迁移 Video Inspect 和 Content Viewer。
4. 重排 Task Center，并实现任务到缩略图状态的单向绑定。
5. 更新 Widget Market 的 HTML/CSS/JS 和 AppKit 容器状态。
6. 把 Base64 从 Alert 提升为独立窗口。
7. 最后迁移 History、Preferences、Onboarding 和全部空态。

每完成一个页面，都用 `./run.sh` 启动生产 App 验证。HTML 只负责锁定结构、层级和状态，不参与运行时构建。

## 本轮边界

- 没有修改 `Glance/Sources`、`project.yml` 或 `run.sh`。
- 没有改变 Widget API、任务数据模型、缓存和签名逻辑。
- 没有把预览稿包装为新的 SwiftUI App，避免再次出现“稿件很好看但无法迁移”的分叉实现。
