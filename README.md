# Glance

Glance 是一个原生 macOS 菜单栏工具，用来从任意应用中选中的文本里识别图片、视频、文档、网页 URL 或本地文件路径，并在鼠标附近快速打开预览或内容查看器。

这个项目当前的主实现位于 `Glance/`。仓库根目录保留运行脚本、历史验证资料、界面截图和早期原型脚本。

## 主要能力

- 全局热键触发：默认使用 `Option + Space` 显示或关闭 Peek，可在偏好设置中自定义。
- 跨应用读取选中文本：优先使用 Accessibility API，失败时可通过剪贴板回退读取。
- 多类型路径识别：支持 HTTP(S) URL、裸域名、本地绝对路径、`~/` 路径、`file://`、相对路径和裸文件名。
- Spotlight 文件解析：当文本只有 `screenshot.png` 或 `docs/readme.md` 这类不完整路径时，会尝试通过 Spotlight 查找实际文件。
- 媒体预览：图片和视频在浮动预览面板中展示，多个命中会以网格方式展示。
- 内容查看：Markdown、文本/代码、PDF、网页可在内置内容面板中查看，部分本地文本文件支持切换编辑并保存。
- 其他文件入口：Office、设计稿、压缩包、音频、字体、安装包等不可内联预览的文件会显示为文件卡片，点击后打开或在 Finder 中定位。
- 历史记录：菜单栏中可打开 Preview History，查看最近预览过的内容。
- 权限引导：首次启动会提示 Input Monitoring 和 Accessibility 权限。
- 多显示器定位：预览窗口会根据当前鼠标所在屏幕自动避让边缘。
- 图片深度检查：单击 Peek 中的图片进入 Image Inspect，支持适应窗口、100%、指针中心缩放和平移。
- 多图浏览与比较：多张明确图片路径使用缩略网格；Finder 同时打开两张图片会直接进入并排或滑杆比较，并显示技术属性差异。
- Finder 文件入口：可通过“打开方式 > Glance”或将 Glance 设为图片查看器打开一张或多张图片。

## 使用方式

1. 启动 `Glance.app`，它会作为菜单栏应用运行，不显示 Dock 图标。
2. 按提示授予 Input Monitoring 和 Accessibility 权限。
3. 在任意应用中选中一段包含 URL、路径、文件名或域名的文本。
4. 按 `Option + Space` 触发 Peek；再次按相同快捷键可以关闭。
5. 使用 Peek 快速确认内容；单击图片进入 Image Inspect 查看细节。
6. 在 Finder 中用 Glance 打开两张图片可直接比较，打开三张以上则进入同组浏览。

## 支持内容

图片：

`jpg`、`jpeg`、`png`、`gif`、`webp`、`heic`、`heif`、`bmp`、`tiff`、`tif`

视频：

`mp4`、`mov`、`m4v`、`webm`、`mkv`、`avi`

文档和文本：

`md`、`markdown`、`txt`、`json`、`xml`、`yaml`、`html`、`css`、`js`、`ts`、`swift`、`py`、`go`、`rs`、`sh`、`sql`、`log` 等常见文本、配置和代码格式。

其他：

PDF、网页 URL，以及常见 Office 文档、设计稿、音频、压缩包、安装包、字体、相机 RAW 文件等。

## 运行环境

- macOS 12.3 或更高版本
- Xcode 14 或更高版本
- 可选：XcodeGen，用于从 `Glance/project.yml` 重新生成 Xcode 工程
- 系统权限：Input Monitoring、Accessibility
- 可选权限：Full Disk Access，仅用于 Spotlight 找不到文件时的受控文件系统回退搜索

## 快速开始

构建 Release 版本：

```bash
./Glance/build.sh
```

构建完成后，脚本会把应用复制到仓库根目录：

```text
./Glance.app
```

启动应用并跟踪日志：

```bash
./run.sh
```

构建 Debug 版本：

```bash
./Glance/build.sh Debug
```

Debug 构建会启用 `DebugInputWindow`，便于直接输入样本文本测试路径识别和预览流程。

## 手动构建

如果需要直接使用 Xcode 工具链：

```bash
cd Glance
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Release -derivedDataPath ./DerivedData build
```

如果安装了 XcodeGen，可以先重新生成工程：

```bash
cd Glance
xcodegen generate
```

## 权限说明

Glance 依赖 macOS TCC 权限：

- Input Monitoring：监听全局修饰键状态，用于识别热键触发。
- Accessibility：读取当前应用中的选中文本。
- Full Disk Access：不是核心功能必需权限，只在 Spotlight 未命中并需要枚举 Desktop、Documents、Downloads 等目录时提示。

可在 System Settings > Privacy & Security 中管理这些权限。开发时如需重置权限，可使用：

```bash
tccutil reset ListenEvent com.glance.app
tccutil reset Accessibility com.glance.app
tccutil reset All com.glance.app
```

## 核心流程

1. `KeyboardMonitor` 通过 `CGEventTap` 在专用线程监听默认 `Option + Space` 或用户自定义快捷键。
2. `AppDelegate` 收到热键激活通知，检查权限和偏好设置。
3. `SelectedTextExtractor` 从当前焦点控件读取选中文本，必要时用剪贴板回退。
4. `PathDetector` 从文本中提取 URL、本地路径、相对路径或裸文件名。
5. `FileNameResolver` 对未解析的文件名/相对路径执行 Spotlight 查询和缓存。
6. `ImageLoader` 加载图片、探测视频元数据，或生成可打开文件的占位信息。
7. `PreviewPanel` 负责不抢焦点的 Peek；`ImageInspectWindow` 负责图片 Focus、Browse 和 Compare；其他内容继续由 `ContentPanel`、`ContentViewerWindow` 展示。
8. `HistoryManager` 将已解析的预览记录写入 Application Support。

## 运行数据

运行时数据保存在：

```text
~/Library/Application Support/Glance/
```

主要文件：

- `app.log`：应用日志。
- `history.json`：预览历史记录。
- `filename-cache.json`：裸文件名到绝对路径的解析缓存。
- `debug_marker.txt`：启动调试标记。

## 相关文档

- [项目结构](PROJECT_STRUCTURE.md)
- [Glance 子项目入口](Glance/)
- [历史实现计划](.sisyphus/plans/mac-image-hover-preview.md)
