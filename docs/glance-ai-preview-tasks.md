# Glance 全栈执行任务清单（AI 可执行）

> 方向与工期：`docs/glance-ai-preview-plan.md`。本文件是执行版，覆盖三个代码库：
> - **G**：macOS App（`Glance/`，Swift/AppKit）
> - **S**：服务端（`GlanceService/`，Cloudflare Worker + D1 + R2，TypeScript）
> - **C**：开发者 CLI 与 Worker（`glance-cli/`，Python ≥3.11，仅用标准库）
> - **W**：官方 Widget 代码（`widgets/<uuid>/`）
> - **H**：人工任务（AI 只准备脚本和文档）
>
> 创建：2026-10-12。执行者每完成一个任务，就更新本文件中该任务的状态。行号是 2026-10-12 的快照，**执行前必须先 grep 符号重新定位**。

---

## 0. 执行者必读

### 0.1 产品核心
**Glance 是 AI 时代的 Preview：看图看视频是主动作，看完不满意就地用 AI 改，改完用对比确认。**
主路径：**看 → 改（Widget）→ 对比**。服务端和 CLI 的任务都是为了让「改」这一步可靠、可取消、可控成本。

### 0.2 已确认的产品决定（不要重新讨论）
- D1 Widget 结果成功后**保持现有逻辑**：插到源图右边并直接展示结果。**不自动进入对比**，用户自己决定。
- D2 **不改工具栏 Widget 按钮**（它继续打开 Market）。跑 Widget 的入口是右键菜单（图片和视频都已有 Widgets 子菜单）。
- D3 预装目前已有的全部 Widget。
- D4 Peek 改为用户主动开启的高级功能；首次启动不要求任何权限。
- D5 开发者平台冻结：不给审核、灰度、OAuth、CLI 命令加新功能（修 bug、加固安全、适配新契约不算新功能）。
- D6 后端唯一对外域名：`api.glance.mcreator.ai`（需要 H 任务确认它已绑定到 `glance-service` Worker）。
- D9（2026-10-12）签名**先用个人 Apple Developer 账号**，mcreator 组织账号和 D-U-N-S 暂不办。验证期先发自签名 DMG（`GLANCE_DMG=1 ./Glance/build.sh`），随 `INSTALL.md` 的放行说明一起发；验证通过后再办个人 Developer ID 做公证。
- D7 测试版鉴权：邀请码换设备 token；配额每人每天 20 个任务、全局每天 300 个，可在管理后台调整。
- D8（2026-10-12）图片信息面板**不再有 QUICK ACTIONS**（Remove Background / Upscale 2× 整块删除）；等待状态保持现状（只有呼吸边框，不加文字标签）；**视频没有滑杆对比，只有图片有**（视频保持并排对比）。

### 0.3 硬性规则
**通用**
1. **不要自行 commit / push / merge / deploy / 执行远程 D1 迁移**。每完成一个任务就汇报，等用户指示。
2. 不要把任何密钥写进仓库。新增密钥一律走 `wrangler secret put` 或环境变量，并在文档里写明名称。
3. 执行协议：按编号顺序；`依赖` 未完成的任务不要开始；遇到 🎨 先查 Figma，查不到就问用户；👤 只准备材料。

**G（来自 `CLAUDE.md`）**
4. **不要构建 App，也不要提出要构建**；不要启动 Glance，不要做 UI 操作测试（AppleScript、截屏、模拟输入都不行）。
5. Swift 改动只能用 `xcrun swiftc -parse` 做语法检查（**不做类型检查**）。交付时必须写明「未编译，需用户构建确认」。
6. 不得破坏 `KeyboardMonitor.swift` 的 CGEventTap 规则：专用线程、callback 不阻塞、重新启用、`passUnretained`、加锁。
7. 主线程不做同步网络/文件 I/O，不用 `semaphore.wait()`，不用轮询 Timer。
8. 窗口定位用 `ScreenManager`；样式复用 `PanelStyle.swift`。
9. 有 Figma 参考的界面必须 1:1 匹配；新增或改变布局的 UI 必须先有 Figma frame（Figma MCP 只读）。
10. Image Inspect filmstrip 缩略图的尺寸和间距在任何状态下都不变。
11. 日志中的用户内容一律用 `Logger.redact(...)` 包裹。
12. 新文案同时加到 `Glance/Resources/en.lproj` 和 `zh-Hans.lproj` 的 `Localizable.strings`。

**S**
13. 每个改变行为的 S 任务都必须带测试（S0.1 建好测试框架之后）；`npm run typecheck` 和 `npm test` 都要通过。
14. 新的数据库变更只能新增迁移文件（`migrations/00NN_*.sql`），不改已有迁移。
15. 不改变已有接口的成功响应字段名；只能新增字段。破坏性变更必须在「契约」一节登记，并列出 G/C 的配套任务。

**C**
16. 保持「仅用标准库」（`dependencies = []`）。
17. 每个行为改动都要在 `glance-cli/tests/test_cli.py` 加 unittest；用 0.6 的命令运行。

### 0.4 状态图例
`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成（等用户确认）· `[✓]` 用户已确认 · `[!]` 阻塞（写明原因）· `[—]` 已决定不做

### 0.5 汇报格式（每个任务完成后）
1. 改了哪些文件（以及新增的迁移/密钥名称）
2. 验证命令和结果
3. 未覆盖的风险
4. 需要用户做的事（构建、UI 测试、部署、执行迁移）

### 0.6 验证命令速查（在仓库根目录执行）
| 范围 | 命令 |
|---|---|
| G 语法 | `xcrun swiftc -parse Glance/Sources/<路径>.swift` |
| S 类型 | `cd GlanceService && npm run typecheck` |
| S 测试 | `cd GlanceService && npm test`（S0.1 之后可用） |
| C 测试 | `PYTHONPATH=glance-cli/src python3 -m unittest discover -s glance-cli/tests -v` |
| W 测试 | `cd widgets/<uuid> && python3 -m unittest test_main -v`（需要的依赖见各 Widget 的 README） |
| Figma 插件 | `cd layout/GlanceFigmaPlugin && node --check code.js && node test-generation.cjs` |
| 本地化 | 比对 en 与 zh-Hans 的 key 集合，以及代码中所有 `"…".localized` 的 key |

---

## 1. 接口契约（G / S / C 三方共同遵守）

本节是所有跨端任务的唯一依据。S 先实现，C 和 G 再适配。**任何改动都要先改本节。**

### 1.1 任务状态
| 状态 | 含义 | 是否终态 |
|---|---|---|
| `queued` | 等待 Worker 领取 | 否 |
| `claimed` | 已被领取，尚无心跳 | 否 |
| `running` | Worker 心跳中 | 否 |
| `succeeded` | 成功（`taskStatus` 对外映射为 `completed`，保持现状） | 是 |
| `failed` | 失败（`error_code` 说明原因，新增 `max_attempts`） | 是 |
| `cancelled` | 用户取消 | 是 |
| `expired` | **新增**：排队超时（默认 30 分钟无人领取） | 是 |

### 1.2 `GET /api/v2/tasks/:id`（客户端轮询）
在现有响应上**新增**字段：
```json
{
  "taskID": "…", "status": "queued|claimed|running|completed|failed|cancelled|expired",
  "processCount": 0, "attempts": 1,
  "progress": 42,            // 新增：0–100，来自 Worker 心跳；无数据时省略
  "phase": "processing",     // 新增：Worker 上报的阶段字符串（可选）
  "pollAfterMs": 3000,       // 新增：建议的下次轮询间隔
  "error": "error_code"      // 失败时的错误码字符串（沿用现有格式，不是对象）
}
```
`pollAfterMs` 规则：`queued` 为 3000，`claimed`/`running` 为 2000，终态省略。

### 1.3 `POST /api/v2/widget-tasks/:id/heartbeat`（Worker）
- 请求体（**新增，可选**）：`{"progress": 0-100, "phase": "string≤40"}`。
- 任务仍活动（claimed/running）：200 `{"status":"running","leaseExpiresAt":"ISO"}`。
- 任务已不活动（cancelled/expired/failed/succeeded）：**409** `{"success":false,"error":{"code":"task_not_active","message":"…"},"status":"cancelled"}`（沿用现有 `success:false` 外层；`status` 为当前真实状态，`succeeded` 映射为 `completed`）。
- **Worker 收到 409 或 404 时，必须终止该任务的子进程，丢弃 spool，不再上报结果。**
- 旧的 worker-token 心跳路径（legacy `pullTask`）同样遵守：不再对非活动任务返回 200。

### 1.4 `DELETE /api/v2/tasks/:id`（客户端取消）
现有行为保留，并补充：取消时清空 `lease_expires_at` 和 `claim_token_hash`；返回 200 `{"taskID","status":"cancelled"}`；任务已是终态时返回 409 `task_not_active`（替代现在的 404，同时客户端兼容 404）。

### 1.5 配额（D7）
- `POST /api/v2/tasks` 和 `POST /api/v2/uploads` 超出配额时返回 **429**，带 `Retry-After`（秒，到 UTC 次日 0 点），body：`{"error":{"code":"quota_exceeded","scope":"user|global"}}`。
- 默认值放在 `service_settings`：`quota_user_daily=20`、`quota_global_daily=300`。只有任务创建计数，上传不单独计数，但会检查当天是否已超额。

### 1.6 终端用户鉴权（D7）
- `POST /api/v2/beta/redeem`，body `{"code":"XXXX-XXXX"}`，成功返回 200 `{"token":"<明文，仅此一次>","createdAt":"ISO"}`；码无效、过期或用尽时返回 400 `invalid_invite`。
- 之后所有终端用户接口都用 `Authorization: Bearer <deviceToken>`。未知或已吊销的 token 返回 **401** `unauthorized`。
- `FLOW_TEST_TOKEN` 和 `DEVELOPER_TEST_TOKEN` 的现有语义保持不变（但见 S3.x 的生产清理）。

### 1.7 错误响应
统一为 `{"error":{"code":"snake_case","message":"可读文本"}}`。非预期异常返回 500 `internal_error`，**不再把原始异常信息返回给客户端**（只记日志）。

---

## P0 收尾

### [ ] P0-G1 提交上一轮的 W1 改动 👤
- 工作区里有未提交的改动：`Logger.redact` 与日志轮转、剪贴板恢复修复、删除 `.bak`、取消跟踪 DMG 和 `xcuserdata`、`.gitignore` 加 `*.dmg`、替换个人路径。
- 等用户构建并确认后，按用户指示提交。
- **用户测试点**：Release 构建触发一次预览，`app.log` 里没有选中的原文；在 VSCode 里选中文字并预览后，剪贴板保持原样。

### [x] P0-G2 回滚 Widget Menu Flow Figma 生成器（D2）
- 文件：`layout/GlanceFigmaPlugin/code.js`、`ui.html`、`test-generation.cjs`。
- 删除 `WIDGET_MENU`、`widgetMenuPanel`、`widgetMenuSceneBoard`、`widgetMenuVideoPlayback`、`WIDGET_MENU_MARKET`、`createWidgetMenuFlowScreen`、`generateWidgetMenuFlow`，以及 `generate-widget-menu-flow` 的消息处理、按钮和测试段（先用 `git diff --stat layout/GlanceFigmaPlugin` 确认该目录只有这次改动，如果是，可以直接 `git checkout --`）。
- 验收：插件检查命令通过；`grep -rn widget-menu-flow layout/GlanceFigmaPlugin` 无结果。

### [x] P0-C1 清理 CLI 仓库杂物（0.1 人天）
- 删除过期的构建产物 `glance-cli/build/` 和 `glance-cli/src/glance_cli.egg-info/`；在根目录 `.gitignore` 增加 `glance-cli/build/` 和 `*.egg-info/`（已有 `*.egg-info/` 的话就跳过）、`.glance-test-output/`（已有）。
- 删除空目录 `widgets/6442556d-aa53-4506-9539-0d80c445f363/` 和空目录 `GlanceService/GlanceService/`（先确认里面确实为空或只有空子目录）。
- 验收：`git status` 只显示删除和 `.gitignore` 的改动；C 测试通过。

---

## P1 主路径 MVP
**里程碑**：「看 → 改 → 对比」顺畅；任务能真正取消；客户端能看到进度。之后录演示视频。
**顺序**：S1.1 → S1.2 → S1.3 → C1.x → G1.x（G1.1–G1.8 不依赖服务端，可以先做）。

### 服务端 S

#### [x] P1-S1.1 建立测试框架（1 人天）
- **目标**：后续所有 S 任务都能写测试。
- **步骤**：
  1. devDependencies 增加 `vitest` 和 `@cloudflare/vitest-pool-workers`。版本：先查 pool 包的 `peerDependencies`，选与已安装 wrangler（4.131.x）兼容的组合，写死精确版本。
  2. 新增 `GlanceService/vitest.config.ts`：用 pool 的 workers 配置指向 `wrangler.toml`；用 `readD1Migrations("migrations")` 读迁移，通过 binding `TEST_MIGRATIONS` 传给 setup 文件；在 miniflare `bindings` 中提供测试密钥：`SESSION_SECRET`、`MEDIA_SIGNING_SECRET`、`WORKER_TOKEN_PEPPER`、`FLOW_TEST_TOKEN`、`DEVELOPER_TEST_TOKEN`、`ADMIN_TOKEN`、`ADMIN_USERNAME`、`ADMIN_PASSWORD`、`ADMIN_PATH`。如果 pool 需要 `nodejs_compat`，**只在测试配置里加**，不改 `wrangler.toml`。
  3. 新增 `GlanceService/test/setup.ts`：调用 `applyD1Migrations(env.DB, env.TEST_MIGRATIONS)`。
  4. 新增 `GlanceService/test/tsconfig.json`（引用 pool 的类型），`package.json` 增加 `"test": "vitest run"`。
  5. 写冒烟测试 `test/smoke.test.ts`：`GET /health` 返回 200；`GET /api/v2/widgets` 返回 200 且是数组。
  6. 同步修正过期的 `worker-configuration.d.ts`，或改为从 `index.ts` 的 `Env` 导出类型，二选一并说明。
- **验收**：`npm test` 和 `npm run typecheck` 都通过。
- **注意**：Google OAuth 会调用真实的 `fetch`（`index.ts` 约 123、130 行），相关测试要 mock fetch。本任务不需要测 OAuth。

#### [x] P1-S1.2 取消语义闭环（0.75 人天）
- **依赖**：S1.1。**契约**：1.3、1.4。
- **现状**：
  - 取消路由（`index.ts` 约 1134–1140）只改 status，不清 lease 和 claim hash。
  - `taskHeartbeat`（约 943–954）无论是否更新成功都返回 200 `running`；legacy worker-token 路径对已取消的任务也返回 200。
  - result 和 heartbeat 的 worker-token 路径不检查 `widget_workers.status`。
- **步骤**：
  1. 把取消逻辑抽成 `cancelTask(env, request, taskID)`：UPDATE 同时清空 `lease_expires_at` 和 `claim_token_hash`；终态时返回 409 `task_not_active`。
  2. `taskHeartbeat`：UPDATE 的 `meta.changes === 0` 时，查询当前 status 并返回 409 `{error:{code:"task_not_active"}, status}`；成功时返回 `leaseExpiresAt`。
  3. 两条 worker-token 路径（heartbeat、result）的 SELECT 加上 `widget_workers.status='active'`。
  4. `pullTask` 中 requeue 的 UPDATE（约 788 行）同时清空 `claim_token_hash`（与 `pullBatch` 约 837 行保持一致）。
- **测试**（`test/task-lifecycle.test.ts`）：建 widget 和 worker grant → 创建任务 → pull-batch 领取 → 取消 → 心跳返回 409 且 `status=cancelled` → result 返回 409；终态任务再次取消返回 409。
- **验收**：测试通过；typecheck 通过。

#### [x] P1-S1.3 进度上报与轮询间隔（0.5 人天）
- **依赖**：S1.2。**契约**：1.2、1.3。
- **步骤**：
  1. 新迁移 `0008_task_progress.sql`：`ALTER TABLE widget_tasks ADD COLUMN progress INTEGER;`、`ADD COLUMN phase TEXT;`。
  2. `taskHeartbeat` 解析可选 body：progress 夹到 0–100 的整数，phase 截断到 40 字符；写入表。body 为空或无效 JSON 时忽略，不报错（兼容旧 Worker）。
  3. `taskStatus`（约 600–614）返回 `progress`、`phase`、`pollAfterMs`（规则见 1.2）。
- **测试**：心跳带 progress=42 后，`GET /api/v2/tasks/:id` 返回 `progress:42` 和 `pollAfterMs:2000`；queued 状态返回 3000；完成后不含 `pollAfterMs`。
- **验收**：测试通过。

#### [x] P1-S1.4 错误响应不泄露内部信息（0.25 人天）
- **契约**：1.7。
- **步骤**：`fetch` 的 catch（约 1150–1153）中，非预期错误一律返回 500 `internal_error`（固定 message），原始错误用 `console.error` 记录；`readJSON` 遇到无效 JSON 时返回 400 `invalid_json`，不再返回 500。
- **测试**：发送无效 JSON 到 `POST /api/v2/tasks`（带合法 token）得到 400。
- **验收**：测试通过。

### CLI C

#### [x] P1-C1.1 Worker 响应取消：心跳 409/404 时终止任务（1 人天）
- **依赖**：S1.2（可以先按契约 1.3 编码，用 mock 测试）。
- **现状**：心跳线程（`worker.py` 约 76–82）忽略响应；子进程只在超时（1500s）时被杀；只杀直接子进程。
- **步骤**：
  1. `runtime.execute`：子进程用 `start_new_session=True` 启动（POSIX），超时或取消时用 `os.killpg(proc.pid, SIGTERM)`，等 5 秒，再 `SIGKILL`。Windows 下退回到 `proc.kill()`。`on_log=None` 分支（`subprocess.run`）也要改成可被终止的 Popen 实现。
  2. `execute` 接收一个 `threading.Event`（`cancel_event`）；等待子进程的循环每 0.5 秒检查一次，置位时按上面的方式终止，并抛出 `TaskCancelledError`。
  3. 心跳线程：收到 `APIError` 且 status 为 409 或 404 时，记录日志「任务已被取消/不再活动，停止执行」，并置位 `cancel_event`。
  4. `_run_task`：捕获 `TaskCancelledError` → `discard_results(taskId)` → 不调用 `/result`，直接返回。
  5. 心跳 body 增加进度：`execute` 支持子进程写 `GLANCE_TASK_PROGRESS_FILE`（新环境变量，指向临时目录里的文件，内容为 `{"progress":N,"phase":"…"}`），心跳线程读取后附在请求体里（契约 1.3）。在 `sdk.py` 增加 `report_progress(progress:int, phase:str="")` 辅助函数，原子写该文件（先写临时文件再 rename）。
- **测试**：
  - mock API 让心跳第二次返回 409 → 断言子进程（一个 sleep 60 的脚本）在 2 秒内被终止、spool 被丢弃、`/result` 未被调用。
  - 子进程再派生一个孙进程 → 取消后孙进程也不存在（POSIX 下用 `os.kill(pid, 0)` 检查）。
  - `report_progress(42, "processing")` 后，下一次心跳的 body 含 `progress:42`。
- **验收**：C 测试全部通过。

#### [x] P1-C1.2 Worker 主循环不因单个请求崩溃（0.25 人天）
- **现状**：`worker.py` 约 195–200 行上报 `widget_not_registered` 时没有 try；循环里的非 `APIError` 异常会让 Worker 退出。
- **步骤**：该上报包进 try，失败只记日志；主循环最外层捕获 `Exception`，记录堆栈后退避 5 秒继续（`KeyboardInterrupt` 和 `SystemExit` 不捕获）。
- **测试**：mock pull 返回未注册的 widget，且上报接口抛出 APIError → Worker 不退出，下一轮继续 pull。
- **验收**：测试通过。

### 客户端 G（G1.1–G1.8 不依赖服务端）

#### [x] P1-G1.1 机械拆分 ImageInspectWindow.swift（1 人天）
- **目标**：把 6.9k 行文件中的辅助类型挪到 `Glance/Sources/Inspect/`，**不改任何逻辑**。`project.yml` 的 sources 是 `path: Sources`，会递归包含子目录。
- **要挪的类型**（先 grep 定位起止行）：Compression 对话框相关（文件开头）、`WidgetTextResultWindow` 及其视图、`OCRResultWindow`、`InspectToastWindow`、`ActionMenuEntry` / `ActionMenuPanel` / `ActionMenuRow`、`MediaDropCanvasView`、`InspectImageViewport`、`ImageRevealView`、`ImageFilmstripView` 及其 item、`ImageInfoPanel` / `ImageInfoBlock`、`ImageDifferencePanel`、`ImageExporter` 及格式枚举。
- **步骤**：一个类型一个文件；跨文件访问时，把**类型级**的 `private` / `fileprivate` 改为 `internal`（只改必须改的）；不重命名，不改格式，保留注释。
- **验收**：每个文件 parse 通过；`git diff --stat` 新增行数 ≈ 删除行数。提醒用户：如果工程由 XcodeGen 生成，构建前需要重新生成（查看 `Glance/build.sh` 的做法后，告诉用户具体命令）。

#### [x] P1-G1.2 机械拆分 VideoCompareWindow.swift（0.5 人天）
- 挪到 `Glance/Sources/Video/`：`VideoInspectViewport`、`WebMVideoView`、`WebMStreamingFallback`、filmstrip、播放条和信息视图。`WebMVideoView` 也被 `ImageLoader.swift` 使用，必须是 `internal`。
- 验收同 G1.1。

#### [x] P1-G1.3 删除死代码（0.25 人天）
- **依赖**：G1.1。
- 删除（先 grep 确认没有调用方）：`ImageInspectWindow` 的 `runWidgetButton` 和 `updateRunWidgetButton()`；`StatusBarController.createMenu()`；`WidgetModels.swift` 的 `WidgetPlatformClient.review` / `promote`（它们调用的接口在服务端不存在）。
- 验收：grep 不到这些符号；parse 通过。

#### [x] P1-G1.4 删除有问题的隐藏 Widget 入口（0.5 人天）🎨
- **依赖**：G1.1。
- **现状**：信息面板的 QUICK ACTIONS 里，「Remove Background」会跑第一个已安装的图片 Widget，不管它是什么；「Upscale 2×」按名字猜。
- **步骤**：删除 `ImageInfoPanel` 的 `removeButton` / `upscaleButton` 及回调、`ImageInspectWindow.runDefaultWidgetTapped()`、`runUpscaleWidget()`，以及 `infoPanel.onUpscale = …` 等绑定。
- 🎨 删按钮会改变信息面板布局。先用 Figma MCP 查信息面板的参考 frame：Figma 里没有这个区块就整块删除；有就**停下来问用户**。
- 验收：grep 不到 `runDefaultWidgetTapped` 和 `runUpscaleWidget`；parse 通过。

#### [x] P1-G1.5 右键菜单的 Market 兜底入口（0.25 人天）
- **依赖**：G1.1。
- 图片的 `buildContextActionEntries()` 和视频的 `buildMoreEntries()`（视频的右键与 More 共用它）：
  - 没有兼容的 Widget：在原 Widgets 位置放一行 `"Widget Market…".localized`，点击调用 `WidgetMarketPanel.shared.toggle(from:)`。
  - 有兼容的 Widget：在 Widgets 子菜单末尾加分隔线和同一行。
- 本地化：en 为 `Widget Market…`，zh 为 `Widget 市场…`。
- 验收：两种情况下都有 Market 入口；parse 通过。

#### [x] P1-G1.6 对比按「源 ↔ 结果」配对（1 人天）
- **依赖**：G1.1、G1.2。
- **现状**：图片 `activateCompare(style:)` 把当前项和「第一个其他图片」配对；视频 `compareTapped()` 用 `(focusedIndex, focusedIndex == 0 ? 1 : 0)`。
- **步骤**：用 `WidgetTaskManager.shared.completedRecord(for:)?.source` 识别结果与源。
  - 当前项是结果、源在 session 里：配对 **(源, 结果)**，左/A 是原图。
  - 当前项是源、它有已完成的结果在 session 里：配对 (源, 最新结果)。
  - 其他情况保持原逻辑。
  - 视频用同样的规则。**不要**在结果完成时自动进入对比（D1）。
- 验收：parse 通过。**用户测试点**：去水印完成 → 点 Slider，左边是原图、右边是结果。

#### [x] P1-G1.7 抽出通用的结果插入函数（0.5 人天）
- **依赖**：G1.1。
- 从 `insertCompressedImage(at:url:)` 和 `insertWidgetResult(info:after:)` 抽出 `insertDerivedItem(_:afterSourceIndex:)`（只负责插入和刷新 filmstrip）。压缩保持进入并排对比；Widget 保持 `selectWidgetResult`。
- 验收：行为不变；parse 通过。

#### [x] P1-G1.8 结果文件按原文件名命名（0.5 人天）
- `WidgetTaskManager.destinationURL(for:response:fallback:)`：命名为 `<源文件名去扩展>.<commandName>.<ext>`；重名时追加 ` 2`、` 3`……；源是远程 URL 时用 lastPathComponent，为空时用 commandName；文件名中的 `/` 和 `:` 替换为 `-`。抽成静态纯函数。
- 验收：parse 通过。

#### [x] P1-G1.9 点击完成通知打开结果（0.5 人天）
- **依赖**：G1.6。
- 通知的 `userInfo` 带 record `id`；`AppDelegate` 实现 `UNUserNotificationCenterDelegate`，并在 `applicationDidFinishLaunching` 里设置 delegate。点击时用 [源, 结果] 打开 Inspect（视频则打开 VideoCompareWindow），当前显示结果；源不存在时只打开结果。
- 验收：parse 通过。

#### [x] P1-G1.10 Task Center「在 Inspect 中查看」带上原图（0.25 人天）
- **依赖**：G1.9。`AppDelegate.openTaskOutputInInspect(_:)` 改为复用 G1.9 的打开函数。

#### [x] P1-G1.11 任务进行中不禁用无关操作（0.5 人天）
- **依赖**：G1.1。`buildContextActionEntries()` 中，有活动任务时只禁用 **Rotate / Flip** 和**同一个 command 的重复运行**；Copy、格式导出、Base64、OCR、Compress 和其他 Widget 都保持可用。

#### [x] P1-G1.12 客户端适配新契约：取消、轮询间隔、新状态（1.25 人天）
- **依赖**：S1.2、S1.3、G1.11。**契约**：1.1–1.4。
- **步骤**：
  1. `WidgetTaskPhase`（`WidgetTaskClient.swift`）新增 `.cancelled` 和 `.expired`，都不计入 `isActive`。本地化：`Cancelled` / `已取消`，`Expired` / `已过期`。
  2. `WidgetTaskClient.cancel(taskID:)` 发送 DELETE；200、404、409 都视为已结束。
  3. `poll`（约 430–457）：每轮先检查取消标记；按响应的 `pollAfterMs` 决定下次间隔（夹在 1–10 秒，缺省 5 秒）；终态 `cancelled` / `expired` / `failed` 立即结束；收到 401/404 立即结束并报错（不再静默重试 30 分钟）；把 `progress` / `phase` 通过已有的 progress 回调更新到 record。
  4. 上传阶段取消：取消正在进行的 `URLSessionTask`。
  5. `WidgetTaskManager.cancel(_ id: UUID)`：有 `remoteTaskID` 就调服务端，然后 `update(phase: .cancelled)`。
  6. 入口：图片和视频右键菜单中，当前项有活动任务时，在 Widgets 位置显示「Cancel <命令名>」（`"Cancel %@"` / `取消%@`）。
  7. 🎨 Task Center 的取消按钮：先查 Figma 的 Task Center frame，没有就不做，并告诉用户。
- 验收：parse 通过。**用户测试点**：跑一个视频去水印 → 右键取消 → Task Center 显示「已取消」，Worker 日志显示子进程被终止。

#### [—] P1-G1.13 等待时的文字状态（已决定：保持现状，不做）
- **依赖**：G1.12（需要进度数据）。
- `InspectImageViewport.setWidgetProcessing(_:)` 现在设置了文字但强制隐藏。先用 Figma MCP 查 `Image Inspect / Widget Task Running / Focused Source` 和 `… / Browsing Another Image`；按 Figma 的位置、字号、颜色显示「<命令名> · <阶段> <进度>%」（没有进度时只显示阶段）。Figma 与 V2 spec 不一致时以 Figma 为准，并告诉用户。
- 验收：与 Figma 坐标 1:1（顶部原点换算为 AppKit 底部原点）；parse 通过。

---

## P1.5 大量任务时的处理能力（2026-10-12 高并发评估后新增）
**背景**：RunningHub 企业版可开 100 并发，但 Worker 现在最多同时 4 个任务、每个 Widget 同时只跑 1 个，企业版用不上。排队时用户也不知道要等多久，超时后服务端任务还在白跑。
**决定**：配额由用户按人配置额度（登录功能一起做，不在本节）；本节只解决「喂饱 100 并发」和「排队要诚实」。

### 契约补充（1.8）
- `POST /api/v2/tasks` 的 202 响应新增 `queuePosition`（整数，1 = 下一个被领取）和 `estimatedWaitSeconds`（整数，可省略）。
- 队列中 `queued` 任务数 ≥ `service_settings.task_queue_limit`（默认 300）时返回 **429** `{"error":{"code":"queue_full","message":"…"}}`，带 `Retry-After: 60`。
- `GET /api/v2/tasks/:id` 在 `queued` 状态时也返回 `queuePosition` 和 `estimatedWaitSeconds`。

#### [x] P1.5-C1 Worker 并发可配置（0.5 人天）
- `MAX_CONCURRENT` 改为读环境变量 `GLANCE_WORKER_MAX_CONCURRENT`（默认 4，上限 200）。
- 每个 Widget 的并发上限改为 `GLANCE_WORKER_PER_WIDGET_CONCURRENT`（默认 1 保持现状；0 表示不限）。`eligible()` 按「该 Widget 当前运行数 < 上限」过滤，而不是「是否在 busy 集合里」。
- 测试：设为 3 时，同一 Widget 可同时领取 3 个任务，第 4 个要等；设为 0 时不限。
- `glance-cli/deploy/worker.env.example`（P3 才建）里写上这两个变量；本任务先写进 `glance-cli/README.md`。

#### [x] P1.5-S1 排队位置、队列上限、预估等待（0.75 人天）
- `createTask`：插入前 `SELECT COUNT(*) FROM widget_tasks WHERE status='queued'`，≥ 上限则 429 `queue_full`；插入后返回 `queuePosition` = 同一 widget 中 `created_at` 更早的 queued 任务数 + 1。
- `estimatedWaitSeconds` = `queuePosition × 该 Widget 最近 20 个成功任务的平均耗时（completed_at − claimed_at） ÷ max(1, 该 Widget 最近 10 分钟内同时 running 的任务数)`；没有历史数据时省略。
- `taskStatus`：`queued` 时附带同样的两个字段。
- 迁移 `0009_queue_index.sql`：`CREATE INDEX idx_widget_tasks_status_created ON widget_tasks(status, created_at)`。
- 测试：上限设为 2 时第 3 个任务 429；3 个排队任务的 position 依次为 1、2、3；状态接口返回 position。

#### [x] P1.5-G1 客户端：显示排队、超时取消（0.75 人天）
- `WidgetTaskClient.poll`：超过 30 分钟放弃时**先调用 `cancel(taskID:)`**，再报错。
- 解析 `queuePosition` / `estimatedWaitSeconds`；`WidgetTaskRecord` 新增可选字段 `queuePosition`、`estimatedWaitSeconds`，由 progress 回调之外的新回调更新（或扩展现有回调）。
- Task Center 的状态文字：queued 且有位置时显示「排队中 · 前面 N 个 · 约 M 分钟」（`"Queued · %d ahead · ~%@"`，zh：`排队中 · 前面 %d 个 · 约 %@`）；只有位置没有时间时显示「排队中 · 前面 N 个」。
- 收到 429 `queue_full`：任务记为 failed，错误文案「服务繁忙，请稍后再试」（`"The service is busy right now. Please try again later."`）。
- Inspect 窗口不加新 UI（等待状态保持现状，D8）。

## P2 看图器优先
**里程碑**：首次启动零权限、开箱即用。本阶段只有 G 任务。

#### [x] P2-G2.1 Peek 开关与迁移（0.5 人天）
- 新增 `Preferences.peekEnabled`（key `<suite>.peekEnabled`），新用户默认 false。迁移只执行一次：key 不存在时，如果旧的 `enabled == true` 且两项权限都已授权，设为 true，否则设为 false。所有读取 `Preferences.enabled` 的地方改读 `peekEnabled`（注意排除无关的 `isEnabled`）。

#### [x] P2-G2.2 首次启动不要权限、授权后立即生效（1 人天）
- **依赖**：G2.1。
- `AppDelegate.checkPermissions()`：`peekEnabled == false` 时不弹引导、不启动键盘监听。首次启动（新增标记 `<suite>.hasLaunchedBefore`）时显示 Home（复用 `surfaceHomeIfIdle()` 的逻辑）。
- 新增 `setPeekEnabled(_:)`：开启时，权限齐全就 `startKeyboardMonitoring()`，否则弹 `OnboardingWindow`；关闭时 `KeyboardMonitor.stopMonitoring()`。Onboarding 授权完成后立即启动监听（不需要重启）；`preferencesChanged()` 里同步启停。只调用已有的 start/stop，不改 tap 线程模型。
- **用户测试点**：执行 `defaults delete com.glance.app` 后启动，直接看到 Home；在偏好设置里开启 Peek → 弹出引导 → 授权后热键立即可用。

#### [x] P2-G2.3 文案：Peek 是高级功能（0.25 人天）
- 偏好设置的「Enable Image Hover Preview」→ `Enable Peek (preview selected text)` / `启用 Peek（选中文本秒开预览）`。
- 托盘「Preview is on/off」→ `Peek is on` / `Peek is off`（`Peek 已开启` / `Peek 已关闭`）。
- `StatusBarController` 的 About → `Version %@\n\nThe Preview for the AI era: view images and videos, fix them with AI in place, and compare the result.` / `版本 %@\n\nAI 时代的 Preview：看图看视频，不满意就地用 AI 改，改完对比确认。`，版本号从 Bundle 读取。
- 🎨 托盘里 Peek 关闭时是否隐藏 Permissions 行：先查 Figma 的 Tray Popover frame，不确定就问用户；本任务默认不改布局。

#### [x] P2-G2.4 App 主菜单（1 人天）
- 在 `applicationDidFinishLaunching` 里设置 `NSApp.mainMenu`（标准 `NSMenu`，不需要 Figma）：
  - Glance：About、Preferences…（⌘,）、`Set as Default Viewer…`、Hide（⌘H）、Quit（⌘Q）。
  - File：Open…（⌘O，`NSOpenPanel` 多选图片和视频，走 `flushPendingOpenURLs()` 同一条路径）、Open Folder…（⌘⇧O，复用 Home）。
  - Edit：标准 Undo/Redo/Cut/Copy/Paste/Select All（标准 selector）。
  - Window：Minimize（⌘M）、Close（⌘W）。
- 检查与 Home/Inspect 现有 `performKeyEquivalent` 是否冲突。

#### [x] P2-G2.5 设为默认看图器（0.5 人天）
- **依赖**：G2.4。确认弹窗后，对 `UTType.image`、`.movie`、`org.webmproject.webm` 调用 `NSWorkspace.shared.setDefaultApplication(at:toOpen:completionHandler:)`（macOS 12+），完成或失败都给出反馈。

#### [x] P2-G2.6 Finder 打开的文件也进历史（0.25 人天）
- `flushPendingOpenURLs()` 中调用 `recordMediaInHistory(_:)`。

#### [—] P2-G2.7 视频滑杆对比（已取消：视频不需要滑杆，只有图片有）
- 先查 `Video Inspect v4 / …` 系列 frame 里有没有滑杆状态；没有就请用户提供设计。设计到位后：复用 `ImageRevealView` 的交互，两个 `VideoInspectViewport` 同步播放和 seek，`VideoCompareWindow.Mode` 增加 `slider`，配对规则同 G1.6。

---

## ⛳ 决策点：2 周验证 👤
- 录演示视频，同时投小红书和少数派/V2EX，分开统计报名。**合计 ≥30 人报名**才进入 P3；否则先换演示或渠道再试。
- AI 可协助（需用户发起）：分镜脚本、两个渠道的文案、报名问卷（含付费意愿题）。

---

## P3 对外内测
**里程碑**：熟人可以安装；服务端有鉴权、配额和清理；官方 Worker 在 VPS 上稳定运行。
**顺序**：S3.1–S3.6 → H3.1（部署）→ C3.x → G3.x → H3.2–H3.5。

### 服务端 S

#### [ ] P3-S3.1 邀请码与设备 token（1.5 人天）
- **依赖**：S1.1。**契约**：1.6。
- **步骤**：
  1. 迁移 `0009_beta_access.sql`：
     - `beta_invites(code_hash TEXT PRIMARY KEY, note TEXT, max_uses INTEGER NOT NULL DEFAULT 1, used_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, expires_at TEXT)`
     - `device_tokens(token_hash TEXT PRIMARY KEY, invite_code_hash TEXT NOT NULL, created_at TEXT NOT NULL, last_seen_at TEXT, revoked_at TEXT)`
  2. `POST /api/v2/beta/redeem`：码统一转大写、去空白后取 `digest`；在同一个 batch 里检查并 `used_count+1`（条件 UPDATE：`used_count < max_uses AND (expires_at IS NULL OR expires_at > now)`，`changes===0` 时返回 400 `invalid_invite`）；生成 32 字节随机 token（base64url），只存哈希，明文返回一次。不做 IP 限流，防暴力猜测靠码的熵：邀请码由 admin 接口生成，格式 `XXXX-XXXX-XXXX`（12 位，字母数字，去掉易混淆字符）。
  3. `requireUser`（约 186–190）：`FLOW_TEST_TOKEN` 保持原逻辑；否则查 `device_tokens`（未吊销），找到就返回 `user_<token_hash>`（**与现有 owner_id 格式保持兼容**：现在是 `user_<sha256(token)>`，新格式也用 sha256，使老数据仍归属同一身份），并节流更新 `last_seen_at`（距上次超过 1 小时才写）；找不到就抛 `Unauthorized`（401）。
  4. Admin：`POST /api/admin/v2/beta-invites` body `{count:1-100, maxUses, expiresInDays, note}`，返回明文码列表（只返回一次）；`GET /api/admin/v2/beta-invites`（只返回哈希前 8 位、用量和备注）；`POST /api/admin/v2/device-tokens/:hashPrefix/revoke`。
  5. 管理后台页面 `site/admin/index.html`：增加「邀请码」区块（生成、列表、吊销）。沿用页面现有的样式和写法。
- **测试**：随意 token → 401；兑换后的 token 能创建上传；用尽的码 → 400；吊销后 → 401；`FLOW_TEST_TOKEN` 仍可查询任意任务。
- **验收**：测试和 typecheck 通过；`GlanceService/README.md` 写明接口和 curl 示例。

#### [ ] P3-S3.2 配额（1 人天）
- **依赖**：S3.1。**契约**：1.5。
- 迁移 `0010_daily_usage.sql`：`daily_usage(owner_id TEXT NOT NULL, day TEXT NOT NULL, task_count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(owner_id, day))`，另用 `owner_id='__global__'` 记全局计数。
- `createTask`：插入任务前用条件 UPSERT 原子地 +1（个人和全局都要；任一超过上限就回滚并返回 429）。上限读取 `service_settings` 的 `quota_user_daily` / `quota_global_daily`，缺省为 20 / 300。`uploadAsset` 只检查不计数。`FLOW_TEST_TOKEN` 和 `review_test` 任务不计入。
- Admin：`adminGlanceConfig` 旁新增 `GET/PUT /api/admin/v2/quota`；后台页面加两个数字输入框。
- **测试**：把上限设为 2 → 第 3 个任务返回 429，带 `Retry-After` 和 `scope:"user"`；全局上限同理。
- 验收：测试通过。

#### [ ] P3-S3.3 任务过期、重试上限、定时清理（1.25 人天）
- **依赖**：S1.2。**契约**：1.1。
- 在 `pullBatch`（约 837 行）和 `pullTask`（约 788 行）的 requeue 中：`attempts >= 3` 的任务改为 `failed`，`error_code='max_attempts'`。
- 新增 `scheduled(event, env, ctx)` 导出，`wrangler.toml` 增加 `[triggers] crons = ["*/10 * * * *"]`：
  1. `queued` 且 `created_at` 早于 30 分钟（可在 `service_settings.task_queue_timeout_minutes` 配置）→ `expired`。
  2. lease 已过期的 claimed/running → 执行同样的 requeue 或 `max_attempts` 逻辑（这样即使没有 Worker 在拉取，也能清理）。
  3. `widget_assets.expires_at < now` → 删除 R2 对象和记录（每次最多 200 条）。
  4. 删除过期的 `developer_sessions`、`developer_oauth_states`、`developer_auth_codes`。
- `uploadAsset` 写入 `expires_at = now + 24h`；`uploadTaskArtifact` 写入 `now + 7d`（结果需要保留更久，供客户端下载和重试）。
- **测试**：用 `scheduled` 的测试辅助函数触发；构造 31 分钟前的 queued 任务 → `expired`；attempts=3 且 lease 过期 → `failed/max_attempts`；过期资产的 R2 对象被删除。
- 验收：测试通过。

#### [ ] P3-S3.4 输入 URL 校验（防 SSRF）（0.5 人天）
- **现状**：`createTask`（约 757–768）不校验 `input.url` 和 `images` / `videos` 的 URL；`adminAction` 的 test 路径反而用了 `validRemoteMediaURL`。
- **步骤**：`createTask` 对所有输入 URL 调用 `validRemoteMediaURL`，并加强该函数（约 50–59）：只允许 https；拒绝 userinfo、IP 字面量（v4/v6）、`localhost`、`.local`、`.internal`、`.lan`；允许本服务签名的 `/api/v2/assets/` URL。DNS 解析到私网地址的情况在 Worker 端无法可靠判断，由 C3.1 在 Worker 侧兜底。
- **测试**：`http://`、`https://127.0.0.1`、`https://[::1]`、`https://foo.local` → 400 `invalid_input_url`；签名资产 URL → 通过。

#### [ ] P3-S3.5 签名与 Market 健壮性（0.75 人天）
- **现状**：官方 / 后台创建的 manifest 带假签名 `{keyID:"admin-console", value:"admin-created"}`（约 374–376，迁移 0006）；`publicManifest` 每次请求都临时签名且不持久化。
- **步骤**：
  1. 新增 `signOfficialManifest`：用同一把 `GLANCE_SIGNING_KEY_PKCS8` 签名，保留 `official:true`，keyID `glance-market-2026-02`。
  2. 后台创建或编辑、approve/promote 时，签名后**写回** `widget_versions.manifest_json`。
  3. 新增 admin 动作 `POST /api/admin/v2/manifests/resign`：对所有 published / gray_release 版本重签并写回，返回处理数量。
  4. `publicManifest` 不再临时签名：未签名的版本记录日志并在列表中跳过（不返回给客户端）。
  5. `ensureOfficialWidgets`：改为只在 `adminAllWidgets` 中运行，不再在 `listWidgets` / `widgetDetail` / `createTask` 中每次运行。
- **测试**：重签后的 manifest 能用测试公钥（`crypto.subtle` 从测试私钥导出）验签；未签名版本不出现在 `/api/v2/widgets` 中。
- **部署顺序**（写进汇报）：先部署 S → 执行 resign → 再发布带 G3.3 的客户端。

#### [ ] P3-S3.6 加固与清理（1 人天）
- 常量时间比较：新增 `safeEqual(a,b)`（先比较长度，再对两者的 SHA-256 做逐字节 XOR），替换约 76、152、160、184、192、193、199 行的 `===` / `!==`。
- `adminLogin`：失败计数存入 `service_settings`（key `admin_login_failures:<ip>`，带时间窗），15 分钟内失败 5 次就返回 429。
- `adminAction`：只允许 POST（`test` 除外的所有动作；GET 返回 405）。
- CORS：admin 接口不再返回 `*`，只对 `PUBLIC_ORIGIN` 同源放行；公共接口保持现状。
- `wrangler.toml` 的 `[assets]` 增加 `run_worker_first = true`（或 `not_found_handling` 加上路由判断），确保 `/admin/` 不会被静态资源直接返回；如果改为 worker-first，要确认 `/` 和 `/widgets/` 页面仍能由 `ASSETS.fetch` 正常返回。
- 缺失的索引（新迁移 `0011_indexes.sql`）：`widget_tasks(owner_id)`、`widget_tasks(version_id, type, status)`、`widget_tasks(created_at)`、`widget_audit_logs(widget_id, action)`、`widget_review_results(version_id)`、`widgets(status)`。
- 无上限的查询加 `LIMIT`（默认 200）：`adminAllWidgets`、admin submissions 列表、`listWidgets`、`developerWidget` 的版本列表。
- `adminGlanceConfig` 的 PUT 拒绝名字中含 `key`、`secret`、`token` 的字段（防止把 Freeimage key 之类误放进公开 config；客户端在 key 缺失时会安全地回退到 R2）。
- `test_passed` 状态在代码里被引用但从未被设置：删除这些引用，或在 review 结果成功时设置它（推荐删除，审批逻辑以 `widget_review_results` 为准）。
- **测试**：admin 登录连续失败 6 次 → 429；GET 调用 admin 动作 → 405；config PUT 带 `freeimageKey` → 400。

#### [ ] P3-S3.7 生产配置与域名（0.25 人天，执行部分 👤）
- **依赖**：H3.0（确认域名绑定）。
- `wrangler.toml`：增加 `[[routes]] pattern = "api.glance.mcreator.ai", custom_domain = true`（以 H3.0 确认的方式为准），`PUBLIC_ORIGIN` 改为 `https://api.glance.mcreator.ai`。
- **注意**：`PUBLIC_ORIGIN` 改变会影响 Google OAuth 回调地址，需要在 Google Console 登记新地址（写进 H3.1）。workers.dev 地址保留一段时间，供旧版 CLI 使用。
- `GlanceService/README.md`：删除 admin 路径和生产 admin URL；更新部署步骤（迁移 0008–0011、新的 secrets、cron）。

### CLI C

#### [ ] P3-C3.1 输入下载加固（防 SSRF）（0.5 人天）
- **现状**：`runtime.prepare_input`（约 38–102）只检查 https；urllib 会跟随重定向，包括跳转到 http 或内网。
- **步骤**：
  1. 下载前解析主机名（`socket.getaddrinfo`），任一地址是私网、回环、链路本地、保留地址或多播（用 `ipaddress` 判断）就拒绝。
  2. 自定义 `HTTPRedirectHandler`：每次重定向都重新检查 scheme（必须是 https）和目标地址；最多 5 次跳转。
  3. 允许本服务签名资产的主机（`GLANCE_API_URL` 的主机）。
- **测试**：`https://127.0.0.1/x`、解析到 `10.0.0.1` 的主机名（mock `getaddrinfo`）、https→http 的重定向都被拒绝；正常的公网 https 地址通过（mock 网络）。

#### [ ] P3-C3.2 子进程隔离（0.5 人天）
- **现状**：子进程继承完整环境变量（包括 `GLANCE_MOCK_TOKEN`）；task JSON 里有 `claimToken`；`validate_outputs` 接受任意绝对路径（约 141–150 行），还会跟随符号链接。
- **步骤**：
  1. 环境变量白名单：`PATH`、`HOME`、`LANG`、`LC_*`、`TMPDIR`、`PYTHONPATH`、`VIRTUAL_ENV`、`GLANCE_TASK_OUTPUT_DIR`、`GLANCE_TASK_PROGRESS_FILE`，加上该 Widget 声明需要的变量。声明方式：在本机注册表的 `widgets` 表增加 `env_allowlist` 列（迁移逻辑参照已有的 `python_path` 列），通过 `glance widget bind --env RUNNINGHUB_API_KEY --env FFMPEG_PATH …` 设置（这是适配安全加固所需，不算新功能）；`widget add` 也接受 `--env`。默认不传任何 `GLANCE_*` 凭据。
  2. 传给子进程的 task JSON 删除 `claimToken`。
  3. `validate_outputs`：`path` 解析（`resolve(strict=True)`）后必须位于本次任务的临时目录或 `code_path` 之内；拒绝符号链接逃逸。
- **测试**：子进程读不到 `GLANCE_MOCK_TOKEN`；声明过的 `RUNNINGHUB_API_KEY` 能读到；输出 `/etc/hosts` 被拒绝；task JSON 不含 claimToken。
- **兼容提醒**：已在用的 Widget 需要用 `bind --env` 重新声明所需变量（写进 H3.2 的部署步骤）。

#### [ ] P3-C3.3 Worker 适合无人值守运行（1 人天）
- **步骤**：
  1. **SIGTERM**：安装 handler，进入「排空」模式：停止拉取新任务，等待运行中的任务最多 `GLANCE_WORKER_DRAIN_SECONDS`（默认 60 秒），超时就按 C1.1 的方式终止子进程并退出。SIGINT 也走同样逻辑；「正在等待…」的日志要在开始等待**之前**打印。
  2. **401**：pull 收到 401 时，记录明确日志（「凭据失效，请重新登录或更新 token」），退避到 300 秒，而不是一直按 30 秒重试；连续 401 超过 1 小时就以退出码 3 退出（交给 systemd 决定是否重启并报警）。
  3. **429**：遵守 `Retry-After`。
  4. **失败上报重试**：`_run_task` 中上报 `failed` 也走 `_deliver` 的重试逻辑。
  5. **spool 清理**：启动时和每小时清理一次 `pending-results/` 中超过 24 小时的条目；`load_results` 遇到损坏的 spool 时丢弃并记日志，不再抛异常。
  6. **默认 API 地址**：`api.py` 的 `BASE_URL` 默认改为 `https://api.glance.mcreator.ai`（依赖 S3.7 上线）；在调用时读取 `GLANCE_API_URL`，而不是在 import 时读取。
  7. **上传**：`upload_task_file` 改为流式读取文件，不再一次性读进内存。
- **测试**：给 Worker 进程发 SIGTERM（测试中用线程模拟）→ 不再 pull，运行中的任务完成或被终止后退出；连续 401 的退避；429 遵守 `Retry-After`；24 小时前的 spool 被清理；损坏的 spool 不导致异常。

#### [ ] P3-C3.4 `widget test` 支持多输入（0.25 人天）
- **现状**：`command_test`（约 242 行）只能传一个 `--input`，所以测不了需要两张图的「换装」。
- **步骤**：`--input` 改为可重复参数；根据 manifest 的 `parameterSchema` 中 `images` / `videos` 的定义，把多个本地路径填入 `imagePaths` / `videoPaths`（只有一个时同时设置 `path`，保持兼容）。
- **测试**：两个 `--input` 时，子进程收到的 `imagePaths` 长度为 2。

#### [ ] P3-C3.5 VPS 部署文件（0.5 人天）
- 新增 `glance-cli/deploy/glance-worker.service`（systemd unit）：专用用户 `glance`；`EnvironmentFile=/etc/glance/worker.env`（权限 0600）；`ExecStart=/opt/glance/.venv/bin/glance worker`；`Restart=always`；`RestartSec=10`；`KillSignal=SIGTERM`；`TimeoutStopSec=90`；`KillMode=control-group`；`NoNewPrivileges=true`；`ProtectSystem=strict`；`ReadWritePaths=/home/glance/.config/glance /tmp`。
- 新增 `glance-cli/deploy/worker.env.example`：`GLANCE_API_URL`、`GLANCE_MOCK_TOKEN` 或说明如何放置 `session.json`、`RUNNINGHUB_API_KEY`、`RUNNINGHUB_API_KEY_AI`、`FREEIMAGEKEY`、`GLANCE_WORKER_DRAIN_SECONDS`。
- 新增 `glance-cli/deploy/README.md`：Debian 12 / Ubuntu 24.04 的步骤（安装 python3.11+ 和 ffmpeg、克隆仓库、`./glance-cli-run.sh`、为每个 Widget 建 venv 并安装依赖、`glance widget add <dir> --python … --env …`、启用服务、查看 `journalctl` 和 `glance worker logs`）；无浏览器时的登录方式（SSH 端口转发完成 `glance login`，或拷贝 `session.json`；说明 session 30 天过期、需要续期）。
- 验收：`systemd-analyze verify` 无法在 macOS 上运行，所以只检查文件格式，并在汇报里请用户在 VPS 上验证。

### Widget W

#### [ ] P3-W3.1 官方 Widget 可在 Linux 上运行（0.75 人天）
- **55e64c7e（免费图床）**：`main.py` 约 96–103 行用 macOS 的 `sips` 转换 HEIC。改为优先 `sips`（macOS），否则用 `heif-convert` 或 `ffmpeg`；都不可用时返回清晰的错误。更新它的 `test_main.py`。
- **783745bf（视频去水印）**：README 写明需要 `ffmpeg` / `ffprobe`（apt 安装）；启动时检测不到就给出清晰错误。
- **没有 `widget.json` 的三个目录**（`7cc3967a`、`a0d3311a`、`ddd803cf`，分别对应服务端 `official.ts` 里的 remove-bg-pro、remove-bg、upscale）：确认它们是否仍是线上的官方 Widget（看 `official.ts`）。如果是，按 `official.ts` 中的 manifest 补上 `widget.json`，让 `glance widget add` 能挂载；把 `a0d3311a/requirement.txt` 重命名为 `requirements.txt`。如果已经弃用，**问用户**是否删除。
- 所有 Widget 中，长时间运行的轮询循环（RunningHub 查询）调用 `glance_cli.sdk.report_progress`（C1.1 新增）上报进度；需要兼容没有安装 glance_cli 的环境（`try: from glance_cli.sdk import report_progress except ImportError: report_progress = lambda *a, **k: None`）。
- 删除各 Widget 目录里提交进仓库的 `.venv/`、`__pycache__/`、`.glance-test-output/`（先确认是否被 git 跟踪）。
- **验收**：各 Widget 的 `test_main.py` 通过（需要网络的测试必须已被 mock，否则标注为跳过）。

### 客户端 G

#### [ ] P3-G3.1 邀请码兑换与 Keychain（1.25 人天）🎨
- **依赖**：S3.1。**契约**：1.6。
- `AuthManager`：host 统一为 `https://api.glance.mcreator.ai`；新增 `redeemInvite(code:)`；token 存 Keychain（`kSecClassGenericPassword`，service `com.glance.app.device-token`）；首次读取时迁移 UserDefaults 里的旧会话并删除旧值。移除或隐藏调用不存在接口的入口（Google、email、native exchange）。
- 兑换输入界面：先查 `LoginPanel` 对应的 Figma frame，能复用现有的输入框和按钮样式就复用；**布局有变化先问用户**。
- 删除调试用的 `glance.widgetTaskToken` UserDefaults 覆盖，或限定为 `#if DEBUG`。
- 验收：parse 通过。

#### [ ] P3-G3.2 运行前检查 token、处理 401/429（0.5 人天）
- **依赖**：G3.1、S3.2。
- 运行云 Widget 前没有 token：打开兑换界面，不开始任务。轮询或创建任务时收到 401：清除 token，提示重新兑换。收到 429：提示「今日次数已用完，明天再试」（`scope=global` 时提示「服务今日繁忙」）。新增 en/zh 文案。

#### [ ] P3-G3.3 Manifest 验签与 Market 健壮性（0.5 人天）
- **依赖**：S3.5 已部署并完成重签。
- `WidgetModels.swift`：删除 `official == true` 时跳过签名校验的分支（约 323 行）；`WidgetCatalogClient.fetchAll` 改为逐条解码，坏条目跳过并记日志。`privacy.uploadsMedia` 改为可选（缺失时视为 true）。

#### [ ] P3-G3.4 预装现有的全部 Widget（0.5 人天）
- 首次启动时（`WidgetRegistry` 为空，且没有标记 `<suite>.widgetsPreinstalled`）：后台 `fetchAll` → 对每个 manifest 调 `fetch(widgetID:)` 验签 → 安装 → 设置标记。失败时静默，下次启动重试。

#### [ ] P3-G3.5 发布工程（1.5 人天，签名部分 👤）
- `get-task-allow` 只在 Debug 保留（`project.yml` 按配置区分 entitlements，或 Release 用单独的 entitlements 文件）。
- `Glance/build.sh`：签名身份参数化（`GLANCE_SIGN_IDENTITY`，默认是现在的自签名证书）；`--notarize` 选项：`xcrun notarytool submit … --keychain-profile "$GLANCE_NOTARY_PROFILE" --wait` → `xcrun stapler staple` → `hdiutil` 生成 DMG。
- Sparkle 2.x：`project.yml` 加 SPM 依赖；`Info.plist` 加 `SUFeedURL` 和 `SUPublicEDKey` 占位；主菜单增加「Check for Updates…」。
- 版本号改为 `1.0.0-beta.2` / build `5`；确认 `Resources/Info.plist` 未被使用后删除。
- 验收：`bash -n Glance/build.sh` 通过；`project.yml` 是合法的 YAML。

#### [ ] P3-G3.6 本地化、文档、隐私说明（0.5 人天）
- 补齐 en 缺失的约 69 个 key 和 zh 缺失的 key；重写 `README.md` 和 `PROJECT_STRUCTURE.md`（新定位、Widget、视频对比、普通 App + 菜单栏、Peek 为可选）；新增 `docs/privacy.md`（上传去向 R2 / freeimage.host、ipapi.co、日志脱敏、数据保留：上传 24 小时、结果 7 天）。

### 人工 H

- [ ] **H3.0** 确认 `api.glance.mcreator.ai` 已在 Cloudflare 绑定为 `glance-service` 的 Custom Domain（或说明实际的绑定方式），把结论告诉 AI 再执行 S3.7。
- [ ] **H3.1** 部署服务端：`wrangler secret put` 新增或确认的密钥；`wrangler d1 migrations apply glance-service-db --remote`（0008–0011）；`wrangler deploy`；执行 `POST /api/admin/v2/manifests/resign`；轮换 `ADMIN_PATH`；Google Console 登记新的 OAuth 回调地址；生产环境删除 `DEVELOPER_TEST_TOKEN`（Worker 改用真实登录后）。
- [ ] **H3.2** VPS：按 `glance-cli/deploy/README.md` 部署官方 Worker，为每个 Widget 执行 `bind --env`。
- [ ] **H3.3** Apple Developer（**个人账号**，Apple ID + $99，一般 1–2 天；D9）、Developer ID 证书、`notarytool store-credentials`、Sparkle EdDSA 密钥、appcast 托管地址。
- [ ] **H3.4** 构建并公证 `1.0.0-beta.2`，在一台干净的 Mac 上验证 Gatekeeper 直接放行。
- [ ] **H3.5** 在后台生成邀请码，建反馈群，发给熟人。

---

## P4 主路径视觉打磨（约 10 人天）🎨 全部依赖 Figma
- 前置：用户确认作为基准的 Figma frame（候选：`Dark Refresh v3 / Image Inspect / Clean Editable`、`Video Inspect v4 / …`）。没有确认前不要开始。
- P4-G4.1 Image Inspect 按 Figma 落地（6 人天）；P4-G4.2 Video Inspect 按 Figma 落地（4 人天）。先 `get_metadata` 获取节点坐标，逐区域实现（遵守规则 9、10），每个区域完成后列出与 Figma 的差异，请用户确认。

---

## 附录 A：工期汇总（人天）
| 阶段 | G | S | C | W | 合计 |
|---|---|---|---|---|---|
| P0 | 0（人工） | 0 | 0.1 | 0 | 0.1 |
| P1 | 7.5 | 2.5 | 1.25 | 0 | 11.25 |
| P2 | 3.5（不含阻塞的 G2.7） | 0 | 0 | 0 | 3.5 |
| P3 | 4.75 | 6.25 | 2.75 | 0.75 | 14.5 |
| P4 | 10 | 0 | 0 | 0 | 10 |
| **合计** | 25.75 | 8.75 | 4.1 | 0.75 | **约 39.4**（另加 G2.7 约 3 天、缓冲 20%，约 51 人天） |

## 附录 B：依赖图
```
P1:  S1.1 → S1.2 → S1.3        S1.1 → S1.4
     S1.2 → C1.1 (S1.3 → C1.1 的进度部分)     C1.2 独立
     G1.1 → G1.3, G1.4, G1.5, G1.7, G1.11      G1.1 + G1.2 → G1.6 → G1.9 → G1.10
     S1.2 + S1.3 + G1.11 → G1.12 → G1.13
P2:  G2.1 → G2.2, G2.3          G2.4 → G2.5
P3:  S3.1 → S3.2 → G3.2         S3.1 → G3.1 → G3.2
     S1.2 → S3.3                S3.5 →(部署+重签)→ G3.3
     H3.0 → S3.7 → C3.3(默认地址)    C1.1 → C3.2, C3.3, W3.1(进度)
     S3.x → H3.1 → H3.2 → H3.4 → H3.5
```

## 附录 C：修订记录
- 2026-10-12 v1：仅包含 Glance 客户端任务。
- 2026-10-12 v2：扩展为 G/S/C/W 全栈清单，新增第 1 节接口契约。新发现：
  - 取消没有闭环：服务端心跳对已取消任务仍返回 200，Worker 也忽略心跳响应，子进程会继续运行直到 25 分钟超时。
  - 服务端不返回 `pollAfterMs` 和进度。
  - 服务端没有测试。
  - CLI 默认地址是 workers.dev，客户端用 mcreator 域名，需要统一。
  - Freeimage key 实际上没有通过公开 config 下发（客户端缺 key 时会安全回退到 R2），改为在服务端禁止把 key 放进公开 config。
  - 视频右键已有 Widgets 菜单。
  - 「运行前检查登录」移到 P3，因为现有的登录接口在服务端不存在。

## 附录 D：实施记录（2026-10-12，分支 `feat/ai-preview-mvp`）

**已完成并验证**
- S：`npm run typecheck` 通过，`npm test` 8 个测试通过。新增迁移 `0008_task_progress.sql`（**上线前必须先执行迁移再部署代码**，代码会读写新列）。
- C：33 个 unittest 通过（原 28 + 新增 5）。
- G：所有 Swift 文件 `swiftc -parse` 通过，**未编译、未做类型检查，需要用户构建确认**。构建时 `build.sh` 会自动运行 `xcodegen generate` 收录新文件（`Sources/Inspect/`、`Sources/Video/`、`AppMenu.swift`、`ArrayExtensions.swift`）。拆分前后代码逐行比对一致（仅少了合并掉的重复 `Array[safe:]` 扩展，并把跨文件需要的 `private`/`fileprivate` 改为 internal）。

**与任务描述不同的地方**
1. S1.2：409 响应保留现有的 `success:false` 外层；另外给「持 `X-Task-Claim` 的开发者 Worker」加了一条路径（`inactiveTaskStatusForDeveloper`），因为取消会清空 claim hash，否则 pull-batch Worker 的心跳只会得到 404 而不是 409。契约 1.2 的 `error` 保持为字符串错误码。
2. S1.1：`@cloudflare/vitest-pool-workers@0.23.0` 已改名为 `@cloudflare/vitest-plugin`（会打印警告，功能正常）；其 workerd 只支持到 2026-08-22 的兼容日期，测试配置里用 `2026-08-01`，与线上的 `2026-09-15` 略有差异。
3. C1.1：另外在上传前和提交 `/result` 前也检查取消标志；`on_log=None` 路径现在也会合并 stderr 到 stdout。取消延迟 ≈ 心跳间隔 30 秒 + 0.5 秒轮询。
4. G1.7：压缩路径用上通用插入函数后，顺带修正了一个原有问题（压缩插入后没有平移 `failedIndices`）。
5. G1.12：**没有**做 Task Center 里的取消按钮（需要 Figma 参考）；**没有**中断正在进行的上传请求，只在各阶段之间检查取消（上传完成后才会停）。
6. G2.2：不需要额外的 `hasLaunchedBefore` 逻辑——原有的「空闲时显示 Home」在去掉权限引导窗口后，首次启动自然会显示 Home。`Preferences.enabled` 改名为 `peekEnabled`（存储 key 不变），默认值改为 false，并有一次性迁移：已经授权过两项权限、且没有显式设置过的老用户保持开启。

**用户已决定（2026-10-12）**
- G1.4：整块删除 QUICK ACTIONS（标题、两个按钮、`onRunDefaultWidget`/`onUpscale` 回调，以及窗口里的 `defaultWidgetCommand`、`runDefaultWidgetTapped`、`runUpscaleWidget`）。**面板高度**：已从 684pt 缩短到 396pt（最后一行分隔线结束在 372，加 24pt 底部留白，与顶部 23pt 对称）。这个数值由布局常量推出，**没有对照 Figma frame**（没有 Figma 访问权限）；需要在 Figma 里把信息面板同步缩短，或告诉我 Figma 里的实际高度。
- G1.13：保持现状，不做。
- G2.7：取消。视频不做滑杆对比。

**P1.5 实施记录（2026-10-12）**
- S：`npm test` 14 个测试通过（新增 6 个），新增迁移 `0009_queue_index.sql`（上线前先执行）。`estimatedWaitSeconds` 的分母采用「最近 10 分钟内同时活跃的峰值数」，这是对「同时 running」最贴近字面的解释；没有历史数据时省略该字段。`fail()` 增加可选的额外响应头参数，用于 `Retry-After`。
- C：38 个 unittest 通过（新增 5 个）。两个环境变量在 Worker 启动时读取；`GLANCE_WORKER_PER_WIDGET_CONCURRENT` 为负数时按 0（不限）处理并告警。`eligible()` 的签名从 `busy: set` 改为 `running: Mapping[str,int]`。
- G：语法检查通过，未编译。排队文案挂在 `WidgetTaskRecord.queueText` 上，列表行和详情面板共用；30 分钟超时放弃前会先发 DELETE 取消；429 映射为「服务繁忙」。
- **上线提醒**：RunningHub 企业版开通后，VPS 上把 `GLANCE_WORKER_MAX_CONCURRENT` 设为 ≤100、`GLANCE_WORKER_PER_WIDGET_CONCURRENT=0`，否则企业版并发用不上。

**停在决策点**：P3（邀请码、配额、过期清理、SSRF 加固、VPS 部署、发布工程）未开始，按本文件的约定等 2 周验证结果（≥30 人报名）。
