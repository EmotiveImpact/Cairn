from __future__ import annotations

from pathlib import Path
from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner


def _installed_bundle_ids() -> set[str]:
    """Collect bundle ids from /Applications and ~/Applications by reading Info.plist."""
    ids: set[str] = set()
    app_roots = [Path("/Applications"), HOME / "Applications"]
    for root in app_roots:
        if not root.exists():
            continue
        try:
            for app in root.glob("*.app"):
                ids.update(_bundle_id_from_app(app))
            for app in root.glob("*/*.app"):
                ids.update(_bundle_id_from_app(app))
        except (OSError, PermissionError):
            pass
    return ids


def _bundle_id_from_app(app: Path) -> set[str]:
    plist = app / "Contents" / "Info.plist"
    if not plist.exists():
        return set()
    try:
        import plistlib
        with plist.open("rb") as fh:
            data = plistlib.load(fh)
        bid = data.get("CFBundleIdentifier")
        return {bid} if bid else set()
    except Exception:
        return set()


@register
class OrphanedAppDataScanner(Scanner):
    name = "Orphaned App Data"
    description = "Application Support / Containers folders for apps no longer installed."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        installed = _installed_bundle_ids()
        installed_lower = {b.lower() for b in installed}
        min_size = self.mb("min_orphaned_size_mb")

        for sub in ("Application Support", "Containers", "Group Containers"):
            base = HOME / "Library" / sub
            if not base.exists():
                continue
            self.report(progress, f"Orphaned scan: {sub}")
            try:
                entries = list(base.iterdir())
            except (OSError, PermissionError):
                continue
            for p in entries:
                if not p.is_dir():
                    continue
                if self.is_excluded(p):
                    continue
                name = p.name
                if "." in name:
                    if name.lower() in installed_lower:
                        continue
                else:
                    if any(b.lower().endswith("." + name.lower()) for b in installed):
                        continue
                if name.startswith("com.apple.") or name in {
                    "MobileSync", "CrashReporter", "Caches", "iCloud",
                }:
                    continue
                size = dir_size(p)
                if size < min_size:
                    continue
                yield ScanItem(
                    path=p,
                    size=size,
                    mtime=latest_mtime(p),
                    category=self.name,
                    severity=Severity.REVIEW,
                    note=f"No matching app installed for '{name}'",
                    selected=False,
                )
