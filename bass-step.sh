#!/usr/bin/env bash
# bass-step.sh — change bass by +1 or -1 dB using jblctl
# usage: bass-step.sh +1 [--decode] [--ip <addr>]   or   bass-step.sh -1 [...]

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JBLCTL="${SCRIPT_DIR}/jblctl"
CMD_DIR="${SCRIPT_DIR}/commands"

step="${1:-}"; shift || true
[[ "$step" == "+1" || "$step" == "-1" ]] || { echo "usage: $(basename "$0") +1| -1 [--decode] [--ip <addr>]" >&2; exit 1; }

# pass-through flags
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decode|--ip) args+=("$1"); shift; [[ "$1" != "--decode" ]] && args+=("$1");;
    *) args+=("$1");;
  esac
  shift || true
done

# 1) get current bass
resp="$("$JBLCTL" bass-query 2>/dev/null || true)"
# expect: 02-23-0C-00-01-<byte>-0D-
cur_hex="$(grep -oE '02-23-0C-00-01-[0-9A-Fa-f]{2}-0D-' <<<"$resp" | sed -E 's/.*-([0-9A-Fa-f]{2})-0D-.*/\1/')"
if [[ -z "$cur_hex" ]]; then
  echo "could not read current bass; defaulting to 0 dB" >&2
  cur=0
else
  val=$((16#$cur_hex))
  # 0x00..0x0C = +0..+12; 0xFF..0xF4 = -1..-12
  if (( val <= 0x0C )); then cur=$val; else cur=$((val - 256)); fi
fi

# 2) compute new value
delta=$([[ "$step" == "+1" ]] && echo 1 || echo -1)
new=$((cur + delta))
(( new > 12 )) && new=12
(( new < -12 )) && new=-12

# 3) convert back to one byte
if (( new >= 0 )); then
  new_hex=$(printf "%02X" "$new")
else
  new_hex=$(printf "%02X" $((256 + new)))
fi

# 4) build temp command and send via jblctl
tmp="${CMD_DIR}/_tmp_set_bass"
{
  echo "# Bass ${new} dB"
  printf '\\x23\\x0C\\x01\\x%s\\x0D\n' "$new_hex"
} > "$tmp"

"$JBLCTL" "$(basename "$tmp")" "${args[@]}" || true
rm -f "$tmp"

