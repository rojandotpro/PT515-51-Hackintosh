# Getting started — build this Hackintosh from zero

This is the practical, end-to-end walkthrough. For *why* each setting exists, the measurements
behind it, and the things that must not be changed, read
[`BUILD-REFERENCE.md`](BUILD-REFERENCE.md).

If you have never done this before, read [`HACKINTOSH-101.md`](HACKINTOSH-101.md) first — it
explains the boot chain, kexts, ACPI and SMBIOS in plain language. Once the machine is running,
[`STABILITY.md`](STABILITY.md) is the upkeep manual.

The target is an **Acer Predator Triton 500 PT515-51** with the i7-8750H / UHD 630 / ALC289 /
Intel CNVi combination. If your machine differs, expect to change patches.

---

## 0. Before you touch anything

- **Back up** your current EFI, your data, and anything you cannot lose.
- Have a **second computer** available (for downloads and for reading this guide while the laptop
  is rebooting).
- Have a **16 GB or larger USB stick**.
- Keep a **known-good bootable USB** until the new install is proven. Do not overwrite it.
- This guide assumes you are comfortable with Terminal and with mounting EFI partitions.

> Installing macOS on non-Apple hardware is not supported by Apple. You are responsible for
> licences, data loss and any damage. This repository documents one working machine.

---

## 1. BIOS

The machine must be on **BIOS V1.13**. It is already installed on the reference unit; **do not
update it**. A BIOS update rewrites the ACPI tables and EC firmware this build depends on, and
there is no flashback recovery on this model.

Set these in the firmware setup (F2 at boot):

| Setting | Value |
|---|---|
| Secure Boot | **Disabled** |
| CSM / Legacy boot | **Disabled** (UEFI only) |
| SATA mode | **AHCI** |
| Fast Boot | Disabled (makes F12/USB boot reliable) |
| VT-d | May stay enabled — OpenCore's `DisableIoMapper` handles it |
| Boot menu | F12 enabled |

Do not change DVMT, "More VRAM", or any GPU memory setting. The UHD 630 allocates dynamically;
those settings do nothing useful and can stop the boot.

---

## 2. Prepare the installer USB

On a working Mac:

```sh
# Download the current Tahoe installer (or use the App Store)
softwareupdate --fetch-full-installer --full-installer-version 26.7.3

# Erase the USB as GPT + HFS+ (or APFS) and name it MyUSB
diskutil list
sudo diskutil eraseDisk JHFS+ MyUSB GPT /dev/diskN

# Write the installer
sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia \
     --volume /Volumes/MyUSB
```

The volume is renamed to `Install macOS Tahoe`.

### Add the EFI

Mount the USB's EFI partition (normally `diskXs1`):

```sh
diskutil list
sudo diskutil mount diskXs1
```

Copy the **contents** of this repository's `efi/` so the USB ends up with:

```
/Volumes/EFI/EFI/BOOT/BOOTx64.efi
/Volumes/EFI/EFI/OC/config.plist
/Volumes/EFI/EFI/OC/OpenCore.efi
/Volumes/EFI/EFI/OC/ACPI/...
/Volumes/EFI/EFI/OC/Kexts/...
/Volumes/EFI/EFI/OC/Drivers/...
```

```sh
cp -R efi/OC efi/BOOT /Volumes/EFI/EFI/
```

Remove macOS metadata so the firmware sees clean files:

```sh
sudo dot_clean -m /Volumes/EFI
```

### Generate **your own** SMBIOS identity

The repository ships **placeholders**:

```
SystemSerialNumber = C02XXXXXXXXX
MLB                = M0000000000000001
SystemUUID         = 00000000-0000-4000-8000-000000000001
ROM                = 112233445566
```

These will boot macOS, but **iServices (iMessage, FaceTime, App Store account features) will not
work reliably**, and everyone using this repo would share them. Generate a fresh identity:

1. Download [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS).
2. Run it, choose **Generate SMBIOS**, model **`MacBookPro16,1`**.
3. Put the generated `Serial`, `MLB`, `SystemUUID` into `config.plist` under
   **PlatformInfo → Generic**.
4. Set `ROM` to your Ethernet MAC address without colons (or any stable 12-hex-digit value).

With ProperTree:

```sh
# Or use PlistBuddy; keep a backup first
cp efi/OC/config.plist efi/OC/config.plist.bak
/usr/libexec/PlistBuddy -c 'Set :PlatformInfo:Generic:SystemSerialNumber YOURSERIAL' \
    efi/OC/config.plist
```

Repeat for `MLB`, `SystemUUID` and `ROM`, then copy the edited config to the USB again.

> **Do not change `SystemProductName`.** It must stay `MacBookPro16,1`. Older models are not
> supported by Tahoe and will break the boot; `MacBookPro15,1` is only correct as the **CPUFriend
> data-provider source model**, not as SMBIOS.

---

## 3. Install macOS

1. Plug the USB into the laptop, power on, press **F12**, choose the USB's **UEFI** entry.
2. The OpenCore picker appears. Choose **Install macOS Tahoe**.
3. In Disk Utility, erase the internal disk as **APFS / GUID Partition Map**.
4. Install. Expect several reboots; keep choosing the installer/`macOS Installer` entry until the
   desktop appears.
5. Complete Setup Assistant offline if possible.

If the picker does not appear, verify the USB is FAT32 and that `EFI/BOOT/BOOTx64.efi` and
`EFI/OC/OpenCore.efi` exist. See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 4. Move the EFI to the internal disk

Mount the internal ESP and copy the same EFI:

```sh
diskutil list
sudo diskutil mount disk0s1
cp -R efi/OC efi/BOOT /Volumes/EFI/EFI/
sudo dot_clean -m /Volumes/EFI
```

Then either select the internal disk in the BIOS boot order, or add a boot entry:

```sh
sudo bless --mount /Volumes/EFI --setBoot --file \
     /Volumes/EFI/EFI/OC/OpenCore.efi --verbose
```

Keep the USB installer until the internal boot is proven.

---

## 5. Verify the install

Run the bundled health check:

```sh
chmod +x tools/pt515-healthcheck.sh
./tools/pt515-healthcheck.sh
```

Expected results:

| Check | Expected |
|---|---|
| macOS | Tahoe 26.7.x |
| GPU | Intel UHD 630, Metal 3, internal display |
| Display | 1920×1080 at 90/120/144 Hz |
| Audio | Built-in output and input, 48 kHz |
| Wi-Fi | `en0` has an IP address |
| Bluetooth | Controller present (on this unit it may show as off until toggled) |
| Battery | Percentage and charging state |
| Trackpad | Cursor and gestures work |
| Sleep | Lid close/open wakes |
| Keystat | Lilu, VirtualSMC, WhateverGreen, AppleALC, VoodooI2C, PredatorSenseEC loaded |

Useful manual checks:

```sh
kmutil showloaded --list-only | grep -v com.apple
ioreg -rn AppleSmartBattery | grep -E 'CycleCount|MaxCapacity'
system_profiler SPDisplaysDataType | head -20
pmset -g
```

---

## 6. PredatorSense

The stack is already in the EFI as `PredatorSenseEC.kext`. Build and install the daemon and app:

```sh
cd predatorsense
sudo ./build.sh
```

Then:

```sh
# Check the daemon
echo status | nc -U /var/run/predatorsense.sock

# Open the app
open /Applications/PredatorSense.app
```

If the kext is not loaded, confirm it is first in `Kernel → Add` after Lilu and that the EFI copy
is the one being booted. Full details: [`PREDATORSENSE.md`](PREDATORSENSE.md).

---

## 7. Audio (already working, optional custom build)

The EFI ships the custom AppleALC 1.9.9 with layout 23, so internal speakers and mic should work
immediately. If you want to rebuild the custom version from source (EQ, gain, limiter, mute fix):

```sh
cd audio
./build.sh
```

Read [`AUDIO.md`](AUDIO.md) first — there are two settings that break the microphone if changed.

---

## 8. Display refresh rates

The EFI's EDID override exposes 144, 120 and 90 Hz. Change the rate in **System Settings →
Displays**, or use the scripts in [`../display/90hz/`](../display/90hz/).

- 120 Hz is the best all-round choice for video and UI.
- 144 Hz for work.
- 90 Hz for lower power; expect judder on 24/60 fps video.

---

## 9. Wi-Fi after a macOS update

This is the fragile part. macOS updates replace system components and Wi-Fi/audio can stop until
the root patch is re-applied.

After **every** update:

1. Boot and check whether `en0` has an IP.
2. If not, re-apply the OCLP-Mod Intel Wi-Fi root patch (see [`NETWORK.md`](NETWORK.md)).
3. Re-check audio; re-apply the AppleHDA/AppleHDAController patch if needed.
4. Confirm `csr-active-config` is still `03080000` and `SecureBootModel = Disabled`.
5. Re-run `tools/pt515-healthcheck.sh`.

Keep a bootable USB and an EFI backup before every update.

---

## 10. What to do when something breaks

1. **Do not change several things at once.**
2. Boot the known-good USB.
3. Compare the working `config.plist` with the broken one (`diff -u`).
4. Check the OpenCore log (`Misc → Debug → Target 67`) and the macOS unified log.
5. Search [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) and the rejected-approaches section of
   [`BUILD-REFERENCE.md`](BUILD-REFERENCE.md).
6. If you used an AI assistant, give it the **exact** error text and the current config; do not let
   it guess register values.

---

## Minimum reproducible recipe

If you only want the short version:

1. BIOS 1.13, Secure Boot off, CSM off, AHCI.
2. Copy `efi/` to a FAT32 USB (or the ESP).
3. Replace the four SMBIOS placeholders with your own.
4. Install Tahoe.
5. Copy the EFI to the internal ESP.
6. `sudo ./predatorsense/build.sh`.
7. Re-apply the Wi-Fi root patch after every macOS update.

When it boots, take a snapshot with `sudo ./tools/backup-efi.sh`, then read
[`STABILITY.md`](STABILITY.md) so the next update does not undo the work.
