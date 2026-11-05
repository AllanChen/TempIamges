# 移除物体 / Remove Objects

- Widget ID: `0b164640-9998-49c7-aa93-5ed5cb957c40`，版本 `0.1.0`。
- 每次 **30 积分**，沿用 Glance 现有余额检查、费用确认和失败退款流程。
- 输入一张静态 PNG/JPEG/WebP 图片及必填 `parameters.prompt`（1–2000 字，使用英文）。例如 “Remove the red ball on the right”。中英文指界面文案；当前工作流中文描述未通过真实效果测试，代码在上传前拒绝中文描述并提示改用英文。
- 输出一张保存到 `GLANCE_TASK_OUTPUT_DIR` 的图片，Worker 上传结果后供客户端展示。
- 中文基础文案、英文 `localizations.en`；复用客户端已有图片＋文字输入面板。

使用与图片去水印相同的 RunningHub `.cn` App `2117102824717897730`。上传真实输入文件后，节点 `191.image` 接收文件名，节点 `6.text` 接收用户描述及仅移除指定物体、自然补全背景、保留其余内容的指令。生成结果仍需用户确认，不能保证所有图片都能完美保留细节。

依赖 `requirements.txt` 中的 Pillow；凭据读取 `RUNNINGHUB_API_KEY`，不得提交密钥。图片和描述会发送到 Glance 与 RunningHub。

同一任务共用 900 秒期限；明确生成失败最多尝试 3 次。内容审核拒绝、无效输入和明确权限错误立即停止。提交超时不盲目重提；查询与下载网络失败只重试当前步骤。无法解码、为空、超大或非图片的结果不会作为成功返回。

在仓库根目录验证：

```sh
PYTHONPATH=server/glance-cli/src .venv/bin/glance widget validate --manifest server/widgets/0b164640-9998-49c7-aa93-5ed5cb957c40/widget.json
.venv/bin/python -m unittest discover -s server/widgets/0b164640-9998-49c7-aa93-5ed5cb957c40 -p 'test_*.py'
```

发布命令 `glance widget publish` 提交市场审核并登记本机 Worker，只有管理员批准后才公开上架。不要将「已提交审核」描述为「已公开上架」。

## 验证记录（2026-11-02）

- Manifest 校验、13 项非 UI 模拟测试通过：图片/文字映射、必填与长度、中文输入提前拦截、单图约束、无效输入/结果、网络查询重试、提交超时不重提、明确失败最多三次、审核拒绝、共享超时和密钥脱敏。
- 真实测试中中文描述两次未移除目标；用户确认只要求界面中英文，因此正式版要求英文描述，不增加翻译服务。
- 最终英文实现真实任务 `2117173079640858625`：170 秒返回有效的 768×768 PNG，Glance 输出校验通过；红球与阴影被移除，杯子仍保留，但模型将杯子位置稍作调整。不能承诺未指定区域像素或构图完全不变。
- 本机测试图片与结果位于 `.glance-test-output/`（不发布测试媒体）；未运行 Glance UI 测试。

## 发布记录（2026-11-02）

已通过 CLI 提交 Widget 市场审核，submission ID 为 `version_15315bc6-274e-4e62-9d0e-74e0e3560cff`，服务器状态 `manual_review`，尚未公开上架。回读确认价格为 30 积分，中英文名称与必填 prompt 均正确；本机 Worker 已注册此目录，使用仓库 `.venv/bin/python`。本次未代替管理员审批，也未部署服务端或推送无关仓库变更。
