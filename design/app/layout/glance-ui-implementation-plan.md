# Glance 新 UI 实现计划

## 目标

基于 `glance-full-app.html` 和 `glance-ui-flows.html`，把 Glance 的桌面端界面统一为深色磨砂工作台：主图优先、右侧信息层级清楚、Widget 和任务状态可追踪、中文文案完整本地化。此计划只描述实现，不在当前分支修改生产代码。

## 视觉与交互基线

- 背景：`#09090b`，窗口表面：`#111114` / `#17171c`，边框使用低透明度亮线。
- 主强调色只有暖琥珀 `#e8a87c`；绿色表示完成，红色表示失败，蓝色表示信息。
- 所有窗口使用深色磨砂材质，避免白底 WebView、纯黑大块和高亮霓虹。
- 8px 间距节奏，圆角优先使用 8、12、16，控件高度保持统一。
- 动画只用于状态变化：任务轮询使用缩略图呼吸灯，加载使用项目现有 Loading；减少主图遮挡。
- 默认语言为简体中文，所有新增文案进入 `zh-Hans.lproj` 与 `en.lproj`，代码中不直接写展示文案。

## 实现阶段

### 阶段一：建立视觉基础层

1. 扩展 `PanelStyle.swift`，集中定义背景、磨砂、文字、边框、强调色、状态色、圆角和间距 token。
2. 检查 `ContentPanel.swift`、`PreviewPanel.swift`、`ImageInspectWindow.swift`、`WidgetMarketPanel.swift`、`WidgetTaskCenterWindow.swift` 的窗口材质，统一为 token，不再各自定义颜色。
3. 建立通用 AppKit 组件：玻璃容器、状态徽标、图标按钮、分段标签、空态/加载态/错误态卡片。
4. 给图标按钮补 accessibility label、tooltip、键盘焦点和中文本地化名称，避免右键菜单与 toolbar 字体模糊。

验收：所有核心窗口在深色模式下无白底，颜色只承担辅助表达，文字和图标仍能独立表达状态。

### 阶段二：重做图片预览工作台

涉及：`ImageInspectWindow.swift`、`ContentViewerWindow.swift`、`ImageLoader.swift`、`PanelStyle.swift`。

1. 以现有布局稿 01 为唯一结构：顶部 toolbar、中央画布、右侧 Information、底部 filmstrip。
2. toolbar 与底部信息栏默认常驻，不再因为鼠标移入/移出自动隐藏；保留关闭和明确的收起操作。
3. 方向按钮收纳向左旋转、向右旋转、左右翻转、上下翻转；使用 hover submenu 或 popover，方向和其中 item 全部本地化。
4. 缩放改为基于目标缩放值的平滑动画，避免 zoom in/out 一卡一卡；保留适应窗口和当前百分比。
5. 多图拖入与剪贴板图片必须按独立 item 建立缓存，缩略图立即出现，不能以 URL 作为唯一 identity。
6. 非媒体内容（代码、Markdown、PDF）切换到内容查看器：隐藏媒体 toolbar，右侧信息区域保持 3:4 比例。
7. 修正长 URL 与终端输出识别：先剥离 ANSI/终端 bounds 等噪声，再使用 URL 解析和 HEAD/content-type 校验，不把代码或 Markdown 当媒体。

验收：单图、多图、拖入、网页复制、URL 粘贴、长 URL、非媒体文件均能进入正确视图；主图可持续查看且缩放平滑。

### 阶段三：Widget Market 与 Widget 介绍

涉及：`WidgetMarketPanel.swift`、`WidgetModels.swift`、`WidgetTaskClient.swift`、本地化资源。

1. Market 容器固定贴右侧，采用与 Information panel 同级的磨砂表面，可自主关闭，不遮挡 toolbar。
2. 点击 Widget card 进入介绍详情；只有点击运行/安装按钮才执行动作，不能让 card 点击无响应。
3. 详情页右上角使用 reload 图标，不显示“刷新”文字。
4. 安装状态以本地 registry 为准，并处理 manifest ID 变更：发现已安装 Widget 的 ID 与线上 ID 不一致时自动卸载旧记录，再允许安装新版本。
5. 安装后按钮变为“卸载”；Widget 只有一个 command 时直接显示一级 command，多 command 才显示二级菜单。
6. Widget Web 使用透明深色磨砂容器和项目 Loading，加载、完成、失败三种状态统一呈现。

验收：重启 App 后安装状态仍正确；card、详情、安装、卸载、reload、单 command 和多 command 路径均可操作。

### 阶段四：任务状态与结果回流

涉及：`WidgetTaskManager.swift`、`WidgetTaskCenterWindow.swift`、`WidgetTaskClient.swift`、`ImageInspectWindow.swift`。

1. 提交成功后立即创建本地 task record，并在 toolbar 任务按钮显示小红点。
2. 主图不被大面积 loading 遮挡；当前图片对应的缩略图显示暖琥珀呼吸灯，表示正在轮询。
3. 任务管理器重做为分段列表：全部、处理中、已完成、失败；每一行包含 Widget、输入图、进度、时间和可用操作。
4. task detail 展示提交、worker processing、下载输出的时间线，错误显示可执行的重试动作。
5. Widget 完成后，将结果作为新 item 插入原图缩略图右侧，标记“刚刚完成”和绿色完成标记；不自动抢主图焦点，点击结果缩略图后再切换。
6. 轮询结束、失败或取消后移除呼吸灯；红点仅在存在进行中任务时显示。

验收：提交、轮询、完成、失败、重试、取消、App 重启恢复都能保持任务状态；结果不会覆盖原图或打断用户当前查看。

### 阶段五：Base64、设置与首次启动

涉及：`OnboardingWindow.swift`、`PreferencesWindow.swift`、`StatusBarController.swift`、本地化资源。

1. 首次启动按当前 `OnboardingWindow` 视觉实现：580 × 580 深色磨砂窗口、Glance 图标、欢迎文案、输入监听/辅助功能/完全磁盘访问三项状态和 Continue 禁用逻辑。
2. 设置页沿用同一套 token，优先完成语言、快捷键、登录时启动、外观和剪贴板行为。
3. Base64 转图片与图片转 Base64 使用多行 area，不使用单行 input；明确校验、转换中、成功预览和失败原因。

验收：首次启动不出现白底；权限状态实时刷新；中英文切换后新增页面没有硬编码文案；Base64 长文本可粘贴和恢复。

### 阶段六：质量、回归与发布

1. 在新 UI 分支上先运行 `git diff --check`、Swift 构建和现有测试。
2. 为状态机补测试：Widget 安装状态、任务轮询、结果插入、URL/剪贴板内容分流、语言切换。
3. 手动回归矩阵：单图、多图、视频、代码/Markdown、拖入、URL、网页复制、Base64、Widget 安装/卸载、任务失败重试、深色窗口和权限引导。
4. 检查 VoiceOver、键盘操作、最小窗口尺寸和多显示器位置；动画支持 Reduce Motion。
5. 通过后再拆分提交：基础样式、预览工作台、Widget Market、任务中心、设置与本地化，便于回滚。

## 建议分支与提交顺序

建议从当前稳定版本创建：

```text
git switch -c feat/glance-ui-refresh
```

提交顺序：

1. `ui: add shared dark glass tokens and controls`
2. `ui: rebuild image inspect workbench`
3. `ui: rebuild widget market and widget web states`
4. `ui: rebuild task center and result thumbnail flow`
5. `ui: align onboarding preferences and base64 flows`
6. `test: cover ui state transitions and localization`

## 明确不在本轮做的事情

- 不改变 Widget 后端 API、worker 调度和审核流程。
- 不把首次启动权限流程改成新的产品逻辑，只做当前实现的视觉统一。
- 不强制主图自动切换到 Widget 结果。
- 不在当前分支提前合并或 push 新 UI。

## 当前落地状态与后续执行说明

设计稿不会被 `run.sh` 自动加载。Glance 主体是 Swift/AppKit 原生窗口，HTML 文件只作为视觉和交互规格；要看到完整新版 UI，必须把设计稿逐页转换为原生 `NSWindow`、`NSView`、约束和交互，而不是简单把 HTML 放进 WebView。

当前分支已经完成视觉 token、部分 Image Inspect / Video Inspect、任务详情面板、Widget Market 深色样式、共享 loading/error 基础组件，以及构建启动脚本修复。但目前仍是旧原生布局叠加局部新版样式，尚未完成所有页面的结构替换。

后续按以下顺序继续，每完成一页就通过 `./run.sh` 实机检查再进入下一页：

1. Image Inspect：顶部 toolbar、中央主图、右侧 Information、底部 filmstrip、任务状态和结果插入。
2. Video Inspect：视频画布、比较模式、播放控制、信息面板和 loading/error 状态。
3. Task Center：筛选分段、任务列表、右侧时间线详情、重试/取消和空态。
4. Widget Market / Widget Web：右侧详情、安装状态、单 command 展示、reload、loading/success/error。
5. Preferences、Base64、History：统一磨砂容器、表单层级、多行输入和状态反馈。
6. 全局收尾：中文/英文文案、空态/错误态统一、键盘与 VoiceOver、Reduce Motion、最小窗口尺寸和回归测试。

推荐保留原生 AppKit 实现。这样可以继续复用现有拖拽、快捷键、图片加载、Widget 任务和权限逻辑，避免维护一套与原生窗口脱节的 WebView UI。
