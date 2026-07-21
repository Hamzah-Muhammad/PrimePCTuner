"""Repo-relative path resolution.

Dev mode resolves relative to this file's location on disk. Frozen mode
(PyInstaller onefile, §8) resolves to the exe's own folder instead — the
`.ps1` engine folders (shared/, changes/, FPSOptimization/, StartupOptimization/)
ship as real sibling files next to the exe, not embedded in the bundle,
since `subprocess` needs actual paths on disk to hand to pwsh/powershell.
Mirrors PS's `$PSScriptRoot` fallback.
"""

import sys
from pathlib import Path

if getattr(sys, "frozen", False):
    REPO_ROOT = Path(sys.executable).resolve().parent
else:
    REPO_ROOT = Path(__file__).resolve().parents[2]
SHARED_DIR = REPO_ROOT / "shared"
CHANGES_DIR = REPO_ROOT / "changes"


def tool_dir(tool_key: str) -> Path:
    return REPO_ROOT / {"fps": "FPSOptimization", "startup": "StartupOptimization"}[tool_key]


def manifest_path(tool_key: str) -> Path:
    return tool_dir(tool_key) / "manifest.json"


def logs_dir(tool_key: str) -> Path:
    return tool_dir(tool_key) / "logs"
