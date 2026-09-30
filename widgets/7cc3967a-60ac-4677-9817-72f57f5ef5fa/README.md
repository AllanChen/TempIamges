# RemoveBG 高级 Widget

这个目录保留旧版没有 `widget.json` 的结构。CLI 的 Manifest 缓存放在本机配置目录；`main.py` 接收 Glance 任务中的本地图片路径，返回本地图片，由 Worker 上传结果。

在仓库根目录运行本地测试：

```bash
python3 -m venv widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/.venv
widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/.venv/bin/python -m pip install -r widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/requirements.txt
export RUNNINGHUB_API_KEY=<你的 RunningHub API Key>
.venv/bin/glance widget test \
  --code widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa \
  --input /path/to/image.png \
  --python widgets/7cc3967a-60ac-4677-9817-72f57f5ef5fa/.venv/bin/python
```

也可以直接运行 `main.py /path/to/image.png`，输出文件路径会写在 JSON 结果中。当前账号要让 Worker 领取此官方 Widget 的任务，还需 Service 授予该版本任务权限；仅本地 `add` 不会授予权限。
