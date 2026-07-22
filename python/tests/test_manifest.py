from backend import manifest


def test_load_static_items_fps_matches_real_repo_catalog():
    items = manifest.load_static_items("fps")
    assert len(items) == 54
    assert all(item.ScriptPath for item in items)
    # Every manifest entry must resolve to a real script on disk — the same
    # integrity check done manually when the manifests were first built.
    from pathlib import Path

    for item in items:
        assert Path(item.ScriptPath).is_file(), f"{item.Id} -> {item.ScriptPath} missing"


def test_load_static_items_skips_comment_entries():
    items = manifest.load_static_items("startup")
    assert all(item.Id for item in items)
    assert len(items) == 7


def test_build_dynamic_startup_items_maps_kind_to_script_and_args():
    discovered = [
        {
            "Id": "R.1",
            "Level": 1,
            "Module": "Registry Run Entries",
            "Kind": "RunKeyEntry",
            "Name": "Foo",
            "Desc": "d",
            "Target": "removed",
            "DefaultChecked": True,
            "RegPath": "HKCU:\\Run",
            "ValueName": "Foo",
        },
        {
            "Id": "R.0",
            "Level": 1,
            "Module": "Registry Run Entries",
            "Kind": None,
            "Name": "nothing found",
            "Desc": "d",
            "Target": "nothing",
            "DefaultChecked": False,
        },
    ]
    items = manifest.build_dynamic_startup_items(discovered)
    assert items[0].ScriptPath.endswith("RunKeyEntry.ps1")
    assert items[0].ScriptArgs == {"RegPath": "HKCU:\\Run", "ValueName": "Foo"}
    assert items[1].ScriptPath is None
    assert items[1].ScriptArgs == {}


def test_load_catalog_startup_merges_static_and_dynamic(monkeypatch):
    monkeypatch.setattr(
        manifest.ps_bridge,
        "run_enumerate_startup",
        lambda: [
            {
                "Id": "F.1",
                "Level": 1,
                "Module": "Startup Folder Shortcuts",
                "Kind": "StartupFolderShortcut",
                "Name": "Bar",
                "Desc": "d",
                "Target": "removed",
                "DefaultChecked": True,
                "FilePath": "C:\\Users\\x\\Bar.lnk",
            }
        ],
    )
    items = manifest.load_catalog("startup")
    ids = {i.Id for i in items}
    assert "F.1" in ids  # dynamic
    assert any(i.Module == "Windows Extras" for i in items)  # static
