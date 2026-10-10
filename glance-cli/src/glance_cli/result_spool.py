"""Keep completed Widget outputs until GlanceService confirms delivery."""

from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import tempfile

from .registry import config_dir
from .runtime import validate_outputs


def _root() -> Path:
    root = config_dir() / "pending-results"
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name == "posix":
        root.chmod(0o700)
    return root


def _directory(task_id: str) -> Path:
    return _root() / sha256(task_id.encode("utf-8")).hexdigest()


def load(task_id: str) -> list[dict] | None:
    directory = _directory(task_id)
    if not directory.exists():
        return None
    entries = json.loads((directory / "outputs.json").read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError(f"Stored outputs for {task_id} are invalid")
    outputs = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError(f"Stored output for {task_id} is invalid")
        if "file" in entry:
            filename = entry["file"]
            if not isinstance(filename, str) or Path(filename).name != filename:
                raise ValueError(f"Stored output path for {task_id} is invalid")
            outputs.append({"type": entry.get("type"), "path": str(directory / filename)})
        else:
            outputs.append(entry)
    return validate_outputs({"outputs": outputs}, directory)


def save(task_id: str, outputs: list[dict]) -> list[dict]:
    existing = load(task_id)
    if existing is not None:
        return existing
    root = _root()
    directory = _directory(task_id)
    temporary = Path(tempfile.mkdtemp(prefix=".pending-", dir=root))
    try:
        entries = []
        for index, output in enumerate(outputs, start=1):
            if "path" in output:
                source = Path(output["path"])
                filename = f"{index}{source.suffix.lower()}"
                target = temporary / filename
                shutil.copyfile(source, target)
                if os.name == "posix":
                    target.chmod(0o600)
                entries.append({"type": output["type"], "file": filename})
            else:
                entries.append(output)
        metadata = temporary / "outputs.json"
        metadata.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
        if os.name == "posix":
            metadata.chmod(0o600)
        os.replace(temporary, directory)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    return load(task_id)


def discard(task_id: str) -> None:
    shutil.rmtree(_directory(task_id), ignore_errors=True)
