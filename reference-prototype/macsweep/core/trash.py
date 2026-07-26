from __future__ import annotations

import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from .fs import HOME, safe_under_home


class TrashError(Exception):
    pass


def move_to_trash(path: Path) -> None:
    """Move a file/dir to the macOS Trash. Tries Finder via osascript first
    (preserves Put Back), falls back to a manual move into ~/.Trash."""
    if not path.exists():
        return
    if not safe_under_home(path):
        raise TrashError(f"Refusing to trash path outside allowlist: {path}")

    posix = str(path.resolve())
    try:
        result = subprocess.run(
            [
                "osascript",
                "-e",
                f'tell application "Finder" to delete (POSIX file "{posix}" as alias)',
            ],
            capture_output=True,
            timeout=30,
        )
        if result.returncode == 0:
            return
    except (subprocess.SubprocessError, FileNotFoundError):
        pass

    _manual_trash(path)


def _manual_trash(path: Path) -> None:
    trash = HOME / ".Trash"
    trash.mkdir(exist_ok=True)
    target = trash / path.name
    if target.exists():
        ts = datetime.now().strftime("%Y-%m-%d %H.%M.%S")
        stem = path.stem if path.is_file() else path.name
        suffix = path.suffix if path.is_file() else ""
        target = trash / f"{stem} {ts}{suffix}"
    try:
        shutil.move(str(path), str(target))
    except OSError as e:
        raise TrashError(f"Could not move {path} to trash: {e}") from e


def permanent_delete(path: Path) -> None:
    """Delete a file or directory permanently. Use with care."""
    if not path.exists():
        return
    if not safe_under_home(path):
        raise TrashError(f"Refusing to delete path outside allowlist: {path}")
    if path.is_file() or path.is_symlink():
        path.unlink(missing_ok=True)
    else:
        shutil.rmtree(path, ignore_errors=False)


def empty_trash() -> int:
    """Empty the user's Trash. Returns reclaimed size in bytes."""
    trash = HOME / ".Trash"
    if not trash.exists():
        return 0
    from .fs import dir_size
    size = dir_size(trash)
    for child in trash.iterdir():
        try:
            if child.is_file() or child.is_symlink():
                child.unlink()
            else:
                shutil.rmtree(child, ignore_errors=True)
        except OSError:
            pass
    return size
