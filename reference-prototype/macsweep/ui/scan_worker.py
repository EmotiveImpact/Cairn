from __future__ import annotations

import queue
import threading
from dataclasses import dataclass
from typing import Optional

from ..core.item import ScanItem
from ..core.registry import all_scanners


@dataclass
class ProgressMessage:
    text: str


@dataclass
class ItemMessage:
    item: ScanItem


@dataclass
class CategoryStartMessage:
    name: str
    description: str


@dataclass
class CategoryDoneMessage:
    name: str


@dataclass
class DoneMessage:
    cancelled: bool = False


@dataclass
class ErrorMessage:
    text: str


Message = (
    ProgressMessage
    | ItemMessage
    | CategoryStartMessage
    | CategoryDoneMessage
    | DoneMessage
    | ErrorMessage
)


class ScanWorker:
    """Runs all scanners in a background thread, pushing messages to a Queue
    that the Tk main thread polls."""

    def __init__(self) -> None:
        self.q: queue.Queue[Message] = queue.Queue()
        self._cancel = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._cancel.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def cancel(self) -> None:
        self._cancel.set()

    def is_running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())

    def _run(self) -> None:
        try:
            for s in all_scanners():
                if self._cancel.is_set():
                    self.q.put(DoneMessage(cancelled=True))
                    return
                self.q.put(CategoryStartMessage(name=s.name, description=s.description))

                def progress(msg: str, _name=s.name) -> None:
                    self.q.put(ProgressMessage(text=f"[{_name}] {msg}"))

                try:
                    for item in s.scan(progress=progress):
                        if self._cancel.is_set():
                            self.q.put(DoneMessage(cancelled=True))
                            return
                        self.q.put(ItemMessage(item=item))
                except Exception as e:  # noqa: BLE001
                    self.q.put(ErrorMessage(text=f"{s.name} failed: {e}"))
                self.q.put(CategoryDoneMessage(name=s.name))
            self.q.put(DoneMessage(cancelled=False))
        except Exception as e:  # noqa: BLE001
            self.q.put(ErrorMessage(text=f"Scan crashed: {e}"))
            self.q.put(DoneMessage(cancelled=True))
