#!/bin/bash
# Install cc-dumb-zone-statusline into ~/.claude
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_URL="https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/statusline.sh"
TARGET="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

if [ -n "${SOURCE:-}" ]; then
  if [ ! -f "$SOURCE" ]; then
    echo "[download] SOURCE='$SOURCE' is not a readable file" >&2
    exit 1
  fi
  echo "[download] Copying statusline.sh from $SOURCE to $TARGET"
  cp "$SOURCE" "$TARGET"
else
  echo "[download] Fetching statusline.sh to $TARGET"
  if ! curl -fsSL "$SCRIPT_URL" -o "$TARGET"; then
    echo "[download] Failed to fetch $SCRIPT_URL" >&2
    exit 1
  fi
fi
chmod +x "$TARGET"

if ! command -v jq >/dev/null 2>&1; then
  echo "[jq-check] jq not found — install it (brew install jq / apt install jq / winget install jqlang.jq). Required at runtime." >&2
fi

echo
echo "[install] Now point Claude Code at the script. Add this to $SETTINGS:"
echo
cat <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "bash $TARGET",
    "padding": 0
  }
}
EOF
echo
echo "[install] Done. Restart Claude Code to see the statusline."
