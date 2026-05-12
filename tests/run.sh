#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

PASS=0
FAIL=0
TMPDIRS=()

_cleanup() {
  for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do
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
# Scenario 6 — jq missing → precheck aborts, no files written
# ---------------------------------------------------------------------------
FAKE_HOME_6="$(_mktmp)"

echo "→ Scenario 6: jq missing → precheck aborts"

SHIM_BIN_6="$FAKE_HOME_6/shim-bin"
mkdir -p "$SHIM_BIN_6"

# install.sh's jq precheck only invokes `uname` before aborting; the test
# runner also needs to find `bash` to launch install.sh. Wrapping just those
# two is enough to give the installer a jq-free PATH without iterating every
# executable on the host.
for cmd in bash uname; do
  real="$(command -v "$cmd" 2>/dev/null || true)"
  [ -z "$real" ] && continue
  cat > "$SHIM_BIN_6/$cmd" <<EOF
#!/bin/sh
exec "$real" "\$@"
EOF
  chmod +x "$SHIM_BIN_6/$cmd"
done
PATH_NO_JQ="$SHIM_BIN_6"

INSTALL_ERR_6="$FAKE_HOME_6/install.err"
EXIT_CODE_6=0
HOME="$FAKE_HOME_6" \
CLAUDE_CONFIG_DIR="$FAKE_HOME_6/.claude" \
SOURCE="$REPO_DIR/statusline.sh" \
PATH="$PATH_NO_JQ" \
  bash "$REPO_DIR/install.sh" > "$FAKE_HOME_6/install.out" 2>"$INSTALL_ERR_6" || EXIT_CODE_6=$?

if [ "$EXIT_CODE_6" -ne 0 ]; then
  _pass "scenario 6: installer exited non-zero when jq missing"
else
  _fail "scenario 6: installer should have exited non-zero but didn't"
fi

if grep -q '\[jq-check\]' "$INSTALL_ERR_6"; then
  _pass "scenario 6: stderr contains [jq-check]"
else
  _fail "scenario 6: stderr missing [jq-check]"
  cat "$INSTALL_ERR_6"
fi

if grep -qE 'brew install jq|apt|dnf|pacman|apk|winget' "$INSTALL_ERR_6"; then
  _pass "scenario 6: stderr contains an install command hint"
else
  _fail "scenario 6: stderr missing install command hint"
  cat "$INSTALL_ERR_6"
fi

if [ ! -f "$FAKE_HOME_6/.claude/statusline.sh" ]; then
  _pass "scenario 6: no statusline.sh written on abort"
else
  _fail "scenario 6: statusline.sh was created despite precheck failure"
fi

# ---------------------------------------------------------------------------
# Scenario 7a — smoke-test failure: statusline stub emits no output
# ---------------------------------------------------------------------------
# Strategy: set SOURCE= to a stub statusline that exits 0 but emits nothing.
# The installer installs that stub, then runs validate_install → smoke-test
# expects 3 non-empty lines but gets 0 → should exit non-zero with [smoke-test].
FAKE_HOME_7A="$(_mktmp)"

echo "→ Scenario 7a: smoke-test failure (stub emits no output)"

STUB_DIR_7A="$(_mktmp)"
STUB_SH_7A="$STUB_DIR_7A/statusline.sh"
mkdir -p "$STUB_DIR_7A/lib"
cat > "$STUB_SH_7A" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB_SH_7A"

# Provide stub lib scripts that are also no-ops (install.sh copies lib/*.sh).
for f in parse_hook_input.sh classify_zone.sh render_lines.sh validate_install.sh; do
  if [ -f "$REPO_DIR/lib/$f" ]; then
    cp "$REPO_DIR/lib/$f" "$STUB_DIR_7A/lib/$f"
  else
    printf '#!/bin/bash\n' > "$STUB_DIR_7A/lib/$f"
    chmod +x "$STUB_DIR_7A/lib/$f"
  fi
done
# Overwrite validate_install.sh with the real one (we want the real validator).
cp "$REPO_DIR/lib/validate_install.sh" "$STUB_DIR_7A/lib/validate_install.sh"

INSTALL_OUT_7A="$FAKE_HOME_7A/install.log"
EXIT_CODE_7A=0
HOME="$FAKE_HOME_7A" \
CLAUDE_CONFIG_DIR="$FAKE_HOME_7A/.claude" \
SOURCE="$STUB_SH_7A" \
TESTS_DIR_FOR_VALIDATOR="$TESTS_DIR/fixtures/hook-input.json" \
  bash "$REPO_DIR/install.sh" > "$INSTALL_OUT_7A" 2>&1 || EXIT_CODE_7A=$?

if [ "$EXIT_CODE_7A" -ne 0 ]; then
  _pass "scenario 7a: installer exited non-zero on empty statusline output"
else
  _fail "scenario 7a: installer should have exited non-zero but didn't"
  cat "$INSTALL_OUT_7A"
fi

if grep -q '\[smoke-test\]' "$INSTALL_OUT_7A"; then
  _pass "scenario 7a: output contains [smoke-test] tag"
else
  _fail "scenario 7a: expected [smoke-test] tag in output"
  cat "$INSTALL_OUT_7A"
fi

# ---------------------------------------------------------------------------
# Scenario 7b — runtime-check failure: command path does not exist
# ---------------------------------------------------------------------------
# Strategy: craft a settings.json whose command produces 3 lines (Stage 1
# passes) but whose parsed path — everything after "bash " — does not exist
# as a file (Stage 2 fails with [runtime-check]).
# Command: "bash -c 'printf \"line1\nline2\nline3\n\"'" passes Stage 1
# (3 non-empty lines), but "-c 'printf...'" is not a real file → Stage 2 fails.
FAKE_HOME_7B="$(_mktmp)"

echo "→ Scenario 7b: runtime-check failure (script path does not exist)"

SETTINGS_7B="$FAKE_HOME_7B/settings.json"
FIXTURE_7B="$TESTS_DIR/fixtures/hook-input.json"
# Use jq to write valid JSON; the command passes Stage 1 (3 non-empty lines)
# but the parsed script path ("-c \"printf...\"") does not exist → Stage 2 fails.
jq -n '{"statusLine":{"type":"command","command":"bash -c \"printf \\\"line1\\\\nline2\\\\nline3\\\\n\\\"\"","padding":0}}' \
  > "$SETTINGS_7B"

# Source the validator and call it directly.
# We must wrap in a subshell to avoid `set -e` killing the test runner on failure.
VALIDATE_OUT_7B="$FAKE_HOME_7B/validate.log"
EXIT_CODE_7B=0
(
  # shellcheck source=/dev/null
  source "$REPO_DIR/lib/validate_install.sh"
  validate_install "$SETTINGS_7B" "$FIXTURE_7B"
) > "$VALIDATE_OUT_7B" 2>&1 || EXIT_CODE_7B=$?

if [ "$EXIT_CODE_7B" -ne 0 ]; then
  _pass "scenario 7b: validate_install exited non-zero on missing script path"
else
  _fail "scenario 7b: validate_install should have exited non-zero but didn't"
  cat "$VALIDATE_OUT_7B"
fi

if grep -q '\[runtime-check\]' "$VALIDATE_OUT_7B"; then
  _pass "scenario 7b: output contains [runtime-check] tag"
else
  _fail "scenario 7b: expected [runtime-check] tag in output"
  cat "$VALIDATE_OUT_7B"
fi

# ---------------------------------------------------------------------------
# Scenario 7c — runtime-check failure: settings.json is malformed JSON
# ---------------------------------------------------------------------------
# Strategy: source validate_install.sh directly with a malformed settings.json.
FAKE_HOME_7C="$(_mktmp)"

echo "→ Scenario 7c: runtime-check failure (malformed settings.json)"

SETTINGS_7C="$FAKE_HOME_7C/settings.json"
FIXTURE_7C="$TESTS_DIR/fixtures/hook-input.json"
printf 'THIS IS NOT JSON\n' > "$SETTINGS_7C"

VALIDATE_OUT_7C="$FAKE_HOME_7C/validate.log"
EXIT_CODE_7C=0
(
  # shellcheck source=/dev/null
  source "$REPO_DIR/lib/validate_install.sh"
  validate_install "$SETTINGS_7C" "$FIXTURE_7C"
) > "$VALIDATE_OUT_7C" 2>&1 || EXIT_CODE_7C=$?

if [ "$EXIT_CODE_7C" -ne 0 ]; then
  _pass "scenario 7c: validate_install exited non-zero on malformed JSON"
else
  _fail "scenario 7c: validate_install should have exited non-zero but didn't"
  cat "$VALIDATE_OUT_7C"
fi

if grep -q '\[smoke-test\]\|\[runtime-check\]' "$VALIDATE_OUT_7C"; then
  _pass "scenario 7c: output contains expected error tag"
else
  _fail "scenario 7c: expected [smoke-test] or [runtime-check] tag in output"
  cat "$VALIDATE_OUT_7C"
fi

# ---------------------------------------------------------------------------
# Scenario 8 — resolve_release_ref helper
# ---------------------------------------------------------------------------
echo "→ Scenario 8: resolve_release_ref"

# shellcheck source=/dev/null
source "$REPO_DIR/lib/resolve_release.sh"

# 8a-i: VERSION= env var → returned as-is, no curl needed
RESULT_8AI="$(VERSION="v1.2.3" resolve_release_ref "https://this-should-not-be-called.invalid")"
if [ "$RESULT_8AI" = "v1.2.3" ]; then
  _pass "scenario 8a-i: VERSION= env var returned verbatim"
else
  _fail "scenario 8a-i: expected 'v1.2.3', got '$RESULT_8AI'"
fi

# Helper: create a shim bin dir with a curl that emits a fixed response body.
_make_curl_shim() {
  local shim_dir="$1"
  local response_body="$2"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/curl" <<EOF
#!/bin/bash
printf '%s' '${response_body}'
exit 0
EOF
  chmod +x "$shim_dir/curl"
}

# 8a-ii: API returns empty/no tag_name → falls back to "main" with warning
SHIM_8AII="$(_mktmp)"
_make_curl_shim "$SHIM_8AII" '{}'
WARN_8AII_FILE="$(_mktmp)/warn.txt"
RESULT_8AII="$(VERSION="" PATH="$SHIM_8AII:$PATH" resolve_release_ref "https://fake.invalid" 2>"$WARN_8AII_FILE" || true)"
if [ "$RESULT_8AII" = "main" ]; then
  _pass "scenario 8a-ii: no tag_name → falls back to main"
else
  _fail "scenario 8a-ii: expected 'main', got '$RESULT_8AII'"
fi
if grep -q '\[download\]' "$WARN_8AII_FILE"; then
  _pass "scenario 8a-ii: fallback warning printed"
else
  _fail "scenario 8a-ii: expected [download] warning on fallback"
fi

# 8a-iii: API returns a tag_name → that tag is returned
SHIM_8AIII="$(_mktmp)"
_make_curl_shim "$SHIM_8AIII" '{"tag_name": "v9.9.9"}'
RESULT_8AIII="$(VERSION="" PATH="$SHIM_8AIII:$PATH" resolve_release_ref "https://fake.invalid")"
if [ "$RESULT_8AIII" = "v9.9.9" ]; then
  _pass "scenario 8a-iii: tag_name from API response returned"
else
  _fail "scenario 8a-iii: expected 'v9.9.9', got '$RESULT_8AIII'"
fi

# 8b — live API (only in CI with network, skip gracefully otherwise)
if [ "${CI:-}" = "true" ]; then
  echo "→ Scenario 8b: live GitHub releases API"
  LIVE_REF="$(VERSION="" resolve_release_ref \
    "https://api.github.com/repos/juanpinheiro/cc-dumb-zone-statusline/releases/latest" \
    2>/dev/null || true)"
  if [ -n "$LIVE_REF" ]; then
    _pass "scenario 8b: live API returned non-empty ref ('$LIVE_REF')"
  else
    _fail "scenario 8b: live API returned empty ref"
  fi
else
  echo "  (scenario 8b skipped — not in CI)"
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
