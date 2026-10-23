#!/bin/sh
# Assembles the public EmotiveImpact/cairn-plugins repository from these
# folders. Claude Code reads the marketplace at the root; Gemini CLI reads
# gemini-extension.json, GEMINI.md and commands/ at the root.
#
#   sh integrations/publish.sh ../cairn-plugins
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: publish.sh <cairn-plugins checkout>}
[ -d "$out/.git" ] || { echo "$out is not a git checkout" >&2; exit 1; }
rm -rf "$out/.claude-plugin" "$out/plugins" "$out/commands" "$out/gemini-extension.json" "$out/GEMINI.md"
cp -R "$here/claude-code/.claude-plugin" "$here/claude-code/plugins" "$out/"
cp "$here/gemini-extension/gemini-extension.json" "$here/gemini-extension/GEMINI.md" "$out/"
cp -R "$here/gemini-extension/commands" "$out/"
cp "$here/public-README.md" "$out/README.md"
echo "Updated $out. Review with git -C $out status, then commit and push."
