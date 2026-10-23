# Cairn for AI coding tools

Every integration starts the same local server, `/Applications/Cairn.app/Contents/MacOS/Cairn mcp`. Cairn's own Settings › AI tools can connect each tool in one click; these packages add commands and guidance on top.

| Tool | Package | Install |
| --- | --- | --- |
| Claude Code | [`claude-code`](claude-code) plugin with `/cairn:status`, `/cairn:free-space`, `/cairn:projects` and a disk-space skill | `/plugin marketplace add EmotiveImpact/Cairn` then `/plugin install cairn@cairn` |
| Gemini CLI | [`gemini-extension`](gemini-extension) with the same three commands | For now, connect from Cairn › Settings › AI tools (needs its own small public repo to publish) |
| Cursor | Install link | [Add to Cursor](cursor://anysphere.cursor-deeplink/mcp/install?name=cairn&config=eyJjb21tYW5kIjoiL0FwcGxpY2F0aW9ucy9DYWlybi5hcHAvQ29udGVudHMvTWFjT1MvQ2Fpcm4iLCJhcmdzIjpbIm1jcCJdfQ%3D%3D) |
| VS Code | Install link | [Add to VS Code](vscode:mcp/install?%7B%22name%22%3A%22cairn%22%2C%22command%22%3A%22%2FApplications%2FCairn.app%2FContents%2FMacOS%2FCairn%22%2C%22args%22%3A%5B%22mcp%22%5D%7D) |
| Codex, Claude Desktop, Windsurf | Connect from Cairn › Settings › AI tools | |

The Claude Code marketplace is `.claude-plugin/marketplace.json` at the root of this repository, so Claude Code installs straight from it. Gemini CLI only installs an extension whose files sit at a repository's root, so publishing `gemini-extension` needs a small repository of its own; until then, Gemini users connect from Cairn › Settings › AI tools or run `gemini extensions link` on this folder.
