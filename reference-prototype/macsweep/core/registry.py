from __future__ import annotations

from typing import Callable

from ..scanners.base import Scanner

_SCANNERS: list[Callable[[], Scanner]] = []


def register(factory: Callable[[], Scanner]) -> Callable[[], Scanner]:
    _SCANNERS.append(factory)
    return factory


def all_scanners() -> list[Scanner]:
    return [f() for f in _SCANNERS]


def discover():
    """Import all scanner modules so they self-register."""
    from ..scanners import (  # noqa: F401
        installers,
        caches,
        orphaned,
        logs,
        browsers,
        xcode,
        trash_scanner,
        large_files,
        dev_caches,
    )
