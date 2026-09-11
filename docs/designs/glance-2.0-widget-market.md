# Glance 2.0：Widget Market 与媒体任务平台

状态：PLANNED
版本：2.0
更新时间：2026-09-10

## 1. 产品定位

Glance 2.0 是一个图片、视频快速查看和处理入口。用户可以在 Widget Market 中发现需要的媒体处理能力，点击加载后将 Widget 挂载到 Glance，再从当前图片或视频窗口的右键菜单、主菜单中直接调用。

核心体验：

```text
Market 发现 Widget
    ↓
点击加载
    ↓
Glance 保存 Widget 安装信息
    ↓
图片/视频窗口右键选择
    ↓
选择一个 Command
    ↓
上传媒体并创建云端任务
    ↓
Glance 轮询任务状态
    ↓
展示结果并导出副本
```

第一期 Market 中的 Widget 全部由 Glance 官方提供。这样可以验证 Market、安装、菜单入口、任务协议和结果展示，而不需要一开始解决第三方生态冷启动。

## 2. Widget 与 Command 模型

一个 Widget 可以只包含一个功能，也可以包含多个相关功能。

```text
Background Removal Widget
└── Remove Background

Film Filters Widget
├── Black & White
├── Vintage
└── Cinematic
```

Widget 不是下载到本机执行的程序，而是一个声明式能力描述。Market 安装的是 Manifest、图标和元数据，不安装 Swift、动态库、Node.js 或任意本地可执行代码。

Manifest 至少包含：

- Widget ID、名称、版本、作者和图标。
- 支持的图片/视频类型及 MIME 类型。
- 一个或多个 Command。
- 每个 Command 的参数 Schema。
- 输入和输出类型。
- 云端任务类型。
- 是否上传媒体、文件限制和隐私提示。
- 最低 Glance 版本和 Manifest 签名。

示例：

```json
{
  "id": "com.glance.filters",
  "version": "1.0.0",
  "name": "Film Filters",
  "execution": {
    "mode": "cloud"
  },
  "commands": [
    {
      "id": "black-white",
      "name": "Black & White",
      "inputTypes": ["image"],
      "outputs": ["image"],
      "taskType": "filter.black-white.v1",
      "requiresUpload": true
    },
    {
      "id": "vintage",
      "name": "Vintage",
      "inputTypes": ["image"],
      "outputs": ["image"],
      "taskType": "filter.vintage.v1",
      "requiresUpload": true
    }
  ]
}
```

## 3. Market 体验

Market 以 Web 形式嵌入 Glance。用户可以浏览分类、搜索 Widget、查看详情和点击加载。

详情页需要显示：

- Widget 名称、图标、简介和包含的 Commands。
- 支持的图片/视频类型。
- `Official by Glance` 标识。
- `Cloud Processing` 标识。
- 明确说明“媒体将上传至服务器”。
- 当前版本、更新时间和使用限制。
- 加载、已加载、更新和移除状态。

Market 页面不能直接修改 Glance 状态。点击加载后，通过受限 Native Bridge 调用 Glance：

```text
Market Web 页面
    ↓ installWidget(manifest)
Glance Native
    ↓ 验证签名和 Schema
Installed Widget Registry
    ↓
动态生成右键菜单
```

Market 数据需要缓存。网络不可用时，用户仍然可以使用已经加载的 Widget；右键菜单生成不能依赖实时网络请求。

## 4. 右键与菜单入口

第一期只支持 Glance 内部的图片和视频窗口，不实现 Finder 扩展或 Finder 右键入口。

建议菜单结构：

```text
Widgets
├── Remove Background…
├── Film Filters
│   ├── Black & White…
│   ├── Vintage…
│   └── Cinematic…
├── Image Toolkit
│   ├── Compress…
│   ├── Resize…
│   └── Convert…
└── Manage Widgets…
```

- 只显示已加载、已启用、兼容当前媒体的 Commands。
- 图片上不显示仅支持视频的 Command，反之亦然。
- 菜单使用原生 macOS 子菜单，不制作自定义悬停卡片。
- 带参数的 Command 点击后打开 Glance 右侧检查器。
- 无参数且安全的 Command 可以直接提交任务。
- 右键菜单和主菜单使用同一个本地 Registry，避免两处状态不一致。

## 5. 执行模型：Market Widget 全部云端

这是 Glance 2.0 的核心安全边界：

> Market Widget 不加载动态本地代码。Glance 负责发现、安装、收集输入、提交任务、跟踪状态和展示结果；Widget 逻辑全部在 Glance 后端执行。

Glance 本身可以保留必要的基础本地功能，但这些功能属于 Glance 核心，不属于可下载的 Market Widget。

### 5.1 任务输入

任务使用结构化 `WidgetInvocation`，不能把图片、文字和参数混成任意字典：

- invocation ID 和幂等键。
- Widget ID、Command ID 和版本。
- 图片/视频输入引用、MIME 类型和 SHA-256。
- 用户文字输入。
- 参数值。
- Glance 版本和语言。

图片和视频不直接以 Base64 放进 JSON。Glance 先请求预签名上传地址，再上传到对象存储，最后用 `assetID` 创建任务。

### 5.2 后端接口

```text
GET  /v2/widgets
GET  /v2/widgets/{widgetID}
POST /v2/assets/upload-request
POST /v2/widget-jobs
GET  /v2/widget-jobs/{jobID}
POST /v2/widget-jobs/{jobID}/cancel
```

任务状态：

```text
queued → running → succeeded
                 ↘ failed
                 ↘ cancelled
                 ↘ expired
```

任务创建返回 `jobID` 和 `pollAfterMs`。Glance 根据服务端建议轮询，初始约 500ms，最大间隔 5 秒。窗口关闭、网络中断或 App 重启后，可以凭 `jobID` 恢复任务状态。

### 5.3 任务结果

后端只返回 Glance 支持的结构化结果，不返回任意 HTML、JavaScript 或可执行文件：

```json
{
  "status": "succeeded",
  "progress": 100,
  "result": {
    "artifacts": [
      {
        "type": "image",
        "url": "https://example.com/result.png",
        "mimeType": "image/png",
        "filename": "image-no-background.png"
      }
    ],
    "metadata": {
      "hasAlpha": true
    }
  }
}
```

Glance 使用自己的原生界面展示图片、视频、文字和元数据，并允许用户导出副本。

### 5.4 三阶段 Job 流程

每个云端 Widget 调用都拆成三个明确阶段：提交 Job、轮询 Job、获取结果。Glance 只调用 Glance Backend；Backend 通过 Provider Adapter 调用 PPPron 或其他任务供应商。

```text
Glance
  ↓ 统一 WidgetInvocation
Glance Backend
  ↓ Provider Adapter
PPPron vision-tasks API
```

#### 阶段一：提交 Job

1. 用户在右键菜单选择 Command。
2. Glance 根据 Manifest 校验媒体类型、文件大小和参数。
3. 如果输入是本地文件，Glance 请求预签名上传地址并上传媒体，获得 `assetID` 或可访问的媒体 URL。
4. Glance 调用 `POST /v2/widget-jobs`，发送统一格式的 `widget_id`、`command_id`、媒体引用和参数。
5. Backend 根据 Widget 的 Provider 配置，将请求转换为供应商格式。
6. Provider Adapter 向 PPPron `POST /vision-tasks` 提交任务。
7. Backend 保存 Glance `jobID` 与供应商 `task_uuid` 的映射，返回 Glance 自己的 Job 响应。

Glance 请求示例：

```json
{
  "widget_id": "com.glance.remove-background",
  "command_id": "remove-background",
  "input": {
    "type": "image",
    "url": "https://storage.example.com/input.png",
    "mime_type": "image/png"
  },
  "parameters": {
    "prompt": "Remove the background and preserve the subject edges"
  },
  "idempotency_key": "uuid"
}
```

Provider Adapter 转换为 PPPron 请求时，使用服务端配置注入 `valid_token`、`team_id`、`team_creator_id` 和 `user_id`。客户端和 Market Web 页面不能传入这些字段。

PPPron 请求中的 `widget_name` 使用 Provider Widget UUID，不能使用用户看到的显示名称。一个 Widget 的每个 Command 可以映射到不同的 Provider Widget UUID 或 `task_type`。

提交成功后的统一响应：

```json
{
  "job_id": "glance_job_123",
  "status": "queued",
  "poll_after_ms": 1000
}
```

如果供应商返回无法解析的响应、没有 `task_uuid` 或提交超时，Backend 不应返回一个看似成功的 Glance Job，而应返回明确的可重试错误。

#### 阶段二：轮询 Job

1. Glance 保存 `jobID`，开始调用 `GET /v2/widget-jobs/{jobID}`。
2. Backend 根据映射找到供应商 `task_uuid`，调用 PPPron 状态接口。
3. Provider Adapter 将供应商状态转换为 Glance 状态。
4. Glance 根据 `poll_after_ms` 决定下一次查询时间。
5. 任务处于 `queued` 或 `running` 时，右侧检查器显示当前阶段和进度。

统一状态映射：

| PPPron 状态 | Glance 状态 |
|---|---|
| `task_status` 不是 3 或 4 | `queued` / `running` |
| `task_status = 3` | `succeeded` |
| `task_status = 4` | `failed` |
| 请求超时但任务可能仍在执行 | 保持 `running`，继续重试 |
| 超过 Glance 最大等待时间 | `expired` |

轮询策略：

- 首次等待约 500ms，之后优先使用服务端返回的 `poll_after_ms`。
- 没有建议间隔时使用 1、2、3、5 秒的退避间隔，最大 5 秒。
- 临时网络错误不立即将任务标记为失败。
- 轮询必须可取消；窗口关闭时停止客户端轮询，但不自动取消云端任务。
- Glance 重启后通过持久化的 `jobID` 恢复查询。
- 用户主动取消时调用 `POST /v2/widget-jobs/{jobID}/cancel`，Backend 再调用供应商取消接口；供应商不支持取消时，将任务标记为客户端取消并继续回收结果。

PPPron 返回的 `success`、`process_count`、`task_status` 和 `task_result` 只在 Provider Adapter 内解析，不能让这些供应商字段渗透到 Glance UI 或公共接口。

#### 阶段三：获取结果

1. Backend 发现供应商任务完成后，解析 `task_result`。
2. `task_result` 可能是 JSON 字符串或 JSON 对象，Adapter 必须统一解析。
3. Backend 校验结果 URL、MIME 类型、文件大小和哈希。
4. 结果下载到受控临时目录，不能直接把未经验证的远程 URL交给媒体查看器。
5. Backend 或 Glance 生成统一的 `artifacts` 结果。
6. Glance 将结果交给原生图片/视频查看器，用户可以预览并导出副本。

统一结果示例：

```json
{
  "job_id": "glance_job_123",
  "status": "succeeded",
  "result": {
    "artifacts": [
      {
        "type": "image",
        "url": "https://storage.example.com/result.png",
        "mime_type": "image/png",
        "filename": "image-no-background.png",
        "sha256": "..."
      }
    ],
    "metadata": {
      "has_alpha": true
    }
  }
}
```

结果 URL 不存在、`task_result` 不是有效 JSON、扩展名与 MIME 类型不一致或结果下载失败时，任务不能显示为成功，应进入 `failed` 状态并给出重试或重新提交入口。

Provider Adapter 应单独覆盖以下行为：

- 从提交响应中提取 `task_uuid`，兼容顶层字段和 `result.task_uuid`。
- 解析字符串形式的 `task_result`。
- 从结果中提取 URL，并通过 MIME 类型优先于扩展名判断图片或视频。
- 将供应商失败信息转换成用户可读但不泄露内部凭据的错误。
- 对提交重试使用幂等键，避免网络超时造成重复任务或重复计费。

## 6. 第一批官方 Widget

第一批建议包含以下 Widget 和 Commands：

### Image Toolkit

- Compress
- Resize
- Convert
- Strip Metadata

### Film Filters

- Black & White
- Vintage
- Cinematic

### Video Toolkit

- Extract Frame

### AI Background Removal

作为第一个完整云端异步 Widget，用来验证上传、创建任务、轮询、取消、恢复和结果下载链路。

## 7. 安全与隐私

- 客户端验证 Manifest 签名、版本和 Schema。
- Widget 不能注入 Glance 主进程。
- Widget 不能访问本地任意目录或执行系统命令。
- Glance 只连接自己的任务网关，不允许 Widget 自由指定上传地址。
- 上传前检查 MIME 类型、文件大小和哈希。
- 第一次运行云端 Widget 时显示上传确认。
- 日志不得记录本地路径、原始文件名、图片内容或用户输入全文。
- 结果先写入临时目录，确认类型和大小后再展示。
- 所有处理默认导出新文件，不覆盖原始媒体。
- 后端限制任务时长、文件大小、调用频率和结果保留时间。
- 提供取消任务、删除源文件和清理结果的生命周期策略。

动态本地代码加载明确不属于 Glance 2.0。未来即使开放第三方，也优先考虑由 Glance 后端执行，而不是下载并运行第三方原生代码。

## 8. 错误和边界状态

必须覆盖：

- Market 离线、目录缓存过期或 Widget 已下架。
- Manifest 签名失败或版本不兼容。
- 当前媒体类型不支持。
- 上传中断、登录过期、任务限流和额度不足。
- 任务失败、超时、取消和结果过期。
- Glance 关闭后任务仍在云端执行。
- App 重启后恢复任务。
- 结果下载失败、磁盘空间不足或导出目录只读。
- 原始文件在任务执行期间被移动或删除。

任何失败都不得修改原始媒体。

## 9. 验收标准

- Market 至少提供三个官方 Widget。
- 至少有一个单功能 Widget 和一个多功能 Widget。
- 用户可以完成“浏览 → 加载 → 右键调用 → 提交 → 轮询 → 预览 → 导出”完整流程。
- 至少一个云端 Widget 完整通过“提交 Job → 轮询 Job → 获取结果”三个阶段。
- 提交响应中的供应商 `task_uuid`、轮询响应中的 `task_status/process_count`、以及字符串形式的 `task_result` 都能被 Adapter 正确转换。
- 提交超时、轮询临时失败、任务失败、任务取消和结果 URL 无效时，Glance 都显示明确状态且不误报成功。
- 右键菜单生成不依赖网络，响应时间不超过 100ms。
- 云端任务可以取消，并能在网络恢复或 App 重启后继续查询。
- 用户在提交前可以明确知道媒体是否会上传。
- 所有结果均以新文件形式导出。
- 至少 5 名测试用户每周重复使用 Widget 3 次以上，再考虑第三方提交和付费系统。

## 10. 明确不做的事情

- 不下载或执行第三方 Swift、动态库、Node.js 或任意本地程序。
- 不做 Finder 右键扩展。
- 不做第三方创作者上传审核。
- 不做支付、分成、评分和评论。
- 不允许 Widget 返回任意 UI 代码。
- 不允许 Widget 直接上传到任意第三方 URL。

## 11. 技术落点

现有 `ImageInspectWindow` 和 `VideoCompareWindow` 作为宿主界面，新增可复用的 Widget 检查器和菜单注册层。Market Web 页面复用现有 WebView 能力，但通过窄权限 Native Bridge 与 Swift 通信。

核心模块建议拆分为：

- `WidgetManifest`
- `WidgetCommand`
- `WidgetInstallation`
- `InstalledWidgetRegistry`
- `WidgetMenuBuilder`
- `WidgetInvocation`
- `WidgetJobClient`
- `WidgetResultRenderer`

Glance 2.0 的核心模型是：

> Widget 是云端媒体处理能力的声明；Glance 是它的本地入口、任务控制器和结果查看器。
