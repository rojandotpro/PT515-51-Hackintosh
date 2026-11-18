#!/bin/bash
# PT515-51 audio data collection — run in CachyOS live (no Wi-Fi needed)
# Usage: open Multimedia drive in file manager first, then:
#   bash /run/media/$USER/Multimedia/Hackintosh/Final/audio-linux-dump.sh
cd ~
MM=$(ls -d /run/media/$USER/Multimedia 2>/dev/null)
[ -z "$MM" ] && { echo "Multimedia drive not mounted - click it in the file manager first"; exit 1; }
OUT="$MM/Hackintosh/Final/audio-dump-linux.txt"
sudo -v
{
echo "=== CODEC (full) ==="; cat /proc/asound/card*/codec#*
echo; echo "=== CARDS ==="; cat /proc/asound/cards
echo; echo "=== PCI ==="; lspci -nnk | grep -iA3 audio
echo; echo "=== PIN CONFIGS ==="
for d in /sys/class/sound/hwC*D*; do echo "-- $d"; for f in vendor_name chip_name init_pin_configs driver_pin_configs user_pin_configs hints; do echo "[$f]"; cat $d/$f 2>/dev/null; done; done
echo; echo "=== MIXER ==="; amixer -c0 contents 2>/dev/null
echo; echo "=== KERNEL ==="; sudo dmesg | grep -iE "snd|hda|realtek|alc"
echo; echo "=== MODULE OPTS ==="; for p in /sys/module/snd_hda_intel/parameters/*; do echo "$(basename $p)=$(cat $p 2>/dev/null)"; done
} > "$OUT" 2>&1
sync
echo "saved to $OUT"; wc -l "$OUT"
echo
echo "NEXT: mute key test. Press Fn+Mute a few times, then Ctrl+C."
echo "Output is also saved to Hackintosh/Final/mute-key-linux.txt"
sudo timeout 30 libinput debug-events --show-keycodes 2>&1 | grep -iE "key" | tee "$MM/Hackintosh/Final/mute-key-linux.txt"
sync
echo "done - reboot to macOS"
