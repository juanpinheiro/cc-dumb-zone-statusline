#!/bin/bash
# validate_install.sh — two-stage post-install validator
# Sourced by install.sh and by tests/run.sh scenarios 7a/7b/7c.
#
# Usage:
#   validate_install <settings_path> <fixture_path>
#
# Returns 0 on success, non-zero on failure (with [smoke-test] or
# [runtime-check] tagged messages on stderr).

validate_install() {
  local settings="$1"
  local fixture="$2"

  # ---- Stage 1: Smoke test ------------------------------------------------
  # Read the resolved command from settings.json and pipe the fixture through
  # it. Expect exactly 3 non-empty lines of output.
  local cmd
  cmd="$(jq -r '.statusLine.command // empty' "$settings" 2>/dev/null || true)"
  if [ -z "$cmd" ]; then
    echo "[smoke-test] ERROR: could not read statusLine.command from $settings" >&2
    return 1
  fi

  local smoke_out
  local smoke_exit
  if [ -n "${MSYSTEM:-}" ]; then
    smoke_out="$(cmd.exe //c "$cmd" < "$fixture" 2>&1)"
    smoke_exit=$?
  else
    smoke_out="$(bash -c "$cmd" < "$fixture" 2>&1)"
    smoke_exit=$?
  fi

  local nonempty
  nonempty="$(printf '%s\n' "$smoke_out" | grep -cv '^[[:space:]]*$' || true)"

  if [ "$smoke_exit" -ne 0 ] || [ "$nonempty" -ne 3 ]; then
    echo "[smoke-test] ERROR: expected 3 non-empty output lines, got $nonempty (exit $smoke_exit)" >&2
    echo "[smoke-test] Command: $cmd" >&2
    echo "[smoke-test] Output was:" >&2
    printf '%s\n' "$smoke_out" | sed 's/^/[smoke-test]   /' >&2
    return 1
  fi

  # ---- Stage 2: Settings revalidation -------------------------------------
  # Re-read settings from disk; verify JSON is valid and key resolves.
  if ! jq -e '.statusLine.command' "$settings" >/dev/null 2>&1; then
    echo "[runtime-check] ERROR: $settings is malformed or missing statusLine.command" >&2
    return 1
  fi

  local script_path
  local raw_cmd
  raw_cmd="$(jq -r '.statusLine.command' "$settings")"
  # Handle two command forms:
  #   bash /path/to/statusline.sh          (non-Windows or bash-on-PATH)
  #   "/path/to/bash.exe" "/path/to/statusline.sh"  (Windows absolute-path form)
  if printf '%s' "$raw_cmd" | grep -q '^"'; then
    script_path="$(printf '%s' "$raw_cmd" | sed 's/^"[^"]*" "//' | sed 's/"$//')"
  else
    script_path="$(printf '%s' "$raw_cmd" | sed 's/^bash //')"
  fi

  if [ -z "$script_path" ]; then
    echo "[runtime-check] ERROR: could not parse script path from statusLine.command in $settings" >&2
    return 1
  fi

  if [ ! -f "$script_path" ]; then
    echo "[runtime-check] ERROR: script path does not exist: $script_path" >&2
    echo "[runtime-check] (parsed from statusLine.command in $settings)" >&2
    return 1
  fi

  if [ ! -x "$script_path" ]; then
    echo "[runtime-check] ERROR: script exists but is not executable: $script_path" >&2
    echo "[runtime-check] (parsed from statusLine.command in $settings)" >&2
    return 1
  fi

  return 0
}
