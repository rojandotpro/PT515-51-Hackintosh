# Build reference — the complete technical record

This is the authoritative engineering document for this machine. It contains the
reverse-engineered ACPI-WMI interface, EC register map, fan ordinals, MSR values, audio pin
configurations, EDID bytes, the verification snapshots, and the rejected approaches.

It is written so that a person **or another AI assistant** can pick this machine up cold and
continue work without rediscovering anything.

**Reading order for a new session:** this section, then
[§12 Rejected approaches](#12-rejected-approaches--do-not-retry-without-new-evidence).

> **Live state (2026-11-19):** macOS Tahoe **26.7.3 (25G342)** (published on 26.7.2; the point
> update required no EFI change), OpenCore
> **1.0.8**, SMBIOS `MacBookPro16,1`. Kext versions in the live EFI: Lilu 1.7.3,
> WhateverGreen 1.7.2, AppleALC 1.9.9, VirtualSMC 1.3.9, AirportItlwm 2.3.0,
> IntelBluetoothFirmware 2.5.1, AMFIPass 1.4.1, PredatorSenseEC 3.7.0.
>
> The document's own §0/§14/§17a snapshots are **historical** (2026-09/10) and are kept because
> the measurements in them are still valid. Where a version number differs, the live state above
> and the `efi/` folder in this repository win.

---

# Acer Predator Triton 500 (PT515-51) — macOS Build Reference

**Purpose:** complete technical record of this Hackintosh build, including reverse-engineered
hardware interfaces that exist in no public documentation. Written so that a person *or another
AI assistant* can pick up this machine cold and continue work without rediscovering anything.

**Status:** fully working. macOS Tahoe **26.6.2 (25G83)**, OpenCore **REL-107-2026-03-20**.
Last full verification: 2026-09-02 (see §17), cross-checked against a live Linux boot (see §1.1).
**Three corrections came from that Linux data — see §6.3 (PL2), §8.1 (audio pins) and §9 (I2C1).**

<details>
<summary><b>Contents</b> — 22 sections, from hardware inventory to the rejected-approaches list</summary>

| | |
|---|---|
| [0. CURRENT STATE](#0-current-state--2026-10-06-supersedes-older-sections-where-they-conflict) | [11. Performance Tuning Summary](#11-performance-tuning-summary) |
| [1. Hardware Inventory](#1-hardware-inventory) | [12. Rejected Approaches](#12-rejected-approaches--do-not-retry-without-new-evidence) |
| [2. OpenCore Configuration (current, verified)](#2-opencore-configuration-current-verified) | [13. File Locations](#13-file-locations) |
| [3. Reverse-Engineered ACPI-WMI Interface](#3-reverse-engineered-acpi-wmi-interface) | [14. Version State (historical)](#14-version-state-historical-2026-09-02--current-versions-are-in-0) |
| [4. Fan Control](#4-fan-control) | [15. Tools Used](#15-tools-used) |
| [5. Keyboard RGB](#5-keyboard-rgb) | [16. Sleep](#16-sleep--instant-wake-from-usb-unresolved-by-design) |
| [6. CPU Power Profiles](#6-cpu-power-profiles) | [17a. Verification Snapshot](#17a-verification-snapshot--2026-09-02-historical) |
| [7. PredatorSense Port](#7-predatorsense-port--software-architecture) | [18. Guidance For Whoever Continues This](#18-guidance-for-whoever-continues-this) |
| [8. Audio](#8-audio--alc289) | [6.9 PL1 hidden cap](#69-pl1-hidden-cap--final-closed-2026-10-02-do-not-retry) |
| [9. Trackpad](#9-trackpad--polling-is-correct) | [17b. Changes 2026-10-02](#17b-changes-2026-10-02) |
| [10. Display](#10-display) | [19. Display](#19-display--native-edid-name-14412090-hz-2026-10-06-verified) |

</details>

## 0. CURRENT STATE — 2026-10-06 (supersedes older sections where they conflict)

**Everything below this section is history plus detail. Where it disagrees with this section, this section wins.**

Loaded/installed versions (read from the live EFI `Kexts` folder 2026-10-06):

```
OpenCore REL-107-2026-03-20 (1.0.7)
Lilu 1.7.3   WhateverGreen 1.7.2   VirtualSMC / SMCProcessor / SMCBatteryManager 1.3.9
AppleALC 1.9.9 (custom ALC289 layout 23, see below)   NVMeFix 1.1.4   RestrictEvents 1.1.7
CPUFriend 1.3.1 (+DataProvider 1.0.1)   VoodooI2C 2.9.1 + HID   VoodooPS2Controller 2.3.7 (keyboard only)
IntelBluetoothFirmware 2.5.0   IntelBTPatcher 2.5.0 (ENABLED)   BlueToolFixup 2.7.3   (Injector disabled)
AirportItlwm 2.3.0   IO80211FamilyLegacy 12.0   IOSkywalkFamily 1.0   LucyRTL8125Ethernet 1.2.3
USBToolBox 1.2.0 + UTBMap 1.1   AMFIPass 1.4.1   PredatorSenseEC 3.7.0 (this project)
Unused on disk (not in config): NativeUSBMap.kext
boot-args: -amfipassbeta alcid=23 -vi2c-force-polling -wegnoegpu -ibtcompatbeta revpatch=sbvmm -igfxnotelemetryload
```

Status of earlier open items:

| Item | Status |
|---|---|
| Hardware mute key (old §8 "known unresolved") | **FIXED** — AppleALC `Platforms23.xml` mute flags moved to the correct nodes (speaker/headphone pins) |
| Speakers / mic | Custom `layout23.xml`: Maxx-style EQ + 2x gain + limiter on IntSpeaker; mic +10 dB pin boost and noise-reduction param. **Do not set `AFGLowPowerState` to 0** (built-in mic vanishes). Sources and build: `Hackintosh/AppleALC-mod/` |
| Bluetooth breaking after sleep | **FIXED** (IntelBTPatcher enabled + matched 2.5.0 set), user-confirmed |
| Intermittent blank panel on restart (§16.1) | **FIXED**, user-confirmed |
| Instant wake from USB (§16) | Works / accepted, no action needed |
| Left USB-A (Hackintool `SS04` = port 0x14 = UTBMap `SS01`) | Mapped (type 3). Linux logs show the RTL9201 enclosure failing at SuperSpeed with U1 errors = device-specific; **left as is** by user |
| Idle load ~12 % | Accepted |
| Display | Native BOE EDID + name `Triton 500` + 144/120/**90** Hz, 60 Hz dropped. See §19 |
| Gradient banding in macOS UI | Likely panel default (8-bit, no dithering in macOS compositor). Browser is smooth. `AAPL00,Dither` set, no confirmed effect. **Closed unless user asks for the pipe-dithering experiment** |
| PL1 45 W cap | Hidden firmware cap, closed (§6.9) |

Health check 2026-10-06 (after boot-speed change): macOS **26.7 (25G229)**, OpenCore REL-107-2026-03-20, all kexts in the table above loaded (PredatorSenseEC 3.7.0, AppleALC 1.9.9, Lilu 1.7.3, WhateverGreen 1.7.2, VirtualSMC 1.3.9, IntelBluetoothFirmware 2.5.0), display UHD 630 Metal 3 at 1920x1080 @ 90 Hz (24-bit), audio 48 kHz in/out, Bluetooth On, TRIM Yes, dual-channel DDR4-2667, 12 CPUs available. Kernel errors: only Apple cloud/Maps/locationd noise and `bluetoothd addScanFilterByUUID 0xFEAA` (harmless). Battery: 3889 mAh full charge, 279 cycles, macOS reports "Service Recommended". ScanPolicy set to 17763587 (0x10F0D03: internal SATA/NVMe, APFS+NTFS+ESP, no USB); rollback file `config.pre-scanpolicy.bak` on the EFI.

Best refresh rate: **120 Hz** for all-round and video (divides 24/30/60 fps evenly); 144 Hz for pure UI/work; 90 Hz works but judders on 24/60 fps video.

Backups: `Hackintosh/EFI-backup-20261006/` = full copy of the live EFI (config.plist identical, byte-compared). EFI also keeps `config.A-working.plist` (previous 144/120/60 display variant), `config-bak.plist`, `config1.plist`. Pre-update kexts: `Hackintosh/EFI-Kexts-backup-1003-0038/`. Archived stale display files (do not use): `Hackintosh/_archive-stale-display/`.

---

> **Read this first.** Several "obvious" configurations on this machine are wrong, and were only
> disproved by testing on real hardware. Each is documented in
> [§12 Rejected Approaches](#12-rejected-approaches--do-not-retry-without-new-evidence) with the
> evidence that killed it. **Do not re-attempt those without new evidence.** The recurring failure
> mode in this project was confident inference from partial data; the corrections all came from
> hardware measurement.

---

## 1. Hardware Inventory

| Component | Detail |
|---|---|
| Model | Acer Predator Triton 500, **PT515-51** |
| CPU | Intel Core **i7-8750H** (Coffee Lake-H, 6C/12T, 45 W, **locked/non-K**) |
| Chipset | Intel **HM370** (Cannon Lake **PCH-H**) |
| iGPU | Intel **UHD Graphics 630**, device-id `3E9B` |
| dGPU | NVIDIA RTX (2060/2080 Max-Q) — **physically dead**, disabled via `-wegnoegpu` |
| RAM | 16 GB DDR4-2667, **dual channel** (ChannelA-DIMM0 + ChannelB-DIMM0, 8 GB each) |
| Storage | **WDC PC SN720 / SanDisk** `[15b7:5002]` 512 GB NVMe, PCIe x4 @ 8.0 GT/s |
| Display | **BOE NV156FHM-N4K** (EDID `BOE082A`), 15.6" 1920×1080 IPS 144 Hz |
| Audio | Realtek **ALC289** (`VEN_10EC&DEV_0289&SUBSYS_1025132D`) |
| Wi-Fi | **Intel CNVi** `[8086:a370]`, subsystem Killer Wireless-AC 1550i (9560NGW) `[1a56:1552]`. **CNVi, not PCIe** — see §1.1 |
| Bluetooth | **Intel 9460/9560 "Jefferson Peak"** `[8087:0aaa]`, USB |
| Ethernet | **Killer E3000 2.5GbE** `[10ec:3000]` (Realtek RTL8125-family rebadge) — driven by `LucyRTL8125Ethernet` |
| Trackpad | **Elantech ELAN0504** (HID `04F3:3093`), I²C-HID on **`\_SB.PCI0.I2C1.TPD0`** (PCI `00:15.1`), IOAPIC **IRQ 90** |
| Keyboard | PS/2, 3-zone RGB backlight |
| EC | ACPI Embedded Controller, `\_SB.PCI0.LPCB.EC0` |
| BIOS | **V1.13 confirmed installed** (`dmidecode -t system`) — **do not update**, see §12 |

### 1.1 Verified against Linux (2026-09-02)

A live Linux boot (`lspci -nnk -v`, `lsusb`, `dmidecode`, `acpidump`) was used to cross-check
everything. Two corrections came out of it, plus one permanent closure.

**The dGPU is absent from the PCI bus entirely.** Not "present but failing" — `lspci` shows **no
NVIDIA device and no `00:01.0` CPU PEG root port at all**. Intel firmware hides an empty PEG port,
so the port itself vanishing is the signature of nothing being on it. Combined with the same
result under Windows, this is conclusive: the GPU does not answer PCI configuration cycles, which
happens in silicon before any firmware runs. **No VBIOS, BIOS flash or ACPI change can affect
this.** See §12.

**Wi-Fi is CNVi, not a PCIe card.** `00:14.3` is the PCH's integrated CNVi controller with the
9560 companion RF module. The M.2 slot is CNVio and typically carries no PCIe lanes, so
**swapping in a Broadcom card for native macOS Wi-Fi is probably not possible** — verify the slot
wiring before buying anything. `itlwm` is the correct and likely only option.

**ACPI dumps verified identical.** `md5(DSDT)` from the macOS-side dump and the Linux
`acpidump` match byte-for-byte (`5449381c826c6aad2a2a5914b68f1136`, 250219 bytes), and SSDT1-10
match by size. Everything in §3-§5 was reverse-engineered from the true firmware tables.

Linux additionally exposes 7 CPU power-management SSDTs that the macOS dump did not capture
(`PmRef` `Cpu0Cst`, `Cpu0Ist`, `Cpu0Psd`, `ApIst`, `ApHwp`, `ApPsd`, `ApCst`). `ApHwp` confirms
the firmware supplies HWP/Speed Shift tables — consistent with the frequency scaling behaviour
described in §11. None of these are patched or deleted by this build.

**Battery, from Linux (cross-checks the macOS SMC reading):**

```
manufacturer  Getac KT00408001      model AP18JHQ      Li-ion, 15.2 V design
charge_full         4039 mAh        (macOS SMC reported 4035 mAh — agrees)
charge_full_design  5400 mAh        -> 74.8 % health.  252 cycles per macOS.
```

**EDID — RESOLVED.** A later Linux read decoded the native panel EDID: **BOE NV156FHM-N4K,
1920x1080 @ 143.999 Hz, 8 bits per primary, RGB 4:4:4, no HDR static-metadata block.**
Confirms §10: the panel is **SDR and 8-bit**. The injected override formerly declared 10 bits
(byte 20 = `0xB5`); **this was reverted to the native `0xA5` on 2026-09-02** after the 10-bit
framebuffer was shown to survive the change. See §10.2.1 — do not re-add the 10-bit claim.

**USB inventory** (`lsusb`): Keychron Link `3434:d030`, HD User Facing webcam `1bcf:2cb0`,
Intel Bluetooth `8087:0aaa`, Realtek RTL9201 USB-Ethernet `0bda:9201` (USB 3.0 bus).

---

## 2. OpenCore Configuration (current, verified)

### 2.1 SMBIOS

```
SystemProductName = MacBookPro16,1
SecureBootModel   = Disabled
csr-active-config = 03080000
```

> **CRITICAL:** `MacBookPro16,1` is **required**. macOS Tahoe dropped support for the older
> models (MacBookPro15,1 etc.) that would otherwise be a better CPU-generation match. Changing
> SMBIOS to "match the hardware better" will break the boot. See §12.

### 2.2 boot-args

```
keepsyms=1 -amfipassbeta alcid=23 -vi2c-force-polling -wegnoegpu -ibtcompatbeta revpatch=sbvmm
```

| Flag | Purpose | Removable? |
|---|---|---|
| `keepsyms=1` | symbols in panic backtraces | yes, but useful |
| `-amfipassbeta` | required by AMFIPass on Tahoe | **no** |
| `alcid=23` | ALC289 layout — **verified correct**, see §8 | **no** |
| `-vi2c-force-polling` | trackpad polling — **required**, see §9 | **no** |
| `-wegnoegpu` | disables the dead NVIDIA GPU | **no** |
| `-ibtcompatbeta` | Intel Bluetooth on beta builds | **no** |
| `revpatch=sbvmm` | RestrictEvents — keeps OTA updates working | **no** |

> `boot-args` is in OpenCore's **NVRAM → Delete** list. OpenCore wipes and rewrites it every boot,
> so **`sudo nvram boot-args=...` does not persist** — edits must be made in `config.plist`.

### 2.3 Quirks

```
Kernel : AppleXcpmCfgLock, DisableIoMapper, DisableLinkeditJettison
Booter : AvoidRuntimeDefrag, EnableSafeModeSlide, EnableWriteUnprotector,
         ProvideCustomSlide, SetupVirtualMap
UEFI   : EnableVectorAcceleration, ReleaseUsbOwnership, RequestBootVarRouting
Drivers: HfsPlus.efi, OpenRuntime.efi
Misc/Debug: Target 0, DisplayLevel 0
```

### 2.4 Kexts (load order matters — Lilu first)

```
Lilu, CPUFriend, CPUFriendDataProvider, VirtualSMC, RestrictEvents,
WhateverGreen, AppleALC, LucyRTL8125Ethernet, NVMeFix,
VoodooPS2Controller (+ PlugIns/VoodooPS2Keyboard only),
VoodooI2C (+ VoodooI2CServices, VoodooGPIO, VoodooInput), VoodooI2CHID,
SMCBatteryManager, SMCProcessor,
USBToolBox, UTBMap, IntelBluetoothFirmware, BlueToolFixup,
itlwm, AMFIPass, PredatorSenseEC
```

**Deliberately DISABLED — enabling these breaks things:**

| Kext | Why disabled |
|---|---|
| `VoodooPS2Mouse`, `VoodooPS2Controller/VoodooInput` | trackpad is I²C, not PS/2 |
| `VoodooI2CSynaptics`, `VoodooI2CELAN` | device is HID-over-I²C → `VoodooI2CHID` is correct |
| `IntelBluetoothInjector`, `IntelBTPatcher` | superseded by `BlueToolFixup` on Monterey+; **both together break Bluetooth** |
| `AirportItlwm`, `IO80211FamilyLegacy`, `IOSkywalkFamily` | mutually exclusive with `itlwm` |
| `SMCSuperIO` | **verified 0 instances in ioreg** — monitors desktop SuperIO chips; this laptop has none |

### 2.5 ACPI

```
Enabled : SSDT-EC, SSDT-PLUG, SSDT-PNLF, SSDT-RTCAWAC, SSDT-SBUS-MCHC, SSDT-USBX, SSDT-XOSI
Patches : PNLF -> XNLF ; _OSI -> XOSI
```

SSDT-TPD0 / SSDT-GPIO / SSDT-GPRW were deleted from the ESP and their `ACPI/Add`
entries removed. **No trackpad or wake SSDT is used on this machine** — see §9 and §16.

### 2.6 DeviceProperties — `PciRoot(0x0)/Pci(0x2,0x0)`

| Key | Value | Meaning |
|---|---|---|
| `AAPL,ig-platform-id` | `0900A53E` (0x3EA50009) | CFL mobile UHD 630 |
| `device-id` | `9B3E0000` (0x3E9B) | |
| `framebuffer-patch-enable` | `01000000` | |
| `framebuffer-stolenmem` | `00003001` (0x01300000, 19 MB) | scanout allocation; not a performance knob |
| `framebuffer-fbmem` | `00009000` (0x00900000, 9 MB) | framebuffer memory; paired with unifiedmem |
| `framebuffer-unifiedmem` | `00000080` (0x80000000, 2048 MB) | **reported** VRAM only — see §12 note below |
| `enable-backlight-registers-fix` | `01000000` | KBL/CFL/ICL backlight fix |
| ~~`rps-control`~~ | *removed* | tried and reverted — raised package temps (shared 45 W budget with the CPU) for no measured benefit |
| `AAPL00,override-no-connect` | see §10 | custom EDID: 120 Hz DTD added; bit depth left **native 8-bit** (§10.2.1) |

> Do **not** also set the `-igfxblr` boot-arg — it is the global form of
> `enable-backlight-registers-fix` and was removed as redundant.

### 2.6.1 BIOS graphics options (from `BIOS_113/setup.txt` IFR dump)

The BIOS does expose a real 2048 MB aperture. Options and factory defaults, decoded from the
setup IFR (VarStore `SaSetup`, GUID `72C5E28C-7783-43A1-8767-FAD73FCCAFA4`):

| Option | Offset | Selectable values | Factory default |
|---|---|---|---|
| `GTT Size` | `0x43` | 2 / 4 / 8 MB | **8 MB** |
| `Aperture Size` | `0x44` | 128 / 256 / 512 / 1024 / **2048 MB** | **256 MB** |
| `DVMT Pre-Allocated` | `0x107` | 0, 32, 64, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60 MB | **32 MB** |
| `DVMT Total Gfx Mem` | `0x108` | 128 / 256 / MAX MB | **256 MB** |

The 64 MB reservation measured in Linux (`0x75800000-0x797fffff`) is above the 32 MB factory
default for `DVMT Pre-Allocated`, so the installed BIOS is not at that default. The IFR dump gives
defaults and selectable values only — it does not contain the live NVRAM value. Do not change any
of these BIOS settings to "fix" VRAM: the macOS patch in §2.6 works without touching firmware.

---

## 3. Reverse-Engineered ACPI-WMI Interface

This is the core of the PredatorSense port and exists in no public documentation.

### 3.1 Access path

```
Device: \_SB.PCI0.WMID              (matched via PNP0C14 + validateObject("WMBH"))
Call  : WMBH(instance, methodId, buffer)
GUID  : {7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56}   class AcerGamingFunction
```

Internally `WSMI` writes `MTID`/`WMIB` into an SMM mailbox, then writes `0xD0` to the SMI port.
`WMIB` is a 33056-bit field.

Decoded from the binary MOF in ACPI object `WQAB` using [`pali/bmfdec`](https://github.com/pali/bmfdec).

### 3.2 Method table — ARGUMENT WIDTH IS CRITICAL

> **The single most important fact in this document:** the firmware validates the *byte length*
> of the input buffer against the MOF-declared type. Passing 8 bytes to a `uint32` method fails
> silently. An early version of this driver sent 8 bytes to everything and RGB never worked.

| ID | Method | In type | **Bytes** |
|---|---|---|---|
| 1 | SetGamingProfile | uint64 | 8 |
| 2 | SetGamingLED | uint64 | 8 |
| 3 | GetGamingProfile | uint32 | 4 |
| 4 | GetGamingLED | uint32 | 4 |
| 5 | GetGamingSysInfo | uint32 | 4 |
| 6 | **SetGamingRgbKb** | **uint32** | **4** |
| 7 | GetGamingRgbKb | uint32 | 4 |
| 8/9 | Set/GetGamingProfileSetting | uint64 / uint32 | 8 / 4 |
| 10/11 | Set/GetGamingLEDBehavior | uint64 / uint32 | 8 / 4 |
| 12/13 | Set/GetGamingLEDColor | uint64 / uint32 | 8 / 4 |
| 14/15 | Set/GetGamingFanBehavior | uint64 / uint32 | 8 / 4 |
| 16/17 | Set/GetGamingFanSpeed | uint64 / uint32 | 8 / 4 |
| 18/19 | Set/GetGamingFanTable | uint64 / uint32 | 8 / 4 |
| 20 | **SetGamingKBBacklight** | **uint8[16]** | **16** |
| 21 | GetGamingKBBacklight | uint32 → uint8[16] out | 4 |
| 22/23 | Set/GetGamingMiscSetting | uint64 / uint32 | 8 / 4 |

**There is no overclocking method.** All 23 methods are fans / LEDs / RGB / profiles / misc.
PredatorSense's OC slider on Windows drove the **NVIDIA GPU via NVAPI**, not the BIOS. See §12.

### 3.3 Return status

First output byte: `0x00` = success, `0x01` = firmware error. This was only knowable by testing
a known-good method ID as a control.

### 3.4 Turbo LED

```c
#define kWMITurboLedOn  0x10001ULL
#define kWMITurboLedOff 0x1ULL      // via SetGamingLED (method 2)
```

---

## 4. Fan Control

### 4.1 Fan ordinals — MEASURED, counter-intuitive

Only ordinals **1 and 4** exist. Ordinals 2, 3 and 8 return firmware error `0x01`.

```
Fan ordinal 1 = GPU
Fan ordinal 4 = CPU
```

```c
kWMIFanSelectMask = 0x0009          // bit0 (slot0/GPU) | bit3 (slot3/CPU)
// mode bits within the uint64: bit 16 = slot0 (GPU), bit 22 = slot3 (CPU)
// duty == 100% -> kWMIFanMax (mode 2); below 100% -> custom mode
```

### 4.2 EC register map (`SSDT1`, `OperationRegion (RAM, EmbeddedControl, 0, 0xFF)`)

| Offset | Name | Meaning |
|---|---|---|
| `0x93` | F1ST | fan 1 mode/status |
| `0x94` | F1WS | fan 1 duty |
| `0x95` | F1RS | fan 1 tach |
| `0x96` | F2ST | fan 2 mode/status |
| `0x97` | F2WS | fan 2 duty |
| `0x98` | F2RS | fan 2 tach |
| `0x9A`–`0x9C` | F3ST/F3WS/F3RS | **third channel — F3RS reads 255 = not present** |
| — | MS0T | CPU temp (read by name) |
| — | MS1T | GPU temp |

```
RPM = 0x78000 / tach
```

> **Sensor channels are CROSSED relative to control:** `F2*` reports the **CPU** fan,
> `F1*` reports the **GPU** fan. Both the control mapping and the sensor mapping were corrected
> independently, from user measurements, after each was initially wrong.

### 4.3 Per-fan maximum duty (from ACPI `Method (GFMS)`)

These are **raw duty ceilings, not percentages**. Userspace speaks percent; the driver scales.

```
fan 1 -> 0x66 (102)
fan 2 -> 0x4E (78)
fan 3 -> 0x4A (74)     // reported, but no physical fan
```

This is why the GPU fan tops out around **4772 RPM** — 78/102 of the CPU fan's ceiling. That is a
hardware limit, not a bug.

### 4.4 Manual-control sequence (from firmware `Method (SFMS)`)

```
F1ST = 0x14            // bit 0x10 = manual override
F1WS = <duty>
```

Never hardcode the auto value. **Capture the pre-write mode byte and restore exactly that.**

### 4.5 Safety limits

```c
PSEC_MIN_DUTY_PERCENT    35     // applied AFTER scaling
PSEC_THERMAL_CEILING_C   88     // uses EC MS0T, not an MSR
PSEC_THERMAL_RELEASE_C   78     // hysteresis
PSEC_WATCHDOG_TIMEOUT_MS 6000
PSEC_POLL_INTERVAL_MS    2000
PSEC_FIRST_READ_DELAY_MS 20000
```

The driver tracks `fEcManualEngaged` so `revertToAuto()` unconditionally restores the EC state —
an early bug left fans pinned while reporting "auto".

---

## 5. Keyboard RGB

### 5.1 Zones — MEASURED

The keyboard has **three physical zones**, but the firmware indices are **not** 1,2,3:

```
Left = 1    Middle = 2    Right = 4        (index 3 is not wired)
```

Stored as a user-correctable `zoneMap = [1, 2, 4]` in persisted settings.

### 5.2 Per-zone colour — method 6, 4-byte packed payload

```
{ zone, r, g, b }        // one call PER ZONE
```

> Passing a zone **bitmask** (e.g. 15) causes the firmware to reject the call **and switch the
> backlight off entirely.** This produced the "keyboard goes off every time I run a command"
> symptom.

### 5.3 Effects — method 20, 16-byte descriptor

| Index | Field |
|---|---|
| 0 | mode |
| 1 | speed (0–9) |
| 2 | brightness (0–100) |
| 3 | `8` if wave |
| 4 | direction (1 or 2) |
| 5 | R |
| 6 | G |
| 7 | B |
| 9 | `1` (enable) |

```
Modes: 0 static, 1 breath, 2 neon, 3 wave, 4 shifting, 5 zoom
```

### 5.4 Backlight timeout

30-second idle timeout replicating the Windows behaviour. Idle is read from
`IOHIDSystem`'s **`HIDIdleTime`** property (nanoseconds) — this requires **no event tap and no
Accessibility permission**.

---

## 6. CPU Power Profiles

### 6.1 MSRs

```
0x606  MSR_RAPL_POWER_UNIT
0x610  MSR_PKG_POWER_LIMIT
0x1A0  MSR_IA32_MISC_ENABLE   (bit 38 = turbo disable)
```

`MSR_PKG_POWER_LIMIT` layout:

```
PL1      bits [14:0]   enable bit 15   clamp bit 16
PL2      bits [46:32]  enable bit 47   clamp bit 48
Time win bits [23:17] (PL1) and [55:49] (PL2)
         encoded as  2^Y * (1 + Z/4) * time_unit
```

### 6.2 Values — taken from Acer's own published profile table

```
PL1 = 45 W   (UNCHANGED in every profile — this is Acer's design)
PL2 = 90 W
Tau = 28 s
```

> **PL1 must stay at 45 W.** An earlier revision raised it to 60 W based on my invention;
> the user supplied Acer's actual profile table which showed PL1 constant across all profiles.

### 6.3 Measured reality — CORRECTED 2026-09-02 by Linux MSR reads

Earlier this document claimed the CPU peaked at ~75 W because of "current delivery / VR thermals".
**That was wrong.** Reading the MSRs directly under Linux shows the firmware's own limits:

```
MSR_PKG_POWER_LIMIT 0x610 = 0x0042825800dd8168
  PL1 = 360 units x 0.125 W = 45 W   enabled, clamped
  Tau = 2^14 x (1 + 3/4) / 1024      = 28 s
  PL2 = 600 units x 0.125 W = 75 W   enabled
  bit 63 (lock) = 0                  -> limits are NOT locked
MSR_RAPL_POWER_UNIT 0x606 = 0x00000000000a0e03  (power 1/8 W, time 1/1024 s)

/sys/class/powercap/intel-rapl:0/
  long_term  = 45000000 uW  window 27983872 us   (45 W / 28 s)
  short_term = 75000000 uW  window 2440 us       (75 W)
```

**The firmware PL2 is 75 W, not 90 W.** The observed 75 W peak was PL2 doing exactly its job —
not a thermal or current wall. Acer's published profile table (which we used for §6.2) evidently
does not match what this BIOS actually programs.

**Open question:** §6.2 has the driver writing PL2 = 90 mW*1000 in Performance/Turbo. The MSR is
not locked, so the write should take. But the machine still peaks at 75 W, which is suspiciously
exactly the firmware default. **Worth verifying** that the driver's PL2 write is actually landing
(read `pl2Milliwatts` back from `PSECStatus`, or check Intel Power Gadget's package power limit).
If it is landing and the CPU still stops at 75 W, then a real current/thermal wall exists after
all; if it is not landing, there is genuine headroom being left unused.

### 6.4 PL2 = 90 W — RESOLVED 2026-09-02: applied, and not needed

The driver's 90 W write **does land**. Live from the daemon socket
(`echo status | nc -U /var/run/predatorsense.sock`) with Performance selected:

```json
"powerProfile":"performance", "pl1mW":45000, "pl2mW":90000,
"powerLocked":false, "turbo":true, "fan1RPM":6301, "fan2RPM":4772
```

Package draw nevertheless tops out at **75 W** under load. That is **not** a failure and **not**
the EC overriding the MSR — no evidence of an override was ever produced. The explanation is
simpler and is proven by MSR 0x1AD below:

* All-core turbo ratio is **39 (3.9 GHz)**, single-core **41 (4.1 GHz)** — hard silicon limits on
  this locked non-K part.
* Intel Power Gadget shows `CORE REQ` reaching 4.10 GHz and all-core ~3.9 GHz **at 75 W**.
* The CPU therefore hits its maximum multiplier before exhausting 75 W. The extra 15 W has no
  higher frequency bin to be spent on, so it is simply never drawn.

**Conclusion: 90 W is correctly configured, unreachable, and irrelevant to performance.**
Do not spend further effort on it. Do not add MSR rewrites to the polling loop to "fight the EC" —
there is nothing to fight, and re-writing MSR 0x610 every 2 s from a kernel timer is cost without
benefit.

### 6.5 Turbo ratios and locks (Linux MSR reads, 2026-09-02)

```
MSR_PLATFORM_INFO   0xCE  = 0x0008083bf1011600
    max non-turbo ratio = 0x16 = 22   -> 2.2 GHz base
    max efficiency ratio = 0x08 = 8   -> 800 MHz LFM  (matches CPUFriend LFM 0x08)

MSR_TURBO_RATIO_LIMIT 0x1AD = 0x0000272728282929
    1C 0x29=41  2C 0x29=41  3C 0x28=40  4C 0x28=40  5C 0x27=39  6C 0x27=39
    -> 4.1 GHz single core, 3.9 GHz all-core. Exactly Intel spec; nothing detuned.

MSR_FEATURE_CONTROL 0x03A = 0x0000000000020005
    bit 0 = 1  -> CFG LOCK IS SET.  AppleXcpmCfgLock is REQUIRED. Confirmed.

MSR_IA32_MISC_ENABLE 0x1A0 = 0x0000000000850089
    bit 38 = 0 -> turbo is enabled.

MSR 0x150 (OC mailbox) read back 0x00000000000185c4 without faulting, but a successful *read*
says nothing about whether *writes* are honoured. Undervolting remains untested and unrecommended.
```

The 3.9 GHz all-core ratio matches the ~3.86 GHz average seen in Intel Power Gadget under load —
further confirmation that frequency behaviour is correct, not throttled.

### 6.4 CPUFriend

`CPUFriendDataProvider.kext` is a **codeless** Lilu plugin whose personality carries
`cf-frequency-data`, generated by CPUFriendFriend from MacBookPro15,1 vectors.

```
LFM multiplier = byte offset 4 of each FrequencyVector
    0x0D = 1300 MHz     0x08 = 800 MHz
Frequencies dict maps max-turbo MHz -> vector index
```

Settings used: **target model `MacBookPro15,1`**, LFM `08`, EPP `80`, Perf Bias `05`,
MacBook Air options `N`.

### 6.6 CPUFriendFriend target model — MUST be MacBookPro15,1

`cf-frequency-data` embeds an `IOPlatformPowerProfile` whose `Frequencies` dictionary maps
**max-turbo MHz -> vector index**. XCPM looks up this CPU's max turbo (**4100**) in that map.

```
CORRECT (MacBookPro15,1)   Frequencies {'4100':0, '4300':1, '4500':2, '4600':2, '4800':3, '5000':4}
                           5 vectors, LFM byte4 = 0x08     <- correct; idle re-measured 2026-09-02 at ~2.6 W

WRONG   (MacBookPro16,1)   Frequencies {'4500':0, '4800':1, '5000':2}
                           3 vectors, no 4100 key          <- installed 2026-09-02, reverted same day
```

**Benchmark figures previously attached to these two lines (GB7 5744 / 5345) have been removed.**
They were measured in different thermal states and are not a valid comparison. The 6.51 W idle
figure was also not reproducible: the same correct file measured **~2.6 W** on a quiet system.
Treat any single benchmark run on this chassis as unreliable unless taken from a cold start —
see §6.7.

Entering the SMBIOS model (`MacBookPro16,1`) is a natural mistake and produces a data provider
with **no vector for a 4.1 GHz CPU**. This is the more likely cause of the 6.9 % multi-core
regression than EPP alone. A known-good copy of the correct Info.plist is worth keeping —
`CPUFriendDataProvider.kext` is codeless, so restoring it is just replacing
`Contents/Info.plist` inside the bundle.

**Measured result:** idle **12.59 W → ~2.6 W**, MIN frequency **1.2 → 0.7 GHz**,
correct 4.1 GHz turbo bin. (An intermediate 6.51 W reading was recorded but did not
reproduce; ~2.6 W is the figure measured on a quiet system, 5 samples.)

---

### 6.7 Benchmarking this chassis — read before trusting any score

Every performance conclusion in this document that rested on a single Geekbench run has had to
be retracted at least once. The cause is the chassis, not the configuration.

**Why scores drift downward across a session.** PL1 is a **28-second moving average** on a 45 W
part in a thin chassis. A multi-core run leaves the package hot and the sustained-power budget
partly spent. A second run started minutes later begins from a worse thermal position and scores
lower — producing a clean monotonic decline that looks exactly like a configuration regression
and is not one. Runs taken back-to-back are measuring cooldown, not settings.

**Observed spread on identical, verified-correct configuration (EPP `0x80`, 4100 map):**

```
5744    earlier session, cold
5236    2026-09-02, after a session of repeated runs
```

That is a **9 % spread with nothing changed**. Any effect smaller than ~10 % is undetectable on
this machine without a cold-start protocol.

**Cold-start protocol — required for any A/B claim:**

1. Quit all load (VMs, browsers, Geekbench itself). Reboot for a clean slate.
2. Idle **15 minutes**, lid open, on AC.
3. Verify cold: `sudo powermetrics --samplers smc -n1 | grep -i "CPU die"` — near ambient, not 60 °C+.
4. Run **once**. Record the score *and* the result URL.
5. Wait **15 minutes** before any further run.

**Diagnostic rule.** Single-core has measured **1338–1360 across every configuration tried**
(EPP `0x80`, EPP `0x00`, both frequency maps). Single-core is largely thermally insensitive on a
6-core part. **If single-core is in that band, the CPU is configured correctly** and a low
multi-core score is thermal, not a power-management fault. Check fan RPM in PredatorSense before
touching CPUFriend.

**Open item:** the gap between the 5744 cold baseline and current cold runs is unexplained and is
*not* attributable to EPP or the frequency map, both of which have been controlled for. If a
genuine cold run still lands near 5236, investigate the chassis — fan RPM under load, thermal
paste age (this unit is a 2019 chassis), and intake dust — not the OpenCore configuration.

---

### 6.8 PL1 45 W is enforced by the EC — CLOSED 2026-09-02, do not retry

**The sustained ceiling is not ours to set.** Instrumented Geekbench run:

```
74.9 W  3782 MHz  67 C    <- PL2 burst, exactly as configured
74.7 W  3712 MHz  76 C
--------- tau expires ---------
44.7 W  3100 MHz  60 C    <- clamped, and the die is 40 C below Tjmax
44.8 W  3109 MHz  61 C
```

The CPU is **power-limited, not thermally limited** — ~30 C of headroom sits unused.

**What was tried, and failed:**

1. `PSEC_PERF_PL1_MW = 65000`, written once at profile-switch time (v3.4.0/3.5.0).
   `ioreg` reported `PL1_mW = 65000`, the MSR read-back at write time succeeded,
   **and the package still clamped to 44.8 W.** The Acer EC restores its own PL1
   a few seconds into sustained load.
2. Re-asserting PL1 from the 2 s poll loop whenever the MSR was seen to drift
   (v3.5.0). **Also failed** — sustained power stayed at 44.8 W and no clawback
   was logged. The EC wins below the OS.

**Conclusion: 45 W sustained is a hard floor from macOS.** Reverted to
`wantPl1mW = fBasePl1mW` in v3.7.0. PL2 (75 W burst) still works and is kept.

**The only remaining lever is undervolting** — at a fixed 45 W, less voltage buys
more frequency. MSR 0x150 (OC mailbox). Untested here, and Intel disabled that
mailbox in microcode for Plundervolt (CVE-2019-11157) on many 8th-gen units, so
it may be a no-op on BIOS V1.13. Test the write and read it back before trusting it.

**Linux cross-check completed 2026-09-02 — the ceiling is firmware, not macOS:**

```
MSR 0x610 = 0x0042825800dd8168
  PL1 = 360 * 0.125 W =  45 W   enabled, clamp ON, window 28 s
  PL2 = 600 * 0.125 W =  75 W   enabled, window ~2.4 ms
  bit 63 (LOCK)       =  0      <- NOT locked
MSR 0x606 = 0x000a0e03   power unit 0.125 W, time unit 1/1024 s
MSR 0x1A0 bit 38 = 0     turbo enabled
MSR 0x3A  bit 0  = 1     CFG lock (as documented)
MSR 0x1FC = 0x002c005d   bit 0 = 1, BD PROCHOT enabled but never asserted
```

* **Linux sees the same 45 W PL1 and sustains 3199-3200 MHz** under `stress-ng -c 12`
  — matching macOS's 3100-3150 MHz. The limit is identical across both operating
  systems, so it is firmware, not a macOS or kext defect.
* **Not thermal, conclusively.** All six `/sys/.../thermal_throttle/*` counters
  read **0** — zero throttle events ever — at 58 C against a 100 C limit.
* `MSR_CORE_PERF_LIMIT_REASONS` (0x690) read **0x0 throughout**, including while
  clamped. This SKU does not populate the register; the read is **inconclusive**,
  not evidence of "no limiter". Do not cite it either way.
* `MSR 0x150` (undervolt mailbox) probe returned 0. The write did not fault, but 0
  is also what a locked mailbox returns — **inconclusive**.

**The one experiment never run** (deliberately deferred): the PL1 lock bit is clear,
so write `0x0042825800dd8208` (PL1 -> 65 W) from Linux under load and watch whether
`0x610` holds or snaps back to `...8168`. If it **holds**, the EC is not the culprit
and there is a macOS-side path still unfound — reopen this section. If it **reverts**,
firmware wins in every OS and undervolting is the only remaining lever.

**Ruled out as causes of the score gap:** memory (2x8 GB SK Hynix, dual-channel
ChannelA+ChannelB, DDR4-2667 — optimal), adapter (battery never discharges under
load), thermals, turbo ratios, EPP, frequency map.

---

## 7. PredatorSense Port — Software Architecture

Three components. **No third-party dependencies** — this was an explicit project constraint.

```
kext/PredatorSenseEC/     IOKit driver — IOResources matching
  PSECShared.h            shared ABI (kext <-> daemon)
  PredatorSenseEC.cpp     WMI + EC access
  PSECUserClient.cpp      gMethods[] dispatch table
daemon/                   root daemon, owns IOKit; GUI never touches IOKit
  main.swift              CLI + socket + settings persistence
  PSECBridge.swift        Swift mirror of the C ABI
app/PredatorSense/        SwiftUI MenuBarExtra GUI (LSUIElement)
```

Settings persist to `/Library/Application Support/PredatorSense/state.json` and are restored at
boot, so the app never needs to be opened.

### 7.1 Hard-won implementation notes

| Issue | Resolution |
|---|---|
| `OSBundleLibraries` | must be `com.apple.iokit.IOACPIFamily`. Using `com.apple.driver.AppleACPIPlatform` **causes boot hangs** |
| `IOExternalMethodDispatch` | requires **exact** struct size match |
| Swift/C struct ABI | `MemoryLayout.size` excludes trailing padding, C `sizeof` includes it. Keep `PSECStatus` a multiple of 8 and use `MemoryLayout.stride`. A mismatch gave `kIOReturnBadArgument` (0xe00002c2) on every call |
| Method ordering | `gMethods[]`, `kPSECMethod*` and Swift `PSECSelector` must stay in lockstep |
| `@main` build | needs `-parse-as-library` |
| Daemon boot restore | `restoreSettings()` must run **after** `listen()`, else the socket is deaf during boot |
| WMI gating | WMI calls must not sit behind an `if (!fEC) return` guard |
| `NSColorPanel` | cannot open from `MenuBarExtra` in an `LSUIElement` app without `NSApp.activate(ignoringOtherApps:)` |
| `ScrollView` in `MenuBarExtra` | has no intrinsic height → collapses to an empty popover. Use a plain `VStack` |

A build-time check verifies every `k*` / `PSEC_*` symbol used in `.cpp` exists in the header —
added after a header rewrite silently deleted the turbo LED constants.

---

## 8. Audio — ALC289

```
alcid=23        (AppleALC layout 23)
```

**Layout 23 is correct and this is settled by hardware evidence.** ALC289 pin configs by layout:

| Layout | Internal mic | Speaker(s) | Jack mic | HP |
|---|---|---|---|---|
| **23 (in use)** | **0x13** | 0x14 | **0x1b** | 0x21 |
| 33 / 93 | 0x12 | 0x14 + **0x17** | 0x19 | 0x21 |
| 11 | 0x12 | 0x14 | 0x19 | 0x21 |

Layout 33 was tested to see whether a second speaker pin (`0x17`) was wired. **Result: the
internal microphone stopped working**, proving the mic is on `0x13`/`0x1b`. Since 93 uses the same
mic pins as 33, it is ruled out too. **No stock ALC289 layout pairs `0x13` mics with dual
speakers**, so layout 23 is the correct and final choice.

**Nothing can be ported from the Windows Realtek driver.** `HDXACERNB.inf` contains no
`PinConfigOverrideVerbs`; the Acer extension INF is APO/effects registry keys only. Windows uses
the BIOS-programmed codec defaults — exactly what AppleALC reads.

**Waves MaxxAudio cannot be replicated.** It is a Windows APO (userspace DSP,
`MaxxAudioRender64.dll`, ~23 MB) with no macOS equivalent.

### 8.1 BIOS-programmed pin configuration (from Linux, definitive)

`cat /proc/asound/card0/codec#0` on a live Linux boot gives the pin defaults the firmware
actually programs. **This is ground truth** — it is what Windows uses and what AppleALC's
ConfigData is trying to reproduce.

| NID | Pin Default | Meaning |
|---|---|---|
| 0x12 | `0x40000000` | unused |
| **0x13** | **`0xb7a60130`** | **[Fixed] Mic, Mobile-In, Digital — INTERNAL MIC** |
| **0x14** | **`0x90170110`** | **[Fixed] Speaker, Internal — INTERNAL SPEAKER** |
| 0x16 | `0x411111f0` | **unconnected** |
| **0x17** | **`0x411111f0`** | **UNCONNECTED — there is NO second speaker** |
| 0x18, 0x19, 0x1a | `0x411111f0` | unconnected |
| **0x1b** | **`0x03a11040`** | **[Jack] Mic, External Left — HEADSET MIC** |
| 0x1e | `0x411111f0` | unconnected |
| **0x21** | **`0x03211020`** | **[Jack] HP Out, External Left — HEADPHONE** |

Compared with AppleALC layout 23's ConfigData:

```
layout 23 :  0x13 b7a60130   0x14 90170110   0x1b 03811040   0x21 03211020
firmware  :  0x13 b7a60130   0x14 90170110   0x1b 03a11040   0x21 03211020
                  MATCH           MATCH        differs           MATCH
```

**Three of four are byte-identical. Layout 23 is the correct layout for this board — settled.**

The single difference is NID 0x1b bits[23:20]: layout 23 declares `8` (Line In), firmware
declares `A` (Mic In). Cosmetic in practice — the headset mic works — and correctable with
`alcverbs=1` + an `alc-verbs` property if it ever matters. **Not worth changing while audio works.**

**NID 0x17 being `0x411111f0` permanently closes the dual-speaker question.** Layouts 33 and 93
drive 0x17 as a second speaker; on this board that pin is not wired, so those layouts would drive
nothing while breaking the mic (as the hardware test showed). There is no fuller sound to recover.

**Verified live (ioreg on `HDEF`):**

```
"alc-layout-id" = <17000000>   = 23   <- the layout AppleALC actually uses
"layout-id"     = <07000000>   = 7    <- AppleALC's substitute for AppleHDA
```

Two properties, two jobs. `alc-layout-id` is the real one; a `layout-id` of 7 is **not** a
misconfiguration and must not be "fixed".

`IOHDACodecVendorID = 283902601` = `0x10EC0289`, confirming ALC289.

**(Historical — FIXED 2026-10-03, see §0):** the hardware **mute key** did not mute the built-in speakers/jack. The cause was AppleALC mute flags on the wrong nodes, not EC/HID; fixed in the custom layout 23 platform file.

**Sample rates must match.** Built-in input and output both set to **48000 Hz** in Audio MIDI
Setup. A mismatch causes the output stream to drop when the microphone is activated.

**Codec idle pop:** the ALC289 powers its amplifier down when idle; the click on resume is that
amp re-engaging. Every AppleALC layout for this codec sets `AFGLowPowerState`, so it is inherent
to the profile. No macOS-side fix exists.

---

## 9. Trackpad — Polling Is Correct

```
-vi2c-force-polling        REQUIRED
SSDT-TPD0.aml   disabled
SSDT-GPIO.aml   disabled
```

### 9.1 Established facts

> **CORRECTION (2026-09-02).** Everything below originally referenced
> `\_SB.PCI0.I2C0.TPD0`. **That is the wrong instance.** The DSDT declares four `TPD0` devices
> (under I2C0, I2C1 and two further scopes). Linux reports the live one as:
>
> ```
> /sys/bus/acpi/devices/ELAN0504:00/path = \_SB_.PCI0.I2C1.TPD0     status = 15 (0x0F)
> i2c-ELAN0504:00 -> /sys/devices/pci0000:00/0000:00:15.1/i2c_designware.1/i2c-1/
> ```
>
> **The trackpad is on I2C1 = PCI `00:15.1`.** The `SSDT-TPD0-GPIO` attempt in §12 was scoped to
> `_SB.PCI0.I2C0.TPD0` and therefore patched a device that is not the trackpad — that experiment
> proves nothing about the GPIO approach. The *polling-removal* test (no SSDTs active) does still
> stand as evidence, since it involved no scoping at all.

```
Device : \_SB.PCI0.I2C1.TPD0,  _HID "ELAN0504" (TPDT==5 && EC0.TPTP()==2), _CID "PNP0C50"
HID    : 04F3:3093, driven by hid-multitouch under Linux
IRQ    : IOAPIC 90 — identical to the macOS IOInterruptSpecifiers <5a00000003000000>
GPIO   : \_SB.PCI0.GPI0 -> _HID returns "INT3450" (PCH-H)  [confirmed via ioreg]
         Windows iaLPSS2_GPIO2_CNL.inf binds INT3450 (PCH-H) / INT34BB (PCH-LP) — matches
VoodooGPIOCannonLakeH matches INT3450 and IS "registered, matched, active" in ioreg
macOS already has a working interrupt:
         IOInterruptControllers = ("io-apic-0")
         IOInterruptSpecifiers  = (<5a00000003000000>)     -> IOAPIC vector 0x5A (90), level
```

### 9.2 The firmware's own `_CRS` logic

```asl
Method (_INI) {
    If ((OSYS < 0x07DC)) { SRXO (GPDI, One) }
    INT1 = GNUM (GPDI)          // GPIO pin  — computed at RUNTIME from NVS
    INT2 = INUM (GPDI)          // APIC vector — computed at RUNTIME
    If ((TPDM == Zero)) { SHPO (GPDI, One) }   // host GPIO pad ownership
}
Method (_CRS) {
    If ((OSYS < 0x07DC)) { Return (SBFI) }
    If ((TPDM == Zero))  { Return (Concat(I2CM(...), SBFG)) }   // GPIO mode
                           Return (Concat(I2CM(...), SBFI))     // APIC mode
}
```

`GPDI` is a 32-bit NVS field (DSDT line ~827). **The GPIO pin cannot be determined statically.**

### 9.3 Why polling stays

Three separate hypotheses were tested against hardware and **all three were refuted**:

1. *"The SSDT hardcodes the wrong GPIO pin (0x33)"* — true, but that SSDT was **disabled** anyway.
2. *"`GPHD` makes GPI0 report `PNP0C02` so VoodooGPIO can't bind"* — **refuted**: ioreg shows
   `INT3450` and VoodooGPIO **is** bound.
3. *"The firmware's APIC interrupt works; just remove the polling flag"* — **refuted**: removing
   `-vi2c-force-polling` (with no ACPI changes at all) made the trackpad **lag badly**.

A fourth attempt — overriding `_CRS` to return `ConcatenateResTemplate(SBFB, SBFG)` with a
`_CRS`→`XCRS` rename — also failed, and in hindsight was actively harmful: it replaced a working
APIC interrupt with a `GpioInt` for a pad the host does not own (because `SHPO` is only called
when `TPDM == Zero`).

**Linux uses the same IRQ 90 that macOS is given**, and `hid-multitouch` binds successfully — so
the hardware and the interrupt route are fine. The failure is specific to VoodooI2C's handling.

**Conclusion: VoodooI2C cannot drive this trackpad via interrupts on this board. Polling is the
correct configuration.** The cost is a small amount of extra CPU wakeup activity and nothing
perceptible.

**If anyone ever does reopen this**, the one thing that was never tried correctly is a GPIO/`_CRS`
change scoped to **I2C1**, since every previous attempt aimed at I2C0. That is not a
recommendation — the polling result stands on its own — but it is the only untested variant.

---

## 10. Display

### 10.1 Panel

```
BOE NV156FHM-N4K  (EDID id BOE082A), 15.6" 1920x1080 IPS 144 Hz, 141 ppi
```

Measured (Notebookcheck, same panel):

| Metric | Value |
|---|---|
| sRGB | 93 % |
| AdobeRGB | 60 % |
| Display-P3 | 64.6 % |
| ΔE out of box | 3.22 |
| ΔE calibrated | 1.5 |
| White point | 7290 K |
| Brightness / contrast | 288 cd/m² / 1309:1 |

**Not HDR.** The EDID has **zero extension blocks**, so there is no CTA-861 HDR Static Metadata
block. DisplayHDR 400 is not supported and cannot be enabled. What Safari does with HDR YouTube
is macOS **EDR tone mapping**, not HDR output.

Bit depth is **unverified** — no review states 6-bit+FRC vs true 8-bit; reseller datasheets claim
true 8-bit. (Earlier notes in this project asserted 6-bit+FRC; treat that as unproven.)

### 10.2 Custom EDID (`AAPL00,override-no-connect`)

```
00ffffffffffff0009e52a0800000000
011c0104a523137802de50a3544c9926
0f505400000001010101010101010101
0101010101019d8580a070383e406c30
aa0058c11000001a9d8580a070387d46
6c30aa0058c110000000000000fc0054
7269746f6e203530300a20209d8580a0
703822416c30aa0058c11000001a001e
```

**One modification from the native EDID:**

1. **Added a 120 Hz DTD** in descriptor slot 3 (so macOS renders at a cadence it likes).
   Final DTDs: **144 Hz / 60 Hz / 120 Hz**. Verified working.

### 10.2.1 Byte 20 reverted to native `0xA5` — 2026-09-02

This EDID previously declared **10 bits per primary** (byte 20 = `0xB5`, bits [6:4] `011`) on
the belief that it was required to obtain a 10-bit framebuffer. **That belief was wrong.**

Reverted to the panel's true value `0xA5` (8-bit, matching the Linux EDID read in §1.1), checksum
recomputed `0x0E -> 0x1E`. After reboot:

```
system_profiler SPDisplaysDataType
  Framebuffer Depth: 30-Bit Color (ARGB2101010)     <- UNCHANGED
```

**macOS allocates the 10-bit framebuffer regardless of the EDID bit-depth byte.** The `0xB5`
claim was never load-bearing — it bought nothing and merely made the descriptor contradict the
hardware. **Do not re-add it.**

Secondary motivation: an intermittent blank panel on restart (rare; recovered by closing and
reopening the lid, i.e. a sleep/wake cycle re-running panel bring-up). The connector negotiating
against a descriptor that contradicts the hardware was the leading suspect. **Whether this fixes
that fault is unproven** — the fault was too rare to confirm quickly. The revert is kept on its
own merits regardless of the outcome. See §16.

**DTD field layout** (18 bytes each, starting at offset 54):

```
bytes 0-1  pixel clock / 10 kHz (little-endian)
byte  2    HActive low 8      byte 3  HBlank low 8
byte  4    HActive high 4 (bits 7:4) | HBlank high 4 (bits 3:0)
byte  5    VActive low 8      byte 6  VBlank low 8
byte  7    VActive high 4 | VBlank high 4
```

**Checksum:** `byte127 = (256 - sum(bytes 0..126)) % 256`. Verify with `sum(all 128) % 256 == 0`.

### 10.3 Colour profile

Free ICC measured on this exact panel (i1Pro 2):
`https://www.notebookcheck.net/uploads/tx_nbc2/Triton500.icm`

> **Do not** use `Trit500.icm` from Notebookcheck's *other* PT515-51 review — that unit had an
> **AUO B156HAN08.2** panel.

Install to `~/Library/ColorSync/Profiles/`. **Caveat:** it is another unit's measurements;
published data for this same panel model varies by 540 K in white point. For colour-critical work
a colorimeter is required.

### 10.4 Media playback

UHD 630 hardware-decodes **HEVC Main10** and **VP9 Profile 2**. It has **no AV1 decoder**
(AV1 begins with Tiger Lake / Gen12). This is why HDR YouTube works in Safari (served VP9 P2) and
struggles in Chrome (served AV1 → software decode).

IINA settings that work (`gpu-next` is **NOT available** — IINA's bundled mpv lacks libplacebo):

```
tone-mapping     = bt.2390
hdr-compute-peak = yes
Hardware decoding = Auto        -> videotoolbox, p010 (HW) 10-bit surface
```

### 10.5 Resolution guidance

`2560×1440` is GPU downscaling to the 1080p panel, not real QHD — softer, non-integer resampling,
and costly on this iGPU. HiDPI at 1080p logical requires a 3840×2160 framebuffer (4× the pixels)
and is impractical here. **Use native 1920×1080.**

---

## 11. Performance Tuning Summary

| Change | Effect | Verified |
|---|---|---|
| CPUFriend data provider | idle 12.59 W → 6.51 W; MIN 1.2 → 0.7 GHz | yes, Intel Power Gadget |
| `rps-control` | GPU ramps to GFX REQ **1.10 GHz** (UHD 630 max 1.15); parks at 0.00 at idle | yes, Power Gadget |
| 120 Hz EDID mode | working | yes |
| 10-bit EDID claim (byte 20 `0xB5`) | **reverted 2026-09-02** — framebuffer stays 30-bit without it, so it bought nothing (§10.2.1) | no |
| `Misc/Debug/Target = 0` | slightly faster boot | cosmetic |

**macOS-side, still the largest untested win:**
System Settings → Accessibility → Display → **Reduce transparency** (and **Reduce motion**).
Every blurred surface is a live per-frame gaussian blur on the system's bottleneck GPU.

**Known open item:** ~12 % core utilisation at idle with cores waking to 4 GHz — an unidentified
background process. Check Activity Monitor sorted by CPU.

### 11.1 Power-management settings (applied 2026-09-02, `pmset`)

| Setting | Value | Why |
|---|---|---|
| `lowpowermode` (battery) | **0** | was `1` — macOS was throttling all battery-powered work |
| `powernap` | **0** | was `1` — periodic wakes for iCloud/mail; a spurious-wake source |
| `hibernatemode` | **0** | was `3` — hibernation is unreliable on hackintoshes and costs SSD writes |
| `standby` | **0** | was `1` — prevents deep hibernate after `standbydelaylow` |
| `disksleep` | **10** | `0` is rejected by macOS as inconsistent with system sleep enabled |
| `womp` | **0** | Wake-on-LAN off |

Trade-off of `hibernatemode 0`: if the battery fully dies during sleep, unsaved work is lost.
Note `/var/vm/sleepimage` did not exist on this machine even with `hibernatemode 3`.

**Battery health (2026-09-02):** full-charge capacity **4035 mAh** against ~5500 mAh design,
**252 cycles**, macOS condition **"Service Recommended"** — roughly 73 %. Read from the real EC
via `SMCBatteryManager`; not a hackintosh misreport.

---

## 12. Rejected Approaches — Do Not Retry Without New Evidence

| Idea | Why rejected |
|---|---|
| **SMBIOS → MacBookPro15,1** | macOS **Tahoe does not support it**. Would break the boot. `MacBookPro16,1` is mandatory. |
| **CPU overclocking** | i7-8750H is **locked/non-K**. No multiplier headroom exists. |
| **GPU overclocking via PredatorSense** | The WMI interface has **no OC method** (all 23 enumerated). Windows drove it through NVAPI; the dGPU is dead anyway. |
| **Raising PL1/PL2 further** | **Revised 2026-09-02:** the firmware PL2 is actually **75 W** (MSR 0x610), not 90 W — the observed 75 W peak was PL2, not a thermal wall. Whether the driver's 90 W write lands is now an open question, see §6.3. PL1 must still stay at 45 W per Acer's table. |
| **Undervolting (MSR 0x150)** | Almost certainly blocked by the Plundervolt microcode mitigation (BIOS 1.13 updated ME firmware). Untested but expected locked. |
| **Turbo ratio limits (MSR 0x1AD)** | Typically read-only on non-K mobile parts. Untested. |
| **Trackpad interrupt mode** | Three hypotheses refuted on hardware; see §9.3. |
| **AppleALC layout 33 / 93** | Kills the internal microphone; see §8. |
| **Custom ALC289 layout from Windows driver** | Windows INFs contain no pin-config verbs — nothing to port. |
| **Replicating Waves MaxxAudio** | Windows APO, no macOS equivalent. |
| **BIOS update** | V1.13 is already installed (confirmed by `dmidecode`). Rewrites ACPI + EC firmware — the exact things this build reverse-engineers. No benefit; real risk. |
| **`igfxfw=2` (GuC firmware)** | Not documented as a performance feature; widely reported to cause hangs on Coffee Lake. |
| **Raising `framebuffer-stolenmem`** | Framebuffer allocation, not a performance knob. |
| **Thunderbolt support** | Hardware exists behind PCIe root port #17; TB3 on a Hackintosh is a large project with poor odds. |
| **Resurrecting the dead RTX GPU** | Proven impossible: `lspci` under Linux shows no NVIDIA device **and no CPU PEG root port**. PCI enumeration is a silicon-level handshake — no firmware image or flash changes it. Also irrelevant to macOS: NVIDIA web drivers ended at Pascal / High Sierra, so RTX 20-series has no macOS support and never will. |
| **Swapping the Wi-Fi card for Broadcom** | The 9560 is **CNVi**, integrated into the PCH — the M.2 slot is CNVio and typically has no PCIe lanes. A Broadcom PCIe card will physically fit and not work. |
| **`vo=gpu-next` in IINA** | IINA's bundled mpv is built without libplacebo — option does not exist. |
| **`rps-control` on the iGPU** | Applied, then reverted. GPU reached its 1.10 GHz ceiling and parked at idle, but package temps rose — CPU and iGPU share one 45 W budget and one die. No measured benefit. |
| **`SSDT-GPRW` (neuter GPE 0x6D)** | Applied, rebooted, **failed**. USB still woke the machine. Two reasons: `XDCI` (00:14.1) is a different device from `XHC` (00:14.0), and more fundamentally macOS arms USB remote wake through XHCI **PCI PME** in IOUSBHostFamily, not the ACPI `_PRW` GPE path. |
| **USB sleep-power properties** | `kUSBSleepPowerSupply`/`kUSBSleepPortCurrentLimit` etc. on `PciRoot(0x0)/Pci(0x14,0x0)`. Applied, **failed** — did not stop the drive dropping or the wakes. Reverted. |
| **Modded/unlocked Insyde BIOS** | Nothing worth having behind it: CFG Lock quirk already works, DVMT is not a perf lever, undervolting is Plundervolt-locked. 8th-gen Acer has Boot Guard and no flashback recovery — a failed flash is a dead mainboard. |
| **Spoofing a different iGPU `device-id`** | Already native and correct. Spoofing is for *compatibility*, never performance — it cannot add EUs or clock. |
| **"More VRAM" via `framebuffer-stolenmem` / BIOS DVMT** | Intel iGPUs allocate graphics memory dynamically from system RAM. `stolenmem` sizes display scanout buffers only and is **not** a performance knob. Raising it is still rejected. |
| **`framebuffer-unifiedmem` (reported VRAM)** | **Tested 2026-11-19: works.** Added `framebuffer-fbmem 00009000` + `framebuffer-unifiedmem 00000080` (2048 MB); 1792 MB was tested first, then 2048 MB. Both booted clean on 26.7.3. DVMT is **64 MB** (measured from Linux `dmesg`: `Reserving Intel graphics memory at [mem 0x75800000-0x797fffff]`), and the BIOS exposes a 2048 MB aperture option. **This changes only the number reported to apps, not GPU throughput** — bandwidth stays ~43 GB/s and Metal performance is unchanged. Keep `stolenmem` at 19 MB; do not raise it. |
| **EPP `0x00` (max-performance bias)** | **Tested twice on 2026-09-02. Verdict: no measurable effect — the earlier "−6.9 %" claim in this table was wrong and has been retracted.** Controlled comparison on the *correct* 4100 map: EPP `0x00` = **1359 / 5202**, EPP `0x80` = **1338 / 5236**. That is **0.7 % multi-core apart, inside run-to-run noise**, and single-core moved the *opposite* way. The original 5744 → 5345 slide was confounded: the 5345 run used the broken MacBookPro16,1 map (no 4100 key) *and* followed back-to-back benchmark runs with no thermal cooldown. Do not attribute it to EPP. **Keep EPP `0x80`** — not because it is faster, but because it is the known-good file and measured the best idle (~2.6 W). See §6.7 for the unexplained gap to the 5744 baseline. |
| **CPUFriendFriend target model `MacBookPro16,1`** | **Wrong — see §6.6.** The target model must match the CPU's *frequency range*, not the SMBIOS. MacBookPro16,1 ships 9th-gen chips (4.5/4.8/5.0 GHz), producing a `Frequencies` map with **no 4100 entry** for this 4.1 GHz i7-8750H. Use **`MacBookPro15,1`**, which covers 4100-5000. |

---

## 13. File Locations

```
ESP:  /Volumes/EFI/EFI/OC/
        config.plist
        ACPI/     SSDT-EC, -PLUG, -PNLF, -RTCAWAC, -SBUS-MCHC, -USBX, -XOSI  (the only 7)
        Kexts/    see §2.4
        Drivers/  HfsPlus.efi, OpenRuntime.efi

       PT515-51-macOS-Build.md          (this file, at /Volumes/EFI/EFI/)

macOS: /Library/Application Support/PredatorSense/state.json                 (persisted settings)
       ~/Library/ColorSync/Profiles/Triton500.icm                            (display profile)
       ~/Downloads/pt515-healthcheck.sh                                      (health-check script)
```

**Mounting the ESP:**

```
diskutil list | grep EFI
sudo diskutil mount /dev/diskXs1
```

**Editing one config key safely without a full rewrite:**

```
sudo /usr/libexec/PlistBuddy -c \
  "Set :NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args '<new value>'" \
  /Volumes/EFI/EFI/OC/config.plist
```

---

## 14. Version State (HISTORICAL, 2026-09-02 — current versions are in §0)

**All current — nothing outdated.** Loaded versions confirmed live via `kmutil showloaded`.

```
OpenCore  REL-107-2026-03-20  (1.0.7)
Lilu 1.7.2            WhateverGreen 1.7.0     VirtualSMC / SMC* 1.3.7
AppleALC 1.9.7        NVMeFix 1.1.3           RestrictEvents 1.1.6
CPUFriend 1.3.0       BlueToolFixup 2.7.2     IntelBluetoothFirmware 2.5.0
itlwm 2.3.0           VoodooI2C 2.9.1         VoodooPS2Controller 2.3.7
USBToolBox 1.2.0      AMFIPass 1.4.1          LucyRTL8125Ethernet 1.2.3
PredatorSenseEC 3.1.1 (this project)
```

Check OpenCore's actually-booted version with:

```
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version
```

---

## 15. Tools Used

| Tool | Use |
|---|---|
| `iasl` | compile/decompile ACPI (`iasl -d file.aml`) |
| [`pali/bmfdec`](https://github.com/pali/bmfdec) | decode the binary MOF in `WQAB` → `AcerGamingFunction` |
| Intel Power Gadget | all power/frequency verification |
| CPUFriendFriend | generate `CPUFriendDataProvider.kext` |
| Hackintool | kext collection / framebuffer inspection |
| BetterDisplay (trial) | colour-depth and mode inspection only |

---

## 16. Sleep — Instant Wake From USB (unresolved by design)

**Symptom:** with the **lid open**, the machine wakes within seconds of sleeping. With the **lid
closed** it sleeps correctly (clamshell mode masks more wake sources).

**Confirmed cause:** USB devices. Unplugging everything makes sleep work. Recorded wake reason is
always `HID Activity` or `User`, with `XDCI` armed:

```
Wake from Normal Sleep [CDNVA] : due to XDCI/HID Activity   17-81 secs
```

Read the log format correctly: everything **before** the `/` is the list of *armed* wake sources;
what follows is the *actual* cause. `XDCI` being present is not the same as `XDCI` being the cause.

Candidate devices seen holding USB kernel wake assertions:

```
id=507  0x4=USB       owner=Keychron Link      (wireless keyboard dongle)
id=510  0x4=USB       owner=RTL9201
id=502  0x100=MAGICWAKE  owner=en1             (cleared by pmset womp 0)
```

An external drive also produces "Disk not ejected properly" on wake — it drops off the bus during
sleep and its re-enumeration is itself a wake event.

**Two fixes were attempted and both failed** — see §12 (`SSDT-GPRW`, USB sleep-power properties).

**Accepted workaround: unplug USB devices, or close the lid, before sleeping.** Verified working.

**If someone wants to try again**, the untried step is narrowing to the single device: plug them
back one at a time, sleeping after each. Each culprit has a non-ACPI fix (Bluetooth instead of the
dongle; a powered hub for the drive). Do **not** re-attempt the ACPI route without new evidence.

---


### 16.1 Intermittent blank panel on restart — OPEN, low severity

**Symptom:** rarely, the internal display stays blank through a restart. The machine is fully
alive (it is booting normally behind the black screen).

**Workaround, confirmed working:** close the lid, let it sleep, reopen. The sleep/wake cycle
re-runs panel bring-up and the image returns.

**What that tells us:** this is an intermittent *race in initial panel bring-up*, not a hang, not
a framebuffer failure, and not the dead dGPU (which is absent from the PCI bus entirely and would
fail consistently, not rarely). The second bring-up attempt always succeeds.

**Already in place, so not the fix:** `enable-backlight-registers-fix` is set on the iGPU
(WhateverGreen's BLR).

**Action taken 2026-09-02:** EDID byte 20 reverted from the fabricated `0xB5` (10-bit) to the
panel's native `0xA5` (8-bit) — see §10.2.1 — on the theory that the connector was negotiating
against a descriptor contradicting the hardware. **Unproven as a fix.** The fault is too rare to
confirm quickly; the revert stands on its own merits either way.

**If it recurs**, the next suspect is panel power sequencing rather than the descriptor. Do not
re-add the 10-bit claim while investigating.

## 17a. Verification Snapshot — 2026-09-02 (HISTORICAL)

Produced by `pt515-healthcheck.sh` (kept in `~/Downloads`). All values read from the live system.

```
macOS            26.6.2 (25G83)          SMBIOS MacBookPro16,1
OpenCore         REL-107-2026-03-20      current
CPU              i7-8750H, 6P/12L        RAM 16 GB
Memory           ChannelA-DIMM0 8 GB + ChannelB-DIMM0 8 GB, DDR4-2667   DUAL CHANNEL
Storage          WDC PC SN720 512 GB, PCIe x4 @ 8.0 GT/s, TRIM Yes
GPU              UHD 630, device-id 0x3e9b, Metal 3, 2048 MB reported (unifiedmem patch)
Display          1920x1080 @ 144 Hz (120 Hz mode also present via EDID)
Audio            ALC289 (IOHDACodecVendorID 283902601), alc-layout-id 23, in+out 48000 Hz
Network          en0 itlwm (Wi-Fi), en1 RTL8125 (1000baseT)
Kexts loaded     Lilu 1.7.2, WhateverGreen 1.7.0, AppleALC 1.9.7, VirtualSMC 1.3.7,
                 CPUFriend 1.3.0, NVMeFix 1.1.3, RestrictEvents 1.1.6, itlwm 2.3.0,
                 VoodooI2C 2.9.1, VoodooPS2 2.3.7, USBToolBox 1.2.0, AMFIPass 1.4.1,
                 IntelBluetoothFirmware 2.5.0, LucyRTL8125 1.2.300,
                 PredatorSenseEC 3.1.1
Kernel errors    none driver-related (only CloudKit / AirPlay-AWDL / Spotlight noise)
```

`AirPlayDeviceSupportsAWDLSolo … kA11NotSupportedErr` in the log is **expected** — `itlwm` does
not implement AWDL, so AirPlay and AirDrop cannot work. Harmless.

---

## 18. Guidance For Whoever Continues This

1. **Test on hardware before believing a theory.** Every wrong turn in this project came from
   confident inference on partial evidence: fan ordinals, keyboard zone indices, the keyboard
   method, SMBIOS, the CPU idle floor, and three separate trackpad theories. Every correction
   came from measurement.
2. **Argument widths in §3.2 are load-bearing.** Silent failure is the failure mode.
3. **Change one thing per reboot.** Two changes in one boot makes attribution impossible.
4. **Back up `config.plist` before every edit**, and keep a USB mouse handy for anything touching
   the trackpad.
5. **Read §12 before proposing anything.** Most "obvious" improvements have already been tried
   and disproved here.
6. **ACPI changes on this machine have a 0-for-6 record.** Three trackpad theories, a `_CRS`
   override, `SSDT-GPRW`, and USB sleep-power injection — all reasoned from partial evidence, all
   refuted by hardware. Everything that *did* work came from measurement first. If you find
   yourself constructing a mechanism to explain a symptom, stop and measure instead.

---

## 6.9 PL1 hidden cap — FINAL, CLOSED 2026-10-02 (do not retry)

Linux (CachyOS live, `iomem=relaxed`) test with `Final/pl1-uncap-test.py`:

- MCHBAR = 0xFED10000. MMIO PL (MCHBAR+0x59A0) = MSR 0x610 = 45 W / 75 W, **neither locked**.
- Raised BOTH to 65 W under all-core load. Both held at 65 W, yet package power settled at **44.9 W @ 3.5 GHz, 63–66 °C**.
- `MSR 0x64F` (client perf-limit reasons — 0x690 is the wrong register on this CPU) at that moment: **ACTIVE = PL1** only.
- Ruled out: VR current limit (0x601 = 130 A, never active), PSys/PL3 (0x65C disabled), PROCHOT/thermal, thermald (not running).

**Conclusion:** the firmware/EC imposes a hidden 45 W PL1 through an out-of-band path (PECI/pcode) that sits below both OS-visible limits. Not reachable from software in any OS. Only a BIOS/EC firmware mod could change it — not recommended. Thermals have headroom; repaste helps noise only.

## 17b. Changes 2026-10-02

- PredatorSense review fixes: tolerant settings decode (old state.json no longer wiped), brightness restored before kb commands while dimmed, app slider re-seed (no 25 % lock-in when opened dimmed), Turbo restores prior fan/power state, PL2 cap no longer rolls Turbo back or greys the power picker, clamped CLI ints (no daemon crash on negatives), daemon ProcessType Standard. Old sources: `predatorsense/.bak-1002/`.
- Battery charge-limit (WMBE methods 20/21 exist in firmware MOF) was prototyped then removed at user request — available if ever wanted.
- **App install on Tahoe:** copying from the Multimedia drive drags `._` files into the bundle and breaks the signature ("not compatible"). Install with:
  `sudo ditto --norsrc --noextattr build/PredatorSense.app /Applications/PredatorSense.app && sudo xattr -cr /Applications/PredatorSense.app && sudo codesign --force --deep --sign - /Applications/PredatorSense.app`

## 19. Display — native EDID, name, 144/120/90 Hz (2026-10-06, VERIFIED)

Panel: BOE `NV156FHM-N4K`, EDID vendor/product `09e5`/`082a`, 8 bpc, RGB 4:4:4, gamma 2.2, sRGB-like primaries, native 1920x1080 @ 144 Hz.

Installed `AAPL00,override-no-connect` (128-byte EDID in `PciRoot(0x0)/Pci(0x2,0x0)`):

| Offset | Content |
|---|---|
| 54 | DTD 144 Hz (342.05 MHz, htotal 2080, vtotal 1142) |
| 72 | DTD **90.009 Hz** (same clock/htotal, vtotal 1827, flags 0x1a) |
| 90 | Name descriptor `Triton 500` (shows in Displays / colour profile) |
| 108 | DTD 120.034 Hz (vtotal 1370) |

Rules learned:
- macOS reads only the four base-block slots. A CTA extension block (256-byte EDID) with a 90 Hz DTD was ignored (tested, Option A).
- The panel's own 60 Hz DTD has sync flags 0x00 (decodes as analog composite); it was fixed to 0x1a. Slot 72 was then given to 90 Hz, so **60 Hz is no longer offered** (accepted: laptop is always plugged in). To get 60 Hz back, swap slot 72 or drop the name descriptor.
- Extra refresh rates are made by keeping the pixel clock and htotal and lengthening vertical blanking only.
- Verified: `CGDisplayCopyAllDisplayModes` lists 144/120/90; testufo.com reads 90 Hz / 90 fps; sleep/wake OK at 90 Hz.
- Config files and generator: `Hackintosh/display-90hz/` (`config.B-replace60.plist` is the installed one; `config.A-working.plist` on the EFI is the previous 144/120/60 fallback).
- Do NOT use: `Display-9e5-82a.kext`, `DisplayVendorID-9e5/DisplayProductID-82a`, `EDID-9e5-82a.bin` (fake `9c7c` ID, gamma 1.96, wrong primaries, name "Unknown Display"); ChatGPT-made `config.experimental-90-120hz.plist`, `EDID-native-old120-plus-90hz.bin`, `config.native-plus-old-120hz.plist`, `config.native-ids-triton-120hz.plist`.

### 19.1 Gradient banding — OPEN
Browser gradients are smooth; macOS UI gradients band. Cause is most likely 8-bit compositor output without dithering, not the EDID. `AAPL00,Dither` is set but has no confirmed effect. Next tests: sRGB IEC61966-2.1 colour profile (sRGB looks darker than the auto "Triton 500" profile; result on banding not yet reported); optional pipe-dithering toggle in PredatorSenseEC (untested idea).

### 19.2 Other pending
Left USB-A (SS04) sleep/wake and USB3 fallback to USB2 (see §16 and `usb-report-linux.txt`); Bluetooth after sleep; audio/kext-update notes still to be added to this doc.
