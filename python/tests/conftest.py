import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest

from backend.models import CatalogItem

FAKE_SPECS = {
    "CPU": "Fake CPU",
    "Cores": "8C / 16T",
    "GPU": "Fake GPU",
    "RAM": "32 GB @ 3600 MHz",
    "OS": "Windows 11 (build 26200)",
    "Disks": "Fake SSD (1000 GB)",
    "NIC": "Fake NIC (1 Gbps)",
}

FAKE_SYSTEM_SCAN = {
    "ScannedAt": "2026-07-20T00:00:00",
    "Specs": FAKE_SPECS,
    "InstalledSoftware": [{"Name": "Fake App", "Version": "1.0"}],
    "RunningProcesses": [{"Name": "explorer", "Pid": 123}],
}


@pytest.fixture
def fake_system_scan() -> dict:
    return dict(FAKE_SYSTEM_SCAN)


@pytest.fixture
def fake_catalog() -> list[CatalogItem]:
    return [
        CatalogItem(
            Id="A.1",
            Level=1,
            Module="Fake Module",
            Name="Item A",
            Desc="desc a",
            Target="target a",
            DefaultChecked=True,
            ScriptPath="C:\\fake\\A.ps1",
            ScriptArgs={},
        ),
        CatalogItem(
            Id="A.2",
            Level=1,
            Module="Fake Module",
            Name="Item B",
            Desc="desc b",
            Target="target b",
            DefaultChecked=True,
            ScriptPath="C:\\fake\\B.ps1",
            ScriptArgs={},
        ),
    ]
