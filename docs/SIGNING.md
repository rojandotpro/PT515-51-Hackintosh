# Signing, Gatekeeper and trust

The release binaries are **ad-hoc signed, not notarised**. This page explains exactly what that
means, how to verify what you downloaded, and what to do if macOS blocks it. It also explains why
the project does not ship a Developer ID signature, and how to produce one yourself if you need it.

---

## What "ad-hoc signed" means

`codesign --sign -` creates a signature with no certificate and no identity. It is enough for macOS
to verify that the bundle has not been modified since it was signed, but it proves nothing about who
built it. It is the normal convention for Hackintosh kexts and small open-source utilities.

| Property | Ad-hoc (what ships) | Developer ID + notarisation |
|---|---|---|
| Bundle integrity check | Yes | Yes |
| Identifies the developer | No | Yes |
| Passes Gatekeeper on first launch | Usually not | Yes |
| Requires a paid Apple Developer account | No | Yes |
| Required for this app to function | No | No |

`codesign -dv` on the shipped app reports:

```
Signature=adhoc
TeamIdentifier=not set
```

That is expected, not a fault.

---

## Verify a download

Do this before installing anything. You need the two archives and `SHA256SUMS.txt` from the same
release.

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Expected output names both files and ends with `OK`. If a line says `FAILED`, delete the download and
fetch it again. Do not install a file that fails the check.

The repository also includes a verifier that checks the archives, the app signature, the kext
signature and the EFI's `config.plist` in one pass:

```sh
./tools/verify-release.sh ~/Downloads
```

It is read-only: it extracts to a temporary directory and deletes it.

### What a checksum does and does not prove

It proves the file matches the checksum published with the release. It does **not** protect you if
the release page itself was altered. For a higher level of assurance, build from source:

```sh
git clone https://github.com/rojandotpro/PT515-51-Hackintosh.git
cd PT515-51-Hackintosh
./psec2/build.sh
```

Swift and clang builds are not bit-for-bit reproducible, so compare behaviour and source, not hashes.
Reading the ~1,500 lines of the stack is realistic; that is the strongest verification available.

---

## Gatekeeper and first launch

If you download the app through a browser, macOS attaches a quarantine attribute. An ad-hoc signature
does not satisfy Gatekeeper, so the first launch may be refused with *"Apple could not verify
PredatorSense is free of malware"*.

Safe options, in order:

1. **Right-click the app → Open**, then confirm. This approves that one app.
2. If the dialog only offers *Move to Bin*, open **System Settings → Privacy & Security**, scroll to
   the blocked item, and choose **Open Anyway**.
3. Only after the checksum passes, remove the quarantine flag:

   ```sh
   xattr -dr com.apple.quarantine /Applications/PredatorSense.app
   ```

**Do not disable Gatekeeper globally and do not disable SIP for this app.** The app does not need
either. SIP is relaxed on this build for the Intel Wi-Fi root patch, which is a separate trade
documented in [`NETWORK.md`](NETWORK.md).

The daemon is not a bundle and is not launched by Gatekeeper. It runs as root from
`/usr/local/libexec/predatorsensed` and should be `root:wheel`, mode `0755`.

---

## The kernel extension

`PredatorSenseEC.kext` is ad-hoc signed and lives on the EFI System Partition, where OpenCore injects
it at boot. Injected kexts are not subject to Gatekeeper or notarisation; the signature is there for
bundle integrity and because modern macOS expects one.

Verify it directly:

```sh
codesign --verify --verbose=2 PredatorSenseEC.kext
```

The EFI itself is not signed as a whole. Its integrity comes from the checksum and from comparing
`config.plist` against the repository. Always lint a config before booting it:

```sh
plutil -lint /Volumes/EFI/EFI/OC/config.plist
```

---

## Why there is no Developer ID signature

Apple's Developer ID requires a paid membership in the Apple Developer Program. This is a free,
single-machine project; paying for a certificate would not make the software safer, and notarisation
reviews an app, not the firmware writes it performs. The honest position is to publish the source,
publish checksums, and say plainly that the binaries are ad-hoc signed.

If you fork this and have a Developer ID, do it properly:

```sh
# App: hardened runtime, then notarise and staple
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" PredatorSense.app
ditto -c -k --keepParent PredatorSense.app PredatorSense.zip
xcrun notarytool submit PredatorSense.zip --keychain-profile "notary" --wait
xcrun stapler staple PredatorSense.app

# Verify what you produced
codesign --verify --deep --strict --verbose=2 PredatorSense.app
spctl -a -vvv -t exec PredatorSense.app
```

For the kext, sign with the same identity before packaging:

```sh
codesign --force --timestamp --sign "Developer ID Application: Your Name (TEAMID)" PredatorSenseEC.kext
```

OpenCore does not require a Developer ID for injected kexts, but a consistent signature makes
verification easier. Never sign a binary you did not build.

---

## What signing does not mean

A signature — ad-hoc or Developer ID — says nothing about whether the software is correct or safe.
This stack writes to an undocumented embedded controller and to CPU power-limit registers. A signed
binary can still hang a laptop.

The safety properties come from the design, not the signature: the duty clamp, the thermal ceiling,
the watchdog, the revert-on-disconnect path, and the decision to test upward. Those are described in
[`PREDATORSENSE.md`](PREDATORSENSE.md) and
[`BUILD-YOUR-OWN-APP.md`](BUILD-YOUR-OWN-APP.md#9-safety-rules-that-are-not-optional).

---

## Report a problem

If a checksum does not match, or a release asset contains something the repository does not, open an
issue with the filename, the checksum you computed, and where you downloaded it. Do not run it first.
