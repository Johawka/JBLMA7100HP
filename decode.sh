#!/usr/bin/env bash
# decode.sh — human-readable translation of AVR responses

hex="$1"
[[ -z "$hex" ]] && { echo "No data to decode."; exit 1; }

# Split into byte array
IFS='-' read -r -a bytes <<< "$hex"
cmdid="${bytes[2]}"
datalen="${bytes[4]}"
data1="${bytes[5]}"
data2="${bytes[6]:-}"

case "$cmdid" in
  00) [[ "$data1" == "01" ]] && echo "Power: ON" || echo "Power: Standby" ;;
  01)
    case "$data1" in
      00) echo "Display: Full brightness" ;;
      01) echo "Display: 50%" ;;
      02) echo "Display: 25%" ;;
      03) echo "Display: Off" ;;
      *)  echo "Display: Unknown ($data1)" ;;
    esac ;;
  05)
    declare -A srcmap=(
      [01]="TV/ARC" [02]="HDMI1" [03]="HDMI2" [04]="HDMI3"
      [05]="HDMI4" [06]="HDMI5" [07]="HDMI6" [08]="Coax"
      [09]="Optical" [0A]="Analog1" [0B]="Analog2"
      [0C]="Phono" [0D]="Bluetooth" [0E]="Network"
    )
    echo "Input Source: ${srcmap[$data1]:-Unknown ($data1)}" ;;
  06) echo "Master Volume: $((16#$data1))" ;;
  07) [[ "$data1" == "01" ]] && echo "Mute: ON" || echo "Mute: OFF" ;;
  08)
    declare -A surrmap=(
      [01]="Dolby Surround" [02]="DTS Neural:X" [03]="Stereo 2.0"
      [04]="Stereo 2.1" [05]="All Stereo" [06]="Native" [07]="Dolby PLII"
    )
    echo "Surround Mode: ${surrmap[$data1]:-Unknown ($data1)}" ;;
  0B)  # Treble EQ
    # 0x00–0x0C = +0..+12 dB, 0xFF..0xF4 = -1..-12 dB
    if [[ "$data1" =~ ^0[0-9A-C]$ ]]; then
      echo "Treble: +$((16#$data1)) dB"
    else
      # signed 8-bit: e.g., FF=-1, FE=-2 ... F4=-12
      echo "Treble: $(( (16#$data1) - 256 )) dB"
    fi
    ;;

  0C)  # Bass EQ
    # 0x00–0x0C = +0..+12 dB, 0xFF..0xF4 = -1..-12 dB
    if [[ "$data1" =~ ^0[0-9A-C]$ ]]; then
      echo "Bass: +$((16#$data1)) dB"
    else
      echo "Bass: $(( (16#$data1) - 256 )) dB"
    fi
    ;;
 
  0D)
    declare -A eqmap=([00]="Off" [01]="EZ Set EQ" [02]="Dirac Live")
    echo "Room EQ: ${eqmap[$data1]:-Unknown ($data1)}" ;;
  0E) [[ "$data1" == "01" ]] && echo "Dialog Enhanced: ON" || echo "Dialog Enhanced: OFF" ;;
  0F)
    declare -A dolbymap=([00]="Off" [01]="Music" [02]="Movie" [03]="Night")
    echo "Dolby Audio Mode: ${dolbymap[$data1]:-Unknown ($data1)}" ;;
  10) [[ "$data1" == "01" ]] && echo "DRC: ON" || echo "DRC: OFF" ;;
  11)
    # Data1 = service id (hex, from hexdump), Data2 = state (hex)
    # IDs per spec (dec → hex):
    # 12→0C Bluetooth, 13→0D AirPlay, 15→0F Spotify, 16→10 Google Cast,
    # 21→15 Deezer, 22→16 Tidal, 23→17 Roon, 26→1A Amazon Music, 33→21 Pandora
    declare -A idmap=(
      [0C]="Bluetooth"
      [0D]="AirPlay"
      [0F]="Spotify"
      [10]="Google Cast"
      [15]="Deezer"
      [16]="Tidal"
      [17]="Roon"
      [1A]="Amazon Music"
      [21]="Pandora"
    )
    declare -A stmap=(
      [00]="Stopped"
      [01]="Playing"
      [02]="Paused"
    )
    echo "Streaming: ${idmap[$data1]:-Unknown($data1)} → ${stmap[$data2]:-State($data2)}"
    ;;

esac
