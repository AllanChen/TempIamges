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
