# RemoveBG 高级 Widget

`widget.json` 由线上 Manifest 整理而来（含中英文 `localizations`），发布新版本时随代码一起提交；`main.py` 接收 Glance 任务中的本地图片路径，返回本地图片，由 Worker 上传结果。

处理流程：

1. 调用 guluapi 的 `gpt-image-2.5-flare`（`POST https://guluapi.com/v1/images/edits`，`background=transparent`、`output_format=png`）。HEIC/HEIF 会先用 `sips` 转成 PNG 再上传。
2. 输出保持原图比例，长边限制在 1024–2048（`MIN_LONG_EDGE` / `MAX_LONG_EDGE`）：超过 2048 等比缩小，不足 1024 等比放大，其间保持原尺寸。GPT 是重绘而不是抠图，且倾向把横图重新构图成竖图，所以横图会先旋转 90° 再发给 GPT，拿到结果后转回来；最后检查比例和主体像素是否与原图对齐。
3. 只有 GPT Image 返回内容审核拒绝时，才自动改用本机 Apple Vision（`remove_bg_vision.swift`，需要 macOS 14+ 和 Xcode Command Line Tools）。Swift 脚本首次运行时会编译并缓存到 `~/Library/Caches/glance-widgets/remove-bg-vision/`。
4. 其他失败（接口错误、超时、结果没有透明背景、与原图不对齐等）会重试 3 次，仍失败则任务失败，不会改用 Vision。

Key 读取顺序与 gpu_task 一致：环境变量 `GULU_GPTIMAGE_KEY`，否则读 `~/Desktop/work/gpu_task/config/config.env`（可用 `GULU_CONFIG_ENV` 指定其他路径）。

在仓库根目录运行本地测试：

```bash
python3 -m venv widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/.venv
widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/.venv/bin/python -m pip install -r widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/requirements.txt
.venv/bin/glance widget test \
  --code widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa \
  --input /path/to/image.png \
  --python widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/.venv/bin/python
```

也可以直接运行 `main.py /path/to/image.png`，输出文件路径会写在 JSON 结果中。当前账号要让 Worker 领取此官方 Widget 的任务，还需 Service 授予该版本任务权限；仅本地 `add` 不会授予权限。

旧的 RunningHub 实现备份在 `main.py.runninghub.bak` / `README.md.runninghub.bak`。
