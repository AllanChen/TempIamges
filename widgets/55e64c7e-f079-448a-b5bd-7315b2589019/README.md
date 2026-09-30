# 免费图床 Widget

`main.py` 从任务的 `task_params`（Worker 请求中对应 `parameters`）读取 `url` 和 `location`，也接受 `input.url`。`location` 为 `China` 或 `CN` 时目标是 Freeimage，其他地区目标是 Glance R2。原 URL 已在目标图床时直接返回；否则下载图片后重新上传。如果 Worker 已把 `input.url` 下载到 `input.path`，会复用该文件。Freeimage 上传失败或没有 `FREEIMAGEKEY` 时回退 R2。支持 PNG、JPEG、GIF、WebP、BMP；在 macOS 上还会先将 HEIC 转换为 PNG。

R2 上传由 `glance worker` 完成。Widget 返回带 `returnURL` 的图片输出，Worker 将其上传为任务资产；Service 在查询任务结果时生成图片 URL，并以文本输出返回。R2 URL 是有时效的签名地址，每次查询任务结果会刷新。

在仓库根目录直接用 URL 运行时，默认按中国地区使用 Freeimage：

```bash
export FREEIMAGEKEY=<你的 Freeimage API Key>
.venv/bin/python widgets/55e64c7e-f079-448a-b5bd-7315b2589019/main.py \
  https://example.com/image.png
```

也可以让 CLI 用本地图片测试。R2 路径需要通过正在运行的 Worker 和 Service 完整执行：

```bash
.venv/bin/glance widget test \
  --code widgets/55e64c7e-f079-448a-b5bd-7315b2589019 \
  --input /path/to/image.png
```

旧目录仍不需要 `widget.json`。目前服务端保存的 Manifest 将输出类型写为 `image`；实际返回的是文本 URL，发布或更新服务端 Manifest 时应改为 `text`。当前账号还需获得该官方 Widget 的任务权限，Worker 才能替它接单。
