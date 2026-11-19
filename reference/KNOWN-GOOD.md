# Known-good manifest — verified 2026-11-19

The exact state of the reference machine at publication. If you are debugging, compare against
this. If you make a verified change, update this file.

## System

| Item | Value |
|---|---|
| Model | Acer Predator Triton 500 **PT515-51** |
| BIOS | **V1.13** (do not update) |
| CPU | Intel Core i7-8750H, 6C/12T |
| iGPU | Intel UHD Graphics 630, `device-id 3E9B` |
| dGPU | NVIDIA RTX 2060/2080 Max-Q — **dead, absent from PCI** |
| RAM | 16 GB DDR4-2667 dual channel |
| Storage | WDC PC SN720 512 GB NVMe |
| Panel | BOE NV156FHM-N4K, 1920×1080, 144 Hz |
| Audio | Realtek ALC289 |
| Wi-Fi | Intel CNVi `[8086:a370]` |
| Bluetooth | Intel 9460/9560 `[8087:0aaa]` |
| Ethernet | Killer E3000 `[10ec:3000]` |
| Trackpad | Elantech ELAN0504 on `I2C1.TPD0` |
| macOS | **26.7.3 (25G342)** |
| OpenCore | **REL-108-2026-09-27** (1.0.8) |
| SMBIOS | `MacBookPro16,1` |

## Security / NVRAM

| Key | Value |
|---|---|
| `boot-args` | `-amfipassbeta alcid=23 -vi2c-force-polling -wegnoegpu -ibtcompatbeta revpatch=sbvmm -igfxnotelemetryload` |
| `csr-active-config` | `03080000` |
| `SecureBootModel` | `Disabled` |
| `Vault` | `Optional` |
| `DmgLoading` | `Signed` |
| Picker | Builtin, timeout 2, `HideAuxiliary = true` |
| `ScanPolicy` | `17763587` (`0x10F0D03`) |

## Kexts — enabled, in load order

| Kext | Version |
|---|---|
| Lilu | 1.7.3 |
| CPUFriend | 1.3.1 |
| CPUFriendDataProvider | 1.0.1 |
| VirtualSMC | 1.3.9 |
| RestrictEvents | 1.1.7 |
| WhateverGreen | 1.7.2 |
| AppleALC (custom layout 23) | 1.9.9 |
| LucyRTL8125Ethernet | 1.2.3 |
| NVMeFix | 1.1.4 |
| VoodooPS2Controller | 2.3.7 |
| └ VoodooPS2Keyboard | 2.3.7 |
| VoodooI2C | 2.9.1 |
| └ VoodooI2CServices | 2.9.1 |
| └ VoodooGPIO | 2.9.1 |
| └ VoodooInput | (bundled) |
| VoodooI2CHID | 1.0 |
| SMCBatteryManager | 1.3.9 |
| SMCProcessor | 1.3.9 |
| USBToolBox | (bundled) |
| UTBMap | 1.1 |
| IntelBluetoothFirmware | 2.5.1 |
| IntelBTPatcher | 2.5.1 |
| BlueToolFixup | 2.7.3 |
| IOSkywalkFamily | 1.0 |
| IO80211FamilyLegacy | 12.0 |
| AMFIPass | 1.4.1 |
| AirportItlwm | 2.3.0 |
| PredatorSenseEC | 3.7.0 |

## Kexts — present but **disabled**

| Kext | Reason |
|---|---|
| `itlwm` | non-Airport variant; AirportItlwm is the active one |
| `SMCSuperIO` | not needed; avoid extra sensor probing |
| `VoodooI2CSynaptics` | trackpad is Elantech |
| `VoodooI2CELAN` | trackpad is driven via VoodooI2CHID |
| `IntelBluetoothInjector` | conflicts with the firmware loader on Tahoe |
| `VoodooPS2Controller/PlugIns/VoodooPS2Mouse` | trackpad is I²C; PS/2 mouse would conflict |
| `VoodooPS2Controller/PlugIns/VoodooInput` | VoodooI2C supplies VoodooInput |
| `IO80211FamilyLegacy/PlugIns/AirPortBrcmNIC` | no Broadcom card |

`NativeUSBMap.kext` is in the folder but **not referenced** in `Kernel → Add` — `UTBMap` is the
active USB map.

## ACPI — enabled

`SSDT-EC`, `SSDT-PLUG`, `SSDT-PNLF`, `SSDT-RTCAWAC`, `SSDT-SBUS-MCHC`, `SSDT-USBX`, `SSDT-XOSI`.

`SSDT-TPD0.aml` and `SSDT-GPIO.aml` exist in history and stay **disabled** (polling is correct).

## Drivers

`HfsPlus.efi`, `OpenRuntime.efi`.

## DeviceProperties — `PciRoot(0x0)/Pci(0x2,0x0)`

`AAPL,ig-platform-id`, `device-id 3E9B`, `framebuffer-patch-enable`,
`framebuffer-stolenmem` (19 MB), `framebuffer-fbmem` (9 MB),
`framebuffer-unifiedmem` (2048 MB — reported VRAM only, tested working 2026-11-19),
`enable-backlight-registers-fix`, `AAPL00,Dither`, and the custom
`AAPL00,override-no-connect` EDID (144/90/120 Hz, name `Triton 500`).

## Power and battery

| Item | Value (2026-11-18) |
|---|---|
| PL1 | 45 W (firmware/EC enforced) |
| PL2 | up to 90 W burst, 28 s |
| Battery full charge | 4127 mAh (design ~5400) |
| Cycle count | 235 |
| Condition | Service Recommended (~76 %) |

## Verdict

**Status: working daily driver.** Every enabled item above was verified live on 2026-11-18.
Known open items: Bluetooth controller state (the radio can fail to enumerate; a cold boot with a
20 s power-button hold recovers it), instant wake from USB with the lid open, UI gradient
banding.
