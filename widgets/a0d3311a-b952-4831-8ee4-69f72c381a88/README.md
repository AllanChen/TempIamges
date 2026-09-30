# Remove Background Widget

这个旧目录不需要 `widget.json`。`main.py` 从 Glance 任务读取本地图片，使用 rembg 在本机生成透明背景 PNG，返回本地文件路径，由 Glance Worker 上传结果。macOS 使用 CPU 版 `onnxruntime`；第一次运行时 rembg 会下载模型。

在仓库根目录运行：

```bash
python3.12 -m venv widgets/a0d3311a-b952-4831-8ee4-69f72c381a88/.venv
widgets/a0d3311a-b952-4831-8ee4-69f72c381a88/.venv/bin/python -m pip install -r widgets/a0d3311a-b952-4831-8ee4-69f72c381a88/requirement.txt
.venv/bin/glance widget test \
  --code widgets/a0d3311a-b952-4831-8ee4-69f72c381a88 \
  --input /path/to/image.png \
  --python widgets/a0d3311a-b952-4831-8ee4-69f72c381a88/.venv/bin/python
```

也可以直接运行 `main.py /path/to/image.png`。本地 `add` 不会授予官方 Widget 的任务领取权限，Worker 接单还需 Service 授权。
