from __future__ import annotations

import os
from pathlib import Path

HOME = Path.home()


def human_size(n: int) -> str:
    if n < 1024:
        return f"{n} B"
    units = ["KB", "MB", "GB", "TB"]
    f = float(n)
    for u in units:
        f /= 1024.0
        if f < 1024.0:
            if f >= 100:
                return f"{f:.0f} {u}"
            if f >= 10:
                return f"{f:.1f} {u}"
            return f"{f:.2f} {u}"
    return f"{f:.1f} PB"


def human_age(days: float) -> str:
    if days < 1:
        h = int(days * 24)
        return f"{h}h" if h else "<1h"
    if days < 30:
        return f"{int(days)}d"
    if days < 365:
        return f"{int(days / 30)}mo"
    return f"{days / 365:.1f}y"


def dir_size(path: Path, max_depth: int | None = None, follow_symlinks: bool = False) -> int:
    """Walk a directory and sum file sizes. Skips on permission errors."""
    total = 0
    try:
        base_depth = len(path.parts)
        for root, dirs, files in os.walk(path, followlinks=follow_symlinks):
            if max_depth is not None:
                depth = len(Path(root).parts) - base_depth
                if depth >= max_depth:
                    dirs[:] = []
            for f in files:
                fp = Path(root) / f
                try:
                    if fp.is_symlink():
                        continue
                    total += fp.stat().st_size
                except (OSError, FileNotFoundError):
                    pass
    except (OSError, PermissionError):
        pass
    return total


def latest_mtime(path: Path) -> float:
    """Return the most recent mtime in a tree, or the path's own mtime."""
    try:
        latest = path.stat().st_mtime
    except OSError:
        return 0.0
    if path.is_file():
        return latest
    try:
        for root, _, files in os.walk(path):
            for f in files:
                try:
                    m = (Path(root) / f).stat().st_mtime
                    if m > latest:
                        latest = m
                except OSError:
                    pass
    except (OSError, PermissionError):
        pass
    return latest


def safe_under_home(path: Path) -> bool:
    """Hard guard: only allow paths under the user's home, /private/var/folders, or known system caches."""
    try:
        p = path.resolve()
    except OSError:
        return False
    home = HOME.resolve()
    if str(p).startswith(str(home) + os.sep) or p == home:
        # block ~ itself and a few critical subdirs
        if p == home:
            return False
        forbidden = {home / "Library" / "Keychains", home / ".ssh", home / "Documents"}
        for f in forbidden:
            if p == f or str(p).startswith(str(f) + os.sep):
                return False
        return True
    # allow common temp / system caches that scanners explicitly target
    allowlist = ["/private/var/folders", "/Library/Caches"]
    for a in allowlist:
        if str(p).startswith(a + os.sep):
            return True
    return False
