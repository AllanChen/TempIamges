# Glance · 10 秒产品短片

成片：`glance-10s.mp4`。1920 × 1080，16:9，30 fps，10 秒；H.264 视频、AAC 立体声音轨。

主线：选中路径 → Option + Space → Peek → Image Inspect / Widget → 品牌。

| 时间 | 画面与文案 |
| --- | --- |
| 0–2.05s | 选中。即将看见。文本路径选中，快捷键点亮。 |
| 2.05–4.65s | 一按。内容展开。山湖图片浮出，进入细节查看。 |
| 4.65–7.75s | 看清细节。继续创作。展示现有 Image Inspect 设计素材，强调 Widget 入口。 |
| 7.75–10s | Glance。一眼即见，灵感不断。 |

使用仓库现有 `logo.png`，图片与查看窗口使用 `layout/brand-assets/` 中的新山湖素材，保持镜头连贯。视频是基于设计素材制作的产品动效，非实机录屏。音轨由渲染脚本合成。

`render.py` 为可重渲染的源文件；依赖 Pillow、NumPy 和 ffmpeg。`poster.jpg` 是片尾封面，`storyboard.jpg` 为四段画面总览。
