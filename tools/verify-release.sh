#!/bin/bash
# Verify a downloaded PredatorSense release without installing anything.
#
#   ./tools/verify-release.sh ~/Downloads
#   ./tools/verify-release.sh .                 # a directory of release assets
#
# Checks, in order:
#   1. SHA-256 checksums from SHA256SUMS.txt
#   2. ZIP integrity
#   3. App and kext code signatures, architecture and bundle metadata
#   4. EFI config.plist lint, PredatorSenseEC entry and placeholder SMBIOS
#
# Read-only: archives are extracted to a temporary directory that is removed
# on exit. Nothing is copied to /Applications or the ESP.
set -euo pipefail

DIR="${1:-.}"
grn() { printf '\033[32m==> %s\033[0m\n' "$*"; }
ylw() { printf '\033[33m    %s\033[0m\n' "$*"; }
red() { printf '\033[31m    %s\033[0m\n' "$*"; }
die() { red "error: $*"; exit 1; }

[ -d "$DIR" ] || die "not a directory: $DIR"
cd "$DIR"

[ -f SHA256SUMS.txt ] || die "SHA256SUMS.txt not found in $PWD"
command -v unzip >/dev/null || die "unzip not found"
command -v codesign >/dev/null || die "codesign not found (Xcode Command Line Tools)"

shopt -s nullglob
PS_ZIPS=(PredatorSense-*.zip)
EFI_ZIPS=(PT515-51-EFI-*.zip)
shopt -u nullglob
[ "${#PS_ZIPS[@]}" -eq 1 ] || die "expected one PredatorSense-*.zip, found ${#PS_ZIPS[@]}"
[ "${#EFI_ZIPS[@]}" -eq 1 ] || die "expected one PT515-51-EFI-*.zip, found ${#EFI_ZIPS[@]}"

grn "checksums"
shasum -a 256 -c SHA256SUMS.txt

grn "archive integrity"
for z in "${PS_ZIPS[0]}" "${EFI_ZIPS[0]}"; do
  unzip -t "$z" >/dev/null || die "corrupt archive: $z"
  ylw "$z: ok"
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pt515-verify.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

grn "PredatorSense bundle"
unzip -q "${PS_ZIPS[0]}" -d "$TMP/ps"
APP="$(find "$TMP/ps" -maxdepth 3 -type d -name 'PredatorSense.app' | head -1)"
KEXT="$(find "$TMP/ps" -maxdepth 3 -type d -name 'PredatorSenseEC.kext' | head -1)"
DAEMON="$(find "$TMP/ps" -maxdepth 3 -type f -name 'predatorsensed' | head -1)"
[ -n "$APP" ]  || die "PredatorSense.app missing from ${PS_ZIPS[0]}"
[ -n "$KEXT" ] || die "PredatorSenseEC.kext missing from ${PS_ZIPS[0]}"
[ -n "$DAEMON" ] || die "predatorsensed missing from ${PS_ZIPS[0]}"

codesign --verify --deep --strict "$APP" 2>/dev/null || die "app signature is invalid"
codesign --verify "$KEXT" 2>/dev/null || die "kext signature is invalid"
ylw "app and kext signatures: valid"

SIGINFO="$(codesign -dv "$APP" 2>&1 || true)"
if printf '%s\n' "$SIGINFO" | grep -qE 'flags=.*adhoc|Signature=adhoc'; then
  ylw "signature type: ad-hoc (expected; not notarised — see docs/SIGNING.md)"
else
  ylw "signature type: not ad-hoc — check the TeamIdentifier before trusting it"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "app Info.plist is invalid"
plutil -lint "$KEXT/Contents/Info.plist" >/dev/null || die "kext Info.plist is invalid"
ylw "bundle plists: OK"

ARCH="$(lipo -archs "$APP/Contents/MacOS/PredatorSense" 2>/dev/null || true)"
case "$ARCH" in
  *x86_64*) ylw "app architecture: $ARCH" ;;
  *) die "app is not x86_64 (found: ${ARCH:-unknown})" ;;
esac
[ -x "$DAEMON" ] || die "predatorsensed is not executable"
ylw "daemon executable: yes"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
ylw "app version: $VERSION"

grn "EFI"
unzip -q "${EFI_ZIPS[0]}" -d "$TMP/efi"
CONFIG="$(find "$TMP/efi" -maxdepth 3 -type f -name 'config.plist' | head -1)"
[ -n "$CONFIG" ] || die "config.plist missing from ${EFI_ZIPS[0]}"
plutil -lint "$CONFIG" >/dev/null || die "EFI config.plist is not a valid plist"
ylw "config.plist: valid plist"

grep -q 'PredatorSenseEC.kext' "$CONFIG" \
  || die "config.plist does not reference PredatorSenseEC.kext"
ylw "PredatorSenseEC.kext: referenced in Kernel > Add"

if grep -q 'C02XXXXXXXXX' "$CONFIG"; then
  ylw "SMBIOS: placeholder serial present (expected — generate your own)"
else
  ylw "SMBIOS: no placeholder serial found — this config may contain someone's identity"
fi

OC_DIR="$(dirname "$CONFIG")"
for f in OpenCore.efi; do
  [ -f "$OC_DIR/$f" ] || die "missing $f next to config.plist"
done
[ -d "$OC_DIR/Kexts" ] || die "missing Kexts directory"
[ -d "$OC_DIR/ACPI" ] || die "missing ACPI directory"
ylw "OpenCore.efi, Kexts and ACPI: present"

echo
grn "verified: ${PS_ZIPS[0]} and ${EFI_ZIPS[0]}"
ylw "Nothing was installed. Read docs/SIGNING.md before the first launch."
