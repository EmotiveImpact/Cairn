from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from .fs import HOME

CONFIG_DIR = HOME / "Library" / "Application Support" / "MacSweep"
CONFIG_PATH = CONFIG_DIR / "settings.json"

DEFAULTS: dict[str, Any] = {
    "installers_age_days": 30,
    "logs_age_days": 14,
    "large_files_size_mb": 100,
    "large_files_age_days": 90,
    "min_cache_size_mb": 5,
    "min_orphaned_size_mb": 1,
    "min_browser_cache_mb": 1,
    "min_xcode_size_mb": 50,
    "min_dev_cache_mb": 5,
    "min_trash_item_mb": 1,
    "excluded_paths": [],
}


class Settings:
    """Singleton-ish settings loader. Reads and writes JSON in ~/Library/Application Support/MacSweep/."""

    _instance: "Settings | None" = None

    def __init__(self) -> None:
        self._data: dict[str, Any] = dict(DEFAULTS)
        self._load()

    @classmethod
    def get(cls) -> "Settings":
        if cls._instance is None:
            cls._instance = Settings()
        return cls._instance

    def _load(self) -> None:
        if not CONFIG_PATH.exists():
            return
        try:
            raw = json.loads(CONFIG_PATH.read_text())
            if isinstance(raw, dict):
                for k, v in raw.items():
                    if k in DEFAULTS:
                        self._data[k] = v
        except (OSError, json.JSONDecodeError):
            pass

    def save(self) -> None:
        try:
            CONFIG_DIR.mkdir(parents=True, exist_ok=True)
            CONFIG_PATH.write_text(json.dumps(self._data, indent=2))
        except OSError:
            pass

    # convenience getters with type coercion

    def int_value(self, key: str) -> int:
        try:
            return int(self._data.get(key, DEFAULTS[key]))
        except (TypeError, ValueError):
            return int(DEFAULTS[key])

    def excluded_paths(self) -> list[str]:
        v = self._data.get("excluded_paths", [])
        return list(v) if isinstance(v, list) else []

    def set_value(self, key: str, value: Any) -> None:
        if key not in DEFAULTS:
            return
        self._data[key] = value

    def reset_to_defaults(self) -> None:
        self._data = dict(DEFAULTS)

    def add_exclusion(self, path: Path) -> None:
        s = str(path.resolve())
        ex = self.excluded_paths()
        if s not in ex:
            ex.append(s)
            self._data["excluded_paths"] = ex

    def remove_exclusion(self, path_str: str) -> None:
        ex = [p for p in self.excluded_paths() if p != path_str]
        self._data["excluded_paths"] = ex

    def is_excluded(self, path: Path) -> bool:
        try:
            p = str(path.resolve())
        except OSError:
            return False
        for ex in self.excluded_paths():
            if p == ex or p.startswith(ex + os.sep):
                return True
        return False
