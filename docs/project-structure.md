# 项目结构

本文档说明 Glance 仓库的目录职责、核心源码分层和运行时流程。

## 顶层目录

```text
.
├── clients/                     # 客户端
│   ├── macos/
│   │   ├── Glance/              # 生产源码、资源、Xcode 工程与 build.sh
│   │   ├── scripts/             # 签名、打包、图标生成、非 UI 检查
│   │   ├── prototypes/          # 历史 macOS 技术实验；部分脚本会操作 UI
│   │   ├── legacy/              # 早期 ImageHoverPreview 工程残留
│   │   ├── Glance.app/          # 本地构建产物，忽略提交
│   │   └── dist/               # 本地 DMG，忽略提交
│   └── windows/                # 占位，尚无实现
├── server/                      # 服务端与任务执行
│   ├── GlanceService/          # Cloudflare Worker、D1 migrations、管理后台、测试
│   ├── glance-cli/             # Python CLI 与开发者 Worker
│   ├── widgets/                # Widget manifest 与处理代码
│   └── glance-cli-run.sh       # CLI 安装／命令入口
├── website/                     # 官网
│   ├── static/                 # 当前生产静态官网：src → build.py → public
│   ├── app/                    # 保留的 React / Vinext 网站实现
│   └── seo/                    # SEO、合规、内容、发布证据
├── docs/                        # 产品、架构、计费、审计、安装与历史文档
├── design/                      # 设计
│   ├── app/                    # App 页面、交互、规格与 Figma 插件
│   │   ├── layout/             # HTML 原型、Figma 导出、原生布局演示
│   │   └── specs/              # UI 规格与历史设计计划
│   ├── marketing/              # 宣传资料
│   │   ├── brand-assets/       # Logo、样例图片与品牌素材
│   │   ├── videos/             # 宣传／教程视频、脚本、音频、分镜
│   │   └── scripts/            # 宣传素材生成脚本
│   └── website/                # 官网设计截图与历史 HTML 方案
├── README.md                    # 仓库入口
├── spec.md                      # 系统规范与目录契约
├── AGENTS.md                    # 自动化代理规则入口
├── agent.md                     # 指向 AGENTS.md 的兼容入口
├── CLAUDE.md                    # 工程硬约束
└── run.sh / run / glance-cli-run.sh  # 保留原命令的轻量转发入口
```

当前目录契约见 [系统规范](../spec.md)，迁移映射见 [目录整理记录](repository-reorganization.md)。以下 macOS 源码分层为保留的技术说明。

## Glance 子项目

```text
clients/macos/Glance/
├── build.sh
├── project.yml
├── Info.plist
├── Glance.entitlements
├── Resources/
│   ├── Info.plist
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   ├── KeyboardMonitor.swift
│   ├── SelectedTextExtractor.swift
│   ├── PathDetector.swift
│   ├── FileNameResolver.swift
│   ├── FilenameCache.swift
│   ├── AnimatedImage.swift
│   ├── ImageLoader.swift
│   ├── ImageInspectWindow.swift
│   ├── PeekDiagnostics.swift
│   ├── PreviewPanel.swift
│   ├── ContentPanel.swift
│   ├── ContentViewerWindow.swift
│   ├── HistoryManager.swift
│   ├── HistoryWindow.swift
│   ├── Preferences.swift
│   ├── PreferencesWindow.swift
│   ├── PermissionManager.swift
│   ├── OnboardingWindow.swift
│   ├── ScreenManager.swift
│   ├── ErrorTooltip.swift
│   ├── FileTypeIcon.swift
│   ├── Logger.swift
│   └── PreviewPanelPreview.swift
└── Glance.xcodeproj/
```

## 源码分层

| 模块 | 文件 | 职责 |
| --- | --- | --- |
| 应用入口 | `main.swift` | 创建 `NSApplication`，设置 accessory 模式并挂载 `AppDelegate`。 |
| 生命周期编排 | `AppDelegate.swift` | 初始化组件、监听通知、执行预览主流程、处理偏好和权限入口。 |
| 菜单栏 | `StatusBarController.swift` | 创建菜单栏图标、偏好设置、历史记录、权限、缓存清理、主题切换和退出菜单。 |
| 热键监听 | `KeyboardMonitor.swift` | 使用 `CGEventTap` 监听全局修饰键，按偏好设置判断预览模式是否激活。 |
| 文本读取 | `SelectedTextExtractor.swift` | 优先通过 AX 读取当前选中文本，必要时模拟 Cmd+C 并恢复剪贴板。 |
| 路径识别 | `PathDetector.swift` | 用正则和扩展名分类识别 URL、本地路径、相对路径、裸文件名和网页。 |
| 文件名解析 | `FileNameResolver.swift` | 使用 Spotlight 查询裸文件名/相对路径，必要时执行受限文件系统回退搜索。 |
| 解析缓存 | `FilenameCache.swift` | 将裸文件名解析结果持久化到 Application Support，最多保留 500 条。 |
| 动图与剪贴板 | `AnimatedImage.swift` | 按内容识别 GIF/APNG/WebP 动画，后台逐帧解码并按时序播放；不可见时暂停，剪贴板导入保留原始数据。 |
| 媒体加载 | `ImageLoader.swift` | 异步加载图片、缓存缩略图、探测视频尺寸/时长，生成内容卡片信息。 |
| 图片检查 | `ImageInspectWindow.swift` | 混合内容 Focus/Browse（图片 + 行内预览 txt/Markdown/PDF/网页）、双图并排/滑杆 Compare、同步视口、技术属性差异、拖入追加/替换、旋转/复制/快速保存/导出 PNG/JPG/WebP 和 OCR 文字识别。 |
| 本地诊断 | `PeekDiagnostics.swift` | 仅在本机记录匿名聚合计数与首帧耗时，不保存文本、路径或 URL。 |
| 预览面板 | `PreviewPanel.swift` | 浮动 `NSPanel`，负责单卡片、网格、视频播放器、文件卡片和点击行为。 |
| 内容面板 | `ContentPanel.swift` | 非激活浮动内容面板，显示网页、Markdown、文本、PDF 和图片详情。 |
| 独立查看器 | `ContentViewerWindow.swift` | 标准窗口查看 Markdown、文本、PDF、网页，并支持本地文本编辑保存。 |
| 历史记录 | `HistoryManager.swift`、`HistoryWindow.swift` | 保存最近预览记录，并在历史窗口中复用预览卡片展示。 |
| 偏好设置 | `Preferences.swift`、`PreferencesWindow.swift` | 管理 UserDefaults、热键、主题、最大预览尺寸、剪贴板回退等设置。 |
| 权限 | `PermissionManager.swift`、`OnboardingWindow.swift` | 检查和引导 Input Monitoring、Accessibility、Full Disk Access 权限。 |
| 窗口定位 | `ScreenManager.swift` | 根据鼠标所在屏幕计算不越界的面板位置。 |
| 错误提示 | `ErrorTooltip.swift` | 在无法识别或加载失败时显示浮动提示。 |
| 文件图标 | `FileTypeIcon.swift` | 为 Markdown、代码、PDF、网页和其他文件生成程序化图标。 |
| 日志 | `Logger.swift` | 同时写入 os_log、标准输出和 Application Support 下的 `app.log`。 |
| 调试 | `PreviewPanelPreview.swift` | SwiftUI 预览辅助；旧 Debug 文本输入窗口已移除。 |

## 运行时流程

```text
App 启动
  -> AppDelegate 初始化菜单栏、热键、路径识别、加载器和面板
  -> PermissionManager 检查 Input Monitoring / Accessibility
  -> KeyboardMonitor 开始监听 Option + Space 或自定义快捷键
  -> 用户选中文本并按住热键
  -> SelectedTextExtractor 获取选中文本
  -> PathDetector 提取已解析路径和未解析 token
  -> FileNameResolver 解析裸文件名或相对路径
  -> HistoryManager 记录已解析条目
  -> ImageLoader 加载图片、视频或内容占位信息
  -> PreviewPanel 展示 Peek
  -> 单击图片时复用已加载内容进入 ImageInspectWindow
  -> 其他内容由 ContentPanel / ContentViewerWindow 展示
```

## 构建相关文件

| 文件 | 说明 |
| --- | --- |
| `clients/macos/Glance/build.sh` | 构建脚本。默认 Release，可传入 `Debug`。构建成功后复制 `Glance.app` 到 `clients/macos/`。 |
| `clients/macos/Glance/project.yml` | XcodeGen 配置，声明 bundle id、macOS deployment target、源码、资源和构建目录。 |
| `clients/macos/Glance/Glance.xcodeproj/` | 当前可直接使用的 Xcode 工程。 |
| `clients/macos/Glance/Info.plist` | 应用 bundle 信息，包含 `LSUIElement=true`，因此应用作为菜单栏工具运行。 |
| `clients/macos/Glance/Glance.entitlements` | 当前调试 entitlement，包含 `com.apple.security.get-task-allow`。 |
| `run.sh` | 本地运行辅助脚本，会先停止已有 Glance 进程，再打开 `clients/macos/Glance.app` 并 tail 日志。 |

## 运行时持久化

Glance 将运行数据写入：

```text
~/Library/Application Support/Glance/
```

| 文件 | 来源 | 说明 |
| --- | --- | --- |
| `app.log` | `Logger.swift` | 应用日志。 |
| `history.json` | `HistoryManager.swift` | 最近预览记录，最多 200 条。 |
| `filename-cache.json` | `FilenameCache.swift` | 裸文件名解析缓存，最多 500 条。 |
| `debug_marker.txt` | `AppDelegate.swift` | Debug 启动标记。 |

## Prototype 目录

`clients/macos/prototypes/` 保存早期实验脚本，主要用于验证 macOS 系统能力：

- `main.swift`、`diagnose.swift`、`latency.swift`：Accessibility 与性能验证。
- `movemouse.swift`、`click.swift`、`press_esc.swift`：鼠标和键盘事件验证。
- `findwindows.swift`、`listwindows.swift`、`tree.swift`、`fulltree.swift`：窗口和 AX 树调试。
- `run_tests.sh`、`run_content_tests.sh`、`run_window_tests.sh`、`run_diagnostics.sh`：原型测试入口。
- `test.html`：浏览器内容提取测试页面。

这些脚本不是主应用运行所必需的，但对排查 macOS 权限、文本提取和窗口行为仍有参考价值。
