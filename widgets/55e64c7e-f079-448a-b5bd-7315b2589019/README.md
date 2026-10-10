# 免费图床 Widget

`main.py` 从任务的 `task_params`（Worker 请求中对应 `parameters`）读取 `url` 和 `location`，也接受 `input.url`，并从 `input.type` 区分图片与视频。图片在 `China` 或 `CN` 时优先使用 Freeimage，其他地区使用 Glance R2；Freeimage 不可用或没有 `FREEIMAGEKEY` 时回退 R2。视频在所有地区都使用 Glance R2，因为 Freeimage 的上传 API 只接受图片。图片原 URL 已在目标图床时直接返回；否则下载后重新上传。视频始终生成独立的任务资产，避免结果指向会过期的输入签名 URL。如果 Worker 已把 `input.url` 下载到 `input.path`，会复用该文件。支持 PNG、JPEG、GIF、WebP、BMP、HEIC 图片，以及 MP4、MOV、WebM 视频；媒体文件上限为 50 MB。在 macOS 上会先将 HEIC 转换为 PNG。

Widget 按输入类型返回图片或视频。Freeimage 图片返回 `{"type":"image","url":"https://..."}`；R2 上传由 `glance worker` 完成，Widget 返回对应类型的本地 `path`，Worker 上传为任务资产后由 Service 生成结果 URL。任务中心对图片和视频结果都提供「Copy URL」。R2 URL 是有时效的签名地址，复制时会重新获取。

在仓库根目录直接用 URL 运行时，默认按中国地区使用 Freeimage：

```bash
export FREEIMAGEKEY=<你的 Freeimage API Key>
.venv/bin/python widgets/55e64c7e-f079-448a-b5bd-7315b2589019/main.py \
  https://example.com/image.png
```

也可以让 CLI 用本地图片或视频测试。R2 路径需要通过正在运行的 Worker 和 Service 完整执行：

```bash
.venv/bin/glance widget test \
  --code widgets/55e64c7e-f079-448a-b5bd-7315b2589019 \
  --input /path/to/image.png
```

`widget.json` 是仓库中的本地 Manifest 副本，方便 CLI 和后续维护。线上 Marketplace 读取的是服务端数据库 `widget_versions.manifest_json`；修改此文件不会自动更新线上目录，需要在管理后台把输入类型改为 `image` 和 `video`、添加 `video/mp4`、`video/quicktime`、`video/webm`，并把输出类型改为 `image` 和 `video` 后保存。当前账号还需获得该官方 Widget 的任务权限，Worker 才能替它接单。
