# GlanceService

独立的 Glance Widget 平台 Worker。它是 Widget 提交、审核、发布、任务队列和开发者 Worker 拉取任务的唯一后端，不依赖 `mcreator` 项目。

## 本地配置

复制环境变量示例并通过 Wrangler secret 注入：

```bash
wrangler secret put SESSION_SECRET
wrangler secret put ADMIN_TOKEN
wrangler secret put FLOW_TEST_TOKEN
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
GET  /api/admin/v2/widgets
POST /api/admin/v2/widgets
PUT  /api/admin/v2/widgets/:widget_id
GET  /api/admin/v2/widget-versions
POST /api/admin/v2/widget-submissions/:id/test
POST /api/admin/v2/widget-submissions/:id/approve
POST /api/admin/v2/widget-submissions/:id/reject
GET  /api/v2/widget-tasks/pull?widget_id=...
POST /api/v2/widget-tasks/:id/heartbeat
POST /api/v2/widget-tasks/:id/result
POST /api/v2/widget-jobs
GET  /api/v2/widget-jobs/:id
DELETE /api/v2/widget-jobs/:id
GET  /api/v2/location
```

`POST /api/admin/v2/widgets` 是 Admin Console（或 `ADMIN_TOKEN`）直接新建 Widget 的管理端点，请求体为：

```json
{
  "manifest": { "...与 /api/v2/widget-submissions 相同的 WidgetManifest，创建时无需 id..." },
  "status": "manual_review | gray_release | published",
  "note": "可选审计备注"
}
```

新建 Widget 时，服务端为 Widget 和每个命令分别生成 UUID，并写入保存的 manifest；请求中的 `manifest.id` 和 `commands[].id` 即使存在也不会被采用。`POST /api/v2/widget-submissions` 同样由服务端生成这些 ID，且每次调用都会创建一个新 Widget。创建响应通过 `widgetId`、`commandIds` 返回 ID，同时返回一次性 `workerToken`。后台「Widget Review」的新建表单无需填写 ID，创建成功后才显示。

它复用与客户端提交一致的 manifest 校验，创建 `widgets` + `widget_versions` + `widget_workers` + 审计日志。

`commands[].taskType` 是内部兼容字段，当前不参与任务路由。后台表单无需填写；新建时服务端按 Widget ID 和命令 ID 生成，编辑时保留已有值。

`GET /api/admin/v2/widgets` 返回 D1 中的全部 Widget，包括 `manual_review`、`published`、`gray_release`、`rejected` 和 `suspended`，每个 Widget 只返回当前版本，并明确包含 `widgetId`。公开的 `GET /api/v2/widgets` 仍只返回可安装的 `published` / `gray_release`，不会泄露草稿。

`PUT /api/admin/v2/widgets/:widget_id` 用于编辑 Widget。编辑沿用 URL 中的已有 Widget ID，并沿用已有命令 ID；请求的 manifest 无需填写这些 ID。版本号不变时更新当前 manifest；版本号变化时创建新版本并将其设为当前版本。`GET /api/admin/v2/widget-versions` 保留按版本查看全部历史提交的能力。已有 ID 不会因这次改动而变化。

开发者 Worker 使用提交时生成的 token 拉取任务；生产用户和 Glance 客户端使用用户 Bearer token，管理员使用 `ADMIN_TOKEN`。

调试完整链路时，可以把同一个高强度随机值配置为 `FLOW_TEST_TOKEN` Secret，并在用户、Worker 和管理 API 请求中发送 `Authorization: Bearer <FLOW_TEST_TOKEN>`。它没有时间过期限制，也可读取和操作其他用户的任务、素材与提交；仅限受控调试，完成后删除或轮换该 Secret。未配置时全局 token 不生效。`WORKER_AUTH_DISABLED=true` 仅允许这个全局 token 绕过 Widget 专属 Worker token 校验，Worker 请求仍必须携带 token；普通 Worker Token 仍只授权所属 Widget。管理后台的网页登录仍使用会话 Cookie。

```bash
wrangler secret put FLOW_TEST_TOKEN
```

将客户端中的调试 token 替换为 login 获取的用户 token 后，新 token 会对应新的用户身份；调试 token 创建的私人任务、素材和提交不会自动迁移到该身份。

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

当前 Glance 客户端使用 `/api/v2/tasks`，上传素材后发送：

```json
{
  "widgetID": "official-remove-background",
  "commandID": "remove-background",
  "taskParams": {
    "url": "https://glance-service.allanchanni.workers.dev/api/v2/assets/asset_xxx?...",
    "prompt": "",
    "mask": null,
    "location": "CN"
  }
}
```

`prompt` 与 `mask` 是预留字段。客户端优先向 `https://ipapi.co/country/` 查询当前公网 IP 的两位国家代码；失败时通过 `GET /api/v2/location` 使用 Cloudflare 的国家信息，该回退接口需要用户 Bearer Token。第三方请求会向 ipapi.co 暴露客户端的公网 IP。创建任务时服务端将有效的国家代码转换为英文国家名，并将完整参数交给 Widget Worker；未提供有效代码时使用提交请求的 Cloudflare 国家信息，无法判断时为 `Unknown`。这些结果表示网络出口国家，不保证是用户的实际所在国家。

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
GET https://glance-service.allanchanni.workers.dev/api/v2/widget-tasks/pull?widget_id=7cc3967a-60ac-4677-9817-72f57f5ef5fa&wait=25
Authorization: Bearer <worker_token>
```

查询参数：

- `widget_id`：唯一的任务拉取条件，必须与 Worker 所属 Widget ID 一致。它始终来自对应 Widget Manifest 的 `id`。当前 Widget ID 为：超分 `ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f`、Remove Background `a0d3311a-b952-4831-8ee4-69f72c381a88`、RemoveBG 高级 `7cc3967a-60ac-4677-9817-72f57f5ef5fa`。
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

没有任务时，`task` 为 `null`。Worker 应在请求返回后继续发起下一次长轮询。每次请求最多返回并领取一个任务。后续新增 Widget 也必须使用自己的 Manifest `id` 作为 `widget_id`，服务端不会根据 Widget name 做任务匹配：

```text
GET /api/v2/widget-tasks/pull?widget_id=7cc3967a-60ac-4677-9817-72f57f5ef5fa&wait=25
```

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
