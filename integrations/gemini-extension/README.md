# Cairn for Gemini CLI

Requires the Cairn Mac app in `/Applications`.

Gemini CLI installs extensions only from a repository whose root holds `gemini-extension.json`, so this folder is published as a small repository of its own (not created yet). Until then, connect Gemini from Cairn › Settings › AI tools.

Commands: `/cairn:status`, `/cairn:free-space [GB]`, `/cairn:projects [idle days]`. `GEMINI.md` tells Gemini to reach for Cairn when a build fails with "No space left on device".

Cairn decides what AI tools may do. In Cairn › Settings › AI tools choose Off, Ask me each time, or Let them clean safe junk. Only caches and build files that rebuild themselves are ever cleaned.

To try the commands from a clone of this repository: `gemini extensions link integrations/gemini-extension`.
