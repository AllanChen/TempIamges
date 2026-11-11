# Glance 产品介绍 · 30 秒（看、改、比，一个窗口）

面向大众用户的第一支介绍片：以看图和对比为主线，AI 作为"看完之后的下一步"；⌥ 空格（Peek）只在结尾作为彩蛋出现。1920 × 1080、30 fps、H.264 + AAC；竖屏版为 1080 × 1920。

| 文件 | 用途 |
| --- | --- |
| `glance-intro-30s-zh-voice.mp4` / `-en-voice.mp4` | 配音版（中文：婷婷；英文：Samantha，均为 macOS 自带语音），适合发给朋友、X、YouTube、B 站 |
| `glance-intro-30s-zh.mp4` / `-en.mp4` | 无配音版（音乐和音效） |
| `*-720p.mp4` | 官网用压缩版，建议无配音版静音自动播放 |
| `glance-intro-30s-zh-vertical-voice.mp4` / `-zh-vertical.mp4` | 竖屏 9:16，小红书、抖音 |
| `../../Glance发布文案-小红书-X-YouTube-V2EX.md` | 小红书、X、YouTube、V2EX 发布文案（含 UTM 链接） |
| `social/xiaohongshu-cover.jpg` | 小红书封面，3:4 |
| `storyboard-*.jpg`、`poster-*.jpg` | 分镜总览与封面帧 |
| `soundtrack-<lang>.wav` / `soundtrack-<lang>-voice.wav` | 无配音音轨 / 配音混音（音乐自动避让人声） |
| `voice-zh/`、`voice-en/` | 每句讲解的原始 AIFF |

| 时间 | 画面 | 字幕（中 / 英） |
| --- | --- | --- |
| 0–5s | 下载文件夹、系统预览、在线工具上传、排队、再对比，窗口越堆越多 | 修一张图，要开几个窗口？ / One photo. How many windows? |
| 5–8s | 窗口收起，Glance 出现 | 用 Glance，一个窗口就够了。 / With Glance, one window is enough. |
| 8–13s | 双击打开、放大约 260%、翻看同组图片 | 双击打开，看清每一处细节。 / Double-click. See every detail. |
| 13–18s | 并排对比 → 滑杆对比 | 两张图，差别一眼看清。 / Two images. Spot the difference. |
| 18–25s | 右键 → Widget → 人物背景分离，随后扩图、高清放大 | 不满意？右键，用 AI 改。 / Not quite right? Fix it with AI. |
| 25–30s | Logo、免费范围、⌥ 空格彩蛋、glancepreview.com | 看、改、比，一个窗口。 / View. Fix. Compare. One window. |

讲解稿（中文）：看图、修图、再对比，每次都要开一堆窗口？／用 Glance，一个窗口就够了。／双击就能打开，放大、翻看，细节一清二楚。／两张图并排对比，哪张更好，一眼就知道。／不满意？右键用 AI 改：去背景、扩图、变高清。／Glance，在 Mac 上看、改、比，一个窗口搞定。

这是基于现有 Figma 导出界面和 `design/marketing/brand-assets/` 示例图的产品动效，不是录屏。AI 画面标注"示例效果"：去背景结果由本机 rembg（BiRefNet portrait 模型）生成，不是 Background Remover Pro Widget 的输出；换景、扩图使用仓库提供的示例图对；高清放大为降采样示意。开头"在线修图工具""排队中"为虚构的通用情境。

## 重新渲染

在仓库根目录运行，依赖 Pillow、NumPy、ffmpeg；界面绘制复用 `../glance-ai-intro-43s/render.py`。

```sh
.venv/bin/python design/marketing/videos/glance-intro-30s/render.py --lang zh   # 或 --lang en；--preview 只出分镜
.venv/bin/python design/marketing/videos/glance-intro-30s/vertical.py --lang zh # 竖屏，需先运行 render.py 生成音轨
.venv/bin/python design/marketing/videos/glance-intro-30s/cover.py              # 小红书封面
```

讲解音频需要重做时，用 `say -v Tingting -r 200` / `say -v Samantha -r 185` 逐句生成到 `voice-zh/<n>.aiff` / `voice-en/<n>.aiff`（各 6 句，起点见 `render.py` 的 `VOICE_AT`）。
