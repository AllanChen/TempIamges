# Glance 系统设计与技术规范 (Specification)

## 1. 项目概述 (Overview)

Glance 是一款面向 macOS 的原生菜单栏效率工具应用（`LSUIElement = true`，无 Dock 图标）。
其核心功能是在系统任意应用内，通过全局修饰键（默认 `Option` 或 `Control`）触发，自动获取当前光标或焦点控件所选中的文本内容，智能解析其中的路径、URL、文件名或裸域名，并在屏幕中央/就近位置提供即时、无缝的多媒体预览、内容阅读与快速编辑能力。

---

## 2. 系统架构与模块分工 (System Architecture)

系统采用典型的 Cocoa/AppKit 事件驱动与管道化设计，各层各司其职，遵循单向数据流与弱引用委托机制：

```
[ 用户触发修饰热键 ] 
       │
       ▼
[ KeyboardMonitor (CGEventTap) ]
       │  (异步通知: previewModeDidActivate)
       ▼
[ AppDelegate (调度中枢) ]
       │
   ┌───┴────────────────────────────────────────┐
   ▼                                            ▼
[ PermissionManager ]                [ SelectedTextExtractor ]
 (检查 Input/AX 权限)                 (AXUIElement 优先 -> 剪贴板 Cmd+C 回退)
                                                │
                                                ▼ (选中文本 string)
                                     [ PathDetector (正则/规则匹配) ]
                                                │
                 ┌──────────────────────────────┴──────────────────────────────┐
                 ▼ (精确/完整路径)                                               ▼ (裸文件名 / 相对路径)
          [ ImageLoader ]                                              [ FileNameResolver (Spotlight/FS) ]
                 │                                                             │
                 │                                                     [ FilenameCache (LRU持久化) ]
                 │                                                             │
                 └──────────────────────────────┬──────────────────────────────┘
                                                ▼
                                    [ HistoryManager ] (持久化历史)
                                                │
                                                ▼
                   ┌────────────────────────────┴────────────────────────────┐
                   ▼ (多文件 / 纯媒体 / 列表)                                  ▼ (单文件即时直通)
          [ PreviewPanel ]                                             [ ContentPanel ]
   (单卡片 / 分栏侧边栏 / 缩略图 / 视频)                       (Markdown / 代码高亮 / Web / PDF / 编辑保存 / Git Diff)
```

### 核心模块清单

| 模块 | 源码文件 | 核心职责 |
|---|---|---|
| **应用入口** | `main.swift` | 注册默认语言偏好，设置 `.accessory` 模式，挂载 `AppDelegate`。 |
| **生命周期编排** | `AppDelegate.swift` | 响应热键与系统通知，编排文本提取、路径探测、文件解析、面板展示与深层链接 (Deep Link)。 |
| **全局键盘监听** | `KeyboardMonitor.swift` | 独立线程维护 `CGEventTap`，低开销追踪按键状态，解耦主线程以防全局死锁。 |
| **文本提取** | `SelectedTextExtractor.swift` | 跨进程提取选中文本：首选 Accessibility (`kAXSelectedText`)，超时回退剪贴板模拟合成按键。 |
| **路径与实体探测** | `PathDetector.swift` | 综合运用正则与规则识别绝对路径、相对路径、`~` 路径、`file://`、HTTP(S) URL、裸域名及裸文件名。 |
| **文件名智能解析** | `FileNameResolver.swift` | 针对不完整路径分层搜索：内存缓存 -> 快速浅层遍历 -> Spotlight (`mdfind`) & 深度遍历。 |
| **解析缓存** | `FilenameCache.swift` | 基于 LRU 策略持久化已解析的 token -> 绝对路径映射，限额 500 条。 |
| **媒体加载器** | `ImageLoader.swift` | 异步加载/缩略图生成、解码限制尺寸 (800px)、提取视频时长与尺寸、并发控制 (`loadSemaphore`)。 |
| **悬浮预览面板** | `PreviewPanel.swift` | 悬浮 `NSPanel`（`.floating`, `.nonactivatingPanel`），支持 Single Card、Split View，集成毛玻璃效果。 |
| **内容查看面板** | `ContentPanel.swift` | 沉浸式查看器：内置 WKWebView（网页/Markdown/PDF）、NSTextView（代码/高亮/编辑保存）、Git Diff 对比。 |
| **屏幕与定位管理器** | `ScreenManager.swift` | 计算面板坐标，防跨屏越界、自适应 Dock/MenuBar 可视区域，支持居中收容。 |
| **历史记录管理** | `HistoryManager.swift`, `HistoryWindow.swift` | 持久化记录最近 200 次预览历史 (`history.json`)，支持检索与复看。 |
| **权限管理与引导** | `PermissionManager.swift`, `OnboardingWindow.swift` | 检查并引导系统权限：Input Monitoring、Accessibility、Full Disk Access (FDA)。 |
| **用户偏好设置** | `Preferences.swift`, `PreferencesWindow.swift` | 控制快捷键、深浅主题切换、多语言（中/英）、剪贴板回退及开机自启。 |
| **用户认证与协同** | `AuthManager.swift`, `LoginPanel.swift` | 邮箱验证码登录、Google OAuth、深度链接 `glance://auth/callback` 回调与会话持久化。 |
| **设计系统与样式** | `PanelStyle.swift`, `FileTypeIcon.swift` | 统一的磨砂深色毛玻璃 (Frosted Dark Glass)、Hairline、图标、字体/排版 Tokens。 |

---

## 3. 详细技术规范 (Technical Specifications)

### 3.1 全局热键监听规范 (CGEventTap Hard Constraints)

为保障 macOS 系统级稳定性，`KeyboardMonitor` 必须严格遵守以下规范：
1. **独立线程与 RunLoop**：`CGEventTap`（`headInsertEventTap`）绝不能挂载在主线程 RunLoop。必须开辟专用 `Thread`（QoS: `.userInteractive`），并在其中维持 `CFRunLoop`。
2. **非阻塞回调 (Non-blocking)**：Callback 仅做修饰键 bitmask 计算与轻量状态更新，立刻通过 `passUnretained(event)` 返回，耗时或 UI 构建必须通过 `DispatchQueue.main.async` 派发。
3. **超时与停用恢复**：在收到 `tapDisabledByTimeout` 或 `tapDisabledByUserInput` 事件时，调用 `CGEvent.tapEnable(tap:enable:true)` 重新使能。
4. **并发安全性**：修饰键持有状态由 `NSLock` 保护，供 tap 线程与主线程安全读取。

### 3.2 选中文本提取规范 (Text Extraction)

1. **Accessibility 首选**：
   - 构造 `AXUIElementCreateSystemWide()`，获取 `kAXFocusedUIElementAttribute`。
   - 读取 `kAXSelectedTextAttribute`，同时尝试通过 `kAXBoundsForRangeParameterizedAttribute` 获取选择文本的屏幕坐标。
   - 设定 1.0 秒超时保护（通过 `DispatchSemaphore`）。
2. **剪贴板安全回退**：
   - 当 AX 提取为空或超时，保存当前剪贴板快照（类型与数据）。
   - 模拟 `Cmd + C`（合成按键 `kVK_ANSI_C`，标记 `.maskCommand` 发送到 `.cghidEventTap`）。
   - 轮询 `NSPasteboard.general.changeCount`，设定 0.25 秒截止时限。
   - 读取提取文本后，立刻还原剪贴板快照，避免破坏用户原有剪贴板历史。

### 3.3 路径与格式识别规范 (Path Detection & Classification)

1. **支持的格式类型分类**：
   - **Image**：`jpg`, `jpeg`, `png`, `gif`, `webp`, `heic`, `heif`, `bmp`, `tiff`, `tif`
   - **Video**：`mp4`, `mov`, `m4v`, `webm`, `mkv`, `avi`
   - **Markdown**：`md`, `markdown`
   - **Code/Text**：涵盖编程语言源码（`swift`, `py`, `js`, `ts`, `go`, `rs`, `c`, `cpp` 等）、配置文件（`json`, `yaml`, `toml`, `xml`, `ini` 等）、数据日志（`sql`, `log`, `csv` 等）
   - **PDF**：`pdf`
   - **Other (不可内联预览)**：Office 格式（`doc`, `xls`, `ppt` 等）、设计文件（`psd`, `sketch`, `ai` 等）、压缩包（`zip`, `tar`, `dmg` 等），渲染文件卡片与定位/打开入口。
   - **Folder**：本地合法目录路径。
2. **正则表达式优先级**：
   - 优先级 0：`HTTP/HTTPS`（支持宽容解析及容错处理如 `https//`）。
   - 优先级 1：`file://`。
   - 优先级 2：`~/...` 家目录路径。
   - 优先级 3：`/...` 绝对路径。
   - 优先级 4：相对路径（含 `/`，如 `docs/readme.md`）。
   - 优先级 5：裸域名（无 Scheme，如 `github.com`）。
   - 后备候选：裸文件名（Stem $\ge 2$ 字符 + 扩展名）以及无扩展名词项（长度 3~30 字符）。

### 3.4 文件搜索分级规范 (Search Rules & Cascading)

搜索管道分为三层，满足速度与召回率的平衡：
- **Layer 1: 内存持久化 LRU 缓存（纳秒级）**：
  - 上限 500 条，键为规范化（去除引号、首尾空白、尾随标点）后的 token。
  - 命中后校验文件是否存在，有效则立即返回。
- **Layer 2: 快速文件系统浅层遍历（毫秒级）**：
  - 时限 0.5s，深度 $\le 10$，遍历目录数 $\le 20,000$。
  - 尝试拼接常见候选根路径（CWD、Desktop、Documents、Downloads）。
- **Layer 3: 并发深度搜索与 Spotlight（亚秒级）**：
  - 并发执行 3A (`mdfind -name <stem> -onlyin ~`)、3B (`mdfind kMDItemFSName == "<stem>"cd -onlyin ~`)、3C (深度目录树遍历，时限 1.0s，深度 $\le 12$)。
  - 采用 DispatchGroup 并发执行，总超时 1.5 秒。
  - 黑名单规避：自动跳过 `/.Trash/`, `/Library/Caches/`, `/.git/`, `node_modules`, `DerivedData` 等。
  - 排序优先级：Desktop/Documents/Downloads 优先 > 家目录下优先 > 最近修改优先 > 路径较短优先。

### 3.5 界面与交互规范 (UI & Interaction)

1. **视觉设计系统 (Design System)**：
   - 采用深色磨砂毛玻璃 (`NSVisualEffectView`, `material = .hudWindow`, `appearance = .vibrantDark`) 叠加 30% 黑色遮罩。
   - 面板外框应用 1px 细线边框（`hairline = rgba(255, 255, 255, 0.10)`），统一圆角（Panel: 20px）。
2. **窗口排布与屏幕适配 (Window Placement)**：
   - 面板默认显示在光标所在屏幕，经 `ScreenManager` 裁剪与约束，禁止跨出可视屏幕区域。
   - 联动吸附：当 `PreviewPanel` 处于展示状态且 `ContentPanel` 打开时，通过 `NSWindow.didMoveNotification` 进行坐标对齐，避免轮询定时器。
3. **快捷交互动作**：
   - 单命中直通（Single-hit shortcut）：若解析结果为单个文本/代码/PDF/网页，直接调用 `ContentPanel` 渲染。
   - 键盘控制：`Esc` 键全局与局部监听，一键关闭浮动面板；上下方向键（Arrow Up/Down）支持列表快速选定。
   - 文本编辑与保存：针对本地可写文本/代码文件，`ContentPanel` 支持即时编辑，`Cmd + S` 写回磁盘。
   - Git 差异对比：检测所在工程的 Git 状态，若存在修改，提供轻量级 Diff 对比窗口。

---

## 4. 数据与持久化规范 (Data Storage)

所有持久化数据统一存储在用户的 Application Support 目录下：
`~/Library/Application Support/Glance/`

| 存储项 | 文件路径 | 格式与策略 |
|---|---|---|
| 运行日志 | `Glance/app.log` | 文本追加写入，同时分发至 Console/os_log。 |
| 历史记录 | `Glance/history.json` | JSON 格式，ISO-8601 时间戳，最多存储 200 条，I/O 独立队列写盘。 |
| 解析缓存 | `Glance/filename-cache.json` | 键值对字典（Token -> FilePath），限额 500 条 LRU。 |
| 启动调试标记 | `Glance/debug_marker.txt` | 记录进程冷启动时间与标记。 |
| 用户偏好 | `UserDefaults` (Suite: `com.glance`) | 存储快捷键组合、界面主题、首选语言、窗口拖动尺寸记录等。 |

---

## 5. 权限体系规范 (Permissions & TCC)

| 权限类型 | 适用 API | 核心用途 | 缺省降级策略 |
|---|---|---|---|
| **Input Monitoring** | `CGRequestListenEventAccess()` | 全局监听 Control/Option 热键修饰符状态。 | 应用无法响应全局热键唤起。 |
| **Accessibility (AX)** | `AXIsProcessTrustedWithOptions()` | 获取聚焦应用的当前选中文本及选区坐标。 | 降级为剪贴板模式 (`Cmd + C`) 提取。 |
| **Full Disk Access (FDA)** | 读取受限路径（如 Safari 书签 DB）探测 | 深度搜索 Desktop/Documents/Downloads 受限目录。 | 仅限 Spotlight 索引返回或已授权目录，并在必要时弹窗引导。 |

---

## 6. 构建与工程规范 (Build & Engineering Rules)

1. **部署目标**：macOS 12.3+，架构支持 Apple Silicon (arm64) 与 Intel (x86_64)。
2. **构建方式**：
   - 自动化构建：`./Glance/build.sh [Release|Debug]`，产物打包生成 `Glance.app`。
   - 工程维护：支持使用 `xcodegen` 读取 `Glance/project.yml` 重新生成 `Glance.xcodeproj`。
3. **工程红线约束**：
   - 严格禁止在主线程执行同步 I/O、`semaphore.wait()` 或网络请求。
   - `CGEventTap` 回调必须极简并运行在专属线程，禁止在回调内构建 UI。
   - 窗口放置必须使用 `ScreenManager`，杜绝鼠标硬锚定导致的窗口出界。
   - 必须复用 `PanelStyle.swift` 规范代币（Tokens），不得随意硬编码视图颜色。
   - 自动化构建执行遵循用户控制原则，严禁自发执行编译和改动构建配置。

---

## 7. 开图功能规范 (Image Viewer & Compare Feature)

本章节定义 Glance 的「开图」扩展功能：支持系统级双击打开图片、详细元数据查看、以及多图并排对比。

### 7.1 功能定位与设计原则

1. **定位**：作为 Glance 现有悬浮预览/内容查看器的自然延伸，而非独立看图应用。
2. **核心场景**：
   - 双击图片文件直接用 Glance 打开查看（替代 Preview.app）。
   - 框选多张图片后用 Glance 打开，进入并排对比模式。
   - 在现有热键流程中，选中多个图片路径时提供「对比模式」入口。
3. **设计原则**：
   - 复用现有 `PanelStyle` 深色毛玻璃视觉规范。
   - 复用 `ScreenManager` 窗口定位与边界约束逻辑。
   - 保持轻量、快速响应，不引入重型依赖。

### 7.2 触发入口规范 (Entry Points)

| 入口方式 | 触发条件 | 行为 |
|---|---|---|
| **文件系统关联** | 用户双击图片文件，或右键选择「用 Glance 打开」 | 启动 Glance 并直接展示图片查看器 |
| **多文件打开** | Finder 中框选 2~4 张图片，回车或右键用 Glance 打开 | 启动并进入并排对比模式 |
| **热键流程扩展** | 选中文本包含多个图片路径，按热键触发 | `PreviewPanel` 工具栏显示「对比」按钮，点击进入对比模式 |

#### 7.2.1 Info.plist 配置

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>
    <string>Image</string>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSHandlerRank</key>
    <string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>public.image</string>
      <string>public.jpeg</string>
      <string>public.png</string>
      <string>public.heic</string>
      <string>com.compuserve.gif</string>
      <string>org.webmproject.webp</string>
      <string>public.tiff</string>
      <string>com.microsoft.bmp</string>
    </array>
  </dict>
</array>
```

#### 7.2.2 AppDelegate 扩展

```swift
// 实现文件打开委托
func application(_ application: NSApplication, open urls: [URL]) {
    let imageURLs = urls.filter { ImageLoader.supportedExtensions.contains($0.pathExtension.lowercased()) }
    guard !imageURLs.isEmpty else { return }
    
    if imageURLs.count == 1 {
        // 单图：直接打开图片查看器
        ImageViewerController.shared.show(url: imageURLs[0])
    } else {
        // 多图：进入并排对比模式
        ImageCompareController.shared.show(urls: Array(imageURLs.prefix(4)))
    }
}
```

### 7.3 多图并排对比规范 (Side-by-Side Compare)

#### 7.3.1 布局规则

| 图片数量 | 布局方式 | 说明 |
|---|---|---|
| 2 张 | 左右分屏 (50% / 50%) | 支持切换为上下分屏 |
| 3 张 | 2×2 网格，右下留空 | 或 1+2 布局（左大右双小） |
| 4 张 | 2×2 四宫格 | 对称布局 |

#### 7.3.2 视口同步联动 (Synced Viewport)

核心交互亮点：所有视口的缩放与平移保持同步，便于精细对比细节。

```swift
/// 视口协调器：管理多个 ImageView 的变换同步
class ViewportCoordinator {
    private var imageViews: [ZoomableImageView] = []
    private var isLocked: Bool = true  // 默认锁定同步
    
    /// 同步缩放：所有视口以各自中心按相同倍率缩放
    func syncZoom(scale: CGFloat, from source: ZoomableImageView) {
        guard isLocked else { return }
        for view in imageViews where view !== source {
            view.setZoom(scale, animated: false)
        }
    }
    
    /// 同步平移：所有视口按相同像素偏移移动
    func syncPan(delta: CGPoint, from source: ZoomableImageView) {
        guard isLocked else { return }
        for view in imageViews where view !== source {
            view.pan(by: delta, animated: false)
        }
    }
    
    /// 切换锁定状态
    func toggleLock() -> Bool {
        isLocked.toggle()
        return isLocked
    }
}
```

#### 7.3.3 交互操作

| 操作 | 手势/快捷键 | 行为 |
|---|---|---|
| 缩放 | `Cmd + 滚轮` / 双指捏合 | 所有视口同步缩放（锁定时） |
| 平移 | 拖拽 | 所有视口同步平移（锁定时） |
| 切换锁定 | 工具栏按钮 / `Cmd + L` | 解锁后可独立调整单个视口 |
| 切换布局 | 工具栏按钮 | 左右 ↔ 上下分屏切换 |
| 重置视口 | `Cmd + 0` | 所有视口恢复 Fit-to-View |
| 关闭 | `Esc` | 关闭对比窗口 |

### 7.4 图片元数据面板规范 (Image Inspector)

#### 7.4.1 触发方式

- 工具栏 `(i)` 按钮
- 快捷键 `Cmd + I`
- 从右侧滑出半透明毛玻璃抽屉

#### 7.4.2 元数据字段

| 分类 | 字段 | 来源 |
|---|---|---|
| **基础信息** | 分辨率 (宽×高)、色彩空间、位深、Alpha 通道、文件体积、格式 | `CGImageSource` |
| **EXIF 拍摄信息** | 相机型号、镜头、光圈、快门、ISO、焦段、拍摄时间 | `kCGImagePropertyExifDictionary` |
| **GPS 地理位置** | 经纬度、海拔 | `kCGImagePropertyGPSDictionary` |
| **文件信息** | 完整路径、创建时间、修改时间 | `FileManager` |

#### 7.4.3 元数据提取实现

```swift
import ImageIO

struct ImageMetadata {
    let dimensions: CGSize
    let colorSpace: String?
    let bitDepth: Int?
    let hasAlpha: Bool
    let fileSize: Int64
    let format: String
    
    // EXIF
    let cameraMake: String?
    let cameraModel: String?
    let lens: String?
    let aperture: Double?
    let shutterSpeed: String?
    let iso: Int?
    let focalLength: Double?
    let dateTaken: Date?
    
    // GPS
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    
    /// 从 URL 提取元数据（纳秒级，基于 ImageIO）
    static func extract(from url: URL) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        
        // ... 解析各字段
        return ImageMetadata(...)
    }
}
```

#### 7.4.4 对比模式下的差异高亮

当并排对比两张图片时，Inspector 面板自动对比并高亮差异项：

- 分辨率不同：用醒目颜色标注（如橙色）
- 文件体积差异：显示差值百分比
- 格式不同：并排显示两种格式
- EXIF 差异：逐项对比，差异项高亮

### 7.5 新增模块清单

| 模块 | 源码文件 | 核心职责 |
|---|---|---|
| **图片查看控制器** | `ImageViewerController.swift` | 单图查看入口，管理窗口生命周期 |
| **图片对比控制器** | `ImageCompareController.swift` | 多图对比入口，管理布局与视口协调 |
| **可缩放图片视图** | `ZoomableImageView.swift` | 支持缩放、平移、手势的图片视图组件 |
| **视口协调器** | `ViewportCoordinator.swift` | 管理多视口的同步缩放与平移 |
| **元数据提取器** | `ImageMetadataExtractor.swift` | 基于 ImageIO 提取 EXIF/GPS/基础元数据 |
| **元数据面板** | `ImageInspectorPanel.swift` | 右侧滑出的元数据抽屉视图 |

### 7.6 窗口与视觉规范

1. **窗口类型**：`NSPanel`，样式与 `ContentPanel` 一致（`.titled`, `.closable`, `.resizable`, `.fullSizeContentView`）。
2. **默认尺寸**：
   - 单图查看：800×600，自适应图片比例
   - 双图对比：1200×700
   - 四图对比：1400×900
3. **最小尺寸**：600×400
4. **视觉风格**：复用 `PanelStyle.makeFrostedBase()` 深色毛玻璃背景。
5. **工具栏**：顶部工具栏包含：缩放控制、布局切换、锁定开关、Inspector 按钮、关闭按钮。
