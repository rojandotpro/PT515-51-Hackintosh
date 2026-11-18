#!/usr/bin/env bash
set -u
OUT="${HOME}/Desktop/display-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
exec > >(tee "$OUT/report.txt") 2>&1
echo "=== Display audit ==="; date; echo
echo "=== DRM connectors ==="; ls -1 /sys/class/drm 2>/dev/null || true; echo
CONNECTOR=""
for c in /sys/class/drm/eDP-* /sys/class/drm/LVDS-*; do
  [ -d "$c" ] || continue
  if [ "$(cat "$c/status" 2>/dev/null)" = connected ]; then CONNECTOR="$c"; break; fi
done
if [ -n "$CONNECTOR" ]; then
  echo "=== Internal connector: $CONNECTOR ==="
  cat "$CONNECTOR/status" 2>/dev/null || true; cat "$CONNECTOR/modes" 2>/dev/null || true
  if [ -r "$CONNECTOR/edid" ]; then
    cp "$CONNECTOR/edid" "$OUT/panel-edid.bin"
    if command -v edid-decode >/dev/null 2>&1; then edid-decode "$CONNECTOR/edid" | tee "$OUT/edid-decode.txt"; else echo "edid-decode not installed"; fi
  fi
else echo "No connected eDP/LVDS connector found."; fi
echo; echo "=== XRandR ==="; xrandr --props 2>/dev/null || true
echo; echo "=== DRM/i915 ==="; dmesg 2>/dev/null | grep -iE 'drm|i915|edp|lvds|panel|dither|color' | tail -200 || true
echo; echo "=== GPU/kernel ==="; uname -a; lspci -nnk 2>/dev/null | grep -A4 -iE 'vga|3d|display' || true
echo; echo "REPORT_DIR=$OUT"; echo "Copy report.txt, edid-decode.txt (if present), and panel-edid.bin back for analysis."
