# Glance 任务积分审计 — 2026-10-23

初次审计发现代码不能保证「所有失败任务不扣积分」。用户随后授权修复并部署；服务端修复与数据库迁移已于 2026-10-23 上线。客户端改动待用户重新构建使用，未构建或运行 Glance。

## 生产部署记录

- 数据库备份：`/private/tmp/glance-before-refunds-20261023.sql`，本机权限 `0600`。
- 迁移：`0017_task_failure_refunds.sql` 已于 `2026-10-23 05:16:06 UTC` 应用；已只读确认两个新触发器安装成功。
- Worker：`glance-service`，版本 `8c534c9d-53a8-4153-a853-2bd7e58140db`；前一版本 `a007df83-75b0-4a58-a51b-22924bab1a44`。发布使用 `--keep-vars`。
- `https://api.glancepreview.com/health` 返回成功；新增 settle 接口未登录请求返回预期的 HTTP 401，没有创建生产测试任务或扣款。
- 每 5 分钟 cron 已注册；本次未等待并观察一次真实定时执行。
- 迁移前后，已标记 failed / expired / cancelled 的生产任务中漏退记录均为 **0**，因此没有历史补退金额。核验时无 queued / claimed / running 任务。

## 修复结果与上线条件

- `0017_task_failure_refunds.sql`：生产任务进入 failed / expired / cancelled，一律按实际扣款流水全额退点。退款流水唯一，重复操作不多退。迁移同时补退历史上已标记失败、过期或取消但没有退款的任务；不推断历史 succeeded 任务是否交付失败。
- 服务端独立处理掉线 Worker 和超时：失效租约回队，运行任务从创建起超过 30 分钟终止退款；新客户端生成成功后 30 分钟未确认交付也退款。清理在状态查询、队列请求和每 5 分钟 cron 中执行，因此无人请求时到账可能比截止时间晚约 5 分钟。
- 所有 Worker 都校验成功结果；空结果、空文本和非法结果结构会失败并退款。
- 新客户端使用持久化的 Idempotency-Key，同一次提交的网络重发不会重复扣款。请求响应丢失、提交前取消通过按用户隔离的 abandonment 记录处理，迟到的提交不能再次扣款。
- 下载、HTTP 响应、本地保存失败均发起退款。结果文件及其记录保存后才确认交付；未完成的退款或交付确认持久化，恢复网络或登录后重试。客户端读取真实扣款与退款信息，未确认时显示待确认，不能冒充已到账。
- 已确认交付的成功任务不能随后改成失败退款；这是防止重复结算的边界。此前已经成功交付的文件被用户删除后重新下载，不能视为原任务未交付。

验证：服务端完整测试 **88 项通过（7 个文件）**，TypeScript 类型检查通过；两个 Swift 任务文件使用实际系统 SDK、应用依赖桩进行独立类型检查通过；中英文 strings 校验及 `git diff --check` 通过。此结果不等于完整 App 构建、UI 测试或线上账目验证。

上线顺序：先应用数据库迁移 `0017`，再部署服务端，最后由用户重新构建并使用客户端。前两步已完成；交付确认、断网恢复及稳定请求标识需要新版客户端。旧客户端不发送 deliveryRequired，不会自动进入交付确认超时流程。

## CLI 补充核查与修复

用户要求继续核查 `glance-cli` 后，确认 CLI 不直接操作积分，生产任务退款仍由服务端终态触发器执行。本地 `widget test` 不创建付费任务。以下 CLI 缺口已修复：

- 失败只上报一次且不落盘：现在先持久化失败，再重试上报；重新领取时优先补报失败，不重复执行模型。磁盘保存失败仍尝试上报，并明确记录服务端超时兜底。
- 409 终态信息被 API 层丢弃：保留服务端错误码和任务状态；区分已结束与凭证失效，明确结束才清理待上报记录。
- 成功响应缺少明确状态也被当成确认：现在保留记录并重试；成功日志不再等同于用户交付完成。
- 空白文本和零字节文件能通过输出校验：现在拒绝并走失败上报。文件扩展名/MIME 校验不等于媒体完整性或质量判断，远端 URL 的交付仍由客户端验证。
- 输入下载不计入执行超时、缺少取消检查：下载与执行共享 1500 秒预算，下载分段检查，超时终止子进程并上报 `worker_timeout`；结果上传重试前也检查取消。

验证：CLI 完整 **60 项测试通过**（含新增 14 项失败恢复测试），网络请求均使用 mock；已有取消测试还验证了子进程组终止。未启动真实 Worker、未调用生成模型或修改生产余额。本次修改尚未更新运行中的 Worker，需要安装当前源码并重启 Worker 生效；操作见 `glance-cli/README.md`。

## 原始审计记录（修复前）

以下内容保留初次复现证据，路径行号对应修复前代码。临时审计用例断言的是旧错误行为，不应作为修复后回归测试运行；正式回归测试在 `GlanceService/test/task-refunds.test.ts`。

## 验证范围和结果

- 本地 Cloudflare Workers / D1 测试环境，使用仓库全部迁移和当前服务端代码；不代表线上迁移或历史账目已验证。
- 原有测试：`npm test -- test/billing.test.ts test/accounts-credits.test.ts test/task-lifecycle.test.ts test/task-queue.test.ts`，60 项通过。
- 临时审计用例：5 项完成复现。它们断言当前行为以确认问题，**不是**「失败不扣费」验收通过。
- 临时用例保存在 `/private/tmp/glance-task-credit-audit.test.ts`；需要复现时复制至 `GlanceService/test/task-billing-audit-temp.test.ts`，在 `GlanceService` 执行 `npm test -- test/task-billing-audit-temp.test.ts`。核查结束后移出正式测试目录，以免将错误行为固化成产品契约。

## 正常路径

任务创建时即扣点，任务记录、扣款流水与余额变更由数据库触发器原子完成。服务端状态进入 failed / expired，或从 queued 进入 cancelled 时，自动退还该任务原价；退款流水 `refund:<taskID>` 唯一，重复通知不会重复退款。拒绝输入、余额不足和队列满等已有检查覆盖；免费任务不扣点。

补充 API 复现：初始余额 10000，任务价格 7；Worker 上报 `failed / invalid_user_input` 后余额回到 10000，`refundedCredits=7`，再次上报返回 409 且余额不变。说明用户输入问题只要被正确记为服务端失败，也会退款。

## P1：超时自动取消会留下扣费

- `Glance/Sources/WidgetTaskClient.swift:502`：轮询超过 1800 秒，客户端调用 DELETE 取消远端任务并向用户报失败。
- `GlanceService/migrations/0013_pricing_licenses_payments.sql:79`：退款触发器只退 queued → cancelled，claimed / running → cancelled 不退。
- API 复现：创建并运行 7 点任务后调用同一 DELETE 路径，返回 cancelled、refundedCredits=0，余额仍为 9993。
- 用户主动取消运行中任务也采用此路径。无论主动取消政策如何，系统超时导致的失败不能套用不退款取消政策。
- 修复要求：区分系统失败与主动取消；所有失败必须全额退款，并审视运行中主动取消的产品政策和明确告知。退款迁移、客户端错误处理与测试要一致。

## P1：Worker 掉线可能永久占款

- `GlanceService/src/pricing.ts:157`：cron 仅处理超时 queued，以及达到 maxAttempts 的 claimed / running。
- 未达到重试上限的失效租约，仅在 Worker 再次拉取任务时回队。若 Worker 不再上线，任务不会回队，也不会满足队列过期条件。
- 复现：第一次领取后，将创建时间和租约到期时间设为一天前；反复执行清理和查询后仍为 claimed、attempts=1、refundedCredits=0，余额 9993。
- 修复要求：定时任务独立回收失效租约；设置有界的全生命周期截止时间，在没有 Worker 和客户端的情况下也能结束失败任务并退点。

## P1：结果未成功交付仍可能保留扣费

- `GlanceService/src/index.ts:1076`：空结果和输出结构检查只在 developerTask 路径执行。旧 Worker token 路径绕过这些检查。
- API 复现：注册并分配旧 Worker，提交 succeeded 和空 artifacts，接口返回 200，查询为 completed、result=[]、refundedCredits=0，余额仍为 9993。
- `Glance/Sources/WidgetTaskManager.swift:260`：下载网络错误或本地保存失败只改变本地状态，未向服务端发起交付失败确认或退款。服务端已有 succeeded 状态不会触发失败退款。
- 同一下载路径未检查 HTTP 成功状态及实际结果有效性，存在把 HTTP 错误响应文件保存为成功结果的风险（代码检查发现，未运行 App 复现）。
- 修复要求：统一所有 Worker 成功结果校验，检查下载响应和结果有效性；建立可验证、可重试的交付失败处理，避免仅相信客户端声明就开放任意退款。不能把「Worker 返回成功」直接等同于用户收到可用结果。

## P1：网络自动重发可能产生重复扣费

- `Glance/Sources/WidgetTaskClient.swift:82`：直连发生 NSURLError 后，会通过系统网络自动重发同一请求，包含任务创建 POST。
- `Glance/Sources/WidgetTaskClient.swift:450`：提交任务没有携带 Idempotency-Key，也没有跨重启保存请求标识。
- 服务端支持按用户和请求标识去重，但客户端未接入。
- API 复现：相同请求不带标识提交两次，得到不同任务 ID，7 点扣两次，余额 9986。若首个请求已被服务端受理、只是响应丢失，就会触发该风险；本次未模拟真实网络丢包。
- 修复要求：每次逻辑任务提交前生成并持久化稳定请求标识；网络回退、响应丢失恢复和重启对账复用该标识。重新生成一个新任务与重试原请求必须明确区分。

## P2：客户端没有接收实际扣费和退点信息

- `GlanceService/src/index.ts:653`：任务状态返回 creditCost、refundedCredits 和 balance。
- `Glance/Sources/WidgetTaskClient.swift:607`：TaskResult 未解码这些字段。
- `Glance/Sources/WidgetTaskManager.swift:45`：记录存在字段和展示文案，但当前运行链路没有为它们写入服务端账务结果。
- 影响：即使实际已经退款，任务中心也无法可靠告知用户退款金额。取消 API 的响应仅记录日志，没有同步账务。
- 修复要求：以服务端流水为准同步账务状态；区分已退款、等待确认和无需扣费，不能未经确认显示已退款。

## 后续验收要求

应新增规则驱动的回归测试：系统超时退款、无人值守租约回收、所有 Worker 空结果拒绝、下载和保存失败恢复、网络重发只扣一次，以及退款到账后的客户端展示。修复部署后还需只读核对生产迁移及失败任务的扣款/退款净额；本次未确认线上是否已有受影响用户，也没有更改任何用户余额。
