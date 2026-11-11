# Glance AI 介绍 · 43 秒（早期方向，已被 30 秒版取代）

以 AI 修图为主线的介绍片：开头讲本地 AI 工作流的麻烦（搭节点、没显卡、装环境），然后"右键就行"，依次展示去背景、换景、扩图、高清放大，最后以 ⌥ 空格作为彩蛋。之后定位调整为"看图为主、AI 为下一步"，正式使用的是 [`../glance-intro-30s/`](../glance-intro-30s/README.md)。本片保留作参考。

`glance-ai-intro-43s-en.mp4` / `-zh.mp4`：1920 × 1080、30 fps、43.2 秒、H.264 + AAC，无配音；`*-720p.mp4` 为压缩版。

| 时间 | 内容 |
| --- | --- |
| 0–9s | 痛点：搭工作流、没有显卡、安装调试；"There is an easier way. Glance. Just right-click." |
| 9–28s | 右键 → Widget：人物背景分离、移除物体（换景）、智能扩图、高清放大 |
| 28–32s | 更多 Widget：AI 换装、去水印、视频去水印、图生图、图片转提示词、免费图床 |
| 32–39s | 不用工作流、不用显卡、不用安装；⌥ 空格彩蛋 |
| 39–43s | 品牌、glancepreview.com、14 天试用 |

产品动效，不是录屏。`assets/cutout-birefnet-portrait.png` 是用本机 rembg（BiRefNet portrait）对示例人像做的去背景结果，作为示例效果使用，不是 Background Remover Pro Widget 的输出。其余示例图来自 `design/marketing/brand-assets/`。

`render.py` 同时是 `glance-intro-30s` 的界面绘制库（Glance 窗口、右键菜单、演示场景），修改时注意两边。

```sh
.venv/bin/python design/marketing/videos/glance-ai-intro-43s/render.py --lang en   # 或 --lang zh；--preview 只出分镜
```
