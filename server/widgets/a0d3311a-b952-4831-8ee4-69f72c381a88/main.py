"""Remove an image background locally with rembg for a Glance Widget task."""

import argparse
import json
import os
from pathlib import Path
import tempfile
import uuid

import onnxruntime as ort
from rembg import new_session, remove


def main(task: dict) -> dict:
    input_path = Path((task.get("input") or {}).get("path", ""))
    if not input_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    if input_path.stat().st_size > 50 * 1024 * 1024:
        raise ValueError("Input image exceeds 50 MB")

    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-rembg-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"result-{uuid.uuid4().hex}.png"

    available = ort.get_available_providers()
    providers = (["CUDAExecutionProvider", "CPUExecutionProvider"]
                 if "CUDAExecutionProvider" in available else ["CPUExecutionProvider"])
    session = new_session(os.environ.get("REMBG_MODEL", "u2net"), providers=providers)
    output = remove(input_path.read_bytes(), session=session)
    if not output:
        raise RuntimeError("rembg returned an empty image")
    if len(output) > 50 * 1024 * 1024:
        raise ValueError("rembg result exceeds 50 MB")
    output_path.write_bytes(output)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run this Widget on a local image")
    parser.add_argument("image", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(main({"input": {"path": str(arguments.image)}}), ensure_ascii=False))
