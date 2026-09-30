# Glance CLI

供 Widget 开发者安装的 Python 包。需要 Python 3.11 或更新版本。

在仓库根目录可直接运行 `./glance-cli-run.sh`。脚本每次都会在 `.venv` 中重新安装当前源码，然后退出；不会自动启动 Worker。需要运行命令时可传入参数，例如 `./glance-cli-run.sh widget list`；脚本保留当前工作目录，因此也能从 `widgets/` 目录运行 `../glance-cli-run.sh widget init`。需要 Worker 时，开发者自行运行 `.venv/bin/glance worker`。

在仓库根目录创建虚拟环境后安装当前源码：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e ./glance-cli
glance widget init
cd <生成的 UUID 文件夹>
glance widget test
glance login
glance widget publish --code .
glance worker
```

Homebrew 管理的 Python 不接受全局 `pip install`，因此请在虚拟环境中安装；无需使用 `--break-system-packages`。上面的 `.venv` 属于 CLI，也可以用来安装 Widget 的 Python 依赖。

如果某个 Widget 需要独立依赖，可在它的 UUID 目录创建自己的虚拟环境，并在测试、发布时指定 Python 路径：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install <Widget 所需依赖>
glance widget test --python .venv/bin/python
glance widget publish --code . --python .venv/bin/python
```

若 `main.py` 导入 `glance_cli` 提供的辅助函数，还需在该 Widget 虚拟环境中安装本包。发布后的版本可用 `glance widget bind --version <版本> --code <目录> --python <Python 路径>` 更新解释器。Worker 会使用本机表里该版本记录的解释器；更换后无须重启 Worker。

`glance widget init` 会在当前目录生成以 Widget UUID 命名的文件夹，内含 `widget.json` 和 `main.py`。开发者自行管理自己的 Python 代码和依赖。修改版本号后，用 `glance widget publish --code <该版本代码目录>` 提交审核；本机 SQLite 表记录版本与代码目录、Python 解释器的对应关系。`glance widget bind --version <版本> --code <目录>` 可更新路径。

已有 Widget 目录（包括朋友分享的目录）可以直接挂载，不复制代码：

```bash
glance widget add /path/to/widget
glance widget add /path/to/widget --python /path/to/widget/.venv/bin/python
glance widget add <已发布的 Widget UUID>
```

`widget.json` 是 Widget 目录中的可选文件：`init` 创建的新目录会包含它，旧目录可以没有。`add` 和 `test` 优先读取本地文件；没有时，`add` 根据 UUID 目录名从 Service 获取已公开发布的 Manifest，并缓存在 CLI 配置目录。已登记且有缓存的目录在 Service 暂时不可用时也能再次 `add`。首次添加时若本地没有文件、Service 没有公开 Manifest，也没有已有缓存，CLI 无法确定版本与命令，此时需要提供 Manifest。Service 不保存开发者的 `main.py`，所以还需从分享者获取代码。目录缺少 `main.py` 时可以登记，但 Worker 不会领取它的任务。代码放入目录后，可再次 `add`，再用 `glance widget test` 本地测试；`test` 会读取本地 Manifest 或已登记的缓存。重复 `add` 同一 Widget 版本会更新本机代码路径；`--python` 可切换该版本的解释器。登录后，CLI 会查询当前账号是否拥有该版本的服务端任务权限。未获授权的分享目录仍可本地测试，但不会参与 Worker 领取任务。当前 Service 仅允许 Widget 所有者账号领取该版本任务；跨账号协作领取需要后续增加授权机制。

开发者可以直接返回标准 Python 字典，也可以使用库里的类型和辅助函数：

```python
from glance_cli import WidgetTask, result, text, image

def main(task: WidgetTask) -> dict:
    # 自行处理 task["input"]["path"]，并生成本地输出文件。
    return result(text("处理完成"), image("output.png"))
```

一台机器运行一个 `glance worker` 即可。它每次向 GlanceService 批量请求任务前都会重读本机表，并在对应版本目录里执行 `main.py` 的 `main(task)`。函数返回 `{"outputs":[{"type":"text","text":"..."}]}`；图片、视频或音频输出使用 `{"type":"image|video|audio","path":"输出文件路径"}`。单个文件最大 50 MB。

Worker 启动后同时把日志写到终端和 `~/.config/glance/worker.log`。另开终端可以查看最近日志，或持续跟踪：

```bash
glance worker logs
glance worker logs --lines 50
glance worker logs --follow
```

日志会显示每次拉取、暂无任务、执行和完成。临时网络错误会注明下次重试时间；Worker 会继续运行。

日志文件最多 5 MB，保留 3 份轮换文件。`glance worker logs` 只读取日志，不会启动 Worker。

CLI 数据放在 `~/.config/glance/`，可通过 `GLANCE_CLI_HOME` 调整。开发或本地联调可通过 `GLANCE_API_URL` 指向其他 GlanceService。这个包尚未上传到 PyPI。

联调期间，可将临时开发者 token 放在 `~/.config/glance/mock-token`（权限 `0600`），或通过 `GLANCE_MOCK_TOKEN` 环境变量提供。此时 `glance login` 会保存一个本地模拟会话，跳过浏览器登录；`glance whoami` 等后续命令仍向 Service 发送该 token。移除 token 文件或环境变量后，`glance login` 恢复正常登录流程。
