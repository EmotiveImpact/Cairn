# Using Cairn from Claude Code and other agents

Cairn includes a read-only [Model Context Protocol](https://modelcontextprotocol.io) server, so a coding agent can see what is using space while you work.

## Set up

Open **Settings › AI tools** in Cairn and press **Connect** beside each tool. Cairn finds Claude Code, Claude Desktop, Codex, Cursor, Gemini CLI, VS Code and Windsurf, adds a single `cairn` entry to that tool's own MCP settings and keeps a `.cairn-backup` copy of the file first. Claude Code is connected through its own `claude mcp add` command. Settings files Cairn cannot parse, such as JSON with comments, are left alone. Restart the tool afterwards.

To set it up by hand, point the tool at Cairn's binary with the argument `mcp`:

```sh
claude mcp add --scope user cairn -- /Applications/Cairn.app/Contents/MacOS/Cairn mcp
```

ChatGPT and Grok only connect to online MCP servers, so they cannot reach Cairn on this Mac.

The server runs alongside the Cairn app. It never opens Cairn's stores, journals or recovery data.

## Tools

| Tool | What it does |
| --- | --- |
| `storage_status` | Available and total space, plus the recent trend |
| `list_projects` | Repositories with rebuildable build output, size and days idle (`minIdleDays`, `limit`) |
| `find_reclaimable` | Measured cleanup candidates by category, with rebuildable and actionable flags (`category`, `limit`) |
| `list_categories` | Scanner ids for `find_reclaimable` |
| `plan_cleanup` | The exact safe, rebuildable items Cairn would remove (`scope`: recommended, projects or category; `targetGB`, `minIdleDays`, `projects`, `category`). Removes nothing |
| `run_cleanup` | Runs one plan, once, within 15 minutes (`planId`) |
| `recent_cleanups` | The latest receipts, including who ran them and the measured change |
| `open_cairn` | Opens Cairn on a page (`projects`, `developer`, `makeRoom`, `settings` and others) |

## Letting AI tools clean

Cleaning by AI tools is **off** until you choose otherwise in **Settings › AI tools**:

- **Off**: agents can measure and plan. To free space they open Cairn for you.
- **Ask me each time**: when an agent runs a plan, Cairn comes forward and lists exactly what will be removed. Nothing happens until you press Free.
- **Let them clean safe junk**: agents can run their plans without asking.

Whatever you choose, a plan only ever holds findings Cairn has proved are safe and rebuild themselves: build output, `node_modules`, package-manager and tool caches. Items that need a person (virtual environments without a manifest, anything marked for review), personal files, AI conversation history, the Trash and data-destroying tool commands such as `docker system prune --volumes` are never included. Every run goes through the same executor, recovery journal and protected-path guard as a clean you start yourself, follows your removal setting (Smart, Delete now or Move to Trash), and leaves a receipt in Activity named after the tool that asked.

How it works: `Cairn mcp` runs inside the agent and forwards `plan_cleanup`, `run_cleanup` and `recent_cleanups` to the running app over a socket in `~/Library/Application Support/Cairn` that only your user can open. If Cairn is not running, it is started in the background. A plan can be run once, and only within 15 minutes of being made.

## From a terminal

```sh
cairn projects --idle 30        # idle repositories and their rebuildable output
cairn projects --json
```
