from __future__ import annotations

import time
from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner


@register
class LogsScanner(Scanner):
    name = "Old Logs"
    description = "~/Library/Logs subdirectories that haven't been touched in a while."

    MIN_SIZE = 1 * 1024 * 1024

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        logs = HOME / "Library" / "Logs"
        if not logs.exists():
            return
        age_days = self.days("logs_age_days")
        cutoff = time.time() - age_days * 86400
        try:
            entries = list(logs.iterdir())
        except (OSError, PermissionError):
            return
        for p in entries:
            if self.is_excluded(p):
                continue
            self.report(progress, f"Logs: {p.name}")
            mtime = latest_mtime(p)
            if mtime > cutoff:
                continue
            size = dir_size(p) if p.is_dir() else _safe_size(p)
            if size < self.MIN_SIZE:
                continue
            yield ScanItem(
                path=p,
                size=size,
                mtime=mtime,
                category=self.name,
                severity=Severity.SAFE,
                note=f"Untouched logs for {p.name}",
                selected=True,
            )


def _safe_size(p):
    try:
        return p.stat().st_size
    except OSError:
        return 0
