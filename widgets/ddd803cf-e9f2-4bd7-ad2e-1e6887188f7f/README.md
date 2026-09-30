# 超分 Widget

这个旧目录不需要 `widget.json`。`main.py` 读取 Glance 下载好的本地图片，用 RunningHub 生成超分图片，再返回本地文件路径，由 Glance Worker 上传结果。默认分辨率为 `4k`；本地测试可用 `--parameters` 指定 `1k` 或 `2k`。

在仓库根目录运行：

```bash
python3 -m venv widgets/ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f/.venv
widgets/ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f/.venv/bin/python -m pip install -r widgets/ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f/requirements.txt
export RUNNINGHUB_API_KEY=<你的 RunningHub API Key>
.venv/bin/glance widget test \
  --code widgets/ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f \
  --input /path/to/image.png \
  --parameters '{"resolution":"2k"}' \
  --python widgets/ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f/.venv/bin/python
```

也可以直接运行 `main.py /path/to/image.png --resolution 2k`。本地 `add` 不会授予官方 Widget 的任务领取权限，Worker 接单还需 Service 授权。
