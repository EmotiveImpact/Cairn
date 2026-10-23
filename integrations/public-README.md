# Cairn for AI coding tools

[Cairn](https://github.com/EmotiveImpact) is a Mac app that finds the junk in your coding projects: `node_modules`, Xcode `DerivedData`, Rust `target`, package-manager caches and Docker build cache. These add-ons let your AI coding tool ask Cairn what is filling your disk and, if you allow it, free the space for you.

Requires the Cairn app in `/Applications`.

## Claude Code

```text
/plugin marketplace add EmotiveImpact/cairn-plugins
/plugin install cairn@cairn
```

## Gemini CLI

```sh
gemini extensions install https://github.com/EmotiveImpact/cairn-plugins
```

## Commands

- `/cairn:status`: free space and the biggest things you could safely free
- `/cairn:free-space [GB]`: plan a cleanup, show it, and run it once you agree
- `/cairn:projects [idle days]`: clear rebuildable build output from projects you have not touched in a while

When a build fails with "No space left on device", the agent is told to use Cairn rather than deleting files itself.

## You stay in charge

In Cairn › Settings › AI tools choose **Off** (the default), **Ask me each time**, or **Let them clean safe junk**. Only caches and build files that rebuild themselves are ever cleaned. Your files, AI chats and the Trash are never touched, and every clean leaves a receipt in Cairn's Activity.

This repository is generated from the Cairn source; changes made here directly will be overwritten.
