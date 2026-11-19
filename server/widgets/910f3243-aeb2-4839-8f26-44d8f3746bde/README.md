# 局部编辑 / Edit Area

- Widget ID: `910f3243-aeb2-4839-8f26-44d8f3746bde`，版本 `0.1.0`，每次 **1 积分**（`widget.json` 的 `creditCost`，沿用 Glance 现有余额检查、费用确认和失败退款流程）。
- 三个输入：原图（`task.input.path`，PNG/JPEG/WebP）、蒙版（`parameters.mask`，客户端上传后的 https PNG 链接，必填）、文字描述（`parameters.prompt`，1–2000 字，中英文均可，必填）。`parameterSchema` 里声明了 `mask`，客户端就会显示「Upload mask / Draw mask」入口并要求提交前提供蒙版。
- 蒙版约定：Glance 的涂抹编辑器导出透明底 PNG，**不透明的白色 = 要修改的区域**。纯黑白蒙版（白色 = 修改）也能识别；黑色或透明区域不会被修改。蒙版会拉伸到原图尺寸（编辑器的笔迹按整张图归一化，所以按原始像素导出的蒙版也能对齐）。
- 输出一张 PNG，保持原图比例，长边限制在 1024–2048。

## 处理流程

1. 把原图和黑白蒙版一起发给 gulu 的 `gpt-image-2.5-flare`（`POST https://guluapi.com/v1/images/edits`，`image[]` 依次为原图、蒙版），提示词要求只改白色区域。横图先旋转 90° 再发送，结果转回来（模型会把横图重新构图成竖图）。
2. GPT 会重画整张图，所以只保留结果中蒙版内的部分：蒙版以外**贴回原图像素**，接缝处做轻微羽化。实测蒙版外的平均像素差约 0.1。
3. 结果比例与原图不符，或蒙版外的画面被挪动/重画（对齐检查），视为失败并重试，最多 3 次。
4. 内容审核拒绝不重试，直接提示用户换描述或换图；**没有 RunningHub 兜底**（RunningHub 的移除物体工作流不接收蒙版，无法保证只改涂抹区域）。失败按规则全额退积分。

Key 读取顺序：环境变量 `GULU_GPTIMAGE_KEY`，否则读 `~/Desktop/work/gpu_task/config/config.env`（可用 `GULU_CONFIG_ENV` 指定路径）。蒙版 URL 只接受 https，且只在 `main()` 中下载；本地命令行用法见下，不会读取任务里的本地路径。

## 验证

```sh
PYTHONPATH=server/glance-cli/src .venv/bin/glance widget validate --manifest server/widgets/910f3243-aeb2-4839-8f26-44d8f3746bde/widget.json
.venv/bin/python -m unittest discover -s server/widgets/910f3243-aeb2-4839-8f26-44d8f3746bde -p 'test_*.py'
# 本地真实调用（会请求 gulu 并消耗额度）：
.venv/bin/python server/widgets/910f3243-aeb2-4839-8f26-44d8f3746bde/main.py photo.png mask.png --prompt "移除这个人"
```

测试全部离线，不访问网络。发布命令 `glance widget publish` 只是提交市场审核并登记本机 Worker，管理员在 Admin Console 批准后才公开上架。

## 发布记录（2026-11-13）

已通过 `glance widget publish` 提交 Widget 市场审核，版本 ID `version_81cc1f5a-a2d6-440f-8340-f3397ed5d33e`，服务器状态 `manual_review`，**尚未公开上架**，需管理员在 Admin Console 测试并 promote。本机 Worker 已登记此目录（使用仓库 `.venv/bin/python`）并开始请求任务。真实验证：竖图 941×1672 + 椭圆蒙版 + 中文描述“移除这个黑色手提包，露出后面的背景”，26 秒返回同尺寸 PNG，手提包被移除，蒙版以外平均像素差 0.14。本次未部署服务端、未构建客户端、未运行 Glance UI。
