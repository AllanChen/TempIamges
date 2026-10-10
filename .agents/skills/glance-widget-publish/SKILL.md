---
name: glance-widget-publish
description: 根据用户提供的代码或处理流程，在本项目的 widgets 目录创建、验证并按要求发布 Glance Widget。适用于本机处理、外部 API 或混合流程。
---

# 创建与发布 Glance Widget

在项目根目录工作并遵守 `CLAUDE.md`。先查看最相近的 `widgets/<id>/main.py` 和 `widget.json`，以及 `glance-cli/src/glance_cli/runtime.py`、`worker.py`、`cli.py` 的当前约定。`GlanceService/site/widgets` 是市场页面；Widget 执行代码的例子在项目根目录的 `widgets/`。

## 用户只问怎么使用时

先解释：用户可以直接粘贴代码、上传 `.py` 文件，或提供项目中的文件路径。用户不必先把代码改写成 Glance 格式。询问所需的输入、输出和处理步骤；凭证只需提供环境变量名，不要索取密钥明文。给出简短例子：

```text
用 $glance-widget-publish 创建并发布一个「换装」Widget。
代码：/项目路径/example.py（也可以上传文件或直接粘贴代码）
输入：两张图片，第一张是人物，第二张是服装
输出：一张图片
凭证环境变量：MY_API_KEY
```

如果只需要本地文件，提示写明“先创建，不发布”。本机处理或多个 API 组合时，用户只需补充各步骤的顺序。能从代码确定的信息不要反复追问。仅咨询用法时，不创建文件或提交发布。

## 创建 Widget

1. 从用户给出的代码或描述确定名称、输入类型与数量、参数、输出类型和处理顺序。区分示例值与真实任务输入。只有关键映射无法推断时才询问用户。不要默认使用 RunningHub、特定 API、节点格式或网络上传。
2. 在 `widgets/` 下创建 UUID 目录，包含 `main.py` 和 `widget.json`；可使用项目的 `glance widget init --directory widgets` 创建骨架。更新已有 Widget 时沿用 ID，并按发布要求更新版本。不要覆盖无关文件。
3. 将实现整理为 `main(task: dict) -> dict`。从 Glance 任务读取实际输入：单个媒体文件可读 `task["input"]["path"]`；多个图片或视频分别读 `imagePaths` 或 `videoPaths`；可编辑参数从 `task["parameters"]` 读取。外部 API 的字段、节点和顺序只按该服务的实际协议映射，不能留下示例文件名。
4. 让 Manifest 与代码一致：声明实际输入类型、媒体数量、可编辑参数及输出类型。只有代码支持 prompt 时才声明 prompt。需要外部 API 时按其要求上传、提交和查询；本机处理不增加多余的外部步骤。凭证从环境变量读取，不写入代码、Manifest 或日志；需要额外 Python 依赖时使用适合该 Widget 的解释器并说明安装要求。

### RunningHub 域名与凭证

仅当用户提供的代码或流程使用 RunningHub 时，根据实际请求的域名选择 Worker 环境变量：`runninghub.ai`（包括 `www.runninghub.ai`）使用 `RUNNINGHUB_API_KEY_AI`；`runninghub.cn`（包括 `www.runninghub.cn`）使用 `RUNNINGHUB_API_KEY`。上传输入、提交任务和查询结果必须使用对应平台的域名与密钥；不要仅因参考的旧 Widget 使用 `.cn` 就把用户的 `.ai` 地址或密钥改成 `.cn`。若同一流程确实调用两个域名，分别读取并使用各自的密钥。缺少密钥时明确指出缺少哪个环境变量，不打印密钥值。

例：代码中的提交地址是 `https://www.runninghub.ai/openapi/v2/run/ai-app/...`，生成的 `main.py` 应读取 `os.environ.get("RUNNINGHUB_API_KEY_AI", "")`；地址是 `https://www.runninghub.cn/openapi/v2/run/ai-app/...`，则读取 `os.environ.get("RUNNINGHUB_API_KEY", "")`。

## 失败与重试

按实际流程设置有上限的重试；用户未指定时，普通、可恢复的生成失败默认总共尝试 3 次（含首次）。所有尝试共用总超时，并保持在 Glance Widget 运行时限内。

- 外部服务明确报告色情、Porn、政治、涉政或其他内容审核拒绝时立即终止，不重试。依据该服务的结构化错误和消息判断；若错误原因不明确，不要把普通失败猜成审核拒绝。
- 无效输入、缺少凭证及明确的权限错误直接报错。普通可恢复失败按上限重试；本机步骤也应考虑重试是否会重复副作用。
- 查询或下载暂时失败时，优先重试当前步骤。提交状态不明时，先避免盲目重复提交可能收费的任务。记录安全、可读的最终失败原因，不泄露凭证。

## 返回结果到 Glance

按 `glance-cli` 支持的 `outputs` 格式返回结果，并使实际结果与 Manifest 的输出声明一致。图片、视频和音频优先保存到 `GLANCE_TASK_OUTPUT_DIR`，返回本地文件的绝对 `path`；文字返回 `text`。检查媒体文件非空、格式与大小符合运行时限制。图片例子：

`{"outputs": [{"type": "image", "path": "/absolute/path/to/result.png"}]}`

Glance Worker 会把本地媒体文件上传到 Glance 服务器并回报任务结果。若外部 API 只提供结果 URL，而需求是将结果上传到 Glance，应先下载并返回本地路径；不要在 Widget 中重复调用 Glance 上传接口。

## 验证与发布

1. 运行 `glance widget validate --manifest widgets/<id>/widget.json`，并做适合该 Widget 的非 UI 检查。对外部 API 流程，优先用模拟响应验证输入映射、重试、审核拒绝和输出。不要为了验证擅自发起付费任务；遵守项目不运行 Glance UI 测试的规则。
2. 只有本次请求包含发布时，运行 `glance widget publish --manifest widgets/<id>/widget.json --code widgets/<id>`。该命令提交审核，不代表已在市场公开上架；不要代替管理员审批或部署 GlanceService。
3. 汇报 Widget ID、目录、版本、输入与输出、验证结果及发布状态。发布失败时保留本地成果并说明错误，不声称已发布。
