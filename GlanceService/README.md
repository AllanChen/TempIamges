# GlanceService

独立的 Glance Widget 平台 Worker。它是 Widget 提交、审核、发布、任务队列和开发者 Worker 拉取任务的唯一后端，不依赖 `mcreator` 项目。

## 本地配置

复制环境变量示例并通过 Wrangler secret 注入：

```bash
wrangler secret put SESSION_SECRET
wrangler secret put ADMIN_TOKEN
wrangler secret put WORKER_TOKEN_PEPPER
wrangler secret put MEDIA_SIGNING_SECRET
wrangler secret put ADMIN_USERNAME
wrangler secret put ADMIN_PASSWORD
wrangler secret put ADMIN_PATH
```

创建资源后把 `wrangler.toml` 中的 `database_id` 替换为真实 D1 ID：

```bash
wrangler d1 create glance-service-db
wrangler r2 bucket create glance-service-assets
wrangler d1 migrations apply glance-service-db --remote
```

## 核心 API

```text
POST /api/v2/widget-submissions
GET  /api/v2/widgets
POST /api/admin/v2/widget-submissions/:id/test
POST /api/admin/v2/widget-submissions/:id/approve
POST /api/admin/v2/widget-submissions/:id/reject
GET  /api/v2/widget-tasks/pull?widget_id=...
POST /api/v2/widget-tasks/:id/heartbeat
POST /api/v2/widget-tasks/:id/result
POST /api/v2/widget-jobs
GET  /api/v2/widget-jobs/:id
DELETE /api/v2/widget-jobs/:id
```

开发者 Worker 使用提交时生成的 token 拉取任务；生产用户和 Glance 客户端使用用户 Bearer token，管理员使用 `ADMIN_TOKEN`。

`POST /api/v2/uploads` 返回带时效 HMAC 签名的媒体 URL，Worker 可直接读取该 URL；签名过期后必须重新上传或由客户端重新获取授权 URL。

## Admin Console

配置 `ADMIN_USERNAME`、`ADMIN_PASSWORD`、`ADMIN_PATH` 和 `SESSION_SECRET` 后，访问 `https://你的域名/<ADMIN_PATH>`。Admin 使用 HttpOnly、Secure、SameSite=Strict 会话 Cookie；`ADMIN_TOKEN` 仍可作为服务间管理 API 的兼容认证方式。`ADMIN_PATH` 只是降低被扫描概率，真正的安全边界仍然是用户名、密码和会话校验。

当前 Admin 地址：

```text
https://glance-service.allanchanni.workers.dev/ops-9527/
```

## 任务提交与 Worker 执行协议

任务链路如下：

```text
Glance 用户端 → 创建任务 → widget_tasks
Widget Worker → 拉取任务 → 执行 → 心跳续租 → 回传结果
Glance 用户端 → 查询任务状态和结果
```

### 1. 用户端提交任务

用户端使用用户 Bearer Token 调用：

```http
POST https://glance-service.allanchanni.workers.dev/api/v2/widget-jobs
Authorization: Bearer <user_token>
Content-Type: application/json
```

`/api/v2/tasks` 是同等作用的兼容路径。

请求参数：

```json
{
  "widgetID": "official-remove-background",
  "commandID": "remove-background",
  "input": {
    "assetID": "asset_xxx",
    "url": "https://glance-service.allanchanni.workers.dev/api/v2/assets/asset_xxx?..."
  },
  "parameters": {}
}
```

- `widgetID`：Widget Manifest 中稳定且唯一的 `id`，不要使用可修改的 Widget 名称。
- `commandID`：Manifest 中 command 的 `id`。
- `input`：任务输入，可以包含已上传素材的 `assetID` 或签名 URL。
- `parameters`：对应 command 的业务参数。

成功返回 `202`：

```json
{
  "success": true,
  "result": {
    "taskID": "task_xxx",
    "status": "queued",
    "processCount": 0,
    "pollAfterMs": 1000
  }
}
```

如果需要上传文件，先调用：

```http
POST https://glance-service.allanchanni.workers.dev/api/v2/uploads
Authorization: Bearer <user_token>
Content-Type: multipart/form-data
```

表单字段为 `file`。上传接口返回 `assetID` 和临时 `url`，再将其放入任务的 `input`。

### 2. Widget Worker 拉取任务

Worker 使用提交 Widget 时获得的 Worker Token 调用：

```http
GET https://glance-service.allanchanni.workers.dev/api/v2/widget-tasks/pull?widget_id=official-remove-background&wait=25
Authorization: Bearer <worker_token>
```

查询参数：

- `widget_id`：必须与 Worker Token 所属 Widget 一致。
- `wait`：长轮询等待秒数，范围 `0` 到 `25`，推荐使用 `25`。

有任务时返回：

```json
{
  "success": true,
  "result": {
    "task": {
      "taskId": "task_xxx",
      "widgetId": "official-remove-background",
      "versionId": "version_xxx",
      "commandId": "remove-background",
      "type": "production",
      "input": {
        "assetID": "asset_xxx",
        "url": "https://..."
      },
      "parameters": {},
      "leaseExpiresAt": "2026-09-16T10:00:00.000Z"
    }
  }
}
```

没有任务时，`task` 为 `null`。Worker 应在请求返回后继续发起下一次长轮询，不要使用 Widget name 作为拉取参数。

### 3. Worker 处理中的心跳

任务执行期间，Worker 定期调用：

```http
POST https://glance-service.allanchanni.workers.dev/api/v2/widget-tasks/<taskID>/heartbeat
Authorization: Bearer <worker_token>
```

当前每次心跳会将任务状态更新为 `running`，并将租约延长 120 秒。建议执行时间较长的任务每 60 秒发送一次心跳。

### 4. Worker 回传任务结果

成功：

```http
POST https://glance-service.allanchanni.workers.dev/api/v2/widget-tasks/<taskID>/result
Authorization: Bearer <worker_token>
Content-Type: application/json
```

```json
{
  "status": "succeeded",
  "artifacts": [
    {
      "url": "https://example.com/result.png",
      "type": "image/png"
    }
  ]
}
```

失败：

```json
{
  "status": "failed",
  "errorCode": "upstream_timeout",
  "artifacts": []
}
```

`status` 只能使用 `succeeded` 或 `failed`；未识别的值会按失败处理。

### 5. 用户端查询任务状态

用户端使用自己的 User Token 查询：

```http
GET https://glance-service.allanchanni.workers.dev/api/v2/widget-jobs/<taskID>
Authorization: Bearer <user_token>
```

`/api/v2/tasks/<taskID>` 同样可用。返回状态包括：

```text
queued      等待 Worker
claimed     Worker 已领取
running     执行中
completed   执行成功
failed      执行失败
cancelled   用户取消
```

任务处于 `queued`、`claimed` 或 `running` 时继续轮询；`completed`、`failed` 和 `cancelled` 为终态。推荐按照 `pollAfterMs` 开始轮询，并逐渐增加间隔，最大 5 秒。

成功结果包含 `result`，如果第一个产物带有 URL，还会额外返回 `resultURL`：

```json
{
  "success": true,
  "result": {
    "taskID": "task_xxx",
    "status": "completed",
    "processCount": 100,
    "attempts": 1,
    "result": [
      { "url": "https://example.com/result.png" }
    ],
    "resultURL": "https://example.com/result.png"
  }
}
```

### 6. 取消任务

用户端可以取消尚未完成的任务：

```http
DELETE https://glance-service.allanchanni.workers.dev/api/v2/widget-jobs/<taskID>
Authorization: Bearer <user_token>
```

当前 `processCount` 只会返回 `0` 或 `100`，还没有中间进度上报；Worker 的 `heartbeat` 只负责续租和标记 `running`。
