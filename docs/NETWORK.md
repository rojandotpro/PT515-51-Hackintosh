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

### State on the reference unit

The stack loads, but the controller state is **inconsistent** and was not fully resolved before
publication:

- macOS has reported Bluetooth **Off**, transport `THIRD_PARTY_DONGLE`, with the controller
  address `NULL`.
- Pairing works when the controller comes up; after sleep it can disappear until toggled.

This is documented as an **open item**, not as a solved feature. Diagnostic sequence:

```sh
system_profiler SPBluetoothDataType | head -30
log show --last 5m --predicate 'process == "bluetoothd"'
ioreg -l -w0 | grep -i -E 'IOBluetooth|BCM|IntelBT'
```

Things that were already checked: kext load order, `IntelBluetoothInjector` disabled, matched
2.5.1 firmware/patcher versions, USB device present in `ioreg` under the XHCI controller.

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
