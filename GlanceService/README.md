# GlanceService

独立的 Glance Widget 平台 Worker。它是 Widget 提交、审核、发布、任务队列和开发者 Worker 拉取任务的唯一后端，不依赖 `mcreator` 项目。

## 用户登录与 Widget 积分

Glance 用户可使用 Google 或邮箱六位验证码登录。普通用户会话与开发者 CLI 会话、管理员会话相互独立；任意字符串或调试 token 不再能创建用户任务。用户身份绑定数据库用户 ID，退出后再次登录仍使用同一账户和余额。用户 token 只以 SHA-256 摘要保存在服务端，客户端保存在 macOS Keychain；退出会撤销当前服务端会话。

上线前先应用 `0010_user_accounts_credits.sql`，再部署 Worker：

```bash
cd GlanceService
npx wrangler d1 migrations apply glance-service-db --remote
npm run deploy
```

Google 登录复用 `GOOGLE_CLIENT_ID`、`GOOGLE_CLIENT_SECRET`，用户登录的回调地址由 `GOOGLE_REDIRECT_URI` 配置，当前为 `https://glance.mcreator.ai/auth/google/callback`，需要在 Google OAuth 客户端中登记这一完整地址；未配置时回退到 `<PUBLIC_ORIGIN>/auth/google/callback`。授权请求和授权码交换使用同一个回调地址。桌面客户端通过 `glance://auth/callback` 接收短期一次性授权码，并用本次请求的 PKCE verifier 交换会话；回调不包含用户 token。

官网域名由静态站点提供，`mcreator.ai` Zone 中单独设置 Worker Route `glance.mcreator.ai/auth/google/callback*` → `glance-service`。Cloudflare 路由匹配包含查询参数，结尾的 `*` 确保 Google 携带 `code`、`state` 返回时进入认证服务。Google 控制台登记的回调 URI 和 `GOOGLE_REDIRECT_URI` 仍使用完整地址 `https://glance.mcreator.ai/auth/google/callback`，不加 `*`。此路由通过 Cloudflare Zone Routes 管理；不要将整个 `glance.mcreator.ai/*` 指向认证 Worker。官网首页与 API 自定义域名继续沿用各自的现有绑定。

邮箱验证码通过 Resend 发送，需要配置已验证发信域名的地址，以及 API Key（均使用 Wrangler Secret）：

```bash
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put AUTH_EMAIL_FROM
```

`AUTH_EMAIL_FROM` 示例格式为 `Glance <auth@your-verified-domain.example>`。验证码有效期 10 分钟、最多尝试 5 次、同一邮箱发送间隔至少 60 秒；每个来源 IP 每小时最多请求 20 次。未配置邮件服务时邮箱登录返回 `503 email_not_configured`，不会发放可绕过认证的验证码。Google 登录不依赖邮件服务。

`wrangler.toml` 的 `NEW_USER_CREDITS` 控制新账户的一次性赠送，默认 `100`；设为 `0` 时由管理员发放。修改该配置不改变已有账户的余额。后台新增“用户与积分”页面，展示最近 100 位用户的余额并支持备注发放；每次发放使用唯一提交编号，重试不会再次到账。

开发者在 `widget.json` 的顶层设置每次任务的积分消耗：

```json
{ "creditCost": 1 }
```

每个新建 Widget 的 `widget.json` 都必须显式填写顶层 `creditCost`，为 `0–1000000` 的整数，默认 `1`；`0` 表示免费。同一 Widget 的所有命令使用这个费用；旧 Manifest 未填写时兼容为 `1`。开发者通过 CLI 提交的新版本沿用现有审核、发布流程，上线后价格才生效；管理后台的“每次任务消耗积分”读写同一个 Manifest 字段 `creditCost`。计价取服务端当前已发布版本，客户端传入的费用不能覆盖它。仅修改本地 `widget.json` 不会改变后台当前保存的价格。

现有 Widget 通过 `0011_widget_credit_prices.sql` 一次性统一为 `1` 积分 / 次，本地 Widget 配置和内置模板也显式设置为 `1`。管理员可在 **Widget Review → 全部 Widget → 编辑 → 每次任务消耗积分** 修改并保存；保留当前版本号和发布状态时，新价格立即用于后续提交。后续部署不会重置管理员已修改的价格。

任务创建、积分扣减和流水写入由同一个数据库语句中的触发器完成。余额不足返回 `402 insufficient_credits`，且不创建任务。免费 Widget 仍需登录，余额为 `0` 也可提交，不扣积分、不写扣费流水；已有服务需应用 `0012_free_widget_tasks.sql` 以更新数据库校验。无效请求、价格变化和队列已满不扣积分。付费任务被接受即扣费；系统失败、排队过期及排队中撤销按任务最初费用自动退点，每个任务最多退一次。已被 Worker 领取后主动取消不退点；Worker 重新领取、心跳、结果回传和管理员审核测试不重复扣费。任务记录保存提交时的费用，后续修改价格不影响已提交任务。

新客户端提交时附带 `Idempotency-Key` 和 `expectedCreditCost`。相同用户、相同提交编号和参数只会创建一个任务；编号重复但参数不同返回 `409 idempotency_conflict`。价格与用户看到的不一致返回 `409 price_changed`，客户端刷新本地 Widget，但不会自动按新价格付费。

```text
GET  /auth/google?state=...&code_challenge=...
GET  /auth/google/callback
POST /auth/native/exchange          { code, code_verifier }
POST /auth/email/send-code          { email }
POST /auth/email/verify-code        { email, code }
GET  /auth/me                       用户 Bearer token
POST /auth/logout                   撤销当前 Bearer token
GET  /api/v2/account/credits        余额、最近 100 笔流水
GET  /api/admin/v2/users            管理员鉴权
POST /api/admin/v2/users/:id/credits { amount, note }，必须带 Idempotency-Key
```

新版本客户端使用登录会话提交任务，移除了 `glance.widgetTaskToken` 调试覆盖。之前由调试 token 创建的任务和素材保留原归属，不自动转移到真实账户。受控 `FLOW_TEST_TOKEN` 仍仅用于任务状态和素材排查，不可创建付费任务。

## 开发者 CLI

仓库中的 `glance-cli/` 是 Python 包。开发者安装后运行 `glance widget init` 创建 UUID 文件夹，`glance widget publish` 提交审核，并在自己的机器上运行一个 `glance worker`。该 Worker 用一次 `POST /api/v2/widget-tasks/pull-batch` 按 Widget ID 请求任务；服务端按 Widget ID 授权和分配，任务的版本号仅保留用于发布、审核和历史记录。Worker 对每个 Widget ID 运行一份本机代码，上传结果并发送心跳。管理员在 Admin Console 发送测试任务、检查结果、手动灰度及正式发布。

开发者 Google 登录需要设置 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`，并在 Google OAuth 客户端中登记重定向地址：`<PUBLIC_ORIGIN>/api/v2/developer/auth/google/callback`。发布前还需要配置 `GLANCE_SIGNING_KEY_PKCS8`，值是与 Glance 客户端内 `glance-market-2026-02` 公钥对应的 Ed25519 PKCS#8 DER 的 Base64。此机器上的开发用私钥保存在 `~/.config/glance-service/signing-key.pem`，**不要提交私钥到仓库**；生产环境应通过 Wrangler Secret 配置并安全备份。配置命令示例：

当前联调可把临时开发者 token 配为 Wrangler Secret `DEVELOPER_TEST_TOKEN`，CLI 本机将相同 token 写入 `~/.config/glance/mock-token`（权限 `0600`），无须运行 `glance login`。Service 将其映射为固定的模拟开发者 `mock:glance-cli`；这个 token 只用于开发者 API，不授予 Admin Console 权限。完成真实 Google 登录后应删除此 Secret 和本机 mock-token 文件。

```bash
openssl pkey -in ~/.config/glance-service/signing-key.pem -outform DER | base64 | tr -d '\n' | wrangler secret put GLANCE_SIGNING_KEY_PKCS8
wrangler secret put GOOGLE_CLIENT_ID
wrangler secret put GOOGLE_CLIENT_SECRET
wrangler d1 migrations apply glance-service-db --remote
```

2026-09-30 已将当前 Service 部署到 `https://glance-service.allanchanni.workers.dev`，并应用 `0002_developers.sql`；线上已配置临时开发者 token 和 Manifest 签名密钥。Google OAuth 仍需配置客户端凭据。Gray release 只供审核，不进入公开 Market；管理员执行 `promote` 后才公开。

登录使用 Google 官方的 [Web Server OAuth 流程](https://developers.google.com/identity/protocols/oauth2/web-server)和 [OpenID Connect UserInfo 接口](https://developers.google.com/identity/openid-connect/reference)。

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
GET  /api/v2/developer/widgets/:widget_id
POST /api/v2/developer/widgets/:widget_id/unpublish
POST /api/v2/developer/widgets/:widget_id/archive
POST /api/v2/widget-tasks/pull-batch
POST /api/v2/widget-tasks/:id/artifacts
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
GET  /api/v2/glance_config
GET  /api/admin/v2/glance-config
PUT  /api/admin/v2/glance-config
GET  /api/admin/v2/upload-settings
PUT  /api/admin/v2/upload-settings
```

`POST /api/admin/v2/widgets` 是 Admin Console（或 `ADMIN_TOKEN`）直接新建 Widget 的管理端点，请求体为：

```json
{
  "manifest": { "...与 /api/v2/widget-submissions 相同的 WidgetManifest，创建时无需 id..." },
  "status": "manual_review | gray_release | published",
  "note": "可选审计备注"
}
```

管理后台新建 Widget 时，服务端为 Widget 和每个命令生成 UUID，并返回一次性 `workerToken`。开发者通过 Python CLI 提交 `POST /api/v2/widget-submissions` 时，保留 `glance widget init` 生成的 Widget UUID 和稳定的 Command ID；相同 Widget 可以提交新的版本，服务端按开发者身份核对所有权。CLI 使用可撤销的开发者会话调用批量领取接口，不从提交响应获取 Worker Token。

它复用与客户端提交一致的 manifest 校验，创建 `widgets` + `widget_versions` + `widget_workers` + 审计日志。

`commands[].taskType` 是内部兼容字段，当前不参与任务路由。后台表单无需填写；新建时服务端按 Widget ID 和命令 ID 生成，编辑时保留已有值。

`GET /api/admin/v2/widgets` 返回 D1 中的全部 Widget，每个 Widget 只返回当前线上版本；`GET /api/admin/v2/widget-versions` 返回待审核和历史版本。公开的 `GET /api/v2/widgets` 只返回正式 `published` 的当前版本，不泄露待审核或灰度版本。

`PUT /api/admin/v2/widgets/:widget_id` 用于编辑 Widget，包括开发者发布的文字输出 Widget。编辑沿用 URL 中的已有 Widget ID，并沿用已有命令 ID；请求的 manifest 无需填写这些 ID。版本号不变时更新当前 manifest；版本号变化时创建新版本并将其设为当前版本。开发者 Widget 仍保持开发者归属，后台修改后由服务端重新签名；官方 Widget 保持官方归属。`GET /api/admin/v2/widget-versions` 保留按版本查看全部历史提交的能力。已有 ID 不会因这次改动而变化。

Manifest 可选的 `localizations` 按语言标签（`en`、`zh-Hans`）提供 `name`、`summary` 和按 command id 组织的命令 `name`、`description`；Glance 客户端和市场页按界面语言显示，缺少的字段回退到基础文案。后台表单的英文字段写入 `localizations.en`，其他语言在编辑时保留。该字段参与 Manifest 签名，校验规则与基础字段相同（非空字符串、command id 必须存在）。

Widget 的展示名称以当前版本 Manifest 的 `name` 为准。开发者提交新版本时不会提前覆盖已发布名称；审核将新版本设为当前版本时，同步更新 `widgets` 表的名称、摘要、作者和图标。后台列表也从对应版本 Manifest 读取这些字段，避免列表旧标题与编辑表单不一致。

后台表单支持单图、多图（最多 4 张）、单视频、多视频（最多 4 段），并可声明文字 `prompt`；单图还可声明 `mask`。多图和多视频分别写入 `commands[].parameterSchema.properties.images`、`videos`，文字和遮罩写入 `prompt`、`mask`。选中图片和视频表示两个可触发的媒体类型，不表示一次任务混合两类媒体。输出类型可同时选择多个；编辑时保留表单未展示的其他命令和参数字段。

Widget Review 的「发送测试」弹窗读取**待审核版本**的 Manifest，可选择命令及媒体类型，并按 `images` / `videos` 的 `minItems`、`maxItems` 收集 1–4 个 HTTPS URL；仅在命令声明时显示 `prompt` 和 `mask`。提交时图片写入 `input.images`、视频写入 `input.videos`，首个媒体同时作为 `input.url`，文字和遮罩写入 `parameters`。服务端按同一版本的命令配置再次校验，避免测试任务缺少第二张图或将未声明的输入送给 Worker。线上版本的输入声明需先随 Widget 版本提交，改动本地 `widget.json` 不会改变审核弹窗。

`DELETE /api/admin/v2/widgets/:widget_id` 删除任意 Widget（包括预置官方 Widget）的市场记录、版本和 Worker 绑定。存在排队或运行中任务时返回 `409`；历史任务、产物和审计记录保留。预置 Widget 只在首次初始化时写入数据库；管理员编辑或删除后不会被初始化流程覆盖或重新创建。

Python CLI Worker 使用开发者会话批量领取属于自己或经 `widget_worker_grants` 显式授权的 Widget 任务，并在心跳、上传和回传时附带本次领取的 `X-Task-Claim`。执行授权只允许领取任务。`widget_publish_grants` 则单独授权开发者向已有的管理员 Widget 提交新版本：`glance widget publish` 创建 `manual_review` 版本，管理员测试、审核并执行 `promote` 后才上线；管理员 Widget 的官方标记会保留。该授权不允许开发者自行上线、取消发布或归档。`0007_widget_publish_grants.sql` 为当前模拟开发者配置 OSS Widget 的提交权限，真实 Google 账号上线时需单独配置授权。`0005_widget_worker_grants.sql` 暂时为模拟开发者授权本仓库的四个既有 Widget 执行任务。旧版单 Widget Worker 仍使用原有 Worker Token。生产用户和 Glance 客户端使用用户 Bearer token，管理员使用 Admin 会话或 `ADMIN_TOKEN`。

旧版任务链路仍支持受控调试用的 `FLOW_TEST_TOKEN`；它不授予开发者提交、批量领取或管理后台权限。`WORKER_AUTH_DISABLED=true` 只影响旧版单 Widget Worker 接口。开发者 API 通常使用 Google 登录后取得的会话；联调期间也接受独立配置的 `DEVELOPER_TEST_TOKEN`。管理后台网页登录仍使用会话 Cookie。

```bash
wrangler secret put FLOW_TEST_TOKEN
```

真实用户身份绑定账户 ID，多次登录产生的新 token 仍可访问该账户已有任务和积分。调试 token 创建的私人任务和素材不会自动迁移到真实账户。

Admin Console 左侧的“Glance 配置”页面可编辑整份 `glance_config` JSON；配置保存在 D1 的 `service_settings` 表，新增字段无需新增数据库列。`PUT /api/admin/v2/glance-config` 会替换整份配置，要求 `locationBasedUpload` 为布尔值；首页的便捷开关只修改这个字段并保留其他字段。该字段默认开启。`GET /api/v2/glance_config` 下发整份配置，Glance 客户端在每次上传前读取；读取失败时保守地使用 R2。开启时，客户端根据随后任务中使用的同一个 `location` 值判断：`CN` 或 `China` 的图片优先从本机上传到 Freeimage，失败时回退 R2；其他地区及非图片文件使用 R2。关闭时所有媒体统一上传 R2。Service 的 `POST /api/v2/uploads` 始终只上传 R2，不再调用 Freeimage。`glance_config` 会完整下发给客户端，不应放入密钥。

Freeimage API Key 保存在运行 Glance 的 Mac 的 Keychain 中，不由 `glance_config` 下发。开发机已在 shell 中配置 `FREEIMAGEKEY` 时，可从仓库根目录运行 `zsh -ic 'swift Glance/scripts/set-freeimage-key.swift'` 导入 Keychain。客户端也兼容已有的 `glance.freeimageAPIKey` UserDefaults 值与进程环境变量。缺少本地 Key 时，中国地区图片同样回退 R2。

R2 上传返回带时效 HMAC 签名的媒体 URL，Worker 可直接读取；签名过期后必须重新上传或由客户端重新获取授权 URL。Freeimage 成功时由客户端直接取得图床的 HTTPS 图片 URL。客户端将最终 URL 放入后续任务参数；R2 响应包含 `assetID`、`url` 和 `provider`。

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
POST https://api.glance.mcreator.ai/api/v2/uploads
Authorization: Bearer <user_token>
Content-Type: multipart/form-data
```

表单字段为 `file`，Service 始终上传到 R2。接口返回 `assetID`、`url` 和 `provider: r2`；客户端将 URL 放入任务参数。中国地区图片由 Glance 在本机直接上传到 Freeimage，不经过此接口。

Widget command 可在图片或视频输出声明旁设置 `"showResultURL": true`。后台 Widget 表单提供“显示复制 URL 按钮”选项；Service 仅允许媒体输出开启。客户端在成功返回可用 HTTP(S) URL 后显示复制按钮。需要长期分享链接时，Worker 应直接返回公开托管的媒体 `url`，因为通过 `path` 上传到 Service 的资源链接可能带有效期。

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


## Pricing、Pro 与支付（PRD v0.5）

实现说明和上线配置见 [`docs/billing-setup.md`](docs/billing-setup.md)。先应用数据库迁移 `0013_pricing_licenses_payments.sql`、`0014_billing_metrics.sql` 和 `0015_admin_pro_grants.sql`，再部署对应 Worker。迁移保留已有账户、会话、余额和流水，允许退款回收产生负余额。负余额仍可提交免费 Widget。后台「用户与授权」支持填写备注手动授予永久 Pro，沿用配置的功能更新期，不生成支付订单或附送积分。

后台新增「定价与授权」「订单与退款」。软件买断和更新续购金额默认为空，只有管理员设置后才能购买。人民币与美元的价格、积分分别配置；积分包数量、启用和推荐可调整。开启销售需要有效商户配置；没有可用购买路径时客户端不会限制本地工具。

订单与任务消费均使用 `Idempotency-Key`；下单携带 `expectedPrice`，提交任务携带 `expectedCreditCost`。付款页回跳不是支付凭据；只有通过原始请求体 RSA 验签、商户环境与金额核对的 webhook 能发放权益。支付 URL 中的买家令牌加密存储，后台订单接口不会返回。

查询任务额外返回 `creditCost`、`refundedCredits` 和 `balance`。`DELETE /api/v2/tasks/:id?queuedOnly=true` 是撤销，只在排队中成功并全额退点；已领取时返回 409，客户端确认「不退点取消」后才发送常规 DELETE。定时任务每五分钟兜底清理过期任务，提交、领取、状态查询时也会检查；最长排队与最多领取次数由后台配置。
