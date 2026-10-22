# Cairn for Claude Code

Requires the Cairn Mac app in `/Applications`.

```text
/plugin marketplace add emotiveimpact/cairn-plugins
/plugin install cairn@cairn
```

Commands: `/cairn:status`, `/cairn:free-space [GB]`, `/cairn:projects [idle days]`. The `disk-space` skill steps in when a build fails with "No space left on device".

Cairn decides what AI tools may do. In Cairn › Settings › AI tools choose Off, Ask me each time, or Let them clean safe junk. Only caches and build files that rebuild themselves are ever cleaned.
