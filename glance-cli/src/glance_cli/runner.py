"""Run untrusted developer code in a separate Python process."""

import importlib.util
import json
from pathlib import Path
import sys
import traceback


def main() -> int:
    code_path, task_path, result_path = map(Path, sys.argv[1:4])
    try:
        module_path = code_path / "main.py"
        spec = importlib.util.spec_from_file_location("glance_widget_main", module_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("无法加载 main.py")
        module = importlib.util.module_from_spec(spec)
        sys.path.insert(0, str(code_path))
        spec.loader.exec_module(module)
        function = getattr(module, "main", None)
        if not callable(function):
            raise RuntimeError("main.py 必须导出 main(task) 函数")
        task = json.loads(task_path.read_text(encoding="utf-8"))
        result = function(task)
        if not isinstance(result, dict) or not isinstance(result.get("outputs"), list):
            raise RuntimeError("main(task) 必须返回含 outputs 数组的 dict")
        result_path.write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8")
        return 0
    except Exception:
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
