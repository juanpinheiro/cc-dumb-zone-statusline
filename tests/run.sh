#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

PASS=0
FAIL=0
TMPDIRS=()

_cleanup() {
  for d in "${TMPDIRS[@]}"; do
    rm -rf "$d"
  done
}
trap _cleanup EXIT

_mktmp() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  printf '%s' "$d"
}

_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

_run_installer() {
  local fake_home="$1"
  shift
  HOME="$fake_home" \
  CLAUDE_CONFIG_DIR="$fake_home/.claude" \
  SOURCE="$REPO_DIR/statusline.sh" \
    bash "$REPO_DIR/install.sh" "$@"
}

# ---------------------------------------------------------------------------
# Scenario 0 — original smoke test
# ---------------------------------------------------------------------------
FAKE_HOME_0="$(_mktmp)"

echo "→ Scenario 0: smoke test (install + statusline output)"

if _run_installer "$FAKE_HOME_0" > "$FAKE_HOME_0/install.log" 2>&1; then
  TARGET_0="$FAKE_HOME_0/.claude/statusline.sh"
  if [ ! -x "$TARGET_0" ]; then
    _fail "scenario 0: $TARGET_0 missing or not executable"
  else
    OUTPUT=$(bash "$TARGET_0" < "$TESTS_DIR/fixtures/hook-input.json")
    NONEMPTY=$(printf '%s\n' "$OUTPUT" | grep -cv '^[[:space:]]*$' || true)
    if [ "$NONEMPTY" -ne 3 ]; then
      _fail "scenario 0: expected 3 non-empty lines, got $NONEMPTY"
      printf '%s\n' "$OUTPUT"
    else
      _pass "scenario 0: statusline produces 3 non-empty lines"
    fi
  fi
else
  _fail "scenario 0: installer exited non-zero"
  cat "$FAKE_HOME_0/install.log"
fi

# ---------------------------------------------------------------------------
# Scenario 1 — no prior settings.json → file created with statusLine
# ---------------------------------------------------------------------------
FAKE_HOME_1="$(_mktmp)"

echo "→ Scenario 1: no prior settings.json"

mkdir -p "$FAKE_HOME_1/.claude"
_run_installer "$FAKE_HOME_1" > "$FAKE_HOME_1/install.log" 2>&1

SETTINGS_1="$FAKE_HOME_1/.claude/settings.json"
EXPECTED_CMD_1="bash $FAKE_HOME_1/.claude/statusline.sh"
ACTUAL_CMD_1="$(jq -r '.statusLine.command' "$SETTINGS_1" 2>/dev/null || true)"

if [ "$ACTUAL_CMD_1" = "$EXPECTED_CMD_1" ]; then
  _pass "scenario 1: settings.json created with correct statusLine.command"
else
  _fail "scenario 1: expected '$EXPECTED_CMD_1', got '$ACTUAL_CMD_1'"
fi

if [ -f "$FAKE_HOME_1/.claude/settings.json.bak" ]; then
  _fail "scenario 1: unexpected .bak file created when no prior settings.json"
else
  _pass "scenario 1: no spurious .bak file"
fi

# ---------------------------------------------------------------------------
# Scenario 2 — prior settings.json with unrelated keys → merge + .bak
# ---------------------------------------------------------------------------
FAKE_HOME_2="$(_mktmp)"

echo "→ Scenario 2: prior settings.json with unrelated keys"

mkdir -p "$FAKE_HOME_2/.claude"
printf '{"foo": "bar"}\n' > "$FAKE_HOME_2/.claude/settings.json"
_run_installer "$FAKE_HOME_2" > "$FAKE_HOME_2/install.log" 2>&1

SETTINGS_2="$FAKE_HOME_2/.claude/settings.json"
FOO_VAL="$(jq -r '.foo' "$SETTINGS_2" 2>/dev/null || true)"
EXPECTED_CMD_2="bash $FAKE_HOME_2/.claude/statusline.sh"
ACTUAL_CMD_2="$(jq -r '.statusLine.command' "$SETTINGS_2" 2>/dev/null || true)"

if [ "$FOO_VAL" = "bar" ] && [ "$ACTUAL_CMD_2" = "$EXPECTED_CMD_2" ]; then
  _pass "scenario 2: existing keys preserved and statusLine merged"
else
  _fail "scenario 2: merge failed — foo='$FOO_VAL', statusLine.command='$ACTUAL_CMD_2'"
fi

if [ -f "$FAKE_HOME_2/.claude/settings.json.bak" ]; then
  BAK_FOO="$(jq -r '.foo' "$FAKE_HOME_2/.claude/settings.json.bak" 2>/dev/null || true)"
  if [ "$BAK_FOO" = "bar" ]; then
    _pass "scenario 2: .bak contains original content"
  else
    _fail "scenario 2: .bak content unexpected, foo='$BAK_FOO'"
  fi
else
  _fail "scenario 2: .bak file not created"
fi

# ---------------------------------------------------------------------------
# Scenario 3 — idempotent re-run → no new .bak
# ---------------------------------------------------------------------------
FAKE_HOME_3="$(_mktmp)"

echo "→ Scenario 3: idempotent re-run"

mkdir -p "$FAKE_HOME_3/.claude"
_run_installer "$FAKE_HOME_3" > "$FAKE_HOME_3/install.log" 2>&1

BAK_3="$FAKE_HOME_3/.claude/settings.json.bak"
[ -f "$BAK_3" ] && rm "$BAK_3"

_run_installer "$FAKE_HOME_3" > "$FAKE_HOME_3/install2.log" 2>&1

EXPECTED_CMD_3="bash $FAKE_HOME_3/.claude/statusline.sh"
ACTUAL_CMD_3="$(jq -r '.statusLine.command' "$FAKE_HOME_3/.claude/settings.json" 2>/dev/null || true)"

if [ "$ACTUAL_CMD_3" = "$EXPECTED_CMD_3" ]; then
  _pass "scenario 3: idempotent re-run preserves correct statusLine.command"
else
  _fail "scenario 3: statusLine.command changed to '$ACTUAL_CMD_3'"
fi

if [ -f "$BAK_3" ]; then
  _fail "scenario 3: .bak created on idempotent re-run"
else
  _pass "scenario 3: no .bak on idempotent re-run"
fi

# ---------------------------------------------------------------------------
# Scenario 4 — foreign statusLine → abort with [patch] error
# ---------------------------------------------------------------------------
FAKE_HOME_4="$(_mktmp)"

echo "→ Scenario 4: foreign statusLine → abort"

mkdir -p "$FAKE_HOME_4/.claude"
printf '{"statusLine": {"type": "command", "command": "bash /some/other/script.sh"}}\n' \
  > "$FAKE_HOME_4/.claude/settings.json"

INSTALL_OUT_4="$FAKE_HOME_4/install.log"
EXIT_CODE_4=0
_run_installer "$FAKE_HOME_4" > "$INSTALL_OUT_4" 2>&1 || EXIT_CODE_4=$?

if [ "$EXIT_CODE_4" -ne 0 ]; then
  _pass "scenario 4: installer exited non-zero on foreign statusLine"
else
  _fail "scenario 4: installer should have exited non-zero but didn't"
fi

if grep -q '\[patch\]' "$INSTALL_OUT_4" && grep -q 'FORCE=1\|--force' "$INSTALL_OUT_4"; then
  _pass "scenario 4: [patch] error with FORCE instructions present"
else
  _fail "scenario 4: expected [patch] tag and FORCE instructions in output"
  cat "$INSTALL_OUT_4"
fi

CURRENT_CMD_4="$(jq -r '.statusLine.command' "$FAKE_HOME_4/.claude/settings.json" 2>/dev/null || true)"
if [ "$CURRENT_CMD_4" = "bash /some/other/script.sh" ]; then
  _pass "scenario 4: settings.json unchanged on abort"
else
  _fail "scenario 4: settings.json was modified despite abort"
fi

# ---------------------------------------------------------------------------
# Scenario 5a — FORCE=1 env var overrides foreign statusLine
# ---------------------------------------------------------------------------
FAKE_HOME_5A="$(_mktmp)"

echo "→ Scenario 5a: FORCE=1 env var overrides foreign statusLine"

mkdir -p "$FAKE_HOME_5A/.claude"
printf '{"statusLine": {"type": "command", "command": "bash /some/other/script.sh"}}\n' \
  > "$FAKE_HOME_5A/.claude/settings.json"

HOME="$FAKE_HOME_5A" \
CLAUDE_CONFIG_DIR="$FAKE_HOME_5A/.claude" \
SOURCE="$REPO_DIR/statusline.sh" \
FORCE=1 \
  bash "$REPO_DIR/install.sh" > "$FAKE_HOME_5A/install.log" 2>&1

EXPECTED_CMD_5A="bash $FAKE_HOME_5A/.claude/statusline.sh"
ACTUAL_CMD_5A="$(jq -r '.statusLine.command' "$FAKE_HOME_5A/.claude/settings.json" 2>/dev/null || true)"

if [ "$ACTUAL_CMD_5A" = "$EXPECTED_CMD_5A" ]; then
  _pass "scenario 5a: FORCE=1 overwrote foreign statusLine"
else
  _fail "scenario 5a: expected '$EXPECTED_CMD_5A', got '$ACTUAL_CMD_5A'"
fi

if [ -f "$FAKE_HOME_5A/.claude/settings.json.bak" ]; then
  BAK_CMD_5A="$(jq -r '.statusLine.command' "$FAKE_HOME_5A/.claude/settings.json.bak" 2>/dev/null || true)"
  if [ "$BAK_CMD_5A" = "bash /some/other/script.sh" ]; then
    _pass "scenario 5a: .bak contains original foreign statusLine"
  else
    _fail "scenario 5a: .bak content unexpected: '$BAK_CMD_5A'"
  fi
else
  _fail "scenario 5a: .bak not created when FORCE=1"
fi

# ---------------------------------------------------------------------------
# Scenario 5b — --force flag overrides foreign statusLine
# ---------------------------------------------------------------------------
FAKE_HOME_5B="$(_mktmp)"

echo "→ Scenario 5b: --force flag overrides foreign statusLine"

mkdir -p "$FAKE_HOME_5B/.claude"
printf '{"statusLine": {"type": "command", "command": "bash /some/other/script.sh"}}\n' \
  > "$FAKE_HOME_5B/.claude/settings.json"

HOME="$FAKE_HOME_5B" \
CLAUDE_CONFIG_DIR="$FAKE_HOME_5B/.claude" \
SOURCE="$REPO_DIR/statusline.sh" \
  bash "$REPO_DIR/install.sh" --force > "$FAKE_HOME_5B/install.log" 2>&1

EXPECTED_CMD_5B="bash $FAKE_HOME_5B/.claude/statusline.sh"
ACTUAL_CMD_5B="$(jq -r '.statusLine.command' "$FAKE_HOME_5B/.claude/settings.json" 2>/dev/null || true)"

if [ "$ACTUAL_CMD_5B" = "$EXPECTED_CMD_5B" ]; then
  _pass "scenario 5b: --force overwrote foreign statusLine"
else
  _fail "scenario 5b: expected '$EXPECTED_CMD_5B', got '$ACTUAL_CMD_5B'"
fi

if [ -f "$FAKE_HOME_5B/.claude/settings.json.bak" ]; then
  BAK_CMD_5B="$(jq -r '.statusLine.command' "$FAKE_HOME_5B/.claude/settings.json.bak" 2>/dev/null || true)"
  if [ "$BAK_CMD_5B" = "bash /some/other/script.sh" ]; then
    _pass "scenario 5b: .bak contains original foreign statusLine"
  else
    _fail "scenario 5b: .bak content unexpected: '$BAK_CMD_5B'"
  fi
else
  _fail "scenario 5b: .bak not created when --force"
fi

# ---------------------------------------------------------------------------
# Unit tests
# ---------------------------------------------------------------------------
echo "→ Running unit tests"
for unit in "$TESTS_DIR/unit"/*.sh; do
  if bash "$unit"; then
    _pass "unit: $(basename "$unit")"
  else
    _fail "unit: $(basename "$unit") exited non-zero"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
