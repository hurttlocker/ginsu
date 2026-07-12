#!/bin/bash
# Ginsu installer — symlink `ginsu` onto your PATH.
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/ginsu"
chmod +x "$src"

# pick a PATH dir we can write to
for dir in "$HOME/.local/bin" "$HOME/.npm-global/bin" "/usr/local/bin"; do
  if [ -d "$dir" ] && [ -w "$dir" ]; then target="$dir/ginsu"; break; fi
done
: "${target:=$HOME/.local/bin/ginsu}"; mkdir -p "$(dirname "$target")"

ln -sfn "$src" "$target"
echo "✓ linked ginsu → $target"

command -v codex >/dev/null || echo "  ⚠ Codex CLI not found on PATH — install it: https://github.com/openai/codex"
command -v python3 >/dev/null || command -v python >/dev/null || echo "  ⚠ python3 not found on PATH — ginsu needs it to render the worker window"
case ":$PATH:" in *":$(dirname "$target"):"*) ;; *) echo "  ⚠ add $(dirname "$target") to your PATH";; esac
echo "  try:  ginsu spawn dev <a-repo>   then   ginsu send dev \"say hi\""
