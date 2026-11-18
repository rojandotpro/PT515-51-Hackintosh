#!/bin/bash
# Build the release archives from this repository.
#
#   ./tools/package-release.sh                 # build the stack, then package 1.0.0
#   ./tools/package-release.sh 1.0.1           # package a different version
#   ./tools/package-release.sh 1.0.0 --no-build
#
# Output (in dist/):
#   PredatorSense-<version>.zip
#   PT515-51-EFI-<version>.zip
#   SHA256SUMS.txt
#   verify-release.sh
#
# The PredatorSense archive is self-contained: binaries, source, licence and the
# documentation that describes them. Links in the bundled markdown that point at
# material outside the archive are rewritten to the public repository so nothing
# in the package is broken. Run tools/verify-release.sh on the output before
# uploading.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
BUILD=1
[ "${2:-}" = "--no-build" ] && BUILD=0

OUT="$ROOT/dist"
PS_NAME="PredatorSense-$VERSION"
EFI_NAME="PT515-51-EFI-$VERSION"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pt515-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

grn() { printf '\033[32m==> %s\033[0m\n' "$*"; }

[ -f "$ROOT/predatorsense/build.sh" ] || { echo "not a repository checkout: $ROOT" >&2; exit 1; }

if [ "$BUILD" -eq 1 ]; then
  grn "build"
  ( cd "$ROOT/predatorsense" && ./build.sh )
fi

for f in PredatorSense.app PredatorSenseEC.kext predatorsensed; do
  [ -e "$ROOT/predatorsense/build/$f" ] || {
    echo "missing predatorsense/build/$f — run predatorsense/build.sh first" >&2
    exit 1
  }
done

grn "stage PredatorSense"
PS="$WORK/$PS_NAME"
mkdir -p "$PS/docs" "$PS/predatorsense"
cp -R "$ROOT/predatorsense/build/PredatorSense.app" \
      "$ROOT/predatorsense/build/PredatorSenseEC.kext" \
      "$ROOT/predatorsense/build/predatorsensed" "$PS/"
cp "$ROOT/predatorsense/daemon/local.predatorsense.daemon.plist" "$PS/"
cp "$ROOT/predatorsense/RELEASE-README.txt" "$PS/README.txt"
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$PS/"

for d in PREDATORSENSE SIGNING BUILD-YOUR-OWN-APP BUILD-REFERENCE AI-ATTRIBUTION NETWORK; do
  cp "$ROOT/docs/$d.md" "$PS/docs/"
done

cp -R "$ROOT/predatorsense/kext" "$ROOT/predatorsense/daemon" "$ROOT/predatorsense/app" "$PS/predatorsense/"
cp "$ROOT/predatorsense/build.sh" "$ROOT/predatorsense/INSTALL.md" \
   "$ROOT/predatorsense/RELEASE-README.txt" "$PS/predatorsense/"

grn "fix links outside the archive"
python3 - "$PS" <<'PY'
import glob, os, re, sys

root = sys.argv[1]
base = "https://github.com/rojandotpro/PT515-51-Hackintosh/blob/main/"
changed = 0
for path in glob.glob(os.path.join(root, "**", "*.md"), recursive=True):
    text = open(path, encoding="utf-8").read()
    def repl(m):
        global changed
        target = m.group(1)
        if not target or target.startswith(("http", "mailto:", "#")):
            return m.group(0)
        file_part, _, anchor = target.partition("#")
        resolved = os.path.normpath(os.path.join(os.path.dirname(path), file_part))
        if os.path.exists(resolved):
            return m.group(0)
        repo_path = os.path.relpath(resolved, root).replace(os.sep, "/")
        url = base + repo_path + (("#" + anchor) if anchor else "")
        changed += 1
        return "](" + url + ")"
    text = re.sub(r"\]\(([^)]+)\)", repl, text)
    open(path, "w", encoding="utf-8").write(text)
print(f"    rewrote {changed} link(s) to the repository")
PY

grn "stage EFI"
EFI="$WORK/$EFI_NAME"
mkdir -p "$EFI"
cp -R "$ROOT/efi/BOOT" "$ROOT/efi/OC" "$EFI/"

grn "clean metadata"
find "$WORK" -name '.DS_Store' -delete
find "$WORK" -name '._*' -delete
dot_clean -m "$WORK" 2>/dev/null || true

grn "archive"
rm -rf "$OUT"
mkdir -p "$OUT"
( cd "$WORK" && ditto -c -k --keepParent "$PS_NAME" "$OUT/$PS_NAME.zip" )
( cd "$WORK" && ditto -c -k --keepParent "$EFI_NAME" "$OUT/$EFI_NAME.zip" )
cp "$ROOT/tools/verify-release.sh" "$OUT/verify-release.sh"
chmod +x "$OUT/verify-release.sh"

grn "checksums"
( cd "$OUT" && shasum -a 256 "$PS_NAME.zip" "$EFI_NAME.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt )

grn "verify"
( cd "$OUT" && ./verify-release.sh . )

printf '\nArtifacts in %s\n' "$OUT"
ls -lh "$OUT"
