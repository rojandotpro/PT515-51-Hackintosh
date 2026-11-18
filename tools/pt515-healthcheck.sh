#!/bin/bash
# PT515-51 Hackintosh health check — read-only, no sudo required.
line(){ printf '\n===== %s =====\n' "$1"; }

line "SYSTEM"
sw_vers
sysctl -n hw.model machdep.cpu.brand_string 2>/dev/null
echo "cores: $(sysctl -n hw.physicalcpu)P / $(sysctl -n hw.logicalcpu)L   RAM: $(( $(sysctl -n hw.memsize)/1073741824 )) GB"

line "OPENCORE / BOOT"
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null
nvram boot-args 2>/dev/null
csrutil status 2>/dev/null

line "KEXTS LOADED"
kmutil showloaded 2>/dev/null | grep -iE "lilu|whatevergreen|virtualsmc|smc|applealc|cpufriend|nvmefix|restrictevents|voodoo|usbtoolbox|itlwm|bluetooth|amfipass|predator|lucy" \
  | awk '{printf "  %-58s %s\n", $6, $7}'

line "CPU POWER MANAGEMENT"
ioreg -rw0 -c AppleACPICPU -d1 2>/dev/null | grep -c "AppleACPICPU" | xargs echo "  AppleACPICPU instances:"
ioreg -l -w0 2>/dev/null | grep -m1 -o '"CPUFriend[^"]*"' | xargs echo "  CPUFriend:"
pmset -g therm 2>/dev/null | head -5

line "MEMORY CHANNELS"
system_profiler SPMemoryDataType 2>/dev/null | grep -E "BANK|Size|Speed|Status|Type:" | sed 's/^ */  /'

line "GPU / DISPLAY"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset|VRAM|Device ID|Metal|Resolution|UI Looks like|Framebuffer|Display Type|Mirror|Online|Rotation" | sed 's/^ */  /'
ioreg -rw0 -n IGPU -d1 2>/dev/null | grep -oE '"(AAPL,ig-platform-id|device-id|rps-control|framebuffer-stolenmem|enable-backlight-registers-fix)" = <[0-9a-f]*>' | sed 's/^/  /'

line "REFRESH RATE (all modes)"
system_profiler SPDisplaysDataType 2>/dev/null | grep -iE "hz|resolution" | sed 's/^ */  /'

line "AUDIO"
system_profiler SPAudioDataType 2>/dev/null | grep -E "Devices|Input|Output|Manufacturer|Current SampleRate|Transport" | sed 's/^ */  /' | head -20
ioreg -rw0 -c IOHDACodecDevice -d1 2>/dev/null | grep -oE '"(IOHDACodecVendorID|IOHDACodecRevisionID)" = [0-9]*' | sed 's/^/  /'
ioreg -l -w0 2>/dev/null | grep -m2 -oE '"layout-id" = <[0-9a-f]*>' | sed 's/^/  /'

line "NETWORK"
ifconfig -a 2>/dev/null | grep -E "^en[0-9]|status:|media:" | sed 's/^/  /'
networksetup -listallhardwareports 2>/dev/null | grep -A2 "Wi-Fi\|Ethernet" | sed 's/^/  /'

line "BLUETOOTH"
system_profiler SPBluetoothDataType 2>/dev/null | grep -E "State|Chipset|Firmware|Vendor|Product|Transport" | sed 's/^ */  /' | head -10

line "INPUT DEVICES"
ioreg -rw0 -c IOHIDDevice -d1 2>/dev/null | grep -oE '"Product" = "[^"]*"' | sort -u | sed 's/^/  /'
kmutil showloaded 2>/dev/null | grep -c -i voodooi2c | xargs echo "  VoodooI2C kexts loaded:"

line "USB PORTS ENUMERATED"
ioreg -p IOUSB -w0 -l 2>/dev/null | grep -E "\+-o" | sed 's/<class.*//' | sed 's/^/  /'

line "STORAGE"
diskutil list 2>/dev/null | grep -E "^/dev/|Apple_APFS|Container" | sed 's/^/  /'
system_profiler SPNVMeDataType 2>/dev/null | grep -E "Model|Capacity|TRIM|Link Width|Link Speed" | sed 's/^ */  /'

line "BATTERY / SMC"
system_profiler SPPowerDataType 2>/dev/null | grep -E "Cycle Count|Condition|Full Charge|State of Charge|Charging|Connected|Wattage|Amperage|Voltage" | sed 's/^ */  /'

line "POWER / SLEEP SETTINGS"
pmset -g custom 2>/dev/null

line "RECENT WAKE REASONS"
pmset -g log 2>/dev/null | grep -i "Wake from" | tail -6

line "PREDATORSENSE"
kmutil showloaded 2>/dev/null | grep -i predator | sed 's/^/  /'
ls -la /Library/Application\ Support/PredatorSense/ 2>/dev/null | sed 's/^/  /'

line "KERNEL ERRORS (last boot)"
log show --last boot --predicate 'messageType == 16 OR messageType == 17' --style compact 2>/dev/null \
  | grep -iE "error|fail|panic|timeout" | grep -viE "cfprefs|tccd|assertion|Sandbox|bootstrap" | tail -15

echo
echo "===== END ====="
