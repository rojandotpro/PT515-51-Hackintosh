#!/bin/bash
# Diagnose Bluetooth on the PT515-51.
#
#   ./tools/bluetooth-check.sh
#
# Read-only. Reports what macOS can see, then says which layer is broken:
# the USB radio, the OpenCore kext injection, or the controller itself.
#
# Exit codes:
#   0  radio present and controller on
#   1  Bluetooth USB radio not enumerating (hardware/EC level)
#   2  radio present, IntelBluetoothFirmware not loaded (EFI/kext level)
#   3  radio and firmware present, controller off (controller/firmware level)
set -uo pipefail

grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

echo "== macOS =="
sw_vers
echo

echo "== controller =="
BT="$(system_profiler SPBluetoothDataType 2>/dev/null)"
printf '%s\n' "$BT" | sed -n '/Bluetooth Controller:/,/^$/p' | sed 's/^/  /'
STATE="$(printf '%s\n' "$BT" | awk -F': *' '/State:/{print $2; exit}')"
ADDR="$(printf '%s\n' "$BT" | awk -F': *' '/Address:/{print $2; exit}')"
echo

echo "== USB radio (Intel 8087:0aaa, internal port HS06) =="
USB="$(ioreg -p IOUSB -l -w0 2>/dev/null)"
LOADED="$(kmutil showloaded --list-only 2>/dev/null)"
# The controller exposes idProduct 2730 and UsbDeviceSignature <8780aa0a...>
# rather than an idVendor property, so check the signature and the name too.
if printf '%s\n' "$USB" | grep -qE 'UsbDeviceSignature" = <8780aa0a|Bluetooth USB Host Controller|"idProduct" = 2730' \
   || printf '%s\n' "$LOADED" | grep -q com.zxystd.IntelBluetoothFirmware; then
  RADIO=1
  grn "  present"
else
  RADIO=0
  red "  absent — no USB device on the internal Bluetooth port"
  echo "  Ports currently carrying a device:"
  printf '%s\n' "$USB" | grep -E '^\s+\+-o .*IOUSBHostDevice' | sed 's/^/    /'
fi
echo

echo "== driver stack =="
for id in com.zxystd.IntelBluetoothFirmware com.zxystd.IntelBTPatcher as.acidanthera.BlueToolFixup; do
  if printf '%s\n' "$LOADED" | grep -q "$id"; then
    printf '  loaded    %s\n' "$id"
  else
    printf '  not loaded %s\n' "$id"
  fi
done
echo

echo "== verdict =="
if [ "$RADIO" -eq 0 ]; then
  red "  The Bluetooth radio is not enumerating over USB."
  echo "  IntelBluetoothFirmware has nothing to attach to, so it stays unloaded."
  echo "  This is below macOS and below OpenCore: no kext or config change fixes it."
  echo
  echo "  Next steps, in order:"
  echo "    1. Shut down completely (not restart). Unplug the charger and all USB devices."
  echo "    2. Hold the power button 20 s, then boot."
  echo "    3. Re-run this script."
  echo "    4. Still absent: boot Linux or Windows and check for 8087:0aaa."
  echo "       Absent there too: BIOS wireless setting, or the CNVi module/EC."
  exit 1
fi

if ! printf '%s\n' "$LOADED" | grep -q com.zxystd.IntelBluetoothFirmware; then
  ylw "  Radio present but IntelBluetoothFirmware did not load."
  echo "  Check that the kext is in EFI/OC/Kexts and enabled in Kernel > Add,"
  echo "  with IntelBluetoothInjector disabled. See docs/NETWORK.md."
  exit 2
fi

if [ "$STATE" != "On" ]; then
  ylw "  Radio and firmware are present, but the controller reports State: ${STATE:-unknown}"
  echo "  Address: ${ADDR:-unknown}"
  echo "  Toggle Bluetooth in Control Centre, then check:"
  echo "    log show --last 2m --predicate 'process == \"bluetoothd\"'"
  echo "  See docs/NETWORK.md for the known post-sleep behaviour."
  exit 3
fi

grn "  Radio present, firmware loaded, controller on."
