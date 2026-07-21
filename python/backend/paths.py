"""Repo-relative path resolution.

Dev-mode only for now — resolves relative to this file's location on disk.
The PyInstaller frozen-mode branch (extracted-sibling-folder resolution,
mirroring PS's $PSScriptRoot fallback) lands with app.py/packaging, out of
scope for the backend-only cut.
"""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SHARED_DIR = REPO_ROOT / "shared"
CHANGES_DIR = REPO_ROOT / "changes"


def tool_dir(tool_key: str) -> Path:
    return REPO_ROOT / {"fps": "FPSOptimization", "startup": "StartupOptimization"}[tool_key]


def manifest_path(tool_key: str) -> Path:
    return tool_dir(tool_key) / "manifest.json"


def logs_dir(tool_key: str) -> Path:
    return tool_dir(tool_key) / "logs"
