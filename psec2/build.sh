#!/bin/bash
# Builds PredatorSenseEC.kext, predatorsensed and PredatorSense.app
# Requires only Xcode Command Line Tools.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; BUILD="$ROOT/build"
grn(){ printf '\033[32m==> %s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m    %s\033[0m\n' "$*"; }
die(){ printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }
command -v xcrun >/dev/null || die "run: xcode-select --install"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
[ -d "$KHDR" ] || die "Kernel headers missing"
SDKVER="$(xcrun --sdk macosx --show-sdk-version)"

grn "kext"
src="$ROOT/kext/PredatorSenseEC"; obj="$BUILD/obj"; b="$BUILD/PredatorSenseEC.kext"
rm -rf "$b" "$obj"; mkdir -p "$obj" "$b/Contents/MacOS"
F=(-arch x86_64 -std=gnu++17 -fapple-kext -mkernel -nostdinc -fno-builtin -fno-common
   -fno-exceptions -fno-rtti -fno-stack-protector -mmacosx-version-min=11.0
   -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
   -isystem "$KHDR" -I "$KHDR" -I "$src" -Wall -Wno-unused-parameter -O2)
for f in PredatorSenseEC.cpp PSECUserClient.cpp kmod_info.cpp; do
  ylw "compile $f"; xcrun clang++ "${F[@]}" -c "$src/$f" -o "$obj/${f%.cpp}.o"
done
ylw "link"
OUT="$b/Contents/MacOS/PredatorSenseEC"
if ! xcrun ld -kext -arch x86_64 -syslibroot "$SDK" \
     -platform_version macos 11.0 "$SDKVER" -o "$OUT" "$obj"/*.o 2>"$obj/l1.log"; then
  ylw "retrying with -ld_classic"
  xcrun ld -kext -ld_classic -arch x86_64 -syslibroot "$SDK" \
     -platform_version macos 11.0 "$SDKVER" -o "$OUT" "$obj"/*.o 2>"$obj/l2.log" \
     || { cat "$obj"/l*.log; die "kext link failed"; }
fi
xcrun nm -u "$OUT" 2>/dev/null | grep -qE '^_(start|stop)$' && die "undefined _start/_stop"
cp "$src/Info.plist" "$b/Contents/Info.plist"
codesign --force --sign - "$b" 2>/dev/null || true
grn "kext -> $b"

grn "daemon"
xcrun swiftc -O -swift-version 5 -target x86_64-apple-macos12.0 \
  -framework Foundation -framework IOKit \
  -o "$BUILD/predatorsensed" "$ROOT/daemon/PSECBridge.swift" "$ROOT/daemon/main.swift"

grn "app"
a="$BUILD/PredatorSense.app"; rm -rf "$a"; mkdir -p "$a/Contents/MacOS" "$a/Contents/Resources"
# -parse-as-library: the app uses @main. Without it swiftc treats the input as
# top-level script code and @main has no entry point to attach to.
xcrun swiftc -O -swift-version 5 -parse-as-library -target x86_64-apple-macos13.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -o "$a/Contents/MacOS/PredatorSense" \
  "$ROOT/app/PredatorSense/PSECClient.swift" "$ROOT/app/PredatorSense/PredatorSenseApp.swift"
cp "$ROOT/app/PredatorSense/Info.plist" "$a/Contents/Info.plist"
# Icon. A Finder "paste icon" lives in an extended attribute and is lost the
# moment the bundle is replaced — baking it into Resources makes it survive
# every rebuild. Your own .icns wins; otherwise a .png is converted to a proper
# multi-resolution .icns; otherwise no icon.
ic="$ROOT/app/PredatorSense"
if [ -f "$ic/PredatorSense.icns" ]; then
  cp "$ic/PredatorSense.icns" "$a/Contents/Resources/"
  ylw "icon: your PredatorSense.icns"
elif [ -f "$ic/PredatorSense.png" ]; then
  set="$BUILD/PredatorSense.iconset"; rm -rf "$set"; mkdir -p "$set"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz       "$ic/PredatorSense.png" --out "$set/icon_${sz}x${sz}.png"     >/dev/null 2>&1
    sips -z $((sz*2)) $((sz*2)) "$ic/PredatorSense.png" --out "$set/icon_${sz}x${sz}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$set" -o "$a/Contents/Resources/PredatorSense.icns" 2>/dev/null \
    && ylw "icon: built from PredatorSense.png" \
    || ylw "icon: iconutil failed, continuing without one"
  rm -rf "$set"
else
  ylw "icon: none (drop PredatorSense.icns or .png in app/PredatorSense/)"
fi
# Menu bar template images (black + alpha; macOS tints them per appearance).
for f in MenuIcon.png MenuIcon@2x.png MenuIcon@3x.png; do
  [ -f "$ic/$f" ] && cp "$ic/$f" "$a/Contents/Resources/$f"
done
codesign --force --deep --sign - "$a" 2>/dev/null || true

echo; grn "Done -> $BUILD"
ylw "Read INSTALL.md. Test in the safe direction (higher duty) first."
