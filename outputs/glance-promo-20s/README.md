# Glance 产品介绍 · 20 秒

成片：中文版 `glance-20s.mp4`、英文版 `glance-20s-en.mp4`，均为 1920 × 1080、16:9、30 fps、H.264 + AAC 立体声。官网另提供压缩到 1280 × 720 的版本。

使用当前 Figma All 页面导出的 UI、中文画面文案、原创合成配乐和操作音效。视频为设计素材制作的产品演示动效，不是实机录屏。

| 时间 | 内容 |
| --- | --- |
| 0–3s | 选中路径，Option + Space 快速唤起 |
| 3–6.2s | 图片细节查看与多图浏览 |
| 6.2–9.2s | 双图并排比较 |
| 9.2–12.7s | 视频预览、截帧、裁剪 |
| 12.7–17.5s | Widget 图片与文本输入、运行、结果 |
| 17.5–20s | Glance 品牌与快捷键 |

Figma 来源：`6UToazHuW3e37cw4XLBd8t`。

- Focus `49:2`
- Compare `38:3289`
- Video `110:2`
- Capture Editor / Video `208:3118`
- Widget Input `165:711`
- Widget Result `167:1047`
- Tangible Character Logo `206:1650`

保留导出 UI 的窗口、工具栏、按钮与布局；媒体统一使用 `layout/brand-assets/glance-alpine-before.png` 和 `glance-alpine-after.png`。两张图为同一山湖场景的自然版和暖色版，分别用于查看、对比和 Widget 演示。设计文件本身未改动；画面为产品动效，非实机录屏或实际 AI 任务结果。

`render.py` 为可重新渲染的源文件，依赖 Pillow、NumPy 和 ffmpeg。运行 `render.py --lang zh` 或 `render.py --lang en` 生成对应语言版本；英文版另外输出 `poster-en.jpg`。`assets/` 为原始 Figma 导出素材；官网截图由 `scripts/refresh-brand-media.py` 重组原 UI 与山湖照片，并生成带英文界面的 Widget 图片。`poster.jpg` 为中文版片尾封面，`storyboard.jpg` 为分镜预览。
