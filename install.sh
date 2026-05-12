#!/bin/bash
# Install cc-dumb-zone-statusline into ~/.claude
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
_RELEASES_API="https://api.github.com/repos/juanpinheiro/cc-dumb-zone-statusline/releases/latest"
TARGET="$CLAUDE_DIR/statusline.sh"
LIB_DIR="$CLAUDE_DIR/lib"
SETTINGS="$CLAUDE_DIR/settings.json"
SETTINGS_BAK="$CLAUDE_DIR/settings.json.bak"
SETTINGS_TMP="$CLAUDE_DIR/settings.json.tmp"

# Source the validator (supports both local SOURCE= runs and post-download runs).
# When SOURCE= is set, we load it from the repo's lib/ alongside SOURCE.
# Otherwise it was downloaded alongside statusline.sh into $LIB_DIR.
_resolve_bash_command() {
  local target="$1"
  local is_windows=0
  if [ -n "${MSYSTEM:-}" ]; then
    is_windows=1
  else
    local uname_s
    uname_s="$(uname -s 2>/dev/null || true)"
    case "$uname_s" in
      MINGW*|MSYS*) is_windows=1 ;;
    esac
  fi

  if [ "$is_windows" -eq 0 ]; then
    printf 'bash %s' "$target"
    return 0
  fi

  if cmd.exe //c "bash --version" >/dev/null 2>&1; then
    printf 'bash %s' "$target"
    return 0
  fi

  local bash_path
  if [ -n "${BASH:-}" ]; then
    bash_path="$BASH"
  else
    bash_path="$(command -v bash 2>/dev/null || true)"
  fi
  echo "[runtime-check] WARNING: bash not on cmd.exe PATH, using absolute path: $bash_path" >&2
  printf '"%s" "%s"' "$bash_path" "$target"
}

_load_validator() {
  local validator_path
  if [ -n "${SOURCE:-}" ]; then
    local src_dir
    src_dir="$(cd "$(dirname "$SOURCE")" && pwd)"
    validator_path="$src_dir/lib/validate_install.sh"
  else
    validator_path="$LIB_DIR/validate_install.sh"
  fi
  # shellcheck source=/dev/null
  source "$validator_path"
}

_FORCE_ENV="${FORCE:-0}"
FORCE=0
[ "$_FORCE_ENV" = "1" ] && FORCE=1
UNINSTALL=0
for arg in "$@"; do
  [ "$arg" = "--force" ] && FORCE=1
  [ "$arg" = "--uninstall" ] && UNINSTALL=1
done

if [ "$UNINSTALL" = "1" ] && [ "$FORCE" = "1" ]; then
  echo "[uninstall] ERROR: --uninstall and --force are mutually exclusive" >&2
  exit 1
fi

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

_write_settings() {
  local json="$1"
  printf '%s\n' "$json" > "$SETTINGS_TMP"
  mv "$SETTINGS_TMP" "$SETTINGS"
}

_normalize_cmd() {
  printf '%s' "$1" | tr -s ' '
}

# ---------------------------------------------------------------------------
# Uninstall mode
# ---------------------------------------------------------------------------
if [ "$UNINSTALL" = "1" ]; then
  if [ ! -f "$SETTINGS" ]; then
    echo "[uninstall] No $SETTINGS to clean up."
  else
    EXISTING_CMD="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)"
    DESIRED_COMMAND="$(_resolve_bash_command "$TARGET")"

    if [ -z "$EXISTING_CMD" ]; then
      echo "[uninstall] No statusLine in $SETTINGS — nothing to remove."
    else
      NORM_EXISTING="$(_normalize_cmd "$EXISTING_CMD")"
      NORM_DESIRED="$(_normalize_cmd "$DESIRED_COMMAND")"

      if [ "$NORM_EXISTING" = "$NORM_DESIRED" ]; then
        cp "$SETTINGS" "$SETTINGS_BAK"
        _write_settings "$(jq 'del(.statusLine)' "$SETTINGS_BAK")"
        echo "[uninstall] Removed statusLine from $SETTINGS (backup at $SETTINGS_BAK)."
      else
        echo "[uninstall] WARNING: statusLine in $SETTINGS points to $EXISTING_CMD — leaving it alone."
      fi
    fi
  fi

  if [ -f "$TARGET" ]; then
    rm -f "$TARGET"
    echo "[uninstall] Removed $TARGET."
  else
    echo "[uninstall] $TARGET not found — nothing to remove."
  fi

  if [ -d "$LIB_DIR" ]; then
    rm -rf "$LIB_DIR"
    echo "[uninstall] Removed $LIB_DIR."
  else
    echo "[uninstall] $LIB_DIR not found — nothing to remove."
  fi

  echo "[uninstall] Done."
  exit 0
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
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/resolve_release.sh"
  _RESOLVED_REF="$(resolve_release_ref "$_RELEASES_API")"
  echo "[download] Installing from ref: $_RESOLVED_REF"
  REPO_URL="https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/$_RESOLVED_REF"
  echo "[download] Fetching statusline.sh to $TARGET"
  if ! curl -fsSL "$REPO_URL/statusline.sh" -o "$TARGET"; then
    echo "[download] Failed to fetch statusline.sh" >&2
    exit 1
  fi
  echo "[download] Fetching lib/ scripts"
  for f in parse_hook_input.sh classify_zone.sh render_lines.sh validate_install.sh resolve_release.sh; do
    if ! curl -fsSL "$REPO_URL/lib/$f" -o "$LIB_DIR/$f"; then
      echo "[download] Failed to fetch lib/$f" >&2
      exit 1
    fi
  done
fi
chmod +x "$TARGET"

_load_validator

DESIRED_COMMAND="$(_resolve_bash_command "$TARGET")"
NEW_STATUSLINE="$(jq -n --arg cmd "$DESIRED_COMMAND" '{"type":"command","command":$cmd,"padding":0}')"

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

FIXTURE_PATH="${TESTS_DIR_FOR_VALIDATOR:-}"
if [ -z "$FIXTURE_PATH" ]; then
  # Locate the fixture relative to this script (works for local runs).
  _SCRIPT_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _FIXTURE_CANDIDATE="$_SCRIPT_SELF/tests/fixtures/hook-input.json"
  if [ -f "$_FIXTURE_CANDIDATE" ]; then
    FIXTURE_PATH="$_FIXTURE_CANDIDATE"
  else
    # Write a minimal inline fixture to a tempfile.
    _FIXTURE_TMP="$(mktemp /tmp/hook-input-XXXXXX.json)"
    cat > "$_FIXTURE_TMP" <<'FIXTURE_EOF'
{
  "model": {"display_name": "Opus 4.7", "id": "claude-opus-4-7"},
  "version": "1.0.0",
  "transcript_path": "",
  "workspace": {"current_dir": "/tmp"},
  "cwd": "/tmp",
  "context_window": {
    "used_percentage": 12.5,
    "current_usage": {"input_tokens": 5000, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
    "total_input_tokens": 50000,
    "total_output_tokens": 8000
  },
  "cost": {"total_cost_usd": 0.42, "total_duration_ms": 600000}
}
FIXTURE_EOF
    FIXTURE_PATH="$_FIXTURE_TMP"
    trap 'rm -f "$_FIXTURE_TMP"' EXIT
  fi
fi

echo "[install] Running post-install validation..."
if ! validate_install "$SETTINGS" "$FIXTURE_PATH"; then
  echo "[install] Validation failed. Check errors above." >&2
  exit 1
fi

echo "[install] Done. Restart Claude Code to see the statusline."
