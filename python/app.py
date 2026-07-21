"""Desktop entry point: elevation check, FastAPI in a background thread,
pywebview window pointed at the built frontend (§3.5, §6).

Usage:  python app.py              (self-elevates via UAC)
        python app.py --self-test  (skip elevation + webview, verify wiring)
"""

from __future__ import annotations

import argparse
import ctypes
import socket
import sys
import threading
from pathlib import Path

import uvicorn

from backend.main import app as fastapi_app

REPO_ROOT = Path(__file__).resolve().parent
FRONTEND_DIST = REPO_ROOT / "frontend" / "dist"


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def relaunch_elevated() -> bool:
    """Mirrors PS's Invoke-PrimeBootstrap elevation step (§3.5). Returns True
    if a relaunch was fired (caller should exit immediately after)."""
    params = " ".join(f'"{a}"' for a in sys.argv)
    try:
        result = ctypes.windll.shell32.ShellExecuteW(
            None, "runas", sys.executable, f'"{__file__}" {params}', str(REPO_ROOT), 1
        )
        # ShellExecuteW returns a value > 32 on success.
        return result > 32
    except Exception:
        return False


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def mount_frontend() -> str | None:
    """Serves frontend/dist from the same FastAPI instance/origin the API
    lives on — zero CORS config, matches §8's packaging plan. Returns a
    warning message if the build is missing (never crashes: an API-only
    window is still more useful than no window)."""
    if not (FRONTEND_DIST / "index.html").is_file():
        return f"Frontend build not found at {FRONTEND_DIST} — run `npm run build` in frontend/ first."
    from fastapi.staticfiles import StaticFiles

    fastapi_app.mount("/", StaticFiles(directory=str(FRONTEND_DIST), html=True), name="frontend")
    return None


def run_server(port: int) -> None:
    uvicorn.run(fastapi_app, host="127.0.0.1", port=port, log_level="warning")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true", help="skip elevation + webview, verify wiring")
    args = parser.parse_args()

    if not args.self_test and not is_admin():
        if relaunch_elevated():
            sys.exit(0)
        print("Elevation declined — continuing unelevated; some checks may show REVIEW.", file=sys.stderr)

    warning = mount_frontend()
    if warning:
        print(f"WARNING: {warning}", file=sys.stderr)

    port = free_port()
    server_thread = threading.Thread(target=run_server, args=(port,), daemon=True)
    server_thread.start()

    if args.self_test:
        import time
        import urllib.request

        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=1)
                break
            except OSError:
                time.sleep(0.1)
        else:
            print("SELFTEST FAILED — server never came up", file=sys.stderr)
            sys.exit(1)

        frontend_ok = False
        if warning is None:
            body = urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=2).read()
            frontend_ok = b"PrimePCTuner" in body

        print(f"SELFTEST OK — server up on 127.0.0.1:{port}, frontend mounted: {warning is None}")
        if warning is None and not frontend_ok:
            print("SELFTEST FAILED — static mount served a response but it wasn't the app", file=sys.stderr)
            sys.exit(1)
        return

    import webview

    webview.create_window(
        "PrimePCTuner by @Humzeeny",
        f"http://127.0.0.1:{port}/",
        width=1180,
        height=840,
        min_size=(920, 600),
        background_color="#09090E",
    )
    webview.start()


if __name__ == "__main__":
    main()
