#!/usr/bin/env bash
set -euo pipefail

tmp_file="$(mktemp /tmp/paru-pkgbuild-diff.XXXXXX)"
trap 'rm -f "$tmp_file"' EXIT

ai_model="${OPENCODE_MODEL:-github-copilot/gpt-5.2}"

if [ "$#" -gt 0 ]; then
  cat "$@" > "$tmp_file"
else
  cat > "$tmp_file"
fi

show_diff() {
  local pager_cmd="${PAGER:-less -R}"
  if ! bash -c "$pager_cmd \"\$1\"" _ "$tmp_file"; then
    less -R "$tmp_file"
  fi
}

if ! command -v opencode >/dev/null 2>&1; then
  printf 'WARNING: opencode is not installed. Showing PKGBUILD diff.\n\n' >&2
  show_diff
  exit 0
fi

printf 'Running AI check on PKGBUILD changes (model: %s)...\n' "$ai_model" >&2

read -r -d '' ai_prompt <<'EOF' || true
You are auditing an AUR PKGBUILD diff for security risk.

Return exactly this format:
RESULT: GOOD|WARN|BAD
REASON: one short sentence

Flag as WARN or BAD for suspicious changes (install()/package() scripts, remote downloads/execution, curl|bash patterns, sudo/chown/chmod abuse, systemd unit changes, hidden network fetches, or obfuscation).
Use GOOD only when the diff looks routine and low risk.
EOF

if ! ai_output="$(opencode run --model "$ai_model" --file "$tmp_file" -- "$ai_prompt" 2>&1)"; then
  printf 'WARNING: AI check failed (offline/API/command error). Showing PKGBUILD diff.\n\n' >&2
  printf '%s\n\n' "$ai_output" >&2
  show_diff
  exit 0
fi

clean_output="$(printf '%s\n' "$ai_output" | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g')"
result="$(printf '%s\n' "$clean_output" | sed -n 's/.*RESULT:[[:space:]]*//p' | head -n 1 | tr '[:lower:]' '[:upper:]')"
reason="$(printf '%s\n' "$clean_output" | sed -n 's/.*REASON:[[:space:]]*//p' | head -n 1)"

case "$result" in
  GOOD)
    printf 'AI CHECK: GOOD - continuing install.\n' >&2
    exit 0
    ;;
  WARN|BAD)
    printf 'AI REVIEW: %s\n' "$result" >&2
    if [ -n "$reason" ]; then
      printf 'REASON: %s\n\n' "$reason" >&2
    else
      printf '\n' >&2
    fi
    show_diff
    exit 0
    ;;
  *)
    printf 'WARNING: AI returned an unexpected response. Showing PKGBUILD diff.\n\n' >&2
    printf '%s\n\n' "$clean_output" >&2
    show_diff
    exit 0
    ;;
esac
