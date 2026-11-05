# Waffo 底层模型披露整改记录

状态：本地修改完成并通过构建检查，尚未部署。用户已确认图生图使用 Krea 2、换装使用 Qwen 2.1、扩图使用 FLUX.2；换装按官方图像模型名称规范为 Qwen-Image-2.1。图片转提示词当前服务版本仍待核对。

## 已完成的页面修改

- 新增 `/ai-models/` 与 `/en/ai-models/`，静态 HTML，不依赖登录或 JavaScript 加载模型说明。
- 从中英文全站页脚、Widget 页、定价页、服务条款和 AUP 链接到该页。
- 区分文生图、基于图片的生成/编辑、图片理解、图生视频和已有视频修复。
- 保留已有披露的型号，补充官方来源；将用户确认的三个模型逐项列出，并补充官方型号链接。
- 从当前公开列表移除本地存在但不在在线目录中的 Remove Background（rembg/U²-Net）条目。
- 不将应用名“洗图2-krea2”当作模型名称或版本证据。
- 不把 RunningHub（服务平台）当作模型，不将 MiniMax-Remover 论文项目等同于 MiniMax 商业视频生成服务。

## 事实来源与限制

2026-10-22 读取 https://api.glancepreview.com/api/v2/widgets?limit=50 ，共 9 个公开 Widget。所有生成/处理命令均要求输入图片或视频；当前没有文本单独生成图片、或图片生成视频的命令。该结论适用于此次读取的目录，不表示底层模型本身没有其他能力。

本地 main.py 证明调用的 RunningHub 应用编号，不能证明服务商内部实际模型版本。公开应用页通常只有名称和输入节点，并未暴露完整工作流。已有网站文字也不构成独立的运行版本验证。

| Widget | RunningHub 应用或工作流 | 状态 |
| --- | --- | --- |
| 图生图 | https://www.runninghub.cn/ai-detail/2108761461056163841 | 用户确认 Krea 2；未指定 RAW/Turbo 等子版本，不推断 |
| AI 换装 | https://www.runninghub.cn/ai-detail/2108493566690545665 | 用户确认 Qwen 2.1；官方图像模型名称 Qwen-Image-2.1 |
| 智能扩图 | https://www.runninghub.cn/ai-detail/2109591136061976577 | 用户确认 FLUX.2；未指定 [dev]/[pro]/[klein] 等变体，不推断 |
| 图片转提示词 | https://www.runninghub.cn/ai-detail/2084152800765890561 | 原网站披露 Gemini 3.5 Flash，当前服务版本需重新确认 |
| 高清放大 | https://www.runninghub.cn/ai-detail/2097856100338065410 | 原网站披露 Gemini 3.1 Flash Image；官方名称已核对，运行版本需以工作流为据 |
| 图片去水印 | https://www.runninghub.cn/ai-detail/1939683977558925314 | 公开应用介绍支持 Kontext-DEV / Nunchaku；具体量化权重应与工作流核对 |
| 人物背景分离 | https://www.runninghub.cn/ai-detail/2071773965567217666 | 原网站披露 RMBG-1.4 + ViTMatte；具体权重以工作流为据 |
| 视频去水印 | 工作流 2109559022260154369 | 原网站披露 MiniMax-Remover；模型权重、YOLO 版本需以工作流为据 |

官方型号参考：

- Gemini 3.1 Flash Image / Nano Banana 2: https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image
- FLUX.1 Kontext [dev]: https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev
- BRIA RMBG-1.4: https://huggingface.co/briaai/RMBG-1.4
- ViTMatte: https://github.com/hustvl/ViTMatte
- MiniMax-Remover: https://github.com/zibojia/MiniMax-Remover
- Gemini 3.5 Flash: https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash

最后一个官方页面已说明 `gemini-3.5-flash` 弃用，Google 官方 API 会路由到 `gemini-3.6-flash`。这不能直接证明 RunningHub 的实际路由，不能未经确认将网站改成“实际使用 Gemini 3.6 Flash”。

## 继续完成所需信息

用户对三个模型的确认已记录，名称与官方来源对应。进一步核实图片转提示词当前服务版本；如审核需要精确到模型变体，再补充 Krea 2 与 FLUX.2 的具体权重或变体，不擅自指定。更新页面内状态文字后再部署，匿名 HTTP 验证中英文页面及入口可读，再向 Waffo 提交公开链接。尚未联系审核员或重新提交。

验证：`python3 website/static/build.py` 成功；`python3 -m unittest discover -s website-static -p 'test_*.py'` 7 项通过；`node --check website/static/src/assets/site.js`、`git diff --check` 通过。未构建或运行 Glance，未进行 UI 测试。

## 本轮用户确认与官方名称

用户原文：“图生图用的是krea2，换装用的是 qwen2.1，智能扩图用的是flux2”。这是功能与模型对应关系的来源；官方文档仅用于规范型号名称，不证明 Glance 的运行配置。

- Krea 2：https://www.krea.ai/krea-2
- Qwen-Image-2.1：https://huggingface.co/Qwen/Qwen-Image-2.1
- FLUX.2：https://help.bfl.ai/articles/4292391522-what-is-flux-2

## Gemini 系列确认

用户进一步确认“就是用gemini 的”。据此将图片转提示词标为 Google Gemini，用户未确认具体型号/版本。公开页面草稿已移除原先无配置证据的 Gemini 3.5 Flash 和服务路由推断，保留“具体型号与版本待核实”。定价页同步更新。该条尚不能称为满足 Waffo 精确版本披露要求；本轮未部署。
