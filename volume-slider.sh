#!/usr/bin/env bash
# volume-slider.sh — interactive terminal volume control for JBL MA series
# - Pure bash/tty (no fzf/dialog dependencies)
# - Generates bytes: 23 06 01 <NN> 0D  and calls ./jblctl with a temp command file
# Controls:
#   ↑ / → / +     increase
#   ↓ / ← / -     decrease
#   PgUp/PgDn     +/- 10
#   digits 0–9    type two digits to jump (e.g., '4''5' => 45)
#   Enter         send volume
#   q or Esc      quit without sending
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JBLCTL="${SCRIPT_DIR}/jblctl"
CMD_DIR="${SCRIPT_DIR}/commands"

# -------- flags (pass to jblctl) --------
IP=""
DECODE=0
START=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)     shift; IP="$1" ;;
    --decode) DECODE=1 ;;
    --start)  shift; START="$1" ;;   # optional starting volume 0-99
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--ip <addr>] [--decode] [--start <0-99>]

Interactive keys:
  ↑/→/+  : increase   │ PgUp : +10
  ↓/←/-  : decrease   │ PgDn : -10
  0..9   : type two digits to jump
  Enter  : send       │ q/Esc: quit without sending
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
  shift
done

# -------- helpers --------
die(){ echo "error: $*" >&2; exit 1; }
command -v hexdump >/dev/null || die "hexdump not found"
[[ -x "$JBLCTL" ]] || die "jblctl not found at $JBLCTL"
mkdir -p "$CMD_DIR"

# Query current volume as starting point (fallback to 40)
get_current_vol() {
  local resp
  if [[ -n "$IP" ]]; then
    resp="$("$JBLCTL" volume-query --ip "$IP" 2>/dev/null || true)"
  else
    resp="$("$JBLCTL" volume-query 2>/dev/null || true)"
  fi
  # Expect hex like: 02-23-06-00-01-32-0D-
  local byte
  byte="$(grep -oE '02-23-06-00-01-[0-9A-Fa-f]{2}-0D-' <<<"$resp" | sed -E 's/.*-([0-9A-Fa-f]{2})-0D-.*/\1/')" || true
  if [[ -n "$byte" ]]; then
    printf "%d" $((16#$byte))
  else
    echo 40
  fi
}

to_hex2() { printf "%02X" "$1"; }

draw() {
  local v="$1"
  local filled=$(( v ))
  (( filled > 50 )) && filled=50
  local empty=$(( 50 - filled ))
  printf "\rVolume: %3d  [%-*s%*s]  (+/- or arrows, Enter to send, q/Esc to quit)" \
         "$v" "$filled" "" "$empty" "" \
    | sed 's/ /#/1; s/ /#/g' | sed "s/$(printf '#').*/$(printf '#')/g" > /dev/null
  # Simpler bar: use '=' chars
  local bar="$(printf '%*s' "$filled" '' | tr ' ' '=')"
  local spc="$(printf '%*s' "$empty" '')"
  printf "\rVolume: %3d  [%s%s]  (+/- or arrows, x/Space to send, q/Esc to quit)" "$v" "$bar" "$spc"
}

# -------- main UI loop --------
stty -echo -icanon time 0 min 0 || true
tput civis || true

trap 'stty sane; tput cnorm 2>/dev/null || true; echo' EXIT

vol="${START:-}"
if [[ -z "$vol" ]]; then vol="$(get_current_vol)"; fi
# bounds
if ! [[ "$vol" =~ ^[0-9]+$ ]]; then vol=40; fi
(( vol < 0 )) && vol=0
(( vol > 99 )) && vol=99

typed=""   # for digit entry

draw "$vol"
while :; do
  IFS= read -rsn1 key || true
  [[ -z "${key:-}" ]] && { sleep 0.02; continue; }

  case "$key" in
    $'\x1b') # ESC or arrow/PgUp/PgDn sequence
      # read rest (if any)
      IFS= read -rsn2 -t 0.001 more || true
      seq="$key$more"
      case "$seq" in
        $'\x1b[A'|$'\x1b[C') (( vol < 99 )) && ((vol++)) ;;  # Up/Right
        $'\x1b[B'|$'\x1b[D') (( vol >  0 )) && ((vol--)) ;;  # Down/Left
        $'\x1b[5'?)          (( vol = (vol+10>99)?99:vol+10 )) ;; # PgUp
        $'\x1b[6'?)          (( vol = (vol-10<0)?0:vol-10 ))  ;;  # PgDn
        *) echo -ne "\r"; echo; exit 0 ;; # bare Esc quits
      esac
      typed=""
      ;;
    '+') (( vol < 99 )) && ((vol++)); typed="";;
    '-') (( vol >  0 )) && ((vol--)); typed="";;
    [0-9])
      typed+="$key"
      if (( ${#typed} == 2 )); then
        v="$typed"; typed=""
        if (( v >=0 && v <=99 )); then vol="$v"; fi
      fi
      ;;
    # Enter Non Repsonsive, swapped with X/Space/ and Enter is still there but idk why.
    x|X|$'\x20'|$'\x0a'|$'\x0d'|$'\r') # X or Space or Enter
      echo
      break
      ;;
    q|Q)
      echo -ne "\r"; echo "Canceled."; exit 0;;
    *)
      # ignore
      ;;
  esac
  draw "$vol"
done

echo # newline after bar

# -------- build temp command and invoke jblctl --------
hex="$(to_hex2 "$vol")"
tmp="${CMD_DIR}/_tmp_set_volume"
{
  echo "# Set master volume to ${vol}"
  printf '\\x23\\x06\\x01\\x%s\\x0D\n' "$hex"
} > "$tmp"

args=()
[[ -n "$IP" ]] && args+=(--ip "$IP")
(( DECODE )) && args+=(--decode)

#echo "DEBUG: will send volume=$vol (hex=$hex) using $JBLCTL" >&2
#echo "DEBUG: temp file $tmp contents: $(cat "$tmp")" >&2
"$JBLCTL" "$(basename "$tmp")" "${args[@]}"
rm -f "$tmp"

