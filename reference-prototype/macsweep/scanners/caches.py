from __future__ import annotations

from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner

# Caches we never touch — they're tiny system-critical things or contain
# meaningful state that some apps treat as a real database.
EXCLUDE = {
    "com.apple.Safari",  # handled by browsers scanner
    "com.apple.Safari.SafeBrowsing",
    "com.apple.HomeKit",
    "com.apple.iCloud",
    "com.apple.Spotlight",
    "Mozilla",  # handled by browsers
    "Google",   # handled by browsers
    "Firefox",
    "BraveSoftware",
    "company.thebrowser.Browser",  # Arc
}

@register
class CachesScanner(Scanner):
    name = "App Caches"
    description = "Per-app caches under ~/Library/Caches. Apps recreate these on next launch."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        caches = HOME / "Library" / "Caches"
        if not caches.exists():
            return
        min_size = self.mb("min_cache_size_mb")
        try:
            entries = list(caches.iterdir())
        except (OSError, PermissionError):
            return
        for p in entries:
            if p.name in EXCLUDE or any(p.name.startswith(e) for e in EXCLUDE):
                continue
            if not p.is_dir():
                continue
            if self.is_excluded(p):
                continue
            self.report(progress, f"App caches: {p.name}")
            size = dir_size(p)
            if size < min_size:
                continue
            mtime = latest_mtime(p)
            yield ScanItem(
                path=p,
                size=size,
                mtime=mtime,
                category=self.name,
                severity=Severity.SAFE,
                note=f"Cache for {p.name}",
                selected=False,
            )
