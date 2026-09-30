# 免费图床 Widget

`main.py` 接收 `input.url` 或 `parameters.url`，下载图片后用 `FREEIMAGEKEY` 调用 Freeimage 的上传 API，返回 Freeimage 图片 URL 作为文本输出。如果 Glance Worker 已将 `input.url` 下载到 `input.path`，会直接使用该文件，避免重复下载。支持 PNG、JPEG、GIF、WebP、BMP；在 macOS 上还会先将 HEIC 转换为 PNG。

在仓库根目录直接用 URL 运行：

```bash
export FREEIMAGEKEY=<你的 Freeimage API Key>
.venv/bin/python widgets/55e64c7e-f079-448a-b5bd-7315b2589019/main.py \
  https://example.com/image.png
```

也可以让 CLI 用本地图片测试：

```bash
.venv/bin/glance widget test \
  --code widgets/55e64c7e-f079-448a-b5bd-7315b2589019 \
  --input /path/to/image.png
```

旧目录仍不需要 `widget.json`。目前服务端保存的 Manifest 将输出类型写为 `image`；实际返回的是文本 URL，发布或更新服务端 Manifest 时应改为 `text`。当前账号还需获得该官方 Widget 的任务权限，Worker 才能替它接单。
