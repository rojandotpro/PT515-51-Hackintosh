# Troubleshooting

Work through this in order. The single most common cause of a "new" problem is **more than one
change since the last known-good boot**.

Before anything else:

```sh
# Keep a bootable USB and a copy of the working EFI
cp -R /Volumes/EFI/EFI/OC ~/Desktop/OC-working-$(date +%Y%m%d)
```

---

## The machine will not boot / stalls at the Apple logo

1. Boot with **`-v`** and photograph the last screen. The last loaded kext line is the clue.
2. Boot the known-good USB. If that works, the problem is in the EFI you changed, not the install.
3. Compare configs:
   ```sh
   diff -u ~/Desktop/OC-working/config.plist /Volumes/EFI/EFI/OC/config.plist
   ```
4. Enable OpenCore logging temporarily: `Misc → Debug → Target = 67`, then read
   `OpenCore-YYYY-MM-DD.txt` from the ESP root.
5. Disable the kext you suspect (`Kernel → Add → Enabled = false`) and retry. One kext at a time.

**Known boot-breakers on this machine — do not do these:**

- `OSBundleLibraries = com.apple.driver.AppleACPIPlatform` in a custom kext → **hangs the boot**.
  It must be `com.apple.iokit.IOACPIFamily`.
- Changing `SystemProductName` away from `MacBookPro16,1` → Tahoe does not support the older
  models.
- Editing `boot-args` with `sudo nvram` → OpenCore deletes and rewrites it every boot; edit
  `config.plist` instead.
- Setting `AFGLowPowerState` to 0 → kills the internal microphone (not a boot failure, but it
  looks like broken audio).

## The OpenCore picker does not appear

- Confirm the USB is **FAT32** (or the ESP is), with `EFI/BOOT/BOOTx64.efi` and
  `EFI/OC/OpenCore.efi`.
- Remove macOS metadata: `sudo dot_clean -m /Volumes/EFI`.
- BIOS: **Secure Boot off, CSM off, Fast Boot off**. Press **F12** for the boot menu and choose the
  **UEFI** entry, not the legacy one.
- Confirm `Drivers/OpenRuntime.efi` and `Drivers/HfsPlus.efi` are present and enabled.

## Black internal screen, machine clearly running

Close the lid, wait for sleep, reopen. The second panel bring-up succeeds. This is a known
intermittent race in initial bring-up — see [`DISPLAY.md`](DISPLAY.md#intermittent-blank-panel-on-restart--open-low-severity).

If it is *always* black, you changed the EDID. Back up your config, then remove
`AAPL00,override-no-connect` from `DeviceProperties → PciRoot(0x0)/Pci(0x2,0x0)` and reboot. The
tested variants are in [`../display/90hz/`](../display/90hz/) if you want to compare.

## Boots to a black screen with the dGPU

The dead NVIDIA GPU must stay hidden: `-wegnoegpu` **and** `-igfxnotelemetryload` in `boot-args`.
Do not remove `-wegnoegpu`.

## No graphics acceleration / choppy UI

```sh
system_profiler SPDisplaysDataType | head -20
```

Expect `Chipset Model: Intel UHD Graphics 630`, `Metal: Supported, feature set Metal 3`, and
`VRAM (Dynamic, Max): 2048 MB` (reported via `framebuffer-unifiedmem`; the stock value is 1536 MB and is also normal). If Metal is missing:

- check `device-id` = `3E9B` and `AAPL,ig-platform-id` under `PciRoot(0x0)/Pci(0x2,0x0)`;
- check WhateverGreen is loaded (`kmutil showloaded | grep WhateverGreen`);
- check you did not raise `framebuffer-stolenmem` (it is a scanout size, not a performance knob).

## Trackpad does not work / lags

- **`-vi2c-force-polling` must be in `boot-args`.** Removing it makes the trackpad lag badly —
  tested three ways, all refuted; see the build reference §9.
- The trackpad is on **I2C1 (`00:15.1`)**, `\_SB.PCI0.I2C1.TPD0`, ELAN0504 (`04F3:3093`).
  Anything scoped to I2C0 patches the wrong device.
- `SSDT-TPD0.aml` and `SSDT-GPIO.aml` stay **disabled**.

## Keyboard works, special keys do not

Expected. See [`SPECIAL-KEYS.md`](SPECIAL-KEYS.md). Volume and mute work; the rest are
firmware-only.

## No audio

1. `ioreg -rn HDEF | grep -E 'alc-layout-id|layout-id|IOHDACodecVendorID'` — expect
   `alc-layout-id = 23`, `layout-id = 7`, vendor `0x10EC0289`.
2. Confirm `alcid=23` in `boot-args` and AppleALC is loaded.
3. Set **both** input and output to 48 kHz in Audio MIDI Setup.
4. If audio broke after a macOS update, AppleHDA/AppleHDAController may need re-patching.
5. Do **not** set `AFGLowPowerState` to 0.

Full details: [`AUDIO.md`](AUDIO.md).

## Wi-Fi gone after an update

Expected — the Intel Wi-Fi root patch is wiped by every macOS update. Follow
[`NETWORK.md`](NETWORK.md#the-part-that-breaks-after-updates).

## Bluetooth missing or off

Run `./tools/bluetooth-check.sh` first; it separates the two causes.

- **Radio absent from USB** (firmware loader not loaded, controller shows `BCM_4350C2`, address
  `NULL`, firmware `v0 c0`): cold boot — shut down, unplug power and USB, hold the power button
  20 s. If it stays absent in Linux or Windows too, it is the module, its USB path or the EC.
  NVRAM resets and macOS reinstalls do not help.
- **Radio present, controller off**: toggle Bluetooth, then read
  `log show --last 5m --predicate 'process == "bluetoothd"'`.

Full detail and the port map: [`NETWORK.md`](NETWORK.md#bluetooth). This is an open item on the
reference unit, not a solved feature.

## Sleep wakes instantly (lid open)

Caused by USB devices, not ACPI. `pmset -g log` will show `XDCI/HID Activity`. Two ACPI fixes were
tried and **failed** (`SSDT-GPRW` and USB sleep-power properties) — do not retry them.

**Workaround: unplug USB devices, or close the lid, before sleeping.** Test one device at a time to
find the culprit (a wireless dongle and an external SSD were the ones here).

## External drive "not ejected properly" on wake

Same cause as above — the drive drops off the bus during sleep and its re-enumeration is itself a
wake event. Use a powered hub, or unplug before sleeping.

## PredatorSense app does nothing

```sh
kmutil showloaded --list-only | grep PredatorSense
echo status | nc -U /var/run/predatorsense.sock
sudo launchctl print system/local.predatorsense.daemon
```

| Symptom | Cause |
|---|---|
| Kext not listed | disabled/missing in `config.plist`, or you are booting a different EFI |
| Socket missing | daemon not running — check the LaunchDaemon |
| `wmiPresent:false` | WMI device not found; check the ACPI tables and kext version |
| `kIOReturnBadArgument` (`0xe00002c2`) on every call | Swift/C struct size mismatch — use `MemoryLayout.stride`, keep `PSECStatus` a multiple of 8 |
| Sliders move, nothing happens | check `hwFanMode` in `status`; test upward (90 %) first |
| Fans stuck | `echo "fanmode auto" | nc -U /var/run/predatorsense.sock` |
| Settings reset each boot | `state.json` unwritable, or the daemon started before the kext was ready |
| `powerLocked:true` | firmware sealed MSR `0x610`; reboot. Not a bug |

Full protocol and safety model: [`PREDATORSENSE.md`](PREDATORSENSE.md).

## Reading a panic

```sh
ls -lt /Library/Logs/DiagnosticReports | head
log show --last 10m --predicate 'eventMessage CONTAINS "panic"'
```

The first line names the faulting kext or the CPU. Give an AI assistant the **full** backtrace and
your `config.plist`; do not accept a diagnosis from the backtrace alone. Add `keepsyms=1` to
`boot-args` if symbols are missing.

## Intermittent, unexplainable problems

Check the boring causes before the exotic ones:

- The project volume is external USB exFAT. Builds and I/O there are slow and can time out. Keep a
  working copy on the internal NVMe.
- The battery is degraded ("Service Recommended", ~76 %). A weak battery limits peak power and can
  cause shutdowns under load.
- Spotlight indexing external volumes causes constant USB churn. Exclude them in System Settings →
  Spotlight → Privacy.
- CleanMyMac and similar tools install LaunchDaemons and FinderSync extensions; they are a common
  source of background CPU and wake assertions. Remove them before debugging anything else.

## Collect a support bundle

```sh
chmod +x tools/collect-hackintosh-audit.sh
./tools/collect-hackintosh-audit.sh
```

The script gathers `ioreg`, `kmutil`, `pmset`, `system_profiler`, `nvram` and log excerpts into one
folder. **Review it before sharing** — `nvram` and `system_profiler` can contain serial numbers and
UUIDs.
