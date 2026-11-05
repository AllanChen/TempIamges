# Pricing & Credits 实现与配置

## 2026-10-29 当前部署（优先于历史说明）

- Worker 使用 Waffo `test` 环境，公开销售关闭；`TEST_CHECKOUT_USER_ID=2` 允许现有测试账户购买 Pro 和点数包。
- 已绑定 5 个沙盒商品，各支持 CNY/USD/JPY/EUR/HKD；全部走 Waffo 测试收银台，不是直接模拟到账。
- 5 人版已实现：含购买者共 5 账号、每人 1 Mac、点数独立。邀请与删除接口见 [账户与团队](../../../docs/account-and-team.md)。
- 付款与退款回调地址：`https://api.glancepreview.com/api/v2/payments/waffo/webhook`。USD 2.99 / 600 点已完成沙盒付款与全额退款，账本分别只有一笔入账及一笔回收。
- 订单保存 `billing_mode`，正式转化报表排除测试订单。授权按环境读取，正式退款不能恢复旧测试授权。测试及正式仍共用数据库，并非整库隔离。
- 商户执行退款走签名的 merchant API；客户申请接口仅登记申请。回调确认后才回收权益。
- 正式商品配置模板见 `../config/billing-production-v1.json`；正式公钥已从官方 SDK 0.27.0 核对（与已安装 0.26.0 一致），正式私钥也已验证可访问正式商店；仍须客户端验收后再切正式收款。
- 测试和正式私钥分别使用 `WAFFO_PRIVATE_KEY_TEST` / `WAFFO_PRIVATE_KEY_PROD`，按 `WAFFO_ENVIRONMENT` 选择；旧 `WAFFO_PRIVATE_KEY` 仅作兼容回退。不得混用两种环境的商品 ID 或公钥。
- 最新部署、测试证据和手工验收项见 [上线清单](../../../docs/launch-readiness.md)。没有构建或操作 macOS App。


## 数据库和服务

服务使用原有 `users`、登录会话和 `user_credit_ledger`，没有另外创建不兼容的账户系统。新增迁移 `0013_pricing_licenses_payments.sql`、`0014_billing_metrics.sql` 和 `0015_admin_pro_grants.sql`：

- 保留现有账户、会话、积分及流水，放开退款回收所需的负余额。
- 增加定价版本、订单价格快照、支付通知去重、退款申请、Pro 授权、设备与释放记录。
- 任务受理和扣点同一事务；终态和退点同一事务。
- 应用 `0017_task_failure_refunds.sql` 后，失败、过期和取消（包括运行中取消）均按实际扣款全额退点，且只退一次。新版客户端还会确认结果交付；下载或保存失败退款，生成成功后 30 分钟未确认交付也会退款。详见 [`../../docs/glance-task-credit-audit.md`](../../../docs/glance-task-credit-audit.md)。

已有服务先备份 D1，再应用仓库中尚未执行的迁移。开发和正式环境使用各自的数据库、商户配置和 webhook 公钥。生产 Worker 需要 `nodejs_compat`（官方 Pancake SDK 的 RSA 实现），`wrangler.toml` 已设置。定时清理每五分钟运行，同时提交、领取和查询任务都会清理过期任务。

## 商户配置

### 审核期间的模拟充值

`MOCK_CHECKOUT_USER_ID` 是旧模拟结账功能，当前部署已移除。现在使用指定测试账号的真实 Waffo 沙盒流程，付款必须等待验签回调；不能照旧说明将该变量重新配置为用户 1。

商户审核完成后，先配置以下密钥和后台商品，再移除 `MOCK_CHECKOUT_USER_ID` 并部署正式版本。不要把测试积分或模拟订单计作收入。

通过 Worker secrets 设置，禁止把密钥写入后台配置或版本库：

| 变量 | 内容 |
| --- | --- |
| `WAFFO_MERCHANT_ID` | Pancake Merchant ID |
| `WAFFO_PRIVATE_KEY` | 商户 RSA 私钥，PEM 或平台支持的 Base64 格式 |
| `WAFFO_STORE_ID` | `STO_…` Store ID |
| `WAFFO_ENVIRONMENT` | `test` 或 `prod`；仓库默认 `test` |
| `WAFFO_WEBHOOK_PUBLIC_KEY_TEST` | 测试环境 RSA 验签公钥 |
| `WAFFO_WEBHOOK_PUBLIC_KEY_PROD` | 正式环境 RSA 验签公钥 |
| `GLANCE_SIGNING_KEY_PKCS8` | 现有 Widget 市场 Ed25519 签名私钥（Base64 PKCS#8），用于签发授权凭证 |
| `SESSION_SECRET` | 原有会话密钥；也用于加密保存收银台 URL，修改前应结束未付款订单 |

授权公钥固定在客户端，必须与 `GLANCE_SIGNING_KEY_PKCS8` 对应现有 `glance-market-2026-02` 公钥。更换签名密钥时需要同步发布含新公钥的客户端；不能任意换私钥让已发布客户端接受新签名。

在 Pancake 创建一次性商品，取得 `PROD_…` ID，分别填入后台 Pro、更新续购和积分包。不要创建订阅商品。后台保存不直接修改 Pancake 商品；下单时使用签名的 `priceSnapshot` 固定管理员配置的金额。

- Webhook：`https://api.glancepreview.com/api/v2/payments/waffo/webhook`
- 订阅事件：`order.completed`、`refund.succeeded`、`refund.failed`
- 成功地址：`https://glancepreview.com/pay/return?order=<order_id>`
- App 深链：`glance://payment/return?order=<order_id>`
- 服务条款：`https://glancepreview.com/terms`
- 隐私说明：`https://glancepreview.com/privacy`
- 退款政策：`https://glancepreview.com/refunds`

`site/pay/return` 和三个政策页面可由 Worker assets 托管，也同步提供在 `website/app/public`；静态官网构建器使用 `website/static/src/pages/50-payment-return.html`。官网域名若由单独的网站部署负责，须同时发布这些公共文件，确保上述路径落到实际页面；API 域名继续路由 Worker。

## 后台启用顺序

1. 配置商户、商品、webhook、官网页面和客服邮箱。
2. 打开「定价与授权」，填写 Pro 的人民币 / 美元金额、可选首发价和截止时间、更新续购金额。金额单位为分 / cents。
3. 核对积分包。V1 CNY 为 1200 / 600、3000 / 1500、9800 / 5000；USD 为 299 / 600、699 / 1500、1999 / 5000。JPY 为整数日元，其他币种金额使用分；完整配置见正式配置模板。
4. 设置设备数、离线天数、释放次数、任务确认阈值、排队时限和最大尝试次数。默认遵循 PRD。
5. 商户测试完成后再打开销售开关。缺少支付密钥、验签公钥或授权签名密钥时，购买不可用，客户端不会因此锁住本地工具。

保存采用定价 revision 防覆盖；改价不改变已经创建的订单。已购 Pro 不再提供重复买断入口。后台「订单与退款」显示最近 200 笔订单和退款申请；管理员可批准并提交退款工单，或填写原因拒绝申请；拒绝原因会在客户端显示，均不直接撤销权益。平台确认成功后自动回收，失败保留权益并标记待处理。

## 管理员手动升级 Pro

后台「用户与授权」支持按邮箱、姓名或用户 ID 搜索与翻页，展示 Pro 状态、授权来源、Mac 名额和激活数。免费版或已退款的正常账户可填写赠送备注，再点击「免费赠送终身 Pro」。该操作包含终身功能更新，Mac 名额沿用当前 `deviceLimit`，离线凭证仍按正常周期刷新。已有有效 Pro 不会被覆盖或重复授予，禁用账户不能升级。赠送历史通过 `GET /api/admin/v2/users/:id/pro` 查询，仅管理员可用。

接口为 `POST /api/admin/v2/users/:id/pro`，仅管理员会话或管理员 Token 可用，请求体为 `{ "note": "内测用户" }`，必须携带 `Idempotency-Key`。授权及备注写入 `admin_pro_grants`，与账户授权、试用失效在同一 SQL 事务生效；重复请求不会重复发放；授权包含终身功能更新。手动授权不生成支付订单、不计销售收入、不附送积分，积分仍通过原有发放入口单独操作。既有未付款订单之后到账或退款，不会撤销管理员授予的 Pro。

用户回到客户端刷新账户后，可通过现有激活入口激活这台 Mac，或重新登录后自动激活空余设备名额。签发可被客户端验证的离线授权仍需要正确配置 `GLANCE_SIGNING_KEY_PKCS8`。本功能上线须应用 `0015_admin_pro_grants.sql` 后部署 Worker 和后台页面。

## Pro 兑换码（0025）

后台「兑换码」支持生成终身或一年 Pro 批次、查看最近 100 个批次及撤销未使用码。每次生成 1–100 个码，必须填写批次备注和 Mac 名额；可另外设置兑换截止时间。明文只在生成响应中返回一次，数据库只保存 SHA-256 哈希与末四位提示，后台之后不能找回明文。

- 管理员生成／列表：`POST`、`GET /api/admin/v2/redemption-codes`。
- 撤销批次未使用码：`POST /api/admin/v2/redemption-codes/:batchID/revoke`，已兑换授权不受影响。
- 用户兑换：`POST /api/v2/account/pro/redeem`，body 为 `{ "code": "GLG-…" }`，必须登录。
- 同一码只能由一个账户兑换一次；同一账户重复提交已兑换码返回当前授权。已有有效 Pro 时不覆盖授权，也不消耗新码。并发兑换由条件更新和事务保证只有一个成功。
- 终身码没有访问到期日；一年码从兑换时起算一个日历年，写入独立 `access_expires_at`，不复用付费授权的 `updates_until`。
- 一年到期后授权变为 `expired`，设备释放，查看、对比、截图、OCR、文件和点数保留。在线接口与客户端签名离线凭证都执行该到期日，离线凭证有效期不会超过访问到期日。
- 兑换只赠本地 Pro，不生成订单、不赠送点数、不计付费收入。测试与正式码按 `billing_mode` 隔离。
- 付费升级或管理员授权成为新的授权来源时，会清除旧兑换来源和到期限制。

`0025_pro_redemption_codes.sql` 已应用，Worker 与后台已部署；尚未生成正式兑换码。包含兑换入口的 macOS 客户端仍由项目所有者构建验收，验收通过后再随新客户端发行。

## 客户端行为

- 当前范围按用户要求收回到收费功能。Widget 已恢复原上传、提交、查询和取消流程，不依赖 `/api/v2/pricing`、钱包或授权前置检查；不再弹出新增的任务确认、就地充值续提交或取消确认界面。服务端原有账户余额校验与扣点仍生效。
- 登录支持 Google 和邮箱六位验证码；Pro 购买和独立充值继续使用收费窗口。
- 登录、设备标识及试用 / 授权缓存恢复为本地设置存储。旧钥匙串数据仅尝试一次禁止交互的静默迁移，失败不会弹密码框；退出账户不会从旧钥匙串重新恢复登录。钥匙串防重装强化暂缓。
- 钱包、最近 100 笔流水、订单、退款申请、设备释放、更新资格与续购均有入口。
- 浏览器回跳只查询订单；验签通知负责到账。关闭或放弃支付不关闭服务器订单，迟到付款仍到账。重启/回到前台可恢复待付订单查询。
- Pro 为每台 Mac 签发最多 30 天的离线凭证。普通在线会话过期不会抹掉仍有效的离线授权；显式退出账户会清除本机授权。被释放设备联网后不会自动重新激活，重新登录或点击激活才占用名额。
- `Info.plist` 的 `GlanceFeatureReleaseDate` 是该版本功能发布日期。每次功能版本发布应更新；纯安全修复设置 `GlanceSecurityUpdate=true`。更新资格覆盖的旧版本继续有效，最新兼容版本下载地址由后台设置。

## 非 UI 验证与用户验收

`npm run typecheck`、`npm test` 验证服务代码、D1 迁移、支付通知真实 RSA 验签、幂等、价格快照、退款、管理员 Pro 授权和设备规则。客户端可做 Swift 类型检查，不构建、不启动 Glance。

真实收款联调仍需已获批的 Pancake 商户：用测试环境完成 CNY 微信 / USD 银行卡、支付回跳、重复通知、晚到通知和退款成功 / 失败检查，再切正式环境。客户端 UI 和真实支付由项目所有者构建并测试。


## PRD 指标与设计状态对照

后台新增「收费指标」，支持最近 7 / 30 / 90 天。`POST /api/v2/billing/events` 收集登录提示/成功、首次试用、试用功能使用、余额不足、Pro 介绍和被锁操作点击；设备标识仅保存散列，不保存媒体、提示词、邮箱、支付令牌。设备和网络分别限流，客户端事件失败不阻塞操作。事件以账户和设备范围去重。

`GET /api/admin/v2/billing/metrics` 仅管理员可用。实际付款、任务受理、退点、撤销和退款来自服务端订单、任务、流水；充值订单保存本次 intent，只有同账户且对应已支付充值订单的任务才能关联，防止把「已到账」误当成「原任务已提交」。

指标口径：

- 登录转化以设备和登录 journey 配对匿名提示与登录成功。
- 赠点耗尽按首次触及非正余额且发生在赠送后 7 天内计一次；退款后余额恢复仍保留发生记录。只统计观察满 7 天的队列。
- 余额不足转化以同账户 intent 的实际充值到账计数；充值后任务指标以对应任务被实际受理计数。
- 试用活跃以对比、转换或 Widget 使用计数；已关联账户的多设备按账户合并，未登录时按设备统计。试用转 Pro 只计试用结束前后 7 天的购买，并排除还未观察满试用结束后 7 天的队列。
- 支付成功率按币种统计；按实际支付方式展示已确认订单数。Pancake 一次性支付只在成功事件提供实际方式，未付款美元订单无法可靠拆成银行卡/Apple Pay/Google Pay 失败，因此显示「尚未回报」，不伪造渠道失败率。
- 付费任务退点按 Widget 统计，任务撤销单列；现金退款按商品统计。

所有指标从迁移 `0014` 的采集开始时间起算，历史缺失记录不会补成虚假的转化。无成熟分母时 rate 为 null，后台显示暂无成熟样本。

当前 Widget 已恢复原流程，不再上报余额不足 intent 或把充值订单关联到原任务，因此对应转化指标不会有新的客户端数据；不能将空指标解读为充值或任务故障。

显式放弃付款会释放本站同商品待付名额，让微信不可用的用户切换 USD；这不撤销支付平台上的会话。旧会话之后成功，仍按验签事件交付。关闭 App 或付款窗口本身不会自动放弃服务器订单。

Figma 全部 93 个原型状态的代码入口、PRD 覆盖调整和待验收范围见 [`../../docs/glance-billing-state-audit.md`](../../../docs/glance-billing-state-audit.md)。这份对照不是运行时的像素级验收报告。

上线漏斗、官网点击与免费终身 Pro 的最新操作及统计口径见 [上线统计说明](../../../docs/launch-analytics.md)。新增官网采集和正式环境 Pro 漏斗须先应用 `0024_launch_analytics.sql`，再部署服务端与官网，并发布包含新埋点的客户端。
