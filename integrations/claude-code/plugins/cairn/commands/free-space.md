---
description: Plan and free disk space with Cairn (safe, rebuildable junk only)
argument-hint: [gigabytes]
allowed-tools: ["mcp__plugin_cairn_cairn__storage_status", "mcp__plugin_cairn_cairn__plan_cleanup", "mcp__plugin_cairn_cairn__recent_cleanups", "mcp__plugin_cairn_cairn__open_cairn"]
---

Free disk space on this Mac with Cairn.

1. Call `storage_status`.
2. Call `plan_cleanup` with scope `recommended`. If I gave a number ($ARGUMENTS), pass it as `targetGB`.
3. Show me the plan: the total, the largest items with their paths, and anything held back for review.
4. If `cleaningMode` is `off`, tell me I can allow it in Cairn › Settings › AI tools, offer to call `open_cairn`, and stop.
5. Otherwise ask me to confirm, then call `run_cleanup` with the `planId`. If the mode is `ask`, Cairn will also ask me in its own window.
6. Report what was freed, the change macOS measured and anything that failed.
