from __future__ import annotations

from pathlib import Path
from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner

# (display_name, relative_path_under_home) — only entries that are pure cache.
BROWSER_CACHES: list[tuple[str, str]] = [
    ("Safari", "Library/Caches/com.apple.Safari"),
    ("Safari WebKit", "Library/Caches/com.apple.WebKit.PluginProcess"),
    ("Chrome", "Library/Caches/Google/Chrome"),
    ("Chrome Code Cache", "Library/Application Support/Google/Chrome/Default/Code Cache"),
    ("Chrome GPU Cache", "Library/Application Support/Google/Chrome/Default/GPUCache"),
    ("Chrome Service Worker", "Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage"),
    ("Firefox", "Library/Caches/Firefox"),
    ("Brave", "Library/Caches/BraveSoftware/Brave-Browser"),
    ("Arc", "Library/Caches/company.thebrowser.Browser"),
    ("Edge", "Library/Caches/Microsoft Edge"),
    ("Opera", "Library/Caches/com.operasoftware.Opera"),
]


@register
class BrowserCachesScanner(Scanner):
    name = "Browser Caches"
    description = "Web caches for installed browsers. Safe to clear; you'll re-download some content next visit."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        min_size = self.mb("min_browser_cache_mb")
        for label, rel in BROWSER_CACHES:
            p = HOME / rel
            if not p.exists() or not p.is_dir():
                continue
            if self.is_excluded(p):
                continue
            self.report(progress, f"Browser: {label}")
            size = dir_size(p)
            if size < min_size:
                continue
            yield ScanItem(
                path=p,
                size=size,
                mtime=latest_mtime(p),
                category=self.name,
                severity=Severity.SAFE,
                note=label,
                selected=False,
            )
