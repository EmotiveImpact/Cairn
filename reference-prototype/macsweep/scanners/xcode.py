from __future__ import annotations

from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner

XCODE_TARGETS = [
    ("DerivedData", "Library/Developer/Xcode/DerivedData", Severity.SAFE,
     "Build outputs Xcode rebuilds on demand"),
    ("iOS DeviceSupport", "Library/Developer/Xcode/iOS DeviceSupport", Severity.REVIEW,
     "Per-iOS-version symbols; only matters if debugging old devices"),
    ("watchOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport", Severity.REVIEW,
     "watchOS debug symbols"),
    ("tvOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport", Severity.REVIEW,
     "tvOS debug symbols"),
    ("Archives", "Library/Developer/Xcode/Archives", Severity.REVIEW,
     "Build archives — keep recent ones if you ship apps"),
    ("CoreSimulator Caches", "Library/Developer/CoreSimulator/Caches", Severity.SAFE,
     "Simulator caches"),
    ("CoreSimulator Devices", "Library/Developer/CoreSimulator/Devices", Severity.REVIEW,
     "Old simulator devices — recreated by Xcode"),
]


@register
class XcodeScanner(Scanner):
    name = "Xcode Junk"
    description = "Xcode caches, archives, simulator devices, and DeviceSupport. Skipped if Xcode isn't installed."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        root = HOME / "Library" / "Developer"
        if not root.exists():
            return
        min_size = self.mb("min_xcode_size_mb")

        for label, rel, sev, note in XCODE_TARGETS:
            p = HOME / rel
            if not p.exists():
                continue
            if self.is_excluded(p):
                continue
            self.report(progress, f"Xcode: {label}")
            size = dir_size(p)
            if size < min_size:
                continue
            yield ScanItem(
                path=p,
                size=size,
                mtime=latest_mtime(p),
                category=self.name,
                severity=sev,
                note=f"{label} — {note}",
                selected=(sev == Severity.SAFE),
            )
