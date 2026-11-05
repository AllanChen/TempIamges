# 产品与网站背景

整理日期：2026-10-22。已核对公开官网响应与本地网站源码；App 发行包中的功能尚未逐项验证。

## 产品

- 名称：Glance。
- 形态：原生 macOS 菜单栏 App。
- 核心使用方式：在其他应用中选中包含链接或文件路径的文本，通过快捷键打开预览。
- 仓库 README 记录的能力：图片与视频预览、文档和网页查看、图片深度检查、多图浏览与比较、Finder 打开入口、预览历史。
- Widget：为媒体处理提供扩展工具；使用时需要登录，具体功能及积分消耗应按当前 Widget 配置核对。

来源：[项目 README](../../README.md)、[图片查看器](../../clients/macos/Glance/Sources/ImageInspectWindow.swift)、[视频查看器](../../clients/macos/Glance/Sources/VideoCompareWindow.swift)、[Widget 模型](../../clients/macos/Glance/Sources/WidgetModels.swift)。

## 正式网站与代码

- 正式域名：[glancepreview.com](https://glancepreview.com/)。旧域名 `glance.mcreator.ai` 和 `www.glancepreview.com` 的首页均 301 跳转至该地址。
- 对应代码：[`website/static/`](../static/)，由 [`build.py`](../static/build.py) 生成静态页面。
- 线上首页与本地 `website/static/public/index.html` 的文本差异仅为 Cloudflare 邮箱保护改写和附加解码脚本；线上 `site.js` 与本地源码字节一致。
- 首页、价格、Widget、安装及政策页面已有中英文独立 URL；原路径为中文，`/en/` 下为英文，初始 HTML 直接输出对应语言。
- 公开下载入口：`https://glancepreview.com/download/Glance-1.0.0-beta.1.dmg`。已核对发布前后 SHA-256 一致；未安装或运行发行包。
- 当前线上安装页标注 macOS 12.3+、Apple silicon、内测版。发布文案时仍须与实际发行包核对。
- `website/app/` 中另有 React / vinext 实现，本轮没有证据表明它是正式官网当前的实现，不作为此次 SEO 修改入口。

取证：[发布前 HTTP 审计数据](evidence/2026-10-22-http-audit.json)、[首轮审计](audit-2026-10-22.md)、[发布记录](releases/2026-10-22.md)。

## 待确认

1. 优先面向哪些国家或地区。首轮已按用户发布指示上线英文入口，并保留中文页面。
2. 首要转化目标。首轮以官网下载点击作为可实施的代理指标，不把点击等同于安装或活跃用户。
3. 当前可公开宣传的发行版本、功能范围、系统要求与价格。
4. Search Console、网站分析及历史搜索流量是否已有数据。

## 关键词调研起点

以下是按产品功能整理的候选主题；首轮方向验证与优先级见 [SEO 执行计划](plan.md)，具体词表见 [关键词映射](keyword-map.csv)。没有搜索量或难度数据：

- Mac 跨应用链接与文件预览。
- Mac 图片查看与图片对比。
- Mac 视频预览与视频对比。
- 图片文字识别。
- 已上线 Widget 对应的具体媒体处理需求。

后续需结合目标市场的真实搜索结果和发行版本能力，决定采用哪些主题以及对应页面。
