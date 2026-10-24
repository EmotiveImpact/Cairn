---
name: disk-space
description: Use when a build, install, Docker pull or test fails with "No space left on device", ENOSPC or a full disk, or when the user asks what is using space on their Mac. Cairn measures and safely frees rebuildable developer junk.
---

# Disk space with Cairn

Cairn is a Mac app that knows which developer output rebuilds itself: `node_modules`, `DerivedData`, Rust `target`, `.build`, Pods, package-manager caches and Docker build cache. Its tools are available here through the `cairn` MCP server.

## When a command fails for lack of space

1. Call `storage_status` to confirm the disk is nearly full.
2. Call `plan_cleanup` with `targetGB` set to what the failing step needs plus a margin (10 GB is a sensible default).
3. Show the user the plan in a few lines and ask before calling `run_cleanup`.
4. After it runs, retry the command that failed.

## Rules

- Only `run_cleanup` removes anything, and only a plan made in the last 15 minutes. Make a new plan rather than reusing an old `planId`.
- Never delete files yourself with `rm` to free space when Cairn is available. Cairn checks every item, keeps a recovery journal and records a receipt.
- If `cleaningMode` is `off`, the user has not allowed AI tools to clean. Explain that, and offer `open_cairn` so they can review it themselves.
- Do not include the project the user is actively working in. Pass `projects` to `plan_cleanup` to choose which ones.
- Personal files, AI conversation history and the Trash are never part of a plan. Do not ask Cairn to remove them.
