# Glance UI/UX Layout Exploration

## 最新可落地提案

- `glance-production-ui-v2.html`：针对当前 AppKit 架构制作的全 App 可交互设计稿。
- `GLANCE-PRODUCTION-UI-V2-SPEC.md`：窗口尺寸、状态、交互和现有 Swift 文件的落地映射。

这一版不参与 `run.sh` 构建。先评审设计，确认后再逐页迁移到生产代码。

这是基于 `ui-ux-pro-max` 生成的视觉方案草图，不包含生产代码。

打开 `glance-ui-flows.html` 可以查看四个核心画面；打开 `glance-full-app.html` 可以查看全 App 流程布局板：

1. 图片预览工作台：图片画布、信息栏、工具栏和底部缩略图。
2. Widget Market：Widget 卡片、安装状态和右侧详情面板。
3. 任务管理器：进行中、已完成和失败任务的层级与反馈。
4. Base64 转图片：多行输入区域、校验状态和转换结果。

全流程布局板补充了：

- 首次启动与权限沿用当前产品，不在新稿中改版。
- 媒体预览直接绘制 `glance-ui-flows.html` 的「01 · 图片预览工作台」结构。
- 右键方向菜单、单 command Widget 直达、代码/Markdown 非媒体分流。
- 右侧 Widget Market、详情介绍、安装/卸载和 reload 图标。
- 任务管理器的进行中、完成、失败、轮询红点和任务时间线。
- 提交任务后的主图、呼吸灯轮询、阶段进度、Widget Web Loading、成功结果和失败重试。
- Base64 area、设置/账号、加载和错误状态。

视觉方向：深色电影感画布、暖琥珀色主强调、磨砂黑玻璃层、Inter 字体、8px 间距节奏。交互控件保留明确焦点和状态，不使用颜色作为唯一状态提示。全流程板沿用 `design-taste-frontend` 的高质感桌面工作台方向，以及 `ui-ux-pro-max` 的状态覆盖、信息层级和响应式折叠原则。
