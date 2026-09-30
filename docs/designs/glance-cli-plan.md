# Glance CLI：发布、本机 Widget 表与统一任务 Worker

## Python 包交付

`glance-cli/` 是可发布到 PyPI 的 Python 包，开发者通过 `pip install glance-cli` 安装，获得 `glance` 命令。包使用 `pyproject.toml` 和 `console_scripts` 入口；首版支持 Python 3.11 及以上，尽量使用标准库。发布到 PyPI 由项目维护者执行，仓库中的实现和测试先完成。开发者的 Widget 代码由开发者自行管理，不会打进 CLI 包；CLI 只负责初始化模板、发布、领取任务、执行约定的 `main.py` 和回传结果。
包同时导出可选的 `WidgetTask` 类型和 `text`、`image`、`video`、`audio`、`result` 辅助函数，让开发者可以在自己的代码中导入使用。

开发时先用 `python3 -m venv .venv` 创建虚拟环境，再用 `.venv/bin/python -m pip install -e ./glance-cli` 安装源码。Homebrew Python 可能拒绝全局 pip 安装。Widget 可以共享 CLI 的虚拟环境，也可以给每个 Widget 建独立虚拟环境，并在 `test`、`publish` 或 `bind` 时通过 `--python` 指定其解释器。若 Widget 代码导入本包的辅助函数，也要在该 Widget 虚拟环境中安装本包。

## 开发者流程

1. 在目标目录运行 `glance widget init`。CLI 生成 UUID，以 UUID 新建文件夹，创建 `widget.json` 和 `main.py`；UUID 是永久 Widget ID。该目录同时登记到本机 Widget 表，状态为 `local`。
   `widget.json` 对已有 Widget 目录是可选的。已有目录可运行 `glance widget add <widget_path>` 直接挂载，不复制文件；本地有 Manifest 时优先读取，目录名可以不同于 Widget ID，但 Manifest 中的 ID 保持不变。旧目录没有 Manifest 时，目录名须为 Widget UUID；CLI 从 Service 获取已公开发布的 Manifest，缓存在 CLI 配置目录，不写入 Widget 源码目录。已登记的缓存可在 Service 暂时不可用时继续使用。首次添加时若本地和 Service 都没有 Manifest，CLI 无法确定版本与命令，需提供 Manifest。Service 不保存 Python 代码，缺少 `main.py` 时只能登记，不能接任务。
2. 开发者自行管理 `main.py`、依赖和各版本代码。`glance widget test` 在本机调用 `main(task)`，检查返回结果。
3. `glance widget publish --code <代码目录>` 提交 Manifest，并将 Widget ID、版本和代码目录的绝对路径登记到本机表。提交成功后，版本进入待审核状态，可以接收管理员测试任务。
4. 一台机器只需运行一个 `glance worker` 进程。它从本机表读取所有可接任务的 Widget 版本，向服务器批量请求任务，并调用对应目录的 `main.py`。
5. 管理员查看实际输出后手动批准，先灰度再正式发布。新版本审核期间，旧版仍可继续处理线上任务；开发者负责保留各版本代码。

## 命令与本机表

CLI 提供 `glance login`、`logout`、`whoami`、`glance widget init|add|bind|validate|test|publish|status|list|unpublish|delete`、`glance worker` 和 `glance worker logs`。

本机 SQLite 表位于用户配置目录，不放在 Widget 项目中。每条记录包含 Widget ID、版本、Manifest 路径、代码目录、该版本使用的 Python 解释器路径、本机启用状态、服务端状态、最近请求时间和错误。认证凭据单独保存。`init` 时登记本地版本；`publish` 时更新状态；`bind` 可以修改开发者自己管理的代码路径和解释器。Worker 每次请求前重读表；单次请求最多等待 5 秒，因此表的变化无需重启即可生效。Worker 每分钟同步服务端状态。

`add` 校验目录后登记绝对路径和解释器；同一 ID 与版本重复添加会更新路径。本地 `widget.json` 优先；没有时，UUID 模式从公开接口获取 Manifest，仅写入 CLI 私有缓存，不会伪造 `main.py`；无代码版本保持禁用。`widget test` 和 `widget validate` 可从本机表找到该缓存，因此旧源码目录不需要 Manifest。`init` 创建的目录仍包含 Manifest；首次发布必须能提供 Manifest。当前账号拥有该服务端版本时，CLI 同步审核状态并允许 Worker 请求任务；没有任务权限的朋友分享目录仅供本地测试。跨账号协作领取需要服务端单独授予权限，不能仅凭共享代码目录绕过所有权校验。

Worker 是独立常驻进程，只有一条批量长轮询请求。每次请求最多等待 5 秒，使本机表的变化很快生效。Python 任务在子进程中执行，主进程仍可请求任务；默认全机最多 4 个并发任务、每个 Widget 版本最多 1 个。停止 Worker 时不再领取新任务，并等待在运行的任务结束。

Worker 将带时间戳的运行、任务和错误日志同时输出到终端与本机 `worker.log`。`glance worker logs` 显示最近 100 行；`--lines` 指定行数，`--follow` 持续跟踪。日志轮换限制单文件 5 MB 并保留 3 份旧文件。

## 批量请求与执行协议

- `POST /api/v2/widget-tasks/pull-batch` 携带已授权的 `{widgetId, version}` 列表。服务端核对所有权，在最多 25 秒内原子领取一个匹配任务；无任务返回 `task: null`。Worker 收到响应后重读本机表。
- 管理员测试任务及生产任务都绑定明确的 Widget 版本。Worker 按 Widget ID 和版本查找本机代码目录，找不到时报告配置错误，不使用其他版本的代码。
- Worker 下载输入到任务临时目录，使用对应版本登记的 Python 解释器调用 `main.py` 的 `main(task: dict) -> dict`。`task` 包含任务 ID、Command ID、参数和本地输入路径。返回 `outputs` 数组：文本为 `{"type":"text","text":"..."}`，图片、视频或音频为 `{"type":"image|video|audio","path":"本地文件路径"}`，一次任务可以返回多个输出。
- Worker 约每 60 秒发送心跳，续期 120 秒租约；完成后上传文件并回传结果或错误。租约过期的任务可以重新领取，所以开发者代码应允许重试。
- 执行成功只表示测试任务完成；管理员仍须检查结果并手动批准。CLI、审核后台和 Glance 客户端最终都应支持文本、图片、视频及音频结果。

## 账号、发布及安全

开发者通过 Google 浏览器登录及一次性授权码获得可撤销会话。开发者 API 验证会话及 Widget 所有权。提交时保留 `init` 生成的 Widget UUID 和稳定的 Command ID，待审核版本不得替换线上版本。管理员批准后由 Glance 签署最终 Manifest，控制灰度和正式发布。`unpublish` 下架并阻止新任务；`delete` 归档并保留版本与审核记录。

首轮联调允许本机 `mock-token` 文件或 `GLANCE_MOCK_TOKEN` 提供临时 token。`glance login` 将其保存成模拟会话，Service 通过独立 Secret `DEVELOPER_TEST_TOKEN` 将其映射到固定模拟开发者。此 token 不授予管理后台权限；正式登录接入后删除本机文件和线上 Secret。

## 验证

检查 UUID 文件夹与本机表创建、运行中更新、批量领取、版本匹配、Python 异常与超时、租约重试、四种输出、所有权限制及人工审核门槛。Glance 的界面测试由用户执行，不由代理启动应用或操作界面。
