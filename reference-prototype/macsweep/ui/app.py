from __future__ import annotations

import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk
from typing import Optional

from ..core.fs import human_age, human_size
from ..core.item import CategoryResult, ScanItem, Severity
from ..core.registry import discover
from ..core.trash import TrashError, move_to_trash, permanent_delete
from .scan_worker import (
    CategoryDoneMessage,
    CategoryStartMessage,
    DoneMessage,
    ErrorMessage,
    ItemMessage,
    ProgressMessage,
    ScanWorker,
)

CHECK_ON = "☑"   # ☑
CHECK_OFF = "☐"  # ☐
DOT_SAFE = "\U0001f7e2"   # 🟢
DOT_REVIEW = "\U0001f7e1" # 🟡
DOT_RISKY = "\U0001f534"  # 🔴

SEV_DOT = {
    Severity.SAFE: DOT_SAFE,
    Severity.REVIEW: DOT_REVIEW,
    Severity.RISKY: DOT_RISKY,
}


class MacSweepApp:
    def __init__(self) -> None:
        discover()  # populate scanner registry

        self.root = tk.Tk()
        self.root.title("MacSweep")
        self.root.geometry("1080x680")
        self.root.minsize(900, 560)

        self.categories: dict[str, CategoryResult] = {}
        self.current_category: Optional[str] = None
        self.worker: Optional[ScanWorker] = None
        # map of treeview row id -> ScanItem
        self.row_items: dict[str, ScanItem] = {}

        self._build_layout()
        self._build_styles()
        self.root.after(200, self._start_scan)

    # ---------- layout ----------

    def _build_styles(self) -> None:
        style = ttk.Style()
        try:
            style.theme_use("aqua")  # native macOS
        except tk.TclError:
            pass
        style.configure("Sidebar.TFrame", background="#f4f4f6")
        style.configure("Sidebar.TLabel", background="#f4f4f6")
        style.configure("SidebarTotal.TLabel", background="#f4f4f6", font=("Helvetica", 18, "bold"))
        style.configure("SidebarItem.TLabel", background="#f4f4f6", font=("Helvetica", 13))
        style.configure("SidebarItemActive.TLabel", background="#dde6ff", font=("Helvetica", 13, "bold"))
        style.configure("Treeview", rowheight=24, font=("Helvetica", 12))
        style.configure("Treeview.Heading", font=("Helvetica", 11, "bold"))

    def _build_layout(self) -> None:
        # toolbar
        toolbar = ttk.Frame(self.root, padding=(10, 8))
        toolbar.pack(side=tk.TOP, fill=tk.X)
        self.rescan_btn = ttk.Button(toolbar, text="Rescan", command=self._start_scan)
        self.rescan_btn.pack(side=tk.LEFT)
        self.cancel_btn = ttk.Button(toolbar, text="Stop", command=self._cancel_scan, state=tk.DISABLED)
        self.cancel_btn.pack(side=tk.LEFT, padx=(6, 0))
        ttk.Label(toolbar, text="MacSweep", font=("Helvetica", 16, "bold")).pack(side=tk.LEFT, padx=14)

        # main paned window
        body = ttk.Frame(self.root)
        body.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        # sidebar
        self.sidebar = ttk.Frame(body, style="Sidebar.TFrame", width=260, padding=(14, 14))
        self.sidebar.pack(side=tk.LEFT, fill=tk.Y)
        self.sidebar.pack_propagate(False)

        ttk.Label(self.sidebar, text="Recoverable", style="Sidebar.TLabel").pack(anchor="w")
        self.total_label = ttk.Label(self.sidebar, text="—", style="SidebarTotal.TLabel")
        self.total_label.pack(anchor="w", pady=(0, 14))

        self.sidebar_items: dict[str, ttk.Label] = {}

        # main pane
        self.main_pane = ttk.Frame(body, padding=(14, 8))
        self.main_pane.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.cat_title = ttk.Label(self.main_pane, text="Scanning…", font=("Helvetica", 16, "bold"))
        self.cat_title.pack(anchor="w")
        self.cat_desc = ttk.Label(self.main_pane, text="", foreground="#555")
        self.cat_desc.pack(anchor="w", pady=(2, 8))

        # treeview
        cols = ("check", "sev", "name", "size", "age", "note")
        self.tree = ttk.Treeview(self.main_pane, columns=cols, show="headings", selectmode="browse")
        self.tree.heading("check", text="")
        self.tree.heading("sev", text="")
        self.tree.heading("name", text="Path", command=lambda: self._sort("name", False))
        self.tree.heading("size", text="Size", command=lambda: self._sort("size", True))
        self.tree.heading("age", text="Age", command=lambda: self._sort("age", True))
        self.tree.heading("note", text="Note")
        self.tree.column("check", width=36, anchor="center", stretch=False)
        self.tree.column("sev", width=32, anchor="center", stretch=False)
        self.tree.column("name", width=420, anchor="w")
        self.tree.column("size", width=90, anchor="e", stretch=False)
        self.tree.column("age", width=70, anchor="e", stretch=False)
        self.tree.column("note", width=280, anchor="w")

        scroll = ttk.Scrollbar(self.main_pane, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scroll.set)
        self.tree.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        scroll.place(in_=self.tree, relx=1.0, rely=0, relheight=1.0, anchor="ne")

        self.tree.bind("<Button-1>", self._on_tree_click)
        self.tree.bind("<Double-Button-1>", self._on_tree_double)
        self.tree.bind("<space>", self._on_space)

        # actions
        actions = ttk.Frame(self.main_pane, padding=(0, 10, 0, 0))
        actions.pack(side=tk.TOP, fill=tk.X)
        self.selection_label = ttk.Label(actions, text="Selected: 0 items · 0 B")
        self.selection_label.pack(side=tk.LEFT)

        ttk.Button(actions, text="Select All", command=self._select_all).pack(side=tk.RIGHT, padx=(6, 0))
        ttk.Button(actions, text="Select None", command=self._select_none).pack(side=tk.RIGHT, padx=(6, 0))
        ttk.Button(actions, text="Reveal in Finder", command=self._reveal).pack(side=tk.RIGHT, padx=(6, 0))
        self.delete_btn = ttk.Button(actions, text="Delete Permanently…", command=self._delete_permanent)
        self.delete_btn.pack(side=tk.RIGHT, padx=(6, 0))
        self.trash_btn = ttk.Button(actions, text="Move to Trash", command=self._move_to_trash)
        self.trash_btn.pack(side=tk.RIGHT, padx=(6, 0))

        # status bar
        status = ttk.Frame(self.root, padding=(10, 6))
        status.pack(side=tk.BOTTOM, fill=tk.X)
        self.status_label = ttk.Label(status, text="Ready.", foreground="#444")
        self.status_label.pack(side=tk.LEFT)
        self.progress = ttk.Progressbar(status, mode="indeterminate", length=160)
        self.progress.pack(side=tk.RIGHT)

        self._sort_state: dict[str, bool] = {}

    # ---------- sidebar ----------

    def _ensure_sidebar_row(self, name: str) -> None:
        if name in self.sidebar_items:
            return
        row = ttk.Frame(self.sidebar, style="Sidebar.TFrame")
        row.pack(fill=tk.X, pady=2)
        lbl = ttk.Label(row, text=f"  {name}\n  —", style="SidebarItem.TLabel", justify="left")
        lbl.pack(fill=tk.X)
        lbl.bind("<Button-1>", lambda _e, n=name: self._show_category(n))
        self.sidebar_items[name] = lbl

    def _refresh_sidebar(self) -> None:
        total = 0
        for name, lbl in self.sidebar_items.items():
            cat = self.categories.get(name)
            if cat is None:
                lbl.configure(text=f"  {name}\n  —")
                continue
            total += cat.total_size
            count = len(cat.items)
            lbl.configure(text=f"  {name}\n  {human_size(cat.total_size)} · {count} items")
            style = "SidebarItemActive.TLabel" if name == self.current_category else "SidebarItem.TLabel"
            lbl.configure(style=style)
        self.total_label.configure(text=human_size(total))

    # ---------- scan lifecycle ----------

    def _start_scan(self) -> None:
        if self.worker and self.worker.is_running():
            return
        self.categories.clear()
        self.current_category = None
        self.row_items.clear()
        self.tree.delete(*self.tree.get_children())
        for lbl in self.sidebar_items.values():
            lbl.destroy()
        self.sidebar_items.clear()
        self.cat_title.configure(text="Scanning…")
        self.cat_desc.configure(text="")
        self.total_label.configure(text="—")
        self.selection_label.configure(text="Selected: 0 items · 0 B")
        self.status_label.configure(text="Starting scan…")
        self.progress.start(60)
        self.cancel_btn.configure(state=tk.NORMAL)
        self.rescan_btn.configure(state=tk.DISABLED)

        self.worker = ScanWorker()
        self.worker.start()
        self.root.after(80, self._poll_worker)

    def _cancel_scan(self) -> None:
        if self.worker:
            self.worker.cancel()
            self.status_label.configure(text="Cancelling…")

    def _poll_worker(self) -> None:
        if not self.worker:
            return
        try:
            while True:
                msg = self.worker.q.get_nowait()
                self._handle_message(msg)
        except Exception:
            pass
        if self.worker.is_running():
            self.root.after(80, self._poll_worker)

    def _handle_message(self, msg) -> None:
        if isinstance(msg, CategoryStartMessage):
            self._ensure_sidebar_row(msg.name)
            self.categories.setdefault(msg.name, CategoryResult(name=msg.name))
            if self.current_category is None:
                self._show_category(msg.name, description=msg.description)
            self.status_label.configure(text=f"Scanning: {msg.name}")
        elif isinstance(msg, ItemMessage):
            cat = self.categories.setdefault(msg.item.category, CategoryResult(name=msg.item.category))
            cat.items.append(msg.item)
            if self.current_category == msg.item.category:
                self._insert_row(msg.item)
            self._refresh_sidebar()
        elif isinstance(msg, CategoryDoneMessage):
            self._refresh_sidebar()
        elif isinstance(msg, ProgressMessage):
            self.status_label.configure(text=msg.text[:140])
        elif isinstance(msg, ErrorMessage):
            self.status_label.configure(text=f"Error: {msg.text}")
        elif isinstance(msg, DoneMessage):
            self.progress.stop()
            self.cancel_btn.configure(state=tk.DISABLED)
            self.rescan_btn.configure(state=tk.NORMAL)
            if msg.cancelled:
                self.status_label.configure(text="Scan cancelled.")
            else:
                self.status_label.configure(text="Scan complete.")
            self._refresh_sidebar()

    # ---------- category / table ----------

    def _show_category(self, name: str, description: str | None = None) -> None:
        self.current_category = name
        self.cat_title.configure(text=name)
        if description:
            self.cat_desc.configure(text=description)
        else:
            # try to find description from any registered scanner
            from ..core.registry import all_scanners
            for s in all_scanners():
                if s.name == name:
                    self.cat_desc.configure(text=s.description)
                    break
        self.tree.delete(*self.tree.get_children())
        self.row_items.clear()
        cat = self.categories.get(name)
        if not cat:
            return
        # sort by size desc by default
        items = sorted(cat.items, key=lambda i: -i.size)
        for item in items:
            self._insert_row(item)
        self._refresh_sidebar()
        self._update_selection_label()

    def _insert_row(self, item: ScanItem) -> None:
        check = CHECK_ON if item.selected else CHECK_OFF
        sev = SEV_DOT.get(item.severity, "")
        rid = self.tree.insert(
            "",
            tk.END,
            values=(check, sev, str(item.path), human_size(item.size), human_age(item.age_days), item.note),
        )
        self.row_items[rid] = item
        self._update_selection_label()

    def _on_tree_click(self, event) -> None:
        region = self.tree.identify("region", event.x, event.y)
        if region != "cell":
            return
        col = self.tree.identify_column(event.x)
        rid = self.tree.identify_row(event.y)
        if not rid:
            return
        if col == "#1":  # check column
            self._toggle_row(rid)

    def _on_tree_double(self, event) -> None:
        rid = self.tree.identify_row(event.y)
        if rid:
            self._toggle_row(rid)

    def _on_space(self, _event) -> None:
        sel = self.tree.selection()
        for rid in sel:
            self._toggle_row(rid)

    def _toggle_row(self, rid: str) -> None:
        item = self.row_items.get(rid)
        if not item:
            return
        if item.severity == Severity.RISKY:
            return  # never selectable
        item.selected = not item.selected
        vals = list(self.tree.item(rid, "values"))
        vals[0] = CHECK_ON if item.selected else CHECK_OFF
        self.tree.item(rid, values=vals)
        self._update_selection_label()

    def _update_selection_label(self) -> None:
        cat = self.categories.get(self.current_category) if self.current_category else None
        if not cat:
            self.selection_label.configure(text="Selected: 0 items · 0 B")
            return
        n = cat.selected_count
        s = cat.selected_size
        self.selection_label.configure(text=f"Selected: {n} items · {human_size(s)}")

    def _select_all(self) -> None:
        cat = self.categories.get(self.current_category) if self.current_category else None
        if not cat:
            return
        for rid, item in self.row_items.items():
            if item.severity == Severity.RISKY:
                continue
            item.selected = True
            vals = list(self.tree.item(rid, "values"))
            vals[0] = CHECK_ON
            self.tree.item(rid, values=vals)
        self._update_selection_label()

    def _select_none(self) -> None:
        cat = self.categories.get(self.current_category) if self.current_category else None
        if not cat:
            return
        for rid, item in self.row_items.items():
            item.selected = False
            vals = list(self.tree.item(rid, "values"))
            vals[0] = CHECK_OFF
            self.tree.item(rid, values=vals)
        self._update_selection_label()

    def _sort(self, column: str, numeric: bool) -> None:
        if not self.current_category:
            return
        cat = self.categories.get(self.current_category)
        if not cat:
            return
        reverse = self._sort_state.get(column, False)
        if numeric:
            if column == "size":
                cat.items.sort(key=lambda i: i.size, reverse=not reverse)
            elif column == "age":
                cat.items.sort(key=lambda i: i.age_days, reverse=not reverse)
        else:
            cat.items.sort(key=lambda i: str(i.path).lower(), reverse=not reverse)
        self._sort_state[column] = not reverse
        # rebuild rows
        self.tree.delete(*self.tree.get_children())
        self.row_items.clear()
        for item in cat.items:
            self._insert_row(item)
        self._update_selection_label()

    # ---------- actions ----------

    def _selected_items(self) -> list[ScanItem]:
        cat = self.categories.get(self.current_category) if self.current_category else None
        if not cat:
            return []
        return [i for i in cat.items if i.selected]

    def _reveal(self) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        item = self.row_items.get(sel[0])
        if not item or not item.path.exists():
            return
        try:
            subprocess.run(["open", "-R", str(item.path)], check=False)
        except OSError:
            pass

    def _move_to_trash(self) -> None:
        items = self._selected_items()
        if not items:
            messagebox.showinfo("MacSweep", "No items selected.")
            return
        total_size = sum(i.size for i in items)
        if not messagebox.askyesno(
            "Move to Trash",
            f"Move {len(items)} item(s) ({human_size(total_size)}) to the Trash?\n\n"
            "You can restore them from Trash if you change your mind.",
        ):
            return
        self._perform(items, lambda p: move_to_trash(p), label="Trashed")

    def _delete_permanent(self) -> None:
        items = self._selected_items()
        if not items:
            messagebox.showinfo("MacSweep", "No items selected.")
            return
        total_size = sum(i.size for i in items)
        msg = (
            f"PERMANENTLY delete {len(items)} item(s) ({human_size(total_size)})?\n\n"
            "This cannot be undone."
        )
        if total_size > 1024 ** 3:
            confirm = _ask_typed_confirm(self.root, msg)
            if not confirm:
                return
        else:
            if not messagebox.askyesno("Delete Permanently", msg, icon="warning"):
                return
        self._perform(items, lambda p: permanent_delete(p), label="Deleted")

    def _perform(self, items: list[ScanItem], action, label: str) -> None:
        succeeded = 0
        failed = 0
        for item in items:
            if not item.path.exists():
                item.selected = False
                continue
            try:
                action(item.path)
                item.selected = False
                item.size = 0  # mark gone
                succeeded += 1
            except (TrashError, OSError, PermissionError) as e:
                failed += 1
                self.status_label.configure(text=f"Failed on {item.path.name}: {e}")
        # refresh current view
        if self.current_category:
            cat = self.categories.get(self.current_category)
            if cat:
                cat.items = [i for i in cat.items if i.path.exists()]
                self._show_category(self.current_category)
        self._refresh_sidebar()
        if failed:
            messagebox.showwarning("MacSweep", f"{label}: {succeeded} ok, {failed} failed.")
        else:
            self.status_label.configure(text=f"{label} {succeeded} item(s).")

    def run(self) -> None:
        self.root.mainloop()


def _ask_typed_confirm(parent: tk.Tk, prompt: str) -> bool:
    win = tk.Toplevel(parent)
    win.title("Confirm Permanent Deletion")
    win.transient(parent)
    win.grab_set()
    win.resizable(False, False)

    ttk.Label(win, text=prompt, padding=14, justify="left", wraplength=420).pack()
    ttk.Label(win, text='Type DELETE to confirm:', padding=(14, 0)).pack(anchor="w")
    var = tk.StringVar()
    entry = ttk.Entry(win, textvariable=var, width=20)
    entry.pack(padx=14, pady=(2, 10))
    entry.focus_set()

    result = {"ok": False}

    def on_ok():
        if var.get().strip() == "DELETE":
            result["ok"] = True
            win.destroy()

    def on_cancel():
        win.destroy()

    btns = ttk.Frame(win, padding=(14, 0, 14, 14))
    btns.pack(fill=tk.X)
    ttk.Button(btns, text="Cancel", command=on_cancel).pack(side=tk.RIGHT)
    ttk.Button(btns, text="Delete", command=on_ok).pack(side=tk.RIGHT, padx=(0, 6))
    win.bind("<Return>", lambda _e: on_ok())
    win.bind("<Escape>", lambda _e: on_cancel())
    parent.wait_window(win)
    return result["ok"]
