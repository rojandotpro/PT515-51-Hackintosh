# Wi-Fi and Bluetooth

This machine has **Intel CNVi** wireless — the Wi-Fi is integrated into the PCH, **not** a PCIe
M.2 card. A Broadcom swap is almost certainly impossible: the M.2 slot is CNVio and typically has
no PCIe lanes, so a Broadcom card will physically fit and not work.

| Radio | Hardware | Driver stack |
|---|---|---|
| Wi-Fi | Intel CNVi `[8086:a370]` / Killer 1550i (9560NGW) | AirportItlwm 2.3.0 + IOSkywalkFamily + IO80211FamilyLegacy |
| Bluetooth | Intel 9460/9560 "Jefferson Peak" `[8087:0aaa]`, USB | IntelBluetoothFirmware 2.5.1 + IntelBTPatcher + BlueToolFixup |

---

## The Wi-Fi stack

Enabled kexts, in this order:

1. `IOSkywalkFamily.kext`
2. `IO80211FamilyLegacy.kext` (the `AirPortBrcmNIC` plugin inside it must stay **off**)
3. `AirportItlwm.kext` 2.3.0

Required `config.plist` settings:

| Setting | Value | Why |
|---|---|---|
| `Kernel → Block` | `com.apple.iokit.IOSkywalkFamily`, Strategy **Exclude**, MinKernel `23.0.0`, Arch `x86_64` | macOS's own IOSkywalk must not load over the replacement |
| `csr-active-config` | `03080000` | allows the root patch and the legacy 80211 family |
| `Misc → Security → SecureBootModel` | `Disabled` | required for the same reason |
| `boot-args` | `-amfipassbeta` | AMFIPass 1.4.1 on Tahoe |

`itlwm.kext` (the non-Airport variant) is present but **disabled** — only AirportItlwm gives the
native Wi-Fi menu and `en0`.

### The part that breaks after updates

macOS updates replace system components, so **the Intel Wi-Fi root patch must be re-applied after
every macOS update**. This is the fragile part of the whole build.

> **Honest gap in this record.** Wi-Fi was repaired after 26.7.1 in a separate ChatGPT session and
> the exact steps were **not written down**. What follows is the probable procedure, reconstructed
> from the configuration that is working now. Treat it as a checklist, not as a verified recipe.

Probable recovery sequence:

1. Boot and check whether `en0` exists and has an IP (`ifconfig en0`, `networksetup -listallhardwareports`).
2. If the interface is missing, confirm the three kexts above are enabled and in that order in
   `Kernel → Add`.
3. Re-apply the **OCLP-Mod Intel Wi-Fi root patch** (the patch is wiped by every update). Use a
   build that supports Tahoe and Intel Wi-Fi; do not mix OCLP variants.
4. Verify `csr-active-config = 03080000` and `SecureBootModel = Disabled` survived the update.
5. Reboot, check `en0` again, then re-run `tools/pt515-healthcheck.sh`.

If you know the exact steps that were used, please open a PR against this file.

### Known limitations of itlwm/AirportItlwm

- AirDrop, Instant Hotspot and Continuity Camera **do not work**.
- `awdl0` has broken on point updates before (26.5.1, 26.6 beta 1); if it disappears, the root
  patch needs re-applying.
- Throughput is lower than a native Broadcom card and power management is less refined.

---

## Bluetooth

Enabled: `IntelBluetoothFirmware.kext` 2.5.1 and `IntelBTPatcher.kext` 2.5.1, with
`BlueToolFixup.kext` 2.7.3. **`IntelBluetoothInjector.kext` must stay disabled** — it conflicts
with the firmware loader on Tahoe.

`-ibtcompatbeta` is in `boot-args` for beta-build compatibility.

### How the stack fits together

The Bluetooth half of the Intel 9560 is a **USB device** (`8087:0aaa`) on the internal XHCI port
**HS06**. `IntelBluetoothFirmware.kext` cannot do anything until that device appears: its IOKit
personality matches `IOUSBHostDevice` with `idVendor 0x8087` and `idProduct 0x0aaa`, so the kext is
loaded only after enumeration. `IntelBTPatcher` and `BlueToolFixup` load without it.

That ordering is the whole diagnosis. If `kmutil showloaded` lists the patcher and the fixup but
**not** the firmware loader, the usual cause is not a kext problem — the radio is missing from the
USB tree.

```sh
./tools/bluetooth-check.sh
```

It prints the controller, the USB radio, the three kexts and a verdict with the next step.

### State on the reference unit (2026-11-19)

Bluetooth is an **open item**, and there are two distinct failure modes:

| Symptom | Meaning |
|---|---|
| Radio present in `ioreg`, firmware loaded, controller Off with address `NULL` | Controller/firmware state — toggle Bluetooth, read `bluetoothd` logs |
| Radio absent, firmware loader not loaded, controller reports `BCM_4350C2`, `NULL`, `v0 c0` | The USB device is not enumerating; nothing above the USB layer can help |

The second mode was observed on 2026-11-19, after the 26.7.3 update and an NVRAM reset. No EFI or
kext change was made in between and the same kexts still load, so treat it as an enumeration/EC
event rather than a driver regression. `ioreg` showed internal port `HS06` present and empty, while
the camera on `HS05` and a USB Ethernet adapter on `SS01` were fine. Linux had already reported the
radio on port 014 (`lsusb`: `8087:0aaa`), so the port map is correct.

`BCM_4350C2` is a placeholder, not the real chip: it is what macOS reports when no Bluetooth USB
device is attached.

Pairing works when the controller comes up; after sleep it can disappear until toggled.

### If the radio is absent

1. **Cold boot, not a restart.** Shut down, unplug the charger and every USB device, hold the power
   button for 20 seconds, then boot. This resets the embedded controller, which owns power to the
   CNVi module.
2. Run `./tools/bluetooth-check.sh` again. Enumeration usually returns on the next boot.
3. Still absent: check the BIOS wireless/Bluetooth setting and press `Fn+F3` twice (aeroplane-mode
   toggle). Wi-Fi and Bluetooth share that switch.
4. Boot Linux or Windows and check for `8087:0aaa`. If it is absent there too, the operating system
   is not the cause — the CNVi module, its USB path or the EC is. Reseating the module is the next
   physical step.
5. Resetting NVRAM does not fix this and is not required. Neither does reinstalling macOS.

Diagnostics, if you want the raw output:

```sh
system_profiler SPBluetoothDataType | head -30
kmutil showloaded --list-only | grep -iE 'IntelBluetooth|BlueTool'
ioreg -p IOUSB -l -w0 | grep -E 'idVendor"=32903|0aaa'
log show --last 5m --predicate 'process == "bluetoothd"'
```

Things already checked on this unit: kext load order, `IntelBluetoothInjector` disabled, matched
2.5.1 firmware/patcher versions, the USB map includes `HS06` as an internal port, and the radio was
present under Linux on that same port.

---

## Ethernet

Killer E3000 2.5GbE (`[10ec:3000]`, RTL8125 family) is driven by `LucyRTL8125Ethernet.kext`
1.2.3. It works without configuration and does not depend on any root patch.

---

## Verify the network state

```sh
# Interfaces and addresses
ifconfig en0
networksetup -listallhardwareports

# Which kexts are actually loaded
kmutil showloaded --list-only | grep -i -E 'AirportItlwm|IOSkywalk|IO80211|IntelBluetooth|BlueTool'

# Kernel blocks that must be present
/usr/libexec/PlistBuddy -c 'Print :Kernel:Block' \
  /Volumes/EFI/EFI/OC/config.plist | grep -A5 IOSkywalk
```
