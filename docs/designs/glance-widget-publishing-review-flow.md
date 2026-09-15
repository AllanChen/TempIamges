# Glance Widget 发布、审核与执行流程

状态：方案评审中  
更新时间：2026-09-15

本文定义第三方开发者如何提交 Widget、Glance 后台审核者如何审核，以及审核通过后的灰度发布和 GPU 执行流程。

## 1. 角色与边界

| 角色 | 能做什么 | 不能做什么 |
| --- | --- | --- |
| Widget 开发者 | 提交 Manifest、任务配置、测试样例；查看自己的审核状态和聚合指标 | 不能上传本地可执行代码；不能查看生产用户媒体 |
| Glance 审核者 | 自动检查结果复核、运行测试任务、通过/拒绝/要求修改、灰度和暂停版本 | 不直接修改开发者的 Widget 代码 |
| Glance 用户 | 浏览、安装和调用已发布 Widget | 不能调用未发布或已暂停版本 |
| GPU Worker | 执行已审核的任务类型并写入结果 | 不访问用户本机；不执行未经审核的代码 |

首期采用“官方 Widget + Glance 自有 GPU”。第三方 Widget 可以提交，但必须审核并灰度后才能进入公开 Market。

## 2. 开发者提交入口

开发者登录 Glance 后台：

```text
https://mcreator.ai
```

提交入口规划为：

```text
https://mcreator.ai/glance/widgets/submit
```

提交一个新版本时，后台创建一条 `WidgetSubmission` 记录。版本号相同的 Widget 不允许重复提交。

提交 API：

```http
POST /api/glance/v2/widget-submissions
Authorization: Bearer <developer-session-token>
Content-Type: application/json
```

## 3. 开发者必须提交的资料

### 3.1 Widget 基本信息

- `id`：3–128 个字符，只允许字母、数字、`.`、`_`、`-`
- `version`：语义化版本，不能覆盖已有版本
- `name`
- `summary`
- `author`
- `iconURL`
- `minimumGlanceVersion`

### 3.2 Command

每个 Widget 至少包含一个 Command。每个 Command 包含：

- `id`
- `name`
- `description`
- `inputTypes`：`image` 或 `video`
- `inputMimeTypes`
- `outputs`：`image`、`video`、`text` 或 `metadata`
- `taskType`
- `requiresUpload`
- `parameterSchema`

如果只有一个 Command，客户端只显示一级 Command，不再生成多余的三级菜单。

### 3.3 执行和隐私资料

- 执行模式必须为 `cloud`
- 最大输入文件大小
- 最大输入分辨率
- 预计执行时间
- GPU 显存需求
- 并发需求
- 是否上传用户媒体
- 源文件保留时间
- 是否用于训练
- 完整隐私声明

### 3.4 测试资料

- 测试图片或视频
- 预期输出
- 失败样例
- 模型许可证或版权证明
- 已知限制和不支持的输入

开发者提交的是声明式 Manifest、任务配置和样例，不提交 Swift、Node.js、动态库或任意本地可执行文件。

## 4. 自动检查

提交后状态变为：

```text
submitted → automated_checking
```

后台自动检查：

- JSON Schema 和字段类型
- Widget ID、Command ID 和版本号
- Command 是否重复
- 输入输出类型是否完整
- 参数 Schema、默认值和范围
- Ed25519 签名
- `execution.mode == cloud`
- 文件大小、MIME 类型和超时限制
- 是否包含任意代码执行能力
- 是否允许向任意第三方 URL 上传
- GPU 资源声明是否合理
- 隐私声明是否完整

检查失败时状态变为 `rejected`，开发者看到机器检查问题，可以修改后提交新版本。

检查通过后状态变为：

```text
manual_review
```

## 5. 审核者入口

审核者使用现有后台管理员账号登录：

```text
https://mcreator.ai/admin/{ADMIN_SLUG}
```

Widget 审核页面规划为：

```text
https://mcreator.ai/admin/{ADMIN_SLUG}/glance/widgets
```

审核列表显示：

- Widget 名称、ID、版本
- 开发者
- 提交时间
- 当前状态
- 自动检查结果
- 测试任务状态
- GPU 平均耗时和失败率

审核详情 API：

```http
GET  /api/admin/{ADMIN_SLUG}/glance/widget-submissions
GET  /api/admin/{ADMIN_SLUG}/glance/widget-submissions/{submissionID}
```

## 6. 审核操作

### 6.1 查看 Manifest

审核者查看完整的 Widget 信息、Command、参数 Schema、输入输出和隐私声明。

### 6.2 运行测试任务

审核者选择测试样例并点击 `Run Test`。后台使用受控 GPU 执行，不使用开发者的生产接口：

```http
POST /api/admin/{ADMIN_SLUG}/glance/widget-submissions/{submissionID}/test
```

测试页面显示：

- 排队中
- GPU 执行中
- 进度
- 实际输出
- 执行耗时
- 显存占用
- 错误信息

### 6.3 通过审核

审核者确认效果、隐私和资源消耗后提交：

```http
POST /api/admin/{ADMIN_SLUG}/glance/widget-submissions/{submissionID}/review
```

请求内容包括：

```json
{
  "decision": "approve",
  "note": "测试通过，允许灰度发布",
  "testPassed": true,
  "providerTemplateName": "platform-controlled-template-id"
}
```

通过后状态变为 `testing`，并创建一个待灰度的 Release。

### 6.4 要求修改

```json
{
  "decision": "request_changes",
  "note": "输出结果与描述不一致；请补充 HEIC 输入限制",
  "testPassed": false
}
```

状态变为 `rejected`。开发者根据审核意见提交新版本，旧版本保留完整审核记录。

### 6.5 拒绝

用于侵权、违规、不安全、无法稳定执行或 GPU 成本不可接受的 Widget。拒绝必须填写原因。

### 6.6 暂停版本

已发布 Widget 出现异常时，审核者可以暂停 Release：

```http
POST /api/admin/{ADMIN_SLUG}/glance/widget-releases/{releaseID}/suspend
```

暂停后：

- Market 不再展示新的安装入口
- Glance 不再创建新任务
- 历史任务仍可查询
- 审核者可以回滚到上一版本

## 7. 灰度发布

审核通过后状态为：

```text
testing → gray_release
```

审核者设置：

- 灰度比例
- 测试用户或账号范围
- 最大并发数
- 每日任务额度
- 单文件大小
- 单任务超时时间

建议发布节奏：

```text
5% → 25% → 50% → 100%
```

提升灰度：

```http
POST /api/admin/{ADMIN_SLUG}/glance/widget-releases/{releaseID}/promote
```

每次提升前检查：

- 任务成功率
- P95 执行时间
- GPU 显存和利用率
- 超时率
- 结果下载失败率
- 用户投诉和异常日志

达到 100% 后状态变为 `published`，Widget 才进入公开 Market：

```text
https://glance.mcreator.ai/widgets
```

## 8. 用户任务执行

用户安装已发布 Widget 后，Glance 客户端执行：

```text
选择图片/视频
    ↓
选择 Widget Command
    ↓
上传到 Glance 临时存储
    ↓
创建 Widget Job
    ↓
GPU Worker 执行
    ↓
Glance 轮询状态
    ↓
下载并展示结果
```

客户端接口：

```http
POST /api/glance/v2/uploads
POST /api/glance/v2/tasks
GET  /api/glance/v2/tasks/{taskID}
```

平台内部执行：

```text
Glance API → Job Queue → GPU Worker → Provider Adapter → Result Storage
```

开发者只能看到自己 Widget 的测试任务和聚合指标，不能看到生产用户原图、文件名、本地路径、身份或完整参数。

## 9. GlanceService 与开发者 Worker 的交互

当前部署采用分部署算力架构：`api.glance.mcreator.ai` 是 Glance 的控制面、审核面和任务队列；开发者自己的 Python Worker 是数据面，只通过 Widget ID 和提交时生成的 Worker Token 拉取任务。Glance 不再依赖 `api.himarts.com`，也不修改 mcreator 项目。

```text
Glance 客户端 / 审核后台
          ↓ HTTPS
api.glance.mcreator.ai (GlanceService)
          ↓ D1 queue + R2 assets
开发者 Python Worker
          ↓ POST result
api.glance.mcreator.ai
```

### 9.1 提交和审核

开发者或 Glance 后台向 `POST /api/v2/widget-submissions` 提交 Manifest。服务端保存版本、生成只显示一次的 `workerToken`，并将状态设为 `manual_review`。审核者通过后台调用：

```text
POST /api/admin/v2/widget-submissions/{id}/test
    ↓ 创建 review_test 任务
Worker GET /api/v2/widget-tasks/pull?widget_id=...
    ↓ 执行成功并 POST /api/v2/widget-tasks/{taskId}/result
审核后台确认输出
    ↓
POST .../{id}/approve   → gray_release
```

审核通过后再将版本发布为 `published`。测试成功只代表 Worker 的技术执行链路通过，人工审核仍可拒绝或暂停版本。

### 9.2 生产任务

客户端只调用 GlanceService 创建任务和查询状态：

```text
POST /api/v2/widget-jobs
    ↓ queued
开发者 Worker 按 widget_id 长轮询 pull
    ↓ claimed/running
Worker 执行并提交 result
    ↓ succeeded/failed
GET /api/v2/widget-jobs/{taskId}
```

输入媒体上传到 Glance R2 后，上传接口返回带 HMAC 时效签名的 URL，Worker 可以在任务有效期内读取，不需要用户 Bearer Token。任务过期会自动回收为 `queued`，Worker 可用 heartbeat 续租。

### 9.3 Worker 最小实现

开发者只需要保存创建提交时返回的 `widgetId` 和 `workerToken`，循环调用：

```http
GET /api/v2/widget-tasks/pull?widget_id={widgetId}&wait=25
Authorization: Bearer {workerToken}
```

完成后提交：

```http
POST /api/v2/widget-tasks/{taskId}/result
Authorization: Bearer {workerToken}
Content-Type: application/json

{"status":"succeeded","artifacts":[{"url":"https://..."}]}
```

Worker Token 只存服务端环境变量；Manifest、客户端和公开 Widget 市场都不能包含该 Token。

## 10. 状态机

```text
draft
  ↓
submitted
  ↓
automated_checking
  ├── rejected → developer submits a new version
  └── manual_review
        ├── rejected
        └── testing
              ↓
          gray_release
              ├── suspended
              └── published
                    └── deprecated
```

每次状态变化都记录：操作者、时间、备注、版本和自动检查结果。

## 11. 当前实现状态

后端当前已经实现：

- 官方 Widget 目录
- Widget Manifest 签名
- 媒体上传
- PPPron 任务提交
- 任务状态轮询
- 任务结果代理

当前还需要实现：

- 开发者提交页面
- `widget-submissions` 数据表和 API
- 自动检查服务
- 审核者 Widget 审核页面
- 测试任务接口
- Release 和灰度发布接口
- 第三方 Widget 与受控 GPU Worker 的任务映射
- 审核操作日志和回滚机制

在这些接口和审核流程上线前，公开 Market 仍只允许 Glance 官方维护的 Widget。

## 相关文档

- [Glance 2.0 Widget Market 与媒体任务平台](./glance-2.0-widget-market.md)
