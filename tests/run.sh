#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT

echo "→ Installing into fake HOME: $FAKE_HOME"
HOME="$FAKE_HOME" \
CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
SOURCE="$REPO_DIR/statusline.sh" \
  bash "$REPO_DIR/install.sh" > "$FAKE_HOME/install.log" 2>&1 || {
    echo "FAIL: installer exited non-zero"
    cat "$FAKE_HOME/install.log"
    exit 1
  }

TARGET="$FAKE_HOME/.claude/statusline.sh"
if [ ! -x "$TARGET" ]; then
  echo "FAIL: $TARGET missing or not executable"
  exit 1
fi

echo "→ Smoke-testing statusline output"
OUTPUT=$(bash "$TARGET" < "$TESTS_DIR/fixtures/hook-input.json")
NONEMPTY=$(printf '%s\n' "$OUTPUT" | grep -cv '^[[:space:]]*$' || true)

if [ "$NONEMPTY" -ne 3 ]; then
  echo "FAIL: expected 3 non-empty lines, got $NONEMPTY"
  echo "--- output ---"
  printf '%s\n' "$OUTPUT"
  echo "--------------"
  exit 1
fi

echo "OK: statusline produces 3 non-empty lines"
