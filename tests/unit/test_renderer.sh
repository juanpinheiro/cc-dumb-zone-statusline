#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$SCRIPT_DIR/lib/render_lines.sh"

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

pass=0; fail=0

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | LC_ALL=C grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    echo "FAIL [$desc]: expected to find '$needle' in output"
    echo "  output was: $haystack"
    fail=$((fail + 1))
  fi
}

run_render() {
  local GREEN='\033[38;5;158m'; local MINT='\033[38;5;150m'
  local YELLOW='\033[38;5;215m'; local RED='\033[38;5;203m'
  local BLUE='\033[38;5;117m'; local PURPLE='\033[38;5;147m'
  local GOLD='\033[38;5;222m'; local BURN='\033[38;5;220m'
  local LAV='\033[38;5;189m'; local DIM='\033[2m'; local RESET='\033[0m'

  ZONE_COLOR="$1"; ZONE_LABEL="$2"; CTX_FMT="$3"; WIN_FMT="$4"
  WIN_PCT="$5"; BAR="$6"; SESSION_FMT="$7"; CWD="$8"; GIT_BRANCH="$9"
  MODEL="${10}"; CC_VERSION="${11}"; COST_FMT="${12}"; BURN_RATE="${13}"; TPM="${14}"

  LINE1="${ZONE_COLOR}${ZONE_LABEL}${RESET} │ ${ZONE_COLOR}${CTX_FMT}/${WIN_FMT} (${WIN_PCT}%)${RESET} ${BAR} │ ⏱ ${SESSION_FMT}"
  LINE2="📁 ${BLUE}${CWD:-?}${RESET}"
  [ -n "$GIT_BRANCH" ] && LINE2="${LINE2}  🌿 ${MINT}${GIT_BRANCH}${RESET}"
  LINE2="${LINE2}  🤖 ${PURPLE}${MODEL}${RESET}"
  [ -n "$CC_VERSION" ] && [ "$CC_VERSION" != "null" ] && LINE2="${LINE2}  ${DIM}v${CC_VERSION}${RESET}"
  LINE3="💰 ${GOLD}\$${COST_FMT}${RESET}"
  [ -n "$BURN_RATE" ] && LINE3="${LINE3} ${DIM}(${RESET}${BURN}\$${BURN_RATE}/h${RESET}${DIM})${RESET}"
  [ -n "$TPM" ]       && LINE3="${LINE3}  📊 ${LAV}${TPM} tpm${RESET}"

  render_lines | strip_ansi
}

# snapshot 1: smart zone, no branch, no burn rate, no tpm
OUT=$(run_render '\033[38;5;158m' '🧐 smart zone' '26k' '1M' '2' '' '10m' \
  'myproject' '' 'Claude Sonnet' '1.2.3' '0.42' '' '')
assert_contains "snap1 zone label"  "$OUT" "smart zone"
assert_contains "snap1 ctx"         "$OUT" "26k/1M (2%)"
assert_contains "snap1 timer"       "$OUT" "10m"
assert_contains "snap1 cwd"         "$OUT" "myproject"
assert_contains "snap1 model"       "$OUT" "Claude Sonnet"
assert_contains "snap1 version"     "$OUT" "v1.2.3"
assert_contains "snap1 cost"        "$OUT" '$0.42'

# snapshot 2: dumb zone, with branch, burn rate, tpm
OUT=$(run_render '\033[38;5;203m' '🤪 dumb zone' '150k' '200k' '75' '' '2h30m' \
  'bigproject' 'main' 'Claude Opus' '' '1.50' '2.52' '5800')
assert_contains "snap2 zone label"  "$OUT" "dumb zone"
assert_contains "snap2 ctx"         "$OUT" "150k/200k (75%)"
assert_contains "snap2 timer"       "$OUT" "2h30m"
assert_contains "snap2 cwd"         "$OUT" "bigproject"
assert_contains "snap2 branch"      "$OUT" "main"
assert_contains "snap2 model"       "$OUT" "Claude Opus"
assert_contains "snap2 cost"        "$OUT" '$1.50'
assert_contains "snap2 burn"        "$OUT" '$2.52/h'
assert_contains "snap2 tpm"         "$OUT" "5800 tpm"

# snapshot 3: drifting, no version (null)
OUT=$(run_render '\033[38;5;215m' '🥱 drifting' '90k' '200k' '45' '' '-' \
  'proj' '' 'Claude Haiku' 'null' '0.05' '' '')
assert_contains "snap3 zone label"  "$OUT" "drifting"
assert_contains "snap3 ctx"         "$OUT" "90k/200k (45%)"
assert_contains "snap3 no version"  "$(echo "$OUT" | LC_ALL=C grep -v 'vnull' || true)" ""
assert_contains "snap3 cost"        "$OUT" '$0.05'

echo "renderer: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
