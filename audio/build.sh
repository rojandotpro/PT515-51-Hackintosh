#!/bin/bash
# Builds AppleALC with this machine's PT515-51 layout 23 mods:
#  - mute fix (mute on pins 0x14/0x21, volume on DACs 0x02/0x03)
#  - speaker DSP: Maxx EQ (from FineTune) -> 2x gain (+6 dB) -> limiter
# Output: ~/Desktop/AppleALC-mod/out/AppleALC.kext
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/work"; mkdir -p "$W" "$HERE/out"; cd "$W"
if [ -d AppleALC/MacKernelSDK ] && [ -d AppleALC/Lilu.kext ]; then
  echo "== reusing previous download (keeps the slow one-time resource formatting cache)"
  cd AppleALC
  rm -f AppleALC/kern_resources.cpp Resources.md5
else
  rm -rf AppleALC
  echo "== cloning AppleALC + MacKernelSDK"
  git clone -q --depth 1 https://github.com/acidanthera/AppleALC.git
  cd AppleALC
  git clone -q --depth 1 https://github.com/acidanthera/MacKernelSDK.git
  echo "== fetching Lilu (DEBUG, needed to build)"
  URL=$(curl -s https://api.github.com/repos/acidanthera/Lilu/releases/latest | grep -o 'https://[^"]*DEBUG.zip' | head -1)
  curl -sL "$URL" -o lilu.zip && unzip -q lilu.zip -d lilu && cp -R lilu/Lilu.kext ./
fi
git checkout -q -- Resources/PinConfigs.kext/Contents/Info.plist 2>/dev/null || true
echo "== applying layout 23 mods"
cp "$HERE/layout23.xml" "$HERE/Platforms23.xml" Resources/ALC289/
python3 "$HERE/pinpatch.py" Resources/PinConfigs.kext/Contents/Info.plist
echo "== building (takes a few minutes)"
xcodebuild -quiet -configuration Release -arch x86_64 > "$HERE/build.log" 2>&1 || { echo "BUILD FAILED - send ~/Desktop/AppleALC-mod/build.log"; tail -20 "$HERE/build.log"; exit 1; }
rm -rf "$HERE/out/AppleALC.kext"
cp -R build/Release/AppleALC.kext "$HERE/out/"
echo; echo "DONE: $HERE/out/AppleALC.kext"
defaults read "$HERE/out/AppleALC.kext/Contents/Info.plist" CFBundleShortVersionString
