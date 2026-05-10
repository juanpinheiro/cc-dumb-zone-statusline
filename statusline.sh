#!/bin/bash
input=$(cat)

# ---- core extraction ----
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
MODEL_ID=$(echo "$input" | jq -r '.model.id // ""')
CC_VERSION=$(echo "$input" | jq -r '.version // ""')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // ""')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
CWD_REAL="$CWD"
CWD=$(basename "$CWD")

# ---- context ----
CTX_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_PCT=${CTX_PCT:-0}
CTX_TOKENS=$(echo "$input" | jq -r '((.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0))')

# ---- I/O totals ----
IN_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
CACHED_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
IN_TOKENS=${IN_TOKENS:-0}
OUT_TOKENS=${OUT_TOKENS:-0}
CACHED_TOKENS=${CACHED_TOKENS:-0}
CTX_TOKENS=${CTX_TOKENS:-0}
TOTAL_IO=$((IN_TOKENS + OUT_TOKENS))

# ---- cost & duration ----
COST_USD=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
COST_USD=${COST_USD:-0}
DURATION_MS=${DURATION_MS:-0}

# ---- colors (256-color palette) ----
GREEN='\033[38;5;158m'; MINT='\033[38;5;150m'; YELLOW='\033[38;5;215m'
RED='\033[38;5;203m'; BLUE='\033[38;5;117m'; PURPLE='\033[38;5;147m'
GOLD='\033[38;5;222m'; BURN='\033[38;5;220m'; LAV='\033[38;5;189m'
GRAY='\033[38;5;245m'; DIM='\033[2m'; RESET='\033[0m'

# ---- model-aware zone thresholds & window size ----
# dictionary-of-ai-coding anchors dumb zone ~100k for "frontier models" but
# admits debate; Opus holds longer than Sonnet, Opus 1M holds longer still.
if [[ "$MODEL_ID" == *"[1m]"* ]] || [[ "$MODEL_ID" == *"1m"* ]]; then
  WINDOW=1000000; T_DRIFT=200000; T_DUMB=400000
elif [[ "$MODEL_ID" == *opus* ]] || [[ "$MODEL" == *Opus* ]]; then
  WINDOW=200000;  T_DRIFT=120000; T_DUMB=160000
elif [[ "$MODEL_ID" == *haiku* ]] || [[ "$MODEL" == *Haiku* ]]; then
  WINDOW=200000;  T_DRIFT=60000;  T_DUMB=100000
else
  WINDOW=200000;  T_DRIFT=80000;  T_DUMB=120000
fi

if   [ "$CTX_TOKENS" -ge "$T_DUMB" ];  then ZONE_COLOR="$RED";    ZONE_LABEL="🤪 dumb zone"
elif [ "$CTX_TOKENS" -ge "$T_DRIFT" ]; then ZONE_COLOR="$YELLOW"; ZONE_LABEL="🥱 drifting"
else                                        ZONE_COLOR="$GREEN";  ZONE_LABEL="🧐 smart zone"; fi
CTX_COLOR="$ZONE_COLOR"

# ---- token formatter ----
fmt_tokens() {
  local t=$1
  if   [ "$t" -ge 1000000 ]; then LC_ALL=C awk -v t="$t" 'BEGIN { printf (t%1000000==0?"%.0fM":"%.1fM"), t/1000000 }'
  elif [ "$t" -ge 100000  ]; then LC_ALL=C awk -v t="$t" 'BEGIN { printf "%.0fk", t/1000 }'
  elif [ "$t" -ge 10000   ]; then LC_ALL=C awk -v t="$t" 'BEGIN { printf "%.1fk", t/1000 }'
  elif [ "$t" -ge 1000    ]; then LC_ALL=C awk -v t="$t" 'BEGIN { printf "%.1fk", t/1000 }'
  else echo "$t"; fi
}

CTX_FMT=$(fmt_tokens "$CTX_TOKENS")

# ---- segmented progress bar (20 chars, 4-shade gradient) ----
# █ used  │  ░ safe headroom  │  ▒ approaching dumb  │  ▓ past dumb threshold
# density rises with risk: used (solid) → safe (light) → warning → degraded
BAR_LEN=20
USED_CHARS=$(( CTX_TOKENS * BAR_LEN / WINDOW ))
DUMB_CHARS=$(( T_DUMB * BAR_LEN / WINDOW ))
[ "$USED_CHARS" -gt "$BAR_LEN" ] && USED_CHARS=$BAR_LEN
[ "$DUMB_CHARS" -gt "$BAR_LEN" ] && DUMB_CHARS=$BAR_LEN

BAR=""
for ((i=0; i<BAR_LEN; i++)); do
  if   [ "$i" -lt "$USED_CHARS" ];  then BAR="${BAR}${ZONE_COLOR}█${RESET}"
  elif [ "$i" -lt "$DUMB_CHARS" ];  then BAR="${BAR}${ZONE_COLOR}${DIM}▓${RESET}"
  else                                   BAR="${BAR}${RED}${DIM}▒${RESET}"
  fi
done
# semantic: █ used  │  ▓ safe headroom  │  ▒ past dumb threshold (always red)
# safe headroom segment follows the current zone color (green/yellow/red)

# computed % of window for display
WIN_PCT=$(( CTX_TOKENS * 100 / WINDOW ))
WIN_FMT=$(fmt_tokens "$WINDOW")

# ---- session elapsed (prefer native duration, fallback to transcript) ----
ELAPSED=0
if [ "$DURATION_MS" -gt 0 ] 2>/dev/null; then
  ELAPSED=$((DURATION_MS / 1000))
elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  FIRST_TS=$(jq -r 'select(.timestamp) | .timestamp' "$TRANSCRIPT" 2>/dev/null | head -n 1)
  if [ -n "$FIRST_TS" ]; then
    CLEAN_TS=$(echo "$FIRST_TS" | sed -E 's/\.[0-9]+Z?$//' | sed 's/Z$//')
    FIRST_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$CLEAN_TS" "+%s" 2>/dev/null \
                  || date -u -d "${CLEAN_TS}Z" "+%s" 2>/dev/null)
    [ -n "$FIRST_EPOCH" ] && ELAPSED=$(( $(date +%s) - FIRST_EPOCH ))
  fi
fi

if [ "$ELAPSED" -gt 0 ]; then
  H=$((ELAPSED / 3600)); M=$(((ELAPSED % 3600) / 60))
  [ "$H" -gt 0 ] && SESSION_FMT="${H}h${M}m" || SESSION_FMT="${M}m"
else
  SESSION_FMT="-"
fi

# ---- burn rate & tpm ----
BURN_RATE=""
if LC_ALL=C awk -v c="$COST_USD" -v d="$DURATION_MS" 'BEGIN{exit !(c+0>0 && d+0>0)}'; then
  BURN_RATE=$(LC_ALL=C awk -v c="$COST_USD" -v d="$DURATION_MS" 'BEGIN{printf "%.2f", c*3600000/d}')
fi
TPM=""
if [ "$TOTAL_IO" -gt 0 ] && [ "$DURATION_MS" -gt 0 ] 2>/dev/null; then
  TPM=$(LC_ALL=C awk -v t="$TOTAL_IO" -v d="$DURATION_MS" 'BEGIN{printf "%.0f", t*60000/d}')
fi
COST_FMT=$(LC_ALL=C awk -v c="$COST_USD" 'BEGIN{printf "%.2f", c+0}')

# ---- git branch ----
GIT_BRANCH=""
if [ -n "$CWD_REAL" ] && [ -d "$CWD_REAL" ]; then
  GIT_BRANCH=$(git -C "$CWD_REAL" branch --show-current 2>/dev/null \
               || git -C "$CWD_REAL" rev-parse --short HEAD 2>/dev/null)
fi

# ---- render ----
LINE1="${ZONE_COLOR}${ZONE_LABEL}${RESET} │ ${ZONE_COLOR}${CTX_FMT}/${WIN_FMT} (${WIN_PCT}%)${RESET} ${BAR} │ ⏱ ${SESSION_FMT}"

LINE2="📁 ${BLUE}${CWD:-?}${RESET}"
[ -n "$GIT_BRANCH" ]   && LINE2="${LINE2}  🌿 ${MINT}${GIT_BRANCH}${RESET}"
LINE2="${LINE2}  🤖 ${PURPLE}${MODEL}${RESET}"
[ -n "$CC_VERSION" ] && [ "$CC_VERSION" != "null" ]     && LINE2="${LINE2}  ${DIM}v${CC_VERSION}${RESET}"

LINE3="💰 ${GOLD}\$${COST_FMT}${RESET}"
[ -n "$BURN_RATE" ] && LINE3="${LINE3} ${DIM}(${RESET}${BURN}\$${BURN_RATE}/h${RESET}${DIM})${RESET}"
[ -n "$TPM" ]       && LINE3="${LINE3}  📊 ${LAV}${TPM} tpm${RESET}"

echo -e "$LINE1"
echo -e "$LINE2"
echo -e "$LINE3"
