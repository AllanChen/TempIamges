# 视频按时长计费：实现与上线准备

2026-10-27：服务端、生产迁移 0019 和视频去水印 Widget 0.3.0 已部署；本机 CLI Worker 已重启加载新核验代码。macOS 尚未构建或进行 UI 测试，费用确认弹窗需要新版客户端。

## 行为

所有客户端 Widget 提交先通过服务端报价检查余额：不足直接充值，足够显示消费确认。充值成功只刷新报价，不自动提交。仅用户明确确认后才上传、创建任务和扣点。已存在的固定单次计费语义保持不变。

视频去水印为 `ceil(durationSeconds / 10) * 100` 点；使用视频流精确时长，视频流没有时长时回退容器时长。内部仍按最多 8 秒（长视频按 7.8 秒目标）切片，最多 24 段、输入 50 MiB，约 187.2 秒上限。30 分钟不支持。前置时长读取失败即阻止提交；网络视频先下载为本地输入以便核验，不提前上传或调用供应商。

报价通过后：不足点数打开现有充值窗口；足够则展示时长、份数、单价、总额、当前和扣后余额，以及失败整单退点、重试不额外收费。取消后异步返回不得恢复提交。确认后的文件改动、余额变化、价格变化、过期报价必须重新确认。任务详情保存本次计费快照；已创建的历史任务不补扣。

## 数据与接口

- Manifest 增加可选 `billing: {mode: "duration", unitSeconds: 10}`；`creditCost` 是每单位价格。未配置仍为固定单次计费。视频去水印清单版本 `0.3.0`、`creditCost: 100`。
- `POST /api/v2/task-quotes`：认证用户传 `widgetID`、`commandID`；按时长收费还需要 `evidence: {durationSeconds, byteSize, sha256}`。返回 `quoteID, mode, unitSeconds, unitPrice, units, totalCredits, expiresAt, evidence, balance, shortfall, limits`。
- 报价时不扣点、不创建任务。报价 10 分钟有效，绑定用户、命令、Widget 版本和文件证据；SHA-256 是内容指纹，不上传文件路径。
- `POST /api/v2/tasks`：新客户端携带 `quoteID`、`expectedCreditCost` 和 `Idempotency-Key`。服务端从不可变报价中计算总额并写入现有 `credit_cost`，由原有数据库触发器原子检查余额、扣点。报价有唯一任务约束。客户端伪造的 `_billingQuote` 被覆盖／删除。
- 迁移 `0019_task_quotes.sql` 新增 `task_quotes` 和任务 `quote_id`、`billing_verified_at`。任务详情 API 返回 `quote` 快照。报价不是资金预留，确认后以提交时余额为准。
- 按时长任务必须有报价；缺少报价的旧客户端收到 `quote_required`。视频去水印线上旧清单尚未启用按时长配置时返回 `billing_not_ready`，避免沿用测试价格或旧固定费率。固定价旧客户端保持兼容。
- Worker 批量领取请求声明 `durationBilling: 1`；旧 Worker 和旧 token 领取接口不分配按时长任务。
- 新 CLI runtime 下载输入后、启动 Widget 进程前使用 ffprobe 检查实际视频时长、计算 SHA-256，并带当前 claim token 调用 `POST /api/v2/widget-tasks/:id/verify-input`。服务器校验字节数、哈希、实际限制、计费份数；探测时长差允许最多 0.1 秒，但不能跨计费单位。
- 核验不符，服务端将任务标为失败并触发整单退款；没有核验成功的任务不能报告成功。核验服务不可用时不启动供应商处理。失败、过期、取消和交付失败复用现有幂等退款与恢复机制。

## 上线顺序与完成状态

1. 暂停新的视频去水印提交并等待旧任务结束，保留原记录与退款数据。
2. 应用迁移 0019，再发布支持报价和核验的服务端。
3. 升级实际运行的 CLI Worker，确认其有 ffprobe，并以 `durationBilling: 1` 领取任务。
4. 审核并发布视频去水印 0.3.0 清单，确认 Admin 显示 100 点／10 秒。不能只修改客户端的显示价格。
5. **待用户完成：**构建并运行新版 macOS 客户端，手动验证充值、费用确认、取消及任务结果交付。服务端已恢复 Widget 公开状态，旧客户端因没有报价而被拒绝提交视频任务。

回退时先停止新的按时长任务，保留新数据库表和退款路径，等待已确认任务结算完成。不要把按时长任务交给旧 Worker，或直接恢复按固定单次价格处理长视频。

## 非 UI 验证

在仓库根目录运行：

```sh
npm --prefix server/GlanceService run typecheck
npm --prefix server/GlanceService test
PYTHONPATH=server/glance-cli/src python3 -m unittest discover -s server/glance-cli/tests
python3 -m unittest discover -s server/widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8 -p test_main.py
python3 clients/macos/scripts/test-widget-billing-preflight.py
```

服务端测试覆盖 10 秒边界、长度／文件上限、少报／伪造输入、余额变化、过期／调价、重复和并发提交、Worker 能力兼容、核验前置及整单幂等退款。CLI 测试确认核验失败／断网不会启动 Widget 进程。客户端测试提取实际确认控制器，使用无界面替身检查充值与确认顺序、取消、账号变更和重复确认；不启动 Glance。

## 用户验收

- 点数不足：直接充值并展示差额，取消后没有任务或扣点。
- 点数足够：明确确认前无上传／任务／扣点；确认后金额与弹窗一致。
- 充值后：回到新的费用确认；不自动执行。
- 10 秒、11 秒、60 秒分别扣 100、200、600 点；30 分钟在提交前阻止。
- Worker／分段／合并／交付失败整单退款，任务中心展示已确认的退款状态；运行成功后能正常看到并使用结果。

## 2026-10-27 部署记录

- Cloudflare 服务：`glance-service`，版本 `894b0b8b-5269-4d55-bd44-33d5807a2b8a`。
- 生产 D1：`0019_task_quotes.sql` 已应用；迁移前已保存本机私有备份。
- 视频 Widget：`783745bf-501d-4cfd-b2b8-69d32a8d90a8`，版本 `0.3.0`，状态 `published`，100 点／10 秒。
- 发布时间（UTC）：`2026-10-27T14:55:30.767Z`。发布前没有活动视频任务；切换期间暂停提交，完成后恢复。
- 本机 Worker 已正常重启，保留原运行凭证和环境；注册表显示 0.3.0 已启用且状态 published，已观察到正常轮询，无最近错误。
- 上线检查：`/health` 正常；公开清单返回正确计费规则及签名；报价接口对未认证请求返回 401；生产迁移记录存在。没有提交收费测试任务。
- 保留原有线上支付环境及其他变量；本次不修改支付配置、不构建或启动 macOS 客户端、不发布 CLI 安装包。
