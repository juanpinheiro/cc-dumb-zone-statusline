#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/lib/classify_zone.sh"

pass=0; fail=0

assert_zone() {
  local desc="$1" model_id="$2" model="$3" ctx="$4" want_label="$5"
  local result label
  result=$(classify_zone "$model_id" "$model" "$ctx")
  label=$(printf '%s' "$result" | cut -f5)
  if [ "$label" = "$want_label" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL [$desc]: got '$label', want '$want_label'"
    fail=$((fail + 1))
  fi
}

# 1M profile: T_DRIFT=200000 T_DUMB=400000
assert_zone "1m below drift"    "claude-opus-4-7[1m]" "Opus 4.7" 199999 "🧐 smart zone"
assert_zone "1m at drift"       "claude-opus-4-7[1m]" "Opus 4.7" 200000 "🥱 drifting"
assert_zone "1m below dumb"     "claude-opus-4-7[1m]" "Opus 4.7" 399999 "🥱 drifting"
assert_zone "1m at dumb"        "claude-opus-4-7[1m]" "Opus 4.7" 400000 "🤪 dumb zone"

# Opus profile: T_DRIFT=120000 T_DUMB=160000
assert_zone "opus below drift"  "claude-opus-3" "Claude Opus 3" 119999 "🧐 smart zone"
assert_zone "opus at drift"     "claude-opus-3" "Claude Opus 3" 120000 "🥱 drifting"
assert_zone "opus below dumb"   "claude-opus-3" "Claude Opus 3" 159999 "🥱 drifting"
assert_zone "opus at dumb"      "claude-opus-3" "Claude Opus 3" 160000 "🤪 dumb zone"

# Haiku profile: T_DRIFT=60000 T_DUMB=100000
assert_zone "haiku below drift" "claude-haiku-3" "Claude Haiku 3" 59999 "🧐 smart zone"
assert_zone "haiku at drift"    "claude-haiku-3" "Claude Haiku 3" 60000 "🥱 drifting"
assert_zone "haiku below dumb"  "claude-haiku-3" "Claude Haiku 3" 99999 "🥱 drifting"
assert_zone "haiku at dumb"     "claude-haiku-3" "Claude Haiku 3" 100000 "🤪 dumb zone"

# Default profile: T_DRIFT=80000 T_DUMB=120000
assert_zone "default below drift" "claude-sonnet-4" "Claude Sonnet 4" 79999 "🧐 smart zone"
assert_zone "default at drift"    "claude-sonnet-4" "Claude Sonnet 4" 80000 "🥱 drifting"
assert_zone "default below dumb"  "claude-sonnet-4" "Claude Sonnet 4" 119999 "🥱 drifting"
assert_zone "default at dumb"     "claude-sonnet-4" "Claude Sonnet 4" 120000 "🤪 dumb zone"

echo "zone classifier: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
