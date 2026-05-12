#!/bin/bash
# parse_hook_input: single jq call → flat shell vars via eval
parse_hook_input() {
  local input="$1"
  eval "$(echo "$input" | jq -r '
    "MODEL="          + (.model.display_name // "Claude" | @sh),
    "MODEL_ID="       + (.model.id // "" | @sh),
    "CC_VERSION="     + (.version // "" | @sh),
    "TRANSCRIPT="     + (.transcript_path // "" | @sh),
    "CWD_REAL="       + (.workspace.current_dir // .cwd // "" | @sh),
    "CTX_PCT="        + ((.context_window.used_percentage // 0) | floor | tostring),
    "CTX_TOKENS="     + (((.context_window.current_usage.input_tokens // 0)
                        + (.context_window.current_usage.cache_creation_input_tokens // 0)
                        + (.context_window.current_usage.cache_read_input_tokens // 0)) | tostring),
    "IN_TOKENS="      + (.context_window.total_input_tokens // 0 | tostring),
    "OUT_TOKENS="     + (.context_window.total_output_tokens // 0 | tostring),
    "CACHED_TOKENS="  + (.context_window.current_usage.cache_read_input_tokens // 0 | tostring),
    "COST_USD="       + (.cost.total_cost_usd // 0 | tostring),
    "DURATION_MS="    + (.cost.total_duration_ms // 0 | tostring)
  ')"
  CWD=$(basename "$CWD_REAL")
  TOTAL_IO=$((IN_TOKENS + OUT_TOKENS))
}
