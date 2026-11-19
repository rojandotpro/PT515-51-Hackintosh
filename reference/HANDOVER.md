# Handover (latest): Acer Predator Triton 500 (PT515-51) Hackintosh

Updated: 2026-11-18. Supersedes `Handover-PT515-51-Hackintosh.md` (2026-10-10).

> **Path note (2026-11-18):** this is a historical record, written when the project folder was
> called `psec2/`. Paths below have been updated to today's `predatorsense/`; nothing else changed.

## 1. System
- Acer Predator Triton 500 PT515-51, i7-8750H, UHD 630
- macOS Tahoe 26.7 (25G229), updated to 26.7.1
- OpenCore REL-107, SMBIOS MacBookPro16,1
- Custom stack: PredatorSenseEC kext (v3.7.0), root daemon, menu-bar app
- User constraints: no third-party software references (everything built into the custom stack); use only the Hackintosh and Drivers folders and do not recreate deleted folders; the user normally deletes things manually (deletion was authorised for one session only, now over).

## 2. Current status: everything working
- Wi-Fi (AirportItlwm) broke after the 26.7.1 update. **The user has since fixed it with ChatGPT; everything works now.** The exact steps were not shared with me, so ask the user for them and record them in section 6.
- Audio had already been re-patched after the update.
- No open bugs at the time of writing.

## 3. Project layout (Mac)
Root: `/Volumes/Multimedia/Hackintosh/Final/predatorsense`
- `kext/PredatorSenseEC/` (PredatorSenseEC.cpp/.hpp, PSECShared.h, PSECUserClient.cpp, Info.plist, kmod_info.cpp)
- `daemon/` (main.swift, PSECBridge.swift, local.predatorsense.daemon.plist)
- `app/PredatorSense/` (PredatorSenseApp.swift, PSECClient.swift, Info.plist, icons)
- `build.sh`, `INSTALL.md`, `build/`, backups `.bak-1002`, `.bak-1008` (unmodified originals)

Build and install:
- Build: `sudo /Volumes/Multimedia/Hackintosh/Final/predatorsense/build.sh`
- Kext goes to `/Volumes/EFI/EFI/OC/Kexts/PredatorSenseEC.kext` (mount EFI with `sudo diskutil mount disk0s1`)
- Daemon: `/usr/local/libexec/predatorsensed`, plist `local.predatorsense.daemon`, socket `/var/run/predatorsense.sock` (test: `echo "cmd" | nc -U /var/run/predatorsense.sock`), state `/Library/Application Support/PredatorSense/state.json`
- App: `/Applications/PredatorSense.app` (SwiftUI MenuBarExtra, LSUIElement, id `local.predatorsense.app`). Tahoe install fix: `ditto --norsrc --noextattr`, `xattr -cr`, `codesign --force --deep --sign -`.
- Docs: `Hackintosh/PT515-51-macOS-Build.md` (not yet updated for brightness work or the Wi-Fi fix; backup `.bak-1006`).

## 4. Completed work
- Left USB-A diagnosis; USB map (UTBMap; HS01-03 type 3, HS04 type 9, HS05/HS06 internal).
- Display: native EDID with "Triton 500" name; 144/120/90 Hz modes (macOS reads only the 4 base-block DTDs; extra rates via same clock/htotal with longer vblank; 90 Hz DTD `9d8580a07038eb426c30aa0058c11000001a`; config B replaces the 60 Hz slot). 90 Hz verified. Banding believed to be the panel default.
- EFI backups, folder tidy, ScanPolicy change for boot speed (now 19860739 / 0x12F0D03 — adds USB device scanning so the OpenCore picker sees external clones/installers; earlier no-USB value 17763587 / 0x10F0D03 is the rollback, backup `config.pre-scanpolicy.bak`), health and idle-power checks. EFI recheck was healthy. A bootable SuperDuper clone of 26.7.3 was made to the external 274.9 GB APFS volume on 2026-11-20 and verified (see `docs/STABILITY.md`).
- **Keyboard backlight 0-100% slider (confirmed working):** hardware 0 = off, 25-100 visible. `kbPctToHw(p) = p==0 ? 0 : 24 + round(0.76*p)`; `kbHwToPct(hw) = hw<25 ? 0 : clamp(round((hw-24)/0.76),1,100)`. Daemon has a `kbpct <0-100>` command and `kbPercent` in status; the app slider is 0...100 with caption "0% turns the backlight off."
- **"Off" not holding, fixed:** the slider floor of 25 plus `kbIdleTick` re-asserting brightness every 15 s caused it. The re-assert is now skipped when brightness is 0.
- Cleanup: deleted `config-bak.plist`, `config1.plist`, `config.A-working.plist`, and junk `._Info.plist` in the kext.

## 5. Special keys: investigated, not possible, reverted
Goal was a Turbo toggle, a PredatorSense key that opens/closes the app, an Airplane key toggling Wi-Fi/BT/Location, and the app following Fn backlight changes. Findings:
- No ACPI notify (EC `_Q2C` path via `WMID` notify 0xBC fires only for other events such as AC plug), no EC RAM change (full 256-byte scan vs. control), no HID events (IOHIDManager), and the VoodooPS2 release build prints nothing with `LogScanCodes=1`.
- Setting EC bit LMIB (0x75 bit 1) did not expose the keys. The Airplane key uses a separate ACPI device `SMKB` (_HID 10251229) with no EC query. Fn brightness is handled in firmware; WMI method 21 and EC GBRL do not reflect it.
- User said to leave the keys. All key work was reverted; the kext is the original v3.7.0.
- Only untested idea: boot a Linux live USB, run `sudo showkey -s`, `acpi_listen`, `evtest` while pressing the four keys, then map any PS/2 scan codes in VoodooPS2's Custom PS2 Map to spare function keys and have the daemon listen via IOHIDManager.

## 6. EFI state (disk0s1, `/Volumes/EFI/EFI/OC`) and Wi-Fi notes
- boot-args: `-amfipassbeta alcid=23 -vi2c-force-polling -wegnoegpu -ibtcompatbeta revpatch=sbvmm -igfxnotelemetryload` (as last read, before the Wi-Fi fix; the fix may have changed the EFI).
- Kexts enabled: Lilu, CPUFriend(+DataProvider), VirtualSMC, RestrictEvents, WhateverGreen, AppleALC, LucyRTL8125Ethernet, NVMeFix, VoodooPS2Controller(+Keyboard), VoodooI2C(+Services, GPIO, Input), VoodooI2CHID, SMCBatteryManager, SMCProcessor, USBToolBox, UTBMap, IntelBluetoothFirmware, IntelBTPatcher, BlueToolFixup, IOSkywalkFamily, IO80211FamilyLegacy (AirPortBrcmNIC plugin off), AMFIPass, AirportItlwm, PredatorSenseEC.
- Disabled: itlwm, SMCSuperIO, VoodooI2CSynaptics, VoodooI2CELAN, IntelBluetoothInjector.
- Booter: AvoidRuntimeDefrag, EnableSafeModeSlide, EnableWriteUnprotector, ProvideCustomSlide, SetupVirtualMap true. Kernel: AppleXcpmCfgLock, DisableIoMapper, DisableLinkeditJettison true. Security: SecureBootModel Disabled, Vault Optional, DmgLoading Signed. Picker Builtin, Timeout 2, HideAuxiliary true.
- ACPI: SSDT-EC, SSDT-PLUG, SSDT-PNLF, SSDT-RTCAWAC, SSDT-SBUS-MCHC, SSDT-USBX, SSDT-XOSI.
- I never read the Kernel > Block/Force/Patch sections.
- **Wi-Fi fix record:** the user fixed Wi-Fi with ChatGPT after 26.7.1; the exact steps were never written down. The working config and the honest, reconstructed recovery checklist are now recorded in [`docs/NETWORK.md`](../docs/NETWORK.md#the-part-that-breaks-after-updates): IOSkywalkFamily `Kernel → Block` (Exclude, MinKernel `23.0.0`, x86_64), kext order IOSkywalkFamily → IO80211FamilyLegacy → AirportItlwm, `csr-active-config 03080000`, `SecureBootModel Disabled`, `-amfipassbeta`, and re-applying the OCLP-Mod Intel Wi-Fi root patch after every macOS update. The live config was checked on 2026-11-19 and matches this list. Treat it as a checklist, not a verified recipe.

## 7. Community research (web, forum/news summaries, unverified)
- "Golden Gate" appears to be a rumoured name for macOS 27 (iPhoneSoft, June 2026: "Big Bear", updated to "Golden Gate"). Not confirmed.
- macOS 27 reportedly requires Apple Silicon; Tahoe is the last macOS for Intel, so it is likely the last version for this laptop. Several articles say OpenCore on new releases is effectively over. No Hackintosh or OpenCore work on macOS 27 or Golden Gate was found, and no Tahoe-to-Golden-Gate UI mod. Keep EFI and project backups.
- Tahoe Liquid Glass can be reduced with settings or commands (junian.dev, Korben, Eclectic Light guides), untested.
- itlwm issue #1062 (community status report): AirportItlwm 2.3.0 (Ventura build) or the newer AirportItlwm-Tahoe 1.0.0 (reports `awdl0` working on 26.6.2 with AX210); IntelBluetoothFirmware 2.5.1 + IntelBTPatcher (needed fixes from 26.5 onward); BlueToolFixup 2.7.2; AMFIPass 1.4.1 + `-amfipassbeta`; IOSkywalkFamily replacement; SecureBootModel Disabled; csr-active-config 03080000; OCLP Modern Wi-Fi root patch (OCLP-Mod 3.1.9, OCLP 3.0.0 nightly amfipassbeta edition). Point updates have broken `awdl0` before (26.5.1, 26.6 beta 1). AirDrop, Hotspot and Continuity Camera still don't work with itlwm.
- Other tools seen: OpCore Simplify, Dortania guide Tahoe prerequisites, OCLP forks (boileh Tahoe fork, OCLP-X with Intel Wi-Fi). Unverified; check source before running any root patcher.
- Sources: github.com/OpenIntelWireless/itlwm/issues/1062; github.com/5T33Z0/OCLP4Hackintosh (AirportItllwm_Sequoia.md); appleinsider.com/articles/25/11/24/hackintosh-enjoying-its-last-hurrah-now-supporting-macos-tahoe; iphonesoft.fr/2026/06/03/macos-27-appellerait-macos-big-bear; hothardware.com/news/apple-drops-intel-macs-macos-27.

## 8. Optional pending
- Record the exact Wi-Fi fix steps from the user's ChatGPT session (section 6).
- Update the build doc (§0, §19) for the brightness changes, key findings and Wi-Fi fix.
- Declined by user: deleting old backups (`EFI-Kexts-backup-1003-0038`, `display-audit-*`, `_archive-stale-display`, `panel-audit`, `ChatGPT-Codex-artifacts`, `predatorsense/.bak-1002`, old tarballs) and unused kexts/tools in the EFI.
