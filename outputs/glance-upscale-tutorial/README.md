# Glance Widget 教程 · 高清放大 · 约 2 分钟

成片：`glance-upscale-tutorial.mp4`，1920 × 1080，16:9，30 fps，H.264 + AAC 立体声，时长 118.6 s。

中文旁白（macOS `say`，婷婷音色）+ 同步字幕 + 轻量合成配乐与操作音效。视频由当前 Figma 导出的 UI 合成，
**不是实机录屏**；Widget 市场与任务中心的文案按 `zh-Hans.lproj/Localizable.strings` 本地化重绘。

| 时间 | 步骤 | 画面 |
| --- | --- | --- |
| 0–11s | 开场 | 标题、原图 / 高清放大 对比预览 |
| 11–29.6s | 01 打开图片 | 选中路径 → Option + Space → 图片检查窗口；左侧列出访达 / 主页拖入两种方式 |
| 29.6–43.6s | 02 安装 Widget | 工具栏「Widget 市场」→ 找到「高清放大」→ 点「安装」→ 变为「已安装」 |
| 43.6–60.6s | 03 运行 | 右键菜单 → Widget ▸ 高清放大 · 每次 1 积分（无提示词，直接开始） |
| 60.6–82.2s | 04 等待结果 | 画布呼吸边框 + 缩略图进度徽标；切换到其他图片；任务中心（时间线 / 任务详情 / 生成中芯片动效） |
| 82.2–98.8s | 05 查看结果 | 「Widget 已完成」通知 → 结果以 NEW 插入胶片条 → 比较视图 原图 / 高清放大 |
| 98.8–118.6s | 06 保存与导出 | 自动保存到 下载/Glance、⌘S 快速存储 toast、导出子菜单 → 片尾 |

Figma 来源（`6UToazHuW3e37cw4XLBd8t`）：Focus `49:2`、Compare `38:3289`、Widget Market `248:6617`
（按钮状态 `248:6936` / `248:6945`）、Task Center Running `215:5876`（按子节点导出后拼合）、
Task Running Motion 芯片 `215:6312` `215:6338` `215:6364` `215:6390` `215:6468`。

流程依据源码：`ImageInspectWindow.swift` `buildActionEntries` / `runWidget`（高清放大无参数，跳过输入面板）、
`WidgetTaskManager.swift`（阶段：上传中 → 提交中 → 处理中 → 下载中；结果写入 `~/Downloads/Glance/`）、
`ImageFilmstrip.swift`（进度 / NEW 徽标）。

- `render.py`：可重新渲染的源文件，依赖 Pillow、NumPy、ffmpeg；`--preview` 只输出分镜帧。
- `voice/script.txt`：旁白文稿；`voice/seg*.wav` 由 `say -v Tingting -r 175` 生成。
- `assets/`：Figma 导出 UI 素材；示例图片统一来自 `layout/brand-assets/` 的山湖图；`storyboard.jpg` 分镜；`poster.jpg` 封面。
