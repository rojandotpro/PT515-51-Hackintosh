PredatorSense 1.0.0 — custom hardware control for the Acer Predator Triton 500 (PT515-51)
=========================================================================================

An independent replacement for Acer's Windows-only PredatorSense. Fans, CPU power profiles,
LCD overdrive, keyboard RGB and keyboard backlight, controlled from a macOS menu-bar app.

UNOFFICIAL. Not affiliated with, endorsed by or connected to Acer. "PredatorSense" and "Predator"
are Acer trademarks, used here only to name the feature being replaced.

Tested configuration
--------------------
  Laptop : Acer Predator Triton 500 PT515-51
  BIOS   : V1.13 (do not update)
  OS     : macOS Tahoe 26.7.2 (25G332), x86_64, OpenCore 1.0.8

Compatibility is per model and per firmware revision. The method can be ported to another laptop
that exposes a usable control path; these binaries cannot. No other model has been tested. See
docs/BUILD-YOUR-OWN-APP.md section 1.1 before assuming support.

Contents
--------
  PredatorSense.app                    menu-bar app (run as your user)
  predatorsensed                       root daemon
  PredatorSenseEC.kext                 kernel driver (OpenCore kext)
  local.predatorsense.daemon.plist     LaunchDaemon definition
  LICENSE                              MIT, for the original code and docs
  NOTICE.md                            third-party components and their licences

  docs/PREDATORSENSE.md                command protocol and safety model
  docs/SIGNING.md                      ad-hoc signing, Gatekeeper, verification
  docs/BUILD-YOUR-OWN-APP.md           tutorial: build this for another laptop
  docs/BUILD-REFERENCE.md              every measured value and dead end
  docs/AI-ATTRIBUTION.md               assistants used, authorship, licensing
  docs/NETWORK.md                      Wi-Fi and Bluetooth notes

  predatorsense/                       full source: kext, daemon, app, build.sh
  predatorsense/INSTALL.md             driver design and bring-up order

Verified installation
---------------------
  1. Mount the ESP and copy the kext:

       sudo diskutil mount disk0s1
       sudo rm -rf /Volumes/EFI/EFI/OC/Kexts/PredatorSenseEC.kext
       sudo cp -R PredatorSenseEC.kext /Volumes/EFI/EFI/OC/Kexts/

     It is already enabled in the shipped config.plist. Reboot before continuing.

  2. Install the daemon:

       sudo mkdir -p /usr/local/libexec
       sudo cp predatorsensed /usr/local/libexec/
       sudo chown root:wheel /usr/local/libexec/predatorsensed
       sudo chmod 755 /usr/local/libexec/predatorsensed
       sudo cp local.predatorsense.daemon.plist /Library/LaunchDaemons/
       sudo chown root:wheel /Library/LaunchDaemons/local.predatorsense.daemon.plist
       sudo launchctl bootstrap system /Library/LaunchDaemons/local.predatorsense.daemon.plist

  3. Install the app:

       sudo ditto --norsrc --noextattr PredatorSense.app /Applications/PredatorSense.app
       sudo xattr -cr /Applications/PredatorSense.app
       sudo codesign --force --deep --sign - /Applications/PredatorSense.app

  4. Verify:

       kmutil showloaded --list-only | grep PredatorSense
       echo status | nc -U /var/run/predatorsense.sock

     Healthy output contains "ok":true, "ecPresent":true and "wmiPresent":true.

Signing and Gatekeeper
----------------------
The binaries are AD-HOC SIGNED, NOT NOTARISED. They are not identified by a Developer ID, and
Gatekeeper may refuse the first launch. The safe options are: right-click the app and choose Open,
or approve it in System Settings > Privacy & Security. Do not disable Gatekeeper or SIP globally
for this app.

If Gatekeeper blocks it after you have verified the checksums, removing quarantine is acceptable:

       xattr -dr com.apple.quarantine /Applications/PredatorSense.app

See docs/SIGNING.md for verification commands, why there is no Developer ID, and how to sign your
own build if you have one.

Safety
------
This software writes to firmware interfaces that Acer never documented. It is written to fail safe:
the kernel clamps duty, enforces a thermal ceiling, and hands the fans back to the EC when the
daemon disconnects or the watchdog expires. Read predatorsense/INSTALL.md before you start, test
upward (90 % before 50 %), and keep a bootable USB containing the EFI.

Uninstall
---------
     sudo launchctl bootout system/local.predatorsense.daemon 2>/dev/null
     sudo rm -f /Library/LaunchDaemons/local.predatorsense.daemon.plist
     sudo rm -f /usr/local/libexec/predatorsensed
     sudo rm -rf /Applications/PredatorSense.app
     sudo rm -rf /Volumes/EFI/EFI/OC/Kexts/PredatorSenseEC.kext   # after mounting the ESP

Then remove the PredatorSenseEC entry from Kernel > Add in config.plist, or leave the kext absent —
OpenCore will report a missing bundle. Reboot.

Project, issues and checksums
-----------------------------
  https://github.com/rojandotpro/PT515-51-Hackintosh

MIT licensed original work; third-party components keep their own licences. See NOTICE.md.
