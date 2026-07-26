from __future__ import annotations

from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner


@register
class TrashScanner(Scanner):
    name = "Trash"
    description = "Items already in the Trash — emptying reclaims this space immediately."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        trash = HOME / ".Trash"
        if not trash.exists():
            return
        min_size = self.mb("min_trash_item_mb")
        self.report(progress, "Reading Trash")
        try:
            entries = list(trash.iterdir())
        except (OSError, PermissionError):
            return
        for p in entries:
            if self.is_excluded(p):
                continue
            try:
                size = dir_size(p) if p.is_dir() else p.stat().st_size
            except OSError:
                continue
            if size < min_size:
                continue
            yield ScanItem(
                path=p,
                size=size,
                mtime=latest_mtime(p),
                category=self.name,
                severity=Severity.SAFE,
                note="In Trash",
                selected=True,
            )
