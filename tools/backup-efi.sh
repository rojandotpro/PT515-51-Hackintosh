#!/bin/bash
# Snapshot the live OpenCore EFI with a manifest and checksums.
#
#   sudo ./tools/backup-efi.sh [destination]
#
# Default destination: ~/Hackintosh-Backups/EFI-YYYYMMDD-HHMMSS
# The ESP must already be mounted at /Volumes/EFI
# (sudo diskutil mount disk0s1).
set -euo pipefail

ESP="/Volumes/EFI"
STAMP="$(date +%Y%m%d-%H%M%S)"

# When run with sudo, $HOME is root's. Put the backup in the invoking user's home instead.
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  USER_HOME="${USER_HOME:-/Users/$SUDO_USER}"
else
  USER_HOME="$HOME"
fi

DEST="${1:-$USER_HOME/Hackintosh-Backups/EFI-$STAMP}"

say() { printf '\033[32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m    %s\033[0m\n' "$*"; }
die() { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$ESP/EFI/OC" ] || die "ESP not mounted at $ESP — run: sudo diskutil mount disk0s1"
[ -f "$ESP/EFI/OC/config.plist" ] || die "no config.plist on $ESP — wrong partition?"
[ -f "$ESP/EFI/OC/OpenCore.efi" ] || die "no OpenCore.efi on $ESP"

mkdir -p "$DEST"
say "copying EFI to $DEST"
# --norsrc --noextattr keeps macOS metadata out of the FAT32 copy.
ditto --norsrc --noextattr "$ESP/EFI/OC" "$DEST/OC"
ditto --norsrc --noextattr "$ESP/EFI/BOOT" "$DEST/BOOT"

say "writing manifest"
OCVER="$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | awk '{print $2}')"
BOOTARGS="$(nvram -p 2>/dev/null | awk -F'\t' '$1=="boot-args"{print $2}')"
CSR="$(nvram -p 2>/dev/null | awk -F'\t' '$1=="csr-active-config"{print $2}')"
{
  echo "Created : $(date)"
  echo "Source  : $ESP"
  echo "macOS   : $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "OpenCore: ${OCVER:-unknown}"
  echo "boot-args: ${BOOTARGS:-none}"
  echo "csr-active-config: ${CSR:-unknown}"
  echo
  echo "Kexts in this snapshot:"
  for k in "$DEST"/OC/Kexts/*.kext; do
    [ -d "$k" ] || continue
    v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
         "$k/Contents/Info.plist" 2>/dev/null || echo '?')"
    printf '  %-42s %s\n' "$(basename "$k")" "$v"
  done
  echo
  echo "ACPI files:"
  for a in "$DEST"/OC/ACPI/*.aml; do
    [ -f "$a" ] && printf '  %s\n' "$(basename "$a")"
  done
} > "$DEST/MANIFEST.txt"

say "checking config"
if plutil -lint "$DEST/OC/config.plist" >/dev/null 2>&1; then
  warn "config.plist: OK"
else
  warn "config.plist: INVALID — the live EFI is broken; restore a previous snapshot"
fi

say "checksums (this takes a few seconds)"
( cd "$DEST" && find . -type f ! -name SHA256SUMS.txt -print0 \
    | xargs -0 shasum -a 256 > SHA256SUMS.txt )

SIZE="$(du -sh "$DEST" | awk '{print $1}')"
say "done — $SIZE at $DEST"
echo
echo "Verify later:"
echo "  cd \"$DEST\" && shasum -a 256 -c SHA256SUMS.txt"
echo
echo "Restore (from a booted system or a live USB):"
echo "  sudo diskutil mount disk0s1"
echo "  sudo rm -rf /Volumes/EFI/EFI/OC /Volumes/EFI/EFI/BOOT"
echo "  sudo cp -R \"$DEST/OC\" \"$DEST/BOOT\" /Volumes/EFI/EFI/"
echo "  sudo dot_clean -m /Volumes/EFI"
