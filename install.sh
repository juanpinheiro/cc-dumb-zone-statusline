#!/bin/bash
# Install cc-dumb-zone-statusline into ~/.claude
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_URL="https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/statusline.sh"
TARGET="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

echo "→ Downloading statusline.sh to $TARGET"
curl -fsSL "$SCRIPT_URL" -o "$TARGET"
chmod +x "$TARGET"

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠  jq not found. Install it (brew install jq / apt install jq / choco install jq) — required."
fi

echo
echo "Now point Claude Code at the script. Add this to $SETTINGS:"
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
echo "Done. Restart Claude Code to see the statusline."
