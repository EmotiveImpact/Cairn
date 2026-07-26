from __future__ import annotations

import time
from pathlib import Path
from typing import Iterator

from ..core.fs import HOME
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner

INSTALLER_SUFFIXES = {".dmg", ".pkg", ".iso", ".zip", ".tar.gz", ".tgz", ".xz", ".bz2"}
APP_BUNDLE_SUFFIX = ".app"


def _has_installer_suffix(name: str) -> bool:
    lower = name.lower()
    return any(lower.endswith(s) for s in INSTALLER_SUFFIXES)


@register
class InstallersScanner(Scanner):
    name = "Old Installers"
    description = "DMG, PKG, ZIP, and similar installer files in ~/Downloads older than the configured age."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        downloads = HOME / "Downloads"
        if not downloads.exists():
            return
        age_days = self.days("installers_age_days")
        cutoff = time.time() - age_days * 86400
        self.report(progress, f"Scanning {downloads}")
        try:
            for p in downloads.iterdir():
                if not p.is_file():
                    continue
                if not _has_installer_suffix(p.name):
                    continue
                if self.is_excluded(p):
                    continue
                try:
                    st = p.stat()
                except OSError:
                    continue
                if st.st_mtime > cutoff:
                    continue
                yield ScanItem(
                    path=p,
                    size=st.st_size,
                    mtime=st.st_mtime,
                    category=self.name,
                    severity=Severity.SAFE,
                    note="Installer in Downloads",
                    selected=True,
                )
        except (OSError, PermissionError):
            return
