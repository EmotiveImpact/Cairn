# Using Cairn from Claude Code and other agents

Cairn includes a read-only [Model Context Protocol](https://modelcontextprotocol.io) server, so a coding agent can see what is using space while you work.

## Set up

Install the command line link from Cairn's preferences (it creates `/usr/local/bin/cairn`), then register the server:

```sh
claude mcp add cairn -- /usr/local/bin/cairn mcp
```

The server runs alongside the Cairn app. It never opens Cairn's stores, journals or recovery data.

## Tools

| Tool | What it does |
| --- | --- |
| `storage_status` | Available and total space, plus the recent trend |
| `list_projects` | Repositories with rebuildable build output, size and days idle (`minIdleDays`, `limit`) |
| `find_reclaimable` | Measured cleanup candidates by category, with rebuildable and actionable flags (`category`, `limit`) |
| `list_categories` | Scanner ids for `find_reclaimable` |
| `open_cairn` | Opens Cairn on a page (`projects`, `developer`, `makeRoom` and others) |

## What it will not do

There is no tool that removes files. An agent can find space and open Cairn, but you review the exact items in the app before anything is removed. This keeps the same review-before-removal rule that governs every other route.

## From a terminal

```sh
cairn projects --idle 30        # idle repositories and their rebuildable output
cairn projects --json
```
