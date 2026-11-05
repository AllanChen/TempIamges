# 视频去水印 Widget

输入一个视频。正式报价为每 10 秒 100 点，不足 10 秒按一份，和内部 8 秒处理片段相互独立。客户端先检查余额，再让用户确认总费用；失败整单退款。

Worker 使用 FFmpeg 将它分成时长不超过 8 秒的 MP4 片段，把每段上传到 RunningHub（runninghub.cn）workflow `2109559022260154369` 的视频输入节点，等待全部生成完成后按原顺序合并为一个 MP4。Glance Worker 将最终文件上传到 Glance 服务端。

输入节点是 `184`，最终去水印输出必须取 **`183`（Minmaxremover）**。该 workflow 同时返回 `283`（Eraser）的中间视频，不能按列表顺序选择第一个 MP4。最终节点缺失、重复或返回非视频时任务失败，不会退回中间结果，也不会为已经成功运行的 workflow 再次提交生成。

只有一段结果时保留 RunningHub 视频原文件，不重新编码或补音；多段合并时按每段视频流时长限制音频填充，避免尾部静音把视频拖长。

## Worker 环境

- 设置 `RUNNINGHUB_API_KEY`（runninghub.cn 的 key；旧的 `RUNNINGHUB_API_KEY_AI` 仍可作为回退）。不要将密钥写入代码、Manifest 或日志。
- 安装 `ffmpeg` 和 `ffprobe`，并确保它们位于 Worker 的 `PATH` 中。
- Python 仅使用标准库；无需 `requests`。

Glance 当前限制单个输入与输出文件不超过 50 MB，RunningHub 的单次上传不超过 30 MB。实现最多拆成 24 段，并以 3 个并发任务处理。生成失败最多尝试 3 次；明确的内容审核拒绝和提交状态不明的任务不会重复提交。整个 Widget 受 Glance 的 25 分钟运行时限约束；这里内部留出 150 秒给上传和状态回报。

本地验证：

```sh
.venv/bin/glance widget validate --manifest widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8/widget.json
python3 -m unittest discover -s widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8 -p 'test_main.py'
```

0.3.0 已于 2026-10-27 发布。后续版本需要发布时运行 `glance widget publish --manifest widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8/widget.json --code widgets/783745bf-501d-4cfd-b2b8-69d32a8d90a8`。

## 0.3.0 按时长计费（已发布）

Manifest 新增 `billing: {"mode":"duration","unitSeconds":10}`，`creditCost:100` 表示每个计费单位的单价。最多 24 段对应当前算法的 187.2 秒上限，30 分钟输入暂不支持。

生产任务必须由支持 `durationBilling:1` 的新版 Glance CLI Worker 领取。CLI 在调用 `main.py` 之前读取实际文件时长与 SHA-256，并向服务端 `verify-input` 核验；核验失败不会开始付费处理。先升级 CLI，再启用新清单。完整上线顺序和回滚约束见 [计费实现说明](../../../docs/video-duration-billing.md)。2026-10-27 已完成服务端、迁移、Widget 发布及本机 Worker 重启；macOS 费用确认弹窗需新版客户端。
