# 视频去水印 Widget

输入一个视频（最大 100 MB，与 Glance 上传上限一致）。Worker 使用 FFmpeg 将它分成时长不超过 8 秒的 MP4 片段，把每段通过 S3 兼容接口（SigV4，仅标准库）上传到 Cloudflare R2 的 `temp` 桶（`https://temp.pppron.com/<key>`），按分段提交到 `https://api.pppron.com/vision-tasks`，轮询 `/vision-tasks/uuid/{task_uuid}`（`task_status` 3 成功、4 失败），下载各段结果按原顺序合并，再把**原视频的音轨**换回去。合并结果同样上传到 `temp.pppron.com`，Widget 返回 `{"type":"video","url":…}`，由 Glance 客户端直接下载到本机，因此不受 50 MB 结果上限约束。

## 行为

- 不限制视频时长；段数由时长决定。
- 并发 2 段（`PPPRON_CONCURRENCY` 可覆盖）。
- 单段被 pppron 判定失败时自动重新提交，最多 3 次；提交请求本身不重试，避免重复计费。
- 已完成段的结果 URL 按原视频 SHA-256 缓存在 `~/.cache/glance-video-widget/`（`GLANCE_VIDEO_WIDGET_CACHE` 可覆盖）。任务失败后重跑同一视频时跳过已付费的段。
- `showResultURL: false`：结果只存本机，任务中心不显示 Copy URL。

## 参数（task parameters）

`team_id`、`team_creator_id`、`user_id`、`widget_name`、`valid_token` 都有默认值（来自参考脚本，测试 token 待替换），也可通过 task parameters 或 `PPPRON_<NAME>` 环境变量覆盖。可选：`prompt`、`task_type`（默认 2）、`with_logo`，以及合并进 `task_params` 的 `extra_params`。每段的 `task_params.url` 由 Widget 填入。

## Worker 环境

- 安装 `ffmpeg` 和 `ffprobe`；Python 仅用标准库。
- R2 凭证 `ACCOUNT_ID`、`ACCESS_KEY_ID`、`SECRET_ACCESS_KEY` 目前写在 `main.py` 顶部作为默认值，也可用同名环境变量覆盖。发布前请移除默认值和测试 token。

```sh
.venv/bin/glance widget validate --manifest widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8/widget.json
python3 -m unittest discover -s widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8 -p 'test_main.py'
.venv/bin/glance widget test --code widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8 --input short.mp4
```

线上 Marketplace 读取的是服务端数据库里的 manifest；改完 `widget.json` 后需要用 `glance widget publish` 或在管理后台把 0.2.0 更新上去。
