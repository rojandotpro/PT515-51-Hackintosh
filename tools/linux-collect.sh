#!/bin/bash
# PT515-51 — Linux data collection for macOS cross-check.
# Run from a live Linux USB:   sudo bash linux-collect.sh
# Everything lands in ./pt515-linux-data.txt
OUT="$(pwd)/pt515-linux-data.txt"
exec > >(tee "$OUT") 2>&1
sec(){ printf '\n\n########## %s ##########\n' "$1"; }

sec "0. SYSTEM"
uname -a; echo; cat /etc/os-release | head -3
sudo dmidecode -s bios-version 2>/dev/null
sudo dmidecode -s system-product-name 2>/dev/null

########################################################################
sec "1. AUDIO CODEC — FULL DUMP  (the main prize)"
for f in /proc/asound/card*/codec#*; do
  echo "===== $f ====="
  cat "$f"
done

sec "1b. ALSA cards / PCM / mixer"
cat /proc/asound/cards
echo "--- controls ---"
amixer -c0 scontrols 2>/dev/null
echo "--- full mixer ---"
amixer -c0 2>/dev/null | head -120

sec "1c. HDA driver messages"
sudo dmesg | grep -iE "snd|hda|alc289|codec" | head -60

########################################################################
sec "2. TRACKPAD — is interrupt mode actually working under Linux?"
echo "--- /proc/interrupts (i2c / elan / hid rows) ---"
grep -iE "i2c|elan|hid|IRQ" /proc/interrupts | head -30
echo
echo "--- i2c adapters ---"
ls -l /sys/bus/i2c/devices/ 2>/dev/null
for d in /sys/bus/i2c/devices/i2c-*/; do
  echo "  $d name=$(cat $d/name 2>/dev/null)"
done
echo
echo "--- i2c-hid client devices ---"
for d in /sys/bus/i2c/devices/*-*/; do
  n=$(cat "$d/name" 2>/dev/null)
  [ -n "$n" ] && echo "  $(basename $d)  name=$n  modalias=$(cat $d/modalias 2>/dev/null)"
done
echo
echo "--- ACPI device -> IRQ ---"
for d in /sys/bus/acpi/devices/*ELAN*/ /sys/bus/acpi/devices/*PNP0C50*/; do
  [ -d "$d" ] && echo "  $d" && cat "$d/path" 2>/dev/null && cat "$d/status" 2>/dev/null
done
echo
echo "--- GPIO pinctrl (needs debugfs) ---"
sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null
ls /sys/kernel/debug/pinctrl/ 2>/dev/null
for p in /sys/kernel/debug/pinctrl/*/; do
  echo "===== $p ====="
  sudo cat "$p/pins" 2>/dev/null | grep -iE "mode-1|GPIO 0x|IRQ" | head -40
done
echo
echo "--- gpio chips ---"
sudo cat /sys/kernel/debug/gpio 2>/dev/null | head -40
echo
sudo dmesg | grep -iE "elan|i2c_hid|i2c-hid|INT3450|gpio" | head -40

########################################################################
sec "3. DISPLAY — native EDID (settles the HDR / bit-depth question)"
for e in /sys/class/drm/*/edid; do
  s=$(stat -c%s "$e" 2>/dev/null)
  [ "$s" -gt 0 ] 2>/dev/null && { echo "===== $e  ($s bytes) ====="; xxd "$e" 2>/dev/null || od -An -tx1 "$e"; }
done
echo "--- parsed (if edid-decode present) ---"
for e in /sys/class/drm/*/edid; do
  s=$(stat -c%s "$e" 2>/dev/null)
  [ "$s" -gt 0 ] 2>/dev/null && { echo "===== $e ====="; edid-decode "$e" 2>/dev/null | head -60; }
done
echo "--- connectors / modes ---"
for c in /sys/class/drm/card*-*/; do
  echo "  $(basename $c): status=$(cat $c/status 2>/dev/null)"
  head -12 "$c/modes" 2>/dev/null | sed 's/^/      /'
done

########################################################################
sec "4. CPU POWER — settles the overclock / undervolt question"
echo "--- turbo / freq limits ---"
lscpu | grep -iE "model name|mhz|cpu\(s\)"
cat /sys/devices/system/cpu/intel_pstate/* 2>/dev/null | head -20
echo "no_turbo: $(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)"
echo "hwp: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
echo "avail EPP: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null)"
echo
echo "--- RAPL power limits (actual firmware values) ---"
for r in /sys/class/powercap/intel-rapl:0/constraint_*; do
  echo "  $(basename $r) = $(cat $r 2>/dev/null)"
done
echo
echo "--- MSRs (needs msr-tools; harmless if absent) ---"
sudo modprobe msr 2>/dev/null
if command -v rdmsr >/dev/null; then
  echo "  MSR_PLATFORM_INFO   0xCE  = $(sudo rdmsr -0 0xCE 2>/dev/null)"
  echo "  MSR_TURBO_RATIO     0x1AD = $(sudo rdmsr -0 0x1AD 2>/dev/null)"
  echo "  MSR_PKG_POWER_LIMIT 0x610 = $(sudo rdmsr -0 0x610 2>/dev/null)"
  echo "  MSR_RAPL_UNIT       0x606 = $(sudo rdmsr -0 0x606 2>/dev/null)"
  echo "  MSR_FEATURE_CONTROL 0x03A = $(sudo rdmsr -0 0x3A 2>/dev/null)   (bit0=1 -> CFG lock SET)"
  echo "  MSR_OC_MAILBOX      0x150 = $(sudo rdmsr -0 0x150 2>/dev/null)  (error -> undervolt locked)"
  echo "  MSR_MISC_ENABLE     0x1A0 = $(sudo rdmsr -0 0x1A0 2>/dev/null)"
else
  echo "  rdmsr not installed:  sudo pacman -S --noconfirm msr-tools   then re-run"
fi

sec "4b. THERMAL / FANS"
sensors 2>/dev/null | head -40
for t in /sys/class/thermal/thermal_zone*/; do
  echo "  $(cat $t/type 2>/dev/null) = $(cat $t/temp 2>/dev/null)"
done

########################################################################
sec "5. BATTERY (compare against macOS SMC readings)"
for b in /sys/class/power_supply/BAT*/; do
  for k in manufacturer model_name technology cycle_count energy_full energy_full_design \
           charge_full charge_full_design voltage_min_design capacity status; do
    [ -f "$b$k" ] && echo "  $k = $(cat $b$k 2>/dev/null)"
  done
done

########################################################################
sec "6. PCI / USB (full, for the record)"
lspci -nnk
echo; lsusb -t; echo; lsusb

sec "7. EC / WMI"
ls /sys/bus/wmi/devices/ 2>/dev/null
sudo dmesg | grep -iE "acpi|ec_|embedded controller|wmi" | head -40

sec "8. FIRMWARE ERRORS"
sudo dmesg --level=err,warn 2>/dev/null | head -50

echo
echo "########## DONE — file written to: $OUT ##########"
