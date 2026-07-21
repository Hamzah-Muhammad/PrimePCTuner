"""Load each tool's catalog — static entries from manifest.json, plus
Startup Optimizer's live-discovered entries from Enumerate.ps1 (§3, §7).
Mirrors PS's Get-PrimeManifestItems / Start-StartupOptimization.ps1 wiring.
"""

import json

from . import paths, ps_bridge
from .models import CatalogItem

_KIND_TO_SCRIPT = {
    "RunKeyEntry": "RunKeyEntry.ps1",
    "StartupFolderShortcut": "StartupFolderShortcut.ps1",
    "ScheduledTask": "ScheduledTask.ps1",
}
_KIND_TO_ARG_KEYS = {
    "RunKeyEntry": ("RegPath", "ValueName"),
    "StartupFolderShortcut": ("FilePath",),
    "ScheduledTask": ("TaskPath", "TaskName"),
}


def load_static_items(tool_key: str) -> list[CatalogItem]:
    manifest = paths.manifest_path(tool_key)
    entries = json.loads(manifest.read_text(encoding="utf-8"))
    items = []
    for entry in entries:
        if "Id" not in entry:  # skip _comment entries
            continue
        items.append(
            CatalogItem(
                Id=entry["Id"],
                Level=entry["Level"],
                Module=entry["Module"],
                Name=entry["Name"],
                Desc=entry["Desc"],
                Target=entry["Target"],
                DefaultChecked=bool(entry["DefaultChecked"]),
                ScriptPath=str(paths.REPO_ROOT / entry["Script"]),
                ScriptArgs={},
            )
        )
    return items


def build_dynamic_startup_items(discovered: list[dict]) -> list[CatalogItem]:
    items = []
    for d in discovered:
        kind = d.get("Kind")
        script_path = None
        script_args: dict[str, str] = {}
        if kind:
            script_path = str(paths.CHANGES_DIR / "PC Startup" / _KIND_TO_SCRIPT[kind])
            script_args = {k: str(d[k]) for k in _KIND_TO_ARG_KEYS[kind]}
        items.append(
            CatalogItem(
                Id=d["Id"],
                Level=d["Level"],
                Module=d["Module"],
                Name=d["Name"],
                Desc=d["Desc"],
                Target=d["Target"],
                DefaultChecked=bool(d["DefaultChecked"]),
                ScriptPath=script_path,
                ScriptArgs=script_args,
            )
        )
    return items


def load_catalog(tool_key: str) -> list[CatalogItem]:
    """FPS: manifest.json only (52 static items, no subprocess). Startup:
    manifest.json's static Windows Extras + one live Enumerate.ps1 call for
    the PC-specific Run keys/shortcuts/logon tasks — never N calls for N items.
    """
    static_items = load_static_items(tool_key)
    if tool_key != "startup":
        return static_items
    discovered = ps_bridge.run_enumerate_startup()
    return static_items + build_dynamic_startup_items(discovered)
