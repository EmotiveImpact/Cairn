from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
import time


class Severity(str, Enum):
    SAFE = "safe"
    REVIEW = "review"
    RISKY = "risky"


@dataclass
class ScanItem:
    path: Path
    size: int
    mtime: float
    category: str
    severity: Severity = Severity.SAFE
    note: str = ""
    selected: bool = False

    @property
    def age_days(self) -> float:
        return max(0.0, (time.time() - self.mtime) / 86400.0)

    @property
    def exists(self) -> bool:
        return self.path.exists()


@dataclass
class CategoryResult:
    name: str
    items: list[ScanItem] = field(default_factory=list)

    @property
    def total_size(self) -> int:
        return sum(i.size for i in self.items)

    @property
    def selected_size(self) -> int:
        return sum(i.size for i in self.items if i.selected)

    @property
    def selected_count(self) -> int:
        return sum(1 for i in self.items if i.selected)
