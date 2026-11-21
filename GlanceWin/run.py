#!/usr/bin/env python3
"""Stop the running Glance, rebuild it, and launch the new build.

Usage (from anywhere):
    python GlanceWin/run.py              # Debug build, then launch
    python GlanceWin/run.py --test       # also run unit tests (failures are reported, not blocking)
    python GlanceWin/run.py --release    # Release build
    python GlanceWin/run.py --no-launch  # build only
    python GlanceWin/run.py --clean      # delete bin/obj first

Everything printed is also written to GlanceWin/run.log.
Requires the .NET 10 SDK on PATH.
"""

from __future__ import annotations

import argparse
import locale
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP_PROJECT = ROOT / "src" / "Glance.App" / "Glance.App.csproj"
SOLUTION = ROOT / "Glance.slnx"
EXE_NAME = "Glance.exe"
TFM = "net10.0-windows10.0.19041.0"
RID = "win-x64"
APP_LOG = Path(os.environ.get("APPDATA", "")) / "Glance" / "app.log"
RUN_LOG = ROOT / "run.log"
CONSOLE_ENCODING = locale.getpreferredencoding(False) or "utf-8"

_log_handle = None


def out(message: str = "") -> None:
    print(message, flush=True)
    if _log_handle:
        _log_handle.write(message + "\n")
        _log_handle.flush()


def step(message: str) -> None:
    out(f"\n==> {message}")


def fail(message: str, code: int = 1) -> None:
    out(f"\n[run.py] ERROR: {message}")
    out(f"[run.py] Full output: {RUN_LOG}")
    sys.exit(code)


def run(cmd: list[str], check: bool = True) -> int:
    """Runs a command, streaming its output to the console and run.log."""
    out("$ " + " ".join(cmd))
    process = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert process.stdout is not None
    for raw in process.stdout:
        # dotnet writes UTF-8 when redirected; fall back to the console code page (e.g. GBK).
        try:
            line = raw.decode("utf-8")
        except UnicodeDecodeError:
            line = raw.decode(CONSOLE_ENCODING, errors="replace")
        out(line.rstrip())
    code = process.wait()
    if check and code != 0:
        fail(f"command failed with exit code {code}", code)
    return code


def glance_pids() -> list[str]:
    result = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {EXE_NAME}", "/FO", "CSV", "/NH"],
                            capture_output=True)
    text = result.stdout.decode(CONSOLE_ENCODING, errors="replace")
    return re.findall(rf'^"{re.escape(EXE_NAME)}","(\d+)"', text, flags=re.MULTILINE | re.IGNORECASE)


def check_environment() -> None:
    if os.name != "nt":
        fail("run.py must be run with Windows Python (not MSYS/Cygwin python).")
    dotnet = shutil.which("dotnet")
    if not dotnet:
        fail("`dotnet` not found. Install the .NET 10 SDK: https://dotnet.microsoft.com/download/dotnet/10.0")
    sdks = subprocess.run([dotnet, "--list-sdks"], capture_output=True).stdout.decode(CONSOLE_ENCODING, errors="replace")
    out("SDKs:\n" + sdks.strip())
    versions = re.findall(r"^(\d+)\.\d+\.\S+", sdks, flags=re.MULTILINE)
    if not any(int(v) >= 10 for v in versions):
        fail("No .NET 10 SDK installed. Install: https://dotnet.microsoft.com/download/dotnet/10.0")
    if "10.0.100-preview" in sdks and not re.search(r"^10\.\d+\.\d+ ", sdks, flags=re.MULTILINE):
        out("[run.py] WARNING: only a preview .NET 10 SDK is installed. Install the GA SDK if the build misbehaves.")


def stop_running_glance() -> None:
    step(f"Stopping running {EXE_NAME}")
    pids = glance_pids()
    if not pids:
        out("Glance is not running.")
        return
    out(f"Found {EXE_NAME} PID(s): {', '.join(pids)}")
    result = subprocess.run(["taskkill", "/IM", EXE_NAME, "/F", "/T"], capture_output=True)
    out((result.stdout + result.stderr).decode(CONSOLE_ENCODING, errors="replace").strip())
    for _ in range(50):
        if not glance_pids():
            out("Stopped.")
            return
        time.sleep(0.1)
    fail(f"{EXE_NAME} is still running (PIDs {', '.join(glance_pids())}). "
         "Close it in Task Manager, then run again.")


def clean() -> None:
    step("Cleaning bin/ and obj/")
    for folder in list(ROOT.rglob("*")):
        if folder.is_dir() and folder.name in ("bin", "obj"):
            shutil.rmtree(folder, ignore_errors=True)


def run_tests(configuration: str) -> bool:
    step("Running unit tests")
    code = run(["dotnet", "test", str(SOLUTION), "-c", configuration, "--nologo"], check=False)
    if code != 0:
        out("\n[run.py] TESTS FAILED (see above). Continuing with build + launch.")
        return False
    return True


def build(configuration: str) -> Path:
    step(f"Building Glance ({configuration})")
    run(["dotnet", "build", str(APP_PROJECT), "-c", configuration, "--nologo", "-v", "minimal"])
    exe = ROOT / "src" / "Glance.App" / "bin" / configuration / TFM / RID / EXE_NAME
    if not exe.exists():
        matches = list((ROOT / "src" / "Glance.App" / "bin" / configuration).rglob(EXE_NAME))
        if not matches:
            fail(f"build succeeded but {EXE_NAME} was not found under bin/{configuration}")
        exe = matches[0]
    out(f"Built: {exe} ({datetime.fromtimestamp(exe.stat().st_mtime):%H:%M:%S})")
    return exe


def launch(exe: Path) -> None:
    step(f"Launching {exe.name}")
    log_size = APP_LOG.stat().st_size if APP_LOG.exists() else 0
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
    subprocess.Popen([str(exe)], cwd=exe.parent, creationflags=flags, close_fds=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    time.sleep(3)
    new_log = ""
    if APP_LOG.exists():
        with open(APP_LOG, "rb") as f:
            f.seek(log_size)
            new_log = f.read().decode("utf-8", errors="replace")
    if new_log.strip():
        out("--- app.log (this launch) ---")
        out(new_log.rstrip())
        out("-----------------------------")

    if not glance_pids():
        fail("Glance exited right after launch. See app.log output above.")
    if "[ERROR]" in new_log:
        out("\n[run.py] Glance is running but logged errors (above).")
    else:
        out("\nGlance is running. It has no main window: look for its icon in the notification")
        out("area (bottom-right of the taskbar; click ^ if hidden). Select a path/URL and press Alt+Q.")


def main() -> None:
    global _log_handle
    parser = argparse.ArgumentParser(description="Kill, rebuild and relaunch Glance for Windows.")
    parser.add_argument("--release", action="store_true", help="build Release instead of Debug")
    parser.add_argument("--test", action="store_true", help="run unit tests before building")
    parser.add_argument("--clean", action="store_true", help="delete bin/obj before building")
    parser.add_argument("--no-launch", action="store_true", help="build only, do not start Glance")
    args = parser.parse_args()

    _log_handle = open(RUN_LOG, "w", encoding="utf-8")
    out(f"run.py {datetime.now():%Y-%m-%d %H:%M:%S}  args={' '.join(sys.argv[1:]) or '(none)'}")

    check_environment()
    configuration = "Release" if args.release else "Debug"

    stop_running_glance()
    if args.clean:
        clean()
    tests_ok = run_tests(configuration) if args.test else True
    exe = build(configuration)
    if not args.no_launch:
        launch(exe)
    if not tests_ok:
        out("\n[run.py] Reminder: unit tests failed.")
    out(f"\nDone. Output saved to {RUN_LOG}")


if __name__ == "__main__":
    main()
