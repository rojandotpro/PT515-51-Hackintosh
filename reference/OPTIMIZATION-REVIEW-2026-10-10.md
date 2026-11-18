# PT515-51 live optimization review — 2026-10-10

## Outcome

The current boot is functional. No evidence-based EFI performance change was identified that justifies risking the working configuration. This review did not alter EFI, root patches, power settings, applications, or background services. Earlier OpenCore 1.0.8 and Bluetooth 2.5.1 updates remain installed.

## Verified on this boot

- Tahoe 26.7.1 (25G241), 16 GB RAM. No swap use or compressed memory at collection time; roughly 347 GiB available on the system container. Startup load fell substantially while checking. This is not proof of idle battery consumption.
- UHD 630: Metal 3, internal Triton 500 display, 1920×1080 at 144 Hz, normal 8-bit-per-channel ARGB8888 framebuffer.
- AirportItlwm 2.3.0 loaded, rather than the backup itlwm driver. User reports working native Wi-Fi.
- IntelBluetoothFirmware and IntelBTPatcher 2.5.1 loaded; Bluetooth on and a speaker connected. Resume stability has not been tested in this review.
- AppleALC 1.9.9 and restored AppleHDA/Controller 600.2 loaded. Internal input/output expose two channels at 48 kHz. Effective alc-layout-id is 23.
- Installed AppleALC executable matches the custom build exactly (SHA256 674e7a1929a765323da5000af3cd1f343ec2845cd81fa7abd92b4cab08a1cf4f). Custom layout contains speaker EQ, 2× gain (+6 dB), and limiter. This verifies installation and layout selection, not an acoustic measurement of the actual EQ or safe maximum speaker volume.
- X86PlatformPlugin is attached; CPUFriend is loaded. Installed provider includes the appropriate 4100 MHz frequency entry and the documented MacBookPro15,1-derived map. Preserve the previously tested provider rather than regenerating it from the SMBIOS name.
- PredatorSense daemon reports performance profile, PL1 45 W / PL2 90 W, turbo on, unlocked status, successful WMI status, and no thermal/watchdog trip. At the snapshot CPU temperature was 36°C. These are controller-reported settings, not independent MSR/MMIO readback or measured sustained wattage. Manual fans were 80%; no mode was changed.
- WD SN720: NVMeFix loaded, APST reported enabled, TRIM supported. No speculative ASPM forcing needed.
- EFI plist parses and passes plutil. XML contains no duplicate dictionary keys. All enabled ACPI/kext references and their specified executable/plist files exist. Both enabled firmware drivers exist.
- All seven enabled SSDTs have valid header lengths and zero ACPI checksum. Existing DSDT and documented I2C1 trackpad findings were consulted; full AML namespace/runtime validation and sleep testing were not performed.
- Main XHC USB map contains nine entries, below the 15-port limit, with internal devices marked 255. XhciPortLimit remains off. Map labels are SS01–SS03; the historical Hackintool SS04 name must be correlated to numeric port addresses before any targeted edit, not assumed equivalent to a map label.

## Improvements worth testing, in priority order

1. **Measure the remaining trackpad polling cost.** Forced polling is retained because earlier removal broke input. An interrupt-mode experiment scoped to the real `I2C1.TPD0` may improve idle power, but requires a separate bootable test EFI, a working external input device, and before/after CPU-package-power measurements. No promise that it will work.
2. **Use an already-tested lower refresh rate for efficiency.** The current session is 144 Hz. The project records a working 90 Hz mode. Selecting it can reduce display/compositor work, especially during animation; savings are not quantified and this is not a banding fix. Do not invent additional EDID timings.
3. **Review optional background software.** Cloudflare WARP and CleanMyMac agents are installed. Presence alone does not prove a performance problem; no sustained high CPU from them was established. Disable only features you do not use, through their apps. Preserve OCLP update/patch helpers and PredatorSense safety watchdog.
4. **Optional UI preference:** Reduce Transparency is already enabled; Reduce Motion is off. Enabling Reduce Motion can reduce animation work but changes appearance and has no measured benchmark benefit here.
5. **Power modes:** Keep performance on AC when needed. For battery efficiency use the existing normal/balanced control rather than forcing maximum fans and turbo all day. Do not raise CPU limits or disable thermal protections without controlled measurements.

## Do not apply as generic optimizations

- RAM cleaners, periodic purge, swap disabling, or broad cache deletion: cached RAM improves performance, and current swap use is zero.
- Blanket Spotlight/service disabling, extra CPUFriend bias changes, forced NVMe ASPM, fabricated HDR/EDR metadata, or arbitrary framebuffer memory changes.
- Increasing speaker boost beyond the custom +6 dB without acoustic/distortion testing.
- Restoring deep hibernation or changing USB wake methods blindly. Existing standby/hibernate restrictions are deliberate workarounds for documented USB resume failures.

## Remaining limitations

Left-port USB3 sleep recovery, external-drive ejection after deep sleep, UI gradient banding, hardware hotkeys, sustained-load performance, and Bluetooth resume need their own reproducible tests. This boot being healthy does not establish those issues are fixed. ChatGPT currently holds an idle-sleep assertion, and external USB media/receiver assertions are present; account for these when testing automatic sleep.

Before future macOS updates, retain a bootable EFI backup and the current root-patch recovery workflow: EFI updates cannot prevent an OS update from replacing patched AppleHDA/wireless system components.

## Sources

- CPUFriend guidance: https://github.com/acidanthera/CPUFriend/blob/master/Instructions.md
- Dortania power management: https://github.com/dortania/OpenCore-Post-Install/blob/master/universal/pm.md
- Apple memory-pressure explanation: https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac

