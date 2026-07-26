from __future__ import annotations

import time
from pathlib import Path
from typing import Iterator

from ..core.fs import HOME
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner

ROOTS = ["Downloads", "Desktop", "Movies", "Music"]


@register
class LargeOldFilesScanner(Scanner):
    name = "Large / Old Files"
    description = "Files in Downloads/Desktop/Movies/Music that are over the size limit or older than the age limit."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        size_threshold = self.mb("large_files_size_mb")
        age_days = self.days("large_files_age_days")
        cutoff = time.time() - age_days * 86400
        for r in ROOTS:
            root = HOME / r
            if not root.exists():
                continue
            self.report(progress, f"Large/old: ~/{r}")
            yield from _walk_for_large(root, cutoff, size_threshold, self.is_excluded)


def _walk_for_large(root: Path, cutoff: float, size_threshold: int, is_excluded):
    try:
        for p in root.rglob("*"):
            if not p.is_file() or p.is_symlink():
                continue
            if any(part.endswith(".app") for part in p.parts):
                continue
            if is_excluded(p):
                continue
            try:
                st = p.stat()
            except OSError:
                continue
            big = st.st_size >= size_threshold
            old = st.st_mtime < cutoff and st.st_size >= 10 * 1024 * 1024
            if not (big or old):
                continue
            note = []
            if big:
                note.append("large")
            if old:
                note.append("old")
            yield ScanItem(
                path=p,
                size=st.st_size,
                mtime=st.st_mtime,
                category="Large / Old Files",
                severity=Severity.REVIEW,
                note=", ".join(note),
                selected=False,
            )
    except (OSError, PermissionError):
        return
