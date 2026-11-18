# Third-party components and notices

This repository redistributes **unmodified release binaries** of several open-source projects so
that the build is reproducible. They are not covered by this repository's MIT licence (see
[LICENSE](LICENSE)); each remains under its own licence, held by its authors.

The MIT licence applies to the original code and documentation here: the PredatorSense stack under
`predatorsense/`, the AppleALC layout modifications under `audio/`, the scripts under `tools/`, and the
documentation under `docs/`. Apple's macOS is not distributed in this repository.

If you are an author and want a component removed or re-attributed, open an issue.

## Bootloader

| Component | Upstream | Licence |
|---|---|---|
| OpenCorePkg (`OpenCore.efi`, `BOOTx64.efi`, `OpenRuntime.efi`, `HfsPlus.efi`, tools) | https://github.com/acidanthera/OpenCorePkg | BSD-3-Clause |

## Kexts in `efi/OC/Kexts/`

| Kext | Upstream |
|---|---|
| Lilu | https://github.com/acidanthera/Lilu |
| WhateverGreen | https://github.com/acidanthera/WhateverGreen |
| VirtualSMC, SMCProcessor, SMCBatteryManager, SMCSuperIO | https://github.com/acidanthera/VirtualSMC |
| AppleALC (modified build — see note below) | https://github.com/acidanthera/AppleALC |
| CPUFriend + CPUFriendDataProvider | https://github.com/acidanthera/CPUFriend |
| NVMeFix | https://github.com/acidanthera/NVMeFix |
| RestrictEvents | https://github.com/acidanthera/RestrictEvents |
| VoodooPS2Controller | https://github.com/acidanthera/VoodooPS2 |
| VoodooI2C, VoodooI2CHID, VoodooGPIO, VoodooInput | https://github.com/VoodooI2C/VoodooI2C |
| AirportItlwm, itlwm | https://github.com/OpenIntelWireless/itlwm |
| IntelBluetoothFirmware, IntelBTPatcher, IntelBluetoothInjector | https://github.com/OpenIntelWireless/IntelBluetoothFirmware |
| BlueToolFixup | https://github.com/acidanthera/BrcmPatchRAM |
| USBToolBox + UTBMap, NativeUSBMap | https://github.com/USBToolBox |
| AMFIPass | https://github.com/dhinakg/AMFIPass |
| LucyRTL8125Ethernet | https://github.com/Mieze/LucyRTL8125Ethernet |
| IOSkywalkFamily, IO80211FamilyLegacy | OpenCore Legacy Patcher / Dortania projects |
| PredatorSenseEC | **this repository** — see `predatorsense/` |

> **AppleALC** is the one binary here that is **not** stock: it is a local build from the upstream
> source with this machine's layout 23 modifications. The complete patch is in
> [`audio/applealc-layout23.patch`](audio/applealc-layout23.patch), and `audio/build.sh`
> reproduces it. It remains under AppleALC's BSD-3-Clause licence.

## What is deliberately **not** included

- **Apple software.** No macOS installer, no Apple frameworks, no IPSW-derived files, no
  `AppleHDA`/`AppleHDAController` binaries, no extracted kexts from macOS.
- **Root patches.** The OCLP-Mod Intel Wi-Fi patch is applied on the installed system, not shipped
  here. Install it from its own upstream.
- **SMBIOS identities.** The config ships placeholders. The serial, MLB, UUID and ROM in this
  repository are fake and belong to nobody.
- **Personal data.** No serials, hardware UUIDs, MAC addresses, account names or logs from the
  reference machine.

## Documentation and research

Product names, trademarks and brands (Acer, Predator, Intel, Realtek, BOE, Apple, macOS) belong to
their owners. This is an independent, unofficial project. It is not affiliated with Acer or Apple.

Panel measurements quoted in [`docs/DISPLAY.md`](docs/DISPLAY.md) are attributed to Notebookcheck's
review of the same panel model. The free ICC profile linked there is Notebookcheck's, not ours.
