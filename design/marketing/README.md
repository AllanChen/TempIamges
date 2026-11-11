# 宣传资料

- [brand-assets](brand-assets/README.md)：Logo 与品牌样例图片；根目录原 logo.png / logo.svg 已移入此处。
- [videos](videos/)：10 秒、20 秒宣传片、超分宣传片和教程，保留生成脚本、音频、分镜及成片。
- [30 秒产品介绍](videos/glance-intro-30s/README.md)：中英文、配音／无配音、竖屏版，以及 X／小红书发布文案和封面；早期 AI 主导版见 [glance-ai-intro-43s](videos/glance-ai-intro-43s/README.md)。
- [素材生成脚本](scripts/refresh-brand-media.py)：从品牌样例与 [App Figma 导出](../app/layout/figma-export/) 生成官网与宣传素材。
- [官网部署资源](../../website/static/src/assets/)：实际发布的媒体副本。

视频 render.py 按脚本位置定位仓库和素材，不依赖原来的 outputs/ 或 layout/ 根目录。渲染会写入成片；目录检查只编译 Python 语法，不运行渲染或截图。

- 四平台发布文案（小红书 / X / YouTube / V2EX，含 UTM 链接）：[Glance发布文案-小红书-X-YouTube-V2EX.md](Glance发布文案-小红书-X-YouTube-V2EX.md)
