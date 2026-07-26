from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Iterator, Callable

from ..core.item import ScanItem
from ..core.settings import Settings


ProgressCb = Callable[[str], None]


class Scanner(ABC):
    name: str = ""
    description: str = ""

    def __init__(self) -> None:
        self.settings = Settings.get()

    @abstractmethod
    def scan(self, progress: ProgressCb | None = None) -> Iterator[ScanItem]:
        """Yield ScanItems for this category."""
        ...

    def report(self, progress: ProgressCb | None, msg: str) -> None:
        if progress:
            progress(msg)

    def is_excluded(self, path: Path) -> bool:
        return self.settings.is_excluded(path)

    def mb(self, key: str) -> int:
        return self.settings.int_value(key) * 1024 * 1024

    def days(self, key: str) -> int:
        return self.settings.int_value(key)
