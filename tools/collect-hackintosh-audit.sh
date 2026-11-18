#!/usr/bin/env bash
set -u

# Collect diagnostics only; this script does not modify EFI, ACPI, USB maps,
# kernel settings, or system sleep configuration.

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="${TMPDIR:-/tmp}/hackintosh-audit-${STAMP}"
DEST="/Volumes/Multimedia/Hackintosh/display-audit-${STAMP}"
mkdir -p "$WORK"

run_to_file() {
    local name="$1"
    shift
    "$@" >"$WORK/$name" 2>&1 || true
}

printf 'Hackintosh Linux audit started: %s\n' "$(date)" > "$WORK/README.txt"
printf 'Host: %s\n\n' "$(hostname)" >> "$WORK/README.txt"

# Find the first connected internal eDP/LVDS connector, including cardN-
CONNECTOR=""
for status in /sys/class/drm/card*-eDP-*/status /sys/class/drm/card*-LVDS-*/status; do
    [ -f "$status" ] || continue
    if grep -qx connected "$status"; then
        CONNECTOR="${status%/status}"
        break
    fi
done

if [ -n "$CONNECTOR" ]; then
    printf 'Connector: %s\n' "$CONNECTOR" >> "$WORK/README.txt"
    cat "$CONNECTOR/status" > "$WORK/connector-status.txt" 2>&1 || true
    cat "$CONNECTOR/modes" > "$WORK/connector-modes.txt" 2>&1 || true
    if [ -r "$CONNECTOR/edid" ]; then
        cat "$CONNECTOR/edid" > "$WORK/panel-edid.bin" 2>/dev/null || true
        if command -v edid-decode >/dev/null 2>&1; then
            edid-decode "$WORK/panel-edid.bin" > "$WORK/edid-decode.txt" 2>&1 || true
        else
            printf 'edid-decode is not installed. Install it with: sudo pacman -S edid-decode\n' > "$WORK/edid-decode.txt"
        fi
    fi
else
    printf 'No connected cardN-eDP/LVDS connector found.\n' >> "$WORK/README.txt"
fi

run_to_file xrandr-verbose.txt xrandr --verbose --query
run_to_file drm-connectors.txt sh -c 'ls -l /sys/class/drm; for f in /sys/class/drm/card*-eDP-*/status /sys/class/drm/card*-LVDS-*/status; do [ -f "$f" ] && { echo "### $f"; cat "$f"; }; done'
run_to_file drm-log.txt sh -c 'dmesg | grep -iE "i915|drm|edp|panel|bpc|dither|link"'
run_to_file gpu.txt lspci -nnk
run_to_file i915-parameters.txt sh -c 'cat /sys/module/i915/parameters/* 2>/dev/null'
run_to_file usb-tree.txt lsusb -t
run_to_file usb-log.txt sh -c 'dmesg | grep -iE "xhci|usb|superspeed|reset|disconnect|error"'
run_to_file acpi-wakeup.txt cat /proc/acpi/wakeup
run_to_file bluetooth-rfkill.txt rfkill list bluetooth
run_to_file bluetooth-service.txt systemctl status bluetooth --no-pager
run_to_file bluetooth-log.txt journalctl -b -u bluetooth --no-pager -n 200
run_to_file kernel-version.txt uname -a

if [ -d /Volumes/Multimedia/Hackintosh ]; then
    mkdir -p "$DEST"
    cp -R "$WORK/." "$DEST/"
    printf 'Audit complete. Results copied to:\n%s\n' "$DEST"
else
    printf 'Audit complete, but /Volumes/Multimedia/Hackintosh is not mounted.\nResults remain in:\n%s\n' "$WORK"
fi

