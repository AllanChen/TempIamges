# Glance Widget 提交资料清单

这份清单基于当前 Glance 客户端实现整理，适用于提交一个新的云端 Widget。所有字段对应 `Glance/Sources/WidgetModels.swift` 中的 `WidgetManifest`、`WidgetCommand`、`WidgetExecution`、`WidgetPrivacy` 和 `WidgetSignature`。

## 1. 基础信息

| 项目 | 必填 | 要求 |
|---|---:|---|
| Widget ID | 是 | 3–128 位；字母、数字、`.`、`_`、`-`；全局唯一 |
| Widget 名称 | 是 | Widget Market 卡片和详情页显示 |
| 版本号 | 是 | 建议语义化版本，如 `1.0.0` |
| 一句话摘要 | 是 | Widget Market 卡片摘要，避免技术堆叠 |
| 作者/组织 | 是 | 展示在详情页 |
| 更新日期 | 是 | ISO 8601 时间字符串 |
| 最低 Glance 版本 | 是 | 当前示例使用 `2.0.0` |
| 官方标识 | 是 | `official: true/false` |
| Schema 版本 | 是 | 当前使用 `1` |

## 2. 执行方式

当前客户端只支持云端执行：

```json
"execution": {
  "mode": "cloud"
}
```

`execution.mode` 必须是 `cloud`。本地执行模式暂不接受。

## 3. Widget 命令

至少需要一个命令。每个命令提供：

| 字段 | 必填 | 说明 |
|---|---:|---|
| `id` | 是 | 命令唯一 ID；同一 Widget 内不能重复 |
| `name` | 是 | 用户看到的功能名称 |
| `description` | 是 | 用户在选择功能时看到的行为说明 |
| `inputTypes` | 是 | 当前可用：`image`、`video` |
| `inputMimeTypes` | 是 | 上传接口接受的具体 MIME 类型 |
| `outputs` | 是 | 当前通常为 `["image"]` 或 `["video"]` |
| `taskType` | 是 | 后端任务路由类型，如 `image.remove-background.v1` |
| `requiresUpload` | 是 | 云端任务通常为 `true` |
| `parameterSchema` | 是 | 可参数化选项；没有时使用 `{}` |

当前图片 Widget 的 MIME 示例：

```json
"inputMimeTypes": [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif"
]
```

## 4. 隐私说明

每个 Widget 必须说明是否上传媒体，并给出用户可读的隐私说明：

```json
"privacy": {
  "uploadsMedia": true,
  "notice": "The selected image will be uploaded to Glance for cloud processing."
}
```

如果涉及图片、视频、文件路径、设备信息或第三方服务转发，`notice` 必须明确写出，不要只写 "Your data is safe"。

## 5. 签名

当前 manifest 需要 Ed25519 签名：

```json
"signature": {
  "algorithm": "Ed25519",
  "keyID": "publisher-key-id",
  "value": "base64url-encoded-signature"
}
```

签名覆盖对象是移除 `signature` 字段后的完整 manifest JSON，并使用：

- sorted JSON keys
- 不转义 `/`
- UTF-8 编码
- base64url 签名值

客户端在安装路径会验证签名。官方目录中的 manifest 仍应保留真实签名；不要用占位符提交生产版本。

## 6. Manifest 模板

```json
{
  "schemaVersion": 1,
  "id": "com.example.remove-watermark",
  "version": "1.0.0",
  "name": "Remove Watermark",
  "summary": "Remove a visible watermark from the selected image.",
  "author": "Example Studio",
  "iconURL": "https://example.com/widgets/remove-watermark/icon.png",
  "official": false,
  "execution": {
    "mode": "cloud"
  },
  "commands": [
    {
      "id": "remove-watermark",
      "name": "Remove Watermark",
      "description": "Upload an image and return a copy without the visible watermark.",
      "inputTypes": ["image"],
      "inputMimeTypes": [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif"
      ],
      "outputs": ["image"],
      "taskType": "image.remove-watermark.v1",
      "requiresUpload": true,
      "parameterSchema": {}
    }
  ],
  "privacy": {
    "uploadsMedia": true,
    "notice": "The selected image is uploaded to the Widget service for processing."
  },
  "minimumGlanceVersion": "2.0.0",
  "updatedAt": "2026-09-28T00:00:00Z",
  "signature": {
    "algorithm": "Ed25519",
    "keyID": "publisher-key-id",
    "value": "..."
  }
}
```

## 7. 后端服务要求

客户端任务链路固定为：

1. `POST /api/v2/uploads`
   - multipart 文件上传
   - 成功返回可访问的媒体 URL
2. `POST /api/v2/tasks`
   - 请求体包含 `widgetID`、`commandID`、`taskParams.url`
   - 成功返回 `taskID`
3. `GET /api/v2/tasks/{taskID}`
   - 客户端轮询任务状态
   - 成功时返回可下载的 `resultURL`
4. 客户端下载结果并保存到 `~/Downloads/Glance`

Widget 后端必须提供：

- HTTPS 媒体上传地址
- 任务创建地址
- 任务状态查询地址
- 结果文件的临时或持久 HTTPS URL
- 明确的处理超时和失败状态

## 8. 客户端提交前检查

当前客户端会在提交前检查：

- `schemaVersion >= 1`
- Widget ID 格式合法
- `version`、`name`、`summary`、`author` 非空
- `execution.mode == cloud`
- 至少一个 command
- 命令 ID 不重复
- 每个命令必须声明输入类型、输出类型和 taskType
- 隐私说明非空
- Ed25519 签名完整

## 9. UI / 展示资料

Widget Market 使用以下内容展示：

- Widget 名称
- 一句话摘要
- 版本
- 作者
- 云端标识
- 命令数量和命令名称
- 隐私说明
- 安装/卸载状态
- 图标

图标当前建议：

- PNG 或 WebP
- 至少 256×256 px
- 深色背景或透明背景
- 主体居中，四周保留安全边距
- 不使用过多文字

## 10. 测试样例

提交前至少准备：

| 样例 | 目的 |
|---|---|
| JPEG 图片 | 验证最常见输入 |
| PNG 带透明背景 | 验证透明通道 |
| WebP | 验证现代格式 |
| HEIC/HEIF | 验证 macOS/iPhone 图片 |
| 视频文件 | 仅当 `inputTypes` 包含 `video` |
| 大图 | 验证上传、超时和下载 |
| 失败样例 | 验证失败状态能正确返回 |

测试结果需要覆盖：

- 上传成功
- 任务创建成功
- 轮询中的 processing 状态
- completed/succeeded 结果 URL
- failed 状态
- 下载失败
- 超时
- 重复安装、卸载和重新安装

## 11. 一次完整提交包建议包含

- `widget-manifest.json`
- Widget 图标文件
- 后端 API 文档或 endpoint 清单
- 隐私说明原文
- 测试输入文件
- 预期输出样例
- 签名公钥标识 `keyID`
- 版本更新说明

如果缺少任何一项，客户端或后端审核都可能无法完成。