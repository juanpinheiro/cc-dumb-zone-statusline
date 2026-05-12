#!/bin/bash
# Install cc-dumb-zone-statusline into ~/.claude
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO_URL="https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main"
TARGET="$CLAUDE_DIR/statusline.sh"
LIB_DIR="$CLAUDE_DIR/lib"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR" "$LIB_DIR"

if [ -n "${SOURCE:-}" ]; then
  if [ ! -f "$SOURCE" ]; then
    echo "[download] SOURCE='$SOURCE' is not a readable file" >&2
    exit 1
  fi
  SOURCE_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  echo "[download] Copying statusline.sh from $SOURCE to $TARGET"
  cp "$SOURCE" "$TARGET"
  echo "[download] Copying lib/ from $SOURCE_DIR/lib to $LIB_DIR"
  cp "$SOURCE_DIR/lib/"*.sh "$LIB_DIR/"
else
  echo "[download] Fetching statusline.sh to $TARGET"
  if ! curl -fsSL "$REPO_URL/statusline.sh" -o "$TARGET"; then
    echo "[download] Failed to fetch statusline.sh" >&2
    exit 1
  fi
  echo "[download] Fetching lib/ scripts"
  for f in parse_hook_input.sh classify_zone.sh render_lines.sh; do
    if ! curl -fsSL "$REPO_URL/lib/$f" -o "$LIB_DIR/$f"; then
      echo "[download] Failed to fetch lib/$f" >&2
      exit 1
    fi
  done
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
