from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Iterator

from ..core.fs import HOME, dir_size, latest_mtime
from ..core.item import ScanItem, Severity
from ..core.registry import register
from .base import ProgressCb, Scanner

# (label, relative_path, severity, note)
DEV_TARGETS: list[tuple[str, str, Severity, str]] = [
    ("npm", ".npm/_cacache", Severity.SAFE, "npm package cache"),
    ("npm logs", ".npm/_logs", Severity.SAFE, "npm install logs"),
    ("yarn classic", ".yarn-cache", Severity.SAFE, "yarn v1 cache"),
    ("yarn berry", ".yarn/cache", Severity.SAFE, "yarn berry cache"),
    ("pnpm", "Library/pnpm/store", Severity.REVIEW, "pnpm content-addressed store — clear with pnpm store prune"),
    ("pip", "Library/Caches/pip", Severity.SAFE, "pip wheel cache"),
    ("pip-tools", ".cache/pip-tools", Severity.SAFE, "pip-tools cache"),
    ("uv", ".cache/uv", Severity.SAFE, "uv cache"),
    ("poetry", "Library/Caches/pypoetry", Severity.SAFE, "Poetry cache"),
    ("Cargo registry", ".cargo/registry/cache", Severity.SAFE, "Rust registry tarballs"),
    ("Go build", "Library/Caches/go-build", Severity.SAFE, "Go build cache"),
    ("Gradle", ".gradle/caches", Severity.REVIEW, "Gradle dependency caches"),
    ("Maven", ".m2/repository", Severity.REVIEW, "Maven local repository"),
    ("CocoaPods", "Library/Caches/CocoaPods", Severity.SAFE, "CocoaPods cache"),
    ("Homebrew", "Library/Caches/Homebrew", Severity.SAFE, "Homebrew downloads — also `brew cleanup`"),
    ("Bun install", ".bun/install/cache", Severity.SAFE, "Bun install cache"),
    ("Deno", "Library/Caches/deno", Severity.REVIEW, "Deno module cache"),
]

@register
class DevCachesScanner(Scanner):
    name = "Developer Caches"
    description = "Package manager and build tool caches — npm, pip, brew, cargo, gradle, etc."

    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        min_size = self.mb("min_dev_cache_mb")
        for label, rel, sev, note in DEV_TARGETS:
            p = HOME / rel
            if not p.exists() or not p.is_dir():
                continue
            if self.is_excluded(p):
                continue
            self.report(progress, f"Dev: {label}")
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
                selected=False,
            )

        yield from _docker_items(self.report, progress)


def _docker_items(report, progress) -> Iterator[ScanItem]:
    """Report Docker disk usage if Docker CLI is available."""
    if not shutil.which("docker"):
        return
    try:
        result = subprocess.run(
            ["docker", "system", "df", "--format", "{{.Type}}\t{{.Size}}\t{{.Reclaimable}}"],
            capture_output=True, text=True, timeout=8,
        )
    except (subprocess.SubprocessError, OSError):
        return
    if result.returncode != 0:
        return
    report(progress, "Docker: system df")
    # Docker disk usage isn't a path — represent as a synthetic item the UI can show.
    # We don't auto-delete Docker; selection is disabled by an empty path with a special note.
    summary = result.stdout.strip().replace("\t", "  ")
    if summary:
        # Use a sentinel path inside ~/Library so safe_under_home is happy if user clicks it.
        # We'll mark it Risky so it's never selected/deleted by mistake.
        sentinel = HOME / "Library" / "Caches" / ".macsweep_docker_info"
        yield ScanItem(
            path=sentinel,
            size=0,
            mtime=0.0,
            category="Developer Caches",
            severity=Severity.RISKY,
            note=f"Docker (info only — run `docker system prune`): {summary}",
            selected=False,
        )
