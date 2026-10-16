# Glance 高清放大 · 10 秒宣传片

成片：`glance-upscale-10s.mp4`，1920 × 1080，16:9，30 fps，精确 10 秒，H.264 + AAC。
中文画面文案、原创合成配乐与操作音效，无旁白。

| 时间 | 画面与文案 |
| --- | --- |
| 0–1.55s | 只想放大一张图。还要自己搭工作流？节点、依赖、参数交错。 |
| 1.55–3.05s | 还得先看完广告？广告挡住在线工具，倒计时。 |
| 3.05–3.6s | 换个简单的方式。用 Glance。 |
| 3.6–5.35s | Glance 图片窗口 → 右键 → Widget → 高清放大。 |
| 5.35–6.95s | 然后，等它完成。画布呼吸边框、缩略图进度。 |
| 6.95–8.45s | 放大。清晰。图片划过显示清晰效果，提示完成、自动保存。 |
| 8.45–10s | Glance。右键一下，静待清晰。高清放大 Widget。 |

使用仓库已有 Figma 导出、Logo 与 `layout/brand-assets/` 的山湖示例图片。最新右键菜单来自
`layout/figma-export/widget-context-menu-compact-credits.png`，保留独立积分标签。
图片窗口、任务状态沿用 `outputs/glance-upscale-tutorial/render.py` 的现有素材合成。

这是产品动效，非实机录屏。画质前后为同一示例图片的降采样/原图对比，非本次调用模型生成的实际结果；画面注明效果示意。
处理时间经剪辑压缩；右键使用以已安装高清放大 Widget 为前提。片中没有“免费”或“即时完成”的承诺。
开场工作流与广告为抽象情境，没有指向具体网站或宣称所有工具只有这两种途径。

`render.py`：可重新渲染的源文件，依赖 Pillow、NumPy、ffmpeg，以及仓库现有教程素材。
`--preview` 仅生成分镜；`storyboard.jpg` 为分镜总览，`poster.jpg` 为封面。

```sh
/private/tmp/glance-promo-venv/bin/python outputs/glance-upscale-promo-10s/render.py
```
