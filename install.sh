#!/bin/bash
# Install cc-dumb-zone-statusline into ~/.claude
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO_URL="https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main"
TARGET="$CLAUDE_DIR/statusline.sh"
LIB_DIR="$CLAUDE_DIR/lib"
SETTINGS="$CLAUDE_DIR/settings.json"
SETTINGS_BAK="$CLAUDE_DIR/settings.json.bak"
SETTINGS_TMP="$CLAUDE_DIR/settings.json.tmp"

_FORCE_ENV="${FORCE:-0}"
FORCE=0
[ "$_FORCE_ENV" = "1" ] && FORCE=1
for arg in "$@"; do
  [ "$arg" = "--force" ] && FORCE=1
done

_jq_install_hint() {
  local os
  os="$(uname -s 2>/dev/null || true)"
  if [ "$os" = "Darwin" ]; then
    printf 'brew install jq'
    return
  fi
  if [ -n "${MSYSTEM:-}" ]; then
    printf 'winget install jqlang.jq'
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt-get install -y jq'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf install -y jq'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman -S jq'
  elif command -v apk >/dev/null 2>&1; then
    printf 'apk add jq'
  else
    printf 'apt-get install -y jq  # or: dnf install -y jq / pacman -S jq / apk add jq'
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "[jq-check] jq not found. Install with:" >&2
  echo "  $(_jq_install_hint)" >&2
  echo "[jq-check] Aborting." >&2
  exit 1
fi

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

DESIRED_COMMAND="bash $TARGET"
NEW_STATUSLINE='{
  "type": "command",
  "command": "bash '"$TARGET"'",
  "padding": 0
}'

_write_settings() {
  local json="$1"
  printf '%s\n' "$json" > "$SETTINGS_TMP"
  mv "$SETTINGS_TMP" "$SETTINGS"
}

_normalize_cmd() {
  printf '%s' "$1" | tr -s ' '
}

if [ ! -f "$SETTINGS" ]; then
  _write_settings "$(jq -n --argjson sl "$NEW_STATUSLINE" '{"statusLine": $sl}')"
  echo "[patch] Created $SETTINGS with statusLine."
else
  EXISTING_CMD="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)"

  if [ -z "$EXISTING_CMD" ]; then
    cp "$SETTINGS" "$SETTINGS_BAK"
    echo "[patch] Saved backup to $SETTINGS_BAK"
    _write_settings "$(jq --argjson sl "$NEW_STATUSLINE" '. + {"statusLine": $sl}' "$SETTINGS")"
    echo "[patch] Merged statusLine into $SETTINGS."
  else
    NORM_EXISTING="$(_normalize_cmd "$EXISTING_CMD")"
    NORM_DESIRED="$(_normalize_cmd "$DESIRED_COMMAND")"

    if [ "$NORM_EXISTING" = "$NORM_DESIRED" ]; then
      _write_settings "$(jq --argjson sl "$NEW_STATUSLINE" '. + {"statusLine": $sl}' "$SETTINGS")"
      echo "[patch] statusLine already points to our path — updated in place (no backup needed)."
    else
      if [ "$FORCE" = "1" ]; then
        cp "$SETTINGS" "$SETTINGS_BAK"
        echo "[patch] Saved backup to $SETTINGS_BAK"
        _write_settings "$(jq --argjson sl "$NEW_STATUSLINE" '. + {"statusLine": $sl}' "$SETTINGS")"
        echo "[patch] Overwrote existing statusLine in $SETTINGS."
      else
        echo "[patch] ERROR: $SETTINGS already has statusLine.command pointing elsewhere:" >&2
        echo "[patch]   found:    $EXISTING_CMD" >&2
        echo "[patch]   expected: $DESIRED_COMMAND" >&2
        echo "[patch] To overwrite, re-run with FORCE=1 or pass --force" >&2
        exit 1
      fi
    fi
  fi
fi

echo "[install] Done. Restart Claude Code to see the statusline."
