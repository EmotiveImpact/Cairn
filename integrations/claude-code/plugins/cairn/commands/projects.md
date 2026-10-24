---
description: Find idle projects and clear their rebuildable build output
argument-hint: [idle days, default 30]
allowed-tools: ["mcp__plugin_cairn_cairn__list_projects", "mcp__plugin_cairn_cairn__plan_cleanup"]
---

Use Cairn to tidy projects I have not touched in a while.

1. Call `list_projects` with `minIdleDays` set to $ARGUMENTS, or 30 if I gave nothing.
2. List them with days idle and rebuildable size.
3. Call `plan_cleanup` with scope `projects` and the same `minIdleDays`, and show me the plan.
4. Ask before calling `run_cleanup`. Never include the project I am working in right now; if it appears, pass `projects` with only the others.
