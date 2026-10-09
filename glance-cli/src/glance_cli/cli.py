"""The installed `glance` command."""

import argparse
from contextlib import closing
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import sys
import uuid

from . import __version__
from .api import APIError, request
from .auth import login, logout
from .registry import cache_manifest, connect, read_token, rows, update, upsert
from .runtime import execute, resolve_python
from .worker import run_worker
from .worker_logs import show_worker_logs


def locate_manifest(path: str | None) -> Path:
    manifest = Path(path or "widget.json").resolve()
    if not manifest.is_file():
        raise ValueError(f"找不到 Manifest：{manifest}")
    return manifest


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("Manifest 必须是 JSON 对象")
    return manifest


def validate(manifest: dict, code_path: Path | None = None) -> None:
    required = ("id", "version", "name", "summary", "author", "commands")
    for field in required:
        if not manifest.get(field):
            raise ValueError(f"Manifest 缺少 {field}")
    uuid.UUID(str(manifest["id"]))
    if not isinstance(manifest["commands"], list) or not manifest["commands"]:
        raise ValueError("commands 必须是非空数组")
    if not all(isinstance(command, dict) for command in manifest["commands"]):
        raise ValueError("commands 的每项必须是对象")
    ids = [command.get("id") for command in manifest["commands"]]
    if not all(isinstance(command_id, str) and command_id for command_id in ids) or len(set(ids)) != len(ids):
        raise ValueError("Command ID 不能重复或为空")
    execution = manifest.get("execution")
    privacy = manifest.get("privacy")
    if not isinstance(execution, dict) or execution.get("mode") != "cloud":
        raise ValueError("execution.mode 必须为 cloud")
    if not manifest.get("minimumGlanceVersion") or not isinstance(privacy, dict) or not privacy.get("notice"):
        raise ValueError("minimumGlanceVersion 和 privacy.notice 必填")
    for command in manifest["commands"]:
        for field in ("name", "description", "inputTypes", "inputMimeTypes", "outputs", "taskType"):
            if not command.get(field):
                raise ValueError(f"Command {command.get('id')} 缺少 {field}")
        if not isinstance(command.get("requiresUpload"), bool) or not isinstance(command.get("parameterSchema"), dict):
            raise ValueError(f"Command {command.get('id')} 的 requiresUpload 和 parameterSchema 无效")
        if any(kind not in ("text", "image", "video", "audio") for kind in command["outputs"]):
            raise ValueError(f"Command {command.get('id')} 的输出类型无效")
        if "showResultURL" in command and not isinstance(command["showResultURL"], bool):
            raise ValueError(f"Command {command.get('id')} 的 showResultURL 必须是布尔值")
        if command.get("showResultURL") and "image" not in command["outputs"]:
            raise ValueError(f"Command {command.get('id')} 只有图片输出才能显示结果 URL")
    if code_path and not (code_path / "main.py").is_file():
        raise ValueError(f"找不到 {code_path / 'main.py'}")


def registered_python(db, widget_id: str, version: str) -> str | None:
    return next((row["python_path"] for row in rows(db)
                 if row["widget_id"] == widget_id and row["version"] == version), None)


def manifest_for_code(manifest_arg: str | None, code_arg: str | None = None,
                      version: str | None = None) -> tuple[Path, Path]:
    """Use local metadata when present, otherwise the registered server cache."""
    if manifest_arg:
        path = locate_manifest(manifest_arg)
        return path, Path(code_arg or path.parent).resolve()
    code = Path(code_arg or ".").resolve()
    local = code / "widget.json"
    if local.is_file():
        if version is None or load_manifest(local).get("version") == version:
            return local, code
    with closing(connect()) as db:
        matches = [row for row in rows(db) if row["code_path"] == str(code)
                   and (version is None or row["version"] == version)]
    if len(matches) == 1:
        return locate_manifest(matches[0]["manifest_path"]), code
    if len(matches) > 1:
        raise ValueError("该目录登记了多个版本；请指定 --version 或 --manifest")
    raise ValueError(f"找不到该目录的 Manifest 缓存：{code}；请先运行 glance widget add")


def command_init(args: argparse.Namespace) -> None:
    python_path = resolve_python(args.python)
    widget_id = str(uuid.uuid4())
    directory = Path(args.directory).resolve() / widget_id
    directory.mkdir(parents=True, exist_ok=False)
    manifest = {
        "schemaVersion": 1, "id": widget_id, "version": "0.1.0",
        "name": "My Widget", "summary": "Describe your widget.",
        "author": "Your name", "official": False,
        "execution": {"mode": "cloud"},
        "commands": [{"id": "run", "name": "Run", "description": "Process an input.",
                      "inputTypes": ["image"], "inputMimeTypes": ["image/png", "image/jpeg"],
                      "outputs": ["text"], "taskType": f"widget.{widget_id}.run",
                      "requiresUpload": True, "parameterSchema": {}}],
        "privacy": {"uploadsMedia": True,
                    "notice": "The selected media is uploaded to Glance for processing."},
        "minimumGlanceVersion": "2.0.0"
    }
    manifest_path = directory / "widget.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (directory / "main.py").write_text(
        'def main(task: dict) -> dict:\n'
        '    """Return text or paths to image, video, or audio files."""\n'
        '    return {"outputs": [{"type": "text", "text": "Hello from Glance"}]}\n',
        encoding="utf-8")
    with closing(connect()) as db:
        upsert(db, widget_id=widget_id, version="0.1.0",
               manifest_path=str(manifest_path), code_path=str(directory),
               enabled=False, server_status="local",
               python_path=str(python_path))
    print(f"已创建 {directory}\nWidget ID: {widget_id}")


def command_add(args: argparse.Namespace) -> None:
    code = Path(args.widget_path).expanduser().resolve()
    if code.exists() and not code.is_dir():
        raise ValueError(f"Widget 路径必须是目录：{code}")
    local_manifest = code / "widget.json"
    if local_manifest.is_file():
        manifest_path = local_manifest
        manifest = load_manifest(manifest_path)
    else:
        try:
            requested_id = str(uuid.UUID(code.name))
        except ValueError as error:
            raise ValueError(f"找不到 Manifest：{local_manifest}") from error
        try:
            manifest = request("GET", f"/api/v2/widgets/{requested_id}", authenticated=False)
        except APIError:
            with closing(connect()) as db:
                matches = [row for row in rows(db) if row["widget_id"] == requested_id
                           and row["code_path"] == str(code)
                           and Path(row["manifest_path"]).is_file()]
            if len(matches) != 1:
                raise
            manifest_path = Path(matches[0]["manifest_path"])
            manifest = load_manifest(manifest_path)
        else:
            if manifest.get("id") != requested_id:
                raise APIError("服务端返回的 Widget ID 与目录名称不一致")
            validate(manifest)
            code.mkdir(parents=True, exist_ok=True)
            manifest_path = cache_manifest(manifest)

    has_code = (code / "main.py").is_file()
    validate(manifest, code if has_code else None)
    if not has_code:
        with closing(connect()) as db:
            old = next((row for row in rows(db) if row["widget_id"] == manifest["id"] and
                        row["version"] == manifest["version"]), None)
            upsert(db, widget_id=manifest["id"], version=manifest["version"],
                   manifest_path=str(manifest_path), code_path=str(code),
                   python_path=str(resolve_python(args.python or (old or {}).get("python_path"))),
                   enabled=False, server_status="local",
                   submission_id=(old or {}).get("submission_id"))
        print(f"已登记 {manifest['id']} v{manifest['version']} → {code}")
        print("目录缺少 main.py；请从分享者获取代码并放入此目录，然后再次运行 add。Worker 暂不会领取该 Widget 的任务。")
        return

    remote = None
    denied = False
    if read_token():
        try:
            detail = request("GET", f"/api/v2/developer/widgets/{manifest['id']}")
            version = next((item for item in detail.get("versions", [])
                            if item["version"] == manifest["version"]), None)
            if version:
                remote = (detail["status"] if detail["status"] in ("suspended", "archived")
                          else version["status"])
            else:
                denied = True
        except APIError as error:
            denied = error.status in (401, 403, 404)

    with closing(connect()) as db:
        old = next((row for row in rows(db) if row["widget_id"] == manifest["id"] and
                    row["version"] == manifest["version"]), None)
        python_path = str(resolve_python(args.python or (old or {}).get("python_path")))
        status = "local" if denied else remote or (old or {}).get("server_status", "local")
        if denied:
            enabled = False
        elif remote is None:
            enabled = bool((old or {}).get("enabled", False))
        else:
            enabled = status in {"manual_review", "test_passed", "gray_release", "published"}
        upsert(db, widget_id=manifest["id"], version=manifest["version"],
               manifest_path=str(manifest_path), code_path=str(code),
               python_path=python_path, enabled=enabled, server_status=status,
               submission_id=(old or {}).get("submission_id"))
    print(f"已挂载 {manifest['id']} v{manifest['version']} → {code}（{status}）")
    if denied:
        print("当前账号无权领取该版本任务；已挂载供本地 test 使用。")
    elif remote is None and status == "local":
        print("服务端任务权限尚未确认；可本地 test。配置测试 token 或登录后再次 add 可同步已授权版本。")


def command_publish(args: argparse.Namespace) -> None:
    path = locate_manifest(args.manifest)
    manifest = load_manifest(path)
    code = Path(args.code or path.parent).resolve()
    validate(manifest, code)
    with closing(connect()) as db:
        python_path = str(resolve_python(args.python or registered_python(
            db, manifest["id"], manifest["version"])))
    result = request("POST", "/api/v2/widget-submissions", {"manifest": manifest})
    if result.get("widgetId") != manifest["id"]:
        raise APIError("服务端返回的 Widget ID 与本地 Manifest 不一致")
    with closing(connect()) as db:
        upsert(db, widget_id=manifest["id"], version=manifest["version"],
               manifest_path=str(path), code_path=str(code), enabled=True,
               server_status=result["status"], submission_id=result.get("submissionId"),
               python_path=python_path)
    print(f"已提交审核：{manifest['id']} v{manifest['version']}，状态 {result['status']}")


def command_bind(args: argparse.Namespace) -> None:
    path = locate_manifest(args.manifest)
    manifest = load_manifest(path)
    code = Path(args.code).resolve(strict=True)
    validate(manifest, code)
    with closing(connect()) as db:
        old = next((row for row in rows(db) if row["widget_id"] == manifest["id"] and
                    row["version"] == args.version), None)
        if old is None:
            raise ValueError("该版本尚未登记；请先 publish")
        fields = {"code_path": str(code)}
        if args.python:
            fields["python_path"] = str(resolve_python(args.python))
        update(db, manifest["id"], args.version, **fields)
    print(f"已绑定 {manifest['id']} v{args.version} → {code}")


def command_test(args: argparse.Namespace) -> None:
    path, code = manifest_for_code(args.manifest, args.code, args.version)
    manifest = load_manifest(path)
    validate(manifest, code)
    input_path = Path(args.input).resolve(strict=True) if args.input else None
    params = json.loads(args.parameters)
    task = {"taskId": "local-test", "widgetId": manifest["id"],
            "version": manifest["version"], "commandId": args.command or manifest["commands"][0]["id"],
            "parameters": params, "input": {"path": str(input_path)} if input_path else {}}
    with closing(connect()) as db:
        python_path = resolve_python(args.python or registered_python(
            db, manifest["id"], manifest["version"]))
    with execute(code, task, download_input=False, python_path=python_path) as results:
        outputs = []
        destination = code / ".glance-test-output"
        for output in results:
            if output["type"] == "text":
                outputs.append(output)
            else:
                destination.mkdir(exist_ok=True)
                source = Path(output["path"])
                target = destination / f"{uuid.uuid4().hex}-{source.name}"
                shutil.copy2(source, target)
                outputs.append({"type": output["type"], "path": str(target)})
    print(json.dumps(outputs, indent=2, ensure_ascii=False))


def command_status(args: argparse.Namespace) -> None:
    result = request("GET", f"/api/v2/developer/widgets/{args.widget_id}")
    with closing(connect()) as db:
        for row in rows(db):
            if row["widget_id"] == args.widget_id:
                version = next((v for v in result["versions"] if v["version"] == row["version"]), None)
                if version:
                    state = result["status"] if result["status"] in ("suspended", "archived") else version["status"]
                    update(db, args.widget_id, row["version"], server_status=state)
    print(json.dumps(result, indent=2, ensure_ascii=False))


def command_transition(args: argparse.Namespace, action: str) -> None:
    result = request("POST", f"/api/v2/developer/widgets/{args.widget_id}/{action}", {})
    with closing(connect()) as db:
        for row in rows(db):
            if row["widget_id"] == args.widget_id:
                update(db, args.widget_id, row["version"], enabled=0,
                       server_status=result["status"])
    print(f"{args.widget_id}: {result['status']}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="glance")
    root.add_argument("--version", action="version", version=__version__)
    commands = root.add_subparsers(dest="command", required=True)
    for name in ("login", "logout", "whoami"):
        commands.add_parser(name)
    worker = commands.add_parser("worker")
    worker_actions = worker.add_subparsers(dest="worker_action")
    logs = worker_actions.add_parser("logs", help="查看本机 Worker 日志")
    logs.add_argument("--lines", "-n", type=int, default=100, help="显示最近几行（默认 100）")
    logs.add_argument("--follow", "-f", action="store_true", help="持续显示新日志")
    widget = commands.add_parser("widget")
    actions = widget.add_subparsers(dest="action", required=True)
    init = actions.add_parser("init")
    init.add_argument("--directory", default=".")
    init.add_argument("--python", help="Widget 使用的 Python 解释器路径")
    add = actions.add_parser("add")
    add.add_argument("widget_path", help="Widget 目录或 UUID；widget.json 可选")
    add.add_argument("--python", help="Widget 使用的 Python 解释器路径")
    for name in ("validate", "test", "publish", "bind"):
        action = actions.add_parser(name)
        action.add_argument("--manifest")
        if name in ("test", "publish", "bind"):
            action.add_argument("--code", required=name == "bind")
            action.add_argument("--python", help="Widget 使用的 Python 解释器路径")
        if name == "bind":
            action.add_argument("--version", required=True)
        if name == "test":
            action.add_argument("--input")
            action.add_argument("--command")
            action.add_argument("--version")
            action.add_argument("--parameters", default="{}")
    listing = actions.add_parser("list")
    listing.add_argument("--json", action="store_true")
    for name in ("status", "unpublish", "delete"):
        action = actions.add_parser(name)
        action.add_argument("widget_id")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "login":
            session = login()
            print(f"已登录：{session['email']}")
        elif args.command == "logout":
            logout()
            print("已退出登录")
        elif args.command == "whoami":
            print(json.dumps(request("GET", "/api/v2/developer/auth/me"), ensure_ascii=False))
        elif args.command == "worker":
            if args.worker_action == "logs":
                show_worker_logs(lines=args.lines, follow=args.follow)
            else:
                run_worker()
        elif args.action == "init":
            command_init(args)
        elif args.action == "add":
            command_add(args)
        elif args.action == "list":
            with closing(connect()) as db:
                data = rows(db)
                for row in data:
                    last = row["last_request_at"]
                    active = bool(row["enabled"] and last and
                                  (datetime.now(timezone.utc) - datetime.fromisoformat(last)).total_seconds() < 15)
                    row["requesting"] = active
                if args.json:
                    print(json.dumps(data, indent=2, ensure_ascii=False))
                elif not data:
                    print("本机尚未挂载 Widget。运行 glance widget add <Widget 目录或 UUID> 添加；"
                          "也可运行 glance widget init 创建新 Widget。")
                else:
                    for row in data:
                        print(f"{row['widget_id']} v{row['version']} {row['server_status']} "
                              f"requesting={row['requesting']} enabled={bool(row['enabled'])} "
                              f"code={row['code_path']} python={row['python_path']}")
        elif args.action == "validate":
            path, code = manifest_for_code(args.manifest)
            validate(load_manifest(path), code)
            print("Manifest 与 main.py 检查通过")
        elif args.action == "test":
            command_test(args)
        elif args.action == "publish":
            command_publish(args)
        elif args.action == "bind":
            command_bind(args)
        elif args.action == "status":
            command_status(args)
        elif args.action == "unpublish":
            command_transition(args, "unpublish")
        elif args.action == "delete":
            command_transition(args, "archive")
        return 0
    except (APIError, ValueError, OSError, KeyError, RuntimeError) as error:
        print(f"错误：{error}", file=sys.stderr)
        return 1
