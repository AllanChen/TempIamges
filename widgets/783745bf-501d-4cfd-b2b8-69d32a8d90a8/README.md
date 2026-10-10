# 视频去水印 Widget

输入一个视频。Worker 使用 FFmpeg 将它分成时长不超过 8 秒的 MP4 片段，把每段上传到 RunningHub AI 应用 `2098906395704819714` 的 `5099.video` 节点，等待全部生成完成后按原顺序合并为一个 MP4。Glance Worker 将最终文件上传到 Glance 服务端。

## Worker 环境

- 设置 `RUNNINGHUB_API_KEY_AI`。不要将密钥写入代码、Manifest 或日志。
- 安装 `ffmpeg` 和 `ffprobe`，并确保它们位于 Worker 的 `PATH` 中。
- Python 仅使用标准库；无需 `requests`。

Glance 当前限制单个输入与输出文件不超过 50 MB，RunningHub 的单次上传不超过 30 MB。实现最多拆成 24 段，并以 3 个并发任务处理。生成失败最多尝试 3 次；明确的内容审核拒绝和提交状态不明的任务不会重复提交。整个 Widget 受 Glance 的 25 分钟运行时限约束；这里内部留出 150 秒给上传和状态回报。

本地验证：

```sh
.venv/bin/glance widget validate --manifest widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8/widget.json
python3 -m unittest discover -s widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8 -p 'test_main.py'
```

创建阶段未提交审核。需要发布时再运行 `glance widget publish --manifest widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8/widget.json --code widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8`。
