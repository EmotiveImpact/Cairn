---
description: Show free space on this Mac and what is taking it
allowed-tools: ["mcp__plugin_cairn_cairn__storage_status", "mcp__plugin_cairn_cairn__find_reclaimable", "mcp__plugin_cairn_cairn__list_projects"]
---

Use Cairn to give me a short disk report:

1. Call `storage_status` for free and total space and the recent trend.
2. Call `list_projects` with `limit` 5 for the projects holding the most rebuildable build output.
3. Call `find_reclaimable` with `limit` 10 for the largest cleanup candidates.

Reply in a few lines: free space, the three biggest things I could safely free, and the total. Do not clean anything.
