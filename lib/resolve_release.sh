#!/bin/bash
# resolve_release_ref <api_url>
# Resolves the ref to use for downloading release assets.
# Resolution order:
#   1. $VERSION env var (if set, returned as-is)
#   2. GitHub releases/latest API → .tag_name
#   3. Fallback to "main" with a warning
# Prints the resolved ref to stdout.
resolve_release_ref() {
  local api_url="$1"

  if [ -n "${VERSION:-}" ]; then
    printf '%s' "$VERSION"
    return 0
  fi

  local tag
  tag="$(curl -fsSL "$api_url" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null || true)"

  if [ -z "$tag" ]; then
    echo "[download] No releases found, falling back to main branch." >&2
    printf '%s' "main"
    return 0
  fi

  printf '%s' "$tag"
}
